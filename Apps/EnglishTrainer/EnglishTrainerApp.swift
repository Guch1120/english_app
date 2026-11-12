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

enum AppTab: Hashable { case learn, review, settings }

struct RootView: View {
    @State private var model: AppModel? = nil
    @State private var tab = AppTab.learn
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
        TabView(selection: $tab) {
            NavigationStack { HomeView(model: model, openReview: { tab = .review }) }
                .tabItem { Label("学習", systemImage: "headphones") }.tag(AppTab.learn)
            NavigationStack { ReviewView(model: model) }
                .tabItem { Label("復習", systemImage: "arrow.clockwise") }.tag(AppTab.review)
            NavigationStack { SettingsView(model: model) }
                .tabItem { Label("設定", systemImage: "gearshape") }.tag(AppTab.settings)
        }
        .tint(.teal)
        .alert("処理できませんでした", isPresented: Binding(get: { model.error != nil || model.speech.error != nil || model.speaking.error != nil || model.speaking.reuse.error != nil }, set: { if !$0 { model.error = nil; model.speech.error = nil; model.speaking.error = nil; model.speaking.reuse.error = nil } })) {
            Button("閉じる") { model.error = nil; model.speech.error = nil; model.speaking.error = nil; model.speaking.reuse.error = nil }
        } message: { Text(model.error ?? model.speech.error ?? model.speaking.error ?? model.speaking.reuse.error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // Keep already-started playback alive for lock screen / background listening.
                // Generation and downloads cannot be assumed to complete in the background.
                model.speech.cancelWork()
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
    let openReview: () -> Void
    @State private var adding = false
    @State private var generating = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var dueCount: Int { model.visiblePoints.filter { $0.nextReviewAt <= Date() }.count }
    var body: some View {
        List {
            Section {
                HomeHeroCard(dueCount: dueCount, streak: model.progress.currentStreak,
                             lessonCount: model.visibleItems.count, openReview: openReview)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                let tiles = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                tiles {
                    Button { adding = true } label: {
                        ActionTile(title: "英文を追加", subtitle: "自分の教材を保存", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.addLesson")
                    .disabled(!model.ready)
                    Button { generating = true } label: {
                        ActionTile(title: "AIで教材を生成", subtitle: "端末内のLLMで作成", systemImage: "sparkles", tint: .indigo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.generateLesson")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(model.visibleItems) { item in
                    NavigationLink { LessonView(model: model, item: item) } label: { LessonRow(item: item) }
                }
                if model.visibleItems.isEmpty {
                    ContentUnavailableView("教材がありません", systemImage: "text.badge.plus",
                                           description: Text("英文を追加して学習を始めましょう。"))
                }
            } header: {
                Text("リスニング教材")
            } footer: {
                if !model.visibleItems.isEmpty { Text("教材を開くと、リスニングとスピーキングを切り替えて練習できます。") }
            }
            Section {
                NavigationLink { LessonLibraryView(model: model) } label: {
                    Label("教材を探す・管理", systemImage: "magnifyingglass")
                }
            }
        }
        .navigationTitle("English Trainer")
        .sheet(isPresented: $adding) { NavigationStack { AddLessonView(model: model) } }
        .navigationDestination(isPresented: $generating) {
            LLMLessonGenerationView(model: model.llm, lessons: model.visibleGeneratedLessons, save: model.persistGenerated)
        }
    }
}

/// Today's summary with a direct path into due reviews.
struct HomeHeroCard: View {
    let dueCount: Int
    let streak: Int
    let lessonCount: Int
    let openReview: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("少しずつ、聞こえる英語へ。").font(.title2.bold())
            // A fixed layout: ViewThatFits made the list row measure a shorter variant and clip the card.
            let statsLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            statsLayout {
                stat(value: dueCount, unit: "件", label: "今日の復習", systemImage: "arrow.clockwise")
                stat(value: streak, unit: "日", label: "連続学習", systemImage: "flame.fill")
                stat(value: lessonCount, unit: "件", label: "教材", systemImage: "books.vertical.fill")
            }
            if dueCount > 0 {
                Button(action: openReview) {
                    Label("今日の復習を始める", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Color.teal)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .accessibilityIdentifier("home.startReview")
            } else {
                Label("今日の復習は完了です", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [Color.teal, Color.indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }
    private func stat(value: Int, unit: String, label: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)").font(.title.bold()).monospacedDigit()
                Text(unit).font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 4) {
                Image(systemName: systemImage).imageScale(.small)
                Text(label)
            }
            .font(.caption.weight(.medium))
            .opacity(0.9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)\(unit)")
    }
}

/// Shared lesson summary for the home list and the lesson library.
struct LessonRow: View {
    let item: LearningItem
    var hidden = false
    var flagged = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                Chip(text: item.category.title, systemImage: "waveform")
                if let difficulty = item.difficulty { Chip(text: "難易度 \(difficulty) / 5", tint: .orange) }
                if let part = item.toeicPart { Chip(text: "TOEIC Part \(part)", tint: .indigo) }
                if hidden { Chip(text: "非表示", systemImage: "eye.slash", tint: .gray) }
                if flagged { Chip(text: "要確認", systemImage: "flag.fill", tint: .red) }
            }
            Text(item.text).font(.headline).lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}

/// Sheet for saving the learner's own sentence, kept off the home list so lessons stay in focus.
struct AddLessonView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var translation = ""
    @State private var category = LearningCategory.sentence
    @State private var difficulty = 0
    @State private var part = 0
    var body: some View {
        Form {
            Section {
                TextField("英文", text: $text, axis: .vertical).textInputAutocapitalization(.sentences)
                TextField("日本語訳（任意）", text: $translation, axis: .vertical)
            } footer: {
                Text("入力した英文はこの端末内だけに保存します。")
            }
            Section("分類・難易度（任意）") {
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
        }
        .navigationTitle("英文を追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("教材を追加") {
                    model.save(text: text, translation: translation, category: category,
                               difficulty: difficulty == 0 ? nil : difficulty, toeicPart: part == 0 ? nil : part)
                    if model.error == nil { dismiss() }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.ready)
            }
        }
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
    @State private var selectionStart: Int?
    @State private var selectionEnd: Int?
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
            Section {
                Button { model.speak(item.text, speed: speed, item: item) } label: {
                    PrimaryActionLabel(title: "お手本を再生", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.speech.busy)
                .listRowSeparator(.hidden)
                if model.speech.busy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(model.speech.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                }
                HStack(spacing: 10) {
                    TransportButton(title: "一時停止", systemImage: "pause.fill") { model.speech.pause() }
                    TransportButton(title: "再開", systemImage: "playpause.fill") { model.speech.resume() }
                    TransportButton(title: model.speech.busy ? "生成を中断" : "再生を停止", systemImage: "stop.fill") { model.stop() }
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
                        .foregroundStyle(.secondary)
                    }
                    Slider(value: $speed, in: 0.5...1.5, step: 0.05)
                        .accessibilityLabel("読み上げ速度")
                        .accessibilityValue("\(speed.formatted(.number.precision(.fractionLength(2))))倍")
                        .disabled(model.speech.busy)
                    HStack {
                        Text("0.50×")
                        Spacer()
                        Button("標準の速度に戻す") { speed = 1.0 }
                            .buttonStyle(.borderless)
                            .disabled(speed == 1.0 || model.speech.busy)
                        Spacer()
                        Text("1.50×")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .onChange(of: speed) { _, value in model.speech.setRate(value) }
                Toggle("音声を繰り返す", isOn: Binding(get: { model.speech.repeats }, set: { model.speech.repeats = $0 }))
            } header: {
                Text("まずは聞いてみましょう")
            }
            Section {
                Toggle("英文を表示", isOn: $showEnglish)
                if showEnglish { Text(item.text).font(.title3).textSelection(.enabled) }
                Toggle("日本語訳を表示", isOn: $showTranslation)
                if showTranslation {
                    Text(item.translation.isEmpty ? "日本語訳は登録されていません。" : item.translation)
                        .foregroundStyle(item.translation.isEmpty ? Color.secondary : Color.primary)
                }
            } header: {
                Text("スクリプト")
            }
            if let lesson = model.generatedLesson(for: item) {
                LessonQuestionSection(model: model, item: item, lesson: lesson)
                    .id(item.updatedAt)
            }
            Section {
                if showEnglish {
                    Text("最初と最後の単語を選ぶと、間のフレーズを選択できます。もう一度選ぶと新しい選択になります。")
                        .font(.caption).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(Array(LessonTextSelection.words(in: item.text).enumerated()), id: \.offset) { index, word in
                            Button(String(word)) {
                                if let start = selectionStart, selectionEnd == nil {
                                    selectionEnd = index
                                    selected = LessonTextSelection.phrase(in: item.text, from: start, through: index) ?? ""
                                } else {
                                    selectionStart = index; selectionEnd = nil
                                    selected = String(word)
                                }
                                saved = false
                            }
                            .buttonStyle(.bordered)
                            .tint(isSelectedWord(index) ? .accentColor : .secondary)
                            .accessibilityIdentifier("lesson.word.\(index)")
                            .accessibilityValue(isSelectedWord(index) ? "選択中" : "未選択")
                        }
                    }
                } else {
                    Text("「英文を表示」をオンにすると、単語をタップして選べます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("単語・フレーズ（空欄で文章全体）", text: $selected)
                    .onChange(of: selected) { _, value in
                        saved = false
                        guard let start = selectionStart else { return }
                        if value != LessonTextSelection.phrase(in: item.text, from: start, through: selectionEnd ?? start) {
                            selectionStart = nil; selectionEnd = nil
                        }
                    }
                Picker("理由", selection: $reason) { ForEach(WeakReason.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Button(saved ? "保存しました" : "復習に登録", systemImage: saved ? "bookmark.fill" : "bookmark") {
                    model.mark(item, text: selected.isEmpty ? item.text : selected, reason: reason)
                    saved = model.error == nil
                }
            } header: {
                Text("苦手箇所を保存")
            }
            Section("お手本の音声") {
                TTSEnginePicker(speech: model.speech)
            }
            if let nextItem {
                Section {
                    NavigationLink { LessonView(model: model, item: nextItem) } label: {
                        Label("次の教材", systemImage: "arrow.right.circle")
                    }
                    .disabled(model.speech.busy || model.speaking.busy || model.speaking.recording)
                }
            }
        }.onChange(of: item.text) { _, _ in
            selectionStart = nil; selectionEnd = nil; selected = ""; saved = false
        }.onDisappear { model.stop() }
    }
    private func isSelectedWord(_ index: Int) -> Bool {
        guard let start = selectionStart else { return false }
        let end = selectionEnd ?? start
        return (min(start, end)...max(start, end)).contains(index)
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
                Text(item.text).font(.title3).textSelection(.enabled)
                Button("お手本を聞く", systemImage: "play.circle") { appModel.speak(item.text, speed: 1, item: item) }
            }
            Section {
                if model.recording {
                    Label("録音中 · 発話後に停止してください", systemImage: "record.circle")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                    Button { model.stopRecording(autoTranscribe: true) } label: {
                        PrimaryActionLabel(title: "録音を停止して文字起こし", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        appModel.stop(); model.startRecording(for: item.id)
                    } label: {
                        PrimaryActionLabel(title: "録音を開始", systemImage: "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.recognitionAvailable || model.busy)
                    if !model.recognitionAvailable {
                        Text("選択中の音声認識を利用できません。下の「音声認識モデル」で準備してください。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                if model.busy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(model.status).font(.caption)
                    }
                    Button("処理を中断", systemImage: "xmark.circle") { model.cancel() }
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
                if !model.status.isEmpty && !model.busy { Text(model.status).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("録音して話す")
            }
            transcriptionResults
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
                Text(model.transcriptUsesREUSE ? "RE-USEで強調した音声を認識" : "元の録音を認識")
                    .font(.caption).foregroundStyle(.secondary)
                Text("単語誤り率：\(result.wordErrorRate, format: .percent.precision(.fractionLength(0)))")
                    .font(.headline)
                    .accessibilityIdentifier("speaking.wordErrorRate")
                Text(model.transcript).textSelection(.enabled)
                    .accessibilityIdentifier("speaking.transcriptionText")
                FlowLayout(spacing: 6) {
                    ForEach(Array(result.tokens.enumerated()), id: \.offset) { _, token in
                        Text(token.expected ?? "＋" + (token.recognized ?? ""))
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((token.kind == .match ? Color.green : Color.orange).opacity(0.2), in: Capsule())
                    }
                }
                .accessibilityHidden(true)
                Text("緑：お手本どおりに認識　橙：違い・欠落・余分な語（詳細は「単語ごとの差分」）")
                    .font(.caption).foregroundStyle(.secondary)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Accessibility text sizes need wider tiles, so every row falls back to two columns.
    private func statColumns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 2 : count)
    }
    var body: some View {
        List {
            let due = model.visiblePoints.filter { $0.nextReviewAt <= Date() }.sorted { $0.nextReviewAt < $1.nextReviewAt }
            Section("今日の復習・\(due.count)件") {
                ForEach(due) { point in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(point.text).font(.headline)
                                Chip(text: point.reason.rawValue, tint: .orange)
                            }
                            Spacer(minLength: 0)
                            Button("聞く", systemImage: "play.circle.fill") { model.speak(point.text, speed: 1, item: model.item(for: point)) }
                                .labelStyle(.iconOnly)
                                .font(.largeTitle)
                                .buttonStyle(.borderless)
                                .disabled(model.speech.busy)
                        }
                        Text("どのくらい分かりましたか？").font(.caption).foregroundStyle(.secondary)
                        ViewThatFits {
                            HStack(spacing: 8) { grades(point) }
                            VStack(alignment: .leading) { grades(point) }
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowSeparator(.hidden)
                    if let item = model.item(for: point) {
                        NavigationLink("元の教材とスピーキング練習") { LessonView(model: model, item: item) }
                            .font(.subheadline)
                            .listRowSeparator(.hidden)
                        NavigationLink("新しい用例で復習") { ReviewExampleView(model: model, point: point, original: item) }
                            .font(.subheadline)
                    }
                }
                if due.isEmpty { ContentUnavailableView("今日の復習は完了です", systemImage: "checkmark.circle", description: Text("聞き取れない表現を教材から登録できます。")) }
            }
            Section("学習の記録") {
                // Two fixed rows: an adaptive grid left the wider labels wrapping mid-word in a fourth column.
                VStack(spacing: 8) {
                    LazyVGrid(columns: statColumns(4), spacing: 8) {
                        StatTile(value: "\(model.progress.currentStreak)日", label: "連続学習", systemImage: "flame.fill", tint: .orange, spokenLabel: "連続学習日数")
                        StatTile(value: "\(model.progress.activeDays)日", label: "学習日数", systemImage: "calendar", spokenLabel: "学習した日")
                        StatTile(value: "\(model.progress.totalReviews)回", label: "累計復習", systemImage: "arrow.clockwise", tint: .indigo)
                        StatTile(value: "\(model.progress.masteredCount)件", label: "定着項目", systemImage: "checkmark.seal.fill", tint: .green, spokenLabel: "定着した項目")
                    }
                    LazyVGrid(columns: statColumns(3), spacing: 8) {
                        StatTile(value: "\(model.activityHistory.filter { $0.activity == .listening }.count)回", label: "リスニング", systemImage: "headphones")
                        StatTile(value: "\(model.activityHistory.filter { $0.activity == .speaking }.count)回", label: "スピーキング", systemImage: "mic.fill", tint: .pink)
                        StatTile(value: "\(model.quizAttempts.count)回", label: "設問への回答", systemImage: "questionmark.circle.fill", tint: .purple)
                    }
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
                NavigationLink("復習履歴を表示") { ReviewHistoryView(model: model) }
            }
            Section("保存済み・\(model.points.count)件") {
                ForEach(model.points.sorted { $0.registeredAt > $1.registeredAt }) { point in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(point.text)
                            Text("登録日：\(point.registeredAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(point.reason.rawValue + " · 復習\(point.reviews)回 · 成功\(point.successes) / 失敗\(point.failures)")
                                .font(.caption).foregroundStyle(.secondary)
                            if let mastery = point.mastery {
                                ProgressView(value: mastery) { Text("習熟度").font(.caption) }
                                Text("\(mastery, format: .percent.precision(.fractionLength(0))) · 次回：\(point.nextReviewAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("未復習 · 次回：\(point.nextReviewAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Button(role: .destructive) { pointToDelete = point } label: {
                            Image(systemName: "trash")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("復習項目を削除")
                            .accessibilityIdentifier("review.delete.\(point.id.uuidString)")
                    }
                    .padding(.vertical, 5)
                    .listRowSeparator(.hidden)

                    if let item = model.item(for: point) {
                        NavigationLink("元の教材を開く") { LessonView(model: model, item: item) }
                            .font(.subheadline)
                            .listRowSeparator(.hidden)
                        NavigationLink("新しい用例で復習") { ReviewExampleView(model: model, point: point, original: item) }
                            .font(.subheadline)
                    }
                }
                if model.points.isEmpty { ContentUnavailableView("復習項目はありません", systemImage: "bookmark", description: Text("リスニングやスピーキングから苦手な表現を登録できます。")) }
            }
            Section("復習の音声") {
                TTSEnginePicker(speech: model.speech)
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
            .accessibilityIdentifier("review.delete.confirm")
        } message: {
            Text("関連する復習履歴も削除されます。この操作は取り消せません。")
        }
    }
    @ViewBuilder func grades(_ point: WeakPoint) -> some View {
        ForEach(ReviewGrade.allCases, id: \.self) { grade in
            Button { model.review(point, grade: grade) } label: {
                Text(grade.rawValue).font(.subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .tint(gradeTint(grade))
        }
    }
    private func gradeTint(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .red
        case .hard: .orange
        case .good: .teal
        case .easy: .green
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
    @AppStorage(RecordingRetention.preferenceKey) private var retainRecording = true
    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "不明"
        let build = info["CFBundleVersion"] as? String ?? "不明"
        return "\(version) (\(build))"
    }
    var body: some View {
        Form {
            Section {
                NavigationLink { TTSModelsView(speech: model.speech) } label: {
                    Label("音声モデル管理", systemImage: "speaker.wave.2")
                }
                NavigationLink { ASRModelsView(model: model.speaking) } label: {
                    Label("ASRモデル管理", systemImage: "mic")
                }
                NavigationLink {
                    LLMLessonGenerationView(model: model.llm, lessons: model.visibleGeneratedLessons, save: model.persistGenerated)
                } label: {
                    Label("LLM教材生成・モデル管理", systemImage: "sparkles")
                }
                NavigationLink { REUSESettingsView(model: model.speaking.reuse) } label: {
                    Label("RE-USE音声強調モデル", systemImage: "waveform.badge.mic")
                }
            } header: {
                Text("音声とAI")
            } footer: {
                Text("読み上げ：\(NeuralVoice(rawValue: model.speech.selected)?.title ?? "Apple・米国英語") · 認識：\(model.speaking.selectedEngine.title)。Kokoro / Pocket TTS、Parakeet ASR、LiteRT-LM、RE-USEを端末内で使用します。")
            }
            Section {
                NavigationLink { TTSComparisonView(speech: model.speech) } label: {
                    Label("TTS聴き比べ・性能測定", systemImage: "ear")
                }
                NavigationLink { ASRComparisonView(appModel: model) } label: {
                    Label("ASR聴き取り比較", systemImage: "text.magnifyingglass")
                }
                NavigationLink { OfflineReadinessView(model: model) } label: {
                    Label("オフライン利用の準備", systemImage: "airplane")
                }
                NavigationLink { ModelInformationView(model: model) } label: {
                    Label("AIモデル情報・状態", systemImage: "info.circle")
                }
            } header: {
                Text("モデルの比較と確認")
            } footer: {
                Text("Apple音声は初回取得が必要な場合があります。機内モードでの再生を実機で確認してください。")
            }
            Section("教材") {
                NavigationLink { LessonLibraryView(model: model) } label: {
                    Label("教材を探す・管理", systemImage: "books.vertical")
                }
            }
            Section {
                Toggle("次回起動後も最新の録音を保持", isOn: $retainRecording)
                    .accessibilityIdentifier("recording.retainOnRestart")
                Text("オフの場合、最新録音は次回アプリ起動時に削除します。今回の練習中は再生・再認識でき、新しい録音は前の録音を置き換えます。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("すべての学習データを削除", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("settings.deleteAllData")
                    .disabled(model.speech.busy || model.speaking.busy || model.speaking.recording || model.llm.busy)
            } header: {
                Text("データとプライバシー")
            } footer: {
                Text("学習データは端末内に保存します。音声録音は端末内の保護領域に保存され、削除できます。録音・学習文はクラウドへ送信しません。")
            }
            Section("アプリと端末") {
                LabeledContent("バージョン", value: appVersion)
                LabeledContent("OS", value: UIDevice.current.systemVersion)
                LabeledContent("物理メモリ", value: ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
                LabeledContent("発熱状態", value: ProcessInfo.processInfo.thermalState.localizedTitle)
                NavigationLink { DiagnosticsView() } label: {
                    Label("端末内診断", systemImage: "stethoscope")
                }
                .accessibilityIdentifier("settings.diagnostics")
            }
        }
        .navigationTitle("設定")
        .alert("教材・復習・録音・生成音声・測定履歴を削除しますか？", isPresented: $confirmDelete) {
            Button("削除", role: .destructive) { model.deleteAllLearningData() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
    }
}

/// On-device diagnostic history and explicit export, separated from everyday settings.
struct DiagnosticsView: View {
    @State private var diagnosticEvents: [DiagnosticEvent] = []
    @State private var diagnosticExport: String?
    @State private var confirmClear = false
    private func loadDiagnosticEvents() async -> [DiagnosticEvent] {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--uitest-seed-diagnostics") {
            return (0..<100).map { index in
                DiagnosticEvent(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                    subsystem: .app, action: .appLaunch, model: .system, outcome: .observed,
                    peakMemoryBytes: 100_000_000, thermalState: .nominal
                )
            }
        }
        #endif
        return await DiagnosticEventLog.shared.recentEvents()
    }
    var body: some View {
        List {
            Section {
                Button("共有用の診断情報を作成", systemImage: "doc.badge.gearshape") {
                    Task { diagnosticExport = try? await DiagnosticEventLog.shared.exportJSON() }
                }
                if let diagnosticExport {
                    ShareLink("診断情報を共有", item: diagnosticExport)
                    Text("共有先は次の画面で選びます。記録時刻と識別子、教材・録音・文字起こしは含めません。処理種別や性能値は含まれます。")
                        .font(.caption)
                }
                Button("診断ログを消去", systemImage: "trash", role: .destructive) { confirmClear = true }
                    .tint(.red)
                    .disabled(diagnosticEvents.isEmpty)
            } footer: {
                Text("直近500件を端末内に保存します。教材文、録音、文字起こし、入力内容、エラー文は保存しません。")
            }
            Section("記録・\(diagnosticEvents.count)件") {
                #if DEBUG && targetEnvironment(simulator)
                if diagnosticEvents.count == 100 {
                    Text("診断行のテスト用データを読み込みました")
                        .accessibilityIdentifier("diagnostics.uiTestSeedLoaded")
                }
                #endif
                if diagnosticEvents.isEmpty {
                    Text("記録はありません。").foregroundStyle(.secondary)
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
                            Text("発熱状態 \(event.thermalState.localizedTitle)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 3)
                    }
                }
            }
        }
        .task { diagnosticEvents = await loadDiagnosticEvents() }
        .navigationTitle("端末内診断")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("診断ログを消去しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("診断ログを消去", role: .destructive) {
                Task {
                    await DiagnosticEventLog.shared.clear()
                    diagnosticEvents = []
                    diagnosticExport = nil
                }
            }
        } message: {
            Text("学習データは消去されません。")
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
