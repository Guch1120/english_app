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
let package = Package(
    name: "VoiceLearning",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: ["LearningCore", "LearningPersistence", "SpeechCore", "TTSBackends", "NeuralTTSBackends", "NeuralASRBackends", "LLMCore", "ModelManagement", "DeviceDiagnostics"].map {
        .library(name: $0, targets: [$0])
    },
    dependencies: neuralPackages,
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "LearningCore"),
        .target(name: "LearningPersistence", dependencies: ["LearningCore", "CSQLite"]),
        .target(name: "SpeechCore"),
        .target(name: "TTSBackends", dependencies: ["SpeechCore"]),
        .target(name: "NeuralTTSBackends", dependencies: neuralDependencies, resources: [.process("Resources")]),
        .target(name: "NeuralASRBackends", dependencies: asrDependencies, resources: [.process("Resources")]),
        .target(name: "LLMCore", dependencies: ["LearningCore"]),
        .target(name: "ModelManagement"),
        .target(name: "DeviceDiagnostics"),
        .testTarget(name: "VoiceLearningTests", dependencies: ["LearningCore", "LearningPersistence", "SpeechCore", "TTSBackends", "NeuralTTSBackends", "LLMCore", "ModelManagement"])
    ]
)
