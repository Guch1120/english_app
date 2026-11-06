#!/usr/bin/env bash
set -euo pipefail
: "${IOS_CERTIFICATE_BASE64:?Missing certificate}" "${IOS_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${IOS_PROFILE_BASE64:?Missing profile}" "${APPLE_TEAM_ID:?Missing team}" "${DEV_IPA_PASSWORD:?Missing IPA password}"
temp_dir=$(mktemp -d "$RUNNER_TEMP/english-signing.XXXXXX")
keychain="$temp_dir/signing.keychain-db"
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  if [ -n "${profile_path:-}" ]; then rm -f "$profile_path"; fi
  rm -rf "$temp_dir" build/export build/EnglishTrainer.xcarchive
}
trap cleanup EXIT
printf '%s' "$IOS_CERTIFICATE_BASE64" | base64 --decode > "$temp_dir/cert.p12"
printf '%s' "$IOS_PROFILE_BASE64" | base64 --decode > "$temp_dir/profile.mobileprovision"
security cms -D -i "$temp_dir/profile.mobileprovision" > "$temp_dir/profile.plist"
profile_uuid=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$temp_dir/profile.plist")
profile_name=$(/usr/libexec/PlistBuddy -c 'Print Name' "$temp_dir/profile.plist")
# Values from the profile stay in the process, not in logs.
export PROFILE_PLIST="$temp_dir/profile.plist"
python3 - <<'PY'
import os, plistlib, datetime
with open(os.environ['PROFILE_PLIST'], 'rb') as f: p=plistlib.load(f)
assert p['TeamIdentifier'][0] == os.environ['APPLE_TEAM_ID'], 'Team mismatch'
assert p['Entitlements']['application-identifier'].endswith('.jp.guch1120.EnglishTrainer'), 'Bundle ID mismatch'
assert p['Entitlements'].get('get-task-allow') is True, 'Development profile required'
assert p.get('ProvisionedDevices'), 'Register a device in the profile'
assert p['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Expired profile'
PY
profile_path="$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
mkdir -p "$(dirname "$profile_path")"
cp "$temp_dir/profile.mobileprovision" "$profile_path"
keychain_password=$(openssl rand -hex 24)
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$temp_dir/cert.p12" -P "$IOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain" >/dev/null
security set-key-partition-list -S apple-tool:,apple: -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
xcodebuild -project EnglishTrainer.xcodeproj -scheme EnglishTrainer -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/EnglishTrainer.xcarchive \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_IDENTITY='Apple Development' \
  PROVISIONING_PROFILE_SPECIFIER="$profile_name" CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" archive > "$temp_dir/build.log" 2>&1 || { echo 'Archive failed; signing log withheld to protect profile details.'; exit 1; }
export EXPORT_OPTIONS="$temp_dir/export.plist" PROFILE_NAME="$profile_name"
python3 - <<'PY'
import os, plistlib
with open(os.environ['EXPORT_OPTIONS'],'wb') as f:
    plistlib.dump({'method':'debugging','teamID':os.environ['APPLE_TEAM_ID'],'signingStyle':'manual',
        'provisioningProfiles':{'jp.guch1120.EnglishTrainer':os.environ['PROFILE_NAME']}}, f)
PY
xcodebuild -exportArchive -archivePath build/EnglishTrainer.xcarchive -exportPath build/export -exportOptionsPlist "$EXPORT_OPTIONS" > "$temp_dir/export.log" 2>&1 || { echo 'Export failed; signing log withheld.'; exit 1; }
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -in build/export/EnglishTrainer.ipa -out build/EnglishTrainer.ipa.enc -pass env:DEV_IPA_PASSWORD
