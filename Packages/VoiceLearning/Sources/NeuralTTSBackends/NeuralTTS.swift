import Foundation
import SpeechCore
import ModelManagement

public enum NeuralVoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case kokoro, pocket
    public var id: String { rawValue }
    public var title: String { self == .kokoro ? "Kokoro-82M" : "Pocket TTS" }
    public var speaker: String { self == .kokoro ? "af_heart" : "alba" }
    public var license: String { self == .kokoro ? "Apache-2.0 · hexgrad / FluidInference" : "CC BY 4.0 · Kyutai / Alba MacKenna / FluidInference" }
    public static var licenseNotices: String {
        guard let root = Bundle.module.resourceURL else { return "" }
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files.filter { ["txt","md"].contains($0.pathExtension) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n\n")
    }
    public func manifest() throws -> ModelManifest {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "json") else { throw NeuralTTSError.modelsMissing }
        let result = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: url))
        try result.validate(); return result
    }
}
public enum NeuralTTSError: Error, LocalizedError {
    case modelsMissing, invalidVoice, cancelled, unsupportedPlatform
    public var errorDescription: String? {
        switch self {
        case .modelsMissing: return "設定の音声モデル管理から、モデルを準備してください。"
        case .invalidVoice: return "このモデルでは指定の話者を利用できません。"
        case .cancelled: return "音声生成を中断しました。"
        case .unsupportedPlatform: return "この端末ではCore ML音声生成を実行できません。"
        }
    }
}

#if canImport(FluidAudio)
import FluidAudio
import CryptoKit

public enum NeuralRuntime {
    private static let configured: Void = {
        // No inference text in either the Debug console or routine unified logging.
        AppLogger.minimumLevel = .fault
        AppLogger.mirrorsToConsole = false
        // Downloads belong to the app's immutable, checksum-verified manifest pipeline.
        ModelHub.offlineMode = true
    }()
    public static func configure() { _ = configured }
    public static func backend(voice: NeuralVoice, directory: URL) -> any TTSService {
        FluidTTSBackend(voice: voice, directory: directory)
    }
    public static func modelStore(root: URL) -> VerifiedModelStore {
        configure()
        return VerifiedModelStore(root: root, download: { remote, destination, expectedSize, progress in
            try await URLSessionModelDownloader.download(from: remote, to: destination, expectedSize: expectedSize, progress: progress)
        }, sha256: { url in
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation(); hash.update(data: chunk)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        })
    }
}
public actor FluidTTSBackend: TTSService {
    public nonisolated let modelID: String
    private let voice: NeuralVoice
    private let directory: URL
    private var kokoro: KokoroAneManager?
    private var pocket: PocketTtsManager?
    private var cancelled = false
    public init(voice: NeuralVoice, directory: URL) {
        NeuralRuntime.configure(); self.voice = voice; self.modelID = voice.id; self.directory = directory
    }
    public func load() async throws {
        cancelled = false; try Task.checkCancellation()
        if voice == .kokoro {
            // FluidAudio keeps the ANE chain and shared English frontend in separate
            // repository folders. Both are copied only from the verified manifest tree.
            let models = directory.appendingPathComponent("Models")
            let frontend = models.appendingPathComponent("kokoro")
            try FileManager.default.createDirectory(at: frontend, withIntermediateDirectories: true)
            for name in ["G2PEncoder.mlmodelc", "G2PDecoder.mlmodelc", "g2p_vocab.json", "us_lexicon_cache.json"] {
                let destination = frontend.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: models.appendingPathComponent("kokoro-82m-coreml").appendingPathComponent(name), to: destination)
            }
            let manager = KokoroAneManager(directory: models)
            kokoro = manager
            try await manager.initialize()
        } else {
            let manager = PocketTtsManager(defaultVoice: "alba", language: .english2026Apr, directory: directory, precision: .fp16, placement: .gpu)
            pocket = manager
            try await manager.initialize()
        }
        try Task.checkCancellation(); if cancelled { throw CancellationError() }
    }
    public func unload() async {
        if let kokoro { await kokoro.cleanup() }
        if let pocket { await pocket.cleanup() }
        kokoro = nil; pocket = nil
    }
    public func cancel() async { cancelled = true }
    public func synthesizeData(_ text: String) async throws -> Data {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        let data: Data
        if let kokoro { data = try await kokoro.synthesize(text: text, voice: "af_heart", speed: 1) }
        else if let pocket { data = try await pocket.synthesize(text: text, voice: "alba") }
        else { throw NeuralTTSError.modelsMissing }
        try Task.checkCancellation(); if cancelled { throw CancellationError() }
        return data
    }
    public func synthesize(_ request: SpeechRequest) async throws -> AudioAsset {
        guard request.voiceID == voice.speaker else { throw NeuralTTSError.invalidVoice }
        let data = try await synthesizeData(request.text), info = try WAVInfo(data: data)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        try data.write(to: url, options: .atomic)
        return AudioAsset(url: url, duration: info.duration, sampleRate: info.sampleRate)
    }
}
#endif
