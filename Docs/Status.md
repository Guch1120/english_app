# Implementation status

2026-11-07 / Phase 1–3 are merged. Phase 4 review-history and mastery UX is in progress.

Implemented: reusable SwiftPM targets, SQLite v1 and transactional review history, deterministic interval scheduling, token alignment/WER, LLM result validation/mock, ASR mock contract, exclusive runtime lease, SwiftUI learning/review/settings, Apple speech playback, Docker test entrypoint, secretless macOS CI, manual protected development-signing workflow with encrypted IPA.

Verified locally: Docker Swift 6.0.3 package build and 16 tests passed (SQLite reopen/deletion/foreign keys/review and practice history, schedule, mastery/streak calculations, legacy weak-point decoding, alignment, invalid generated content, runtime lease conflict/error cleanup).

Verified on GitHub Actions: code commit `8fd71c8` passed Linux Docker tests, macOS Package tests, and unsigned iOS Simulator build/analyze. [Run 42170463658](https://github.com/Guch1120/english_app/actions/runs/42170463658).

Verified on iPhone 16 (`iPhone17,3`), iOS 26.4.2, 2026-11-06: [Device build 42205920964](https://github.com/Guch1120/english_app/actions/runs/42205920964) generated an encrypted development-signed IPA; Docker OpenSSL decryption/ZIP validation passed; Docker ideviceinstaller completed USB installation and listed bundle `jp.guch1120.EnglishTrainer` (build 2). The user confirmed the learning screen opened. A USB screenshot was captured using pymobiledevice3 11.50.0 after mounting the DeveloperDiskImage, and the dark-mode home layout was visually inspected.

Accessibility element inspection succeeded, but an attempted accessibility activation did not change the screen; no automated tapping/navigation or end-to-end learning flow is claimed. Audio playback, review interaction, VoiceOver, offline behavior and restart persistence remain to be verified on device. The development build was installed via USB. Subsequently [TestFlight run 42211956318](https://github.com/Guch1120/english_app/actions/runs/42211956318) uploaded build 0.1.0 (101.1); the user confirmed installation through TestFlight after assigning the build and their account to an internal testing group. No AI-model performance numbers measured.

Phase 3 complete in [PR #9](https://github.com/Guch1120/english_app/pull/9), merged as `bc1b03b`. It adds Parakeet and offline-only Apple Speech selection, reusable saved recording playback/re-recognition, transcript comparison normalization, and speaking review registration. The PR passed Docker quality and tests plus macOS package, Simulator, and unsigned archive checks. [TestFlight run 42259482680](https://github.com/Guch1120/english_app/actions/runs/42259482680) uploaded version 0.1.0 (105.1) successfully. USB inspection still reports 104.1 on the connected iPhone; the TestFlight update is not yet installed and real-device ASR behavior remains unverified.

Not implemented: LLM runtime integration, enhancement adapter, model catalog/search, benchmark screens, recording export, automatic lifecycle/memory-pressure management, advanced device UI automation. WhisperKit comparison, streaming/VAD and any pronunciation score remain future work. No mock output is presented as real inference.

Signing requires new App ID/profile and dedicated Environment secrets; see iPhone-Setup.md. The unsigned CI does not need these secrets.

Phase 2 adds SDK adapters, curated verified model downloads, WAV caching/playback controls, comparison metrics and opt-in Apple Silicon smoke tests. See [TTS.md](TTS.md) for results. See [ASR.md](ASR.md) for the pinned model, retention rules and device verification needed. Phase 4 adds queryable review and practice events, streak and mastery summaries, review history, source-lesson access, and review-item deletion. See [Review.md](Review.md) for its behavior.
