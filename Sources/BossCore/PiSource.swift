import CryptoKit
import Foundation
import SQLite3

final class PiSource {
    private var states: [String: TranscriptState] = [:]
    let harness: Harness
    let root: URL
    private let recentWindow: TimeInterval
    var keepMessages = true

    init(harness: Harness, root: URL, recentWindow: TimeInterval = 12 * 3600) {
        self.harness = harness
        self.root = root
        self.recentWindow = recentWindow
    }

    var sessionsDir: URL { root.appendingPathComponent("agent/sessions") }

    func files(modifiedWithin window: TimeInterval) -> [URL] {
        let cutoff = Date().addingTimeInterval(-window)
        guard let enumerator = FileManager.default.enumerator(at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if date >= cutoff { result.append(url) }
        }
        return result
    }

    func sessions() -> [AgentSession] {
        files(modifiedWithin: recentWindow).compactMap { url in
            let state = parse(path: url.path)
            guard !state.prompts.isEmpty else { return nil }
            let modified = fileModificationDate(url.path) ?? Date()
            let idle = Date().timeIntervalSince(modified)
            let lastRole = state.messages.last?.role
            let status: AgentStatus
            if idle < 15 || (lastRole != .assistant && idle < 120) {
                status = .working
            } else if !state.pendingTools.isEmpty && idle < 3600 {
                status = .needsApproval
            } else {
                status = .finished
            }
            let id = state.sessionId ?? url.deletingPathExtension().lastPathComponent
            return AgentSession(harness: harness, sessionId: id, title: state.displayTitle, cwd: state.cwd ?? "",
                                status: status, startedAt: state.startedAt, updatedAt: modified,
                                lastPrompt: state.lastPrompt, lastReply: state.lastAssistantText,
                                pendingAction: status == .needsApproval ? state.pendingDescription : nil,
                                model: state.model, tokens: state.tokens, promptCount: state.prompts.count,
                                transcriptPath: url.path, isLive: idle < 600)
        }
    }

    func messages(sessionId: String) -> [TranscriptMessage] {
        states.values.first(where: { $0.sessionId == sessionId })?.messages ?? []
    }

    func allPrompts(within window: TimeInterval) -> [UserPrompt] {
        files(modifiedWithin: window).flatMap { parse(path: $0.path).prompts }
    }

    func tokensByDay(within window: TimeInterval) -> [String: TokenUsage] {
        var result: [String: TokenUsage] = [:]
        for file in files(modifiedWithin: window) {
            for (day, usage) in parse(path: file.path).tokensByDay {
                result[day, default: TokenUsage()] = result[day, default: TokenUsage()] + usage
            }
        }
        return result
    }

    func parse(path: String) -> TranscriptState {
        var state = states[path] ?? TranscriptState(keepMessages: keepMessages)
        let (objects, reset) = state.tail.readNewObjects(path: path)
        if reset { state.reset() }
        for object in objects { consume(object, into: &state) }
        states[path] = state
        return state
    }

    static func tokens(_ usage: [String: Any]) -> TokenUsage {
        TokenUsage(input: usage["input"] as? Int ?? 0, output: usage["output"] as? Int ?? 0,
                   cacheRead: usage["cacheRead"] as? Int ?? 0, cacheWrite: usage["cacheWrite"] as? Int ?? 0)
    }

    private func consume(_ object: [String: Any], into state: inout TranscriptState) {
        let date = ISODate.parse(object["timestamp"])
        state.touch(date)
        switch object["type"] as? String {
        case "session":
            state.sessionId = object["id"] as? String
            state.cwd = object["cwd"] as? String
        case "session_info":
            if let name = object["name"] as? String { state.title = name }
        case "model_change":
            if let model = object["modelId"] as? String { state.model = model }
        case "usage", "compaction", "branch_summary":
            if let usage = object["usage"] as? [String: Any] { state.addUsage(Self.tokens(usage), at: date) }
        case "message":
            guard let message = object["message"] as? [String: Any] else { return }
            let role = message["role"] as? String
            switch role {
            case "user":
                if let text = ContentText.cleanUserText(ContentText.extract(message["content"])) {
                    state.recordPrompt(harness: harness, text: text, at: date)
                }
            case "assistant":
                if let model = message["model"] as? String { state.model = model }
                if let usage = message["usage"] as? [String: Any] { state.addUsage(Self.tokens(usage), at: date) }
                if let blocks = message["content"] as? [[String: Any]] {
                    for block in blocks where block["type"] as? String == "toolCall" {
                        let id = block["id"] as? String ?? UUID().uuidString
                        let name = block["name"] as? String ?? tr("tool")
                        let args = block["arguments"] as? [String: Any] ?? [:]
                        let detail = (args["command"] as? String) ?? (args["path"] as? String) ?? ""
                        state.pendingTools[id] = (name, detail.singleLine.truncated(120), date)
                    }
                }
                state.recordReply(ContentText.extract(message["content"]), at: date)
            case "toolResult":
                if let id = message["toolCallId"] as? String { state.pendingTools.removeValue(forKey: id) }
            default:
                break
            }
        default:
            break
        }
    }
}

final class CursorSource {
    var chatsDir: URL { Paths.cursor.appendingPathComponent("chats") }
    var projectsDir: URL { Paths.cursor.appendingPathComponent("projects") }

    func sessions(recentWindow: TimeInterval = 12 * 3600, knownDirectories: [String] = []) -> [AgentSession] {
        let cutoff = Date().addingTimeInterval(-recentWindow)
        guard let enumerator = FileManager.default.enumerator(at: chatsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var workspaces: [String: String]?
        var result: [AgentSession] = []
        for case let url as URL in enumerator where url.lastPathComponent == "store.db" {
            let folder = url.deletingLastPathComponent()
            let modified = [url, folder.appendingPathComponent("store.db-wal")]
                .compactMap { fileModificationDate($0.path) }.max() ?? .distantPast
            guard modified >= cutoff else { continue }
            if workspaces == nil { workspaces = workspaceIndex(knownDirectories: knownDirectories) }
            let idle = Date().timeIntervalSince(modified)
            let hash = folder.deletingLastPathComponent().lastPathComponent
            let title = Self.chatName(database: url) ?? tr("Cursor chat %@", String(folder.lastPathComponent.prefix(6)))
            result.append(AgentSession(harness: .cursor, sessionId: folder.lastPathComponent,
                                       title: title, cwd: workspaces?[hash] ?? "",
                                       status: idle < 20 ? .working : .finished, updatedAt: modified,
                                       transcriptPath: url.path, isLive: idle < 600))
        }
        return result
    }

    func workspaceIndex(knownDirectories: [String]) -> [String: String] {
        let slugs = (try? FileManager.default.contentsOfDirectory(atPath: projectsDir.path)) ?? []
        let candidates = Set(knownDirectories.filter { !$0.isEmpty } + slugs.compactMap(Self.directory(fromSlug:)))
        var index: [String: String] = [:]
        for path in candidates {
            index[Self.workspaceHash(path)] = path
            let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path + "/"
            index[Self.workspaceHash(trimmed)] = path
        }
        return index
    }

    static func workspaceHash(_ path: String) -> String {
        Insecure.MD5.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func directory(fromSlug slug: String) -> String? {
        let parts = slug.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, !first.isEmpty else { return nil }
        func search(_ index: Int, _ path: String) -> String? {
            if index == parts.count {
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue ? path : nil
            }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
               let found = search(index + 1, path + "/" + parts[index]) {
                return found
            }
            return search(index + 1, path + "-" + parts[index])
        }
        return search(1, "/" + first)
    }

    static func chatName(database: URL) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = '0'", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let raw: Data
        if let bytes = sqlite3_column_blob(statement, 0) {
            raw = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        } else {
            return nil
        }
        return name(fromMeta: raw)
    }

    static func name(fromMeta raw: Data) -> String? {
        let text = String(data: raw, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let json = hexDecoded(text) ?? raw
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        let name = ((object["name"] ?? object["title"]) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, name != "New Agent", name != "New Chat" else { return nil }
        return name
    }

    static func hexDecoded(_ text: String) -> Data? {
        guard text.count >= 2, text.count % 2 == 0, text.allSatisfy(\.isHexDigit) else { return nil }
        var data = Data(capacity: text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
