import SwiftUI
import AVFoundation
import LearningCore
import LearningPersistence

@main struct EnglishTrainerApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}
@MainActor @Observable final class AppModel {
    var items: [LearningItem] = []
    var points: [WeakPoint] = []
    var error: String?
    var ready = false
    private var store: LearningStore?
    private let speaker = AVSpeechSynthesizer()
    init() {
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
    func speak(_ text: String, speed: Double) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            speaker.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: text)
            guard let voice = AVSpeechSynthesisVoice(language: "en-US") else { error = "英語のシステム音声を端末に追加してください。"; return }
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
            speaker.speak(utterance)
        } catch { self.error = String(describing: error) }
    }
    func stop() { speaker.stopSpeaking(at: .immediate) }
}
struct RootView: View {
    @State private var model = AppModel()
    var body: some View {
        TabView {
            NavigationStack { HomeView(model: model) }.tabItem { Label("学習", systemImage: "headphones") }
            NavigationStack { ReviewView(model: model) }.tabItem { Label("復習", systemImage: "arrow.clockwise") }
            NavigationStack { SettingsView(model: model) }.tabItem { Label("設定", systemImage: "gearshape") }
        }
        .tint(.teal)
        .alert("処理できませんでした", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("閉じる") { model.error = nil }
        } message: { Text(model.error ?? "") }
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
    @State private var speed = 1.0
    @State private var selected = ""
    @State private var reason = WeakReason.listening
    @State private var saved = false
    var body: some View {
        Form {
            Section("まずは聞いてみましょう") {
                Button { model.speak(item.text, speed: speed) } label: {
                    Label("お手本を再生", systemImage: "play.circle.fill").font(.title2).frame(maxWidth: .infinity, minHeight: 70)
                }
                Button("再生を停止", systemImage: "stop.circle") { model.stop() }
                Picker("読み上げ速度", selection: $speed) {
                    Text("0.75×").tag(0.75); Text("1×").tag(1.0); Text("1.2×").tag(1.2)
                }
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
                NavigationLink("文字起こし比較を試す") { SpeakingPreview(item: item) }
                Text("Phase 1：録音・ASRは未接続です。比較画面は入力テキストで確認できます。").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("リスニング").onDisappear { model.stop() }
    }
}
struct SpeakingPreview: View {
    let item: LearningItem
    @State private var recognized = ""
    var body: some View {
        Form {
            Section("お手本") { Text(item.text) }
            Section("比較する文字起こし（手入力）") { TextField("認識結果を入力", text: $recognized, axis: .vertical) }
            if !recognized.isEmpty {
                let result = WordAlignment.compare(expected: item.text, recognized: recognized)
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
                }
            }
        }.navigationTitle("文字起こし比較")
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
    var body: some View {
        Form {
            Section("音声とAI") {
                LabeledContent("TTS", value: "Apple・米国英語")
                Text("Kokoro / Pocket TTS / Parakeet / Gemma / RE-USE は未接続です。実機検証後に順次追加します。")
                Text("Apple音声は初回取得が必要な場合があります。機内モードでの再生を実機で確認してください。").font(.caption)
            }
            Section("端末") {
                LabeledContent("OS", value: UIDevice.current.systemVersion)
                LabeledContent("物理メモリ", value: ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
                LabeledContent("発熱状態", value: String(describing: ProcessInfo.processInfo.thermalState))
            }
            Section("データ") {
                Text("学習データは端末内SQLiteへ保存します。OSバックアップの対象です。録音・クラウド同期はまだありません。")
                Button("すべての学習データを削除", role: .destructive) { confirmDelete = true }
            }
        }.navigationTitle("設定")
        .confirmationDialog("教材・復習・履歴を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { model.perform { try $0.deleteAll() } }
        }
    }
}
