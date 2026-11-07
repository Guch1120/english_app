#!/usr/bin/env python3
"""Create the two explicit WDA App IDs and development profiles.

This script is intended for the protected, main-only setup-wda workflow. It
uses the active English Trainer development profile as its certificate/device
anchor and never logs API credentials, device UDIDs, or profile contents.
"""

from __future__ import annotations

import base64
import datetime as dt
import json
import os
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API_ROOT = "https://api.appstoreconnect.apple.com"
APP_BUNDLE_ID = "jp.guch1120.EnglishTrainer"
REFERENCE_PROFILE_NAME = "English learning app"
WDA_TARGETS = (
    ("jp.guch1120.WebDriverAgentRunner", "English Trainer WDA Base Development"),
    ("jp.guch1120.WebDriverAgentRunner.xctrunner", "English Trainer WDA Runner Development"),
)


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _der_length(data: bytes, offset: int) -> tuple[int, int]:
    first = data[offset]
    offset += 1
    if first < 0x80:
        return first, offset
    count = first & 0x7F
    if count == 0 or count > 4 or offset + count > len(data):
        raise ValueError("Invalid ECDSA signature length")
    return int.from_bytes(data[offset:offset + count], "big"), offset + count


def der_ecdsa_to_raw(signature: bytes, coordinate_size: int = 32) -> bytes:
    """Convert OpenSSL's ASN.1 ECDSA signature to JWT's fixed-width r||s."""
    if len(signature) < 8 or signature[0] != 0x30:
        raise ValueError("Invalid ECDSA signature")
    sequence_length, cursor = _der_length(signature, 1)
    if cursor + sequence_length != len(signature):
        raise ValueError("Invalid ECDSA signature sequence")
    values = []
    for _ in range(2):
        if cursor >= len(signature) or signature[cursor] != 0x02:
            raise ValueError("Invalid ECDSA integer")
        length, cursor = _der_length(signature, cursor + 1)
        integer = signature[cursor:cursor + length]
        cursor += length
        if not integer or integer[0] & 0x80:
            raise ValueError("Invalid ECDSA integer encoding")
        integer = integer.lstrip(b"\x00")
        if len(integer) > coordinate_size:
            raise ValueError("ECDSA coordinate exceeds curve size")
        values.append(integer.rjust(coordinate_size, b"\x00"))
    if cursor != len(signature):
        raise ValueError("Unexpected ECDSA signature data")
    return b"".join(values)


def make_token(private_key_pem: str, key_id: str, issuer_id: str,
               now: int | None = None) -> str:
    issued = int(time.time()) if now is None else int(now)
    header = b64url(json.dumps(
        {"alg": "ES256", "kid": key_id, "typ": "JWT"},
        separators=(",", ":"),
    ).encode())
    claims = b64url(json.dumps(
        {"iss": issuer_id, "iat": issued, "exp": issued + 900,
         "aud": "appstoreconnect-v1"},
        separators=(",", ":"),
    ).encode())
    signing_input = f"{header}.{claims}".encode("ascii")
    with tempfile.TemporaryDirectory(prefix="wda-api-key-") as directory:
        key_path = Path(directory) / "AuthKey.p8"
        input_path = Path(directory) / "claims"
        signature_path = Path(directory) / "signature.der"
        key_path.write_text(private_key_pem, encoding="utf-8")
        key_path.chmod(0o600)
        input_path.write_bytes(signing_input)
        subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(key_path),
             "-out", str(signature_path), str(input_path)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
        signature = der_ecdsa_to_raw(signature_path.read_bytes())
    return f"{header}.{claims}.{b64url(signature)}"


class AppleAPIError(RuntimeError):
    pass


class AppleConnectAPI:
    def __init__(self, token: str, opener=urllib.request.urlopen):
        self.token = token
        self.opener = opener

    def request(self, method: str, path_or_url: str,
                body: dict | None = None) -> dict:
        url = path_or_url if path_or_url.startswith("https://") else API_ROOT + path_or_url
        if not url.startswith(API_ROOT + "/"):
            raise AppleAPIError("Apple API returned an unexpected pagination URL")
        payload = None if body is None else json.dumps(body).encode("utf-8")
        request = urllib.request.Request(
            url, data=payload, method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
        )
        try:
            with self.opener(request, timeout=45) as response:
                data = response.read()
        except urllib.error.HTTPError as error:
            try:
                response = json.loads(error.read().decode("utf-8"))
                item = (response.get("errors") or [{}])[0]
                code = item.get("code", "unknown")
                title = item.get("title", "Apple API request rejected")
            except (UnicodeDecodeError, json.JSONDecodeError, AttributeError):
                code, title = "unknown", "Apple API request rejected"
            raise AppleAPIError(
                f"{method} {urllib.parse.urlsplit(url).path} failed "
                f"(HTTP {error.code}, {code}: {title})"
            ) from None
        except (OSError, urllib.error.URLError) as error:
            raise AppleAPIError(
                f"{method} {urllib.parse.urlsplit(url).path} failed: {type(error).__name__}"
            ) from None
        if not data:
            return {}
        try:
            return json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise AppleAPIError("Apple API returned invalid JSON") from None

    def get_all(self, path: str, query: dict[str, str] | None = None) -> list[dict]:
        url = API_ROOT + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        results = []
        while url:
            page = self.request("GET", url)
            results.extend(page.get("data", []))
            url = (page.get("links") or {}).get("next")
        return results


def _relationship_ids(api: AppleConnectAPI, resource: dict, relation: str) -> list[str]:
    relationship = (resource.get("relationships") or {}).get(relation) or {}
    data = relationship.get("data")
    if data is None:
        resource_id = resource.get("id")
        if not resource_id:
            raise AppleAPIError(f"Profile is missing its {relation} relationship")
        response = api.request("GET", f"/v1/profiles/{resource_id}/{relation}")
        data = response.get("data")
    if isinstance(data, dict):
        data = [data]
    ids = [item.get("id") for item in (data or []) if item.get("id")]
    if not ids:
        raise AppleAPIError(f"Profile is missing its {relation} relationship")
    return ids


def _bundle_identifier(api: AppleConnectAPI, profile: dict) -> str:
    bundle_id, = _relationship_ids(api, profile, "bundleId")
    resource = api.request("GET", f"/v1/bundleIds/{bundle_id}").get("data") or {}
    return (resource.get("attributes") or {}).get("identifier", "")


def reference_signing_resources(api: AppleConnectAPI) -> tuple[str, str]:
    profiles = api.get_all("/v1/profiles", {
        "filter[name]": REFERENCE_PROFILE_NAME,
        "filter[profileType]": "IOS_APP_DEVELOPMENT",
        "limit": "200",
    })
    matches = [profile for profile in profiles
               if _bundle_identifier(api, profile) == APP_BUNDLE_ID]
    active = [profile for profile in matches
              if (profile.get("attributes") or {}).get("profileState") == "ACTIVE"
              and _not_expired((profile.get("attributes") or {}).get("expirationDate"))]
    if len(active) != 1:
        raise AppleAPIError(
            f"Expected one active '{REFERENCE_PROFILE_NAME}' development profile "
            f"for {APP_BUNDLE_ID}; found {len(active)}"
        )
    profile = active[0]
    certificates = _relationship_ids(api, profile, "certificates")
    devices = _relationship_ids(api, profile, "devices")
    if len(certificates) != 1 or len(devices) != 1:
        raise AppleAPIError(
            "The English Trainer profile must use exactly one development certificate "
            "and one registered device"
        )
    return certificates[0], devices[0]


def _not_expired(value: str | None) -> bool:
    if not value:
        return False
    try:
        expiration = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return expiration > dt.datetime.now(dt.timezone.utc)


def get_or_create_bundle_id(api: AppleConnectAPI, identifier: str,
                            name: str) -> tuple[dict, bool]:
    existing = api.get_all("/v1/bundleIds", {
        "filter[identifier]": identifier,
        "limit": "200",
    })
    if len(existing) > 1:
        raise AppleAPIError(f"Multiple Apple IDs are registered for {identifier}")
    if existing:
        resource = existing[0]
        attrs = resource.get("attributes") or {}
        if attrs.get("platform") != "IOS":
            raise AppleAPIError(f"Apple ID {identifier} is not registered for iOS")
        return resource, False
    created = api.request("POST", "/v1/bundleIds", {
        "data": {
            "type": "bundleIds",
            "attributes": {"name": name, "identifier": identifier, "platform": "IOS"},
        }
    }).get("data")
    if not created or not created.get("id"):
        raise AppleAPIError(f"Apple did not create the App ID {identifier}")
    return created, True


def get_or_create_profile(api: AppleConnectAPI, bundle: dict, name: str,
                          certificate_id: str, device_id: str) -> tuple[dict, bool]:
    profiles = api.get_all("/v1/profiles", {
        "filter[name]": name,
        "filter[profileType]": "IOS_APP_DEVELOPMENT",
        "limit": "200",
    })
    for profile in profiles:
        attrs = profile.get("attributes") or {}
        if attrs.get("profileState") != "ACTIVE" or not _not_expired(attrs.get("expirationDate")):
            raise AppleAPIError(
                f"A profile named '{name}' exists but is not active; refusing to replace it"
            )
        bundle_ids = _relationship_ids(api, profile, "bundleId")
        certificates = _relationship_ids(api, profile, "certificates")
        devices = _relationship_ids(api, profile, "devices")
        if (bundle_ids == [bundle["id"]] and certificates == [certificate_id]
                and devices == [device_id]):
            return profile, False
        raise AppleAPIError(
            f"A profile named '{name}' exists with different signing resources; "
            "refusing to replace it"
        )

    created = api.request("POST", "/v1/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_DEVELOPMENT"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
                "devices": {"data": [{"type": "devices", "id": device_id}]},
            },
        }
    }).get("data")
    if not created or not created.get("id"):
        raise AppleAPIError(f"Apple did not create the development profile '{name}'")
    return created, True


def _write_profile(api: AppleConnectAPI, profile: dict, path: Path) -> None:
    content = (profile.get("attributes") or {}).get("profileContent")
    if not content:
        resource_id = profile.get("id")
        if not resource_id:
            raise AppleAPIError("Apple returned a profile without downloadable content")
        profile = api.request("GET", f"/v1/profiles/{resource_id}").get("data") or {}
        content = (profile.get("attributes") or {}).get("profileContent")
    if not content:
        raise AppleAPIError("Apple returned a profile without downloadable content")
    try:
        decoded = base64.b64decode(content, validate=True)
    except (ValueError, base64.binascii.Error):
        raise AppleAPIError("Apple returned invalid provisioning profile content") from None
    path.write_bytes(decoded)
    path.chmod(0o600)


def run() -> None:
    private_key = os.environ["APPSTORE_API_PRIVATE_KEY"]
    key_id = os.environ["APPSTORE_API_KEY_ID"]
    issuer_id = os.environ["APPSTORE_ISSUER_ID"]
    output_dir = Path(os.environ.get("WDA_PROFILE_OUTPUT", tempfile.mkdtemp(prefix="wda-profiles-")))
    output_dir.mkdir(parents=True, exist_ok=True)
    output_dir.chmod(0o700)
    api = AppleConnectAPI(make_token(private_key, key_id, issuer_id))

    # Resolve the exact certificate and device already used by English Trainer.
    certificate_id, device_id = reference_signing_resources(api)
    print("Using the existing English Trainer development certificate and device.")

    for identifier, profile_name in WDA_TARGETS:
        bundle, bundle_created = get_or_create_bundle_id(
            api, identifier, "English Trainer WebDriverAgent " + identifier.rsplit(".", 1)[-1]
        )
        profile, profile_created = get_or_create_profile(
            api, bundle, profile_name, certificate_id, device_id
        )
        file_name = "wda-runner.mobileprovision" if identifier.endswith(".xctrunner") else "wda-base.mobileprovision"
        _write_profile(api, profile, output_dir / file_name)
        print(
            f"{identifier}: App ID {'created' if bundle_created else 'already present'}; "
            f"development profile {'created' if profile_created else 'reused'}"
        )
    print("WDA provisioning profiles are ready for the protected macOS build job.")


if __name__ == "__main__":
    try:
        run()
    except KeyError as error:
        raise SystemExit(f"Missing required environment setting: {error.args[0]}") from None
    except AppleAPIError as error:
        raise SystemExit(str(error)) from None
