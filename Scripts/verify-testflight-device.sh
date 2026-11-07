#!/usr/bin/env bash
set -euo pipefail

expected_build=${1:?Usage: bash Scripts/verify-testflight-device.sh BUILD_NUMBER [TIMEOUT_SECONDS]}
timeout_seconds=${2:-3600}
[[ "$expected_build" =~ ^[0-9]+\.[0-9]+$ ]] || { echo 'Build number must look like 119.1.' >&2; exit 2; }
if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || (( timeout_seconds <= 0 )); then
  echo 'Timeout must be a positive number of seconds.' >&2
  exit 2
fi

cd "$(dirname "$0")/.."
socket=${USBMUXD_SOCKET_PATH:-/var/run/usbmuxd}
test -S "$socket" || { echo 'Existing usbmuxd socket not found. Connect the trusted iPhone.' >&2; exit 1; }

if ! docker image inspect english-trainer-device-debug >/dev/null 2>&1; then
  docker build -t english-trainer-dev .
  docker build -t english-trainer-device -f Dockerfile.device .
  docker build -t english-trainer-device-debug -f Dockerfile.device-debug .
fi

docker run --rm --user "$(id -u):$(id -g)" \
  -e HOME=/tmp/pmd3-home \
  -e EXPECTED_BUILD="$expected_build" \
  -e TIMEOUT_SECONDS="$timeout_seconds" \
  -e PYMOBILEDEVICE3_UDID="${IPHONE_UDID:-}" \
  --mount "type=bind,src=$socket,dst=/var/run/usbmuxd" \
  english-trainer-device-debug bash -c '
set -euo pipefail
bundle_id=jp.guch1120.EnglishTrainer
diagnostics_path="/Library/Application Support/diagnostics.json"

query_build() {
  pymobiledevice3 apps query "$bundle_id" 2>/dev/null | python3 -c '\''
import json, sys
try:
    app = json.load(sys.stdin)["jp.guch1120.EnglishTrainer"]
    print(app["CFBundleVersion"])
except (KeyError, ValueError, TypeError):
    raise SystemExit(1)
'\''
}

deadline=$((SECONDS + TIMEOUT_SECONDS))
installed_build=
while (( SECONDS < deadline )); do
  installed_build=$(query_build || true)
  if [[ "$installed_build" == "$EXPECTED_BUILD" ]]; then break; fi
  printf "Waiting for TestFlight build %s; installed build: %s\n" "$EXPECTED_BUILD" "${installed_build:-unavailable}"
  sleep 15
done
if [[ "$installed_build" != "$EXPECTED_BUILD" ]]; then
  printf "Timed out waiting for build %s; installed build: %s\n" "$EXPECTED_BUILD" "${installed_build:-unavailable}" >&2
  exit 1
fi
printf "Installed TestFlight build: %s\n" "$installed_build"

pid=$(pymobiledevice3 developer dvt process-id-for-bundle-id "$bundle_id" 2>/dev/null || true)
if [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )); then
  printf "App is already running (PID %s); skipped a cold launch.\n" "$pid"
  exit 0
fi

before=$(mktemp)
after=$(mktemp)
trap '\''rm -f "$before" "$after"'\'' EXIT
baseline=-1
if pymobiledevice3 apps pull "$bundle_id" "$diagnostics_path" "$before" >/dev/null 2>&1; then
  baseline=$(python3 - "$before" <<'\''PY'\''
import json, sys
try:
    events = json.load(open(sys.argv[1], encoding="utf-8"))
    print(max((event.get("timestamp", -1) for event in events), default=-1))
except (OSError, ValueError, TypeError):
    print(-1)
PY
)
fi

pymobiledevice3 developer dvt launch "$bundle_id"
sleep 20
pid=$(pymobiledevice3 developer dvt process-id-for-bundle-id "$bundle_id" 2>/dev/null || true)
if ! [[ "$pid" =~ ^[0-9]+$ ]] || (( pid == 0 )); then
  echo "App did not remain running after launch of build $installed_build." >&2
  exit 1
fi
printf "App remained running after launch (PID %s).\n" "$pid"

if ! pymobiledevice3 apps pull "$bundle_id" "$diagnostics_path" "$after" >/dev/null 2>&1; then
  echo "App diagnostics were not available; process liveness passed, event-count check was unavailable." >&2
  exit 1
fi
python3 - "$after" "$baseline" <<'\''PY'\''
import json, sys
events = json.load(open(sys.argv[1], encoding="utf-8"))
baseline = float(sys.argv[2])
launches = [event for event in events
            if event.get("action") == "appLaunch"
            and float(event.get("timestamp", -1)) > baseline]
if len(launches) != 1:
    raise SystemExit(f"Expected exactly one new appLaunch event, found {len(launches)}")
event = launches[0]
print("New appLaunch events: 1")
print(f"RSS peak sample: {event.get('\''peakMemoryBytes'\'', '\''unavailable'\'')} bytes")
print(f"Thermal state: {event.get('\''thermalState'\'', '\''unavailable'\'')}")
PY
'
