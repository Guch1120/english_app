#!/usr/bin/env bash
# Unsigned archive is testable without secrets. Uploads are main-only and environment-protected.
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:---archive-only}
case "$mode" in --archive-only|--upload) ;; *) echo 'Usage: bash Scripts/testflight.sh {--archive-only|--upload}' >&2; exit 2 ;; esac
: "${RUNNER_TEMP:?Run on the GitHub macOS runner}"
if [ "$mode" = --upload ]; then
  [ "${GITHUB_REF:-}" = refs/heads/main ] || { echo 'Uploads are restricted to main.' >&2; exit 1; }
  : "${APPSTORE_ISSUER_ID:?Missing issuer ID}" "${APPSTORE_API_KEY_ID:?Missing key ID}"
  : "${APPSTORE_API_PRIVATE_KEY:?Missing API private key}" "${APPLE_TEAM_ID:?Missing team ID}"
fi
umask 077
work=$(mktemp -d "$RUNNER_TEMP/english-testflight.XXXXXX")
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
build_number="$(( ${GITHUB_RUN_NUMBER:-1} + 100 )).${GITHUB_RUN_ATTEMPT:-1}"
if [ "$mode" = --upload ]; then
  key_path="$work/AuthKey_${APPSTORE_API_KEY_ID}.p8"
  printf '%s' "$APPSTORE_API_PRIVATE_KEY" > "$key_path"
  # Validate format without printing the private key.
  openssl pkey -in "$key_path" -noout >/dev/null 2>&1 || { echo 'Invalid .p8 key: paste the full PEM including real newlines.' >&2; exit 1; }
fi
# Upload SDK requirement is iOS 26+. Fail before spending time on an incompatible archive.
sdk=$(xcrun --sdk iphoneos --show-sdk-version)
[ "${sdk%%.*}" -ge 26 ] || { echo 'TestFlight requires an iOS 26+ SDK.' >&2; exit 1; }
xcodebuild -version
xcodebuild -project EnglishTrainer.xcodeproj -scheme EnglishTrainer -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$work/EnglishTrainer.xcarchive" \
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID:-}" CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym CURRENT_PROJECT_VERSION="$build_number" archive
app="$work/EnglishTrainer.xcarchive/Products/Applications/EnglishTrainer.app"
dsym="$work/EnglishTrainer.xcarchive/dSYMs/EnglishTrainer.app.dSYM"
dsym_binary="$dsym/Contents/Resources/DWARF/EnglishTrainer"
if [ ! -f "$dsym_binary" ]; then
  echo 'The distribution archive did not produce the app dSYM required to symbolicate device crash reports.' >&2
  exit 1
fi
binary_uuids=$(dwarfdump --uuid "$app/EnglishTrainer" | awk '{print $2}' | sort)
dsym_uuids=$(dwarfdump --uuid "$dsym_binary" | awk '{print $2}' | sort)
if [ -z "$binary_uuids" ] || [ "$binary_uuids" != "$dsym_uuids" ]; then
  echo 'The app dSYM UUID does not match the archived executable.' >&2
  exit 1
fi
/usr/libexec/PlistBuddy -c 'Print CFBundleIconName' "$app/Info.plist" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c 'Print CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "$app/Info.plist" >/dev/null
if [ ! -f "$app/Frameworks/CLiteRTLM.framework/CLiteRTLM" ]; then
  echo 'CLiteRTLM.framework is missing from the archived app; the TestFlight build would crash at launch.' >&2
  exit 1
fi
if otool -L "$app/EnglishTrainer" | awk 'NR > 1 && $1 ~ /^@rpath\/[^ ]+\.framework\/[^/]+$/ { found = 1 } END { exit !found }'; then
  if ! otool -l "$app/EnglishTrainer" | grep -Fq 'path @executable_path/Frameworks '; then
    echo 'The archived app has @rpath framework dependencies but no @executable_path/Frameworks runpath.' >&2
    exit 1
  fi
fi
while IFS= read -r dependency; do
  relative_framework=${dependency#@rpath/}
  if [ ! -f "$app/Frameworks/$relative_framework" ]; then
    echo "Dynamic framework dependency is missing from the archive: $relative_framework" >&2
    exit 1
  fi
done < <(otool -L "$app/EnglishTrainer" | awk 'NR > 1 && $1 ~ /^@rpath\/[^ ]+\.framework\/[^/]+$/ { print $1 }')
if [ -n "$(find "$app" \( -name 'luxtts_en_us_lexicon.tsv.zz' -o -name 'luxtts_en_us_g2p_aux.json' \) -print -quit)" ]; then
  echo 'Unused LuxTTS G2P data must not be redistributed in this app.' >&2
  exit 1
fi
if [ "$mode" = --archive-only ]; then
  echo 'Unsigned distribution archive, compiled app icon, and matching crash dSYM verified.'
  exit 0
fi
symbols_zip="$RUNNER_TEMP/EnglishTrainer-dSYMs-run${GITHUB_RUN_NUMBER:-1}-${GITHUB_RUN_ATTEMPT:-1}.zip"
ditto -c -k --sequesterRsrc "$work/EnglishTrainer.xcarchive/dSYMs" "$symbols_zip"
chmod 600 "$symbols_zip"
export ENGLISH_EXPORT_OPTIONS="$work/ExportOptions.plist"
python3 - <<'PY'
import os, plistlib
with open(os.environ['ENGLISH_EXPORT_OPTIONS'], 'wb') as output:
    plistlib.dump({'method':'app-store-connect', 'destination':'upload', 'signingStyle':'automatic',
        'teamID':os.environ['APPLE_TEAM_ID'], 'manageAppVersionAndBuildNumber':False, 'uploadSymbols':True}, output)
PY
# Match the established app's unsigned-archive -> cloud-managed distribution-signing flow.
xcodebuild -exportArchive -archivePath "$work/EnglishTrainer.xcarchive" \
  -exportPath "$work/export" -exportOptionsPlist "$ENGLISH_EXPORT_OPTIONS" \
  -allowProvisioningUpdates -authenticationKeyPath "$key_path" \
  -authenticationKeyID "$APPSTORE_API_KEY_ID" -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID"
echo 'App Store Connect upload command completed; Apple processing and tester availability are separate.'
