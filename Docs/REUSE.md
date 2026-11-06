# Phase 6: on-device speech enhancement

RE-USE is an optional, off-by-default comparison tool for noisy speech. It takes the same saved recording, runs the selected on-device ASR once without enhancement and once after RE-USE, and shows both transcripts, each transcript's word error rate against the lesson, ASR time, enhancement time, real-time factor, and model-load time. It can play the enhanced recording. A transcript match score is not a pronunciation score.

## Runtime and model handling

- The iOS adapter lives in `AudioEnhancementBackends`; the `SpeechCore` protocol and metrics have no RE-USE SDK dependency. Unsupported platforms expose a clear unavailable implementation.
- The iOS integration pins RE-USE Swift package 0.2.0 and the converted model repository revision in `Resources/ModelSource.json`. Model files are not stored in Git. `ReuseModelStore` checks the catalogued size and SHA-256 values during download and keeps model files in Application Support, excluded from backup. The compilation cache is stored separately and is removed with the model.
- The app downloads about 54 MB only after the user confirms. It loads the model only for a requested device check or comparison, and releases it afterward. A shared runtime lease prevents overlap with TTS, ASR, and LLM inference.
- Before processing a personal recording, the user must run the fixed bundled noisy-speech sample through the actual on-device engine. Verification is tied to the pinned model revision. If model files are removed or the revision changes, verification must be repeated. The sample is copied into a protected temporary directory because the app bundle is read-only; the temporary input and output are removed after the check.
- The engine accepts mono audio up to five minutes, writes a protected temporary WAV beside the saved recording, and reports engine measurements. The original recording is retained if enhancement fails. A new recording or the recording-delete action removes its prior enhanced copy.
- The default is disabled. The user can disable comparisons or remove model and compiled-cache files in Settings. Audio, transcripts, and lesson text are not sent to a service or written to routine logs.

## Model and notices

The converted Apple model pack is obtained from `AILogDev/RE-USE-MLX-CoreML` at immutable revision `4b7e50680ba34f10865cab7e24054262596f5ab4`; the source revision is recorded in the app resources. The original NVIDIA NemotronLabs RE-USE model uses OpenMDW-1.1. Its full license and the upstream package's third-party notices, including the bundled sample attribution, are available in Settings → RE-USE → model source and licenses. Only this model and license are used by the integration.

The Swift adapter is pinned to [RE-USE-MLX-CoreML 0.2.0](https://github.com/Corvelis/RE-USE-MLX-CoreML/tree/v0.2.0). The model card and full model terms are linked from the app. No model weights or converted model files are redistributed in the app binary.

## Acceptance and verification limits

Phase 6 is complete when the iOS package, simulator build, and unsigned archive pass CI; Docker tests and quality checks pass; download, checksum verification, cancellation, removal, fixed-sample device verification, recording comparison, playback, and error paths are represented in code; and the data/licensing behavior is documented. GitHub CI does not run Core ML or MLX inference. The app gates use until the fixed sample has run on the user's iPhone. Actual enhancement quality, storage demand, latency, memory pressure, and thermal behavior still need that device measurement before making a quality or performance claim.
