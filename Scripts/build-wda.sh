#!/usr/bin/env bash
set -euo pipefail

: "${RUNNER_TEMP:?Run this script on GitHub macOS}"
: "${IOS_CERTIFICATE_BASE64:?Missing iOS development certificate}"
: "${IOS_CERTIFICATE_PASSWORD:?Missing iOS development certificate password}"
: "${APPLE_TEAM_ID:?Missing Apple team ID}"
: "${DEV_IPA_PASSWORD:?Missing IPA encryption password}"
: "${WDA_BASE_PROFILE_BASE64:?Missing WDA base profile}"
: "${WDA_RUNNER_PROFILE_BASE64:?Missing WDA runner profile}"

source_dir=${1:?Usage: bash Scripts/build-wda.sh PATH_TO_PINNED_WDA_SOURCE}
project="$source_dir/WebDriverAgent.xcodeproj"
test -d "$project"

umask 077
temp_dir=$(mktemp -d "$RUNNER_TEMP/wda-signing.XXXXXX")
keychain="$temp_dir/wda.keychain-db"
profile_root="$HOME/Library/MobileDevice/Provisioning Profiles"
installed_profiles=()
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  for profile in "${installed_profiles[@]}"; do rm -f "$profile"; done
  rm -rf "$temp_dir" build/wda-derived build/wda-payload
}
trap cleanup EXIT

printf '%s' "$IOS_CERTIFICATE_BASE64" | base64 --decode > "$temp_dir/development.p12"
printf '%s' "$WDA_BASE_PROFILE_BASE64" | base64 --decode > "$temp_dir/wda-base.mobileprovision"
printf '%s' "$WDA_RUNNER_PROFILE_BASE64" | base64 --decode > "$temp_dir/wda-runner.mobileprovision"

security cms -D -i "$temp_dir/wda-base.mobileprovision" > "$temp_dir/wda-base.plist"
security cms -D -i "$temp_dir/wda-runner.mobileprovision" > "$temp_dir/wda-runner.plist"
export WDA_PROFILE_DIR="$temp_dir" APPLE_TEAM_ID
python3 - <<'PY'
import datetime
import os
import plistlib
from pathlib import Path

root = Path(os.environ["WDA_PROFILE_DIR"])
team = os.environ["APPLE_TEAM_ID"]
expected = {
    "wda-base.plist": (
        "English Trainer WDA Base Development",
        "jp.guch1120.WebDriverAgentRunner",
    ),
    "wda-runner.plist": (
        "English Trainer WDA Runner Development",
        "jp.guch1120.WebDriverAgentRunner.xctrunner",
    ),
}
now = datetime.datetime.now(datetime.timezone.utc)
device_sets = []
for filename, (name, bundle_id) in expected.items():
    with (root / filename).open("rb") as source:
        profile = plistlib.load(source)
    expiration = profile.get("ExpirationDate")
    if expiration is not None and expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=datetime.timezone.utc)
    entitlements = profile.get("Entitlements", {})
    devices = set(profile.get("ProvisionedDevices", []))
    if profile.get("Name") != name:
        raise SystemExit("WDA provisioning profile name mismatch")
    if not expiration or expiration <= now:
        raise SystemExit("WDA provisioning profile is expired")
    if entitlements.get("application-identifier") != f"{team}.{bundle_id}":
        raise SystemExit("WDA provisioning profile bundle ID mismatch")
    if team not in profile.get("TeamIdentifier", []):
        raise SystemExit("WDA provisioning profile team mismatch")
    if entitlements.get("get-task-allow") is not True:
        raise SystemExit("WDA development profile is required")
    if len(devices) != 1 or len(profile.get("DeveloperCertificates", [])) != 1:
        raise SystemExit("WDA profiles must each contain one device and one certificate")
    device_sets.append(devices)
if device_sets[0] != device_sets[1]:
    raise SystemExit("WDA profiles must target the same registered iPhone")
PY

mkdir -p "$profile_root"
for profile in wda-base wda-runner; do
  uuid=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$temp_dir/$profile.plist")
  destination="$profile_root/$uuid.mobileprovision"
  cp "$temp_dir/$profile.mobileprovision" "$destination"
  chmod 600 "$destination"
  installed_profiles+=("$destination")
done

keychain_password=$(openssl rand -hex 24)
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$temp_dir/development.p12" -P "$IOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain" >/dev/null
security set-key-partition-list -S apple-tool:,apple: -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"

mkdir -p build
if ! xcodebuild \
  -project "$project" \
  -scheme WebDriverAgentRunner \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/wda-derived \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY='Apple Development' \
  PRODUCT_BUNDLE_IDENTIFIER=jp.guch1120.WebDriverAgentRunner \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  build-for-testing > "$temp_dir/xcodebuild.log" 2>&1; then
  echo 'WDA runner build failed; signing details are withheld from public logs.' >&2
  grep -E '(^|[[:space:]])error:|BUILD FAILED' "$temp_dir/xcodebuild.log" \
    | sed -E 's/[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}/[REDACTED-UUID]/g; s/[[:xdigit:]]{20,40}/[REDACTED-ID]/g' \
    | tail -n 20 >&2 || true
  exit 1
fi

runner_app="build/wda-derived/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app"
test -d "$runner_app"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$runner_app/Info.plist")
test "$bundle_id" = jp.guch1120.WebDriverAgentRunner.xctrunner
codesign --verify --deep --strict "$runner_app"
test -f "$runner_app/embedded.mobileprovision"
security cms -D -i "$runner_app/embedded.mobileprovision" > "$temp_dir/embedded-runner.plist"
export WDA_EMBEDDED_PROFILE="$temp_dir/embedded-runner.plist"
export WDA_RUNNER_PROFILE_PLIST="$temp_dir/wda-runner.plist"
python3 - <<'PY'
import os
import plistlib
from pathlib import Path

with Path(os.environ["WDA_EMBEDDED_PROFILE"]).open("rb") as source:
    embedded = plistlib.load(source)
with Path(os.environ["WDA_RUNNER_PROFILE_PLIST"]).open("rb") as source:
    expected = plistlib.load(source)
if embedded.get("UUID") != expected.get("UUID"):
    raise SystemExit("WDA runner was signed with an unexpected provisioning profile")
if embedded.get("Entitlements", {}).get("application-identifier") != (
    os.environ["APPLE_TEAM_ID"] + ".jp.guch1120.WebDriverAgentRunner.xctrunner"
):
    raise SystemExit("WDA runner signature has an unexpected application identifier")
PY

mkdir -p build/wda-payload/Payload
ditto "$runner_app" build/wda-payload/Payload/WebDriverAgentRunner-Runner.app
# An .ipa must contain the Payload directory at the ZIP root.
ditto -c -k --keepParent build/wda-payload/Payload build/wda-runner.ipa
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
  -in build/wda-runner.ipa -out build/wda-runner.ipa.enc \
  -pass env:DEV_IPA_PASSWORD
rm -f build/wda-runner.ipa
echo 'Signed WDA runner package validated and encrypted for short-lived artifact storage.'
