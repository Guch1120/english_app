import Foundation
import XCTest
@testable import LearningCore
import LearningPersistence
import LLMCore
import ModelManagement

final class CoreTests: XCTestCase {
    func testAlignmentSubstitutionDeletionInsertionAndNormalization() {
        let r = WordAlignment.compare(expected: "Could you reschedule the meeting for Thursday?", recognized: "could you schedule the meeting for thursday")
        XCTAssertEqual(r.tokens.filter { $0.kind == .substitution }.map(\.expected), ["reschedule"])
        XCTAssertEqual(r.wordErrorRate, 1.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(WordAlignment.compare(expected: "a b", recognized: "a").tokens.last?.kind, .deletion)
        XCTAssertEqual(WordAlignment.compare(expected: "a", recognized: "a b").tokens.last?.kind, .insertion)
        XCTAssertEqual(WordAlignment.compare(expected: "", recognized: "").wordErrorRate, 0)
        XCTAssertEqual(WordAlignment.compare(expected: "Hello, WORLD!", recognized: "hello world").wordErrorRate, 0)
    }
    func testReviewSchedule() {
        let now = Date(timeIntervalSince1970: 1000)
        let point = WeakPoint(itemID: UUID(), text: "meeting", reason: .listening, now: now)
        let scheduler = SpacedReviewScheduler()
        let again = scheduler.schedule(point, grade: .again, now: now)
        XCTAssertEqual(again.nextReviewAt.timeIntervalSince(now), 600)
        XCTAssertEqual(again.failures, 1)
        let good = scheduler.schedule(point, grade: .good, now: now)
        XCTAssertEqual(good.nextReviewAt.timeIntervalSince(now), 2 * 86400)
        XCTAssertEqual(good.successes, 1)
        XCTAssertEqual(scheduler.schedule(good, grade: .good, now: now).intervalDays, 4)
    }
    @MainActor func testSQLiteRoundTripReviewHistoryAndDeletion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let item = LearningItem(text: "It's a meeting; DROP TABLE learning_items;", translation: "会議")
        let point = WeakPoint(itemID: item.id, text: "meeting", reason: .meaning)
        do {
            let store = try LearningStore(path: url.path)
            try store.save(item); try store.save(point)
            _ = try store.review(point, grade: .easy, now: Date(timeIntervalSince1970: 0))
        }
        let reopened = try LearningStore(path: url.path)
        XCTAssertEqual(try reopened.items(), [item])
        XCTAssertEqual(try reopened.weakPoints().first?.reviews, 1)
        XCTAssertEqual(try reopened.weakPoints().first?.intervalDays, 4)
        XCTAssertThrowsError(try reopened.save(WeakPoint(itemID: UUID(), text: "orphan", reason: .other)))
        try reopened.deleteAll()
        XCTAssertTrue(try reopened.items().isEmpty)
        XCTAssertTrue(try reopened.weakPoints().isEmpty)
    }
    func testGeneratedContentRejectsInvalidAnswer() throws {
        let data = Data(#"{"text":"Hello","translation":"こんにちは","choices":["a","b"],"answerIndex":4}"#.utf8)
        let lesson = try JSONDecoder().decode(GeneratedLesson.self, from: data)
        XCTAssertThrowsError(try lesson.validated())
    }
    func testCoordinatorReleasesAfterFailure() async throws {
        let coordinator = ModelRuntimeCoordinator()
        enum Failure: Error { case expected }
        do { let _: Int = try await coordinator.withExclusiveModel { throw Failure.expected }; XCTFail() } catch {}
        let value = try await coordinator.withExclusiveModel { 42 }
        XCTAssertEqual(value, 42)
    }
}
