# USB iPhone UI automation setup

WebDriverAgent (WDA) lets the trusted USB iPhone accept taps and swipes through XCTest. Its runner must be signed for the actual device; the existing English Trainer development profile cannot sign the WDA bundle IDs.

## Provision the helper IDs

After the setup PR is merged, run **Actions → WDA Provisioning → Run workflow → main** once. The workflow uses the existing `ios-testflight` App Store Connect API key and the active `English learning app` iOS development profile. It creates or reuses these explicit iOS App IDs and matching development profiles:

- `jp.guch1120.WebDriverAgentRunner`
- `jp.guch1120.WebDriverAgentRunner.xctrunner`

The profiles use the same Apple Development certificate and the same registered device as the current English Trainer profile. The workflow refuses to replace a profile with a name collision or to proceed if it cannot find exactly one active matching English Trainer profile. It does not change or regenerate the English Trainer profile. This repository is public, so the workflow encrypts returned profiles with the App Store Connect `.p8` private key before retaining them in a one-day Actions artifact. The raw profile files are removed from the runner before artifact upload and are never committed to Git.

The registered profiles were created successfully by [WDA Provisioning run 42385091149](https://github.com/Guch1120/english_app/actions/runs/42385091149). Their encrypted artifact was decrypted in Docker outside the repository, checked against the connected iPhone and added to the protected `ios-development` environment as `WDA_BASE_PROFILE_BASE64` and `WDA_RUNNER_PROFILE_BASE64`.

For a future profile renewal, download and decrypt the encrypted artifact outside the repository. Replace `RUN_ID` with the WDA Provisioning run number:

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

The profile directory must stay outside the repository. The matching `.p8` private key is required for decryption; the workflow artifact contains only authenticated ciphertext. Set the renewed profile values in the protected environment without printing them:

```bash
base64 -w 0 "$profile_dir/wda-base.mobileprovision" | \
  gh secret set WDA_BASE_PROFILE_BASE64 --repo Guch1120/english_app --env ios-development
base64 -w 0 "$profile_dir/wda-runner.mobileprovision" | \
  gh secret set WDA_RUNNER_PROFILE_BASE64 --repo Guch1120/english_app --env ios-development
```

## Build and install the signed runner

After the runner-build PR is merged, run **Actions → WDA Runner Build → Run workflow → main**. The workflow uses Appium WebDriverAgent 16.18.1 pinned to commit `943e2efdb5d8b26a704d0cef58cb5eec0f37076c`, the existing development certificate, and the two protected profiles. Its non-interactive Xcode 26 build enables provisioning updates so Xcode can resolve the registered development profiles. It verifies the runner signature and embedded profile, then encrypts the IPA with `DEV_IPA_PASSWORD` before uploading a one-day artifact.

Download and decrypt the artifact into the private signing directory (replace `RUN_ID` with the WDA Runner Build run number):

```bash
bash Scripts/download-wda-ipa.sh RUN_ID /home/robo25/.config/english-trainer-signing/registration-vpztHzWL
```

Install the helper runner and start a WDA session over USB:

```bash
ipa=/home/robo25/.config/english-trainer-signing/registration-vpztHzWL/builds/wda-RUN_ID/wda-runner.ipa
pymobiledevice3 apps install --developer "$ipa"
pymobiledevice3 developer wda launch jp.guch1120.EnglishTrainer \
  --xctrunner jp.guch1120.WebDriverAgentRunner.xctrunner
pymobiledevice3 developer wda screenshot /tmp/english-trainer-wda.png \
  --xctrunner jp.guch1120.WebDriverAgentRunner.xctrunner
```

## Device requirements

The iPhone must remain paired over USB and have Developer Mode enabled. Installing and launching the signed WDA runner is separate from registering its App IDs and profiles. After the first successful install, verify a WDA screenshot and harmless tap before using it for app acceptance. Stop the WDA runner when the automation session ends.

WDA is a development helper, not an app update mechanism. It provides UI input to the already installed TestFlight app; TestFlight still controls app installation and updates.
