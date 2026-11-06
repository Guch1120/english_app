#if os(macOS)
import Foundation
import XCTest
import NeuralTTSBackends
import SpeechCore

final class NeuralTTSSmokeTests: XCTestCase, @unchecked Sendable {
    func testRealModelsOnAppleSiliconWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["VOICELEARNING_TTS_SMOKE"] == "1" else {
            throw XCTSkip("Real model download/inference is opt-in; run Validate with tts_smoke=true")
        }
        #if !arch(arm64)
        throw XCTSkip("Real Core ML smoke test requires Apple Silicon")
        #else
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tts-smoke-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NeuralRuntime.modelStore(root: root)
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TTS_SMOKE_OUTPUT"] ?? root.appendingPathComponent("output").path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var measurements: [[String: String]] = []
        for voice in NeuralVoice.allCases {
            let manifest = try voice.manifest()
            try await store.install(manifest, progress: { _ in })
            let installed = try await store.isInstalled(manifest); XCTAssertTrue(installed)
            let backend = NeuralRuntime.backend(voice: voice, directory: try await store.directory(manifest))
            do {
                try await backend.load()
                let start = Date()
                let audio = try await backend.synthesize(SpeechRequest(text: "Please confirm your reservation.", voiceID: voice.speaker))
                defer { try? FileManager.default.removeItem(at: audio.url) }
                let data = try Data(contentsOf: audio.url)
                let elapsed = Date().timeIntervalSince(start), info = try WAVInfo(data: data)
                XCTAssertGreaterThan(info.duration, 0.1)
                XCTAssertEqual(info.sampleRate, 24000)
                XCTAssertTrue(data.dropFirst(44).contains { $0 != 0 }, "Generated audio is all zeros")
                try data.write(to: output.appendingPathComponent(voice.id + ".wav"))
                measurements.append(["engine":voice.id,"revision":manifest.revision,"generationSeconds":String(elapsed),"audioSeconds":String(info.duration),"rtf":String(elapsed/info.duration)])
                await backend.unload()
            } catch { await backend.unload(); throw error }
        }
        try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted,.sortedKeys]).write(to: output.appendingPathComponent("measurements.json"))
        #endif
    }
}
#endif
