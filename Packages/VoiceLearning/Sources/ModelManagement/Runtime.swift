import Foundation
public enum ModelKind: String, Codable, Sendable { case tts, asr, llm, enhancement }
public struct ModelDescriptor: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: ModelKind
    public let runtime: String
    public let verifiedOnDevice: Bool
    public init(id: String, name: String, kind: ModelKind, runtime: String, verifiedOnDevice: Bool = false) {
        self.id = id; self.name = name; self.kind = kind; self.runtime = runtime; self.verifiedOnDevice = verifiedOnDevice
    }
}
public enum RuntimeError: Error { case busy }
/// One large-model lease at a time. Hold the lease across load, inference and unload.
public actor ModelRuntimeCoordinator {
    public static let shared = ModelRuntimeCoordinator()
    private var active: UUID?
    public init() {}
    public func withExclusiveModel<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        guard active == nil else { throw RuntimeError.busy }
        let lease = UUID(); active = lease
        defer { if active == lease { active = nil } }
        try Task.checkCancellation()
        return try await operation()
    }
}
