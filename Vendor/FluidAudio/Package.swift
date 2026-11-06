// swift-tools-version: 6.0
// Source snapshot: FluidAudio v0.18.2, e396cf780c4abf8e395087467c0585d3b0d17f68.
// Runtime source is unchanged. Unused LuxTTS G2P data is deliberately not bundled.
import PackageDescription
let package = Package(
    name: "FluidAudio", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "FluidAudio", targets: ["FluidAudio"])],
    targets: [
        .target(name: "FluidAudio", dependencies: ["FastClusterWrapper", "MachTaskSelfWrapper", "NemoTextProcessing", "LuxTtsG2pResources"],
                path: "Sources/FluidAudio", exclude: ["ASR/Parakeet/Unified/benchmark.md"],
                swiftSettings: [.define("TTS"), .define("Diarizer")]),
        .target(name: "LuxTtsG2pResources", path: "Support"),
        .binaryTarget(name: "NemoTextProcessing", url: "https://github.com/FluidInference/text-processing-rs/releases/download/v0.3.1/NemoTextProcessing.xcframework.zip",
                      checksum: "5fa8c10d4ec26c1bb2413125f351a7222a4c68a23b74476680fbada7e26fc6aa"),
        .target(name: "FastClusterWrapper", path: "Sources/FastClusterWrapper", publicHeadersPath: "include"),
        .target(name: "MachTaskSelfWrapper", path: "Sources/MachTaskSelfWrapper", publicHeadersPath: "include")
    ], cxxLanguageStandard: .cxx17)
