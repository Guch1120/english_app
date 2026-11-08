import SwiftUI
import LLMCore
import ModelManagement

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
                    if let memory = metrics.peakProcessMemoryBytes { LabeledContent("プロセス最大メモリ", value: ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)) }
                    Text("メモリは音声処理などを含むアプリ全体のRSSです。モデル単体の割当量ではありません。")
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
    let save: @MainActor (GeneratedLesson) -> Void
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
                        save(generated)
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
