# Phase 6: on-device speech enhancement

RE-USE is optional and off by default. When enabled, normal transcription enhances the saved recording before ASR. The separate comparison processes the same recording once without enhancement and once with RE-USE, showing transcripts, word error rate against the lesson, ASR time, enhancement time, real-time factor, and model-load time. The original recording remains available, as does enhanced playback. A transcript match score is not a pronunciation score.

Enabling RE-USE does not bypass its fixed-sample verification or five-minute limit: if the model is missing, unverified, or the recording is too long, normal transcription reports the reason and retains the original recording. It never silently sends the original through ASR while claiming enhancement. The user can turn RE-USE off and retry.

## Runtime and model handling

- The iOS adapter lives in `AudioEnhancementBackends`; the `SpeechCore` protocol and metrics have no RE-USE SDK dependency. Unsupported platforms expose a clear unavailable implementation.
- The iOS integration pins RE-USE Swift package 0.2.0 and the converted model repository revision in `Resources/ModelSource.json`. Model files are not stored in Git. The app downloads the package catalog through the shared byte-range downloader into protected, backup-excluded Application Support, verifies each size and SHA-256, then promotes the complete pack to the directory consumed by `ReuseModelStore`. The compilation cache is stored separately and is removed with the model. Interrupted files continue from their saved byte offset on retry.
- The app downloads about 54 MB only after the user confirms. It loads the model only for a requested device check, enhanced transcription or comparison, and releases it afterward. A shared runtime lease prevents overlap with TTS, ASR, and LLM inference.
- Before processing a personal recording, the user must run the fixed bundled noisy-speech sample through the actual on-device engine. Verification is tied to the pinned model revision. If model files are removed or the revision changes, verification must be repeated. The sample is copied into a protected temporary directory because the app bundle is read-only; the temporary input and output are removed after the check.
- The engine accepts mono audio up to five minutes, writes a protected temporary WAV beside the saved recording, and reports engine measurements. The original recording is retained if enhancement fails. A new recording or the recording-delete action removes its prior enhanced copy.
- The default is disabled. The user can disable enhancement or remove model and compiled-cache files in Settings. Audio, transcripts, and lesson text are not sent to a service or written to routine logs.

## Model and notices

The converted Apple model pack is obtained from `AILogDev/RE-USE-MLX-CoreML` at immutable revision `4b7e50680ba34f10865cab7e24054262596f5ab4`; the source revision is recorded in the app resources. The original NVIDIA NemotronLabs RE-USE model uses OpenMDW-1.1. Its full license and the upstream package's third-party notices, including the bundled sample attribution, are available in Settings → RE-USE → model source and licenses. Only this model and license are used by the integration.

The Swift adapter is pinned to [RE-USE-MLX-CoreML 0.2.0](https://github.com/Corvelis/RE-USE-MLX-CoreML/tree/v0.2.0). The model card and full model terms are linked from the app. No model weights or converted model files are redistributed in the app binary.

## Acceptance and verification limits

Phase 6 is complete when the iOS package, simulator build, and unsigned archive pass CI; Docker tests and quality checks pass; download, checksum verification, cancellation, removal, fixed-sample device verification, recording comparison, playback, and error paths are represented in code; and the data/licensing behavior is documented. GitHub CI does not run Core ML or MLX inference. The app gates use until the fixed sample has run on the user's iPhone. Actual enhancement quality, storage demand, latency, memory pressure, and thermal behavior still need that device measurement before making a quality or performance claim.
