#!/usr/bin/env bash
# iOS 17.4+ screenshot via an in-process userspace tunnel: no host root/network changes.
set -euo pipefail
cd "$(dirname "$0")/.."
private_dir=$(realpath -- "${1:?Usage: bash Scripts/capture-iphone.sh PRIVATE_DIRECTORY}")
repo_dir=$(pwd -P)
case "$private_dir/" in "$repo_dir/"*) echo 'Use a private directory outside the repository.' >&2; exit 2 ;; esac
socket=${USBMUXD_SOCKET_PATH:-/var/run/usbmuxd}
test -S "$socket"
umask 077
mkdir -p "$private_dir/device-state" "$private_dir/device-captures"
chmod 700 "$private_dir/device-state" "$private_dir/device-captures"
if ! docker image inspect english-trainer-device-debug >/dev/null 2>&1; then
  docker build -t english-trainer-dev .
  docker build -t english-trainer-device -f Dockerfile.device .
  docker build -t english-trainer-device-debug -f Dockerfile.device-debug .
fi
filename="english-trainer-$(date -u +%Y%m%dT%H%M%SZ).png"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/state -e "CAPTURE_NAME=$filename" \
  --mount "type=bind,src=$socket,dst=/var/run/usbmuxd" \
  --mount "type=bind,src=$private_dir/device-state,dst=/state" \
  --mount "type=bind,src=$private_dir/device-captures,dst=/captures" \
  english-trainer-device-debug bash -c '
set -euo pipefail
umask 077
if ideviceimagemounter --list | grep -Fq "Status: Complete"; then
  echo "Developer image is already mounted; skipping image lookup/download."
else
  pymobiledevice3 mounter auto-mount
fi
pymobiledevice3 developer dvt launch --no-kill-existing jp.guch1120.EnglishTrainer
pymobiledevice3 developer core-device screen-capture screenshot "/captures/$CAPTURE_NAME"
'
printf 'Screenshot: %s/device-captures/%s\n' "$private_dir" "$filename"
