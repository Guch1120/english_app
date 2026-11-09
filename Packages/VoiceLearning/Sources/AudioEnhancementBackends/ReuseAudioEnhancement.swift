import Foundation
import SpeechCore
import ModelManagement

/// Metadata remains available without the inference SDK; it never enables an unsupported engine.
public enum REUSECatalogInformation {
    public static func manifest() throws -> ModelManifest {
        struct Catalog: Decodable {
            struct File: Decodable { let path: String; let bytes: Int64; let sha256: String }
            let files: [File]
        }
        struct Source: Decodable { let repository: String; let revision: String }
        guard let catalogURL = Bundle.module.url(forResource: "ModelCatalog", withExtension: "json"),
              let sourceURL = Bundle.module.url(forResource: "ModelSource", withExtension: "json") else { throw REUSEError.modelMissing }
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
        let source = try JSONDecoder().decode(Source.self, from: Data(contentsOf: sourceURL))
        let result = ModelManifest(id: "reuse-\(source.revision)", repository: source.repository, revision: source.revision,
            files: catalog.files.map { ModelFile(path: $0.path, sha256: $0.sha256, size: $0.bytes) }, storageFolder: "model-pack")
        try result.validate(); return result
    }
}

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
import CryptoKit
import ReuseKit
import ReuseModelAssets

/// On-device NVIDIA RE-USE using the pinned Apple Silicon conversion.
public actor REUSEAudioEnhancement: MeasuredAudioEnhancementService {
    public nonisolated let modelID = "nvidia-reuse-apple-0.2.0"
    public static let modelSizeBytes: Int64 = 54_206_689
    public static let modelRevision = "4b7e50680ba34f10865cab7e24054262596f5ab4"
    public static let verificationKey = "reuse-device-verified-\(modelRevision)"

    private let store: ReuseModelStore
    private let transferStore: VerifiedModelStore
    private let transferManifest: ModelManifest
    private let applicationSupportDirectory: URL
    private var engine: ReuseEngine?
    private var metrics: AudioEnhancementMetrics?

    public init(applicationSupportDirectory: URL, cachesDirectory: URL) throws {
        let catalogURL = try Self.resource("ModelCatalog", extension: "json")
        let catalog = try JSONDecoder().decode(ReuseModelCatalog.self, from: Data(contentsOf: catalogURL))
        store = try ReuseModelStore(catalog: catalog, applicationSupportDirectory: applicationSupportDirectory,
                                    cachesDirectory: cachesDirectory)
        self.applicationSupportDirectory = applicationSupportDirectory
        let modelRoot = store.installedModelDirectory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var excludedModelRoot = modelRoot
        var modelRootValues = URLResourceValues(); modelRootValues.isExcludedFromBackup = true
        try excludedModelRoot.setResourceValues(modelRootValues)
        let manifest = try REUSECatalogInformation.manifest()
        try manifest.validate()
        transferManifest = manifest
        let transferRoot = applicationSupportDirectory.appendingPathComponent("REUSEDownloads", isDirectory: true)
        try FileManager.default.createDirectory(at: transferRoot, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var protectedRoot = transferRoot
        var resourceValues = URLResourceValues(); resourceValues.isExcludedFromBackup = true
        try protectedRoot.setResourceValues(resourceValues)
        transferStore = VerifiedModelStore(root: transferRoot, download: { remote, destination, expectedSize, progress in
            try await URLSessionModelDownloader.download(from: remote, to: destination,
                expectedSize: expectedSize, progress: progress)
        }, sha256: Self.sha256)
    }

    public func storageStatus() async throws -> REUSEStorageStatus {
        let value = try await store.inspect()
        let transferDirectory = try await transferStore.directory(transferManifest)
        let partialBytes = Self.bytes(in: transferDirectory)
        return REUSEStorageStatus(isInstalled: value.isInstalled, storedBytes: value.storedBytes + partialBytes,
                                  compiledBytes: value.compiledBytes)
    }

    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        if try await store.inspect().isInstalled {
            try? await transferStore.remove(transferManifest)
            progress(1)
            return
        }
        try await transferStore.install(transferManifest) { fraction in progress(fraction * 0.85) }
        try Task.checkCancellation()

        let transferDirectory = try await transferStore.directory(transferManifest)
        let verifiedModelPack = transferDirectory.appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("model-pack", isDirectory: true)
        let destination = store.installedModelDirectory
        let incoming = destination.deletingLastPathComponent().appendingPathComponent("incoming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: incoming.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: verifiedModelPack, to: incoming)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: incoming, to: destination)
        guard try await store.inspect().isInstalled else { throw REUSEError.modelMissing }
        try await transferStore.remove(transferManifest)
        progress(1)
    }

    public func removeModel() async throws {
        await unload()
        try await store.remove()
        try await transferStore.remove(transferManifest)
        metrics = nil
    }

    public func load() async throws {
        try Task.checkCancellation()
        guard try await store.inspect().isInstalled else { throw REUSEError.modelMissing }
        guard engine == nil else { return }
        engine = ReuseEngine(modelPack: ReuseModelPack(root: store.installedModelDirectory),
                             cacheDirectory: store.compilationCacheDirectory)
        await ModelRuntimeCoordinator.shared.didLoad(modelID)
    }

    public func unload() async {
        if let engine { await engine.release() }
        engine = nil
        await ModelRuntimeCoordinator.shared.didUnload(modelID)
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

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func bytes(in directory: URL) -> Int64 {
        guard let items = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        return items.reduce(Int64(0)) { total, item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { return total }
            return total + Int64(values.fileSize ?? 0)
        }
    }

    private static func resource(_ name: String, extension ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else { throw REUSEError.unavailable }
        return url
    }

    private static func resourceText(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
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
    public func storageStatus() async throws -> REUSEStorageStatus { throw REUSEError.unavailable }
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
