import Foundation

/// Select an inclusive range of whitespace-delimited words without changing the source text.
public enum LessonTextSelection {
    public static func words(in text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
    }
    public static func phrase(in text: String, from first: Int, through last: Int) -> String? {
        let tokens = words(in: text)
        let lower = min(first, last), upper = max(first, last)
        guard lower >= 0, upper < tokens.count else { return nil }
        return String(text[tokens[lower].startIndex..<tokens[upper].endIndex])
    }
}

public enum LearningCategory: String, Codable, CaseIterable, Sendable {
    case word, phrase, sentence, conversation
    public var title: String {
        switch self {
        case .word: "単語"
        case .phrase: "フレーズ"
        case .sentence: "文章"
        case .conversation: "会話"
        }
    }
}

public struct LearningItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var text: String
    public var translation: String
    public var updatedAt: Date
    public var category: LearningCategory
    public var difficulty: Int?
    public var toeicPart: Int?
    public init(id: UUID = UUID(), text: String, translation: String, updatedAt: Date = Date(),
                category: LearningCategory = .sentence, difficulty: Int? = nil, toeicPart: Int? = nil) {
        self.id = id; self.text = text; self.translation = translation; self.updatedAt = updatedAt
        self.category = category; self.difficulty = difficulty; self.toeicPart = toeicPart
    }
    private enum CodingKeys: String, CodingKey { case id, text, translation, updatedAt, category, difficulty, toeicPart }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        translation = try values.decode(String.self, forKey: .translation)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        category = try values.decodeIfPresent(LearningCategory.self, forKey: .category) ?? .sentence
        difficulty = try values.decodeIfPresent(Int.self, forKey: .difficulty)
        toeicPart = try values.decodeIfPresent(Int.self, forKey: .toeicPart)
    }
    public static let samples = [
        LearningItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, text: "Could you reschedule the meeting for Thursday?", translation: "会議を木曜日に変更していただけますか？"),
        LearningItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, text: "Please submit the expense report by Friday.", translation: "金曜日までに経費報告書を提出してください。")
    ]
}

/// Local learner feedback, never uploaded to a reporting service.
public struct LessonPreferences: Codable, Sendable, Equatable {
    public let itemID: UUID
    public var hidden: Bool
    public var issueNote: String
    public var updatedAt: Date
    public init(itemID: UUID, hidden: Bool = false, issueNote: String = "", updatedAt: Date = Date()) {
        self.itemID = itemID; self.hidden = hidden; self.issueNote = issueNote; self.updatedAt = updatedAt
    }
}

public struct QuizAttempt: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let itemID: UUID
    public let itemUpdatedAt: Date
    public let selectedIndex: Int
    public let correctIndex: Int
    public let answeredAt: Date
    public let question: String
    public let choices: [String]
    public var correct: Bool { selectedIndex == correctIndex }
    public init(id: UUID = UUID(), itemID: UUID, itemUpdatedAt: Date,
                selectedIndex: Int, correctIndex: Int, answeredAt: Date = Date(), question: String = "", choices: [String] = []) {
        self.id = id; self.itemID = itemID; self.itemUpdatedAt = itemUpdatedAt
        self.selectedIndex = selectedIndex; self.correctIndex = correctIndex; self.answeredAt = answeredAt
        self.question = question; self.choices = choices
    }
}
public enum WeakReason: String, Codable, CaseIterable, Sendable {
    case listening = "聞き取れなかった", meaning = "意味がわからなかった", speaking = "発音に自信がない", remember = "覚えておきたい", other = "その他"
}
public enum ReviewGrade: String, Codable, CaseIterable, Sendable { case again = "もう一度", hard = "難しい", good = "普通", easy = "簡単" }
public struct WeakPoint: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let itemID: UUID
    public var text: String
    public var reason: WeakReason
    public var registeredAt: Date
    public var nextReviewAt: Date
    public var updatedAt: Date
    public var reviews: Int = 0
    public var successes: Int = 0
    public var failures: Int = 0
    public var intervalDays: Double = 0
    public var algorithmVersion: Int = 1
    public var mastery: Double? { reviews == 0 ? nil : Double(successes) / Double(reviews) }
    public init(id: UUID = UUID(), itemID: UUID, text: String, reason: WeakReason, now: Date = Date()) {
        self.id = id; self.itemID = itemID; self.text = text; self.reason = reason
        self.registeredAt = now; self.nextReviewAt = now; self.updatedAt = now
    }
    private enum CodingKeys: String, CodingKey {
        case id, itemID, text, reason, registeredAt, nextReviewAt, updatedAt, reviews, successes, failures, intervalDays, algorithmVersion
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        itemID = try container.decode(UUID.self, forKey: .itemID)
        text = try container.decode(String.self, forKey: .text)
        reason = try container.decode(WeakReason.self, forKey: .reason)
        nextReviewAt = try container.decode(Date.self, forKey: .nextReviewAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        registeredAt = try container.decodeIfPresent(Date.self, forKey: .registeredAt) ?? updatedAt
        reviews = try container.decodeIfPresent(Int.self, forKey: .reviews) ?? 0
        successes = try container.decodeIfPresent(Int.self, forKey: .successes) ?? 0
        failures = try container.decodeIfPresent(Int.self, forKey: .failures) ?? 0
        intervalDays = try container.decodeIfPresent(Double.self, forKey: .intervalDays) ?? 0
        algorithmVersion = try container.decodeIfPresent(Int.self, forKey: .algorithmVersion) ?? 1
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id); try container.encode(itemID, forKey: .itemID)
        try container.encode(text, forKey: .text); try container.encode(reason, forKey: .reason)
        try container.encode(registeredAt, forKey: .registeredAt); try container.encode(nextReviewAt, forKey: .nextReviewAt)
        try container.encode(updatedAt, forKey: .updatedAt); try container.encode(reviews, forKey: .reviews)
        try container.encode(successes, forKey: .successes); try container.encode(failures, forKey: .failures)
        try container.encode(intervalDays, forKey: .intervalDays); try container.encode(algorithmVersion, forKey: .algorithmVersion)
    }
}
public struct ReviewEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let weakPointID: UUID
    public let grade: ReviewGrade
    public let reviewedAt: Date
    public let nextReviewAt: Date
    public init(id: UUID = UUID(), weakPointID: UUID, grade: ReviewGrade, reviewedAt: Date, nextReviewAt: Date) {
        self.id = id; self.weakPointID = weakPointID; self.grade = grade
        self.reviewedAt = reviewedAt; self.nextReviewAt = nextReviewAt
    }
}
public enum LearningActivity: String, Codable, CaseIterable, Sendable { case listening, speaking, quiz }
public struct LearningActivityEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let itemID: UUID?
    public let activity: LearningActivity
    public let occurredAt: Date
    public init(id: UUID = UUID(), itemID: UUID?, activity: LearningActivity, occurredAt: Date = Date()) {
        self.id = id; self.itemID = itemID; self.activity = activity; self.occurredAt = occurredAt
    }
}
public struct LearningProgress: Sendable, Equatable {
    public let totalReviews: Int
    public let activeDays: Int
    public let currentStreak: Int
    public let masteredCount: Int
    public init(events: [ReviewEvent], activities: [LearningActivityEvent] = [], weakPoints: [WeakPoint], now: Date = Date(), calendar: Calendar = .current) {
        totalReviews = events.count
        let days = Set(events.map { calendar.startOfDay(for: $0.reviewedAt) } + activities.map { calendar.startOfDay(for: $0.occurredAt) })
        activeDays = days.count
        let today = calendar.startOfDay(for: now)
        var streak = 0
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            currentStreak = 0
            masteredCount = weakPoints.filter { ($0.mastery ?? 0) >= 0.8 && $0.reviews >= 3 }.count
            return
        }
        var day = days.contains(today) ? today : yesterday
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        currentStreak = streak
        masteredCount = weakPoints.filter { ($0.mastery ?? 0) >= 0.8 && $0.reviews >= 3 }.count
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

    private static let contractions: [String: String] = [
        "can't": "can not", "cannot": "can not", "won't": "will not", "shan't": "shall not",
        "don't": "do not", "doesn't": "does not", "didn't": "did not",
        "isn't": "is not", "aren't": "are not", "wasn't": "was not", "weren't": "were not",
        "haven't": "have not", "hasn't": "has not", "hadn't": "had not",
        "couldn't": "could not", "wouldn't": "would not", "shouldn't": "should not", "mustn't": "must not",
        "i'm": "i am", "you're": "you are", "he's": "he is", "she's": "she is", "it's": "it is",
        "we're": "we are", "they're": "they are", "that's": "that is", "what's": "what is",
        "there's": "there is", "here's": "here is", "who's": "who is",
        "i've": "i have", "you've": "you have", "we've": "we have", "they've": "they have",
        "i'll": "i will", "you'll": "you will", "he'll": "he will", "she'll": "she will",
        "we'll": "we will", "they'll": "they will", "it'll": "it will",
        "i'd": "i would", "you'd": "you would", "he'd": "he would", "she'd": "she would",
        "we'd": "we would", "they'd": "they would", "let's": "let us"
    ]

    public static func compare(expected: String, recognized: String) -> WordAlignment {
        func words(_ text: String) -> [String] {
            let expandedNumbers = expandNumbers(text.lowercased().replacingOccurrences(of: "’", with: "'"))
            return expandedNumbers
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
                .flatMap { token in
                    let word = String(token)
                    return (contractions[word] ?? word).split(separator: " ").map(String.init)
                }
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

    private static func expandNumbers(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b\d[\d,]*(?:\.\d+)?\b"#) else { return text }
        let mutable = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            let source = mutable.substring(with: match.range)
            let replacement = spokenNumber(source)
            mutable.replaceCharacters(in: match.range, with: " \(replacement) ")
        }
        return mutable as String
    }

    private static func spokenNumber(_ source: String) -> String {
        let parts = source.replacingOccurrences(of: ",", with: "").split(separator: ".", omittingEmptySubsequences: false)
        guard let integer = parts.first.flatMap({ UInt64(String($0)) }) else { return source }
        var result = cardinalWords(integer)
        if parts.count == 2 {
            result.append("point")
            result += parts[1].compactMap { $0.wholeNumberValue }.map { smallNumberWords[$0] }
        }
        return result.joined(separator: " ")
    }

    private static let smallNumberWords = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"
    ]
    private static let tensWords = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    private static func cardinalWords(_ number: UInt64) -> [String] {
        guard number > 0 else { return ["zero"] }
        let scales = ["", "thousand", "million", "billion"]
        var remainder = number
        var groups: [[String]] = []
        while remainder > 0 && groups.count < scales.count {
            let group = Int(remainder % 1_000)
            if group > 0 {
                var words = tripletWords(group)
                let scale = scales[groups.count]
                if !scale.isEmpty { words.append(scale) }
                groups.append(words)
            } else {
                groups.append([])
            }
            remainder /= 1_000
        }
        if remainder > 0 { return String(number).compactMap(\.wholeNumberValue).map { smallNumberWords[$0] } }
        return groups.reversed().flatMap { $0 }
    }

    private static func tripletWords(_ number: Int) -> [String] {
        var remainder = number
        var words: [String] = []
        if remainder >= 100 {
            words.append(smallNumberWords[remainder / 100]); words.append("hundred")
            remainder %= 100
        }
        if remainder >= 20 {
            words.append(tensWords[remainder / 10])
            remainder %= 10
        }
        if remainder > 0 { words.append(smallNumberWords[remainder]) }
        return words
    }
}
