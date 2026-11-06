# Parakeet ASR / Phase 3 initial implementation

The first ASR path adds a single Parakeet English model to the reusable `ASRService` contract. The speaking screen downloads and verifies the model, records a spoken practice sentence, transcribes the saved WAV on device, and aligns recognized words with the lesson text.

## Model and licensing

- `FluidInference/parakeet-tdt-ctc-110m-coreml`, immutable revision `9bc92ead6e8f17eca92a869fd578ae76842b82ba`.
- CC BY 4.0; attribution to NVIDIA NeMo and the FluidInference conversion is included in the app package and model screen.
- The allowlist contains the three compiled Core ML models and `parakeet_vocab.json`: 16 files / 227,466,209 bytes. It excludes source `.mlpackage` copies and unrelated repository files.
- `Scripts/curate-asr-model.py` regenerates the file manifest from the pinned Hugging Face tree. Downloaded components are checked for exact size and streaming SHA-256 before they are promoted into the SDK's expected model directory.
- The vendored FluidAudio snapshot and SDK logs are configured offline. ASR text and recording audio are not sent to a service or written to routine app logs.

Source: [Parakeet TDT-CTC 110M Core ML model card](https://huggingface.co/FluidInference/parakeet-tdt-ctc-110m-coreml), [Apple microphone permission API](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission%28completionhandler%3A%29).

## Recording and comparison

The first use requires microphone permission and an explicit model download. Recording is 16 kHz mono PCM WAV in the app's protected, backup-excluded `Application Support/NeuralSpeech/Recordings/latest.wav` location. A new recording replaces the previous one. Users can delete it in the speaking screen or with Settings → delete all learning data. A saved recording remains available for retry after a transcription error and for a second transcription. Transcripts and metrics are shown in memory and are not added to the learning database.

The model runs after recording completes. Recognition time excludes model load. The result screen shows word alignment and word error rate; it describes transcript similarity and does not score pronunciation. A single runtime lease covers model loading, inference and cleanup, and is shared with TTS to avoid overlapping large models. Cancellation waits for the Core ML operation to return before model cleanup.

## Verification limits

GitHub CI compiles the iOS app and runs Package tests. The app needs an iPhone run to verify microphone permission, recording signal and format, model load, transcript quality, stop/cancel behavior, and offline recognition. The initial PR does not claim physical-device ASR success or pronunciation evaluation. Long recordings are processed as offline batches; streaming/VAD, WhisperKit comparison and audio enhancement are later work.
