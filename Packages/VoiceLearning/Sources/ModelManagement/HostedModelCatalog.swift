import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HostedModelCandidate: Sendable, Identifiable, Equatable {
    public let id: String
    public let repository: String
    public let revision: String
    public let filePath: String
    public let sizeBytes: Int64
    public let sha256: String
    public let license: String

    public var displayName: String { "\(repository.split(separator: "/").last ?? Substring(repository)) · \(filePath)" }
    public var manifest: ModelManifest {
        ModelManifest(
            id: id,
            repository: repository,
            revision: revision,
            files: [ModelFile(path: filePath, sha256: sha256, size: sizeBytes)],
            storageFolder: id
        )
    }

    public init(id: String, repository: String, revision: String, filePath: String, sizeBytes: Int64, sha256: String, license: String) {
        self.id = id; self.repository = repository; self.revision = revision; self.filePath = filePath
        self.sizeBytes = sizeBytes; self.sha256 = sha256; self.license = license
    }
}

public enum ModelCatalogError: Error, Equatable {
    case invalidQuery
    case unavailable
    case noCompatibleFiles
    case invalidModelMetadata
}

/// Hugging Face search is limited to reviewed LiteRT-LM artifacts published by LiteRT Community.
/// No Python, Jinja, tokenizer, or arbitrary repository files are installed or executed.
public struct HostedModelCatalog: Sendable {
    private let session: URLSession
    private let maximumModelSizeBytes: Int64
    public init(session: URLSession = .shared, maximumModelSizeBytes: Int64 = 6_000_000_000) {
        self.session = session; self.maximumModelSizeBytes = maximumModelSizeBytes
    }

    private struct SearchItem: Decodable {
        let id: String
        let library_name: String?
    }
    private struct Repository: Decodable {
        struct File: Decodable {
            struct LFS: Decodable { let sha256: String?; let size: Int64? }
            let rfilename: String
            let size: Int64?
            let lfs: LFS?
        }
        let id: String
        let sha: String
        let library_name: String?
        let cardData: CardData?
        let siblings: [File]
        struct CardData: Decodable { let license: String? }
    }

    public func search(_ query: String, limit: Int = 20) async throws -> [HostedModelCandidate] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { throw ModelCatalogError.invalidQuery }
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "search", value: normalized),
            URLQueryItem(name: "library", value: "litert-lm"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 30)))
        ]
        guard let url = components.url else { throw ModelCatalogError.invalidQuery }
        let items: [SearchItem] = try await get(url)
        let repositories = items.filter { $0.library_name == "litert-lm" && $0.id.hasPrefix("litert-community/") }
        var candidates: [HostedModelCandidate] = []
        for item in repositories {
            try Task.checkCancellation()
            guard let repository = try? await details(item.id) else { continue }
            candidates.append(contentsOf: try makeCandidates(from: repository))
        }
        guard !candidates.isEmpty else { return [] }
        return candidates.sorted { left, right in
            if left.repository.contains("gemma-4-E2B") != right.repository.contains("gemma-4-E2B") {
                return left.repository.contains("gemma-4-E2B")
            }
            return left.filePath < right.filePath
        }
    }

    public func recommendedGemma4E2B() async throws -> [HostedModelCandidate] {
        let repository = try await details("litert-community/gemma-4-E2B-it-litert-lm")
        return try makeCandidates(from: repository).filter { $0.filePath == "gemma-4-E2B-it.litertlm" || $0.filePath == "gemma-4-E2B-it-gpu.litertlm" }
    }

    private func details(_ id: String) async throws -> Repository {
        guard id.hasPrefix("litert-community/"), id.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil,
              let url = URL(string: "https://huggingface.co/api/models/\(id)/revision/main?blobs=true") else {
            throw ModelCatalogError.invalidModelMetadata
        }
        let repository: Repository = try await get(url)
        guard repository.id == id, repository.library_name == "litert-lm",
              repository.sha.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil else {
            throw ModelCatalogError.invalidModelMetadata
        }
        return repository
    }

    private func makeCandidates(from repository: Repository) throws -> [HostedModelCandidate] {
        guard repository.id.hasPrefix("litert-community/"), repository.library_name == "litert-lm",
              repository.cardData?.license?.lowercased() == "apache-2.0" else {
            throw ModelCatalogError.invalidModelMetadata
        }
            let repoSlug = String(repository.id.split(separator: "/").last ?? Substring(repository.id)).lowercased()
        return repository.siblings.compactMap { file in
            guard file.rfilename.hasSuffix(".litertlm"),
                  file.rfilename.range(of: "^[A-Za-z0-9_.-]+\\.litertlm$", options: .regularExpression) != nil,
                  let size = file.lfs?.size ?? file.size, size > 0, size <= maximumModelSizeBytes,
                  let digest = file.lfs?.sha256,
                  digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
            let fileSlug = file.rfilename.dropLast(".litertlm".count).lowercased()
            let id = "\(repoSlug)-\(fileSlug)".replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
            return HostedModelCandidate(
                id: id, repository: repository.id, revision: repository.sha, filePath: file.rfilename,
                sizeBytes: size, sha256: digest, license: "Apache-2.0"
            )
        }
    }

    private func get<Value: Decodable>(_ url: URL) async throws -> Value {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("EnglishTrainer/1.0 (on-device model catalog)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw ModelCatalogError.unavailable
            }
            return try JSONDecoder().decode(Value.self, from: data)
        } catch let error as ModelCatalogError { throw error }
        catch { throw ModelCatalogError.unavailable }
    }
}
