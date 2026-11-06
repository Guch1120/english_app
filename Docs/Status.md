# Implementation status

Updated 2026-11-07. Local package tests and quality checks run in Docker; iOS Simulator and archive builds run on GitHub's macOS runners because the development host is Linux.

## Phase implementation

Phases 1–7 are merged in `main`. The implementations and their PR-level checks are summarized below. Phase completion here means the planned code and CI scope is merged; it does not imply that the specification's physical iPhone acceptance checks have passed.

- **Phases 1–4:** the listening, speaking, local persistence, and review foundation is in `main`. See [ASR.md](ASR.md) and [Review.md](Review.md). Phase PRs #8–#10 passed their Docker and macOS CI checks.
- **Phase 5 / LLM:** PR [#11](https://github.com/Guch1120/english_app/pull/11), merged as `fea0620`. Docker quality/tests, macOS package tests, iOS Simulator build/analyze, unsigned archive, and review gate passed in [run 42271561361](https://github.com/Guch1120/english_app/actions/runs/42271561361). TestFlight run [42273707239](https://github.com/Guch1120/english_app/actions/runs/42273707239) uploaded **0.1.0 (107.1)**.
- **Phase 6 / RE-USE audio enhancement:** PR [#12](https://github.com/Guch1120/english_app/pull/12), merged as `307eed8`. Docker quality/tests, macOS package tests, iOS Simulator build/analyze, unsigned archive, and review gate passed in [run 42281103300](https://github.com/Guch1120/english_app/actions/runs/42281103300). TestFlight run [42284154032](https://github.com/Guch1120/english_app/actions/runs/42284154032) uploaded **0.1.0 (108.1)**. The initial on-device launch exposed a missing LiteRT-LM runtime framework.
- **Phase 7 / stabilization:** PR [#13](https://github.com/Guch1120/english_app/pull/13), merged as `62f6d34`, added framework embedding and runtime checks. TestFlight builds **109.1** and **110.1** still crashed at launch: USB crash report `EnglishTrainer-2026-11-07-070851.ips` identifies `Library not loaded: @rpath/CLiteRTLM.framework/CLiteRTLM` and only system search locations. This exposed a missing app Frameworks runpath that the archive checks had not covered.
- **Post-phase launch correction:** PR [#15](https://github.com/Guch1120/english_app/pull/15), merged as `1aceeaf`. It explicitly sets `@executable_path/Frameworks` for Debug and Release and makes the archive check reject missing runpaths. Docker tests and quality checks passed; GitHub macOS package tests, Simulator build, unsigned archive/runtime checks, and review gate passed in [run 42298938833](https://github.com/Guch1120/english_app/actions/runs/42298938833). The merge-triggered TestFlight run [42301285370](https://github.com/Guch1120/english_app/actions/runs/42301285370) succeeded and uploaded **0.1.0 (111.1)**. Apple processing and installation are not yet confirmed.

## Physical iPhone validation

The connected iPhone is an iPhone 16 on iOS 26.4.2. Its latest crash report shows **0.1.0 (110.1)**, which predates the runpath correction. Build **111.1** must be installed and launched before the startup fix is considered device-verified.

USB reads and screenshots work. Remote touchscreen input is unavailable: CoreDevice rejects taps because remote control requires iOS 27 or later. The user must select the processed 111.1 build in TestFlight and confirm the app opens.

The following specification checks still need physical-device evidence: offline study after model download; Kokoro/Pocket synthesis, rate, cache and interruptions; microphone recording and Parakeet/on-device Apple Speech transcription; transcript comparison and review persistence after restart; Gemma E2B validation, lesson generation and model lifecycle; RE-USE fixed-sample gate and comparison; per-model timing/memory; model error recovery; and thermal/memory behavior. See [TTS.md](TTS.md), [ASR.md](ASR.md), [LLM.md](LLM.md), [REUSE.md](REUSE.md), and [Phase7.md](Phase7.md) for details and safeguards.

## Operating and release notes

- Run local tests and quality checks inside Docker with `bash Scripts/test.sh` and `bash Scripts/quality.sh`. Never install the iOS SDK on the Linux host.
- PR CI runs on GitHub macOS for package tests, iOS Simulator build/analyze, unsigned distribution archive checks, and the review gate. Every merge to `main` triggers the protected TestFlight workflow.
- The short version is **0.1.0**. The build number follows `(workflow run number + 100).attempt`. See [TestFlight.md](TestFlight.md).
- Signing secrets remain in the GitHub `ios-testflight` environment. Do not commit learning data, audio, model weights, certificates, provisioning profiles, or private keys.
