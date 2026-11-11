# TTS integration / Phase 2

The Phase 1 learning database and review scheduling remain in place. The new path is:

UI → speech controller → exclusive runtime lease → validated model store → SDK adapter → WAV cache → audio playback.

Apple system speech remains the default. Neural voices are opt-in and labeled unverified on physical iPhone until device checks are completed. Settings → 音声モデル管理 downloads the selected model only after confirmation, verifies every file's size/SHA-256, and exposes the engine in the picker after verification. Initial voices are US Kokoro `af_heart` and English Pocket `alba`. No arbitrary Hugging Face search result is executable.

## Pinned components and licenses

- FluidAudio source v0.18.2, commit `e396cf780c4abf8e395087467c0585d3b0d17f68`, Apache-2.0. `Vendor/FluidAudio/Sources` is an unchanged source snapshot verified against `UPSTREAM.json` in every quality run. Original source/license notices are retained. The app consumes it through a local Swift package with no inference SDK types exposed to learning logic.
- The custom package manifest omits CLI/tests and the unused LuxTTS G2P data target. Those data resources have separate GPL/CC-BY-SA terms and are not redistributed. An empty compatibility resource module lets untouched SDK source compile; LuxTTS is not in the app catalog. The device archive check rejects the excluded lexicon/aux files if accidentally bundled later.
- NeMo text normalization binary v0.3.1 is upstream's pinned xcframework, verified by its SwiftPM checksum. Its Apache/MIT component notices are included in Settings → ライセンス.
- Kokoro compiled files/G2P/US lexicon: `FluidInference/kokoro-82m-coreml` revision `2568276a60ff6e7f312afce3dc9e3f07521cb48d`, Apache-2.0, 48 files / 94,809,695 bytes.
- Pocket April English pack (`v2.1/english`, fp16/GPU): `FluidInference/pocket-tts-coreml` revision `c2e998e269e4d4b51f74061faddb8450cd8f9a9a`, 22 files / 369,779,063 bytes. Model weights: Kyutai CC BY 4.0; Alba MacKenna voice: CC BY 4.0. Only `alba.safetensors` is included. The app shows attribution and source/license links.
- Manifest JSON contains metadata and hashes, not model weights. `Scripts/curate-tts-models.py` recreates manifests from fixed revisions. A manifest/revision update is a reviewable code change.

Sources: [FluidAudio v0.18.2](https://github.com/FluidInference/FluidAudio/tree/v0.18.2), [Kokoro card](https://huggingface.co/FluidInference/kokoro-82m-coreml), [Pocket conversion card](https://huggingface.co/FluidInference/pocket-tts-coreml), [Kyutai voice terms](https://huggingface.co/kyutai/tts-voices/blob/main/README.md).

## Privacy and downloads

`NeuralRuntime` configures SDK logging before creating any managers (`minimumLevel = .fault`, `mirrorsToConsole = false`); the selected TTS implementation has no content-bearing fault logs. SDK `ModelHub.offlineMode = true` prevents hidden asset fetches/redownloads. The app's separate downloader only fetches the allowlisted manifest's immutable HTTPS URLs, checks file size and streaming SHA-256 before promotion, and never sends learning text. The model screen updates aggregate progress during large file transfers and reaches 100% only after each file has passed integrity checks. Interrupted file transfers retain an app-private partial and retry with a validated HTTP `Range` request; servers that ignore ranges trigger a clean full-file restart. Partial and unverified files are never loadable.

Model storage is app-owned Application Support, protected on iOS and excluded from backup. Generated WAV/metadata cache is separate from models and recordings. Cache keys retain case and punctuation, normalize whitespace/Unicode and include engine, SDK/model revision, speaker and generation parameters. Playback rate is excluded. UUID sidecar filenames use exact key comparisons; no filename contains learning text. Cache metadata contains text locally, so do not export it as anonymous diagnostics. Cache budgets are configurable (64/128/256 MiB), LRU eviction and explicit clearing are provided.

A single controller disallows overlapping preparation, synthesis, removal and cache operations. Native prediction may not stop immediately: cancellation waits for the current SDK/native call, drops any cancelled result and unloads before the lease is released. Background transitions cancel pending model work without stopping an already-playing audio file. This does not guarantee arbitrary background inference.

## Playback and measurements

Generated WAV playback supports pause/resume, looping, and AVAudioPlayer rate adjustment without regenerating speech. Apple fallback pause/resume is supported; its rate still affects system synthesis. On 2026-11-11, the user confirmed repeat-enabled Kokoro comparison playback continued after both locking and returning to Home on an iPhone 16 / iOS 26.4.2 running TestFlight 208.1. Apple US English lesson TTS continued after locking and after returning Home with repeat enabled; repeat was audibly heard, though the number of cycles was not counted. A saved 3.9-second recording continued after both lock and Home transitions. During active playback over Bluetooth headphones, disconnecting Bluetooth stopped playback without switching to the phone speaker. Playing audio from another app stopped Kokoro playback, which did not resume when the other app's audio ended. The retention OFF relaunch test removed the saved recording; retention was restored ON afterward. Kokoro was selected and repeat was OFF after testing. Calls, other interruption types and long-duration behavior remain untested.

Comparison text and its comparison-group ID persist locally. Results include voice/revision, generation time excluding model load, audio duration, sample rate, RTF, cache-hit flag, and a sampled process-RSS peak (50ms polling). Cached playback has no generation/RTF value. RSS includes the whole process and is not model-only allocation or a guaranteed instantaneous peak. Measurements retain at most 100 records, contain no input text, and only the current comparison-group results are shown together. First call/warm behavior and real audio quality remain separate validation concerns; managers are unloaded after each new generation.

## Verification

- Docker tests cover WAV parsing/truncation, cache identity/restart/corruption/eviction, immutable manifests, path traversal, checksum rejection, interrupted-download byte-range resume and full-restart fallback. Linux deliberately excludes the Apple-only SDK dependency and never claims native inference success.
- GitHub macOS tests compile the real SDK and Simulator app. Normal PR tests skip neural model inference to avoid fetching large assets on every run.
- Manual `Validate` workflow with input `tts_smoke=true` downloads the pinned models and synthesizes the fixed public sentence `Please confirm your reservation.` for both engines on Apple Silicon. WAV files and timing JSON are retained as a three-day artifact. This establishes model execution on that runner, not iPhone compatibility, pronunciation accuracy or usability. No user text/recordings are used in this test.
- Physical iPhone tests must check model install/cancel/retry, offline synthesis, playback rate/loop/pause, interruptions, sequential engine changes, memory/thermal behavior and cache reuse. Keep Apple as the default until this is measured.

Verified code commit `e638898` on 2026-11-06:

- Docker: 14 tests passed; quality/policy/vendor integrity/secret scan passed.
- [Manual native validation run](https://github.com/Guch1120/english_app/actions/runs/42220026354): 15 macOS tests passed, including both actual model executions; iOS Simulator build and static analysis passed; unsigned distribution archive passed.
- [PR validation run](https://github.com/Guch1120/english_app/actions/runs/42220033799): all required checks passed.
- Apple Silicon runner, first synthesis of the fixed sentence: Kokoro 3.135 s generation / 2.45 s audio (RTF 1.279); Pocket 3.089 s generation / 1.84 s audio (RTF 1.679). Model loading is excluded. These are single-run observations, not iPhone benchmarks or audio-quality ratings.
- SDK layout mapping: the verified Kokoro frontend is copied into the SDK's shared `Models/kokoro` directory; Pocket's manifest explicitly selects `Models/pocket-tts`. Storage folder overrides are validated against path traversal.
- Full learning-data deletion also clears generated audio, local comparison text and measurement history; downloaded models remain available.

## Physical iPhone follow-up (2026-11-10)

TestFlight 0.1.0 (160.1) was installed on iPhone 16 / iOS 26.4.2. With Airplane Mode on and Wi-Fi off, both neural engines generated the same verified pure-English comparison input. Kokoro: 1.14 seconds generation, 3.32 seconds audio, 24 kHz, RTF 0.343 and 551.6 MB process RSS peak. Pocket: 1.48 seconds generation, 2.48 seconds audio, 24 kHz, RTF 0.599 and 751.1 MB process RSS peak. Device diagnostics recorded inference success; application code records that event after `AVAudioPlayer.play()` succeeds. The user later confirmed hearing two cycles from Kokoro with repeat enabled and reported Pocket TTS working. This confirms audibility for the Kokoro repeat test and user-observed Pocket operation; it is not a specialist pronunciation or sound-quality assessment. Interruption/route behavior and longer thermal/memory behavior remain unverified. See [Acceptance.md](Acceptance.md).
