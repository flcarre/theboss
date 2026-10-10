import Foundation
import SQLite3

enum CursorAuth {
    static var appDatabase: URL {
        Paths.home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    static var agentAuthFiles: [URL] {
        [Paths.home.appendingPathComponent(".config/cursor/auth.json"), Paths.cursor.appendingPathComponent("auth.json")]
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: appDatabase.path) || agentAuthFiles.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func usableToken() -> String? {
        let candidates = [accessToken(database: appDatabase)] + agentAuthFiles.map(agentToken)
        return candidates.compactMap { $0 }.first { isUsable($0) }
    }

    static func accessToken(database: URL) -> String? {
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return decode(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
    }

    static func agentToken(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    static func decode(_ data: Data) -> String? {
        let looksUTF16 = data.count >= 4 && data.count % 2 == 0
            && stride(from: 1, to: data.count, by: 2).allSatisfy { data[data.startIndex + $0] == 0 }
        let text = looksUTF16 ? String(data: data, encoding: .utf16LittleEndian) : String(data: data, encoding: .utf8)
        let token = text?.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\0")) ?? ""
        return token.isEmpty ? nil : token
    }

    static func claims(fromJWT token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func isUsable(_ token: String, now: Date = Date()) -> Bool {
        guard let claims = claims(fromJWT: token), userId(fromJWT: token) != nil else { return false }
        guard let exp = (claims["exp"] as? NSNumber)?.doubleValue else { return true }
        return Date(timeIntervalSince1970: exp) > now.addingTimeInterval(60)
    }

    static func userId(fromJWT token: String) -> String? {
        guard let sub = claims(fromJWT: token)?["sub"] as? String else { return nil }
        return sub.split(separator: "|").last.map(String.init)
    }
}
