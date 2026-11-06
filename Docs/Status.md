# Implementation status

Updated 2026-11-07. Work proceeds in the Docker environment; iOS builds run on GitHub's macOS runner because the development host is Linux.

## Merged phases

- **Phases 1–4** are in `main`. Phase 3 is documented in [ASR.md](ASR.md); Phase 4 in [Review.md](Review.md). USB app metadata last reported TestFlight version **0.1.0 (106.1)**.
- **Phase 5 / LLM** was merged by PR [#11](https://github.com/Guch1120/english_app/pull/11) at `fea0620`. Docker quality/tests, macOS Package tests, iOS Simulator build/analyze, unsigned archive, and the review gate all passed in [run 42271561361](https://github.com/Guch1120/english_app/actions/runs/42271561361). Merge-triggered TestFlight run [42273707239](https://github.com/Guch1120/english_app/actions/runs/42273707239) succeeded and uploaded **0.1.0 (107.1)**. Apple processing and installation are separate; the connected iPhone still reports 0.1.0 (106.1).
- **Phase 6 / RE-USE audio enhancement** was merged by PR [#12](https://github.com/Guch1120/english_app/pull/12) at `307eed8`. Docker tests and quality checks, macOS Package tests, iOS Simulator build/analyze, unsigned archive, and the review gate passed in [run 42281103300](https://github.com/Guch1120/english_app/actions/runs/42281103300). Merge-triggered TestFlight run [42284154032](https://github.com/Guch1120/english_app/actions/runs/42284154032) uploaded **0.1.0 (108.1)** successfully. USB crash report `EnglishTrainer-2026-11-07-051916.ips` then confirmed a launch-time `DYLD` failure because `CLiteRTLM.framework` was missing from the app bundle.
- **Phase 7 / stabilization and crash fix** was merged by PR [#13](https://github.com/Guch1120/english_app/pull/13) at `62f6d34`. Docker tests and quality checks, macOS Package tests, iOS Simulator build/analyze, unsigned archive with required-framework validation, and the review gate passed in [run 42289606444](https://github.com/Guch1120/english_app/actions/runs/42289606444). The archive now embeds `CLiteRTLM.framework` and checks all dynamic framework references. Merge-triggered TestFlight run [42292835837](https://github.com/Guch1120/english_app/actions/runs/42292835837) successfully uploaded **0.1.0 (109.1)**. The iPhone still has 108.1 installed pending a manual TestFlight update.

## Device-validation follow-up

- **Phase 7** is documented in [Phase7.md](Phase7.md). Docker tests pass (22 tests), and the quality script passed inside Docker with the worktree's git metadata mounted. Manual checks of model audio, offline operation, and interruption recovery remain outstanding.

## Device-validation limits

USB reads and screenshots are available from the Linux host. The installed app was read as 0.1.0 (108.1), and its crash report identified the missing LiteRT-LM framework at launch. A tap request to the authenticated CoreDevice HID touchscreen was rejected with `Remote control requires iOS 27.0 or later`; this device runs iOS 26.4.2. The user must update to 109.1 and confirm launch through TestFlight. Microphone/ASR quality, Gemma model load and generation, RE-USE fixed-sample inference and audio improvement, offline behavior, playback interruption handling, thermal behavior, and memory pressure also need physical-device checks.

## Operating and release notes

- Local package tests and quality checks run in Docker (`bash Scripts/test.sh`, `bash Scripts/quality.sh`). iOS Simulator and unsigned archive checks run on GitHub Actions macOS.
- Merging to `main` triggers the protected TestFlight upload workflow. Short version remains 0.1.0; the build number follows `(workflow run number + 100).attempt`. See [TestFlight.md](TestFlight.md).
- Signing secrets remain in the GitHub `ios-testflight` environment. Do not commit user data, model weights, certificates, provisioning profiles, or private keys.
- See [TTS.md](TTS.md), [ASR.md](ASR.md), [LLM.md](LLM.md), and [REUSE.md](REUSE.md) for per-engine revisions, licenses, storage, privacy, and evidence limits.
