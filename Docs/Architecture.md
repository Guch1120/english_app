# Architecture / Phase 1

`Apps/EnglishTrainer` → local Swift package `Packages/VoiceLearning`.
One package exposes independently importable libraries: LearningCore (models, scheduling, alignment), LearningPersistence (SQLite), SpeechCore (TTS/ASR/enhancement contracts), TTSBackends (Apple system playback adapter), NeuralTTSBackends, NeuralASRBackends, AudioEnhancementBackends, LLMCore (generation contract and validation), LiteRTLLMBackend, ModelManagement (exclusive runtime lease), and DeviceDiagnostics. Keeping related targets in a single package avoids cyclic package dependencies; another app can select individual products.

UI calls no third-party inference SDK. Apple speech playback lives in TTSBackends and is injected through SpeechPlayback at the composition root. Neural TTS, ASR, LLM, and speech-enhancement SDKs are isolated behind their backend targets and the contracts in SpeechCore/LLMCore. On-device model work shares one exclusive runtime lease. RE-USE-specific model handling is described in [REUSE.md](REUSE.md).

SQLite uses system libsqlite3 and bound statements. Schema v1 stores typed JSON payloads in keyed learning/weak-point tables and transactional review history. Future schema changes must add actual ordered migration steps. All DB access is MainActor-confined for this small initial dataset; move heavy queries off UI before scaling. Learning data is under Application Support with iOS file protection and included in OS backup. Speech recordings and downloaded model data use protected storage excluded from backup.

Runtime coordinator grants a single exclusive async lease, rejects overlapping jobs, and releases it on errors/cancellation. Callers hold the lease across load→infer→unload and clean up their backend on errors and cancellation. Model-specific memory-pressure behavior remains subject to real-device validation.

Review schedule v1: again=10 min, hard=max(1 day, previous×1.2), good=max(2 days, previous×2), easy=max(4 days, previous×2.5). The user controls the grade; no LLM is called. WER uses token Levenshtein alignment with insertion/deletion/substitution; case and punctuation normalize. Number words and contractions are not yet equated. WER is not pronunciation scoring.

No microphone permission is requested until recording is implemented. There is no HTTP listener, authentication, telemetry, remote inference, or sync. Delete action removes all learning records after confirmation and does not reseed them on restart.
