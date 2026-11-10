import Foundation
public enum ModelKind: String, Codable, Sendable { case tts, asr, llm, enhancement }
public struct ModelDescriptor: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: ModelKind
    public let runtime: String
    public let verifiedOnDevice: Bool
    public let developer: String?
    public let languages: [String]
    public let version: String?
    public let minimumOS: String?
    public let license: String?
    public let capabilities: [String]
    public let manifest: ModelManifest?
    public let downloadSource: URL?
    public let verificationSummary: String?
    public var sizeBytes: Int64? { manifest?.sizeBytes }
    public init(id: String, name: String, kind: ModelKind, runtime: String, verifiedOnDevice: Bool = false,
                developer: String? = nil, languages: [String] = [], version: String? = nil,
                minimumOS: String? = nil, license: String? = nil, capabilities: [String] = [],
                manifest: ModelManifest? = nil, downloadSource: URL? = nil, verificationSummary: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.runtime = runtime; self.verifiedOnDevice = verifiedOnDevice
        self.developer = developer; self.languages = languages; self.version = version; self.minimumOS = minimumOS
        self.license = license; self.capabilities = capabilities; self.manifest = manifest
        self.downloadSource = downloadSource; self.verificationSummary = verificationSummary
    }
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, runtime, verifiedOnDevice, developer, languages, version, minimumOS, license
        case capabilities, manifest, downloadSource, verificationSummary
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id); name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(ModelKind.self, forKey: .kind); runtime = try values.decode(String.self, forKey: .runtime)
        verifiedOnDevice = try values.decodeIfPresent(Bool.self, forKey: .verifiedOnDevice) ?? false
        developer = try values.decodeIfPresent(String.self, forKey: .developer)
        languages = try values.decodeIfPresent([String].self, forKey: .languages) ?? []
        version = try values.decodeIfPresent(String.self, forKey: .version)
        minimumOS = try values.decodeIfPresent(String.self, forKey: .minimumOS)
        license = try values.decodeIfPresent(String.self, forKey: .license)
        capabilities = try values.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        manifest = try values.decodeIfPresent(ModelManifest.self, forKey: .manifest)
        downloadSource = try values.decodeIfPresent(URL.self, forKey: .downloadSource)
        verificationSummary = try values.decodeIfPresent(String.self, forKey: .verificationSummary)
    }
}
public enum RuntimeError: Error { case busy }
public enum ModelOperationFailure: String, Sendable { case operationFailed }
public struct ModelRuntimeSnapshot: Sendable {
    public let activeModelID: String?
    /// Successful SDK load until unload; this is not physical RAM residency or model-only memory.
    public let loadedModelIDs: Set<String>
    public let failures: [String: ModelOperationFailure]
}
/// One large-model lease at a time. Hold the lease across load, inference and unload.
public actor ModelRuntimeCoordinator {
    public static let shared = ModelRuntimeCoordinator()
    private var active: UUID?
    private var activeModelID: String?
    private var loadedModelIDs: Set<String> = []
    private var failures: [String: ModelOperationFailure] = [:]
    public init() {}
    public func snapshot() -> ModelRuntimeSnapshot {
        ModelRuntimeSnapshot(activeModelID: activeModelID, loadedModelIDs: loadedModelIDs, failures: failures)
    }
    public func didLoad(_ id: String) { loadedModelIDs.insert(id) }
    public func didUnload(_ id: String) { loadedModelIDs.remove(id) }
    public func withExclusiveModel<T: Sendable>(modelID: String? = nil, _ operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        guard active == nil else { throw RuntimeError.busy }
        let lease = UUID(); active = lease; activeModelID = modelID
        defer { if active == lease { active = nil; activeModelID = nil } }
        try Task.checkCancellation()
        do {
            let value = try await operation()
            if let modelID { failures.removeValue(forKey: modelID) }
            return value
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            if let modelID { failures[modelID] = .operationFailed }
            throw error
        }
    }
}
