import SwiftUI
import AVFoundation
import SpeechCore
import TTSBackends
import LearningCore
import LearningPersistence
import NeuralTTSBackends
import NeuralASRBackends
import LLMCore

@main struct EnglishTrainerApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}
@MainActor @Observable final class AppModel {
    var items: [LearningItem] = []
    var points: [WeakPoint] = []
    var reviewHistory: [ReviewEvent] = []
    var activityHistory: [LearningActivityEvent] = []
    var generatedLessons: [GeneratedLesson] = []
    var error: String?
    var ready = false
    private var store: LearningStore?
    let speech: TTSTrainingModel
    let speaking: SpeakingTrainingModel
    let llm: LLMTrainingModel
    init(playback: any SpeechPlayback) {
        self.speech = TTSTrainingModel(speaker: playback)
        self.speaking = SpeakingTrainingModel()
        self.llm = LLMTrainingModel()
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
    var progress: LearningProgress { LearningProgress(events: reviewHistory, activities: activityHistory, weakPoints: points) }
    func refresh() throws {
        items = try store!.items(); points = try store!.weakPoints()
        reviewHistory = try store!.reviewHistory()
        activityHistory = try store!.activityHistory()
        generatedLessons = try store!.generatedLessons()
    }
    func item(for point: WeakPoint) -> LearningItem? { items.first { $0.id == point.itemID } }
    func perform(_ operation: (LearningStore) throws -> Void) {
        guard let store else { error = "保存領域を開けませんでした。アプリを再起動してください。"; return }
        do { try operation(store); try refresh() } catch { self.error = String(describing: error) }
    }
    func deleteAllLearningData() {
        guard !speech.busy, !speaking.busy, !speaking.recording, !llm.busy, let store else { return }
        do { try store.deleteAll(); try refresh(); speech.clearPersonalData(); speaking.deleteRecording() }
        catch { self.error = String(describing: error) }
    }
    func save(text: String, translation: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform { try $0.save(LearningItem(text: trimmed, translation: translation)) }
    }
    func mark(_ item: LearningItem, text: String, reason: WeakReason) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !points.contains(where: { $0.itemID == item.id && $0.text.caseInsensitiveCompare(trimmed) == .orderedSame && $0.reason == reason }) else { return }
        perform { try $0.save(WeakPoint(itemID: item.id, text: trimmed, reason: reason)) }
    }
    func review(_ point: WeakPoint, grade: ReviewGrade) {
        perform { _ = try $0.review(point, grade: grade, now: Date()) }
    }
    func delete(_ point: WeakPoint) { perform { try $0.delete(point) } }
    func recordActivity(_ activity: LearningActivity, item: LearningItem) {
        perform { try $0.recordActivity(activity, itemID: item.id) }
    }
    func saveGenerated(_ lesson: GeneratedLesson) {
        perform { try $0.save(lesson) }
    }
    func speak(_ text: String, speed: Double, item: LearningItem? = nil) {
        if let item { recordActivity(.listening, item: item) }
        speech.speak(text, speed: speed)
    }
    func stop() { speech.stop() }
    func handleAudioInterruption() {
        speech.stop()
        speaking.handleAudioInterruption()
        llm.cancelCurrentOperation()
    }
    func handleAudioRouteLoss() {
        speech.stop()
        speaking.stopRecordingPlayback()
    }
    func handleMemoryWarning() {
        speech.stop()
        speaking.handleMemoryWarning()
        llm.cancelCurrentOperation()
    }
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
        .alert("処理できませんでした", isPresented: Binding(get: { model.error != nil || model.speech.error != nil || model.speaking.error != nil || model.speaking.reuse.error != nil }, set: { if !$0 { model.error = nil; model.speech.error = nil; model.speaking.error = nil; model.speaking.reuse.error = nil } })) {
            Button("閉じる") { model.error = nil; model.speech.error = nil; model.speaking.error = nil; model.speaking.reuse.error = nil }
        } message: { Text(model.error ?? model.speech.error ?? model.speaking.error ?? model.speaking.reuse.error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.speech.stop()
                model.speaking.handleBackground()
                model.llm.cancelCurrentOperation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            model.handleMemoryWarning()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            model.handleAudioInterruption()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            model.handleAudioRouteLoss()
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
                Button { model.speak(item.text, speed: speed, item: item) } label: {
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
                Button("お手本を聞く", systemImage: "play.circle") { appModel.speak(item.text, speed: 1, item: item) }
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
                    Button("録音を開始", systemImage: "mic.circle.fill") {
                        appModel.stop(); model.startRecording()
                        if model.recording { appModel.recordActivity(.speaking, item: item) }
                    }
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
            Section("音声強調の比較") {
                Toggle("RE-USEを使う", isOn: $model.reuse.enabled)
                Text("同じ録音を、音声強調なし／ありで同じASRにかけて比較します。発話音声と学習文は端末内で処理します。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.reuse.installed && !model.reuse.verified {
                    Text("この端末で固定音声の動作確認を完了すると比較を利用できます。")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button("録音をRE-USEなし／ありで比較", systemImage: "waveform.badge.mic") {
                    model.compareWithREUSE()
                }.disabled(model.busy || model.recording || !model.reuse.enabled || !model.reuse.installed ||
                           !model.reuse.verified || !model.recognitionAvailable || model.audioDuration > 300)
                NavigationLink("RE-USEモデルと端末確認の設定") { REUSESettingsView(model: model.reuse) }
                if model.audioDuration > 300 {
                    Text("RE-USEは5分以内の録音に対応します。通常の文字起こしは引き続き利用できます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let metrics = model.reuse.lastMetrics {
                    LabeledContent("RE-USE処理", value: "\(metrics.processingSeconds.formatted(.number.precision(.fractionLength(2))))秒 · RTF \(metrics.realTimeFactor.formatted(.number.precision(.fractionLength(3))))")
                    LabeledContent("モデル読み込み", value: "\(metrics.modelLoadSeconds.formatted(.number.precision(.fractionLength(2))))秒")
                    if let memory = metrics.peakMemoryBytes {
                        LabeledContent("MLXピークメモリ", value: ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory))
                    }
                }
                if let enhancedURL = model.enhancedRecordingURL {
                    Button("RE-USE処理後の音声を聞く", systemImage: "play.circle") { model.playEnhancedRecording() }
                        .disabled(model.busy || model.recording || model.playingRecording)
                    Text(enhancedURL.lastPathComponent).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if !model.transcript.isEmpty {
                let result = WordAlignment.compare(expected: item.text, recognized: model.transcript)
                Section("文字起こし") {
                    Text(model.transcript).textSelection(.enabled)
                    if let seconds = model.processingSeconds {
                        Text("認識時間：\(seconds, specifier: "%.2f")秒 · 録音時間：\(model.audioDuration, specifier: "%.1f")秒")
                            .font(.caption).foregroundStyle(.secondary)
                        if let memory = model.processingPeakMemoryBytes {
                            Text("認識中のプロセスRSS観測ピーク：\(ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
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
            if !model.enhancedTranscript.isEmpty {
                let enhancedResult = WordAlignment.compare(expected: item.text, recognized: model.enhancedTranscript)
                Section("RE-USEありの文字起こし") {
                    Text(model.enhancedTranscript).textSelection(.enabled)
                    Text("単語誤り率：\(enhancedResult.wordErrorRate, format: .percent.precision(.fractionLength(0)))")
                    if let seconds = model.enhancedProcessingSeconds {
                        Text("認識時間：\(seconds, specifier: "%.2f")秒 · RE-USEなし：\(model.processingSeconds ?? 0, specifier: "%.2f")秒")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let memory = model.enhancedPeakMemoryBytes {
                        Text("認識中のプロセスRSS観測ピーク：\(ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("RSSは推論中に50ms間隔で採取したアプリ全体の観測値で、モデル単体の割当量ではありません。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("RE-USEなし／ありの両結果は同じ録音・同じASR・同じ英文で比較しています。")
                        .font(.caption).foregroundStyle(.secondary)
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
    @State private var pointToDelete: WeakPoint?
    var body: some View {
        List {
            let due = model.points.filter { $0.nextReviewAt <= Date() }.sorted { $0.nextReviewAt < $1.nextReviewAt }
            Section("学習の記録") {
                LabeledContent("累計復習", value: "\(model.progress.totalReviews)回")
                LabeledContent("学習した日", value: "\(model.progress.activeDays)日")
                LabeledContent("連続学習日数", value: "\(model.progress.currentStreak)日")
                LabeledContent("定着した項目", value: "\(model.progress.masteredCount)件")
                LabeledContent("リスニング", value: "\(model.activityHistory.filter { $0.activity == .listening }.count)回")
                LabeledContent("スピーキング", value: "\(model.activityHistory.filter { $0.activity == .speaking }.count)回")
                NavigationLink("復習履歴を表示") { ReviewHistoryView(model: model) }
            }
            Section("今日の復習・\(due.count)件") {
                ForEach(due) { point in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(point.text).font(.headline)
                        Text(point.reason.rawValue).font(.caption).foregroundStyle(.secondary)
                        Button("聞く", systemImage: "play.circle") { model.speak(point.text, speed: 1, item: model.item(for: point)) }
                            .disabled(model.speech.busy)
                        if let item = model.item(for: point) {
                            NavigationLink("元の教材とスピーキング練習") { LessonView(model: model, item: item) }
                        }
                        ViewThatFits {
                            HStack { grades(point) }
                            VStack(alignment: .leading) { grades(point) }
                        }
                    }.padding(.vertical)
                }
                if due.isEmpty { ContentUnavailableView("今日の復習は完了です", systemImage: "checkmark.circle", description: Text("聞き取れない表現を教材から登録できます。")) }
            }
            Section("保存済み・\(model.points.count)件") {
                ForEach(model.points.sorted { $0.registeredAt > $1.registeredAt }) { point in
                    VStack(alignment: .leading) {
                        Text(point.text)
                        Text("登録日：\(point.registeredAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(point.reason.rawValue + " · 復習\(point.reviews)回 · 成功\(point.successes) / 失敗\(point.failures)")
                            .font(.caption).foregroundStyle(.secondary)
                        if let mastery = point.mastery {
                            ProgressView(value: mastery) { Text("習熟度") }
                            Text("\(mastery, format: .percent.precision(.fractionLength(0))) · 次回：\(point.nextReviewAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("未復習 · 次回：\(point.nextReviewAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let item = model.item(for: point) {
                            NavigationLink("元の教材を開く") { LessonView(model: model, item: item) }
                        }
                        Button("復習項目を削除", systemImage: "trash", role: .destructive) { pointToDelete = point }
                    }
                    .padding(.vertical, 5)
                }
                if model.points.isEmpty { ContentUnavailableView("復習項目はありません", systemImage: "bookmark", description: Text("リスニングやスピーキングから苦手な表現を登録できます。")) }
            }
        }
        .navigationTitle("復習")
        .onDisappear { model.stop() }
        .confirmationDialog("復習項目と履歴を削除しますか？", isPresented: Binding(
            get: { pointToDelete != nil },
            set: { if !$0 { pointToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("復習項目を削除", role: .destructive) {
                if let pointToDelete { model.delete(pointToDelete) }
                pointToDelete = nil
            }
        } message: {
            Text("関連する復習履歴も削除されます。この操作は取り消せません。")
        }
    }
    @ViewBuilder func grades(_ point: WeakPoint) -> some View {
        ForEach(ReviewGrade.allCases, id: \.self) { grade in
            Button(grade.rawValue) { model.review(point, grade: grade) }.buttonStyle(.bordered)
        }
    }
}
struct ReviewHistoryView: View {
    let model: AppModel
    var body: some View {
        List {
            if model.reviewHistory.isEmpty {
                ContentUnavailableView("復習履歴はありません", systemImage: "clock", description: Text("復習項目に回答するとここに記録されます。"))
            } else {
                ForEach(model.reviewHistory) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.points.first { $0.id == event.weakPointID }?.text ?? "削除済みの復習項目")
                            .font(.headline)
                        Text("\(event.grade.rawValue) · \(event.reviewedAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("次回：\(event.nextReviewAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            Section("リスニング・スピーキング") {
                if model.activityHistory.isEmpty {
                    Text("練習履歴はありません。")
                } else {
                    ForEach(model.activityHistory) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.activity == .listening ? "リスニング" : "スピーキング").font(.headline)
                            Text(model.items.first { $0.id == event.itemID }?.text ?? "教材なし")
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
            }
        }.navigationTitle("学習・復習履歴")
    }
}
struct OfflineReadinessView: View {
    let model: AppModel

    private var selectedLLMReady: Bool {
        guard let id = model.llm.selectedID,
              let candidate = model.llm.candidates.first(where: { $0.id == id }) else { return false }
        return model.llm.installedIDs.contains(id) && model.llm.runtimeIsVerified(candidate)
    }

    var body: some View {
        Form {
            Section("端末内モデルの準備状況") {
                LabeledContent("TTS") {
                    if model.speech.selected == "apple" {
                        Label("iOSの音声データ状態を確認してください", systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                    } else if let voice = NeuralVoice(rawValue: model.speech.selected), model.speech.installed.contains(voice) {
                        Label("選択中の音声を準備済み", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("音声モデルの取得が必要", systemImage: "arrow.down.circle").foregroundStyle(.orange)
                    }
                }
                if model.speech.selected == "apple" {
                    Text("Apple音声データはiOSの音声設定で取得が必要な場合があります。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("ASR") {
                    let ready = model.speaking.recognitionAvailable
                    Label(ready ? "選択中の認識エンジンを利用可能" : "モデルの取得または端末確認が必要", systemImage: ready ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(ready ? .green : .orange)
                }
                LabeledContent("LLM") {
                    Label(selectedLLMReady ? "モデル取得・端末確認済み" : "モデル取得・端末確認が必要", systemImage: selectedLLMReady ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(selectedLLMReady ? .green : .orange)
                }
                LabeledContent("RE-USE") {
                    let ready = model.speaking.reuse.installed && model.speaking.reuse.verified
                    Label(ready ? "モデル取得・端末確認済み" : "任意機能・未準備", systemImage: ready ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(ready ? .green : .secondary)
                }
                Text("表示は端末内の保存状態を使った目安です。Apple音声の取得状態や、各機能の実際のオフライン動作は機内モードで確認してください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("機内モードでの確認") {
                Text("1. Wi-Fiとモバイル通信がある状態で、使うモデルをダウンロードし、端末動作確認を完了します。")
                Text("2. 機内モードを有効にしてアプリを再起動します。")
                Text("3. 教材の表示、TTS再生、録音とASR、保存済み教材、復習履歴を順に確認します。")
                Text("4. LLM教材生成とRE-USE比較は、各モデルの固定音声／固定プロンプト確認済み表示がある場合に試します。")
                Text("モデル検索や初回ダウンロードはインターネット接続が必要です。学習文と録音音声は送信しません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("オフライン準備")
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
                NavigationLink("LLM教材生成・モデル管理") {
                    LLMLessonGenerationView(model: model.llm, lessons: model.generatedLessons, save: model.saveGenerated)
                }
                NavigationLink("RE-USE音声強調モデル") { REUSESettingsView(model: model.speaking.reuse) }
                NavigationLink("オフライン利用の準備") { OfflineReadinessView(model: model) }
                Text("Kokoro / Pocket TTS、Parakeet ASR、LiteRT-LM、RE-USEを端末内で使用します。")
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
                    .disabled(model.speech.busy || model.speaking.busy || model.speaking.recording || model.llm.busy)
            }
        }.navigationTitle("設定")
        .confirmationDialog("教材・復習・録音・生成音声・測定履歴を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { model.deleteAllLearningData() }
        }
    }
}
