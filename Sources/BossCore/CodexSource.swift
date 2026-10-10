import Foundation

public struct RateWindow: Hashable, Sendable, Codable {
    public var label: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var windowMinutes: Int?

    public init(label: String, usedPercent: Double, resetsAt: Date?, windowMinutes: Int?) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
    }
}

struct CodexRateSnapshot {
    var observedAt: Date
    var windows: [RateWindow]
    var plan: String?
}

final class CodexSource {
    private var states: [String: TranscriptState] = [:]
    private var eventPrompts: [String: Bool] = [:]
    private var lastTotals: [String: TokenUsage] = [:]
    private var rateSnapshots: [String: CodexRateSnapshot] = [:]
    private let recentWindow: TimeInterval
    var keepMessages = true

    static let approvalTools: Set<String> = ["request_user_input", "request_user_input_async", "ask_user", "request_permissions"]

    init(recentWindow: TimeInterval = 12 * 3600) {
        self.recentWindow = recentWindow
    }

    var sessionsDir: URL { Paths.codex.appendingPathComponent("sessions") }

    func rolloutFiles(modifiedWithin window: TimeInterval?) -> [URL] {
        let cutoff = window.map { Date().addingTimeInterval(-$0) } ?? .distantPast
        guard let enumerator = FileManager.default.enumerator(at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if date >= cutoff { result.append(url) }
        }
        return result
    }

    func threadNames() -> [String: String] {
        let url = Paths.codex.appendingPathComponent("session_index.jsonl")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var names: [String: String] = [:]
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String, let name = json["thread_name"] as? String else { continue }
            names[id] = name
        }
        return names
    }

    func sessions() -> [AgentSession] {
        let names = threadNames()
        return rolloutFiles(modifiedWithin: recentWindow).compactMap { url in
            let state = parse(path: url.path)
            guard let id = state.sessionId, !state.prompts.isEmpty else { return nil }
            let modified = fileModificationDate(url.path) ?? Date()
            let status = Self.status(state: state, modified: modified)
            return AgentSession(harness: .codex, sessionId: id, title: names[id] ?? state.displayTitle,
                                cwd: state.cwd ?? "", status: status, startedAt: state.startedAt,
                                updatedAt: modified, lastPrompt: state.lastPrompt, lastReply: state.lastAssistantText,
                                pendingAction: status == .needsApproval ? state.pendingDescription : nil,
                                model: state.model, tokens: state.tokens, promptCount: state.prompts.count,
                                transcriptPath: url.path, isLive: Date().timeIntervalSince(modified) < 600)
        }
    }

    static func status(state: TranscriptState, modified: Date) -> AgentStatus {
        let idle = Date().timeIntervalSince(modified)
        let turnOpen = state.turnStartedAt.map { start in state.turnEndedAt.map { $0 < start } ?? true } ?? false
        if turnOpen, let asked = state.approvalRequestedAt, asked >= (state.turnStartedAt ?? .distantPast) {
            return .needsApproval
        }
        if turnOpen && state.pendingTools.values.contains(where: { approvalTools.contains($0.name) }) {
            return .needsApproval
        }
        if turnOpen && idle < 600 { return .working }
        if idle < 10 { return .working }
        return .finished
    }

    func latestRateLimits() -> CodexRateSnapshot? {
        _ = rolloutFiles(modifiedWithin: 3 * 24 * 3600).map { parse(path: $0.path) }
        return rateSnapshots.values.max(by: { $0.observedAt < $1.observedAt })
    }

    func messages(sessionId: String) -> [TranscriptMessage] {
        states.values.first(where: { $0.sessionId == sessionId })?.messages ?? []
    }

    func allPrompts(within window: TimeInterval) -> [UserPrompt] {
        rolloutFiles(modifiedWithin: window).flatMap { parse(path: $0.path).prompts }
    }

    func tokensByDay(within window: TimeInterval) -> [String: TokenUsage] {
        var result: [String: TokenUsage] = [:]
        for file in rolloutFiles(modifiedWithin: window) {
            for (day, usage) in parse(path: file.path).tokensByDay {
                result[day, default: TokenUsage()] = result[day, default: TokenUsage()] + usage
            }
        }
        return result
    }

    func parse(path: String) -> TranscriptState {
        var state = states[path] ?? TranscriptState(keepMessages: keepMessages)
        let (objects, reset) = state.tail.readNewObjects(path: path)
        if reset {
            state.reset()
            eventPrompts[path] = false
            lastTotals[path] = nil
        }
        for object in objects { consume(object, path: path, into: &state) }
        states[path] = state
        return state
    }

    private func consume(_ object: [String: Any], path: String, into state: inout TranscriptState) {
        let date = ISODate.parse(object["timestamp"])
        guard let payload = object["payload"] as? [String: Any] else { return }
        let payloadType = payload["type"] as? String
        switch object["type"] as? String {
        case "session_meta":
            state.sessionId = (payload["id"] as? String) ?? (payload["session_id"] as? String)
            state.cwd = payload["cwd"] as? String
            state.touch(ISODate.parse(payload["timestamp"]) ?? date)
        case "turn_context":
            if let model = payload["model"] as? String { state.model = model }
        case "response_item":
            state.touch(date)
            switch payloadType {
            case "message":
                let role = payload["role"] as? String
                let text = ContentText.extract(payload["content"])
                if role == "user", eventPrompts[path] != true, let clean = ContentText.cleanUserText(text) {
                    state.recordPrompt(harness: .codex, text: clean, at: date)
                } else if role == "assistant" {
                    state.recordReply(text, at: date)
                }
            case "function_call", "custom_tool_call", "local_shell_call":
                let id = (payload["call_id"] as? String) ?? (payload["id"] as? String) ?? UUID().uuidString
                let name = payload["name"] as? String ?? "shell"
                let arguments = (payload["arguments"] as? String) ?? (payload["input"] as? String) ?? ""
                state.pendingTools[id] = (name, arguments.singleLine.truncated(120), date)
            case "function_call_output", "custom_tool_call_output", "local_shell_call_output":
                if let id = payload["call_id"] as? String { state.pendingTools.removeValue(forKey: id) }
                state.approvalRequestedAt = nil
            default:
                break
            }
        case "event_msg":
            state.touch(date)
            switch payloadType {
            case "user_message":
                if eventPrompts[path] != true {
                    eventPrompts[path] = true
                    let replies = state.messages.filter { $0.role != .user }
                    state.prompts.removeAll()
                    state.messages = replies
                }
                if let message = payload["message"] as? String, let clean = ContentText.cleanUserText(message) {
                    state.recordPrompt(harness: .codex, text: clean, at: date)
                }
            case "task_started":
                state.turnStartedAt = date
            case "task_complete", "turn_aborted":
                state.turnEndedAt = date
                state.pendingTools.removeAll()
                state.approvalRequestedAt = nil
            case "exec_approval_request", "apply_patch_approval_request", "request_user_input":
                state.approvalRequestedAt = date
            case "exec_command_end", "patch_apply_end", "exec_command_begin":
                state.approvalRequestedAt = nil
            case "token_count":
                if let info = payload["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any] {
                    let cached = total["cached_input_tokens"] as? Int ?? 0
                    let current = TokenUsage(input: max(0, (total["input_tokens"] as? Int ?? 0) - cached),
                                             output: total["output_tokens"] as? Int ?? 0,
                                             cacheRead: cached,
                                             cacheWrite: total["cache_write_input_tokens"] as? Int ?? 0)
                    let previous = lastTotals[path] ?? TokenUsage()
                    if current.total >= previous.total {
                        state.addUsage(current - previous, at: date)
                        lastTotals[path] = current
                    }
                }
                if let limits = payload["rate_limits"] as? [String: Any], let date {
                    var windows: [RateWindow] = []
                    for (key, label) in [("primary", tr("Short window")), ("secondary", tr("Week"))] {
                        guard let window = limits[key] as? [String: Any],
                              let used = (window["used_percent"] as? NSNumber)?.doubleValue else { continue }
                        let minutes = window["window_minutes"] as? Int
                        windows.append(RateWindow(label: minutes.map(Self.windowLabel) ?? label, usedPercent: used,
                                                  resetsAt: ISODate.parse(window["resets_at"]), windowMinutes: minutes))
                    }
                    if !windows.isEmpty {
                        rateSnapshots[path] = CodexRateSnapshot(observedAt: date, windows: windows, plan: limits["plan_type"] as? String)
                    }
                }
            default:
                break
            }
        default:
            break
        }
    }

    static func windowLabel(_ minutes: Int) -> String {
        if minutes >= 7 * 24 * 60 - 1 { return tr("Week") }
        if minutes >= 24 * 60 { return tr("%d days", minutes / (24 * 60)) }
        return tr("%d h", minutes / 60)
    }
}
