import Foundation
import CSQLite
import LearningCore
import LLMCore

public enum StoreError: Error { case sqlite(String), corruptRecord, invalidRecord }
/// Confined to the UI actor; statements are always bound, never interpolated.
@MainActor public final class LearningStore {
    private final class Connection: @unchecked Sendable {
        var pointer: OpaquePointer?
        deinit { sqlite3_close(pointer) }
    }
    private let connection = Connection()
    private let scheduler: any ReviewScheduling
    private var db: OpaquePointer? {
        get { connection.pointer }
        set { connection.pointer = newValue }
    }
    public init(path: String, scheduler: any ReviewScheduling = SpacedReviewScheduler()) throws {
        self.scheduler = scheduler
        var opened: OpaquePointer?
        let openStatus = sqlite3_open(path, &opened)
        db = opened
        guard openStatus == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db); db = nil; throw StoreError.sqlite(message)
        }
        do {
            try execute("PRAGMA foreign_keys = ON")
            try execute("BEGIN IMMEDIATE")
            try execute("CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY)")
            try execute("CREATE TABLE IF NOT EXISTS learning_items(id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS weak_points(id TEXT PRIMARY KEY, item_id TEXT NOT NULL REFERENCES learning_items(id), payload TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS review_history(id TEXT PRIMARY KEY, weak_id TEXT NOT NULL REFERENCES weak_points(id) ON DELETE CASCADE, grade TEXT NOT NULL, reviewed_at REAL NOT NULL, next_at REAL NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS study_history(id TEXT PRIMARY KEY, item_id TEXT REFERENCES learning_items(id) ON DELETE CASCADE, activity TEXT NOT NULL, occurred_at REAL NOT NULL)")
            try execute("CREATE INDEX IF NOT EXISTS study_history_by_date ON study_history(occurred_at DESC)")
            try execute("CREATE TABLE IF NOT EXISTS generated_content(id TEXT PRIMARY KEY, model_id TEXT NOT NULL, prompt_version TEXT NOT NULL, validation_status TEXT NOT NULL, generated_at REAL NOT NULL, payload TEXT NOT NULL)")
            try execute("CREATE INDEX IF NOT EXISTS generated_content_by_date ON generated_content(generated_at DESC)")
            try execute("INSERT OR IGNORE INTO schema_migrations VALUES(1)")
            try execute("INSERT OR IGNORE INTO schema_migrations VALUES(2)")
            try execute("INSERT OR IGNORE INTO schema_migrations VALUES(3)")
            if try !hasMigration(4) {
                try execute("CREATE TABLE lesson_preferences(item_id TEXT PRIMARY KEY REFERENCES learning_items(id) ON DELETE CASCADE, payload TEXT NOT NULL)")
                try execute("CREATE TABLE quiz_attempts(id TEXT PRIMARY KEY, item_id TEXT NOT NULL REFERENCES learning_items(id) ON DELETE CASCADE, answered_at REAL NOT NULL, payload TEXT NOT NULL)")
                try execute("CREATE INDEX quiz_attempts_by_date ON quiz_attempts(answered_at DESC)")
                try execute("INSERT INTO schema_migrations VALUES(4)")
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); sqlite3_close(db); db = nil; throw error }
    }
    private func hasMigration(_ version: Int32) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM schema_migrations WHERE version = ?", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int(statement, 1, version) == SQLITE_OK else { throw failure() }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else { throw failure() }
        return result == SQLITE_ROW
    }
    private func execute(_ sql: String, values: [String] = [], nullableValueIndex: Int? = nil) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (i, value) in values.enumerated() {
            if nullableValueIndex == i + 1 && value.isEmpty {
                guard sqlite3_bind_null(statement, Int32(i + 1)) == SQLITE_OK else { throw failure() }
                continue
            }
            let result = value.withCString { sqlite3_bind_text(statement, Int32(i + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw failure() }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
    private func failure() -> StoreError { .sqlite(String(cString: sqlite3_errmsg(db))) }
    private func payload<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    public func save(_ item: LearningItem) throws {
        guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              item.difficulty.map({ (1...5).contains($0) }) ?? true,
              item.toeicPart.map({ (1...4).contains($0) }) ?? true else { throw StoreError.invalidRecord }
        try execute("INSERT INTO learning_items VALUES(?, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", values: [item.id.uuidString, try payload(item)])
    }
    public func save(_ preferences: LessonPreferences) throws {
        guard preferences.issueNote.count <= 2_000 else { throw StoreError.invalidRecord }
        try execute("INSERT INTO lesson_preferences VALUES(?, ?) ON CONFLICT(item_id) DO UPDATE SET payload=excluded.payload",
                    values: [preferences.itemID.uuidString, try payload(preferences)])
    }
    public func lessonPreferences() throws -> [LessonPreferences] {
        try load("SELECT payload FROM lesson_preferences ORDER BY item_id")
    }
    public func save(_ attempt: QuizAttempt) throws {
        guard (0..<4).contains(attempt.selectedIndex), (0..<4).contains(attempt.correctIndex),
              attempt.question.count <= 400,
              attempt.choices.isEmpty || (attempt.choices.count == 4 && attempt.choices.allSatisfy({ $0.count <= 240 })) else { throw StoreError.invalidRecord }
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("INSERT INTO quiz_attempts VALUES(?, ?, ?, ?)", values: [attempt.id.uuidString,
                attempt.itemID.uuidString, String(attempt.answeredAt.timeIntervalSince1970), try payload(attempt)])
            try recordActivity(.quiz, itemID: attempt.itemID, at: attempt.answeredAt)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func quizAttempts() throws -> [QuizAttempt] {
        try load("SELECT payload FROM quiz_attempts ORDER BY answered_at DESC")
    }
    public func save(_ point: WeakPoint) throws {
        try execute("INSERT INTO weak_points VALUES(?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", values: [point.id.uuidString, point.itemID.uuidString, try payload(point)])
    }
    public func items() throws -> [LearningItem] { try load("SELECT payload FROM learning_items ORDER BY id") }
    public func weakPoints() throws -> [WeakPoint] { try load("SELECT payload FROM weak_points ORDER BY id") }
    public func reviewHistory(weakPointID: UUID? = nil) throws -> [ReviewEvent] {
        let sql = weakPointID == nil
            ? "SELECT id, weak_id, grade, reviewed_at, next_at FROM review_history ORDER BY reviewed_at DESC"
            : "SELECT id, weak_id, grade, reviewed_at, next_at FROM review_history WHERE weak_id = ? ORDER BY reviewed_at DESC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        if let weakPointID {
            let result = weakPointID.uuidString.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw failure() }
        }
        var events: [ReviewEvent] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return events }
            guard status == SQLITE_ROW,
                  let idText = sqlite3_column_text(statement, 0),
                  let weakIDText = sqlite3_column_text(statement, 1),
                  let gradeText = sqlite3_column_text(statement, 2),
                  let id = UUID(uuidString: String(cString: idText)),
                  let weakID = UUID(uuidString: String(cString: weakIDText)),
                  let grade = ReviewGrade(rawValue: String(cString: gradeText)) else { throw StoreError.corruptRecord }
            events.append(ReviewEvent(
                id: id,
                weakPointID: weakID,
                grade: grade,
                reviewedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                nextReviewAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            ))
        }
    }
    public func recordActivity(_ activity: LearningActivity, itemID: UUID?, at date: Date = Date()) throws {
        try execute("INSERT INTO study_history VALUES(?, ?, ?, ?)", values: [
            UUID().uuidString,
            itemID?.uuidString ?? "",
            activity.rawValue,
            String(date.timeIntervalSince1970)
        ], nullableValueIndex: 2)
    }
    public func activityHistory() throws -> [LearningActivityEvent] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, item_id, activity, occurred_at FROM study_history ORDER BY occurred_at DESC", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        var events: [LearningActivityEvent] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return events }
            guard status == SQLITE_ROW,
                  let idText = sqlite3_column_text(statement, 0),
                  let activityText = sqlite3_column_text(statement, 2),
                  let id = UUID(uuidString: String(cString: idText)),
                  let activity = LearningActivity(rawValue: String(cString: activityText)) else { throw StoreError.corruptRecord }
            let itemID = sqlite3_column_type(statement, 1) == SQLITE_NULL
                ? nil
                : sqlite3_column_text(statement, 1).flatMap { UUID(uuidString: String(cString: $0)) }
            events.append(LearningActivityEvent(
                id: id,
                itemID: itemID,
                activity: activity,
                occurredAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            ))
        }
    }
    public func save(_ lesson: GeneratedLesson) throws {
        let item = try lesson.validated()
        try execute("BEGIN IMMEDIATE")
        do {
            try save(item)
            try execute("INSERT INTO generated_content VALUES(?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", values: [
                lesson.id.uuidString, lesson.modelID, lesson.promptVersion, "valid",
                String(lesson.generatedAt.timeIntervalSince1970), try payload(lesson)
            ])
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func generatedLessons() throws -> [GeneratedLesson] {
        try load("SELECT payload FROM generated_content ORDER BY generated_at DESC")
    }
    private func load<T: Decodable>(_ sql: String) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        var values: [T] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return values }
            guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw failure() }
            values.append(try JSONDecoder().decode(T.self, from: Data(String(cString: text).utf8)))
        }
    }
    public func review(_ point: WeakPoint, grade: ReviewGrade, now: Date) throws -> WeakPoint {
        let next = scheduler.schedule(point, grade: grade, now: now)
        try execute("BEGIN IMMEDIATE")
        do {
            try save(next)
            try execute("INSERT INTO review_history VALUES(?, ?, ?, ?, ?)", values: [UUID().uuidString, point.id.uuidString, grade.rawValue, String(now.timeIntervalSince1970), String(next.nextReviewAt.timeIntervalSince1970)])
            try execute("COMMIT"); return next
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func delete(_ point: WeakPoint) throws {
        try execute("DELETE FROM weak_points WHERE id = ?", values: [point.id.uuidString])
    }
    public func deleteAll() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM quiz_attempts"); try execute("DELETE FROM lesson_preferences")
            try execute("DELETE FROM review_history"); try execute("DELETE FROM study_history"); try execute("DELETE FROM generated_content"); try execute("DELETE FROM weak_points"); try execute("DELETE FROM learning_items"); try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
}
