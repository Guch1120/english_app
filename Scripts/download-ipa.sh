#!/usr/bin/env bash
# Password and plaintext IPA remain outside the repository; no values are printed.
set -euo pipefail
cd "$(dirname "$0")/.."
run_id=${1:?Usage: bash Scripts/download-ipa.sh RUN_ID PRIVATE_SIGNING_DIRECTORY}
private_dir=$(realpath -- "${2:?Specify the private directory containing dev-ipa-password.txt}")
[[ "$run_id" =~ ^[0-9]+$ ]] || { echo 'Run ID must be numeric.' >&2; exit 2; }
repo_dir=$(pwd -P)
case "$private_dir/" in "$repo_dir/"*) echo 'Choose a private directory outside the repository.' >&2; exit 2 ;; esac
test -f "$private_dir/dev-ipa-password.txt"
umask 077
out="$private_dir/builds/$run_id"
mkdir -p "$out"
chmod 700 "$out"
if [ ! -f "$out/EnglishTrainer.ipa.enc" ]; then
  gh run download "$run_id" --name EnglishTrainer-device-encrypted --dir "$out"
fi
if ! docker image inspect english-trainer-dev >/dev/null 2>&1; then docker build -t english-trainer-dev .; fi
docker run --rm --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$out,dst=/artifact" \
  --mount "type=bind,src=$private_dir/dev-ipa-password.txt,dst=/private/password.txt,readonly" \
  english-trainer-dev bash -c '
set -euo pipefail
umask 077
pending=$(mktemp /artifact/decrypted.XXXXXX)
trap '\''rm -f "$pending"'\'' EXIT
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in /artifact/EnglishTrainer.ipa.enc \
  -out "$pending" -pass file:/private/password.txt
unzip -t "$pending" >/dev/null
mv "$pending" /artifact/EnglishTrainer.ipa
chmod 600 /artifact/EnglishTrainer.ipa /artifact/EnglishTrainer.ipa.enc
'
printf 'IPA: %s/EnglishTrainer.ipa\n' "$out"
