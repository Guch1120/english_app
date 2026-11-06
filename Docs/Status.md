# Implementation status

2026-11-06 / Phase 1 foundation and initial Phase 2 TTS integration.

Implemented: reusable SwiftPM targets, SQLite v1 and transactional review history, deterministic interval scheduling, token alignment/WER, LLM result validation/mock, ASR mock contract, exclusive runtime lease, SwiftUI learning/review/settings, Apple speech playback, Docker test entrypoint, secretless macOS CI, manual protected development-signing workflow with encrypted IPA.

Verified locally: Docker Swift 6.0.3 package build and 6 tests passed (SQLite reopen/deletion/foreign keys, scheduling, alignment, invalid generated content, runtime lease conflict/error cleanup).

Verified on GitHub Actions: code commit `8fd71c8` passed Linux Docker tests, macOS Package tests, and unsigned iOS Simulator build/analyze. [Run 42170463658](https://github.com/Guch1120/english_app/actions/runs/42170463658).

Verified on iPhone 16 (`iPhone17,3`), iOS 26.4.2, 2026-11-06: [Device build 42205920964](https://github.com/Guch1120/english_app/actions/runs/42205920964) generated an encrypted development-signed IPA; Docker OpenSSL decryption/ZIP validation passed; Docker ideviceinstaller completed USB installation and listed bundle `jp.guch1120.EnglishTrainer` (build 2). The user confirmed the learning screen opened. A USB screenshot was captured using pymobiledevice3 11.50.0 after mounting the DeveloperDiskImage, and the dark-mode home layout was visually inspected.

Accessibility element inspection succeeded, but an attempted accessibility activation did not change the screen; no automated tapping/navigation or end-to-end learning flow is claimed. Audio playback, review interaction, VoiceOver, offline behavior and restart persistence remain to be verified on device. The development build was installed via USB. Subsequently [TestFlight run 42211956318](https://github.com/Guch1120/english_app/actions/runs/42211956318) uploaded build 0.1.0 (101.1); the user confirmed installation through TestFlight after assigning the build and their account to an internal testing group. No AI-model performance numbers measured.

Not implemented: microphone/ASR integration, LLM runtime integration, model catalog/download/hash verification/resume, enhancement adapter, benchmark screens, recording retention/export, automatic lifecycle/memory-pressure management, advanced device UI automation. These remain later phases. No mock output is presented as real inference.

Signing requires new App ID/profile and dedicated Environment secrets; see iPhone-Setup.md. The unsigned CI does not need these secrets.

Initial Phase 2 code adds SDK adapters, curated verified model downloads, WAV caching/playback controls, comparison metrics and opt-in Apple Silicon smoke tests. Linux 13 tests passed; native CI/device neural-inference results are recorded in the PR. See [TTS.md](TTS.md) for pinned sources, licenses and limits.
