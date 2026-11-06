# Architecture / Phase 1

`Apps/EnglishTrainer` → local Swift package `Packages/VoiceLearning`.
One package exposes six independently importable libraries: LearningCore (models, scheduling, alignment), LearningPersistence (SQLite), SpeechCore (TTS/ASR/enhancement contracts), LLMCore (generation contract and validation), ModelManagement (exclusive runtime lease), DeviceDiagnostics (measurement types). Keeping related targets in a single package avoids cyclic package dependencies; another app can select individual products.

UI calls no third-party inference SDK. Apple speech playback is currently an app adapter; model-generated audio adapters will implement SpeechCore. Apple utterance rate is synthesis speed, not pitch-preserving cached playback. No generated-audio cache exists yet.

SQLite uses system libsqlite3 and bound statements. GRDB is deferred until its version/license and Linux test compatibility are reviewed; no external Swift dependencies are currently required. Schema v1 stores typed JSON payloads in keyed learning/weak-point tables and transactional review history. Future schema changes must add actual ordered migration steps. All DB access is MainActor-confined for this small initial dataset; move heavy queries off UI before scaling. Data is under Application Support with iOS file protection, included in OS backup. No recording files exist in this phase.

Runtime coordinator grants a single exclusive async lease, rejects overlapping jobs, and releases it on errors/cancellation. Callers must hold the lease across load→infer→unload and clean up their backend with `defer` or a cancellation handler. Automatic memory-pressure unloading and adapters are later phases; the lease alone does not implement them.

Review schedule v1: again=10 min, hard=max(1 day, previous×1.2), good=max(2 days, previous×2), easy=max(4 days, previous×2.5). The user controls the grade; no LLM is called. WER uses token Levenshtein alignment with insertion/deletion/substitution; case and punctuation normalize. Number words and contractions are not yet equated. WER is not pronunciation scoring.

No microphone permission is requested until recording is implemented. There is no HTTP listener, authentication, telemetry, remote inference, or sync. Delete action removes all learning records after confirmation and does not reseed them on restart.
