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

After the runner-build PR is merged, run **Actions → WDA Runner Build → Run workflow → main**. The workflow uses Appium WebDriverAgent 16.18.1 pinned to commit `943e2efdb5d8b26a704d0cef58cb5eec0f37076c`, the existing development certificate, and the two protected profiles. It signs with the runner profile UUID in manual mode, so the non-interactive Xcode build does not need an Apple Developer account login or profile creation. It verifies the runner signature and embedded profile, then encrypts the IPA with `DEV_IPA_PASSWORD` before uploading a one-day artifact.

Download and decrypt the artifact into the private signing directory (replace `RUN_ID` with the WDA Runner Build run number):

```bash
bash Scripts/download-wda-ipa.sh RUN_ID /home/robo25/.config/english-trainer-signing/registration-vpztHzWL
```

Install the helper runner and start a WDA session over USB. The following `pymobiledevice3` commands run **inside the Dockerfile.device-debug container**, with the IPA and existing usbmuxd socket mounted; do not install it on the host:

```bash
ipa=/home/robo25/.config/english-trainer-signing/registration-vpztHzWL/builds/wda-RUN_ID/wda-runner.ipa
pymobiledevice3 apps install --developer "$ipa"
pymobiledevice3 developer wda launch jp.guch1120.EnglishTrainer \
  --xctrunner jp.guch1120.WebDriverAgentRunner.xctrunner
pymobiledevice3 developer wda screenshot /tmp/english-trainer-wda.png \
  --xctrunner jp.guch1120.WebDriverAgentRunner.xctrunner
```

## Device requirements

The iPhone must remain paired over USB, have Developer Mode enabled, and have **Settings → Developer → Enable UI Automation** turned on. This is a separate device-side switch; creating the WDA App IDs/profiles, signing the runner, and installing it do not enable UI Automation. If the switch is off, XCTest can launch the runner but time out while enabling automation mode, so WDA never opens its HTTP server on port 8100.

After enabling the switch, unlock the iPhone and retry the WDA launch. If iOS displays a confirmation or passcode prompt, complete it on the device. Verify a WDA status response and screenshot, then perform a harmless tap before using it for app acceptance. Stop the WDA runner when the automation session ends.

### Troubleshooting the automation-mode timeout

If the runner log contains `Timed out while enabling automation mode` and the host reports that port 8100 never became reachable, first check **Settings → Developer → Enable UI Automation** on the iPhone. A successful runner build, valid signing, successful USB installation, Developer Mode, and a mounted Developer image do not prove this switch is enabled.

WDA is a development helper, not an app update mechanism. It provides UI input to the already installed TestFlight app; TestFlight still controls app installation and updates.

## Confirmed USB control (2026-11-09)

After the user enabled UI Automation, WDA 16.18.1 returned `ready: true` on iPhone 16 / iOS 26.4.2. Screenshots worked. Keeping the XCTest runner alive across commands allowed `tap gearshape` to open Settings; a later screenshot confirmed the selected Settings tab and English Trainer 0.1.0 (143.1). RE-USE and LLM management navigation also worked. This establishes remote UI control, not successful TestFlight installation or model inference by itself.

Per-command `--xctrunner` can return before the HTTP server is stable. Prefer one bounded runner and execute subsequent WDA commands in the same container. The image pins pymobiledevice3 11.50.0. Example using the existing private pairing/tunnel state:

```bash
wda_state=/home/robo25/.config/english-trainer-signing/registration-vpztHzWL/device-state
wda_output=/tmp/english-app-device-check
mkdir -p -m 700 "$wda_output"
docker run --detach --rm --name english-trainer-wda-session \
  --user "$(id -u):$(id -g)" -e HOME=/state \
  --mount type=bind,src=/var/run/usbmuxd,dst=/var/run/usbmuxd \
  --mount "type=bind,src=$wda_state,dst=/state" \
  --mount "type=bind,src=$wda_output,dst=/output" \
  english-trainer-device-debug \
  pymobiledevice3 developer dvt xcuitest \
  jp.guch1120.WebDriverAgentRunner.xctrunner --userspace --timeout 900 \
  --output-log /output/runner.log
docker exec english-trainer-wda-session \
  pymobiledevice3 developer wda status --userspace --timeout 15
docker exec english-trainer-wda-session \
  pymobiledevice3 developer wda screenshot /output/device.png --userspace --timeout 15
```

Wait for a successful status response before input commands. Inspect the current screen/elements before each action. SwiftUI tab accessibility names are `headphones`, `arrow.clockwise`, and `gearshape`; Japanese labels need not be the accessibility ID. Do not repeat a timed-out action blindly: inspect the screen because the tap may already have taken effect. Stop the bounded runner with `docker stop english-trainer-wda-session` when done. Keep screenshots, element trees and debug logs outside Git; they may contain learning content.
