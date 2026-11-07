#!/usr/bin/env bash
set -euo pipefail

boot_only=false
if [[ "${1:-}" == "--boot-only" ]]; then
  boot_only=true
  shift
fi
app_path=${1:-}
bundle_id=jp.guch1120.EnglishTrainer
if [[ "$boot_only" != true ]]; then
  [[ -n "$app_path" ]] || { echo 'Usage: bash Scripts/ci/simulator-startup-smoke.sh [/path/to/EnglishTrainer.app | --boot-only]' >&2; exit 2; }
  test -d "$app_path" || { echo "Simulator app not found: $app_path" >&2; exit 1; }
fi

read -r simulator_udid simulator_state < <(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
data = json.load(sys.stdin)
candidates = []
for runtime, devices in data["devices"].items():
    if not runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
        continue
    version = tuple(int(part) for part in re.findall(r"\d+", runtime))
    for device in devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            candidates.append((version, device["udid"], device["state"]))
if not candidates:
    raise SystemExit("No available iPhone simulator was found")
_, udid, state = max(candidates)
print(udid, state)
')

case "$simulator_state" in
  Booted|Booting) ;;
  *) xcrun simctl boot "$simulator_udid" ;;
esac
if [[ "$boot_only" == true ]]; then
  echo "Started booting iPhone Simulator $simulator_udid"
  exit 0
fi
xcrun simctl bootstatus "$simulator_udid" -b
xcrun simctl uninstall "$simulator_udid" "$bundle_id" >/dev/null 2>&1 || true
xcrun simctl install "$simulator_udid" "$app_path"
launch_output=$(xcrun simctl launch "$simulator_udid" "$bundle_id")
printf '%s\n' "$launch_output"
pid=$(sed -nE 's/.*: ([0-9]+)$/\1/p' <<<"$launch_output")
if [[ -z "$pid" ]]; then
  echo 'Could not read the simulator app process ID.' >&2
  exit 1
fi

container=$(xcrun simctl get_app_container "$simulator_udid" "$bundle_id" data)
diagnostics="$container/Library/Application Support/diagnostics.json"
for _ in {1..15}; do
  [[ -f "$diagnostics" ]] && break
  sleep 1
done
sleep 3
kill -0 "$pid" || { echo 'English Trainer exited during its startup smoke check.' >&2; exit 1; }
python3 - "$diagnostics" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.is_file():
    raise SystemExit("English Trainer did not create its diagnostics file")
events = json.loads(path.read_text())
launches = [
    event for event in events
    if event.get("subsystem") == "app" and event.get("action") == "appLaunch"
]
if len(launches) != 1:
    raise SystemExit(f"Expected one appLaunch event after a fresh install, found {len(launches)}")
print("PASS: app stayed running and recorded exactly one launch initialization")
PY
