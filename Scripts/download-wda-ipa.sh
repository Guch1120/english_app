#!/usr/bin/env bash
# Download and decrypt a short-lived WDA runner artifact without exposing it in the repository.
set -euo pipefail
cd "$(dirname "$0")/.."
run_id=${1:?Usage: bash Scripts/download-wda-ipa.sh RUN_ID PRIVATE_SIGNING_DIRECTORY}
private_dir=$(realpath -- "${2:?Specify the private directory containing dev-ipa-password.txt}")
[[ "$run_id" =~ ^[0-9]+$ ]] || { echo 'Run ID must be numeric.' >&2; exit 2; }
repo_dir=$(pwd -P)
case "$private_dir/" in "$repo_dir/"*) echo 'Choose a private directory outside the repository.' >&2; exit 2 ;; esac
test -f "$private_dir/dev-ipa-password.txt"
umask 077
out="$private_dir/builds/wda-$run_id"
mkdir -p "$out"
chmod 700 "$out"
if [ ! -f "$out/wda-runner.ipa.enc" ]; then
  gh run download "$run_id" --repo Guch1120/english_app \
    --name "wda-runner-encrypted-$run_id" --dir "$out"
fi
if ! docker image inspect english-trainer-dev >/dev/null 2>&1; then
  docker build -t english-trainer-dev .
fi
docker run --rm --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$out,dst=/artifact" \
  --mount "type=bind,src=$private_dir/dev-ipa-password.txt,dst=/private/password.txt,readonly" \
  english-trainer-dev bash -c '
set -euo pipefail
umask 077
pending=$(mktemp /artifact/decrypted.XXXXXX)
trap '\''rm -f "$pending"'\'' EXIT
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -in /artifact/wda-runner.ipa.enc -out "$pending" \
  -pass file:/private/password.txt
unzip -t "$pending" >/dev/null
unzip -Z1 "$pending" | grep -Fxq Payload/WebDriverAgentRunner-Runner.app/Info.plist
mv "$pending" /artifact/wda-runner.ipa
chmod 600 /artifact/wda-runner.ipa /artifact/wda-runner.ipa.enc
'
printf 'Encrypted WDA package downloaded and validated in %s\n' "$out"
