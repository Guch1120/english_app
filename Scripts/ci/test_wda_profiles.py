import base64
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from apple.wda_profiles import (  # noqa: E402
    AppleAPIError,
    WDA_TARGETS,
    der_ecdsa_to_raw,
    get_or_create_bundle_id,
    get_or_create_profile,
    make_token,
)
from apple.crypt_profile import decrypt_bytes, encrypt_bytes  # noqa: E402


def _der_integer(value):
    value = value.lstrip(b"\x00") or b"\x00"
    if value[0] & 0x80:
        value = b"\x00" + value
    return b"\x02" + bytes([len(value)]) + value


def _raw_to_der(signature):
    sequence = _der_integer(signature[:32]) + _der_integer(signature[32:])
    return b"\x30" + bytes([len(sequence)]) + sequence


class WDAProfileTests(unittest.TestCase):
    def test_es256_token_is_valid_and_has_short_lived_claims(self):
        with tempfile.TemporaryDirectory() as directory:
            key = Path(directory, "key.pem")
            public = Path(directory, "public.pem")
            subprocess.run([
                "openssl", "genpkey", "-algorithm", "EC", "-pkeyopt",
                "ec_paramgen_curve:P-256", "-out", str(key),
            ], check=True, capture_output=True)
            subprocess.run([
                "openssl", "pkey", "-in", str(key), "-pubout", "-out", str(public),
            ], check=True, capture_output=True)
            token = make_token(key.read_text(), "KEYID", "ISSUER", now=1_800_000_000)
            header, claims, signature = token.split(".")
            header_json = json.loads(base64.urlsafe_b64decode(header + "=="))
            claims_json = json.loads(base64.urlsafe_b64decode(claims + "=="))
            raw_signature = base64.urlsafe_b64decode(signature + "==")
            self.assertEqual(header_json["alg"], "ES256")
            self.assertEqual(header_json["kid"], "KEYID")
            self.assertEqual(claims_json["iss"], "ISSUER")
            self.assertEqual(claims_json["aud"], "appstoreconnect-v1")
            self.assertEqual(claims_json["exp"] - claims_json["iat"], 900)
            self.assertEqual(len(raw_signature), 64)
            signing_input = Path(directory, "claims")
            signing_input.write_text(f"{header}.{claims}")
            signature_file = Path(directory, "signature.der")
            signature_file.write_bytes(_raw_to_der(raw_signature))
            verification = subprocess.run([
                "openssl", "dgst", "-sha256", "-verify", str(public), "-signature",
                str(signature_file), str(signing_input),
            ], capture_output=True, text=True)
            self.assertEqual(verification.returncode, 0, verification.stderr)

    def test_der_signature_conversion_rejects_malformed_input(self):
        self.assertEqual(len(der_ecdsa_to_raw(b"\x30\x06\x02\x01\x01\x02\x01\x02")), 64)
        with self.assertRaises(ValueError):
            der_ecdsa_to_raw(b"invalid")

    def test_existing_app_id_is_reused_without_mutation(self):
        existing = {"id": "bundle-1", "attributes": {"platform": "IOS"}}
        api = Mock()
        api.get_all.return_value = [existing]
        resource, created = get_or_create_bundle_id(api, WDA_TARGETS[0][0], "WDA")
        self.assertIs(resource, existing)
        self.assertFalse(created)
        api.request.assert_not_called()

    def test_new_app_id_uses_explicit_ios_identifier(self):
        created = {"id": "bundle-2", "attributes": {"platform": "IOS"}}
        api = Mock()
        api.get_all.return_value = []
        api.request.return_value = {"data": created}
        resource, was_created = get_or_create_bundle_id(api, WDA_TARGETS[1][0], "WDA runner")
        self.assertTrue(was_created)
        self.assertIs(resource, created)
        request_body = api.request.call_args.args[2]
        attrs = request_body["data"]["attributes"]
        self.assertEqual(attrs["identifier"], WDA_TARGETS[1][0])
        self.assertEqual(attrs["platform"], "IOS")

    def test_profile_creation_is_scoped_to_existing_certificate_and_device(self):
        api = Mock()
        api.get_all.return_value = []
        api.request.return_value = {"data": {"id": "profile-1"}}
        bundle = {"id": "bundle-3"}
        profile, was_created = get_or_create_profile(api, bundle, "WDA profile", "cert-1", "device-1")
        self.assertTrue(was_created)
        self.assertEqual(profile["id"], "profile-1")
        body = api.request.call_args.args[2]["data"]
        self.assertEqual(body["relationships"]["bundleId"]["data"]["id"], "bundle-3")
        self.assertEqual(body["relationships"]["certificates"]["data"][0]["id"], "cert-1")
        self.assertEqual(body["relationships"]["devices"]["data"][0]["id"], "device-1")

    def test_profile_name_collision_is_never_replaced(self):
        api = Mock()
        api.get_all.return_value = [{"id": "old-profile", "attributes": {
            "profileState": "INVALID", "expirationDate": "2099-01-01T00:00:00Z",
        }}]
        with self.assertRaises(AppleAPIError):
            get_or_create_profile(api, {"id": "bundle"}, "WDA profile", "cert", "device")
        api.request.assert_not_called()

    def test_profile_artifact_encryption_round_trips_and_authenticates(self):
        profile = b"a fake provisioning profile that must not be public"
        key = b"-----BEGIN PRIVATE KEY-----\nexample test key\n-----END PRIVATE KEY-----\n"
        encrypted = encrypt_bytes(profile, key)
        self.assertNotIn(profile, encrypted)
        self.assertEqual(decrypt_bytes(encrypted, key), profile)
        tampered = encrypted[:-1] + bytes([encrypted[-1] ^ 1])
        with self.assertRaisesRegex(ValueError, "failed authentication"):
            decrypt_bytes(tampered, key)


if __name__ == "__main__":
    unittest.main()
