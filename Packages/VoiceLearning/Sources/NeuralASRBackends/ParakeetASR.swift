import Foundation
import SpeechCore
import ModelManagement

public enum ParakeetModel {
    public static let id = "parakeet-tdt-ctc-110m"
    public static let title = "Parakeet TDT-CTC 110M"
    public static let license = "CC BY 4.0 · NVIDIA / FluidInference"
    public static var sizeBytes: Int64 { (try? manifest().sizeBytes) ?? 0 }
    public static func manifest() throws -> ModelManifest {
        guard let url = Bundle.module.url(forResource: "parakeet", withExtension: "json") else {
            throw ParakeetASRError.modelUnavailable
        }
        let result = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: url))
        try result.validate()
        return result
    }
}

public enum ParakeetASRError: Error, LocalizedError {
    case modelUnavailable, invalidAudio, unsupportedPlatform, cancelled
    public var errorDescription: String? {
        switch self {
        case .modelUnavailable: return "Parakeetモデルを準備してください。"
        case .invalidAudio: return "録音ファイルを読み込めませんでした。"
        case .unsupportedPlatform: return "この環境ではParakeetを実行できません。"
        case .cancelled: return "文字起こしを中断しました。"
        }
    }
}

#if canImport(FluidAudio)
import FluidAudio
import CryptoKit

public enum NeuralASRRuntime {
    public static func modelStore(root: URL) -> VerifiedModelStore {
        AppLogger.minimumLevel = .fault
        AppLogger.mirrorsToConsole = false
        ModelHub.offlineMode = true
        return VerifiedModelStore(root: root, download: { remote, destination in
            let (temporary, response) = try await URLSession.shared.download(from: remote)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temporary, to: destination)
        }, sha256: { url in
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation(); hash.update(data: chunk)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        })
    }
    public static func backend(directory: URL) -> any ASRService {
        ParakeetTDT110MBackend(directory: directory)
    }
}

public actor ParakeetTDT110MBackend: ASRService {
    public nonisolated let modelID = ParakeetModel.id
    private let directory: URL
    private var manager: AsrManager?
    private var cancelled = false

    public init(directory: URL) {
        self.directory = directory
        AppLogger.minimumLevel = .fault
        AppLogger.mirrorsToConsole = false
        ModelHub.offlineMode = true
    }

    public func load() async throws {
        cancelled = false
        try Task.checkCancellation()
        let models = try AsrModels.loadLocal(from: directory, version: .tdtCtc110m)
        manager = AsrManager(config: ASRConfig(encoderHiddenSize: 512), models: models)
    }

    public func unload() async {
        if let manager { await manager.cleanup() }
        manager = nil
    }

    public func cancel() async { cancelled = true }

    public func transcribe(_ audio: AudioAsset) async throws -> String {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        guard let manager else { throw ParakeetASRError.modelUnavailable }
        var decoder = try TdtDecoderState(decoderLayers: 1)
        let result = try await manager.transcribe(audio.url, decoderState: &decoder)
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        return result.text
    }
}
#endif
