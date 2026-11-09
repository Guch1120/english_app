import SwiftUI
import ModelManagement
import NeuralTTSBackends
import NeuralASRBackends
import AudioEnhancementBackends

private struct ModelInformationEntry: Identifiable {
    let descriptor: ModelDescriptor
    let installed: Bool?
    var id: String { descriptor.id }
}

struct ModelInformationView: View {
    let model: AppModel
    @State private var runtime: ModelRuntimeSnapshot?
    private var entries: [ModelInformationEntry] {
        var result: [ModelInformationEntry] = NeuralVoice.allCases.compactMap { voice in
            guard let manifest = try? voice.manifest() else { return nil }
            let generated = model.speech.measurements.contains { $0.engine == voice.id && $0.modelRevision == manifest.revision && !$0.cacheHit }
            return ModelInformationEntry(descriptor: ModelDescriptor(id: voice.id, name: voice.title, kind: .tts,
                runtime: "FluidAudio 0.18.2 / Core ML", verifiedOnDevice: generated,
                developer: voice == .kokoro ? "hexgrad / FluidInference" : "Kyutai / FluidInference",
                languages: [voice == .kokoro ? "en-US" : "en"], version: manifest.revision, minimumOS: "iOS 18（アプリ対象OS）",
                license: voice.license, capabilities: ["音声生成", "話者選択", "オフライン", "キャッシュ", "性能測定"], manifest: manifest,
                downloadSource: URL(string: "https://huggingface.co/\(manifest.repository)/tree/\(manifest.revision)"),
                verificationSummary: generated ? "このrevisionの端末生成記録あり。音声品質の保証とは別です。" : "このrevisionの端末生成記録なし。"),
                installed: model.speech.installed.contains(voice))
        }
        if let manifest = try? ParakeetModel.manifest() {
            let verified = UserDefaults.standard.bool(forKey: ParakeetModel.verificationKey)
            result.append(ModelInformationEntry(descriptor: ModelDescriptor(id: ParakeetModel.id, name: ParakeetModel.title, kind: .asr,
                runtime: "FluidAudio 0.18.2 / Core ML", verifiedOnDevice: verified, developer: "NVIDIA / FluidInference",
                languages: ["en"], version: manifest.revision, minimumOS: "iOS 18（アプリ対象OS）", license: ParakeetModel.license,
                capabilities: ["録音の文字起こし", "オフライン", "性能測定"], manifest: manifest,
                downloadSource: URL(string: "https://huggingface.co/\(manifest.repository)/tree/\(manifest.revision)"),
                verificationSummary: verified ? "このrevisionで端末認識を実行済み。認識精度の保証とは別です。" : "このrevisionの端末認識結果は未記録。"), installed: model.speaking.installed))
        }
        if let manifest = try? REUSECatalogInformation.manifest() {
            result.append(ModelInformationEntry(descriptor: ModelDescriptor(id: "nvidia-reuse-apple-0.2.0", name: "NVIDIA RE-USE", kind: .enhancement,
                runtime: "RE-USE 0.2.0 / Core ML + MLX", verifiedOnDevice: model.speaking.reuse.verified, developer: "NVIDIA / Corvelis / AILogDev",
                languages: ["音声信号（英語学習で利用）"], version: manifest.revision, minimumOS: "iOS 18（アプリ対象OS）",
                license: "OpenMDW-1.1 / 第三者ライセンスはRE-USE管理画面に表示", capabilities: ["任意の音声強調", "オフライン", "元音声を保持", "性能測定"], manifest: manifest,
                downloadSource: URL(string: "https://huggingface.co/\(manifest.repository)/tree/\(manifest.revision)"),
                verificationSummary: model.speaking.reuse.verified ? "この端末の固定音声確認済み。強調品質の保証とは別です。" : "この端末の固定音声確認が必要です。"), installed: model.speaking.reuse.installed))
        }
        for candidate in model.llm.candidates {
            let verified = model.llm.runtimeIsVerified(candidate)
            let developer = candidate.repository.hasPrefix("litert-community/gemma-4-") ? "Google / LiteRT Community" : "原モデル開発元はモデルカード参照・配布元: \(candidate.repository.split(separator: "/").first ?? "unknown")"
            result.append(ModelInformationEntry(descriptor: ModelDescriptor(id: candidate.id, name: candidate.displayName, kind: .llm,
                runtime: "LiteRT-LM 0.19.1 / GPU", verifiedOnDevice: verified, developer: developer,
                languages: ["en", "ja（教材生成に利用）"], version: candidate.revision, minimumOS: "iOS 18（アプリ対象OS）",
                license: candidate.license, capabilities: ["端末内教材生成", "構造化出力検証", "オフライン", "性能測定"], manifest: candidate.manifest,
                downloadSource: URL(string: "https://huggingface.co/\(candidate.repository)/tree/\(candidate.revision)"),
                verificationSummary: verified ? "このrevisionの端末確認済み。教材の正確さは別途確認してください。" : "取得後の端末確認が必要です。"), installed: model.llm.installedIDs.contains(candidate.id)))
        }
        for (id, name, kind, runtimeName) in [("apple-tts", "Apple音声合成", ModelKind.tts, "AVSpeechSynthesizer"), ("apple-speech-en-us-on-device", "Apple Speech（端末内限定）", ModelKind.asr, "Speech framework")] {
            result.append(ModelInformationEntry(descriptor: ModelDescriptor(id: id, name: name, kind: kind, runtime: runtimeName,
                developer: "Apple", languages: ["en-US"], version: ProcessInfo.processInfo.operatingSystemVersionString,
                minimumOS: "iOS 18（アプリ対象OS）", license: "AppleのOS・音声サービス利用条件",
                capabilities: kind == .tts ? ["システム音声合成"] : ["端末内音声認識のみ（非対応端末では利用不可）"],
                verificationSummary: "OS管理のため、音声データ・モデルのhashとロード状態をアプリから取得しません。"), installed: nil))
        }
        return result
    }
    var body: some View {
        List {
            Section {
                Text("取得済み状態・SDKロード状態・動作確認は別です。SDKロード状態は物理RAMへの常駐やモデル単体メモリを示しません。").font(.caption)
            }
            ForEach(entries) { entry in
                NavigationLink {
                    ModelInformationDetail(entry: entry, runtime: runtime)
                } label: {
                    VStack(alignment: .leading) {
                        Text(entry.descriptor.name)
                        Text(entry.installed.map { $0 ? "ファイル準備済み" : "未準備" } ?? "OS管理").font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("model.info.\(entry.id)")
            }
            Section { Text("LLM候補はモデル管理で検索した対応モデルを表示します。未知の形式を実行可能にする画面ではありません。").font(.caption) }
        }.navigationTitle("AIモデル情報・状態")
            .task {
                while !Task.isCancelled {
                    runtime = await ModelRuntimeCoordinator.shared.snapshot()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}

private struct ModelInformationDetail: View {
    let entry: ModelInformationEntry
    let runtime: ModelRuntimeSnapshot?
    private var info: ModelDescriptor { entry.descriptor }
    var body: some View {
        Form {
            Section("モデル情報") {
                field("モデルID", info.id); field("開発元", info.developer)
                field("種別", info.kind.rawValue); field("対応言語", info.languages.joined(separator: ", "))
                field("ランタイム", info.runtime); field("バージョン / revision", info.version)
                field("必要OS", info.minimumOS); field("ライセンス", info.license)
                if let size = info.sizeBytes { field("ファイル合計", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                else { field("ファイル合計", "OS管理・アプリから取得不可") }
                if let source = info.downloadSource { Link("固定版のダウンロード元", destination: source) }
                field("対応機能", info.capabilities.joined(separator: " / "))
            }
            Section("現在の状態") {
                field("取得状態", entry.installed.map { $0 ? "ファイル準備済み" : "未準備" } ?? "OS管理")
                field("SDKロード状態", entry.installed == nil ? "OS管理・取得不可" : runtime.map { $0.loadedModelIDs.contains(info.id) ? "ロード済み" : "未ロード" })
                field("実行状態", entry.installed == nil ? "OS管理（各画面で確認）" : runtime.map { $0.activeModelID == info.id ? "処理中" : "待機中" })
                field("直近の処理エラー", runtime.map { $0.failures[info.id] == nil ? "記録なし" : "処理失敗（詳細は各モデル画面を確認）" })
                field("動作検証結果", info.verificationSummary)
            }
            if let manifest = info.manifest { ModelManifestDetails(manifest: manifest) }
            if info.id == "kokoro" {
                ForEach(NeuralSpeaker.allCases.filter { $0.supplementalManifest != nil }) { speaker in
                    if let manifest = speaker.supplementalManifest {
                        Section(speaker.title + "の補助データ") { ModelManifestDetails(manifest: manifest) }
                    }
                }
            }
        }.navigationTitle(info.name).navigationBarTitleDisplayMode(.inline)
    }
    private func field(_ name: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "未記録").textSelection(.enabled)
        }
    }
}

private struct ModelManifestDetails: View {
    let manifest: ModelManifest
    var body: some View {
        DisclosureGroup("ファイル・SHA-256（\(manifest.files.count)件）") {
            ForEach(manifest.files, id: \.path) { file in
                VStack(alignment: .leading, spacing: 5) {
                    Text(file.path).font(.caption)
                    Text("\(file.size) bytes").font(.caption)
                    Text(file.sha256).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
    }
}
