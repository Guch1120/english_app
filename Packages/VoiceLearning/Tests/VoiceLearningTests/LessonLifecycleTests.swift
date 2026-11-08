import Foundation
import XCTest
import CSQLite
import LearningCore
import LearningPersistence
import LLMCore

final class LessonLifecycleTests: XCTestCase, @unchecked Sendable {
    private func lesson(id: UUID = UUID(), text: String = "Please confirm the booking.",
                        choices: [String] = ["The booking", "A payment", "A report", "A schedule"],
                        generatedAt: Date = Date(timeIntervalSince1970: 1_000), editedAt: Date? = nil) -> GeneratedLesson {
        GeneratedLesson(id: id, kind: "TOEIC Part 3 conversation", difficulty: 2, text: text,
            translation: "予約を確認してください。", targetPhrases: ["confirm the booking"],
            question: "What should be confirmed?", choices: choices, answerIndex: 0,
            explanation: "The reservation should be checked.", modelID: "fixture-model",
            generatedAt: generatedAt, editedAt: editedAt)
    }

    @MainActor func testVersionThreeDatabaseMigratesWithoutLosingLegacyItems() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let id = UUID()
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &db), SQLITE_OK)
        let fixture = """
        CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY);
        INSERT INTO schema_migrations VALUES(1),(2),(3);
        CREATE TABLE learning_items(id TEXT PRIMARY KEY, payload TEXT NOT NULL);
        INSERT INTO learning_items VALUES('\(id.uuidString)', '{"id":"\(id.uuidString)","text":"Legacy lesson","translation":"旧教材","updatedAt":0}');
        """
        XCTAssertEqual(sqlite3_exec(db, fixture, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        var store: LearningStore? = try LearningStore(path: file.path)
        let item = try XCTUnwrap(store?.items().first)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.text, "Legacy lesson")
        XCTAssertEqual(item.category, .sentence)
        XCTAssertNil(item.difficulty)
        XCTAssertNil(item.toeicPart)
        try store?.save(LessonPreferences(itemID: id, hidden: true, issueNote: "Check translation"))
        let attempt = QuizAttempt(itemID: id, itemUpdatedAt: item.updatedAt, selectedIndex: 1, correctIndex: 0)
        try store?.save(attempt)
        store = nil
        let reopened = try LearningStore(path: file.path)
        XCTAssertEqual(try reopened.items(), [item])
        XCTAssertTrue(try XCTUnwrap(reopened.lessonPreferences().first).hidden)
        XCTAssertEqual(try reopened.quizAttempts(), [attempt])
        XCTAssertEqual(try reopened.activityHistory().first?.activity, .quiz)
    }

    @MainActor func testCorrectionPreservesAttributionFeedbackAndPriorAnswerVersion() async throws {
        let store = try LearningStore(path: ":memory:")
        let original = lesson()
        try store.save(original)
        let oldItem = try XCTUnwrap(store.items().first)
        XCTAssertEqual(oldItem.category, .conversation)
        XCTAssertEqual(oldItem.toeicPart, 3)
        XCTAssertEqual(oldItem.difficulty, 2)
        let oldAttempt = QuizAttempt(itemID: original.id, itemUpdatedAt: oldItem.updatedAt,
                                     selectedIndex: 2, correctIndex: 0,
                                     question: original.question, choices: original.choices)
        try store.save(oldAttempt)
        let preferences = LessonPreferences(itemID: original.id, hidden: true, issueNote: "Needs review")
        try store.save(preferences)
        let editedAt = Date(timeIntervalSince1970: 2_000)
        let edited = lesson(id: original.id, text: "Please confirm your reservation.", editedAt: editedAt)
        try store.save(edited)
        let updated = try XCTUnwrap(store.items().first)
        XCTAssertEqual(updated.text, edited.text)
        XCTAssertEqual(updated.updatedAt, editedAt)
        let restored = try XCTUnwrap(store.generatedLessons().first)
        XCTAssertEqual(restored.generatedAt, original.generatedAt)
        XCTAssertEqual(restored.modelID, original.modelID)
        XCTAssertEqual(restored.editedAt, editedAt)
        XCTAssertEqual(try store.lessonPreferences(), [preferences])
        XCTAssertEqual(try store.quizAttempts(), [oldAttempt])
        XCTAssertNotEqual(oldAttempt.itemUpdatedAt, updated.updatedAt)
        let invalid = lesson(id: original.id, text: "Invalid replacement", choices: ["Same", "same", "C", "D"])
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.items().first?.text, edited.text)
        XCTAssertEqual(try store.generatedLessons().first?.text, edited.text)
    }

    @MainActor func testAnswersAndActivityRemainAtomicAndDeleteAllClearsNewPersonalData() async throws {
        let store = try LearningStore(path: ":memory:")
        let missing = QuizAttempt(itemID: UUID(), itemUpdatedAt: Date(), selectedIndex: 0, correctIndex: 0)
        XCTAssertThrowsError(try store.save(missing))
        XCTAssertTrue(try store.quizAttempts().isEmpty)
        XCTAssertTrue(try store.activityHistory().isEmpty)
        let generated = lesson()
        try store.save(generated)
        let item = try XCTUnwrap(store.items().first)
        try store.save(QuizAttempt(itemID: item.id, itemUpdatedAt: item.updatedAt, selectedIndex: 0, correctIndex: 0))
        try store.save(LessonPreferences(itemID: item.id, issueNote: "Review later"))
        XCTAssertEqual(try store.quizAttempts().count, 1)
        XCTAssertEqual(try store.activityHistory().count, 1)
        XCTAssertThrowsError(try store.save(LessonPreferences(itemID: item.id, issueNote: String(repeating: "x", count: 2_001))))
        try store.deleteAll()
        XCTAssertTrue(try store.items().isEmpty)
        XCTAssertTrue(try store.generatedLessons().isEmpty)
        XCTAssertTrue(try store.quizAttempts().isEmpty)
        XCTAssertTrue(try store.lessonPreferences().isEmpty)
        XCTAssertTrue(try store.activityHistory().isEmpty)
    }

    func testModelOutputCannotClaimEditedStatusOrOverwriteIdentity() throws {
        let generated = lesson(editedAt: Date(timeIntervalSince1970: 10))
        let attributed = generated.attributing(modelID: "actual-model")
        XCTAssertNil(attributed.editedAt)
        XCTAssertEqual(attributed.modelID, "actual-model")
        XCTAssertNotEqual(attributed.id, generated.id)
        XCTAssertNotEqual(attributed.id, generated.attributing(modelID: "actual-model").id)
    }
}
