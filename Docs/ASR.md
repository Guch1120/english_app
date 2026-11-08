# Phase 3 ASR and speaking practice

The speaking screen offers two English recognition engines and saves one protected recording for playback or repeat transcription. Both engines run on device: Parakeet TDT-CTC 110M (downloaded and verified) and Apple Speech (available only when the device reports on-device support). The engine choice persists across launches. WhisperKit remains an optional comparison engine if real-device quality or latency measurements show a need.

Parakeet can be downloaded and removed from **Settings → 音声認識モデル管理**. The same controls are also available from the speaking practice screen. The settings page shows download progress, verification status, model size and licensing information.

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

## Verification limits

GitHub CI compiles the iOS app and runs Package tests. iPhone verification is still required for each engine's model/permission path, microphone signal and format, transcript quality, model switching and repeat transcription, stop/cancel behavior, playback, and offline recognition. Batch recognition is sufficient for this phase; streaming/VAD and pronunciation scoring remain outside the initial release. Optional RE-USE audio enhancement is implemented separately in [REUSE.md](REUSE.md) and requires its own fixed-sample device check.
