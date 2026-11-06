import Foundation
import Observation
import CryptoKit
import LLMCore
import ModelManagement
import LiteRTLLMBackend
import LearningCore
import LearningPersistence

@MainActor @Observable final class LLMTrainingModel {
    var query = "gemma-4-E2B"
    var candidates: [HostedModelCandidate] = []
    var selectedID: String?
    var installedIDs = Set<String>()
    var status = ""
    var error: String?
    var progress = 0.0
    var busy = false
    var latestMetrics: LLMInferenceMetrics?
    private let catalog = HostedModelCatalog()
    private let service = LiteRTLLMService()
    private let coordinator = ModelRuntimeCoordinator.shared
    private let store: VerifiedModelStore
    private let modelRoot: URL
    private var operation: Task<Void, Never>?

    init() {
        let resolvedRoot: URL
        let resolvedStore: VerifiedModelStore
        var initializationError: String?
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let root = support.appendingPathComponent("LLMModels", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var protectedRoot = root
            try? protectedRoot.setResourceValues(values)
            resolvedRoot = root
            resolvedStore = Self.makeStore(root: root)
        } catch {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("EnglishTrainerModels")
            resolvedRoot = fallback
            resolvedStore = Self.makeStore(root: fallback)
            initializationError = "モデル保存領域を準備できませんでした: \(error.localizedDescription)"
        }
        modelRoot = resolvedRoot
        store = resolvedStore
        selectedID = UserDefaults.standard.string(forKey: "selected-llm-model")
        error = initializationError
    }

    private static func makeStore(root: URL) -> VerifiedModelStore {
        VerifiedModelStore(root: root, download: { source, destination in
            let (temporary, response) = try await URLSession.shared.download(from: source)
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

    func search() {
        guard !busy else { return }
        busy = true; status = "対応モデルを検索しています…"; error = nil
        operation = Task {
            do {
                var found = try await catalog.search(query)
                if query.localizedCaseInsensitiveContains("gemma"), !found.contains(where: { $0.repository.contains("gemma-4-E2B") }) {
                    found += try await catalog.recommendedGemma4E2B()
                }
                candidates = found
                for candidate in candidates {
                    if (try? await store.isInstalled(candidate.manifest)) == true { installedIDs.insert(candidate.id) }
                }
                if selectedID == nil, let defaultModel = candidates.first(where: { $0.repository.contains("gemma-4-E2B") && $0.filePath == "gemma-4-E2B-it.litertlm" }) {
                    select(defaultModel)
                }
                status = candidates.isEmpty ? "対応するLiteRT-LMモデルが見つかりませんでした。" : "\(candidates.count)件のモデルファイルが見つかりました。"
            } catch { self.error = "モデル検索に失敗しました: \(error.localizedDescription)" }
            busy = false; operation = nil
        }
    }

    func install(_ candidate: HostedModelCandidate) {
        guard !busy else { return }
        busy = true; progress = 0; error = nil; status = "モデルのダウンロードを開始しています…"
        operation = Task {
            do {
                let values = try modelRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                if let available = values.volumeAvailableCapacityForImportantUsage,
                   available < candidate.sizeBytes + 400_000_000 {
                    throw NSError(domain: "LLMModelStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "空き容量が不足しています。少なくとも約\(ByteCountFormatter.string(fromByteCount: candidate.sizeBytes + 400_000_000, countStyle: .file))が必要です。"])
                }
                try await store.install(candidate.manifest) { [weak self] fraction in
                    await MainActor.run { self?.progress = fraction }
                }
                installedIDs.insert(candidate.id); select(candidate)
                status = "モデルのダウンロードとSHA-256検証が完了しました。"
            } catch { self.error = "モデルを準備できませんでした: \(error.localizedDescription)" }
            busy = false; operation = nil
        }
    }

    func remove(_ candidate: HostedModelCandidate) {
        guard !busy else { return }
        busy = true; error = nil
        operation = Task {
            do {
                if selectedID == candidate.id { await service.unload(); selectedID = nil; UserDefaults.standard.removeObject(forKey: "selected-llm-model") }
                try await store.remove(candidate.manifest)
                installedIDs.remove(candidate.id); status = "モデルを削除しました。"
            } catch { self.error = "モデルを削除できませんでした: \(error.localizedDescription)" }
            busy = false; operation = nil
        }
    }

    func select(_ candidate: HostedModelCandidate) {
        guard installedIDs.contains(candidate.id) else { return }
        selectedID = candidate.id; UserDefaults.standard.set(candidate.id, forKey: "selected-llm-model")
    }

    func generate(topic: String, difficulty: Int, phrases: [String], kind: String,
                  save: @escaping @MainActor (GeneratedLesson) -> Void) {
        guard !busy else { return }
        guard let candidate = candidates.first(where: { $0.id == selectedID }), installedIDs.contains(candidate.id) else {
            error = "先にモデルを検索・ダウンロードし、使用するモデルを選択してください。"; return
        }
        let request = LessonGenerationRequest(topic: topic, difficulty: difficulty, targetPhrases: phrases, kind: kind)
        busy = true; error = nil; status = "モデルを読み込んで教材を生成しています…"
        operation = Task {
            do {
                let directory = try await store.directory(candidate.manifest)
                let modelURL = directory.appendingPathComponent("Models")
                    .appendingPathComponent(candidate.manifest.storageFolder!)
                    .appendingPathComponent(candidate.filePath)
                let lesson = try await coordinator.withExclusiveModel { [service] in
                    try await service.load(modelURL: modelURL)
                    do {
                        let generated = try await LessonGenerator(service: service).generate(request)
                            .attributing(modelID: candidate.id)
                        await service.unload()
                        return generated
                    } catch {
                        await service.unload()
                        throw error
                    }
                }
                _ = try lesson.validated()
                latestMetrics = await service.inferenceMetrics()
                save(lesson)
                status = "教材を保存しました。"
            } catch { self.error = "教材の生成に失敗しました: \(error.localizedDescription)" }
            busy = false; operation = nil
        }
    }

    func cancelCurrentOperation() {
        operation?.cancel()
        Task { await service.cancel() }
    }
}
