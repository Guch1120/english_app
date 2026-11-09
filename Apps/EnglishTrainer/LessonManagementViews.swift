import SwiftUI
import LearningCore
import LLMCore

struct LessonQuestionSection: View {
    let model: AppModel
    let item: LearningItem
    let lesson: GeneratedLesson
    @State private var selected: Int?
    @State private var retrying = false
    private var previous: QuizAttempt? {
        model.quizAttempts.first { $0.itemID == item.id && $0.itemUpdatedAt == item.updatedAt }
    }
    private var result: QuizAttempt? { retrying ? nil : previous }

    var body: some View {
        Section("設問") {
            Text(lesson.question).font(.headline)
            ForEach(Array(lesson.choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    selected = index
                } label: {
                    HStack {
                        Image(systemName: (result?.selectedIndex ?? selected) == index ? "checkmark.circle.fill" : "circle")
                        Text(choice).foregroundStyle(.primary)
                    }
                }
                .accessibilityIdentifier("lesson.choice.\(index)")
                .disabled(result != nil)
            }
            if let result {
                Label(result.correct ? "正解です" : "もう一度確認しましょう",
                      systemImage: result.correct ? "checkmark.circle.fill" : "arrow.clockwise.circle")
                    .foregroundStyle(result.correct ? Color.green : Color.orange)
                    .accessibilityIdentifier("lesson.answerResult")
                Text("正解：\(lesson.choices[lesson.answerIndex])")
                Text(lesson.explanation).textSelection(.enabled)
                Text("AIが生成した設問です。誤りがあれば「教材の操作」から修正や問題の記録ができます。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("もう一度回答") { selected = nil; retrying = true }
                if !result.correct {
                    Button("この教材を復習に登録") { model.mark(item, text: item.text, reason: .meaning) }
                }
            } else {
                Button("回答を確認") {
                    guard result == nil, let selected else { return }
                    model.answer(lesson, item: item, selectedIndex: selected)
                    if model.error == nil { retrying = false }
                }
                .disabled(selected == nil)
            }
        }
    }
}

struct LessonEditorView: View {
    let model: AppModel
    let item: LearningItem
    private let original: GeneratedLesson?
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var translation: String
    @State private var category: LearningCategory
    @State private var difficulty: Int
    @State private var part: Int
    @State private var kind: String
    @State private var phrases: String
    @State private var question: String
    @State private var choices: [String]
    @State private var answer: Int
    @State private var explanation: String

    init(model: AppModel, item: LearningItem) {
        self.model = model; self.item = item
        let original = model.generatedLesson(for: item)
        self.original = original
        _text = State(initialValue: item.text)
        _translation = State(initialValue: item.translation)
        _category = State(initialValue: item.category)
        _difficulty = State(initialValue: original?.difficulty ?? item.difficulty ?? 0)
        _part = State(initialValue: item.toeicPart ?? 0)
        _kind = State(initialValue: original?.kind ?? "")
        _phrases = State(initialValue: original?.targetPhrases.joined(separator: ", ") ?? "")
        _question = State(initialValue: original?.question ?? "")
        _choices = State(initialValue: original?.choices ?? Array(repeating: "", count: 4))
        _answer = State(initialValue: original?.answerIndex ?? 0)
        _explanation = State(initialValue: original?.explanation ?? "")
    }

    private var draft: GeneratedLesson? {
        guard let original else { return nil }
        return GeneratedLesson(id: original.id, kind: kind, difficulty: difficulty,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines), translation: translation,
            targetPhrases: phrases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            question: question, choices: choices, answerIndex: answer, explanation: explanation,
            modelID: original.modelID, promptVersion: original.promptVersion,
            generatedAt: original.generatedAt, editedAt: Date(), sourceWeakPointID: original.sourceWeakPointID)
    }
    private var valid: Bool {
        if let draft { return (try? draft.validated()) != nil }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var body: some View {
        Form {
            Section("教材") {
                TextField("英文", text: $text, axis: .vertical).lineLimit(3...10)
                TextField("日本語訳", text: $translation, axis: .vertical).lineLimit(2...8)
                if original == nil {
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
            if let original {
                Section("設問の修正") {
                    TextField("教材タイプ", text: $kind)
                    Stepper("難易度：\(difficulty) / 5", value: $difficulty, in: 1...5)
                    TextField("対象語句（カンマ区切り）", text: $phrases, axis: .vertical)
                    TextField("設問", text: $question, axis: .vertical)
                        .accessibilityIdentifier("lesson.editor.question")
                    ForEach(choices.indices, id: \.self) { index in
                        TextField("選択肢\(index + 1)", text: $choices[index], axis: .vertical)
                    }
                    Picker("正解の選択肢", selection: $answer) {
                        ForEach(choices.indices, id: \.self) { Text("選択肢\($0 + 1)").tag($0) }
                    }
                    TextField("解説", text: $explanation, axis: .vertical).lineLimit(3...10)
                }
                Section("生成元") {
                    Text(original.modelID).font(.caption).textSelection(.enabled)
                    Text(original.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("修正後も生成元と生成日時を保持します。過去の回答履歴は修正前の記録として残ります。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !valid {
                    Text("英文・訳・設問・解説・対象語句と、重複しない4つの選択肢、正解を設定してください。各項目には文字数の上限があります。")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("教材を修正")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    model.stop()
                    if let draft { model.saveGenerated(draft) }
                    else {
                        model.saveItem(LearningItem(id: item.id,
                            text: text.trimmingCharacters(in: .whitespacesAndNewlines), translation: translation,
                            updatedAt: Date(), category: category, difficulty: difficulty == 0 ? nil : difficulty,
                            toeicPart: part == 0 ? nil : part))
                    }
                    if model.error == nil { dismiss() }
                }.disabled(!valid)
            }
        }
    }
}

struct LessonIssueView: View {
    let model: AppModel
    let item: LearningItem
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    init(model: AppModel, item: LearningItem) {
        self.model = model; self.item = item
        _note = State(initialValue: model.lessonPreferences[item.id]?.issueNote ?? "")
    }
    var body: some View {
        Form {
            Section("気になった点") {
                TextEditor(text: $note).frame(minHeight: 160).accessibilityLabel("教材の問題メモ")
                Text("\(note.count) / 2000文字").font(.caption).foregroundStyle(.secondary)
                Text("この端末に記録します。外部への送信は行いません。教材管理で要確認の教材を探せます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("問題を記録")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    model.saveIssue(note, itemID: item.id)
                    if model.error == nil { dismiss() }
                }.disabled(note.count > 2_000)
            }
        }
    }
}

struct LessonLibraryView: View {
    let model: AppModel
    @State private var category = "all"
    @State private var difficulty = 0
    @State private var part = 0
    @State private var includeHidden = false
    @State private var issuesOnly = false
    @State private var query = ""
    private var filtered: [LearningItem] {
        model.items.filter { item in
            (includeHidden || model.lessonPreferences[item.id]?.hidden != true) &&
            (category == "all" || item.category.rawValue == category) &&
            (difficulty == 0 || item.difficulty == difficulty) &&
            (part == 0 || item.toeicPart == part) &&
            (query.isEmpty || item.text.localizedCaseInsensitiveContains(query) || item.translation.localizedCaseInsensitiveContains(query)) &&
            (!issuesOnly || !(model.lessonPreferences[item.id]?.issueNote ?? "").isEmpty)
        }
    }
    var body: some View {
        List {
            Section("絞り込み") {
                Picker("カテゴリ", selection: $category) {
                    Text("すべて").tag("all")
                    ForEach(LearningCategory.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Picker("難易度", selection: $difficulty) {
                    Text("すべて").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0) / 5").tag($0) }
                }
                Picker("TOEIC分類", selection: $part) {
                    Text("すべて").tag(0)
                    ForEach(1...4, id: \.self) { Text("Part \($0)").tag($0) }
                }
                Toggle("非表示の教材も含める", isOn: $includeHidden)
                Toggle("問題メモのある教材のみ", isOn: $issuesOnly)
            }
            Section("教材・\(filtered.count)件") {
                ForEach(filtered) { item in
                    NavigationLink { LessonView(model: model, item: item) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.text).lineLimit(2)
                            Text(item.category.title + (item.difficulty.map { " · 難易度\($0)" } ?? "") +
                                 (item.toeicPart.map { " · Part \($0)" } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                            if model.lessonPreferences[item.id]?.hidden == true { Label("非表示", systemImage: "eye.slash").font(.caption) }
                            if !(model.lessonPreferences[item.id]?.issueNote ?? "").isEmpty { Label("要確認", systemImage: "flag").font(.caption) }
                        }
                    }
                }
                if filtered.isEmpty { Text("条件に一致する教材はありません。") }
            }
        }
        .navigationTitle("教材を探す・管理")
        .searchable(text: $query, prompt: "英文・日本語訳を検索")
    }
}
