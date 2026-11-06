#!/usr/bin/env bash
# Use the existing host usbmuxd; never install host packages or restart services.
set -euo pipefail
cd "$(dirname "$0")/.."
operation=${1:-check}
case "$operation" in
  check|installed) ;;
  install)
    if [ -z "${2:-}" ] || [ ! -f "$2" ]; then
      echo 'Usage: bash Scripts/iphone.sh install /absolute/path/to/app.ipa' >&2
      exit 2
    fi ;;
  *) echo 'Usage: bash Scripts/iphone.sh {check|installed|install IPA}' >&2; exit 2 ;;
esac
socket=${USBMUXD_SOCKET_PATH:-/var/run/usbmuxd}
test -S "$socket" || { echo 'Existing usbmuxd socket not found. Connect the trusted iPhone.' >&2; exit 1; }
if ! docker image inspect english-trainer-device >/dev/null 2>&1; then
  docker build -t english-trainer-dev .
  docker build -t english-trainer-device -f Dockerfile.device .
fi
mounts=(--mount "type=bind,src=$socket,dst=/var/run/usbmuxd")
if [ "$operation" = install ]; then
  ipa=$(realpath -- "$2")
  mounts+=(--mount "type=bind,src=$ipa,dst=/artifact/app.ipa,readonly")
fi
docker run --rm --user "$(id -u):$(id -g)" "${mounts[@]}" \
  -e "DEVICE_OPERATION=$operation" -e "TARGET_UDID=${IPHONE_UDID:-}" \
  -e 'APP_BUNDLE_ID=jp.guch1120.EnglishTrainer' english-trainer-device bash -c '
set -euo pipefail
if [ -n "$TARGET_UDID" ]; then
  device=$TARGET_UDID
else
  devices=$(idevice_id -l)
  count=$(printf "%s\n" "$devices" | sed "/^$/d" | wc -l)
  if [ "$count" -ne 1 ]; then
    printf "Expected one USB device, found %s. For multiple devices, set IPHONE_UDID.\n" "$count" >&2
    exit 1
  fi
  device=$devices
fi
case "$DEVICE_OPERATION" in
  check)
    printf "Product: "; ideviceinfo -u "$device" -k ProductType
    printf "iOS: "; ideviceinfo -u "$device" -k ProductVersion ;;
  install)
    ideviceinstaller -u "$device" -i /artifact/app.ipa
    ideviceinstaller -u "$device" -l | grep -F "$APP_BUNDLE_ID" ;;
  installed)
    ideviceinstaller -u "$device" -l | grep -F "$APP_BUNDLE_ID" ;;
esac
'
