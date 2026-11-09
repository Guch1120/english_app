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
        if let engine = NeuralVoice(rawValue: speech.selected), speech.installed.contains(engine) {
            TTSSpeakerPicker(speech: speech, engine: engine)
        }
    }
}
struct TTSSpeakerPicker: View {
    let speech: TTSTrainingModel
    let engine: NeuralVoice
    var body: some View {
        Picker("話者", selection: Binding(get: { speech.selectedSpeaker(for: engine) }, set: { speech.selectSpeaker($0) })) {
            ForEach(NeuralSpeaker.allCases.filter { $0.engine == engine && speech.installedSpeakers.contains($0) }) { speaker in
                Text(speaker.title).tag(speaker)
            }
        }.disabled(speech.busy)
    }
}
struct TTSModelsView: View {
    let speech: TTSTrainingModel
    @State private var requested: NeuralVoice?
    @State private var confirmDownload = false
    @State private var confirmRemove = false
    @State private var requestedSpeaker: NeuralSpeaker?
    @State private var confirmSpeakerDownload = false
    @State private var confirmSpeakerRemove = false
    @State private var limit = UserDefaults.standard.integer(forKey: "tts-cache-mb") == 0 ? 128 : UserDefaults.standard.integer(forKey: "tts-cache-mb")
    var body: some View {
        Form {
            Section("標準の音声") { TTSEnginePicker(speech: speech) }
            Section("オンデバイス音声モデル") {
                ForEach(NeuralVoice.allCases) { voice in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(voice.title).font(.headline)
                        Text("英語・話者：" + voice.speaker).font(.subheadline)
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
            Section("Kokoro追加話者") {
                Text("基本モデルはそのままで、各約2.7 MBの話者データだけ取得します。Apache-2.0 · hexgrad / FluidInference。追加話者の実機音声品質は未確認です。").font(.caption)
                ForEach(NeuralSpeaker.allCases.filter { $0.supplementalManifest != nil }) { speaker in
                    VStack(alignment: .leading) {
                        Text(speaker.title)
                        if speech.installedSpeakers.contains(speaker) {
                            Button("追加話者を削除", role: .destructive) { requestedSpeaker = speaker; confirmSpeakerRemove = true }
                        } else {
                            Button("話者データをダウンロード") { requestedSpeaker = speaker; confirmSpeakerDownload = true }
                                .disabled(!speech.installed.contains(.kokoro))
                        }
                    }.disabled(speech.busy)
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
        .confirmationDialog("追加話者データを取得しますか？", isPresented: $confirmSpeakerDownload, titleVisibility: .visible) {
            Button("ダウンロード開始") { if let requestedSpeaker { speech.prepareSpeaker(requestedSpeaker) } }
        } message: { Text("Hugging Faceから固定版の話者データを取得し、SHA-256を検証します。英文は送信しません。") }
        .confirmationDialog("追加話者データを削除しますか？", isPresented: $confirmSpeakerRemove, titleVisibility: .visible) {
            Button("削除", role: .destructive) { if let requestedSpeaker { speech.removeSpeaker(requestedSpeaker) } }
        }
    }
}
struct TTSComparisonView: View {
    let speech: TTSTrainingModel
    @AppStorage("tts-comparison-text") private var text = "Could you reschedule the meeting for Thursday?"
    @AppStorage("tts-comparison-group") private var group = UUID().uuidString
    @State private var editingNote: TTSMeasurement?
    var body: some View {
        Form {
            Section("同じ英文で聴き比べる") {
                TextField("比較する英文", text: $text, axis: .vertical).textInputAutocapitalization(.sentences)
                    .disabled(speech.busy).onChange(of: text) { _, _ in group = UUID().uuidString }
                ForEach(NeuralVoice.allCases) { voice in
                    if speech.installed.contains(voice) { TTSSpeakerPicker(speech: speech, engine: voice) }
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
                        if let note = result.listeningNote { Text(note).font(.subheadline) }
                        Button(result.listeningNote == nil ? "聴き心地のメモを追加" : "比較メモを編集") { editingNote = result }
                    }.padding(.vertical, 5)
                }
                Text("生成時間はモデル読込を含みません。RTFは生成時間÷音声長で、小さいほど高速です。RSSは50ms間隔の観測値で、モデル単体の使用量ではありません。").font(.caption)
                Text("測定値はこの端末の結果です。音声品質は実際に聴いて確認してください。").font(.caption)
            }
        }.navigationTitle("TTS聴き比べ").onDisappear { speech.stop() }
        .sheet(item: $editingNote) { result in TTSListeningNoteView(speech: speech, result: result) }
    }
}
struct TTSListeningNoteView: View {
    let speech: TTSTrainingModel
    let result: TTSMeasurement
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    init(speech: TTSTrainingModel, result: TTSMeasurement) {
        self.speech = speech; self.result = result
        _note = State(initialValue: result.listeningNote ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(result.voice) {
                    TextField("自然さ・聴き取りやすさ・気になった発音など", text: $note, axis: .vertical).lineLimit(5...12).accessibilityIdentifier("tts.listeningNote")
                    Text("\(note.count) / 2000文字・この端末内に保存").font(.caption)
                }
            }.navigationTitle("比較メモ")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { if speech.saveListeningNote(note, measurementID: result.id) { dismiss() } }
                            .disabled(note.count > 2000)
                    }
                }
        }
    }
}
struct TTSNoticesView: View {
    var body: some View {
        ScrollView {
            Text(NeuralVoice.licenseNotices).font(.caption).textSelection(.enabled).padding()
        }.navigationTitle("ライセンス")
    }
}
