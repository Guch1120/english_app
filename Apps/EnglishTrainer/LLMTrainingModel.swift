import Foundation
import Observation
import CryptoKit
import LLMCore
import ModelManagement
import LiteRTLLMBackend
import LearningCore
import LearningPersistence

@MainActor @Observable final class LLMTrainingModel {
    private static let cachedCandidatesKey = "llm-known-model-candidates-v1"
    private static let cachedInstalledIDsKey = "llm-installed-model-ids-v1"
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
    private let store: VerifiedModelStore?
    private let modelRoot: URL?
    private var operation: Task<Void, Never>?

    init() {
        installedIDs = Set(UserDefaults.standard.stringArray(forKey: Self.cachedInstalledIDsKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: Self.cachedCandidatesKey),
           let cached = try? JSONDecoder().decode([HostedModelCandidate].self, from: data) {
            candidates = cached
        }
        selectedID = UserDefaults.standard.string(forKey: "selected-llm-model")
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let root = support.appendingPathComponent("LLMModels", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var protectedRoot = root
            try protectedRoot.setResourceValues(values)
            modelRoot = root
            store = Self.makeStore(root: root)
        } catch {
            modelRoot = nil
            store = nil
            self.error = "保護されたモデル保存領域を準備できませんでした。端末の空き容量と設定を確認してください。"
        }
        Task { await refreshInstalledModels() }
    }

    private func refreshInstalledModels() async {
        guard let store else { return }
        var installed = Set(UserDefaults.standard.stringArray(forKey: Self.cachedInstalledIDsKey) ?? [])
        for candidate in candidates {
            if installed.contains(candidate.id), !(await localModelFilesMatch(candidate, store: store)) {
                installed.remove(candidate.id)
            }
        }
        installedIDs = installed
        if let selectedID, !installed.contains(selectedID) {
            self.selectedID = nil
            UserDefaults.standard.removeObject(forKey: "selected-llm-model")
        }
        persistInstalledIDs()
        persistCandidates()
    }

    private func persistCandidates() {
        guard let data = try? JSONEncoder().encode(candidates) else { return }
        UserDefaults.standard.set(data, forKey: Self.cachedCandidatesKey)
    }

    private func persistInstalledIDs() {
        UserDefaults.standard.set(installedIDs.sorted(), forKey: Self.cachedInstalledIDsKey)
    }

    private func localModelFilesMatch(_ candidate: HostedModelCandidate, store: VerifiedModelStore) async -> Bool {
        do {
            let directory = try await store.directory(candidate.manifest)
            let file = directory.appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent(candidate.manifest.storageFolder ?? candidate.id, isDirectory: true)
                .appendingPathComponent(candidate.filePath)
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            return values.isRegularFile == true && values.fileSize == Int(candidate.sizeBytes)
        } catch { return false }
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
                var combined: [String: HostedModelCandidate] = [:]
                for candidate in candidates where installedIDs.contains(candidate.id) { combined[candidate.id] = candidate }
                for candidate in found { combined[candidate.id] = candidate }
                candidates = combined.values.sorted { $0.displayName < $1.displayName }
                if let store {
                    var installed = Set<String>()
                    for candidate in candidates {
                        if await localModelFilesMatch(candidate, store: store) { installed.insert(candidate.id) }
                    }
                    installedIDs = installed
                    persistInstalledIDs()
                }
                persistCandidates()
                if selectedID == nil, let defaultModel = candidates.first(where: { $0.repository.contains("gemma-4-E2B") && $0.filePath == "gemma-4-E2B-it.litertlm" }) {
                    select(defaultModel)
                }
                status = candidates.isEmpty ? "対応するLiteRT-LMモデルが見つかりませんでした。" : "\(candidates.count)件のモデルファイルが見つかりました。"
            } catch is CancellationError { status = "モデル検索を中断しました。" }
            catch {
                if Task.isCancelled { status = "モデル検索を中断しました。" }
                else { self.error = "モデル検索に失敗しました: \(error.localizedDescription)" }
            }
            busy = false; operation = nil
        }
    }

    func install(_ candidate: HostedModelCandidate) {
        guard !busy else { return }
        guard let store, let modelRoot else { error = "モデル保存領域を利用できません。設定を確認してください。"; return }
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
                if !candidates.contains(where: { $0.id == candidate.id }) { candidates.append(candidate) }
                persistCandidates()
                installedIDs.insert(candidate.id); select(candidate)
                persistInstalledIDs()
                status = "モデルのダウンロードとSHA-256検証が完了しました。"
            } catch is CancellationError { status = "モデル取得を中断しました。検証済みファイルは再試行時に再利用します。" }
            catch {
                if Task.isCancelled { status = "モデル取得を中断しました。検証済みファイルは再試行時に再利用します。" }
                else { self.error = "モデルを準備できませんでした: \(error.localizedDescription)" }
            }
            busy = false; operation = nil
        }
    }

    func remove(_ candidate: HostedModelCandidate) {
        guard !busy else { return }
        guard let store else { error = "モデル保存領域を利用できません。設定を確認してください。"; return }
        busy = true; error = nil
        operation = Task {
            do {
                if selectedID == candidate.id { await service.unload(); selectedID = nil; UserDefaults.standard.removeObject(forKey: "selected-llm-model") }
                try await store.remove(candidate.manifest)
                UserDefaults.standard.removeObject(forKey: "llm-runtime-verified-\(candidate.id)-\(candidate.revision)")
                installedIDs.remove(candidate.id)
                persistInstalledIDs()
                candidates.removeAll { $0.id == candidate.id }
                persistCandidates()
                status = "モデルを削除しました。"
            } catch is CancellationError { status = "モデル削除を中断しました。" }
            catch {
                if Task.isCancelled { status = "モデル削除を中断しました。" }
                else { self.error = "モデルを削除できませんでした: \(error.localizedDescription)" }
            }
            busy = false; operation = nil
        }
    }

    func select(_ candidate: HostedModelCandidate) {
        guard installedIDs.contains(candidate.id) else { return }
        selectedID = candidate.id; UserDefaults.standard.set(candidate.id, forKey: "selected-llm-model")
    }

    func runtimeIsVerified(_ candidate: HostedModelCandidate) -> Bool {
        UserDefaults.standard.bool(forKey: "llm-runtime-verified-\(candidate.id)-\(candidate.revision)")
    }

    var selectedRuntimeIsVerified: Bool {
        guard let candidate = candidates.first(where: { $0.id == selectedID }) else { return false }
        return installedIDs.contains(candidate.id) && runtimeIsVerified(candidate)
    }

    func verifyRuntime(_ candidate: HostedModelCandidate) {
        guard !busy, installedIDs.contains(candidate.id) else { return }
        guard let store else { error = "モデル保存領域を利用できません。設定を確認してください。"; return }
        select(candidate)
        busy = true; error = nil; status = "固定テストでモデルを読み込み、端末内推論を確認しています…"
        operation = Task {
            do {
                let directory = try await store.directory(candidate.manifest)
                let modelURL = directory.appendingPathComponent("Models")
                    .appendingPathComponent(candidate.manifest.storageFolder ?? candidate.id)
                    .appendingPathComponent(candidate.filePath)
                let metrics = try await coordinator.withExclusiveModel { [service] in
                    try await service.load(modelURL: modelURL)
                    do {
                        let output = try await service.generate(prompt: "Return one short English sentence confirming that the on-device language model is ready. No JSON or explanation.")
                        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ContentError.invalidJSON }
                        let metrics = await service.inferenceMetrics()
                        await service.unload()
                        return metrics
                    } catch {
                        await service.unload()
                        throw error
                    }
                }
                UserDefaults.standard.set(true, forKey: "llm-runtime-verified-\(candidate.id)-\(candidate.revision)")
                latestMetrics = metrics
                status = "この端末でモデルの読み込みと推論を確認しました。教材生成を利用できます。"
            } catch is CancellationError { status = "端末確認を中断しました。" }
            catch {
                if Task.isCancelled { status = "端末確認を中断しました。" }
                else { self.error = "端末上のモデル確認に失敗しました: \(error.localizedDescription)" }
            }
            busy = false; operation = nil
        }
    }

    func generate(topic: String, difficulty: Int, phrases: [String], kind: String,
                  save: @escaping @MainActor (GeneratedLesson) -> Void) {
        guard !busy else { return }
        guard let store else { error = "モデル保存領域を利用できません。設定を確認してください。"; return }
        guard let candidate = candidates.first(where: { $0.id == selectedID }), installedIDs.contains(candidate.id) else {
            error = "先にモデルを検索・ダウンロードし、使用するモデルを選択してください。"; return
        }
        guard runtimeIsVerified(candidate) else {
            error = "教材を生成する前に、この端末でモデル動作確認を完了してください。"; return
        }
        let request = LessonGenerationRequest(topic: topic, difficulty: difficulty, targetPhrases: phrases, kind: kind)
        busy = true; error = nil; status = "モデルを読み込んで教材を生成しています…"
        operation = Task {
            do {
                let directory = try await store.directory(candidate.manifest)
                let modelURL = directory.appendingPathComponent("Models")
                    .appendingPathComponent(candidate.manifest.storageFolder ?? candidate.id)
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
            } catch is CancellationError { status = "教材生成を中断しました。" }
            catch {
                if Task.isCancelled { status = "教材生成を中断しました。" }
                else { self.error = "教材の生成に失敗しました: \(error.localizedDescription)" }
            }
            busy = false; operation = nil
        }
    }

    func cancelCurrentOperation() {
        operation?.cancel()
        Task { await service.cancel() }
    }
}
