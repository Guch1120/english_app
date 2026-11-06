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

3. Merge the reviewed PR into main. The TestFlight workflow starts automatically on each push to `main`; it can also be started manually from Actions → TestFlight → Run workflow → main. It never runs for PRs, uses only `ios-testflight` secrets, and rejects uploads from any branch other than main.
4. The macOS 26 runner selects Xcode 26.5 explicitly, runs Package tests, archives unsigned, then cloud-signs for `app-store-connect` and uploads via `xcodebuild -exportArchive`. No distribution p12 is required if cloud signing is authorized. The app version (`CFBundleShortVersionString`, currently `0.1.0`) identifies the feature release; each TestFlight upload gets a unique build number using `(workflow run number + 100).attempt`. For example, TestFlight run 3 uploaded version `0.1.0 (103.1)`. A rerun gets a fresh build number. Both values are visible in Settings → App. No IPA or signing-material artifacts are published.
5. After Apple processing completes, open the app's TestFlight tab, create an internal testing group, add yourself and select the build. Install through the TestFlight app. Upload success alone does not establish processing success or tester availability. External testing/public links are not enabled by this workflow.

## Validation and limitations

PR CI requires no signing secrets. A workflow change runs package checks, builds/analyzes the Simulator app, and runs `Scripts/testflight.sh --archive-only` to verify the unsigned device archive, compiled icon, and that every app-linked dynamic framework (including `CLiteRTLM.framework`) is embedded. This guards against launch-time dyld failures. It does not test cloud-signing permissions or App Store Connect upload validation; those run only after merge to `main`, using the protected `ios-testflight` Environment.

The app now has a code-generated opaque 1024×1024 icon. Regenerate it with Python's standard library inside Docker (e.g. the device debug image):

```bash
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/workspace" english-trainer-device-debug python3 /workspace/Scripts/generate-app-icon.py
```

`ITSAppUsesNonExemptEncryption` is false because the current app and its linked libraries do not implement non-exempt encryption. This must be reviewed when dependencies or cryptographic features change. OpenSSL used by development scripts is not shipped in the app. Export-compliance declarations do not replace Apple's other requirements.

TestFlight distribution only verifies the upload and Apple processing path. The app now includes the implementations described in the phase documentation, but an uploaded build does not by itself verify on-device model downloads, inference, offline operation, or interruption recovery. Those behaviors need the documented device checks.

Sources checked 2026-11-06:
- [Apple upload requirements](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [App icons](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- [Encryption declaration](https://developer.apple.com/documentation/Security/complying-with-encryption-export-regulations)
- [Cloud-managed signing](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/)
- [API keys and team-key scope](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)
