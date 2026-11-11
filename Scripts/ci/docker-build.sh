#!/usr/bin/env bash
# Build a local tool image. Hosted runners have intermittently failed to resolve the Ubuntu
# package mirrors during `docker build`. If the normal build fails, retry once with mirror
# addresses looked up over DNS-over-HTTPS. apt still verifies repository signatures, so the
# lookup path does not decide what gets installed.
set -euo pipefail
if docker build "$@"; then exit 0; fi
echo 'docker build failed; retrying with package mirror addresses resolved over HTTPS.' >&2
hosts=()
for name in archive.ubuntu.com security.ubuntu.com; do
  address=$(curl -fsS -m 20 -H 'accept: application/dns-json' \
    "https://1.1.1.1/dns-query?name=$name&type=A" |
    python3 -c 'import json, sys
print(next(a["data"] for a in json.load(sys.stdin).get("Answer", []) if a.get("type") == 1))')
  [[ "$address" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "No usable address for $name." >&2; exit 1; }
  hosts+=(--add-host "$name:$address")
done
docker build "${hosts[@]}" "$@"
