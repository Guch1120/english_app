# USB iPhone UI automation setup

WebDriverAgent (WDA) lets the trusted USB iPhone accept taps and swipes through XCTest. Its runner must be signed for the actual device; the existing English Trainer development profile cannot sign the WDA bundle IDs.

## Provision the helper IDs

After the setup PR is merged, run **Actions → WDA Provisioning → Run workflow → main** once. The workflow uses the existing `ios-testflight` App Store Connect API key and the active `English learning app` iOS development profile. It creates or reuses these explicit iOS App IDs and matching development profiles:

- `jp.guch1120.WebDriverAgentRunner`
- `jp.guch1120.WebDriverAgentRunner.xctrunner`

The profiles use the same Apple Development certificate and the same registered device as the current English Trainer profile. The workflow refuses to replace a profile with a name collision or to proceed if it cannot find exactly one active matching English Trainer profile. It does not change or regenerate the English Trainer profile. This repository is public, so the workflow encrypts returned profiles with the App Store Connect `.p8` private key before retaining them in a one-day Actions artifact. The raw profile files are removed from the runner before artifact upload and are never committed to Git.

The encrypted artifact can be downloaded and decrypted outside the repository. Replace `RUN_ID` with the WDA Provisioning run number:

```bash
signing_dir="$HOME/.config/english-trainer-signing/registration-vpztHzWL"
profile_dir="$signing_dir/wda-profiles"
mkdir -m 700 -p "$profile_dir"
gh run download RUN_ID --repo Guch1120/english_app \
  --name wda-profiles-runRUN_ID --dir "$profile_dir"
p8_name=$(find "$signing_dir" -maxdepth 1 -type f -name 'AuthKey_*.p8' -printf '%f\n' -quit)
docker run --rm --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$PWD,dst=/workspace,readonly" \
  --mount "type=bind,src=$signing_dir,dst=/signing,readonly" \
  --mount "type=bind,src=$profile_dir,dst=/profiles" \
  english-trainer-dev python3 /workspace/Scripts/apple/crypt_profile.py decrypt \
  /profiles/wda-base.mobileprovision.enc /profiles/wda-base.mobileprovision \
  --key-file "/signing/$p8_name"
docker run --rm --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$PWD,dst=/workspace,readonly" \
  --mount "type=bind,src=$signing_dir,dst=/signing,readonly" \
  --mount "type=bind,src=$profile_dir,dst=/profiles" \
  english-trainer-dev python3 /workspace/Scripts/apple/crypt_profile.py decrypt \
  /profiles/wda-runner.mobileprovision.enc /profiles/wda-runner.mobileprovision \
  --key-file "/signing/$p8_name"
```

The profile directory must stay outside the repository. The matching `.p8` private key is required for decryption; the workflow artifact contains only authenticated ciphertext.

## Device requirements

The iPhone must remain paired over USB and have Developer Mode enabled. Installing and launching the signed WDA runner is a separate step from registering its App IDs and profiles. The runner build should use the pinned Appium WebDriverAgent source, install only the helper runner, start it through `pymobiledevice3`, then verify a WDA screenshot and harmless tap before using it for app acceptance. WDA commands must be stopped when the automation session ends.

WDA is a development helper, not an app update mechanism. It provides UI input to the already installed TestFlight app; TestFlight still controls app installation and updates.
