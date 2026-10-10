import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class Store: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()

    public init(url: URL = Paths.appSupport.appendingPathComponent("boss.sqlite")) {
        if sqlite3_open(url.path, &db) != SQLITE_OK { db = nil }
        execute("PRAGMA journal_mode=WAL")
        execute("""
        CREATE TABLE IF NOT EXISTS suggestions (
            id TEXT PRIMARY KEY, status TEXT NOT NULL, updated_at REAL NOT NULL, payload BLOB NOT NULL)
        """)
        execute("""
        CREATE TABLE IF NOT EXISTS prompts (
            harness TEXT NOT NULL, session_id TEXT NOT NULL, cwd TEXT NOT NULL, ts REAL NOT NULL,
            text TEXT NOT NULL, is_correction INTEGER NOT NULL,
            PRIMARY KEY (harness, session_id, ts, text))
        """)
        execute("CREATE TABLE IF NOT EXISTS usage_samples (ts REAL NOT NULL, harness TEXT NOT NULL, label TEXT NOT NULL, used REAL NOT NULL)")
        execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    private func execute(_ sql: String, _ bindings: [Any?] = []) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return run(sql, bindings) { _ in }
    }

    private func query(_ sql: String, _ bindings: [Any?] = [], row: (OpaquePointer) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        _ = run(sql, bindings, row: row)
    }

    private func run(_ sql: String, _ bindings: [Any?], row: (OpaquePointer) -> Void) -> Bool {
        guard let db else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case let string as String: sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
            case let int as Int: sqlite3_bind_int64(statement, index, Int64(int))
            case let double as Double: sqlite3_bind_double(statement, index, double)
            case let data as Data:
                _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
            default: sqlite3_bind_null(statement, index)
            }
        }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW { row(statement); continue }
            return result == SQLITE_DONE
        }
    }

    public func savedSuggestions() -> [Suggestion] {
        var result: [Suggestion] = []
        let decoder = JSONDecoder()
        query("SELECT payload FROM suggestions") { statement in
            guard let bytes = sqlite3_column_blob(statement, 0) else { return }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            if let suggestion = try? decoder.decode(Suggestion.self, from: data) { result.append(suggestion) }
        }
        return result
    }

    public func save(_ suggestion: Suggestion) {
        guard let data = try? JSONEncoder().encode(suggestion) else { return }
        execute("INSERT OR REPLACE INTO suggestions (id, status, updated_at, payload) VALUES (?, ?, ?, ?)",
                [suggestion.id, suggestion.status.rawValue, Date().timeIntervalSince1970, data])
    }

    public func record(prompts: [UserPrompt]) {
        lock.lock()
        defer { lock.unlock() }
        _ = run("BEGIN", []) { _ in }
        for prompt in prompts {
            let isCorrection = CorrectionDetector.detect(prompt) != nil
            _ = run("INSERT OR IGNORE INTO prompts (harness, session_id, cwd, ts, text, is_correction) VALUES (?, ?, ?, ?, ?, ?)",
                    [prompt.harness.rawValue, prompt.sessionId, prompt.cwd, (prompt.timestamp ?? Date()).timeIntervalSince1970,
                     prompt.text, isCorrection ? 1 : 0]) { _ in }
        }
        _ = run("COMMIT", []) { _ in }
    }

    public func dailyPromptStats(since: Date) -> [String: (prompts: Int, corrections: Int)] {
        var result: [String: (Int, Int)] = [:]
        query("SELECT ts, is_correction FROM prompts WHERE ts >= ?", [since.timeIntervalSince1970]) { statement in
            let day = DayKey.of(Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)))
            let correction = sqlite3_column_int(statement, 1) == 1
            let current = result[day] ?? (0, 0)
            result[day] = (current.0 + 1, current.1 + (correction ? 1 : 0))
        }
        return result.mapValues { (prompts: $0.0, corrections: $0.1) }
    }

    public func searchPrompts(_ text: String, limit: Int = 50) -> [UserPrompt] {
        var result: [UserPrompt] = []
        query("SELECT harness, session_id, cwd, ts, text FROM prompts WHERE text LIKE ? ORDER BY ts DESC LIMIT ?", ["%\(text)%", limit]) { statement in
            let harness = Harness(rawValue: String(cString: sqlite3_column_text(statement, 0))) ?? .claude
            result.append(UserPrompt(harness: harness, sessionId: String(cString: sqlite3_column_text(statement, 1)),
                                     cwd: String(cString: sqlite3_column_text(statement, 2)),
                                     text: String(cString: sqlite3_column_text(statement, 4)),
                                     timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)), previousAssistant: nil))
        }
        return result
    }

    public func recordUsage(_ providers: [ProviderUsage]) {
        let now = Date().timeIntervalSince1970
        for provider in providers where provider.state == .ok {
            for window in provider.windows {
                execute("INSERT INTO usage_samples (ts, harness, label, used) VALUES (?, ?, ?, ?)",
                        [now, provider.harness.rawValue, window.label, window.usedPercent])
            }
        }
    }

    public func setting(_ key: String) -> String? {
        var value: String?
        query("SELECT value FROM settings WHERE key = ?", [key]) { value = String(cString: sqlite3_column_text($0, 0)) }
        return value
    }

    public func setSetting(_ key: String, _ value: String) {
        execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", [key, value])
    }
}
