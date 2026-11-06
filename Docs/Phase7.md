# Phase 7: release stabilization scope

This is the final implementation phase for the initial specification, not an expansion into excluded features. It closes cross-cutting stability, offline readiness, privacy, and distribution work across TTS, ASR, LLM, and RE-USE.

## Completion criteria

1. **Task and model lifecycle:** backgrounding, explicit cancellation, audio interruptions, and iOS memory warnings stop active playback/recording and cancel inference through each backend's cleanup path. A cancelled task reports cancellation without presenting it as a model failure. Concurrent model work remains serialized by the shared runtime coordinator.
2. **Audio stability:** recording is closed and retained when the app backgrounds or the audio session is interrupted; playback stops on interruptions and loss of the active output route. The app does not resume audio without a user action.
3. **Offline readiness:** Settings explains which models must be downloaded and device-verified before airplane-mode use. It shows truthful per-engine readiness from local state and gives a short manual offline smoke checklist. LLM candidate metadata and verified-install markers are cached locally so an installed model can be selected for offline generation after restart without querying Hugging Face. Model SHA-256 is checked at installation; restart readiness checks only the expected local file and size, avoiding a multi-gigabyte rehash at launch. No network check discloses user activity.
4. **Storage and privacy:** model, recording, generated-audio, and measurement paths use intended protection and backup rules; storage setup failure is surfaced and never falls back to a less-protected temporary path. Source review confirms no user audio, transcript, or lesson text is logged or uploaded by inference paths.
5. **Distribution and documentation:** PR/main CI, TestFlight numbering, device installation, permission prompts, model preparation, data deletion, offline operation, and known hardware-validation limits are documented accurately. Tests and the iOS Simulator/archive workflow pass.
6. **Evidence:** Docker tests and quality checks pass; GitHub macOS checks pass. Any operation that requires physical audio or Core ML/MLX is marked as needing iPhone confirmation until performed.

## Explicitly out of scope

Cloud inference/sync, accounts, App Store public release, realtime speech, pronunciation scoring, and claiming real-device model performance without measurements remain excluded from the initial release.
