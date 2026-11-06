import Foundation

public struct LearningItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var text: String
    public var translation: String
    public var updatedAt: Date
    public init(id: UUID = UUID(), text: String, translation: String, updatedAt: Date = Date()) {
        self.id = id; self.text = text; self.translation = translation; self.updatedAt = updatedAt
    }
    public static let samples = [
        LearningItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, text: "Could you reschedule the meeting for Thursday?", translation: "会議を木曜日に変更していただけますか？"),
        LearningItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, text: "Please submit the expense report by Friday.", translation: "金曜日までに経費報告書を提出してください。")
    ]
}
public enum WeakReason: String, Codable, CaseIterable, Sendable {
    case listening = "聞き取れなかった", meaning = "意味がわからなかった", speaking = "発音に自信がない", remember = "覚えておきたい", other = "その他"
}
public enum ReviewGrade: String, CaseIterable, Sendable { case again = "もう一度", hard = "難しい", good = "普通", easy = "簡単" }
public struct WeakPoint: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let itemID: UUID
    public var text: String
    public var reason: WeakReason
    public var nextReviewAt: Date
    public var updatedAt: Date
    public var reviews: Int = 0
    public var successes: Int = 0
    public var failures: Int = 0
    public var intervalDays: Double = 0
    public var algorithmVersion: Int = 1
    public init(id: UUID = UUID(), itemID: UUID, text: String, reason: WeakReason, now: Date = Date()) {
        self.id = id; self.itemID = itemID; self.text = text; self.reason = reason
        self.nextReviewAt = now; self.updatedAt = now
    }
}
public protocol ReviewScheduling: Sendable {
    func schedule(_ point: WeakPoint, grade: ReviewGrade, now: Date) -> WeakPoint
}
public struct SpacedReviewScheduler: ReviewScheduling {
    public init() {}
    public func schedule(_ point: WeakPoint, grade: ReviewGrade, now: Date) -> WeakPoint {
        var p = point
        p.reviews += 1; p.updatedAt = now; p.algorithmVersion = 1
        switch grade {
        case .again: p.failures += 1; p.intervalDays = 0; p.nextReviewAt = now.addingTimeInterval(600)
        case .hard: p.successes += 1; p.intervalDays = max(1, p.intervalDays * 1.2)
        case .good: p.successes += 1; p.intervalDays = max(2, p.intervalDays * 2)
        case .easy: p.successes += 1; p.intervalDays = max(4, p.intervalDays * 2.5)
        }
        if grade != .again { p.nextReviewAt = now.addingTimeInterval(p.intervalDays * 86400) }
        return p
    }
}
public struct WordAlignment: Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case match, substitution, deletion, insertion }
    public struct Token: Sendable, Equatable {
        public let expected: String?
        public let recognized: String?
        public let kind: Kind
    }
    public let tokens: [Token]
    public let wordErrorRate: Double
    public static func compare(expected: String, recognized: String) -> WordAlignment {
        func words(_ text: String) -> [String] {
            text.lowercased().replacingOccurrences(of: "’", with: "'")
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        }
        let a = words(expected), b = words(recognized)
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        if !a.isEmpty && !b.isEmpty {
            for i in 1...a.count { for j in 1...b.count {
                d[i][j] = min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + (a[i-1] == b[j-1] ? 0 : 1))
            } }
        }
        var i = a.count, j = b.count, result: [Token] = []
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && d[i][j] == d[i-1][j-1] + (a[i-1] == b[j-1] ? 0 : 1) {
                result.append(Token(expected: a[i-1], recognized: b[j-1], kind: a[i-1] == b[j-1] ? .match : .substitution)); i -= 1; j -= 1
            } else if i > 0 && d[i][j] == d[i-1][j] + 1 {
                result.append(Token(expected: a[i-1], recognized: nil, kind: .deletion)); i -= 1
            } else {
                result.append(Token(expected: nil, recognized: b[j-1], kind: .insertion)); j -= 1
            }
        }
        return WordAlignment(tokens: result.reversed(), wordErrorRate: Double(d[a.count][b.count]) / Double(max(1, a.count)))
    }
}
