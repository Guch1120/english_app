import Foundation
import SpeechCore

public struct REUSEStorageStatus: Sendable, Equatable {
    public let isInstalled: Bool
    public let storedBytes: Int64
    public let compiledBytes: Int64
}

public enum REUSEError: Error, Equatable {
    case unavailable
    case modelMissing
}

#if canImport(ReuseKit) && canImport(ReuseModelAssets)
import ReuseKit
import ReuseModelAssets

/// On-device NVIDIA RE-USE using the pinned Apple Silicon conversion.
public actor REUSEAudioEnhancement: MeasuredAudioEnhancementService {
    public nonisolated let modelID = "nvidia-reuse-apple-0.2.0"
    public static let modelSizeBytes: Int64 = 54_206_689
    public static let modelRevision = "4b7e50680ba34f10865cab7e24054262596f5ab4"
    public static let verificationKey = "reuse-device-verified-\(modelRevision)"

    private let store: ReuseModelStore
    private let source: ReuseModelSource
    private let applicationSupportDirectory: URL
    private var engine: ReuseEngine?
    private var metrics: AudioEnhancementMetrics?

    public init(applicationSupportDirectory: URL, cachesDirectory: URL) throws {
        let catalogURL = try Self.resource("ModelCatalog", extension: "json")
        let sourceURL = try Self.resource("ModelSource", extension: "json")
        let catalog = try JSONDecoder().decode(ReuseModelCatalog.self, from: Data(contentsOf: catalogURL))
        let sourceConfiguration = try JSONDecoder().decode(ModelSourceConfiguration.self, from: Data(contentsOf: sourceURL))
        store = try ReuseModelStore(catalog: catalog, applicationSupportDirectory: applicationSupportDirectory,
                                    cachesDirectory: cachesDirectory)
        self.applicationSupportDirectory = applicationSupportDirectory
        source = try ReuseModelSource(huggingFaceRepository: sourceConfiguration.repository,
                                      revision: sourceConfiguration.revision)
    }

    public func storageStatus() throws -> REUSEStorageStatus {
        let value = try store.inspect()
        return REUSEStorageStatus(isInstalled: value.isInstalled, storedBytes: value.storedBytes,
                                  compiledBytes: value.compiledBytes)
    }

    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await store.download(from: source) { update in progress(update.fraction) }
    }

    public func removeModel() async throws {
        await unload()
        try await store.remove()
        metrics = nil
    }

    public func load() async throws {
        try Task.checkCancellation()
        guard try await store.inspect().isInstalled else { throw REUSEError.modelMissing }
        guard engine == nil else { return }
        engine = ReuseEngine(modelPack: ReuseModelPack(root: store.installedModelDirectory),
                             cacheDirectory: store.compilationCacheDirectory)
    }

    public func unload() async {
        if let engine { await engine.release() }
        engine = nil
    }

    public func cancel() async {
        await unload()
    }

    public func enhance(_ audio: AudioAsset) async throws -> AudioAsset {
        guard let engine else { throw REUSEError.modelMissing }
        try Task.checkCancellation()
        let prepared = try ReuseAudioFile.read(audio.url, maximumSeconds: 300)
        let result = try await engine.enhance(prepared.samples, mode: .hybrid)
        try Task.checkCancellation()
        let output = audio.url.deletingLastPathComponent().appendingPathComponent("reuse-latest.wav", isDirectory: false)
        let temporary = audio.url.deletingLastPathComponent().appendingPathComponent("reuse-\(UUID().uuidString).partial.wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try ReuseAudioFile.write(result.samples, to: temporary)
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try FileManager.default.moveItem(at: temporary, to: output)
        metrics = AudioEnhancementMetrics(modelLoadSeconds: result.metrics.modelLoadSeconds,
                                          processingSeconds: result.metrics.processingSeconds,
                                          realTimeFactor: result.metrics.rtf,
                                          peakMemoryBytes: result.metrics.mlxPeakBytes)
        return AudioAsset(url: output, duration: result.metrics.inputSeconds, sampleRate: 16_000)
    }

    public func enhancementMetrics() async -> AudioEnhancementMetrics? { metrics }

    public func verifyOnDevice() async throws -> AudioEnhancementMetrics {
        try await load()
        let verificationDirectory = applicationSupportDirectory.appendingPathComponent("REUSEVerification", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: verificationDirectory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            defer { try? FileManager.default.removeItem(at: verificationDirectory) }
            let sampleURL = try Self.resource("sample_noisy", extension: "wav")
            let sample = try ReuseAudioFile.read(sampleURL, maximumSeconds: 30)
            let writableSampleURL = verificationDirectory.appendingPathComponent("sample_noisy.wav")
            try FileManager.default.copyItem(at: sampleURL, to: writableSampleURL)
            let input = AudioAsset(url: writableSampleURL, duration: sample.info.preparedSeconds, sampleRate: 16_000)
            let enhanced = try await enhance(input)
            defer { try? FileManager.default.removeItem(at: enhanced.url) }
            let output = try ReuseAudioFile.read(enhanced.url, maximumSeconds: 30)
            guard output.samples.count == sample.samples.count,
                  let metrics = await enhancementMetrics(), metrics.processingSeconds > 0,
                  metrics.realTimeFactor.isFinite, metrics.realTimeFactor > 0 else {
                throw REUSEError.unavailable
            }
            await unload()
            return metrics
        } catch {
            await unload()
            throw error
        }
    }

    public static var thirdPartyNotices: String { resourceText("ThirdPartyNotices") }
    public static var modelLicense: String { resourceText("NVIDIA-RE-USE") }

    private static func resource(_ name: String, extension ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else { throw REUSEError.unavailable }
        return url
    }

    private static func resourceText(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    private struct ModelSourceConfiguration: Decodable {
        let repository: String
        let revision: String
    }
}
#else
/// The inference runtime is unavailable outside supported iOS devices.
public actor REUSEAudioEnhancement: MeasuredAudioEnhancementService {
    public nonisolated let modelID = "nvidia-reuse-unavailable"
    public static let modelSizeBytes: Int64 = 0
    public static let modelRevision = "unavailable"
    public static let verificationKey = "reuse-device-verified-unavailable"
    public init(applicationSupportDirectory: URL, cachesDirectory: URL) throws {}
    public func storageStatus() throws -> REUSEStorageStatus { throw REUSEError.unavailable }
    public func download(progress: @escaping @Sendable (Double) -> Void) async throws { throw REUSEError.unavailable }
    public func removeModel() async throws { throw REUSEError.unavailable }
    public func load() async throws { throw REUSEError.unavailable }
    public func unload() async {}
    public func cancel() async {}
    public func enhance(_ audio: AudioAsset) async throws -> AudioAsset { throw REUSEError.unavailable }
    public func enhancementMetrics() async -> AudioEnhancementMetrics? { nil }
    public func verifyOnDevice() async throws -> AudioEnhancementMetrics { throw REUSEError.unavailable }
    public static var thirdPartyNotices: String { "" }
    public static var modelLicense: String { "" }
}
#endif
