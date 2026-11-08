import Foundation

public struct ModelFile: Codable, Sendable {
    public let path: String
    public let sha256: String
    public let size: Int64
    public init(path: String, sha256: String, size: Int64) { self.path = path; self.sha256 = sha256; self.size = size }
}
public struct ModelManifest: Codable, Sendable {
    public let id: String
    public let repository: String
    public let revision: String
    public let storageFolder: String?
    public let files: [ModelFile]
    public var sizeBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    public init(id: String, repository: String, revision: String, files: [ModelFile], storageFolder: String? = nil) {
        self.id = id; self.repository = repository; self.revision = revision; self.files = files; self.storageFolder = storageFolder
    }
    public func validate() throws {
        func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        guard matches(id,"^[a-z0-9-]+$"), matches(repository,"^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$"),
              matches(revision,"^[a-f0-9]{40}$"), !files.isEmpty,
              Set(files.map(\.path)).count == files.count else { throw ModelInstallError.invalidManifest }
        if let storageFolder, !matches(storageFolder,"^[A-Za-z0-9][A-Za-z0-9_-]*$") { throw ModelInstallError.invalidManifest }
        for file in files {
            let components = file.path.split(separator: "/", omittingEmptySubsequences: false)
            guard file.size > 0, matches(file.sha256,"^[a-f0-9]{64}$"), !file.path.hasPrefix("/"),
                  !file.path.contains("\\"), !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  !file.path.contains("%"), !file.path.contains(":"), !file.path.contains("?"), !file.path.contains("#") else { throw ModelInstallError.invalidManifest }
        }
    }
    public func downloadURL(for file: ModelFile) throws -> URL {
        try validate()
        guard files.contains(where: { $0.path == file.path && $0.sha256 == file.sha256 }),
              let url = URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.path)") else { throw ModelInstallError.invalidManifest }
        return url
    }
}
public enum ModelInstallError: Error, LocalizedError {
    case invalidManifest, invalidChecksum, incompleteDownload, missingFiles, busy

    public var errorDescription: String? {
        switch self {
        case .incompleteDownload: "ダウンロードが中断しました。再試行すると保存済みの続きから再開します。"
        default: nil
        }
    }
}

public protocol ModelDownloadProgress: Sendable {
    func report(bytesReceived: Int64) async
}

private struct ManifestFileProgress: ModelDownloadProgress, Sendable {
    let completedBytes: Int64
    let fileSize: Int64
    let totalSize: Int64
    let progress: @Sendable (Double) async -> Void

    func report(bytesReceived: Int64) async {
        let current = completedBytes + min(max(0, bytesReceived), fileSize)
        await progress(min(0.99, Double(current) / Double(totalSize)))
    }
}

/// Verified files and byte-level partials survive interruption; incomplete files never become loadable.
public actor VerifiedModelStore {
    public typealias Download = @Sendable (URL, URL, Int64, any ModelDownloadProgress) async throws -> Void
    public typealias Hash = @Sendable (URL) throws -> String
    private let root: URL
    private let download: Download
    private let hash: Hash
    private var busy = false
    public init(root: URL, download: @escaping Download, sha256: @escaping Hash) {
        self.root = root; self.download = download; self.hash = sha256
    }
    public func directory(_ manifest: ModelManifest) throws -> URL {
        try manifest.validate()
        return root.appendingPathComponent(manifest.id + "-" + manifest.revision)
    }
    private func localURL(_ file: ModelFile, manifest: ModelManifest, directory: URL) -> URL {
        directory.appendingPathComponent("Models").appendingPathComponent(manifest.storageFolder ?? String(manifest.repository.split(separator: "/").last!)).appendingPathComponent(file.path)
    }
    private func partialURL(_ file: ModelFile, directory: URL) -> URL {
        directory.appendingPathComponent(".downloads", isDirectory: true).appendingPathComponent(file.sha256 + ".partial")
    }
    private func valid(_ file: ModelFile, manifest: ModelManifest, in directory: URL) throws -> Bool {
        let url = localURL(file, manifest: manifest, directory: directory)
        guard FileManager.default.fileExists(atPath: url.path),
              (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize == Int(file.size) else { return false }
        return try hash(url) == file.sha256
    }
    public func isInstalled(_ manifest: ModelManifest) throws -> Bool {
        let directory = try directory(manifest)
        return try manifest.files.allSatisfy { try valid($0, manifest: manifest, in: directory) }
    }
    public func install(_ manifest: ModelManifest, progress: @escaping @Sendable (Double) async -> Void) async throws {
        guard !busy else { throw ModelInstallError.busy }
        busy = true; defer { busy = false }
        let directory = try directory(manifest)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed: Int64 = 0
        for file in manifest.files {
            try Task.checkCancellation()
            let destination = localURL(file, manifest: manifest, directory: directory)
            if try !valid(file, manifest: manifest, in: directory) {
                let partial = partialURL(file, directory: directory)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)

                if FileManager.default.fileExists(atPath: partial.path) {
                    let partialSize = (try partial.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                    if partialSize == Int(file.size), try hash(partial) == file.sha256 {
                        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                        try FileManager.default.moveItem(at: partial, to: destination)
                        completed += file.size
                        await progress(Double(completed)/Double(manifest.sizeBytes))
                        continue
                    }
                    if partialSize >= Int(file.size) || partialSize < 0 { try FileManager.default.removeItem(at: partial) }
                }

                let fileProgress = ManifestFileProgress(
                    completedBytes: completed, fileSize: file.size,
                    totalSize: manifest.sizeBytes, progress: progress
                )
                try await download(try manifest.downloadURL(for: file), partial, file.size, fileProgress)
                try Task.checkCancellation()
                let downloadedSize = (try partial.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                guard downloadedSize == Int(file.size) else { throw ModelInstallError.incompleteDownload }
                guard try hash(partial) == file.sha256 else {
                    try? FileManager.default.removeItem(at: partial)
                    throw ModelInstallError.invalidChecksum
                }
                // The file lives under app-owned storage, so no reader sees an unverified replacement.
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.moveItem(at: partial, to: destination)
            }
            completed += file.size
            await progress(Double(completed)/Double(manifest.sizeBytes))
        }
    }
    public func remove(_ manifest: ModelManifest) throws {
        guard !busy else { throw ModelInstallError.busy }
        let directory = try directory(manifest)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
}
