import Foundation

final class CopilotSource {
    private var states: [String: TranscriptState] = [:]
    private var permissions: [String: [String: String]] = [:]
    private var finishedTurn: [String: Bool] = [:]
    private let recentWindow: TimeInterval
    var keepMessages = true

    init(recentWindow: TimeInterval = 12 * 3600) {
        self.recentWindow = recentWindow
    }

    var root: URL {
        if let custom = ProcessInfo.processInfo.environment["COPILOT_HOME"], ProcessInfo.processInfo.environment["BOSS_HOME"] == nil {
            return URL(fileURLWithPath: custom)
        }
        return Paths.copilot
    }

    func sessionDirectories(modifiedWithin window: TimeInterval) -> [URL] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root.appendingPathComponent("session-state"), includingPropertiesForKeys: nil) else { return [] }
        let cutoff = Date().addingTimeInterval(-window)
        return dirs.filter { dir in
            let events = dir.appendingPathComponent("events.jsonl")
            guard let date = fileModificationDate(events.path) else { return false }
            return date >= cutoff
        }
    }

    static func workspace(_ dir: URL) -> [String: String] {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("workspace.yaml"), encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix(" ") && !line.hasPrefix("-") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 { value = String(value.dropFirst().dropLast()) }
            if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 { value = String(value.dropFirst().dropLast()) }
            result[key] = value
        }
        return result
    }

    static func livePid(_ dir: URL) -> Int32? {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        for file in files where file.hasPrefix("inuse.") && file.hasSuffix(".lock") {
            let middle = file.dropFirst("inuse.".count).dropLast(".lock".count)
            if let pid = Int32(middle), isProcessAlive(pid) { return pid }
        }
        return nil
    }

    func sessions() -> [AgentSession] {
        sessionDirectories(modifiedWithin: recentWindow).compactMap { dir in
            let path = dir.appendingPathComponent("events.jsonl").path
            let state = parse(path: path)
            guard !state.prompts.isEmpty else { return nil }
            let workspace = Self.workspace(dir)
            let modified = fileModificationDate(path) ?? Date()
            let pid = Self.livePid(dir)
            let pending = permissions[path] ?? [:]
            let status: AgentStatus
            if pid != nil && !pending.isEmpty {
                status = .needsApproval
            } else if pid != nil && finishedTurn[path] != true {
                status = .working
            } else if Date().timeIntervalSince(modified) < 10 && finishedTurn[path] != true {
                status = .working
            } else {
                status = .finished
            }
            let id = state.sessionId ?? workspace["id"] ?? dir.lastPathComponent
            let title = workspace["summary"].flatMap { $0.isEmpty ? nil : $0 } ?? state.displayTitle
            return AgentSession(harness: .copilot, sessionId: id, title: title,
                                cwd: state.cwd ?? workspace["cwd"] ?? "", status: status,
                                startedAt: state.startedAt, updatedAt: modified,
                                lastPrompt: state.lastPrompt, lastReply: state.lastAssistantText,
                                pendingAction: status == .needsApproval ? pending.values.sorted().first : nil,
                                model: state.model, tokens: state.tokens, promptCount: state.prompts.count,
                                pid: pid, transcriptPath: path, isLive: pid != nil)
        }
    }

    func parse(path: String) -> TranscriptState {
        var state = states[path] ?? TranscriptState(keepMessages: keepMessages)
        let (objects, reset) = state.tail.readNewObjects(path: path)
        if reset {
            state.reset()
            permissions[path] = [:]
            finishedTurn[path] = nil
        }
        for object in objects { consume(object, path: path, into: &state) }
        states[path] = state
        return state
    }

    private func consume(_ object: [String: Any], path: String, into state: inout TranscriptState) {
        let date = ISODate.parse(object["timestamp"])
        let data = object["data"] as? [String: Any] ?? [:]
        state.touch(date)
        switch object["type"] as? String {
        case "session.start", "session.resume":
            if let id = data["sessionId"] as? String { state.sessionId = id }
            if let context = data["context"] as? [String: Any], let cwd = context["cwd"] as? String { state.cwd = cwd }
            if let model = data["selectedModel"] as? String { state.model = model }
        case "session.context_changed":
            if let cwd = (data["context"] as? [String: Any])?["cwd"] as? String ?? data["cwd"] as? String { state.cwd = cwd }
        case "session.model_change":
            if let model = data["newModel"] as? String { state.model = model }
        case "user.message":
            guard object["agentId"] == nil, let content = data["content"] as? String,
                  let clean = ContentText.cleanUserText(content) else { return }
            state.recordPrompt(harness: .copilot, text: clean, at: date)
            finishedTurn[path] = false
        case "assistant.turn_start":
            finishedTurn[path] = false
        case "assistant.message":
            guard object["agentId"] == nil, data["parentToolCallId"] == nil else { return }
            if let model = data["model"] as? String { state.model = model }
            let requests = data["toolRequests"] as? [[String: Any]] ?? []
            if let content = data["content"] as? String, !content.isEmpty { state.recordReply(content, at: date) }
            finishedTurn[path] = requests.isEmpty
        case "tool.execution_start":
            if let id = data["toolCallId"] as? String {
                state.pendingTools[id] = (data["toolName"] as? String ?? "tool", (data["toolTitle"] as? String ?? "").singleLine.truncated(120), date)
            }
            finishedTurn[path] = false
        case "tool.execution_complete":
            if let id = data["toolCallId"] as? String { state.pendingTools.removeValue(forKey: id) }
        case "permission.requested":
            guard let id = data["requestId"] as? String else { return }
            let request = data["permissionRequest"] as? [String: Any] ?? [:]
            let detail = (request["fullCommandText"] as? String) ?? (request["fileName"] as? String) ?? (request["url"] as? String)
                ?? (request["toolName"] as? String) ?? (request["path"] as? String) ?? (request["kind"] as? String) ?? "permission"
            permissions[path, default: [:]][id] = "\(request["kind"] as? String ?? "permission") · \(detail.singleLine.truncated(120))"
        case "permission.completed":
            if let id = data["requestId"] as? String { permissions[path]?.removeValue(forKey: id) }
        case "abort", "session.task_complete", "session.shutdown":
            finishedTurn[path] = true
            permissions[path] = [:]
            state.pendingTools.removeAll()
            if let metrics = data["modelMetrics"] as? [String: Any] {
                for case let model as [String: Any] in metrics.values {
                    guard let usage = model["usage"] as? [String: Any] else { continue }
                    let cacheRead = usage["cacheReadTokens"] as? Int ?? 0
                    state.addUsage(TokenUsage(input: max(0, (usage["inputTokens"] as? Int ?? 0) - cacheRead),
                                              output: (usage["outputTokens"] as? Int ?? 0) + (usage["reasoningTokens"] as? Int ?? 0),
                                              cacheRead: cacheRead, cacheWrite: usage["cacheWriteTokens"] as? Int ?? 0), at: date)
                }
            }
        default:
            break
        }
    }

    func messages(path: String) -> [TranscriptMessage] {
        parse(path: path).messages
    }

    func allPrompts(within window: TimeInterval) -> [UserPrompt] {
        sessionDirectories(modifiedWithin: window).flatMap { parse(path: $0.appendingPathComponent("events.jsonl").path).prompts }
    }

    func tokensByDay(within window: TimeInterval) -> [String: TokenUsage] {
        var result: [String: TokenUsage] = [:]
        for dir in sessionDirectories(modifiedWithin: window) {
            for (day, usage) in parse(path: dir.appendingPathComponent("events.jsonl").path).tokensByDay {
                result[day, default: TokenUsage()] = result[day, default: TokenUsage()] + usage
            }
        }
        return result
    }
}
