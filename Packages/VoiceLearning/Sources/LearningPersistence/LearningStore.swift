import Foundation
import CSQLite
import LearningCore

public enum StoreError: Error { case sqlite(String), corruptRecord }
/// Confined to the UI actor; statements are always bound, never interpolated.
@MainActor public final class LearningStore {
    private final class Connection: @unchecked Sendable {
        var pointer: OpaquePointer?
        deinit { sqlite3_close(pointer) }
    }
    private let connection = Connection()
    private var db: OpaquePointer? {
        get { connection.pointer }
        set { connection.pointer = newValue }
    }
    public init(path: String) throws {
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
            try execute("INSERT OR IGNORE INTO schema_migrations VALUES(1)")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); sqlite3_close(db); db = nil; throw error }
    }
    private func execute(_ sql: String, values: [String] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (i, value) in values.enumerated() {
            let result = value.withCString { sqlite3_bind_text(statement, Int32(i + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw failure() }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
    private func failure() -> StoreError { .sqlite(String(cString: sqlite3_errmsg(db))) }
    private func payload<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    public func save(_ item: LearningItem) throws {
        try execute("INSERT INTO learning_items VALUES(?, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", values: [item.id.uuidString, try payload(item)])
    }
    public func save(_ point: WeakPoint) throws {
        try execute("INSERT INTO weak_points VALUES(?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", values: [point.id.uuidString, point.itemID.uuidString, try payload(point)])
    }
    public func items() throws -> [LearningItem] { try load("SELECT payload FROM learning_items ORDER BY id") }
    public func weakPoints() throws -> [WeakPoint] { try load("SELECT payload FROM weak_points ORDER BY id") }
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
        let next = SpacedReviewScheduler().schedule(point, grade: grade, now: now)
        try execute("BEGIN IMMEDIATE")
        do {
            try save(next)
            try execute("INSERT INTO review_history VALUES(?, ?, ?, ?, ?)", values: [UUID().uuidString, point.id.uuidString, grade.rawValue, String(now.timeIntervalSince1970), String(next.nextReviewAt.timeIntervalSince1970)])
            try execute("COMMIT"); return next
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func deleteAll() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM review_history"); try execute("DELETE FROM weak_points"); try execute("DELETE FROM learning_items"); try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
}
