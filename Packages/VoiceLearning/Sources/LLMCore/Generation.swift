import Foundation
import LearningCore
public protocol LLMService: Sendable {
    func generate(prompt: String) async throws -> String
    func cancel() async
}
public enum ContentError: Error { case invalidContent }
public struct GeneratedLesson: Codable, Sendable {
    public let text: String
    public let translation: String
    public let choices: [String]
    public let answerIndex: Int
    public func validated() throws -> LearningItem {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              choices.count >= 2, Set(choices).count == choices.count,
              choices.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              choices.indices.contains(answerIndex) else { throw ContentError.invalidContent }
        return LearningItem(text: text, translation: translation)
    }
}
public actor MockLLM: LLMService {
    public init() {}
    public func generate(prompt: String) async throws -> String {
        try Task.checkCancellation()
        return #"{"text":"Please confirm your reservation.","translation":"ご予約をご確認ください。","choices":["Confirm","Cancel"],"answerIndex":0}"#
    }
    public func cancel() async {}
}
