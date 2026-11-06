import Foundation
import XCTest
@testable import LearningCore
import LearningPersistence
import LLMCore
import ModelManagement
import AudioEnhancementBackends

// Stateless test case; individual async tests own their actor-confined fixtures.
final class CoreTests: XCTestCase, @unchecked Sendable {
    func testAlignmentSubstitutionDeletionInsertionAndNormalization() {
        let r = WordAlignment.compare(expected: "Could you reschedule the meeting for Thursday?", recognized: "could you schedule the meeting for thursday")
        XCTAssertEqual(r.tokens.filter { $0.kind == .substitution }.map(\.expected), ["reschedule"])
        XCTAssertEqual(r.wordErrorRate, 1.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(WordAlignment.compare(expected: "a b", recognized: "a").tokens.last?.kind, .deletion)
        XCTAssertEqual(WordAlignment.compare(expected: "a", recognized: "a b").tokens.last?.kind, .insertion)
        XCTAssertEqual(WordAlignment.compare(expected: "", recognized: "").wordErrorRate, 0)
        XCTAssertEqual(WordAlignment.compare(expected: "Hello, WORLD!", recognized: "hello world").wordErrorRate, 0)
        XCTAssertEqual(WordAlignment.compare(expected: "I can't pay $25 today", recognized: "I cannot pay twenty-five today").wordErrorRate, 0)
        XCTAssertEqual(WordAlignment.compare(expected: "It's 2.5 miles", recognized: "It is two point five miles").wordErrorRate, 0)
    }

    #if !canImport(ReuseKit)
    func testREUSEBackendStaysUnavailableOutsideSupportedAppleRuntime() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = try REUSEAudioEnhancement(applicationSupportDirectory: root, cachesDirectory: root)
        do {
            try await backend.load()
            XCTFail("A host stub must never claim that real RE-USE inference is available")
        } catch REUSEError.unavailable { }
    }
    #endif
    func testHostedModelCandidateMetadataCanBeRestoredOffline() throws {
        let candidate = HostedModelCandidate(id: "gemma-4-e2b", repository: "litert-community/gemma-4-E2B-it-litert-lm",
            revision: String(repeating: "a", count: 40), filePath: "gemma-4-E2B-it.litertlm",
            sizeBytes: 2_580_000_000, sha256: String(repeating: "b", count: 64), license: "Apache-2.0")
        let restored = try JSONDecoder().decode(HostedModelCandidate.self, from: JSONEncoder().encode(candidate))
        XCTAssertEqual(restored, candidate)
        XCTAssertEqual(restored.manifest.revision, candidate.revision)
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
    func testLearningProgressAndLegacyWeakPointDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-01-03T12:00:00Z")!
        let itemID = UUID()
        var point = WeakPoint(itemID: itemID, text: "meeting", reason: .speaking, now: now)
        point.reviews = 3; point.successes = 3; point.failures = 0
        let dates = ["2026-01-01T10:00:00Z", "2026-01-03T10:00:00Z"].compactMap(ISO8601DateFormatter().date(from:))
        let events = dates.map { ReviewEvent(weakPointID: point.id, grade: .good, reviewedAt: $0, nextReviewAt: now) }
        let practiceDay = ISO8601DateFormatter().date(from: "2026-01-02T10:00:00Z")!
        let activities = [LearningActivityEvent(itemID: itemID, activity: .speaking, occurredAt: practiceDay)]
        let progress = LearningProgress(events: events, activities: activities, weakPoints: [point], now: now, calendar: calendar)
        XCTAssertEqual(progress.totalReviews, 2)
        XCTAssertEqual(progress.activeDays, 3)
        XCTAssertEqual(progress.currentStreak, 3)
        XCTAssertEqual(progress.masteredCount, 1)
        XCTAssertEqual(point.mastery, 1)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(point)) as? [String: Any])
        legacy.removeValue(forKey: "registeredAt")
        let restored = try JSONDecoder().decode(WeakPoint.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored.registeredAt, restored.updatedAt)
    }
    @MainActor func testSQLiteRoundTripReviewHistoryAndDeletion() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let item = LearningItem(text: "It's a meeting; DROP TABLE learning_items;", translation: "会議")
        let point = WeakPoint(itemID: item.id, text: "meeting", reason: .meaning)
        do {
            let store = try LearningStore(path: url.path)
            try store.save(item); try store.save(point)
            let first = try store.review(point, grade: .easy, now: Date(timeIntervalSince1970: 0))
            _ = try store.review(first, grade: .good, now: Date(timeIntervalSince1970: 86_400))
            try store.recordActivity(.listening, itemID: item.id, at: Date(timeIntervalSince1970: 123))
            try store.recordActivity(.speaking, itemID: nil, at: Date(timeIntervalSince1970: 456))
        }
        let reopened = try LearningStore(path: url.path)
        XCTAssertEqual(try reopened.items(), [item])
        XCTAssertEqual(try reopened.weakPoints().first?.reviews, 2)
        XCTAssertEqual(try reopened.weakPoints().first?.intervalDays, 8)
        XCTAssertEqual(try reopened.reviewHistory().count, 2)
        XCTAssertEqual(try reopened.reviewHistory(weakPointID: point.id).map(\.grade), [.good, .easy])
        XCTAssertEqual(try reopened.activityHistory().map(\.activity), [.speaking, .listening])
        XCTAssertEqual(try reopened.activityHistory().last?.itemID, item.id)
        XCTAssertNil(try reopened.activityHistory().first?.itemID)
        XCTAssertThrowsError(try reopened.save(WeakPoint(itemID: UUID(), text: "orphan", reason: .other)))
        try reopened.deleteAll()
        XCTAssertTrue(try reopened.items().isEmpty)
        XCTAssertTrue(try reopened.weakPoints().isEmpty)
        XCTAssertTrue(try reopened.reviewHistory().isEmpty)
        XCTAssertTrue(try reopened.activityHistory().isEmpty)
    }
    @MainActor func testLearningStoreAcceptsReplacementScheduler() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try LearningStore(path: url.path, scheduler: FixedSevenDayScheduler())
        let item = LearningItem(text: "Please call me back.", translation: "折り返し電話をください")
        let point = WeakPoint(itemID: item.id, text: "call me back", reason: .listening)
        try store.save(item); try store.save(point)
        let now = Date(timeIntervalSince1970: 1_000)
        let scheduled = try store.review(point, grade: .good, now: now)
        XCTAssertEqual(scheduled.intervalDays, 7)
        XCTAssertEqual(scheduled.algorithmVersion, 77)
    }
    func testGeneratedContentRejectsInvalidAnswer() throws {
        let data = Data(#"{"kind":"conversation","difficulty":2,"text":"Hello","translation":"こんにちは","targetPhrases":["hello"],"question":"Which greeting?","choices":["a","b","c","d"],"answerIndex":4,"explanation":"greeting"}"#.utf8)
        let lesson = try JSONDecoder().decode(GeneratedLesson.self, from: data)
        XCTAssertThrowsError(try lesson.validated())
    }
    func testGeneratedLessonValidatesAndRoundTripsWithMetadata() throws {
        let lesson = GeneratedLesson(kind: "conversation", difficulty: 2, text: "Could you confirm the booking?",
            translation: "予約を確認していただけますか？", targetPhrases: ["confirm the booking"],
            question: "What should be confirmed?", choices: ["A booking", "A payment", "A report", "A schedule"],
            answerIndex: 0, explanation: "Confirm the booking means to check the reservation.", modelID: "gemma-test")
        XCTAssertEqual(try lesson.validated().text, lesson.text)
        let restored = try JSONDecoder().decode(GeneratedLesson.self, from: JSONEncoder().encode(lesson))
        XCTAssertEqual(restored.id, lesson.id)
        XCTAssertEqual(restored.kind, lesson.kind)
        XCTAssertEqual(restored.choices, lesson.choices)
        XCTAssertEqual(restored.modelID, lesson.modelID)
        XCTAssertEqual(restored.generatedAt.timeIntervalSince1970, lesson.generatedAt.timeIntervalSince1970, accuracy: 0.001)
    }
    func testLessonGeneratorProducesValidatedMockLesson() async throws {
        let generator = LessonGenerator(service: MockLLM())
        let lesson = try await generator.generate(LessonGenerationRequest(topic: "hotel reservation", difficulty: 2))
        XCTAssertEqual(lesson.choices.count, 4)
        XCTAssertEqual(lesson.targetPhrases, ["confirm your reservation"])
        XCTAssertEqual(try lesson.validated().translation, "金曜日までに予約を確認してください。")
    }
    func testGenerationRequestRejectsOversizedPromptInput() {
        XCTAssertThrowsError(try LessonGenerationRequest(topic: String(repeating: "x", count: 121), difficulty: 2).prompt())
        XCTAssertThrowsError(try LessonGenerationRequest(topic: "meeting", difficulty: 6).prompt())
    }
    @MainActor func testGeneratedLessonStorePersistsLessonAndLearningItemAtomically() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let lesson = GeneratedLesson(kind: "conversation", difficulty: 2, text: "Please confirm the booking.",
            translation: "予約を確認してください。", targetPhrases: ["confirm the booking"],
            question: "What should be confirmed?", choices: ["The booking", "A payment", "A report", "A schedule"],
            answerIndex: 0, explanation: "The reservation should be checked.", modelID: "gemma-test")
        let store = try LearningStore(path: url.path)
        try store.save(lesson)
        let restored = try XCTUnwrap(store.generatedLessons().first)
        XCTAssertEqual(restored.id, lesson.id)
        XCTAssertEqual(restored.text, lesson.text)
        XCTAssertEqual(restored.modelID, lesson.modelID)
        XCTAssertEqual(restored.generatedAt.timeIntervalSince1970, lesson.generatedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(try store.items().map(\.id), [lesson.id])
        try store.deleteAll()
        XCTAssertTrue(try store.generatedLessons().isEmpty)
    }
    func testCoordinatorReleasesAfterFailure() async throws {
        let coordinator = ModelRuntimeCoordinator()
        enum Failure: Error { case expected }
        do { let _: Int = try await coordinator.withExclusiveModel { throw Failure.expected }; XCTFail() } catch {}
        let value = try await coordinator.withExclusiveModel { 42 }
        XCTAssertEqual(value, 42)
    }
}

private struct FixedSevenDayScheduler: ReviewScheduling {
    func schedule(_ point: WeakPoint, grade: ReviewGrade, now: Date) -> WeakPoint {
        var result = point
        result.reviews += 1; result.successes += 1; result.intervalDays = 7
        result.algorithmVersion = 77; result.updatedAt = now
        result.nextReviewAt = now.addingTimeInterval(7 * 86_400)
        return result
    }
}

private actor RuntimeGate {
    private var entered = false
    private var held: CheckedContinuation<Void, Never>?
    private var listeners: [CheckedContinuation<Void, Never>] = []
    func hold() async {
        await withCheckedContinuation { continuation in
            held = continuation; entered = true
            for listener in listeners { listener.resume() }
            listeners.removeAll()
        }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { listeners.append($0) }
    }
    func release() { held?.resume(); held = nil }
}
extension CoreTests {
    func testCoordinatorRejectsConcurrentModel() async throws {
        let coordinator = ModelRuntimeCoordinator()
        let gate = RuntimeGate()
        let first = Task { try await coordinator.withExclusiveModel { await gate.hold(); return 1 } }
        await gate.waitUntilEntered()
        do {
            _ = try await coordinator.withExclusiveModel { 2 }
            XCTFail("Overlapping model operation was admitted")
        } catch RuntimeError.busy { }
        await gate.release()
        let result = try await first.value
        XCTAssertEqual(result, 1)
    }
}
