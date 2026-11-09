import Foundation
import SpeechCore
import ModelManagement

public enum NeuralSpeaker: String, CaseIterable, Identifiable, Sendable {
    case heart = "af_heart", bella = "af_bella", michael = "am_michael", alba
    public var id: String { rawValue }
    public var engine: NeuralVoice { self == .alba ? .pocket : .kokoro }
    public var title: String {
        switch self {
        case .heart: "Heart（米国英語）"
        case .bella: "Bella（米国英語）"
        case .michael: "Michael（米国英語）"
        case .alba: "Alba（英語）"
        }
    }
    /// Optional voices have isolated storage: removing one cannot remove the base model.
    public var supplementalManifest: ModelManifest? {
        let size: Int64, hash: String
        switch self {
        case .bella: size = 2678538; hash = "e7bdbe207b927d1e59556dcda69b976cbbdc87be5e4affeea5bf030fca80e55c"
        case .michael: size = 2667552; hash = "ec6e03f1fc30c11020ade45f587a64e1b8c51c08e8ab6f59bdf089f410c2b924"
        default: return nil
        }
        return ModelManifest(id: "kokoro-" + rawValue.replacingOccurrences(of: "_", with: "-"),
            repository: "FluidInference/kokoro-82m-coreml", revision: "2568276a60ff6e7f312afce3dc9e3f07521cb48d",
            files: [ModelFile(path: "voices/\(rawValue).json", sha256: hash, size: size)],
            storageFolder: "kokoro-voice-" + rawValue)
    }
}

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
    public static func backend(voice: NeuralVoice, directory: URL, speaker: NeuralSpeaker? = nil, speakerDirectory: URL? = nil) -> any TTSService {
        FluidTTSBackend(voice: voice, directory: directory, speaker: speaker, speakerDirectory: speakerDirectory)
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
    private let speaker: NeuralSpeaker
    private let speakerDirectory: URL?
    private var kokoro: KokoroAneManager?
    private var pocket: PocketTtsManager?
    private var cancelled = false
    public init(voice: NeuralVoice, directory: URL, speaker: NeuralSpeaker? = nil, speakerDirectory: URL? = nil) {
        NeuralRuntime.configure(); self.voice = voice; self.modelID = voice.id; self.directory = directory
        self.speaker = speaker ?? (voice == .kokoro ? .heart : .alba)
        self.speakerDirectory = speakerDirectory
    }
    public func load() async throws {
        cancelled = false; try Task.checkCancellation()
        guard speaker.engine == voice else { throw NeuralTTSError.invalidVoice }
        if voice == .kokoro {
            // FluidAudio keeps the ANE chain and shared English frontend in separate
            // repository folders. Both are copied only from the verified manifest tree.
            let models = directory.appendingPathComponent("Models")
            if let manifest = speaker.supplementalManifest {
                guard let speakerDirectory else { throw NeuralTTSError.modelsMissing }
                let source = speakerDirectory.appendingPathComponent("Models").appendingPathComponent(manifest.storageFolder!).appendingPathComponent(manifest.files[0].path)
                let pack = try KokoroAneVoicePack.load(fromJSON: Data(contentsOf: source))
                let target = models.appendingPathComponent("kokoro-82m-coreml/ANE/\(speaker.id).bin")
                try pack.binaryData.write(to: target, options: .atomic)
            }
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
        await ModelRuntimeCoordinator.shared.didLoad(modelID)
    }
    public func unload() async {
        if let kokoro { await kokoro.cleanup() }
        if let pocket { await pocket.cleanup() }
        kokoro = nil; pocket = nil
        await ModelRuntimeCoordinator.shared.didUnload(modelID)
    }
    public func cancel() async { cancelled = true }
    public func synthesizeData(_ text: String) async throws -> Data {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        let data: Data
        if let kokoro { data = try await kokoro.synthesize(text: text, voice: speaker.id, speed: 1) }
        else if let pocket { data = try await pocket.synthesize(text: text, voice: "alba") }
        else { throw NeuralTTSError.modelsMissing }
        try Task.checkCancellation(); if cancelled { throw CancellationError() }
        return data
    }
    public func synthesize(_ request: SpeechRequest) async throws -> AudioAsset {
        guard request.voiceID == speaker.id else { throw NeuralTTSError.invalidVoice }
        let data = try await synthesizeData(request.text), info = try WAVInfo(data: data)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        try data.write(to: url, options: .atomic)
        return AudioAsset(url: url, duration: info.duration, sampleRate: info.sampleRate)
    }
}
#endif
