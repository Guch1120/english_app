import Foundation
import Observation
import SwiftUI
import AudioEnhancementBackends
import ModelManagement
import SpeechCore

@MainActor @Observable final class REUSETrainingModel {
    var enabled = UserDefaults.standard.bool(forKey: "reuse-enabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "reuse-enabled") }
    }
    var installed = false
    var verified = UserDefaults.standard.bool(forKey: REUSEAudioEnhancement.verificationKey)
    var busy = false
    var progress = 0.0
    var status = ""
    var storage: REUSEStorageStatus?
    var lastMetrics: AudioEnhancementMetrics?
    var error: String?

    private let service: REUSEAudioEnhancement?
    private let coordinator = ModelRuntimeCoordinator.shared
    private var operation: Task<Void, Never>?
    var available: Bool { service != nil }

    init() {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
                .appendingPathComponent("NeuralSpeech", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            service = try REUSEAudioEnhancement(applicationSupportDirectory: support, cachesDirectory: cache)
            refresh()
        } catch {
            service = nil
            self.error = "RE-USEの保存領域を準備できませんでした。"
        }
    }

    func refresh() {
        guard !busy, let service else { return }
        busy = true; status = "RE-USEモデルを確認しています"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil; status = "" }
            do {
                storage = try await service.storageStatus()
                installed = storage?.isInstalled == true
                verified = installed && UserDefaults.standard.bool(forKey: REUSEAudioEnhancement.verificationKey)
            }
            catch { self.error = "RE-USEモデルの状態を確認できませんでした。" }
        }
    }

    func download() {
        guard !busy, let service else { return }
        busy = true; progress = 0; status = "RE-USEモデルを取得して検証しています"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil; status = "" }
            do {
                try await service.download { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
                storage = try await service.storageStatus()
                installed = storage?.isInstalled == true
                verified = installed && UserDefaults.standard.bool(forKey: REUSEAudioEnhancement.verificationKey)
                status = "RE-USEモデルの準備ができました"
            } catch is CancellationError { status = "モデル取得を中断しました" }
            catch { self.error = "モデルを取得できませんでした。通信状態と空き容量を確認してください。" }
        }
    }

    func remove() {
        guard !busy, let service else { return }
        busy = true; status = "RE-USEモデルとコンパイルキャッシュを削除しています"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil; status = "" }
            do {
                try await service.removeModel(); storage = try await service.storageStatus()
                installed = false; verified = false; lastMetrics = nil
                UserDefaults.standard.removeObject(forKey: REUSEAudioEnhancement.verificationKey)
            }
            catch { self.error = "RE-USEモデルを削除できませんでした。" }
        }
    }

    func verifyOnDevice() {
        guard !busy, installed, let service else { return }
        busy = true; status = "固定音声を使って端末内動作を確認しています"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil; status = "" }
            do {
                let measured = service
                let result = try await coordinator.withExclusiveModel {
                    try await measured.verifyOnDevice()
                }
                lastMetrics = result
                verified = true
                UserDefaults.standard.set(true, forKey: REUSEAudioEnhancement.verificationKey)
                status = "この端末でRE-USEの動作を確認しました"
            } catch is CancellationError { status = "端末確認を中断しました" }
            catch { self.error = "固定音声の端末内処理に失敗しました。機種と空き容量を確認してください。" }
        }
    }

    func enhance(_ audio: AudioAsset) async throws -> AudioAsset {
        guard installed, verified, let service else { throw REUSEError.modelMissing }
        let measuredService = service
        let result = try await coordinator.withExclusiveModel {
            try await measuredService.load()
            do {
                let enhanced = try await measuredService.enhance(audio)
                let metrics = await measuredService.enhancementMetrics()
                await measuredService.unload()
                return (enhanced, metrics)
            } catch {
                await measuredService.unload()
                throw error
            }
        }
        lastMetrics = result.1
        return result.0
    }

    func cancel() {
        operation?.cancel()
        if let service { Task { await service.cancel() } }
        status = "処理を中断しています"
    }

    func cancelInference() {
        if let service { Task { await service.cancel() } }
    }
}

struct REUSESettingsView: View {
    @Bindable var model: REUSETrainingModel
    @State private var confirmDownload = false
    @State private var confirmRemoval = false

    var body: some View {
        Form {
            Section("オンデバイス音声強調") {
                Toggle("比較機能でRE-USEを使用", isOn: $model.enabled)
                Text("同じ録音をRE-USEなし／ありでASRにかけ、単語誤り率と処理時間を比較します。音声や学習文を外部へ送信しません。初期設定はOFFです。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("モデル") {
                Text("NVIDIA NemotronLabs RE-USE · 約\(ByteCountFormatter.string(fromByteCount: REUSEAudioEnhancement.modelSizeBytes, countStyle: .file))")
                Text("初回ダウンロード後はオフラインで処理できます。端末にモデルを読み込むまで、推論メモリは使用しません。初回処理ではCore MLキャッシュ用に追加容量が必要です。")
                    .font(.caption).foregroundStyle(.secondary)
                if let storage = model.storage {
                    LabeledContent("保存済みモデル", value: ByteCountFormatter.string(fromByteCount: storage.storedBytes, countStyle: .file))
                    LabeledContent("コンパイルキャッシュ", value: ByteCountFormatter.string(fromByteCount: storage.compiledBytes, countStyle: .file))
                }
                if !model.available {
                    Text("RE-USEは対応するiOS端末でのみ利用できます。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if model.installed {
                    Label("モデルの全ファイルをSHA-256検証済み", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if model.verified {
                        Label("この端末で推論を確認済み", systemImage: "iphone.gen3.radiowaves.left.and.right").foregroundStyle(.green)
                    } else {
                        Button("固定音声で端末内動作を確認", systemImage: "checkmark.shield") { model.verifyOnDevice() }
                            .disabled(model.busy)
                        Text("確認に成功するまで録音の強調処理は有効になりません。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("モデルとコンパイルキャッシュを削除", role: .destructive) { confirmRemoval = true }
                        .disabled(model.busy)
                } else {
                    Button("RE-USEモデルをダウンロード") { confirmDownload = true }.disabled(model.busy || !model.available)
                }
                if model.busy {
                    if model.progress > 0 { ProgressView(value: model.progress) } else { ProgressView() }
                    Text(model.status).font(.caption)
                    Button("処理を中断") { model.cancel() }
                }
            }
            Section("モデルの出典とライセンス") {
                Link("NVIDIA RE-USEモデルカード", destination: URL(string: "https://huggingface.co/nvidia/NVIDIA-NemotronLabs-RE-USE")!)
                Text("元モデル：NVIDIA-NemotronLabs-RE-USE · OpenMDW-1.1 · 変換済みモデルの取得先は固定revisionに制限しています。")
                    .font(.caption).foregroundStyle(.secondary)
                NavigationLink("OpenMDW-1.1と第三者ライセンス表示") { REUSENoticesView() }
            }
            if !model.status.isEmpty && !model.busy { Text(model.status).font(.caption) }
        }
        .navigationTitle("RE-USE設定")
        .confirmationDialog("RE-USEモデルを取得しますか？", isPresented: $confirmDownload, titleVisibility: .visible) {
            Button("ダウンロード開始") { model.download() }
        } message: {
            Text("約54 MBを端末に取得し、全ファイルをSHA-256で検証します。マイク録音や教材文は送信しません。")
        }
        .confirmationDialog("保存したRE-USEモデルとコンパイルキャッシュを削除しますか？", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("削除", role: .destructive) { model.remove() }
        }
    }
}

private struct REUSENoticesView: View {
    var body: some View {
        ScrollView {
            Text(REUSEAudioEnhancement.thirdPartyNotices)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("ライセンス表示")
    }
}
