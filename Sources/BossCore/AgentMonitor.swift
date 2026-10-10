import Foundation

public final class AgentMonitor: @unchecked Sendable {
    private let claude = ClaudeSource()
    private let codex = CodexSource()
    private let pi = PiSource(harness: .pi, root: Paths.pi)
    private let omp = PiSource(harness: .omp, root: Paths.omp)
    private let cursor = CursorSource()
    private let gemini = GeminiSource()
    private let copilot = CopilotSource()
    private let lock = NSLock()

    public init(keepMessages: Bool = true) {
        claude.keepMessages = keepMessages
        codex.keepMessages = keepMessages
        pi.keepMessages = keepMessages
        omp.keepMessages = keepMessages
        copilot.keepMessages = keepMessages
    }

    public func sessions() -> [AgentSession] {
        lock.lock()
        defer { lock.unlock() }
        let ownDirectory = RuleWriter.workingDirectory.path
        var all: [AgentSession] = claude.sessions()
        all += codex.sessions()
        all += pi.sessions()
        all += omp.sessions()
        all += gemini.sessions()
        all += copilot.sessions()
        all += cursor.sessions(knownDirectories: all.map(\.cwd))
        all.removeAll { $0.cwd.hasPrefix(ownDirectory) }
        return all.sorted {
            if $0.status.priority != $1.status.priority { return $0.status.priority < $1.status.priority }
            return $0.updatedAt > $1.updatedAt
        }
    }

    public func messages(for session: AgentSession) -> [TranscriptMessage] {
        lock.lock()
        defer { lock.unlock() }
        switch session.harness {
        case .claude: return claude.messages(sessionId: session.sessionId)
        case .codex:
            if let path = session.transcriptPath { return codex.parse(path: path).messages }
            return codex.messages(sessionId: session.sessionId)
        case .pi:
            if let path = session.transcriptPath { return pi.parse(path: path).messages }
            return []
        case .omp:
            if let path = session.transcriptPath { return omp.parse(path: path).messages }
            return []
        case .gemini:
            if let path = session.transcriptPath { return gemini.messages(path: path) }
            return []
        case .copilot:
            if let path = session.transcriptPath { return copilot.messages(path: path) }
            return []
        case .cursor: return []
        }
    }

    public func prompts(within window: TimeInterval) -> [UserPrompt] {
        lock.lock()
        defer { lock.unlock() }
        let ownDirectory = RuleWriter.workingDirectory.path
        var prompts: [UserPrompt] = claude.allPrompts(within: window)
        prompts += codex.allPrompts(within: window)
        prompts += pi.allPrompts(within: window)
        prompts += omp.allPrompts(within: window)
        prompts += gemini.allPrompts(within: window)
        prompts += copilot.allPrompts(within: window)
        prompts.removeAll { $0.cwd.hasPrefix(ownDirectory) }
        return prompts
    }

    public func dailyTokens(within window: TimeInterval) -> [DailyTokens] {
        lock.lock()
        defer { lock.unlock() }
        var result: [DailyTokens] = []
        let sources: [(Harness, [String: TokenUsage])] = [
            (.claude, claude.tokensByDay(within: window)),
            (.codex, codex.tokensByDay(within: window)),
            (.pi, pi.tokensByDay(within: window)),
            (.omp, omp.tokensByDay(within: window)),
            (.gemini, gemini.tokensByDay(within: window)),
            (.copilot, copilot.tokensByDay(within: window)),
        ]
        for (harness, days) in sources {
            for (day, usage) in days where usage.total > 0 {
                result.append(DailyTokens(day: day, harness: harness, tokens: usage))
            }
        }
        return result.sorted { $0.day < $1.day }
    }

    func codexRateLimits() -> CodexRateSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return codex.latestRateLimits()
    }

    public func installedHarnesses() -> [Harness] {
        let fm = FileManager.default
        var result: [Harness] = []
        if fm.fileExists(atPath: Paths.claude.path) { result.append(.claude) }
        if fm.fileExists(atPath: Paths.codex.path) { result.append(.codex) }
        if fm.fileExists(atPath: Paths.cursor.path) { result.append(.cursor) }
        if fm.fileExists(atPath: Paths.pi.path) { result.append(.pi) }
        if fm.fileExists(atPath: Paths.omp.path) { result.append(.omp) }
        if fm.fileExists(atPath: Paths.gemini.path) { result.append(.gemini) }
        if fm.fileExists(atPath: Paths.copilot.path) { result.append(.copilot) }
        return result
    }
}
