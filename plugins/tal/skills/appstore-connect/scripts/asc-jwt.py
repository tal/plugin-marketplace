#!/usr/bin/env python3
"""Mint an App Store Connect API JWT with an integer `exp`.

`xcrun altool --generate-jwt` emits a fractional `exp` (e.g. 1752252380.805223),
which the ASC REST API rejects with 401 NOT_AUTHORIZED even though altool's own
upload path accepts the same key. This signs the token itself: ES256 via the
`openssl` CLI, Python stdlib only.

Usage: asc-jwt.py --key-id <KEY_ID> [--issuer <ISSUER_ID>] [--key-dir <dir>] [--ttl <seconds>]

  --issuer   Default: the `AuthKey_<KEY_ID>.issuer-id` sidecar in the key dir.
  --key-dir  Default: $API_PRIVATE_KEYS_DIR, else ~/.config/appstoreconnect/private_keys.
  --ttl      Lifetime in seconds, max 1200 (Apple's 20-minute cap). Default 1200.

Prints the token on stdout. Exit 1 on a missing key/issuer or a signing failure.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import time


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_to_raw(der):
    # openssl emits an ASN.1 DER ECDSA signature: SEQUENCE { INTEGER r, INTEGER s }.
    # JWS ES256 wants r || s, each left-padded to 32 bytes.
    def read_len(buf, i):
        n = buf[i]
        if n < 0x80:
            return n, i + 1
        count = n & 0x7F
        return int.from_bytes(buf[i + 1:i + 1 + count], "big"), i + 1 + count

    if der[0] != 0x30:
        raise ValueError("signature is not a DER SEQUENCE")
    _, i = read_len(der, 1)
    parts = []
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError("signature component is not a DER INTEGER")
        length, i = read_len(der, i + 1)
        value = der[i:i + length].lstrip(b"\x00")
        if len(value) > 32:
            raise ValueError("signature component longer than 32 bytes")
        parts.append(value.rjust(32, b"\x00"))
        i += length
    return parts[0] + parts[1]


def main():
    parser = argparse.ArgumentParser(description="Mint an ASC API JWT with an integer exp.")
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer")
    parser.add_argument("--key-dir")
    parser.add_argument("--ttl", type=int, default=1200)
    args = parser.parse_args()

    key_dir = os.path.expanduser(
        args.key_dir
        or os.environ.get("API_PRIVATE_KEYS_DIR")
        or "~/.config/appstoreconnect/private_keys"
    )
    key_path = os.path.join(key_dir, "AuthKey_%s.p8" % args.key_id)
    if not os.path.isfile(key_path):
        sys.exit("asc-jwt: no key at %s" % key_path)

    issuer = args.issuer
    if not issuer:
        sidecar = os.path.join(key_dir, "AuthKey_%s.issuer-id" % args.key_id)
        if not os.path.isfile(sidecar):
            sys.exit("asc-jwt: pass --issuer, or create %s" % sidecar)
        with open(sidecar) as f:
            issuer = f.read().strip()

    if not 0 < args.ttl <= 1200:
        sys.exit("asc-jwt: --ttl must be 1..1200 seconds")

    now = int(time.time())
    header = {"alg": "ES256", "kid": args.key_id, "typ": "JWT"}
    payload = {"iss": issuer, "iat": now, "exp": now + args.ttl, "aud": "appstoreconnect-v1"}
    signing_input = (
        b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64url(json.dumps(payload, separators=(",", ":")).encode())
    )

    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(),
        capture_output=True,
    )
    if result.returncode != 0:
        sys.exit("asc-jwt: openssl signing failed: %s" % result.stderr.decode().strip())

    try:
        signature = der_to_raw(result.stdout)
    except (ValueError, IndexError) as exc:
        sys.exit("asc-jwt: could not parse openssl signature: %s" % exc)

    print(signing_input + "." + b64url(signature))


if __name__ == "__main__":
    main()
