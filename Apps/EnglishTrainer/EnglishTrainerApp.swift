import SwiftUI
import SpeechCore
import TTSBackends
import LearningCore
import LearningPersistence
import NeuralTTSBackends
import NeuralASRBackends

@main struct EnglishTrainerApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}
@MainActor @Observable final class AppModel {
    var items: [LearningItem] = []
    var points: [WeakPoint] = []
    var error: String?
    var ready = false
    private var store: LearningStore?
    let speech: TTSTrainingModel
    let speaking: SpeakingTrainingModel
    init(playback: any SpeechPlayback) {
        self.speech = TTSTrainingModel(speaker: playback)
        self.speaking = SpeakingTrainingModel()
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let url = folder.appendingPathComponent("learning.sqlite")
            let database = try LearningStore(path: url.path)
            store = database
            // Seed once only, so deleting all data survives a restart.
            if !UserDefaults.standard.bool(forKey: "seeded-v1") {
                for item in LearningItem.samples { try database.save(item) }
                UserDefaults.standard.set(true, forKey: "seeded-v1")
            }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            try refresh(); ready = true
        } catch { self.error = String(describing: error) }
    }
    func refresh() throws { items = try store!.items(); points = try store!.weakPoints() }
    func perform(_ operation: (LearningStore) throws -> Void) {
        guard let store else { error = "保存領域を開けませんでした。アプリを再起動してください。"; return }
        do { try operation(store); try refresh() } catch { self.error = String(describing: error) }
    }
    func deleteAllLearningData() {
        guard !speech.busy, !speaking.busy, !speaking.recording, let store else { return }
        do { try store.deleteAll(); try refresh(); speech.clearPersonalData(); speaking.deleteRecording() }
        catch { self.error = String(describing: error) }
    }
    func save(text: String, translation: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform { try $0.save(LearningItem(text: trimmed, translation: translation)) }
    }
    func mark(_ item: LearningItem, text: String, reason: WeakReason) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        perform { try $0.save(WeakPoint(itemID: item.id, text: text, reason: reason)) }
    }
    func review(_ point: WeakPoint, grade: ReviewGrade) {
        perform { _ = try $0.review(point, grade: grade, now: Date()) }
    }
    func speak(_ text: String, speed: Double) { speech.speak(text, speed: speed) }
    func stop() { speech.stop() }
}

struct RootView: View {
    @State private var model = AppModel(playback: AppleSpeechPlayback())
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            NavigationStack { HomeView(model: model) }.tabItem { Label("学習", systemImage: "headphones") }
            NavigationStack { ReviewView(model: model) }.tabItem { Label("復習", systemImage: "arrow.clockwise") }
            NavigationStack { SettingsView(model: model) }.tabItem { Label("設定", systemImage: "gearshape") }
        }
        .tint(.teal)
        .alert("処理できませんでした", isPresented: Binding(get: { model.error != nil || model.speech.error != nil || model.speaking.error != nil }, set: { if !$0 { model.error = nil; model.speech.error = nil; model.speaking.error = nil } })) {
            Button("閉じる") { model.error = nil; model.speech.error = nil; model.speaking.error = nil }
        } message: { Text(model.error ?? model.speech.error ?? model.speaking.error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.speech.cancelWork(); model.speaking.handleBackground() }
        }
    }
}
struct HomeView: View {
    let model: AppModel
    @State private var text = ""
    @State private var translation = ""
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("少しずつ、聞こえる英語へ。 ").font(.title2.bold())
                    Text("今日の復習 \(model.points.filter { $0.nextReviewAt <= Date() }.count) 件").foregroundStyle(.secondary)
                }.padding(.vertical)
            }
            Section("リスニング教材") {
                ForEach(model.items) { item in
                    NavigationLink { LessonView(model: model, item: item) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("ビジネス英語", systemImage: "waveform").font(.caption).foregroundStyle(.teal)
                            Text(item.text).font(.headline)
                        }.padding(.vertical, 6)
                    }
                }
                if model.items.isEmpty { Text("英文を追加して学習を始めましょう。") }
            }
            Section("自分の英文を保存") {
                TextField("英文", text: $text, axis: .vertical).textInputAutocapitalization(.sentences)
                TextField("日本語訳（任意）", text: $translation, axis: .vertical)
                Button("教材を追加", systemImage: "plus.circle") {
                    model.save(text: text, translation: translation)
                    if model.error == nil { text = ""; translation = "" }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.ready)
            }
        }.navigationTitle("English Trainer")
    }
}
struct LessonView: View {
    let model: AppModel
    let item: LearningItem
    @State private var showEnglish = false
    @State private var showTranslation = false
    @AppStorage("listening-speed") private var speed = 1.0
    @State private var selected = ""
    @State private var reason = WeakReason.listening
    @State private var saved = false
    var body: some View {
        Form {
            Section("まずは聞いてみましょう") {
                TTSEnginePicker(speech: model.speech)
                Button { model.speak(item.text, speed: speed) } label: {
                    Label("お手本を再生", systemImage: "play.circle.fill").font(.title2).frame(maxWidth: .infinity, minHeight: 70)
                }
                .disabled(model.speech.busy)
                if model.speech.busy { ProgressView(); Text(model.speech.status) }
                Button(model.speech.busy ? "生成を中断" : "再生を停止", systemImage: "stop.circle") { model.stop() }
                HStack {
                    Button("一時停止") { model.speech.pause() }
                    Spacer()
                    Button("再開") { model.speech.resume() }
                }
                if model.speech.selected != "apple" {
                    Toggle("生成音声を繰り返す", isOn: Binding(get: { model.speech.repeats }, set: { model.speech.repeats = $0 }))
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("読み上げ速度")
                        Spacer()
                        HStack(spacing: 0) {
                            Text(speed, format: .number.precision(.fractionLength(2)))
                            Text("×")
                        }
                        .monospacedDigit()
                    }
                    Slider(value: $speed, in: 0.5...1.5, step: 0.05)
                        .accessibilityLabel("読み上げ速度")
                        .accessibilityValue("\(speed.formatted(.number.precision(.fractionLength(2))))倍")
                        .disabled(model.speech.busy)
                    HStack {
                        Text("0.50×")
                        Spacer()
                        Text("1.50×")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .onChange(of: speed) { _, value in model.speech.setRate(value) }
                Toggle("英文を表示", isOn: $showEnglish)
                if showEnglish { Text(item.text).font(.title3).textSelection(.enabled) }
                Toggle("日本語訳を表示", isOn: $showTranslation)
                if showTranslation { Text(item.translation) }
            }
            Section("苦手箇所を保存") {
                if showEnglish {
                    ScrollView(.horizontal) { HStack {
                        ForEach(Array(item.text.split(separator: " ").enumerated()), id: \.offset) { _, word in
                            Button(String(word)) { selected = String(word); saved = false }.buttonStyle(.bordered)
                        }
                    } }
                }
                TextField("単語・フレーズ（空欄で文章全体）", text: $selected)
                Picker("理由", selection: $reason) { ForEach(WeakReason.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Button(saved ? "保存しました" : "復習に登録", systemImage: "bookmark") {
                    model.mark(item, text: selected.isEmpty ? item.text : selected, reason: reason)
                    saved = model.error == nil
                }
            }
            Section {
                NavigationLink("スピーキング練習・文字起こし") { SpeakingPreview(item: item, appModel: model, model: model.speaking) }
            }
        }.navigationTitle("リスニング").onDisappear { model.stop() }
    }
}
struct SpeakingPreview: View {
    let item: LearningItem
    let appModel: AppModel
    @Bindable var model: SpeakingTrainingModel
    @State private var confirmDownload = false
    @State private var confirmModelRemoval = false
    var body: some View {
        Form {
            Section("お手本") {
                Text(item.text)
                Button("お手本を聞く", systemImage: "play.circle") { appModel.speak(item.text, speed: 1) }
            }
            Section("音声認識モデル") {
                Picker("モデル", selection: $model.selectedEngine) {
                    ForEach(ASREngine.allCases) { engine in Text(engine.title).tag(engine) }
                }.pickerStyle(.menu)
                if model.selectedEngine == .parakeet {
                    Text("\(ParakeetModel.title) · 約\(ByteCountFormatter.string(fromByteCount: ParakeetModel.sizeBytes, countStyle: .file)) · \(ParakeetModel.license)")
                        .font(.caption)
                    Link("モデルの出典・ライセンス（CC BY 4.0）", destination: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-ctc-110m-coreml")!)
                        .font(.caption)
                    if model.installed {
                        Label("モデルのファイルを検証済み", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("モデルを削除", role: .destructive) { confirmModelRemoval = true }
                            .disabled(model.busy || model.recording)
                    } else {
                        Button("Parakeetモデルをダウンロード") { confirmDownload = true }.disabled(model.busy)
                    }
                } else if model.recognitionAvailable {
                    Text("Apple Speechの英語認識を端末内限定で使います。音声は端末外へ送信しません。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("この端末では英語の端末内認識を利用できません。Parakeetを選択してください。")
                        .font(.caption).foregroundStyle(.orange)
                }
                if model.busy {
                    if model.progress > 0 { ProgressView(value: model.progress) } else { ProgressView() }
                    Text(model.status).font(.caption)
                    Button("処理を中断") { model.cancel() }
                }
            }
            Section("録音して話す") {
                if model.recording {
                    Label("録音中 · 発話後に停止してください", systemImage: "record.circle").foregroundStyle(.red)
                    Button("録音を停止", systemImage: "stop.circle.fill") { model.stopRecording() }
                } else {
                    Button("録音を開始", systemImage: "mic.circle.fill") { appModel.stop(); model.startRecording() }
                        .disabled(!model.recognitionAvailable || model.busy)
                }
                if model.busy { Text(model.status).font(.caption) }
                if model.audioDuration > 0 {
                    LabeledContent("録音時間", value: model.audioDuration.formatted(.number.precision(.fractionLength(1))) + "秒")
                    Button(model.playingRecording ? "録音の再生中" : "自分の録音を聞く", systemImage: model.playingRecording ? "speaker.wave.2.fill" : "play.circle") {
                        if model.playingRecording { model.stopRecordingPlayback() } else { model.playRecording() }
                    }.disabled(model.busy || model.recording)
                    Button("もう一度文字起こし", systemImage: "text.magnifyingglass") { model.transcribe() }
                        .disabled(model.busy || model.recording || !model.recognitionAvailable)
                    Button("録音を削除", systemImage: "trash", role: .destructive) { model.deleteRecording() }
                        .disabled(model.busy || model.recording)
                }
                if !model.status.isEmpty && !model.busy { Text(model.status).font(.caption) }
            }
            if !model.transcript.isEmpty {
                let result = WordAlignment.compare(expected: item.text, recognized: model.transcript)
                Section("文字起こし") {
                    Text(model.transcript).textSelection(.enabled)
                    if let seconds = model.processingSeconds {
                        Text("認識時間：\(seconds, specifier: "%.2f")秒 · 録音時間：\(model.audioDuration, specifier: "%.1f")秒")
                            .font(.caption).foregroundStyle(.secondary)
                        let wordCount = model.transcript.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
                        if model.audioDuration > 0 {
                            let speakingTime = max(0.1, model.audioDuration - (model.silenceMetricsAvailable ? model.silenceDuration : 0))
                            Text("発話ペースの目安：\(Double(wordCount) / speakingTime * 60, specifier: "%.0f")語/分")
                                .font(.caption).foregroundStyle(.secondary)
                            if model.silenceMetricsAvailable {
                                Text("無音の目安：\(model.silenceDuration, specifier: "%.1f")秒 · 0.4秒以上の間：\(model.pauseCount)回 · 最長：\(model.longestPause, specifier: "%.1f")秒")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("録音時間全体から求めた概算です。短い間も含みます。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("単語の差分") {
                    ForEach(Array(result.tokens.enumerated()), id: \.offset) { _, token in
                        HStack {
                            Text(token.expected ?? "＋")
                            Spacer()
                            Text(token.recognized ?? "欠落")
                        }.foregroundStyle(token.kind == .match ? Color.primary : Color.orange)
                    }
                    Text("単語誤り率：\(result.wordErrorRate, format: .percent.precision(.fractionLength(0)))")
                    Text("文字起こしの一致度です。発音の正確さを採点するものではありません。").font(.caption)
                    if result.tokens.contains(where: { $0.kind != .match }) {
                        Button("この英文をスピーキングの復習に登録", systemImage: "bookmark") {
                            appModel.mark(item, text: item.text, reason: .speaking)
                        }
                    }
                }
            }
            Section {
                Text("一致度は文字起こしの比較です。発音の正確さを採点するものではありません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("スピーキング練習")
        .confirmationDialog("Parakeetモデルを準備しますか？", isPresented: $confirmDownload, titleVisibility: .visible) {
            Button("ダウンロード開始") { model.prepareModel() }
        } message: {
            Text("約\(ByteCountFormatter.string(fromByteCount: ParakeetModel.sizeBytes, countStyle: .file) )を端末にダウンロードし、SHA-256で検証します。録音や教材文は送信しません。")
        }
        .confirmationDialog("保存したParakeetモデルを削除しますか？", isPresented: $confirmModelRemoval, titleVisibility: .visible) {
            Button("モデルを削除", role: .destructive) { model.removeModel() }
        }
        .onDisappear {
            if model.recording { model.stopRecording() }
            model.stopRecordingPlayback(); appModel.stop()
        }
    }
}
struct ReviewView: View {
    let model: AppModel
    var body: some View {
        List {
            let due = model.points.filter { $0.nextReviewAt <= Date() }
            Section("今日の復習・\(due.count)件") {
                ForEach(due) { point in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(point.text).font(.headline)
                        Text(point.reason.rawValue).font(.caption).foregroundStyle(.secondary)
                        Button("聞く", systemImage: "play.circle") { model.speak(point.text, speed: 1) }
                        ViewThatFits {
                            HStack { grades(point) }
                            VStack(alignment: .leading) { grades(point) }
                        }
                    }.padding(.vertical)
                }
                if due.isEmpty { ContentUnavailableView("今日の復習は完了です", systemImage: "checkmark.circle", description: Text("聞き取れない表現を教材から登録できます。")) }
            }
            Section("保存済み・\(model.points.count)件") {
                ForEach(model.points) { point in
                    VStack(alignment: .leading) {
                        Text(point.text)
                        Text("次回：\(point.nextReviewAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("復習").onDisappear { model.stop() }
    }
    @ViewBuilder func grades(_ point: WeakPoint) -> some View {
        ForEach(ReviewGrade.allCases, id: \.self) { grade in
            Button(grade.rawValue) { model.review(point, grade: grade) }.buttonStyle(.bordered)
        }
    }
}
struct SettingsView: View {
    let model: AppModel
    @State private var confirmDelete = false
    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "不明"
        let build = info["CFBundleVersion"] as? String ?? "不明"
        return "\(version) (\(build))"
    }
    var body: some View {
        Form {
            Section("アプリ") {
                LabeledContent("バージョン", value: appVersion)
            }
            Section("音声とAI") {
                LabeledContent("TTS", value: NeuralVoice(rawValue: model.speech.selected)?.title ?? "Apple・米国英語")
                NavigationLink("音声モデル管理") { TTSModelsView(speech: model.speech) }
                NavigationLink("TTS聴き比べ・性能測定") { TTSComparisonView(speech: model.speech) }
                Text("Kokoro / Pocket TTS と Parakeet ASR を利用できます。Gemma / RE-USE は未接続です。")
                Text("Apple音声は初回取得が必要な場合があります。機内モードでの再生を実機で確認してください。").font(.caption)
            }
            Section("端末") {
                LabeledContent("OS", value: UIDevice.current.systemVersion)
                LabeledContent("物理メモリ", value: ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
                LabeledContent("発熱状態", value: String(describing: ProcessInfo.processInfo.thermalState))
            }
            Section("データ") {
                Text("学習データは端末内に保存します。音声録音は端末内の保護領域に保存され、削除できます。録音・学習文はクラウドへ送信しません。")
                Button("すべての学習データを削除", role: .destructive) { confirmDelete = true }
                    .disabled(model.speech.busy || model.speaking.busy || model.speaking.recording)
            }
        }.navigationTitle("設定")
        .confirmationDialog("教材・復習・録音・生成音声・測定履歴を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { model.deleteAllLearningData() }
        }
    }
}
