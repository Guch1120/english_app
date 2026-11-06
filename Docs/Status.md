# Implementation status

Updated 2026-11-07. Work proceeds in the Docker environment; iOS builds run on GitHub's macOS runner because the development host is Linux.

## Merged phases

- **Phases 1–4** are in `main`. Phase 3 is documented in [ASR.md](ASR.md); Phase 4 in [Review.md](Review.md). The connected iPhone has previously launched the learning screen and, as of this update, USB app metadata reports TestFlight version **0.1.0 (106.1)**.
- **Phase 5 / LLM** was merged by PR [#11](https://github.com/Guch1120/english_app/pull/11) at `fea0620`. Docker quality/tests, macOS Package tests, iOS Simulator build/analyze, unsigned archive, and the review gate all passed in [run 42271561361](https://github.com/Guch1120/english_app/actions/runs/42271561361). Merge-triggered TestFlight run [42273707239](https://github.com/Guch1120/english_app/actions/runs/42273707239) succeeded and uploaded **0.1.0 (107.1)**. Apple processing and installation are separate; the connected iPhone still reports 0.1.0 (106.1).

## Active work

- **Phase 6 / RE-USE audio enhancement** is PR [#12](https://github.com/Guch1120/english_app/pull/12), based on `main`. It includes optional same-recording ASR comparison, model and cache management, fixed-sample device verification, enhanced-audio playback, measurements, and license notices. Docker tests and quality checks passed. macOS CI exposed an actor-isolation error and then an invalid SwiftUI optional binding; both are fixed on the branch and the full check set is running again. Do not merge until every required check passes.
- **Phase 7 / stabilization** is PR [#13](https://github.com/Guch1120/english_app/pull/13), stacked on Phase 6. Its scope is in [Phase7.md](Phase7.md). Docker tests pass (22 tests); the quality script passed inside Docker with the worktree's git metadata mounted. It is rebased on the latest Phase 6 fix; iOS Simulator and unsigned archive checks must pass on this updated branch before merge.

## Device-validation limits

USB reads and screenshots are available from the Linux host, but there is no working remote-tap channel. The installed app was read as 0.1.0 (106.1). Actual iPhone microphone/ASR quality, Gemma model load and generation, RE-USE fixed-sample inference and audio improvement, offline behavior, playback interruption handling, thermal behavior, and memory pressure need physical-device interaction. No performance or quality claim is made until those checks are recorded.

## Operating and release notes

- Local package tests and quality checks run in Docker (`bash Scripts/test.sh`, `bash Scripts/quality.sh`). iOS Simulator and unsigned archive checks run on GitHub Actions macOS.
- Merging to `main` triggers the protected TestFlight upload workflow. Short version remains 0.1.0; the build number follows `(workflow run number + 100).attempt`. See [TestFlight.md](TestFlight.md).
- Signing secrets remain in the GitHub `ios-testflight` environment. Do not commit user data, model weights, certificates, provisioning profiles, or private keys.
- See [TTS.md](TTS.md), [ASR.md](ASR.md), [LLM.md](LLM.md), and [REUSE.md](REUSE.md) for per-engine revisions, licenses, storage, privacy, and evidence limits.
