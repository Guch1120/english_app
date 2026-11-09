# TestFlight distribution

USB development installation and TestFlight are independent. The existing `ios-development` environment remains for direct device builds; development signing files are not used for TestFlight.

## Apple and GitHub setup

1. Create an App Store Connect app record for `jp.guch1120.EnglishTrainer`. Its User Access setting affects your team, not public distribution. Pick an unused app name and your own SKU.
2. Create GitHub Environment `ios-testflight`, restrict deployment branches to main, and add:

| Secret | Value |
|---|---|
| APPSTORE_ISSUER_ID | Issuer ID for the team API key |
| APPSTORE_API_KEY_ID | Key ID |
| APPSTORE_API_PRIVATE_KEY | Entire `.p8` PEM text, including header/footer and real newlines; not base64 |
| APPLE_TEAM_ID | The same Developer Program Team ID as the app |

Do not commit or paste a private key into a PR/chat. An API key's upload permission and its ability to cloud-sign are separate concerns. The workflow follows the existing app's automatic signing route. Apple must grant the API identity permission to use cloud-managed Apple Distribution signing. An authorization error must be resolved explicitly; do not silently broaden a role or use someone else's credentials. Team API keys may access multiple apps according to their role; the app record's User Access choice does not make a team key app-specific.

3. To request automatic TestFlight distribution, apply the lowercase `testflight` label to a PR before merging it into `main`. Only merged PRs with that label start an upload; ordinary merges do not. If you add the label after merging, start the workflow manually from Actions → TestFlight → Run workflow → main. Manual runs do not require the label. The workflow never uploads PR builds, uses only `ios-testflight` secrets, and checks that a labeled PR was merged into `main`.
4. Automatic uploads rely on strict main branch protection: every merged PR must pass `quality`, `core`, `ios`, and `review-gate`, including the macOS Package tests. The TestFlight job skips the duplicate Package test step for a labeled merged PR; a manually started upload runs the Package tests itself. Both paths archive unsigned, then cloud-sign for `app-store-connect` and upload via `xcodebuild -exportArchive`. The archive must contain a matching app dSYM; the TestFlight job retains the archive dSYMs as a GitHub artifact for seven days so a device crash report can be symbolicated. The artifact contains debug symbols only, not the IPA or signing material. No distribution p12 is required if cloud signing is authorized. The app version (`CFBundleShortVersionString`, currently `0.1.0`) identifies the feature release; each TestFlight upload gets a unique build number using `(workflow run number + 100).attempt`. Skipped runs for unlabelled PRs can leave gaps in build numbers. A rerun gets a fresh build number. Both values are visible in Settings → App.
5. After Apple processing completes, open the app's TestFlight tab and create an internal group with **Enable automatic distribution** selected. Add yourself to that group once. App Store Connect then assigns future Xcode uploads to the group automatically. If the existing group was created without this option, create a new group for automatic distribution. Upload success alone does not establish processing success or tester availability. External testing/public links are not enabled by this workflow.
6. On the iPhone, open **TestFlight → English Trainer**, scroll to **App Settings**, and enable **Automatic Updates**. TestFlight can then download and install builds assigned to that tester after Apple processing. Both settings are needed: App Store Connect must assign the build to the group, and TestFlight must automatically install it. These are TestFlight settings; the English Trainer app cannot replace its own installed binary when it launches. Apple prohibits apps from downloading and installing executable code that changes app functionality ([App Review Guideline 2.5.2](https://developer.apple.com/app-store/review/guidelines/#software-requirements)); TestFlight provides its own update mechanism ([Apple TestFlight overview](https://developer.apple.com/testflight/), [WWDC23 walkthrough](https://developer.apple.com/videos/play/wwdc2023/10012/?time=52)).

## Latest upload status (2026-11-10)

[Run 42699366994](https://github.com/Guch1120/english_app/actions/runs/42699366994) completed the protected cloud-sign and upload workflow successfully for version **0.1.0 (151.1)**. Apple processing, internal tester assignment, and installation were not verified by that run. After installation, specifically verify the Apple Speech permission and recording-start fix described in [ASR.md](ASR.md).

## Validation and limitations

PR CI requires no signing secrets. A workflow change runs package checks, builds/analyzes the Simulator app, and runs `Scripts/testflight.sh --archive-only` to verify the unsigned device archive, compiled icon, matching app dSYM UUID, and that every app-linked dynamic framework (including `CLiteRTLM.framework`) is embedded. This guards against missing crash symbols and launch-time dyld failures. It does not test cloud-signing permissions or App Store Connect upload validation; those run only after merge to `main`, using the protected `ios-testflight` Environment.

The app now has a code-generated opaque 1024×1024 icon. Regenerate it with Python's standard library inside Docker (e.g. the device debug image):

```bash
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/workspace" english-trainer-device-debug python3 /workspace/Scripts/generate-app-icon.py
```

`ITSAppUsesNonExemptEncryption` is false because the current app and its linked libraries do not implement non-exempt encryption. This must be reviewed when dependencies or cryptographic features change. OpenSSL used by development scripts is not shipped in the app. Export-compliance declarations do not replace Apple's other requirements.

TestFlight distribution only verifies the upload and Apple processing path. With TestFlight Automatic Updates enabled, Codex can wait for the device's installed build number to change over USB and launch the app for a startup check. This does not enable remote taps on the current iOS 26.4.2 device, so workflows that require navigating controls still need physical interaction. An uploaded build does not by itself verify on-device model downloads, inference, offline operation, or interruption recovery; those behaviors need the documented device checks.

To wait for a specific TestFlight build and check its launch over the trusted USB connection, run this from the repository root:

```bash
bash Scripts/verify-testflight-device.sh 120.1 3600
```

The script polls the installed `CFBundleVersion` inside `english-trainer-device-debug`, then launches the app if it is not already running, waits 20 seconds, confirms the process remains alive, and requires exactly one new fixed-field `appLaunch` event. If the app is already running, it reports the PID and skips the cold-launch check without terminating the process. It does not install or update the app itself; TestFlight must perform the update. It does not simulate taps or validate audio/model flows.

Sources checked 2026-11-07:
- [Apple upload requirements](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [App icons](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- [Encryption declaration](https://developer.apple.com/documentation/Security/complying-with-encryption-export-regulations)
- [Cloud-managed signing](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/)
- [API keys and team-key scope](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)
- [Internal group automatic distribution](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [TestFlight automatic updates](https://developer.apple.com/videos/play/wwdc2023/10012/?time=630)
- [App Review Guideline 2.5.2](https://developer.apple.com/app-store/review/guidelines/#software-requirements)
