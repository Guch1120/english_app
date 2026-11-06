// swift-tools-version: 6.0
import PackageDescription
#if os(Linux)
let neuralPackages: [Package.Dependency] = []
let neuralDependencies: [Target.Dependency] = ["SpeechCore", "ModelManagement"]
#else
let neuralPackages: [Package.Dependency] = [.package(path: "../../Vendor/FluidAudio")]
let neuralDependencies: [Target.Dependency] = ["SpeechCore", "ModelManagement", .product(name: "FluidAudio", package: "FluidAudio")]
#endif
let asrDependencies: [Target.Dependency] = neuralDependencies
#if os(Linux)
let litertPackages: [Package.Dependency] = []
let litertDependencies: [Target.Dependency] = ["LLMCore", "ModelManagement", "DeviceDiagnostics"]
#else
let litertPackages: [Package.Dependency] = [.package(url: "https://github.com/google-ai-edge/LiteRT-LM.git", exact: "0.19.1")]
let litertDependencies: [Target.Dependency] = [
    "LLMCore", "ModelManagement", "DeviceDiagnostics",
    .product(name: "LiteRTLM", package: "LiteRT-LM", condition: .when(platforms: [.iOS]))
]
#endif
let reusePackages: [Package.Dependency] = {
    #if os(Linux)
    []
    #else
    [.package(url: "https://github.com/Corvelis/RE-USE-MLX-CoreML.git", exact: "0.2.0")]
    #endif
}()
let reuseDependencies: [Target.Dependency] = {
    #if os(Linux)
    ["SpeechCore", "ModelManagement"]
    #else
    [
        "SpeechCore", "ModelManagement",
        .product(name: "ReuseKit", package: "re-use-mlx-coreml", condition: .when(platforms: [.iOS])),
        .product(name: "ReuseModelAssets", package: "re-use-mlx-coreml", condition: .when(platforms: [.iOS]))
    ]
    #endif
}()
let package = Package(
    name: "VoiceLearning",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: ["LearningCore", "LearningPersistence", "SpeechCore", "TTSBackends", "NeuralTTSBackends", "NeuralASRBackends", "LLMCore", "ModelManagement", "LiteRTLLMBackend", "AudioEnhancementBackends", "DeviceDiagnostics"].map {
        .library(name: $0, targets: [$0])
    },
    dependencies: neuralPackages + litertPackages + reusePackages,
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "LearningCore"),
        .target(name: "LearningPersistence", dependencies: ["LearningCore", "LLMCore", "CSQLite"]),
        .target(name: "SpeechCore"),
        .target(name: "TTSBackends", dependencies: ["SpeechCore"]),
        .target(name: "NeuralTTSBackends", dependencies: neuralDependencies, resources: [.process("Resources")]),
        .target(name: "NeuralASRBackends", dependencies: asrDependencies, resources: [.process("Resources")]),
        .target(name: "LLMCore", dependencies: ["LearningCore"]),
        .target(name: "ModelManagement"),
        .target(name: "LiteRTLLMBackend", dependencies: litertDependencies),
        .target(name: "AudioEnhancementBackends", dependencies: reuseDependencies, resources: [.process("Resources")]),
        .target(name: "DeviceDiagnostics"),
        .testTarget(name: "VoiceLearningTests", dependencies: ["LearningCore", "LearningPersistence", "SpeechCore", "TTSBackends", "NeuralTTSBackends", "LLMCore", "ModelManagement", "LiteRTLLMBackend", "AudioEnhancementBackends", "DeviceDiagnostics"])
    ]
)
