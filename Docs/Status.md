# Implementation status

2026-11-06 / Phase 1 foundation.

Implemented: reusable SwiftPM targets, SQLite v1 and transactional review history, deterministic interval scheduling, token alignment/WER, LLM result validation/mock, ASR mock contract, exclusive runtime lease, SwiftUI learning/review/settings, Apple speech playback, Docker test entrypoint, secretless macOS CI, manual protected development-signing workflow with encrypted IPA.

Pending verification: Docker tests (initial image download in progress at first commit), macOS/iOS build, UI/VoiceOver/device tests. No AI-model performance numbers measured.

Not implemented: neural TTS adapters/cache/comparison, microphone/ASR integration, LLM runtime integration, model catalog/download/hash verification/resume, enhancement adapter, benchmark screens, recording retention/export, automatic lifecycle/memory-pressure management, Docker USB install tool. These remain later phases. No mock output is presented as real inference.

Signing requires new App ID/profile and dedicated Environment secrets; see iPhone-Setup.md. Nothing has been installed on the iPhone. The unsigned CI does not need these secrets.
