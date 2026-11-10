# Implementation status

Updated 2026-11-10 (JST). The phase implementation is merged in main through Phase 7 and follow-up stabilization. At audit start, main was `fd16acf` (PR #100). There are no open pull requests. Phase completion means the planned implementation and required CI scope was merged; it does not mean all iPhone acceptance checks are complete.

## Delivery and verification

- **Phases 0–7:** implementation and stabilization changes are merged. Learning, review, TTS, ASR, Gemma 4 E2B, model management, RE-USE integration, diagnostics, privacy and release paths are described in the linked component docs below. Do not treat a mocked or unavailable engine as real inference.
- **Latest full iOS gate:** PR #94 run [42818188522](https://github.com/Guch1120/english_app/actions/runs/42818188522) passed quality, Docker core tests, GitHub macOS package tests, iPhone Simulator build/analyze/UI tests, unsigned distribution archive checks and review-gate. The Simulator UI test grades a review item, verifies history after restart, and verifies deletion cascades to review history.
- **Recent documentation gates:** PR #100 merged as `fd16acf`; run [42835937937](https://github.com/Guch1120/english_app/actions/runs/42835937937) passed quality and review-gate. Core and iOS were correctly skipped for docs-only changes.
- **TestFlight:** run [42825893942](https://github.com/Guch1120/english_app/actions/runs/42825893942) uploaded 0.1.0 (190.1) from code commit `973d388`. Apple processing completed, TestFlight offered the update, and USB installed-app query plus app launch confirmed 190.1 on iPhone 16 / iOS 26.4.2.
- **Docker:** run `bash Scripts/test.sh` and `bash Scripts/quality.sh` before every PR. iOS builds and UI validation remain GitHub macOS work; Linux/Docker success is not iOS build evidence.

## Current physical-device evidence

190.1 launched on iPhone 16. Previous acceptance work confirmed offline Gemma generation and saved-lesson restoration, offline Kokoro/Pocket synthesis, repeat playback audible to the user, offline Parakeet/Apple Speech result display, and fixed-sample and recorded-speech RE-USE comparisons. On 2026-11-10, a temporary review item created from an existing sample lesson was graded “普通”: the device showed one review, success 1/failure 0, mastery 100%, and a next review two days later. The matching history entry showed the same grade and next date. The temporary item and its review history were then deleted. The saved-review count and review history returned to zero; existing learning activity history remained. The lesson’s English-display toggle was restored to OFF. On the same build, the Gemma search screen listed nine model files and showed size/license/revision metadata; no model download or removal was performed. WDA was stopped. Details and limitations are in [Acceptance.md](Acceptance.md).

These observations are individual checks. They do not establish broad model accuracy, semantic lesson quality, long-duration stability or full physical-device acceptance. The RE-USE audible-quality comparison remains intentionally unevaluated at the user's request.

## Remaining acceptance work

See the complete section-by-section source and device audit in [Specification-Audit.md](Specification-Audit.md) and the 18 initial-release conditions in [Acceptance.md](Acceptance.md). Notable open items include additional Parakeet recordings and transcript-level accuracy, RE-USE WER difference, accessibility, Bluetooth, microphone-denial retry, interruption/lock/background behavior, cancellation and error recovery, model download/removal lifecycle, offline review restoration, low-storage behavior, and repeated thermal/memory measurements. Any test that needs user speech, headphones, or permission changes must be requested clearly; do not delete or replace user recordings.

## Component documentation

- [Architecture.md](Architecture.md): package boundaries, persistence, runtime lease and review scheduler.
- [TTS.md](TTS.md): pinned SDK/model revisions, licensing, integrity checks, WAV cache and playback.
- [ASR.md](ASR.md): Parakeet and Apple Speech, recording retention and transcript comparison.
- [REUSE.md](REUSE.md): optional enhancement pipeline, verification gate and limits.
- [LLM.md](LLM.md): Gemma integration, validation, model search and on-device measurement.
- [Review.md](Review.md): deterministic review scheduling, history and deletion.
- [Automated-Checks.md](Automated-Checks.md): PR gate scope and limits.
- [TestFlight.md](TestFlight.md): protected signing, upload and device-install flow.
