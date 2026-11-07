#!/usr/bin/env python3
"""Encrypt temporary WDA provisioning artifacts before public GitHub storage."""

import argparse
import hashlib
import hmac
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

MAGIC = b"ET-WDA-PROFILE\x01"
SALT_SIZE = 16
IV_SIZE = 16
TAG_SIZE = 32
KDF_ROUNDS = 600_000


def _derive(passphrase: bytes, salt: bytes) -> tuple[bytes, bytes]:
    material = hashlib.pbkdf2_hmac("sha256", passphrase, salt, KDF_ROUNDS, dklen=64)
    return material[:32], material[32:]


def _cipher(data: bytes, key: bytes, iv: bytes, *, decrypt: bool) -> bytes:
    with tempfile.TemporaryDirectory(prefix="wda-profile-crypto-") as directory:
        source = Path(directory) / "source.bin"
        destination = Path(directory) / "result.bin"
        source.write_bytes(data)
        mode = "-d" if decrypt else "-e"
        subprocess.run(
            ["openssl", "enc", mode, "-aes-256-cbc", "-nosalt",
             "-K", key.hex(), "-iv", iv.hex(), "-in", str(source),
             "-out", str(destination)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
        return destination.read_bytes()


def encrypt_bytes(plain: bytes, passphrase: bytes) -> bytes:
    salt = secrets.token_bytes(SALT_SIZE)
    iv = secrets.token_bytes(IV_SIZE)
    encryption_key, authentication_key = _derive(passphrase, salt)
    ciphertext = _cipher(plain, encryption_key, iv, decrypt=False)
    authenticated = MAGIC + salt + iv + ciphertext
    tag = hmac.new(authentication_key, authenticated, hashlib.sha256).digest()
    return authenticated[:len(MAGIC) + SALT_SIZE + IV_SIZE] + tag + ciphertext


def decrypt_bytes(encrypted: bytes, passphrase: bytes) -> bytes:
    header_length = len(MAGIC) + SALT_SIZE + IV_SIZE + TAG_SIZE
    if len(encrypted) <= header_length or not encrypted.startswith(MAGIC):
        raise ValueError("Not a supported encrypted WDA profile")
    cursor = len(MAGIC)
    salt = encrypted[cursor:cursor + SALT_SIZE]
    cursor += SALT_SIZE
    iv = encrypted[cursor:cursor + IV_SIZE]
    cursor += IV_SIZE
    tag = encrypted[cursor:cursor + TAG_SIZE]
    cursor += TAG_SIZE
    ciphertext = encrypted[cursor:]
    encryption_key, authentication_key = _derive(passphrase, salt)
    authenticated = MAGIC + salt + iv + ciphertext
    expected = hmac.new(authentication_key, authenticated, hashlib.sha256).digest()
    if not hmac.compare_digest(tag, expected):
        raise ValueError("Encrypted WDA profile failed authentication")
    return _cipher(ciphertext, encryption_key, iv, decrypt=True)


def _load_key(args) -> bytes:
    if args.key_env:
        value = os.environ.get(args.key_env)
        if value is None:
            raise ValueError(f"Missing required environment setting: {args.key_env}")
        return value.encode("utf-8")
    if args.key_file:
        return Path(args.key_file).read_bytes()
    raise ValueError("Provide --key-env or --key-file")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("encrypt", "decrypt"))
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--key-env")
    parser.add_argument("--key-file")
    args = parser.parse_args()
    key = _load_key(args)
    source = args.source.read_bytes()
    result = encrypt_bytes(source, key) if args.mode == "encrypt" else decrypt_bytes(source, key)
    args.destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    args.destination.write_bytes(result)
    args.destination.chmod(0o600)


if __name__ == "__main__":
    main()
