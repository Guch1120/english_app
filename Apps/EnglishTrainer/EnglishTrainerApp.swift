import SwiftUI
import AVFoundation
import SpeechCore
import TTSBackends
import LearningCore
import LearningPersistence
import NeuralTTSBackends
import NeuralASRBackends
import LLMCore
import DeviceDiagnostics

@main struct EnglishTrainerApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}
@MainActor @Observable final class AppModel {
    var items: [LearningItem] = []
    var points: [WeakPoint] = []
    var reviewHistory: [ReviewEvent] = []
    var activityHistory: [LearningActivityEvent] = []
    var generatedLessons: [GeneratedLesson] = []
    var lessonPreferences: [UUID: LessonPreferences] = [:]
    var quizAttempts: [QuizAttempt] = []
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
        Task {
            await DiagnosticEventLog.shared.record(DiagnosticEvent(
                subsystem: .app, action: .appLaunch, model: .system, outcome: .observed,
                peakMemoryBytes: ProcessMemorySampler.currentResidentBytes(),
                thermalState: .current
            ))
        }
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
            #if DEBUG && targetEnvironment(simulator)
            // Explicit simulator-only fixtures exercise lesson UI without presenting mock inference.
            for (argument, suffix, text) in [
                ("--uitest-seed-quiz", "000000000091", "Please confirm your test booking."),
                ("--uitest-seed-library", "000000000092", "Please review this library fixture.")
            ] where ProcessInfo.processInfo.arguments.contains(argument) {
                let id = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
                if try !database.items().contains(where: { $0.id == id }) {
                    try database.save(GeneratedLesson(id: id, kind: "UI test conversation", difficulty: 2,
                        text: text, translation: "UIテスト専用の教材です。", targetPhrases: ["test booking"],
                        question: "What should be confirmed?", choices: ["The booking", "A report", "A payment", "A meeting"],
                        answerIndex: 0, explanation: "The booking is the expected answer.", modelID: "ui-test-fixture"))
                }
            }
            #endif
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
        lessonPreferences = Dictionary(uniqueKeysWithValues: try store!.lessonPreferences().map { ($0.itemID, $0) })
        quizAttempts = try store!.quizAttempts()
    }
    var visibleItems: [LearningItem] { items.filter { lessonPreferences[$0.id]?.hidden != true } }
    var visiblePoints: [WeakPoint] { points.filter { lessonPreferences[$0.itemID]?.hidden != true } }
    var visibleGeneratedLessons: [GeneratedLesson] { generatedLessons.filter { lessonPreferences[$0.id]?.hidden != true } }
    func generatedLesson(for item: LearningItem) -> GeneratedLesson? { generatedLessons.first { $0.id == item.id } }
    func saveItem(_ item: LearningItem) { perform { try $0.save(item) } }
    func setHidden(_ hidden: Bool, itemID: UUID) {
        var preferences = lessonPreferences[itemID] ?? LessonPreferences(itemID: itemID)
        preferences.hidden = hidden; preferences.updatedAt = Date()
        if hidden { speech.stop() }
        perform { try $0.save(preferences) }
    }
    func saveIssue(_ note: String, itemID: UUID) {
        var preferences = lessonPreferences[itemID] ?? LessonPreferences(itemID: itemID)
        preferences.issueNote = note; preferences.updatedAt = Date()
        perform { try $0.save(preferences) }
    }
    func answer(_ lesson: GeneratedLesson, item: LearningItem, selectedIndex: Int) {
        let attempt = QuizAttempt(itemID: item.id, itemUpdatedAt: item.updatedAt,
                                  selectedIndex: selectedIndex, correctIndex: lesson.answerIndex,
                                  question: lesson.question, choices: lesson.choices)
        perform { try $0.save(attempt) }
    }
    func item(for point: WeakPoint) -> LearningItem? { items.first { $0.id == point.itemID } }
    func perform(_ operation: (LearningStore) throws -> Void) {
        guard let store else { error = "保存領域を開けませんでした。アプリを再起動してください。"; return }
        do { error = nil; try operation(store); try refresh() } catch { self.error = String(describing: error) }
    }
    func deleteAllLearningData() {
        guard !speech.busy, !speaking.busy, !speaking.recording, !llm.busy, let store else { return }
        do { try store.deleteAll(); try refresh(); speech.clearPersonalData(); speaking.deleteRecording() }
        catch { self.error = String(describing: error) }
    }
    func save(text: String, translation: String, category: LearningCategory = .sentence,
              difficulty: Int? = nil, toeicPart: Int? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform { try $0.save(LearningItem(text: trimmed, translation: translation, category: category,
                                         difficulty: difficulty, toeicPart: toeicPart)) }
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
    func persistGenerated(_ lesson: GeneratedLesson) throws {
        guard let store else { throw StoreError.invalidRecord }
        try store.save(lesson)
        try refresh()
    }
    func speak(_ text: String, speed: Double, item: LearningItem? = nil) {
        if let item { recordActivity(.listening, item: item) }
        speech.speak(text, speed: speed)
    }
    func stop() { speech.stop() }
    func handleAudioInterruption() {
        Task {
            await DiagnosticEventLog.shared.record(DiagnosticEvent(
                subsystem: .app, action: .audioInterruption, model: .system, outcome: .observed,
                thermalState: .current
            ))
        }
        speech.stop()
        speaking.handleAudioInterruption()
        llm.cancelCurrentOperation()
    }
    func handleAudioRouteLoss() {
        speech.stop()
        speaking.stopRecordingPlayback()
    }
    func handleMemoryWarning() {
        Task {
            await DiagnosticEventLog.shared.record(DiagnosticEvent(
                subsystem: .app, action: .memoryWarning, model: .system, outcome: .observed,
                peakMemoryBytes: ProcessMemorySampler.currentResidentBytes(),
                thermalState: .current
            ))
        }
        speech.stop()
        speaking.handleMemoryWarning()
        llm.cancelCurrentOperation()
    }
}

struct RootView: View {
    @State private var model: AppModel? = nil
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let model {
                appContent(model)
            } else {
                ProgressView("学習データを準備しています")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { @MainActor in
            guard model == nil else { return }
            model = AppModel(playback: AppleSpeechPlayback())
        }
    }

    private func appContent(_ model: AppModel) -> some View {
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
    @State private var category = LearningCategory.sentence
    @State private var difficulty = 0
    @State private var part = 0
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("少しずつ、聞こえる英語へ。 ").font(.title2.bold())
                    Text("今日の復習 \(model.visiblePoints.filter { $0.nextReviewAt <= Date() }.count) 件").foregroundStyle(.secondary)
                }.padding(.vertical)
            }
            Section("リスニング教材") {
                ForEach(model.visibleItems) { item in
                    NavigationLink { LessonView(model: model, item: item) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(item.category.title, systemImage: "waveform").font(.caption).foregroundStyle(.teal)
                            if let difficulty = item.difficulty { Text("難易度 \(difficulty) / 5").font(.caption).foregroundStyle(.secondary) }
                            if let part = item.toeicPart { Text("TOEIC Part \(part)").font(.caption).foregroundStyle(.secondary) }
                            Text(item.text).font(.headline)
                        }.padding(.vertical, 6)
                    }
                }
                if model.visibleItems.isEmpty { Text("英文を追加して学習を始めましょう。") }
            }
            Section { NavigationLink("教材を探す・管理") { LessonLibraryView(model: model) } }
            Section("自分の英文を保存") {
                TextField("英文", text: $text, axis: .vertical).textInputAutocapitalization(.sentences)
                TextField("日本語訳（任意）", text: $translation, axis: .vertical)
                DisclosureGroup("分類・難易度（任意）") {
                    Picker("カテゴリ", selection: $category) {
                        ForEach(LearningCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("難易度", selection: $difficulty) {
                        Text("未設定").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0) / 5").tag($0) }
                    }
                    Picker("TOEIC分類", selection: $part) {
                        Text("指定なし").tag(0)
                        ForEach(1...4, id: \.self) { Text("Part \($0)").tag($0) }
                    }
                }
                Button("教材を追加", systemImage: "plus.circle") {
                    model.save(text: text, translation: translation, category: category,
                               difficulty: difficulty == 0 ? nil : difficulty, toeicPart: part == 0 ? nil : part)
                    if model.error == nil { text = ""; translation = "" }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.ready)
            }
        }.navigationTitle("English Trainer")
    }
}
struct LessonView: View {
    let model: AppModel
    private let originalItem: LearningItem
    private var item: LearningItem { model.items.first { $0.id == originalItem.id } ?? originalItem }
    @State private var editing = false
    @State private var reporting = false
    init(model: AppModel, item: LearningItem) { self.model = model; self.originalItem = item }
    @State private var speakingMode = false
    @State private var showEnglish = false
    @State private var showTranslation = false
    @AppStorage("listening-speed") private var speed = 1.0
    @State private var selected = ""
    @State private var reason = WeakReason.listening
    @State private var saved = false
    private var nextItem: LearningItem? {
        let items = model.visibleItems
        guard !items.isEmpty else { return nil }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return items.first }
        return items.count > 1 ? items[(index + 1) % items.count] : nil
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("練習モード", selection: $speakingMode) {
                Text("リスニング").tag(false)
                Text("スピーキング").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("lesson.modeSelector")
            .padding(.horizontal)
            .padding(.vertical, 8)

            Group {
                if speakingMode {
                    SpeakingPreview(item: item, appModel: model, model: model.speaking)
                } else {
                    listeningContent
                }
            }
        }
        .navigationTitle(speakingMode ? "スピーキング練習" : "リスニング")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("教材の操作", systemImage: "ellipsis.circle") {
                    Button("教材を修正", systemImage: "pencil") { editing = true }
                    Button("問題を記録", systemImage: "flag") { reporting = true }
                    Button(model.lessonPreferences[item.id]?.hidden == true ? "教材を再表示" : "教材を非表示", systemImage: "eye.slash") {
                        model.setHidden(model.lessonPreferences[item.id]?.hidden != true, itemID: item.id)
                    }
                }
                .accessibilityIdentifier("lesson.actions")
                .disabled(model.speech.busy || model.speaking.busy || model.speaking.recording)
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { LessonEditorView(model: model, item: item) } }
        .sheet(isPresented: $reporting) { NavigationStack { LessonIssueView(model: model, item: item) } }
    }

    private var listeningContent: some View {
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
            if let lesson = model.generatedLesson(for: item) {
                LessonQuestionSection(model: model, item: item, lesson: lesson)
                    .id(item.updatedAt)
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
            if let nextItem {
                Section {
                    NavigationLink("次の教材") { LessonView(model: model, item: nextItem) }
                        .disabled(model.speech.busy || model.speaking.busy || model.speaking.recording)
                }
            }
        }.onDisappear { model.stop() }
    }
}
struct SpeakingPreview: View {
    let item: LearningItem
    let appModel: AppModel
    @Bindable var model: SpeakingTrainingModel
    var body: some View {
        ScrollViewReader { proxy in
            Form {
            Section("お手本") {
                Text(item.text)
                Button("お手本を聞く", systemImage: "play.circle") { appModel.speak(item.text, speed: 1, item: item) }
            }
            Section("音声認識モデル") {
                Picker("モデル", selection: $model.selectedEngine) {
                    ForEach(ASREngine.allCases) { engine in Text(engine.title).tag(engine) }
                }.pickerStyle(.menu).disabled(model.busy || model.recording)
                if model.selectedEngine == .appleSpeech && model.recognitionAvailable {
                    Text("Apple Speechの英語認識を端末内限定で使います。音声は端末外へ送信しません。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if model.selectedEngine == .appleSpeech {
                    Text("この端末では英語の端末内認識を利用できません。Parakeetを選択してください。")
                        .font(.caption).foregroundStyle(.orange)
                }
                NavigationLink("ASRモデル管理") { ASRModelsView(model: model) }
                if model.reuse.enabled {
                    Text("通常の文字起こしにもRE-USEを適用します。事前のモデル取得と端末確認が必要です。")
                        .font(.caption)
                }
            }
            Section("録音して話す") {
                if model.recording {
                    Label("録音中 · 発話後に停止してください", systemImage: "record.circle").foregroundStyle(.red)
                    Button("録音を停止して文字起こし", systemImage: "stop.circle.fill") { model.stopRecording(autoTranscribe: true) }
                } else {
                    Button("録音を開始", systemImage: "mic.circle.fill") {
                        appModel.stop(); model.startRecording(for: item.id)
                    }
                        .disabled(!model.recognitionAvailable || model.busy)
                }
                if model.busy {
                    Text(model.status).font(.caption)
                    Button("処理を中断") { model.cancel() }
                }
                if model.audioDuration > 0 {
                    if model.recordingItemID != item.id {
                        Text("保存済み録音は別の教材、または教材との対応情報がない録音です。新しく録音するか、この教材との比較を選べます。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("保存録音をこの教材と比較") { model.useSavedRecording(for: item.id) }
                            .disabled(model.busy || model.recording || !model.recognitionAvailable)
                    }
                    LabeledContent("録音時間", value: model.audioDuration.formatted(.number.precision(.fractionLength(1))) + "秒")
                    Button(model.playingRecording ? "録音の再生中" : "自分の録音を聞く", systemImage: model.playingRecording ? "speaker.wave.2.fill" : "play.circle") {
                        if model.playingRecording { model.stopRecordingPlayback() } else { model.playRecording() }
                    }.disabled(model.busy || model.recording)
                    Button("もう一度文字起こし", systemImage: "text.magnifyingglass") { model.transcribe() }
                        .disabled(model.busy || model.recording || !model.recognitionAvailable || model.recordingItemID != item.id)
                    Button("録音を削除", systemImage: "trash", role: .destructive) { model.deleteRecording() }
                        .disabled(model.busy || model.recording)
                }
                if !model.status.isEmpty && !model.busy { Text(model.status).font(.caption) }
            }
            transcriptionResults
            Section("音声強調の比較") {
                Toggle("RE-USEを使う", isOn: $model.reuse.enabled)
                    .disabled(model.busy || model.recording || model.reuse.busy)
                Text("オンでは通常の文字起こしに音声強調を適用できます。同じ録音を強調なし／ありで比較することもできます。発話音声と学習文は端末内で処理します。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.reuse.installed && !model.reuse.verified {
                    Text("この端末で固定音声の動作確認を完了すると比較を利用できます。")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button("録音をRE-USEなし／ありで比較", systemImage: "waveform.badge.mic") {
                    model.compareWithREUSE()
                }.disabled(model.busy || model.recording || !model.reuse.enabled || !model.reuse.installed ||
                           !model.reuse.verified || !model.recognitionAvailable || model.audioDuration <= 0 ||
                           model.audioDuration > 300 || model.recordingItemID != item.id)
                NavigationLink("RE-USEモデルと端末確認の設定") { REUSESettingsView(model: model.reuse) }
                if model.audioDuration > 300 {
                    Text("RE-USEは5分以内の録音に対応します。長い録音はRE-USEをオフにすると認識できます。")
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
            }
            .onChange(of: model.transcript) { _, value in
                guard !value.isEmpty else { return }
                withAnimation { proxy.scrollTo("speaking.transcriptionResult", anchor: .top) }
            }
            .onChange(of: model.enhancedTranscript) { _, value in
                guard !value.isEmpty else { return }
                withAnimation { proxy.scrollTo("speaking.enhancedResult", anchor: .top) }
            }
        }
        .onChange(of: model.recording) { wasRecording, isRecording in
            if isRecording && !wasRecording {
                appModel.recordActivity(.speaking, item: item)
            }
        }
        .alert("音声処理でエラーが発生しました", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        )) {
            Button("閉じる") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
        .onDisappear {
            if model.recording { model.stopRecording() }
            model.stopRecordingPlayback(); appModel.stop()
        }
    }

    @ViewBuilder private var transcriptionResults: some View {
        if model.audioDuration > 0 && model.recordingItemID != item.id {
            Section("文字起こし・評価") { Text("この教材を録音すると、結果がここに表示されます。") }
        } else if model.transcript.isEmpty {
            Section("文字起こし・評価") {
                Text(model.transcriptUsesREUSE ? "RE-USEで強調した音声を認識" : "元の録音を認識")
                    .font(.caption).foregroundStyle(.secondary)
                if model.busy && model.status.localizedCaseInsensitiveContains("文字起こし") {
                    ProgressView(model.status)
                        .accessibilityIdentifier("speaking.transcriptionProgress")
                } else if model.audioDuration > 0 {
                    Text("録音を停止すると文字起こしを開始し、結果と英文との一致度を表示します。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("録音後に文字起こし結果と英文との一致度がここに表示されます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            let result = WordAlignment.compare(expected: item.text, recognized: model.transcript)
            Section("文字起こし・評価") {
                Text("単語誤り率：\(result.wordErrorRate, format: .percent.precision(.fractionLength(0)))")
                    .font(.headline)
                    .accessibilityIdentifier("speaking.wordErrorRate")
                Text(model.transcript).textSelection(.enabled)
                    .accessibilityIdentifier("speaking.transcriptionText")
                Text("文字起こしの一致度です。発音の正確さを採点するものではありません。")
                    .font(.caption)
                DisclosureGroup("認識時間・発話ペース") {
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
                DisclosureGroup("単語ごとの差分") {
                ForEach(Array(result.tokens.enumerated()), id: \.offset) { _, token in
                    HStack {
                        Text(token.expected ?? "＋")
                        Spacer()
                        Text(token.recognized ?? "欠落")
                    }.foregroundStyle(token.kind == .match ? Color.primary : Color.orange)
                }
                }
                if result.tokens.contains(where: { $0.kind != .match }) {
                    Button("この英文をスピーキングの復習に登録", systemImage: "bookmark") {
                        appModel.mark(item, text: item.text, reason: .speaking)
                    }
                }
            }
            .id("speaking.transcriptionResult")
        }

        if !model.enhancedTranscript.isEmpty && model.recordingItemID == item.id {
            let result = WordAlignment.compare(expected: item.text, recognized: model.enhancedTranscript)
            Section("RE-USEありの文字起こし") {
                Text(model.enhancedTranscript).textSelection(.enabled)
                Text("単語誤り率：\(result.wordErrorRate, format: .percent.precision(.fractionLength(0)))")
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
            .id("speaking.enhancedResult")
        }
    }
}

struct ASRModelsView: View {
    @Bindable var model: SpeakingTrainingModel
    @State private var confirmDownload = false
    @State private var confirmRemoval = false

    var body: some View {
        Form {
            Section("標準の音声認識") {
                Picker("認識エンジン", selection: $model.selectedEngine) {
                    ForEach(ASREngine.allCases) { engine in Text(engine.title).tag(engine) }
                }
                if model.selectedEngine == .appleSpeech {
                    Text(model.recognitionAvailable
                         ? "端末内音声認識を利用できます。認識をネットワークへ送信しません。"
                         : "この端末では端末内音声認識を利用できません。Parakeetモデルを準備してください。")
                        .font(.caption).foregroundStyle(model.recognitionAvailable ? Color.gray : Color.orange)
                }
            }
            Section("オンデバイスASRモデル") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ParakeetModel.title).font(.headline)
                    Text("約\(ByteCountFormatter.string(fromByteCount: ParakeetModel.sizeBytes, countStyle: .file)) · \(ParakeetModel.license)")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("モデルの出典・ライセンス（CC BY 4.0）", destination: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-ctc-110m-coreml")!)
                        .font(.caption)
                        .accessibilityIdentifier("asr.modelSource")
                    if model.installed {
                        Label("モデルファイルを検証済み", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Parakeetモデルを削除", role: .destructive) { confirmRemoval = true }
                            .disabled(model.busy || model.recording)
                    } else {
                        Text("未準備・初回ダウンロードが必要です。音声と英文は送信されません。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Parakeetモデルをダウンロード") { confirmDownload = true }
                            .disabled(model.busy || model.recording)
                    }
                }
                .padding(.vertical, 4)
            }
            if model.busy {
                Section {
                    if model.status.localizedCaseInsensitiveContains("ダウンロード"), model.progress > 0 {
                        ProgressView(value: model.progress)
                    } else {
                        ProgressView()
                    }
                    Text(model.status).font(.caption)
                    Button("処理を中断") { model.cancel() }
                }
            } else if !model.status.isEmpty {
                Section { Text(model.status).font(.caption) }
            }
            Section {
                Text("取得したモデルは端末内に保存し、サイズとSHA-256を検証してから使用します。モデルファイルと録音音声はiCloudバックアップ対象外です。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("ASRモデル管理")
        .task { model.refreshModel() }
        .confirmationDialog("Parakeetモデルを準備しますか？", isPresented: $confirmDownload, titleVisibility: .visible) {
            Button("ダウンロード開始") { model.prepareModel() }
        } message: {
            Text("約\(ByteCountFormatter.string(fromByteCount: ParakeetModel.sizeBytes, countStyle: .file))を端末にダウンロードし、SHA-256で検証します。英文や録音は送信しません。")
        }
        .confirmationDialog("保存したParakeetモデルを削除しますか？", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("モデルを削除", role: .destructive) { model.removeModel() }
        }
        .alert("モデル処理に失敗しました", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        )) {
            Button("閉じる") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }
}

struct ReviewView: View {
    let model: AppModel
    @State private var pointToDelete: WeakPoint?
    var body: some View {
        List {
            let due = model.visiblePoints.filter { $0.nextReviewAt <= Date() }.sorted { $0.nextReviewAt < $1.nextReviewAt }
            Section("復習の音声") {
                TTSEnginePicker(speech: model.speech)
            }
            Section("学習の記録") {
                LabeledContent("累計復習", value: "\(model.progress.totalReviews)回")
                LabeledContent("学習した日", value: "\(model.progress.activeDays)日")
                LabeledContent("連続学習日数", value: "\(model.progress.currentStreak)日")
                LabeledContent("定着した項目", value: "\(model.progress.masteredCount)件")
                LabeledContent("リスニング", value: "\(model.activityHistory.filter { $0.activity == .listening }.count)回")
                LabeledContent("スピーキング", value: "\(model.activityHistory.filter { $0.activity == .speaking }.count)回")
                LabeledContent("設問への回答", value: "\(model.quizAttempts.count)回")
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
                            NavigationLink("新しい用例で復習") { ReviewExampleView(model: model, point: point, original: item) }
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
                            NavigationLink("新しい用例で復習") { ReviewExampleView(model: model, point: point, original: item) }
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
            Section("学習の操作履歴") {
                if model.activityHistory.isEmpty {
                    Text("練習履歴はありません。")
                } else {
                    ForEach(model.activityHistory) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.activity == .listening ? "リスニング" : event.activity == .speaking ? "スピーキング" : "設問への回答").font(.headline)
                            Text(model.items.first { $0.id == event.itemID }?.text ?? "教材なし")
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section("設問への回答履歴") {
                ForEach(model.quizAttempts) { attempt in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(attempt.question.isEmpty ? "保存済み教材の設問" : attempt.question).font(.headline)
                        Text(attempt.correct ? "正解" : "要確認").foregroundStyle(attempt.correct ? Color.green : Color.orange)
                        if attempt.choices.indices.contains(attempt.selectedIndex) {
                            Text("回答：\(attempt.choices[attempt.selectedIndex])")
                            Text("当時の正解：\(attempt.choices[attempt.correctIndex])")
                        }
                        if model.items.first(where: { $0.id == attempt.itemID })?.updatedAt != attempt.itemUpdatedAt {
                            Text("教材を修正する前の回答です。") .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(attempt.answeredAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
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
    @State private var diagnosticEvents: [DiagnosticEvent] = []
    @AppStorage(RecordingRetention.preferenceKey) private var retainRecording = true
    @State private var diagnosticExport: String?
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
                NavigationLink("教材を探す・管理") { LessonLibraryView(model: model) }
            }
            Section("音声とAI") {
                LabeledContent("TTS", value: NeuralVoice(rawValue: model.speech.selected)?.title ?? "Apple・米国英語")
                NavigationLink("音声モデル管理") { TTSModelsView(speech: model.speech) }
                NavigationLink("TTS聴き比べ・性能測定") { TTSComparisonView(speech: model.speech) }
                NavigationLink("ASRモデル管理") { ASRModelsView(model: model.speaking) }
                NavigationLink("ASR聴き取り比較") { ASRComparisonView(appModel: model) }
                NavigationLink("LLM教材生成・モデル管理") {
                    LLMLessonGenerationView(model: model.llm, lessons: model.visibleGeneratedLessons, save: model.persistGenerated)
                }
                NavigationLink("RE-USE音声強調モデル") { REUSESettingsView(model: model.speaking.reuse) }
                NavigationLink("オフライン利用の準備") { OfflineReadinessView(model: model) }
                NavigationLink("AIモデル情報・状態") { ModelInformationView(model: model) }
                Text("Kokoro / Pocket TTS、Parakeet ASR、LiteRT-LM、RE-USEを端末内で使用します。")
                Text("Apple音声は初回取得が必要な場合があります。機内モードでの再生を実機で確認してください。").font(.caption)
            }
            Section("端末") {
                LabeledContent("OS", value: UIDevice.current.systemVersion)
                LabeledContent("物理メモリ", value: ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
                LabeledContent("発熱状態", value: String(describing: ProcessInfo.processInfo.thermalState))
            }
            Section {
                if diagnosticEvents.isEmpty {
                    Text("記録はありません。")
                } else {
                    ForEach(diagnosticEvents) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(event.subsystem.rawValue.uppercased()) · \(event.action.rawValue) · \(event.outcome.rawValue)")
                                .font(.subheadline)
                            Text("\(event.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(event.model.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                            if let elapsed = event.elapsedMilliseconds {
                                Text("処理時間 \(elapsed) ms").font(.caption).foregroundStyle(.secondary)
                            }
                            if let size = event.modelBytes {
                                Text("モデル容量 \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let memory = event.peakMemoryBytes {
                                Text("プロセスメモリ \(ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let cache = event.cacheBytes {
                                Text("キャッシュ \(ByteCountFormatter.string(fromByteCount: Int64(cache), countStyle: .memory))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("発熱状態 \(event.thermalState.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 3)
                    }
                }
                Button("共有用の診断情報を作成") {
                    Task { diagnosticExport = try? await DiagnosticEventLog.shared.exportJSON() }
                }
                if let diagnosticExport {
                    ShareLink("診断情報を共有", item: diagnosticExport)
                    Text("共有先は次の画面で選びます。記録時刻と識別子、教材・録音・文字起こしは含めません。処理種別や性能値は含まれます。")
                        .font(.caption)
                }
                Button("診断ログを消去", role: .destructive) {
                    Task {
                        await DiagnosticEventLog.shared.clear()
                        diagnosticEvents = []
                        diagnosticExport = nil
                    }
                }
            } header: {
                Text("端末内診断")
            } footer: {
                Text("直近500件を端末内に保存します。教材文、録音、文字起こし、入力内容、エラー文は保存しません。")
            }
            Section("データ") {
                Text("学習データは端末内に保存します。音声録音は端末内の保護領域に保存され、削除できます。録音・学習文はクラウドへ送信しません。")
                Toggle("次回起動後も最新の録音を保持", isOn: $retainRecording)
                    .accessibilityIdentifier("recording.retainOnRestart")
                Text("オフの場合、最新録音は次回アプリ起動時に削除します。今回の練習中は再生・再認識でき、新しい録音は前の録音を置き換えます。")
                    .font(.caption)
                Button("すべての学習データを削除", role: .destructive) { confirmDelete = true }
                    .disabled(model.speech.busy || model.speaking.busy || model.speaking.recording || model.llm.busy)
            }
        }.task { diagnosticEvents = await DiagnosticEventLog.shared.recentEvents() }
        .navigationTitle("設定")
        .confirmationDialog("教材・復習・録音・生成音声・測定履歴を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { model.deleteAllLearningData() }
        }
    }
}

struct ASRComparisonView: View {
    let appModel: AppModel
    private var model: SpeakingTrainingModel { appModel.speaking }
    private var reference: LearningItem? {
        appModel.items.first { $0.id == model.recordingItemID }
    }
    var body: some View {
        Form {
            Section("同じ録音で比較") {
                Text("直近の録音をParakeetとApple Speechで順番に端末内認識します。文字起こしはこの画面の間だけ保持し、送信しません。")
                if let reference {
                    Text("お手本：\(reference.text)").textSelection(.enabled)
                    LabeledContent("録音時間", value: model.audioDuration.formatted(.number.precision(.fractionLength(1))) + "秒")
                } else {
                    Text("先に教材のスピーキング画面で録音してください。")
                }
                if !model.installed { Text("Parakeetモデルを準備してください。") }
                if !model.comparisonAvailable && model.installed && reference != nil {
                    Text("Apple Speechの端末内認識がこの端末で利用可能か確認してください。")
                }
                Button("2つのASRを比較") { model.compareASREngines() }
                    .disabled(!model.comparisonAvailable || reference == nil || model.busy || model.recording)
                if model.comparingEngines {
                    ProgressView(); Text(model.status)
                    Button("比較を中断") { model.cancel() }
                }
            }
            if let reference {
                ForEach(model.comparisonResults) { result in
                    Section(result.engine.title) {
                        Text(result.transcript.isEmpty ? "認識結果は空でした。" : result.transcript).textSelection(.enabled)
                        let alignment = WordAlignment.compare(expected: reference.text, recognized: result.transcript)
                        LabeledContent("単語誤り率", value: alignment.wordErrorRate.formatted(.percent.precision(.fractionLength(0))))
                        LabeledContent("認識時間", value: result.seconds.formatted(.number.precision(.fractionLength(2))) + "秒")
                        if model.audioDuration > 0 {
                            LabeledContent("RTF", value: (result.seconds / model.audioDuration).formatted(.number.precision(.fractionLength(2))))
                        }
                        if let bytes = result.peakProcessBytes {
                            LabeledContent("プロセスRSS観測ピーク", value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory))
                        }
                    }
                }
                if !model.comparisonResults.isEmpty {
                    Text("単語誤り率はお手本との文字起こしの差で、発音の採点ではありません。RSSはアプリ全体の観測値です。")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("ASR比較")
        .onDisappear {
            if model.comparingEngines { model.cancel() }
            model.comparisonResults = []
        }
        .alert("ASR比較", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("閉じる") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
