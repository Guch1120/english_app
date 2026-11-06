// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VoiceLearning",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: ["LearningCore", "LearningPersistence", "SpeechCore", "TTSBackends", "LLMCore", "ModelManagement", "DeviceDiagnostics"].map {
        .library(name: $0, targets: [$0])
    },
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "LearningCore"),
        .target(name: "LearningPersistence", dependencies: ["LearningCore", "CSQLite"]),
        .target(name: "SpeechCore"),
        .target(name: "TTSBackends", dependencies: ["SpeechCore"]),
        .target(name: "LLMCore", dependencies: ["LearningCore"]),
        .target(name: "ModelManagement"),
        .target(name: "DeviceDiagnostics"),
        .testTarget(name: "VoiceLearningTests", dependencies: ["LearningCore", "LearningPersistence", "SpeechCore", "TTSBackends", "LLMCore", "ModelManagement"])
    ]
)
