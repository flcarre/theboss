import Foundation

struct TranscriptState {
    var keepMessages = true
    var tail = JSONLTail()
    var sessionId: String?
    var cwd: String?
    var title: String?
    var firstPrompt: String?
    var model: String?
    var startedAt: Date?
    var lastActivity: Date?
    var tokens = TokenUsage()
    var tokensByDay: [String: TokenUsage] = [:]
    var usageById: [String: TokenUsage] = [:]
    var prompts: [UserPrompt] = []
    var messages: [TranscriptMessage] = []
    var lastAssistantText: String?
    var pendingTools: [String: (name: String, detail: String, since: Date?)] = [:]
    var turnStartedAt: Date?
    var turnEndedAt: Date?
    var approvalRequestedAt: Date?

    static let messageLimit = 400

    mutating func reset() {
        let keepTail = tail
        let keep = keepMessages
        self = TranscriptState()
        tail = keepTail
        keepMessages = keep
    }

    mutating func touch(_ date: Date?) {
        guard let date else { return }
        if startedAt == nil || date < startedAt! { startedAt = date }
        if lastActivity == nil || date > lastActivity! { lastActivity = date }
    }

    mutating func addUsage(_ usage: TokenUsage, at date: Date?) {
        tokens = tokens + usage
        let key = DayKey.of(date ?? Date())
        tokensByDay[key, default: TokenUsage()] = tokensByDay[key, default: TokenUsage()] + usage
    }

    mutating func appendMessage(_ message: TranscriptMessage) {
        guard keepMessages else { return }
        messages.append(message)
        if messages.count > Self.messageLimit {
            messages.removeFirst(messages.count - Self.messageLimit)
        }
    }

    mutating func recordPrompt(harness: Harness, text: String, at date: Date?) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if firstPrompt == nil { firstPrompt = clean }
        prompts.append(UserPrompt(harness: harness, sessionId: sessionId ?? "", cwd: cwd ?? "", text: clean,
                                  timestamp: date, previousAssistant: lastAssistantText))
        appendMessage(TranscriptMessage(role: .user, text: clean, timestamp: date))
    }

    mutating func recordReply(_ text: String, at date: Date?) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lastAssistantText = clean
        appendMessage(TranscriptMessage(role: .assistant, text: clean, timestamp: date))
    }

    var lastPrompt: String? { prompts.last?.text }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let firstPrompt { return firstPrompt.singleLine.truncated(60) }
        return "Session sans titre"
    }

    var pendingDescription: String? {
        guard let pending = pendingTools.values.sorted(by: { ($0.since ?? .distantPast) < ($1.since ?? .distantPast) }).last else {
            return nil
        }
        return pending.detail.isEmpty ? pending.name : "\(pending.name) · \(pending.detail)"
    }
}

enum ContentText {
    static func extract(_ content: Any?, acceptedTypes: Set<String> = ["text", "input_text", "output_text"]) -> String {
        if let string = content as? String { return string }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { block -> String? in
            guard let type = block["type"] as? String, acceptedTypes.contains(type) else { return nil }
            return block["text"] as? String
        }.joined(separator: "\n")
    }

    static func cleanUserText(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text.contains("<command-name>") {
            let name = between(text, "<command-name>", "</command-name>") ?? ""
            let args = between(text, "<command-args>", "</command-args>") ?? ""
            let command = (name.hasPrefix("/") ? name : "/" + name)
            return (command + " " + args).trimmingCharacters(in: .whitespaces)
        }
        let noisePrefixes = ["<local-command", "<system-reminder>", "Caveat:", "<environment_context>",
                             "<user_instructions>", "# AGENTS.md", "<permissions", "<turn_aborted>",
                             "<task-notification>", "<bash-", "[Request interrupted", "<user-prompt-submit-hook>",
                             "<ci-monitor-event>", "<subagent_notification>"]
        if noisePrefixes.contains(where: { text.hasPrefix($0) }) { return nil }
        while let start = text.range(of: "<system-reminder>"), let end = text.range(of: "</system-reminder>", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func between(_ text: String, _ open: String, _ close: String) -> String? {
        guard let start = text.range(of: open), let end = text.range(of: close, range: start.upperBound..<text.endIndex) else { return nil }
        return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
