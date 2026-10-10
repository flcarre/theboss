import Foundation

struct GeminiMessage {
    var id: String
    var type: String
    var text: String
    var isToolResult: Bool
    var hasToolCalls: Bool
    var timestamp: Date?
    var model: String?
    var tokens: TokenUsage?
}

struct GeminiSession {
    var sessionId: String?
    var summary: String?
    var startTime: Date?
    var lastUpdated: Date?
    var order: [String] = []
    var messages: [String: GeminiMessage] = [:]

    var ordered: [GeminiMessage] { order.compactMap { messages[$0] } }
}

final class GeminiSource {
    private var cache: [String: (size: UInt64, session: GeminiSession)] = [:]
    private let recentWindow: TimeInterval

    init(recentWindow: TimeInterval = 12 * 3600) {
        self.recentWindow = recentWindow
    }

    var root: URL {
        if let custom = ProcessInfo.processInfo.environment["GEMINI_CLI_HOME"], ProcessInfo.processInfo.environment["BOSS_HOME"] == nil {
            return URL(fileURLWithPath: custom).appendingPathComponent(".gemini")
        }
        return Paths.gemini
    }

    func sessionFiles(modifiedWithin window: TimeInterval) -> [(url: URL, cwd: String)] {
        let fm = FileManager.default
        let tmp = root.appendingPathComponent("tmp")
        guard let projects = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return [] }
        let cutoff = Date().addingTimeInterval(-window)
        let registry = projectRegistry()
        var result: [(URL, String)] = []
        for project in projects {
            let chats = project.appendingPathComponent("chats")
            guard let files = try? fm.contentsOfDirectory(at: chats, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            let marker = (try? String(contentsOf: project.appendingPathComponent(".project_root"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cwd = marker ?? registry[project.lastPathComponent] ?? ""
            for file in files where file.pathExtension == "jsonl" && file.lastPathComponent.hasPrefix("session-") {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if date >= cutoff { result.append((file, cwd)) }
            }
        }
        return result
    }

    func projectRegistry() -> [String: String] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("projects.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [String: String] else { return [:] }
        var bySlug: [String: String] = [:]
        for (path, slug) in projects { bySlug[slug] = path }
        return bySlug
    }

    func parse(path: String) -> GeminiSession {
        let size = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.uint64Value ?? 0
        if let cached = cache[path], cached.size == size { return cached.session }
        var session = GeminiSession()
        var tail = JSONLTail()
        for object in tail.readNewObjects(path: path).objects { Self.consume(object, into: &session) }
        cache[path] = (size, session)
        return session
    }

    static func consume(_ object: [String: Any], into session: inout GeminiSession) {
        if let id = object["sessionId"] as? String, object["projectHash"] != nil {
            session.sessionId = id
            session.startTime = ISODate.parse(object["startTime"])
            session.lastUpdated = ISODate.parse(object["lastUpdated"])
            if let summary = object["summary"] as? String { session.summary = summary }
            return
        }
        if let set = object["$set"] as? [String: Any] {
            if let updated = ISODate.parse(set["lastUpdated"]) { session.lastUpdated = updated }
            if let summary = set["summary"] as? String, !summary.isEmpty { session.summary = summary }
            if let id = set["sessionId"] as? String { session.sessionId = id }
            return
        }
        if let rewind = object["$rewindTo"] as? String {
            if let index = session.order.firstIndex(of: rewind) {
                for id in session.order[index...] { session.messages.removeValue(forKey: id) }
                session.order.removeSubrange(index...)
            }
            return
        }
        if let patch = object["$patch"] as? [String: Any] {
            for id in patch["removeIds"] as? [String] ?? [] {
                session.messages.removeValue(forKey: id)
                session.order.removeAll { $0 == id }
            }
            if let id = patch["id"] as? String, var message = session.messages[id], let content = patch["content"] {
                message.text = text(of: content)
                session.messages[id] = message
            }
            if let orderIds = patch["orderIds"] as? [String], Set(orderIds) == Set(session.order) {
                session.order = orderIds
            }
            return
        }
        guard let id = object["id"] as? String, let type = object["type"] as? String else { return }
        let content = object["content"]
        var tokens: TokenUsage?
        if let usage = object["tokens"] as? [String: Any] {
            let cached = usage["cached"] as? Int ?? 0
            tokens = TokenUsage(input: max(0, (usage["input"] as? Int ?? 0) - cached),
                                output: (usage["output"] as? Int ?? 0) + (usage["thoughts"] as? Int ?? 0),
                                cacheRead: cached, cacheWrite: 0)
        }
        let message = GeminiMessage(id: id, type: type, text: text(of: content), isToolResult: isToolResult(content),
                                    hasToolCalls: !((object["toolCalls"] as? [Any])?.isEmpty ?? true),
                                    timestamp: ISODate.parse(object["timestamp"]), model: object["model"] as? String, tokens: tokens)
        if session.messages[id] == nil { session.order.append(id) }
        session.messages[id] = message
    }

    static func text(of content: Any?) -> String {
        if let string = content as? String { return string }
        if let parts = content as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        if let part = content as? [String: Any] { return part["text"] as? String ?? "" }
        return ""
    }

    static func isToolResult(_ content: Any?) -> Bool {
        guard let parts = content as? [[String: Any]] else { return false }
        return parts.contains { $0["functionResponse"] != nil }
    }

    static func status(of session: GeminiSession, modified: Date) -> AgentStatus {
        let idle = Date().timeIntervalSince(modified)
        guard let last = session.ordered.last(where: { $0.type == "user" || $0.type == "gemini" }) else { return .finished }
        if last.type == "user" { return idle < 600 ? .working : .finished }
        if last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !last.hasToolCalls {
            if idle < 20 { return .working }
            return idle < 3600 ? .needsApproval : .finished
        }
        return idle < 10 ? .working : .finished
    }

    func sessions() -> [AgentSession] {
        sessionFiles(modifiedWithin: recentWindow).compactMap { file in
            let session = parse(path: file.url.path)
            let prompts = Self.prompts(session, cwd: file.cwd)
            guard let id = session.sessionId, !prompts.isEmpty else { return nil }
            let modified = fileModificationDate(file.url.path) ?? Date()
            let status = Self.status(of: session, modified: modified)
            let replies = session.ordered.filter { $0.type == "gemini" && !$0.text.isEmpty }
            let tokens = session.ordered.compactMap(\.tokens).reduce(TokenUsage(), +)
            return AgentSession(harness: .gemini, sessionId: id,
                                title: session.summary ?? prompts.first.map { $0.text.singleLine.truncated(60) } ?? tr("Untitled session"),
                                cwd: file.cwd, status: status, startedAt: session.startTime, updatedAt: modified,
                                lastPrompt: prompts.last?.text, lastReply: replies.last?.text,
                                pendingAction: status == .needsApproval ? tr("A tool call is waiting for your confirmation") : nil,
                                model: session.ordered.last(where: { $0.model != nil })?.model, tokens: tokens,
                                promptCount: prompts.count, transcriptPath: file.url.path, isLive: Date().timeIntervalSince(modified) < 600)
        }
    }

    static func prompts(_ session: GeminiSession, cwd: String) -> [UserPrompt] {
        var previous: String?
        var result: [UserPrompt] = []
        for message in session.ordered {
            if message.type == "gemini", !message.text.isEmpty { previous = message.text }
            guard message.type == "user", !message.isToolResult, let text = ContentText.cleanUserText(message.text) else { continue }
            result.append(UserPrompt(harness: .gemini, sessionId: session.sessionId ?? "", cwd: cwd, text: text,
                                     timestamp: message.timestamp, previousAssistant: previous))
        }
        return result
    }

    func messages(path: String) -> [TranscriptMessage] {
        parse(path: path).ordered.compactMap { message in
            switch message.type {
            case "user" where !message.isToolResult && !message.text.isEmpty:
                return TranscriptMessage(role: .user, text: message.text, timestamp: message.timestamp)
            case "gemini" where !message.text.isEmpty:
                return TranscriptMessage(role: .assistant, text: message.text, timestamp: message.timestamp)
            default:
                return nil
            }
        }
    }

    func allPrompts(within window: TimeInterval) -> [UserPrompt] {
        sessionFiles(modifiedWithin: window).flatMap { Self.prompts(parse(path: $0.url.path), cwd: $0.cwd) }
    }

    func tokensByDay(within window: TimeInterval) -> [String: TokenUsage] {
        var result: [String: TokenUsage] = [:]
        for file in sessionFiles(modifiedWithin: window) {
            for message in parse(path: file.url.path).ordered {
                guard let tokens = message.tokens else { continue }
                let day = DayKey.of(message.timestamp ?? Date())
                result[day, default: TokenUsage()] = result[day, default: TokenUsage()] + tokens
            }
        }
        return result
    }
}
