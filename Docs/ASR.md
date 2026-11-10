# Phase 3 ASR and speaking practice

The speaking screen offers two English recognition engines and saves one protected recording for playback or repeat transcription. Both engines run on device: Parakeet TDT-CTC 110M (downloaded and verified) and Apple Speech (available only when the device reports on-device support). The engine choice persists across launches. WhisperKit remains an optional comparison engine if real-device quality or latency measurements show a need.

## Model and licensing

- `FluidInference/parakeet-tdt-ctc-110m-coreml`, immutable revision `9bc92ead6e8f17eca92a869fd578ae76842b82ba`.
- CC BY 4.0; attribution to NVIDIA NeMo and the FluidInference conversion is included in the app package and model screen.
- The allowlist contains the three compiled Core ML models and `parakeet_vocab.json`: 16 files / 227,466,209 bytes. It excludes source `.mlpackage` copies and unrelated repository files.
- `Scripts/curate-asr-model.py` regenerates the file manifest from the pinned Hugging Face tree. Downloaded components are checked for exact size and streaming SHA-256 before they are promoted into the SDK's expected model directory.
- The vendored FluidAudio snapshot and SDK logs are configured offline. ASR text and recording audio are not sent to a service or written to routine app logs.

Source: [Parakeet TDT-CTC 110M Core ML model card](https://huggingface.co/FluidInference/parakeet-tdt-ctc-110m-coreml), [Apple microphone permission API](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission%28completionhandler%3A%29).

## Recording and comparison

The first use requires microphone permission; Apple Speech also asks for speech-recognition permission. Apple Speech is selected only when `supportsOnDeviceRecognition` is true and each request sets `requiresOnDeviceRecognition`, so it cannot silently fall back to network recognition. Parakeet requires an explicit model download. Recording is 16 kHz mono PCM WAV in the app's protected, backup-excluded `Application Support/NeuralSpeech/Recordings/latest.wav` location. The app restores the latest recording after restart; a new recording replaces it. Users can replay or delete it in the speaking screen, or delete it with Settings → delete all learning data. A saved recording can be re-recognized with either selected engine. Transcripts and metrics are shown in memory and are not added to the learning database.

The model runs after recording completes. Recognition time excludes model load. The result screen shows word alignment and word error rate, allows registering the lesson for speaking review, and reports a rough word pace plus metered silence/pause estimates. Metering uses a fixed -42 dB threshold and is presented as an estimate. The screen can play the reference TTS and the saved recording. Transcript similarity is not a pronunciation score. A single runtime lease covers model loading, inference and cleanup, and is shared with TTS to avoid overlapping large models. Cancellation waits for the active inference operation to return before cleanup.

## Navigation and result display

Parakeet download, integrity status, removal, license information, and the Apple Speech engine choice are available from Settings → ASR model management. Lesson detail keeps a segmented Listening/Speaking selector pinned above the content so learners can switch modes without navigating to a separate screen. Stopping a recording starts transcription automatically. The transcript, word alignment, and word error rate sit directly after the recording controls; the view scrolls to those results when recognition completes. RE-USE comparison remains optional and its enhanced transcript is shown separately.

The error rate appears first in the result section, followed by the transcript. Per-word differences and timing/pace details can be expanded below it, so they do not push the summary out of view. Recognition can be cancelled from the recording controls.

The Simulator UI suite checks the in-place mode switch and Settings route. CI does not provide microphone input or validate real ASR output; automatic scroll behavior and recognition still require an on-device recording session.

## Verification limits

GitHub CI compiles the iOS app and runs Package tests but does not provide microphone input or prove real ASR output. Batch recognition is sufficient for this phase; streaming/VAD and pronunciation scoring remain outside the initial release. Optional RE-USE audio enhancement is implemented separately in [REUSE.md](REUSE.md).

## iOS 26.4.2 authorization crash (2026-11-09)

Two private crash reports from TestFlight 0.1.0 (145.1) on iPhone 16 showed the same `EXC_BREAKPOINT` in the TCC authorization callback path. Symbolication with the matching 145.1 dSYM located the Swift executor-isolation failure in the `SFSpeechRecognizer.requestAuthorization` continuation inside `AppleOnDeviceASRBackend.load()`. The callback ran on a background queue while its closure inherited `MainActor` isolation. The authorization request now runs through a non-actor async helper so the callback can safely resume its continuation from the queue supplied by Speech.

Docker tests and quality checks do not compile the app target or execute iOS TCC permission callbacks. The macOS Simulator CI verifies compilation and app launch, but not this first-use permission path. Fixed build 0.1.0 (151.1) was uploaded by [TestFlight run 42699366994](https://github.com/Guch1120/english_app/actions/runs/42699366994). Crash reports and identifying device data are retained outside the repository.

## iPhone 16 follow-up (2026-11-10)

TestFlight 0.1.0 (160.1) is installed on iPhone 16 / iOS 26.4.2. Selecting Apple Speech and starting/stopping a recording kept the app alive. While Airplane Mode was on and Wi-Fi was off, a bundled fixed sample produced results with both Parakeet 110M and Apple Speech. Parakeet took about 5.35 seconds on first recognition (about 5.28 seconds model load, 392.2 MB process RSS peak); Apple Speech took about 0.81 seconds (180.9 MB process RSS peak). Later, the user confirmed that their saved 5.1-second English recording could be transcribed by both engines offline. Device diagnostics recorded successful warm inference: Parakeet 277 ms / 180.8 MB process RSS peak and Apple Speech 330 ms / 172.5 MB; transcripts were not retained or shared. The comparison WER used a lesson reference that was not verified against the recording and is not recognition-quality evidence. See [Acceptance.md](Acceptance.md) for the full device record.

Still unverified on a physical iPhone: Apple Speech permission denial and retry, ASR cancellation/retry, and restoration of review answers after restart. Recognition success was confirmed on the user's saved recording, but its transcript was not independently compared with a ground truth.
