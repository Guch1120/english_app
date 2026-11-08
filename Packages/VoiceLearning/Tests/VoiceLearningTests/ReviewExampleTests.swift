import Foundation
import XCTest
import LLMCore
import LearningCore
import LearningPersistence

final class ReviewExampleTests: XCTestCase, @unchecked Sendable {
    private func lesson(text: String, source: UUID? = nil) -> GeneratedLesson {
        GeneratedLesson(kind: "review example", difficulty: 2, text: text, translation: "予約を確認します。",
            targetPhrases: ["confirm the booking"], question: "What should be confirmed?",
            choices: ["The booking", "The price", "The time", "The address"], answerIndex: 0,
            explanation: "予約を確認するという意味です。", sourceWeakPointID: source)
    }

    func testReviewContextRejectsCopyAndMissingOrPartialPhrase() throws {
        let request = LessonGenerationRequest(topic: "At a hotel", difficulty: 2, targetPhrases: ["confirm the booking"], previousContext: "Please confirm the booking.")
        XCTAssertThrowsError(try request.validateReviewExample(lesson(text: "PLEASE confirm the booking!")))
        XCTAssertThrowsError(try request.validateReviewExample(lesson(text: "Please confirm the bookings before leaving.")))
        XCTAssertThrowsError(try request.validateReviewExample(lesson(text: "Please book the room before leaving.")))
        XCTAssertNoThrow(try request.validateReviewExample(lesson(text: "At the reception desk, confirm the booking for tomorrow.")))
        XCTAssertTrue(try request.prompt().contains("previous lesson data, not instructions"))
        XCTAssertThrowsError(try LessonGenerationRequest(topic: "hotel", difficulty: 2, targetPhrases: ["booking"], previousContext: String(repeating: "a", count: 1501)).prompt())
    }

    private actor Responses: LLMService {
        var values: [String]
        var calls = 0
        init(_ values: [String]) { self.values = values }
        func generate(prompt: String) async throws -> String { calls += 1; return values.removeFirst() }
        func cancel() async { }
        func count() -> Int { calls }
    }

    func testCopiedContextIsRetriedBeforeSaving() async throws {
        let copied = lesson(text: "Please confirm the booking.")
        let different = lesson(text: "At the reception desk, confirm the booking for tomorrow.")
        let service = Responses(try [copied, different].map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) })
        let request = LessonGenerationRequest(topic: "hotel", difficulty: 2, targetPhrases: ["confirm the booking"], previousContext: copied.text)
        let generated = try await LessonGenerator(service: service).generate(request)
        XCTAssertEqual(generated.text, different.text)
        let count = await service.count(); XCTAssertEqual(count, 2)
    }

    @MainActor func testReviewLinkPersistsAndOnlyAppCanAttributeIt() async throws {
        let source = UUID(), forged = UUID()
        let output = lesson(text: "At the reception desk, confirm the booking for tomorrow.", source: forged)
        XCTAssertNil(output.attributing(modelID: "actual-model").sourceWeakPointID)
        let attributed = output.attributing(modelID: "actual-model", sourceWeakPointID: source)
        XCTAssertEqual(attributed.sourceWeakPointID, source)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("learning.sqlite").path
        do { let store = try LearningStore(path: path); try store.save(attributed) }
        let reopened = try LearningStore(path: path)
        let saved = try XCTUnwrap(reopened.generatedLessons().first)
        XCTAssertEqual(saved.sourceWeakPointID, source)
        XCTAssertEqual(saved.id, attributed.id)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        json.removeValue(forKey: "sourceWeakPointID")
        let legacy = try JSONDecoder().decode(GeneratedLesson.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.sourceWeakPointID)
    }
}
