import SwiftUI
import LLMCore
import ModelManagement
import LearningCore

struct ReviewExampleView: View {
    let model: AppModel
    let point: WeakPoint
    let original: LearningItem
    @State private var phrase: String
    @State private var topic = "元の教材とは異なる日常・仕事の場面"
    @State private var difficulty: Int
    init(model: AppModel, point: WeakPoint, original: LearningItem) {
        self.model = model; self.point = point; self.original = original
        _phrase = State(initialValue: point.text.count <= 120 ? point.text : "")
        _difficulty = State(initialValue: original.difficulty ?? 2)
    }
    private var canGenerate: Bool {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 120 && !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && topic.count <= 120
            && model.llm.selectedRuntimeIsVerified && !model.llm.busy
    }
    var body: some View {
        Form {
            Section("登録した苦手表現") {
                Text(point.text)
                Text(point.reason.rawValue).font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("元の文脈を確認") { Text(original.text) }
            }
            Section("別の文脈を作る") {
                TextField("使いたい単語・フレーズ（120文字以内）", text: $phrase, axis: .vertical)
                    .accessibilityIdentifier("review.examplePhrase")
                if point.text.count > 120 { Text("文章全体を登録した項目です。練習したい短い表現を入力してください。").font(.caption) }
                TextField("新しい場面（120文字以内）", text: $topic)
                Stepper("難易度: \(difficulty) / 5", value: $difficulty, in: 1...5)
                Button("別の用例を端末内で生成") {
                    model.llm.generate(topic: topic, difficulty: difficulty, phrases: [phrase], kind: "review example",
                        previousContext: original.text, sourceWeakPointID: point.id, save: model.persistGenerated)
                }.disabled(!canGenerate)
                if !model.llm.selectedRuntimeIsVerified {
                    Text("確認済みのLLMモデルが必要です。モデル管理で準備・端末確認を行ってください。").font(.caption)
                }
                NavigationLink("LLMモデル管理") { LLMModelsView(model: model.llm) }
                Text("元の復習予定は変えず、生成した用例を別教材として保存します。生成内容は正確さを保証できないため、教材画面で修正・問題メモを残せます。").font(.caption)
            }.disabled(model.llm.busy)
            if model.llm.busy {
                Section { ProgressView(); Text(model.llm.status); Button("生成を中断") { model.llm.cancelCurrentOperation() } }
            } else if !model.llm.status.isEmpty { Section { Text(model.llm.status) } }
            Section("この表現から作った用例") {
                let lessons = model.visibleGeneratedLessons.filter { $0.sourceWeakPointID == point.id }
                ForEach(lessons) { lesson in
                    if let item = model.items.first(where: { $0.id == lesson.id }) {
                        NavigationLink { LessonView(model: model, item: item) } label: {
                            VStack(alignment: .leading) {
                                Text("用例でリスニング・スピーキング")
                                Text(lesson.generatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            }
                        }
                    }
                }
                if lessons.isEmpty { Text("まだ用例はありません。生成後はここから学習でき、学習一覧にも保存されます。").font(.caption) }
            }
        }.navigationTitle("新しい用例で復習")
            .onDisappear { model.llm.cancelCurrentOperation() }
            .alert("用例を生成できませんでした", isPresented: Binding(get: { model.llm.error != nil }, set: { if !$0 { model.llm.error = nil } })) {
                Button("閉じる") { model.llm.error = nil }
            } message: { Text(model.llm.error ?? "") }
    }
}

struct LLMModelsView: View {
    @Bindable var model: LLMTrainingModel
    @State private var confirmRemoval: HostedModelCandidate?
    var body: some View {
        List {
            Section("LiteRT-LMモデルを検索") {
                HStack {
                    TextField("モデル名", text: $model.query).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("検索") { model.search() }.disabled(model.busy)
                }
                Text("検索語だけがHugging Faceへ送られます。教材文・録音は送信しません。対象はLiteRT CommunityのApache-2.0モデルで、モデル重みだけを検証して保存します。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.busy {
                Section {
                    ProgressView(value: model.progress > 0 ? model.progress : nil)
                    Text(model.status).font(.footnote).foregroundStyle(.secondary)
                }
            } else if !model.status.isEmpty {
                Section { Text(model.status).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("対応モデル") {
                if model.candidates.isEmpty {
                    Text("保存済みモデル情報はありません。モデルを探すにはインターネット接続が必要です。以前に準備したモデルは、保存済み情報を使ってオフラインで表示されます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(model.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(candidate.displayName).font(.subheadline.weight(.semibold))
                            .textSelection(.enabled)
                        Text("\(ByteCountFormatter.string(fromByteCount: candidate.sizeBytes, countStyle: .file)) · \(candidate.license) · revision \(candidate.revision.prefix(8))")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            if model.installedIDs.contains(candidate.id) {
                                Button(model.selectedID == candidate.id ? "使用中" : "使用する") { model.select(candidate) }
                                    .buttonStyle(.borderedProminent).disabled(model.selectedID == candidate.id || model.busy)
                                if model.runtimeIsVerified(candidate) {
                                    Label("端末確認済み", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                                } else {
                                    Button("端末で動作確認") { model.verifyRuntime(candidate) }.disabled(model.busy)
                                }
                                Spacer()
                                Button("削除", role: .destructive) { confirmRemoval = candidate }.disabled(model.busy)
                            } else {
                                Button("ダウンロード・検証") { model.install(candidate) }.buttonStyle(.borderedProminent).disabled(model.busy)
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }
            if let metrics = model.latestMetrics {
                Section("直近の生成性能") {
                    if let load = metrics.modelLoadSeconds { LabeledContent("モデル読み込み", value: String(format: "%.1f秒", load)) }
                    if let first = metrics.timeToFirstResponseSeconds { LabeledContent("最初の応答", value: String(format: "%.1f秒", first)) }
                    LabeledContent("生成時間", value: String(format: "%.1f秒", metrics.generationSeconds))
                    LabeledContent("出力", value: "\(metrics.outputCharacters)文字")
                    if let speed = metrics.decodeTokensPerSecond {
                        LabeledContent("デコード速度", value: String(format: "%.1f tokens/sec", speed))
                    }
                    if let memory = metrics.peakProcessMemoryBytes { LabeledContent("プロセス最大メモリ", value: ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)) }
                    Text("メモリは音声処理などを含むアプリ全体のRSSです。モデル単体の割当量ではありません。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("デコード速度はLiteRT-LMの実測値です。対応する値が得られない場合は表示されません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("LLMモデル管理")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { if model.busy { Button("中止", role: .cancel) { model.cancelCurrentOperation() } } }
            ToolbarItem(placement: .topBarTrailing) { Button("Gemma 4を探す") { model.query = "gemma-4-E2B"; model.search() }.disabled(model.busy) }
        }
        .confirmationDialog("このモデルを端末から削除しますか？", isPresented: Binding(get: { confirmRemoval != nil }, set: { if !$0 { confirmRemoval = nil } }), titleVisibility: .visible) {
            if let candidate = confirmRemoval { Button("モデルを削除", role: .destructive) { model.remove(candidate) } }
            Button("キャンセル", role: .cancel) { confirmRemoval = nil }
        } message: { Text("保存したモデルファイルを削除します。") }
        .alert("モデル処理に失敗しました", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("閉じる") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

struct LLMLessonGenerationView: View {
    @Bindable var model: LLMTrainingModel
    let lessons: [GeneratedLesson]
    let save: @MainActor (GeneratedLesson) throws -> Void
    @State private var topic = "出張先でのホテル予約"
    @State private var phrases = "confirm the reservation, check in"
    @State private var kind = "business conversation"
    @State private var difficulty = 2
    @State private var lesson: GeneratedLesson?
    var body: some View {
        Form {
            Section("教材の条件") {
                TextField("テーマ", text: $topic)
                Picker("教材タイプ", selection: $kind) {
                    Text("ビジネス会話").tag("business conversation")
                    Text("日常会話").tag("daily conversation")
                    Text("TOEIC形式").tag("TOEIC-style listening")
                    ForEach(1...4, id: \.self) { Text("TOEIC Part \($0)").tag("TOEIC Part \($0) listening") }
                    Text("語彙・用例").tag("vocabulary example")
                }
                Stepper("難易度: \(difficulty) / 5", value: $difficulty, in: 1...5)
                TextField("含めたい語句（カンマ区切り）", text: $phrases, axis: .vertical).lineLimit(2...4)
                Button {
                    lesson = nil
                    model.generate(topic: topic, difficulty: difficulty,
                                   phrases: phrases.split(separator: ",").map(String.init), kind: kind, save: { generated in
                        try save(generated)
                        lesson = generated
                    })
                } label: {
                    if model.busy { ProgressView(model.status) }
                    else { Label("端末内で教材を生成", systemImage: "sparkles") }
                }.disabled(model.busy || topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.selectedRuntimeIsVerified)
                if !model.selectedRuntimeIsVerified {
                    Text("未確認のLLMは教材生成に使えません。モデルを準備してから、端末上の固定テストを実行してください。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                NavigationLink("モデル検索・管理") { LLMModelsView(model: model) }
            }
            if let lesson {
                Section("生成した英文") {
                    Text(lesson.text).font(.headline)
                    Text(lesson.translation).foregroundStyle(.secondary)
                    Text("語句: \(lesson.targetPhrases.joined(separator: " · "))").font(.footnote)
                }
                Section(lesson.question) {
                    ForEach(Array(lesson.choices.enumerated()), id: \.offset) { index, choice in
                        Label(choice, systemImage: index == lesson.answerIndex ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(index == lesson.answerIndex ? .green : .primary)
                    }
                    Text(lesson.explanation).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("モデル", value: lesson.modelID)
                    LabeledContent("難易度", value: "\(lesson.difficulty) / 5")
                    LabeledContent("生成日時", value: lesson.generatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            if !lessons.isEmpty {
                Section("保存済みの生成教材") {
                    ForEach(lessons) { saved in
                        Button {
                            lesson = saved
                        } label: {
                            VStack(alignment: .leading) {
                                Text(saved.text).foregroundStyle(.primary).lineLimit(2)
                                Text("\(saved.generatedAt.formatted(date: .abbreviated, time: .shortened)) · \(saved.modelID)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !model.status.isEmpty { Section { Text(model.status).font(.footnote).foregroundStyle(.secondary) } }
        }
        .navigationTitle("教材を生成")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { if model.busy { Button("中止", role: .cancel) { model.cancelCurrentOperation() } } } }
        .alert("生成できませんでした", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("閉じる") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
