import SwiftUI
import SpeechCore
import NeuralTTSBackends

struct TTSEnginePicker: View {
    let speech: TTSTrainingModel
    var body: some View {
        Picker("音声エンジン", selection: Binding(get: { speech.selected }, set: { speech.select($0) })) {
            Text("Apple（米国英語）").tag("apple")
            ForEach(NeuralVoice.allCases) { voice in
                Text(voice.title + (speech.installed.contains(voice) ? "" : "（未準備）"))
                    .tag(voice.id).disabled(!speech.installed.contains(voice))
            }
        }.disabled(speech.busy)
    }
}
struct TTSModelsView: View {
    let speech: TTSTrainingModel
    @State private var requested: NeuralVoice?
    @State private var confirmDownload = false
    @State private var confirmRemove = false
    @State private var limit = UserDefaults.standard.integer(forKey: "tts-cache-mb") == 0 ? 128 : UserDefaults.standard.integer(forKey: "tts-cache-mb")
    var body: some View {
        Form {
            Section("標準の音声") { TTSEnginePicker(speech: speech) }
            Section("オンデバイス音声モデル") {
                ForEach(NeuralVoice.allCases) { voice in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(voice.title).font(.headline)
                        Text("米国英語・話者：" + voice.speaker).font(.subheadline)
                        Text(voice.license).font(.caption).foregroundStyle(.secondary)
                        if let manifest = try? voice.manifest() {
                            Text("初回取得：約" + ByteCountFormatter.string(fromByteCount: manifest.sizeBytes, countStyle: .file)).font(.caption)
                        }
                        Text(speech.installed.contains(voice) ? "ファイル検証済み・実機での音声検証は未完了" : "未準備・初回ダウンロードが必要です").font(.caption)
                        if speech.installed.contains(voice) {
                            Button("モデルを削除", role: .destructive) { requested = voice; confirmRemove = true }
                        } else {
                            Button("ダウンロードして準備") { requested = voice; confirmDownload = true }
                        }
                    }.padding(.vertical, 5).disabled(speech.busy)
                }
            }
            if speech.busy {
                Section {
                    if speech.progress > 0 { ProgressView(value: speech.progress) } else { ProgressView() }
                    Text(speech.status)
                    Button("処理を中断") { speech.stop() }
                }
            } else if !speech.status.isEmpty { Section { Text(speech.status) } }
            Section("生成音声キャッシュ") {
                LabeledContent("使用量", value: ByteCountFormatter.string(fromByteCount: Int64(speech.cacheBytes), countStyle: .file))
                Picker("容量の上限", selection: $limit) { Text("64 MB").tag(64); Text("128 MB").tag(128); Text("256 MB").tag(256) }
                    .onChange(of: limit) { _, value in speech.setCacheLimit(megabytes: value) }.disabled(speech.busy)
                Button("生成音声キャッシュを削除", role: .destructive) { speech.clearCache() }.disabled(speech.busy)
                Text("再生速度の変更では音声を作り直しません。保存済み音声はオフラインで再利用できます。").font(.caption)
            }
            Section { NavigationLink("モデル・ライブラリのライセンス") { TTSNoticesView() } }
        }.navigationTitle("音声モデル管理")
        .confirmationDialog("モデルをダウンロードしますか？", isPresented: $confirmDownload, titleVisibility: .visible) {
            Button("ダウンロード開始") { if let requested { speech.prepare(requested) } }
        } message: { Text("Hugging Faceからモデルファイルを取得します。英文や学習履歴は送信しません。モデルには上記ライセンスが適用されます。取得とSHA-256検証後、端末内で実行します。") }
        .confirmationDialog("保存済みモデルを削除しますか？", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("削除", role: .destructive) { if let requested { speech.remove(requested) } }
        }
    }
}
struct TTSComparisonView: View {
    let speech: TTSTrainingModel
    @AppStorage("tts-comparison-text") private var text = "Could you reschedule the meeting for Thursday?"
    @AppStorage("tts-comparison-group") private var group = UUID().uuidString
    var body: some View {
        Form {
            Section("同じ英文で聴き比べる") {
                TextField("比較する英文", text: $text, axis: .vertical).textInputAutocapitalization(.sentences)
                    .disabled(speech.busy).onChange(of: text) { _, _ in group = UUID().uuidString }
                ForEach(NeuralVoice.allCases) { voice in
                    Button(voice.title + "で生成・再生") { speech.speak(text, speed: 1, engine: voice.id, comparisonID: UUID(uuidString: group)) }
                        .disabled(speech.busy || !speech.installed.contains(voice) || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                NavigationLink("モデルを準備する") { TTSModelsView(speech: speech) }
            }
            if speech.busy { Section { ProgressView(); Text(speech.status); Button("中断") { speech.stop() } } }
            Section("この英文での測定結果") {
                ForEach(speech.measurements.filter { $0.comparisonID?.uuidString == group }) { result in
                    VStack(alignment: .leading, spacing: 5) {
                        Text((NeuralVoice(rawValue: result.engine)?.title ?? result.engine) + " · " + result.voice).font(.headline)
                        if result.cacheHit { Text("キャッシュ再生（生成時間・RTFの比較対象外）") }
                        if let seconds = result.generationSeconds { Text("生成：\(seconds, specifier: "%.2f")秒") }
                        Text("音声長：\(result.duration, specifier: "%.2f")秒 / \(Int(result.sampleRate)) Hz")
                        if let rtf = result.realTimeFactor { Text("RTF：\(rtf, specifier: "%.3f")") }
                        if let memory = result.peakProcessRSS {
                            Text("プロセスRSS観測ピーク：" + ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory))
                        }
                        Text(result.generatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
                Text("生成時間はモデル読込を含みません。RTFは生成時間÷音声長で、小さいほど高速です。RSSは50ms間隔の観測値で、モデル単体の使用量ではありません。").font(.caption)
                Text("測定値はこの端末の結果です。音声品質は実際に聴いて確認してください。").font(.caption)
            }
        }.navigationTitle("TTS聴き比べ").onDisappear { speech.stop() }
    }
}
struct TTSNoticesView: View {
    var body: some View {
        ScrollView {
            Text(NeuralVoice.licenseNotices).font(.caption).textSelection(.enabled).padding()
        }.navigationTitle("ライセンス")
    }
}
