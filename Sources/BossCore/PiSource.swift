import Foundation

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
                if let usage = message["usage"] as? [String: Any] {
                    state.addUsage(TokenUsage(input: usage["input"] as? Int ?? 0, output: usage["output"] as? Int ?? 0,
                                              cacheRead: usage["cacheRead"] as? Int ?? 0, cacheWrite: usage["cacheWrite"] as? Int ?? 0), at: date)
                }
                if let blocks = message["content"] as? [[String: Any]] {
                    for block in blocks where block["type"] as? String == "toolCall" {
                        let id = block["id"] as? String ?? UUID().uuidString
                        let name = block["name"] as? String ?? "outil"
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

    func sessions(recentWindow: TimeInterval = 12 * 3600) -> [AgentSession] {
        let cutoff = Date().addingTimeInterval(-recentWindow)
        guard let enumerator = FileManager.default.enumerator(at: chatsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var result: [AgentSession] = []
        for case let url as URL in enumerator where url.lastPathComponent == "store.db" {
            let folder = url.deletingLastPathComponent()
            let modified = [url, folder.appendingPathComponent("store.db-wal")]
                .compactMap { fileModificationDate($0.path) }.max() ?? .distantPast
            guard modified >= cutoff else { continue }
            let idle = Date().timeIntervalSince(modified)
            result.append(AgentSession(harness: .cursor, sessionId: folder.lastPathComponent,
                                       title: "Chat Cursor \(folder.lastPathComponent.prefix(6))", cwd: "",
                                       status: idle < 20 ? .working : .finished, updatedAt: modified,
                                       transcriptPath: url.path, isLive: idle < 600))
        }
        return result
    }
}
