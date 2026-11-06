# Phase 0 investigation (2026-11-06)

Reference snapshot: [Local_LLM_by_using_MobilePhone](https://github.com/Guch1120/Local_LLM_by_using_MobilePhone) commit `78ca70eabcca4647a116dbd7a98172379d3e8bf6`. Read-only shallow checkout excluded from Git. No source copied and no changes made there. Apache-2.0 license observed in the checkout; copying later requires preserving notices and license obligations.

| Reference source | Finding / extraction decision |
|---|---|
| Core/Inference/InferenceBackend.swift | Sendable load/unload/generate/capabilities/metrics contract; useful design for new LLM adapter |
| Backends/LiteRT, Backends/LlamaCpp | Runtime-specific implementation; depends on model configuration/request types and binaries, defer extraction until runtime build is reviewed |
| Core/Models/ModelDownloader.swift | URLSession tasks, progress, resume data and importer callback; UI callbacks and model import policy need separation |
| Core/Models/HuggingFaceClient.swift | Search summaries and gated model handling; Security framework and token handling need dedicated boundary |
| Core/Models/ModelManager.swift | Import/metadata and app configuration responsibilities need decomposition; do not copy wholesale |
| .github/workflows/pull-request.yml | Secretless PR checks followed by macOS Simulator tests |
| .github/workflows/dev-build.yml | Development IPA with device registration and encrypted artifact; this app instead starts with manually provisioned certificate/profile and protected environment |
| scripts/iphone/install_dev_build.sh | Ubuntu USB installation via pymobiledevice3; existing script assumes old bundle ID, repo, branch and private password path. New app needs explicit parameters and isolated tooling |

## Candidate compatibility, not device validation

Primary sources inspected on 2026-11-06:
- [FluidAudio manifest](https://github.com/FluidInference/FluidAudio/blob/main/Package.swift): Swift 6, iOS 17 minimum in inspected manifest. Parakeet/TTS candidates; Core ML binary dependencies mean Linux cannot validate these adapters.
- [swift-tts manifest](https://github.com/arraypress/swift-tts/blob/main/Package.swift): Swift 6, iOS 17; separate Kokoro/Pocket products; manifest pins FluidAudio 0.15.2 but other dependencies use version ranges. This is upstream's dependency, not a version installed here.
- [Argmax manifest](https://github.com/argmaxinc/argmax-oss-swift/blob/main/Package.swift): tools 5.10, iOS 16, WhisperKit product. Repository lists MIT SDK license; model weights require separate review.
- [RE-USE conversion](https://github.com/Corvelis/RE-USE-MLX-CoreML) and [NVIDIA weights](https://huggingface.co/nvidia/NVIDIA-NemotronLabs-RE-USE): candidates only; conversion API, license and memory not verified. No integration or weights downloaded.
- [Gemma 4 runtime documentation](https://developers.google.com/edge/litert-lm/models/gemma-4): designated candidate from specification; integration/version/model size/license remain pending verification.

| Candidate | SDK / weight-license status | Current app status |
|---|---|---|
| Apple speech | OS API; voice download may be required | Playback implemented, real-device offline test pending |
| Kokoro | swift-tts manifest describes Apache-2.0 model; actual selected files require review | No dependency, no weights |
| Pocket TTS | swift-tts manifest describes MIT code, CC BY 4.0 weights; cosette/jean voices CC BY-NC; verify original model cards before selecting voices | No dependency, no weights |
| Parakeet | FluidAudio integration candidate; SDK license and selected model card audit pending | No dependency, no weights |
| WhisperKit | MIT SDK per repository; selected weights separate | No dependency, no weights |
| Gemma E2B/E4B | Runtime compatibility, terms, tokenizer bundle and exact revision pending | Contract/mock only |
| RE-USE | SDK and weight terms pending | Contract only, disabled |

No third-party SDK/weights were added. No iPhone model load, latency, memory or thermal results have been measured. Future integrations must record immutable revisions, exact model files, SHA-256, dependencies, disk sizes, license/NOTICE and real-device results. This table does not certify deployability or commercial use. Full Phase 0 engine feasibility remains open while Phase 1 permits independent UI/data development.
