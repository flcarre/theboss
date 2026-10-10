import Foundation

public enum Harness: String, Codable, CaseIterable, Sendable {
    case claude, codex, cursor, pi, omp

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .pi: "Pi"
        case .omp: "omp"
        }
    }
}

public enum AgentStatus: String, Codable, Sendable, CaseIterable {
    case working, needsApproval, finished

    public var label: String {
        switch self {
        case .working: "Au travail"
        case .needsApproval: "Attend ton feu vert"
        case .finished: "Terminé"
        }
    }

    var priority: Int {
        switch self {
        case .needsApproval: 0
        case .working: 1
        case .finished: 2
        }
    }
}

public struct TokenUsage: Codable, Hashable, Sendable {
    public var input: Int = 0
    public var output: Int = 0
    public var cacheRead: Int = 0
    public var cacheWrite: Int = 0

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public var total: Int { input + output + cacheRead + cacheWrite }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(input: lhs.input + rhs.input, output: lhs.output + rhs.output,
                   cacheRead: lhs.cacheRead + rhs.cacheRead, cacheWrite: lhs.cacheWrite + rhs.cacheWrite)
    }

    public static func - (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(input: lhs.input - rhs.input, output: lhs.output - rhs.output,
                   cacheRead: lhs.cacheRead - rhs.cacheRead, cacheWrite: lhs.cacheWrite - rhs.cacheWrite)
    }
}

public enum MessageRole: String, Codable, Sendable {
    case user, assistant, tool
}

public struct TranscriptMessage: Codable, Hashable, Sendable {
    public var role: MessageRole
    public var text: String
    public var timestamp: Date?

    public init(role: MessageRole, text: String, timestamp: Date?) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

public struct AgentSession: Identifiable, Hashable, Sendable {
    public var id: String { "\(harness.rawValue):\(sessionId)" }
    public var harness: Harness
    public var sessionId: String
    public var title: String
    public var cwd: String
    public var status: AgentStatus
    public var startedAt: Date?
    public var updatedAt: Date
    public var lastPrompt: String?
    public var lastReply: String?
    public var pendingAction: String?
    public var model: String?
    public var tokens: TokenUsage
    public var promptCount: Int
    public var pid: Int32?
    public var transcriptPath: String?
    public var isLive: Bool

    public init(harness: Harness, sessionId: String, title: String, cwd: String, status: AgentStatus,
                startedAt: Date? = nil, updatedAt: Date, lastPrompt: String? = nil, lastReply: String? = nil,
                pendingAction: String? = nil, model: String? = nil, tokens: TokenUsage = TokenUsage(),
                promptCount: Int = 0, pid: Int32? = nil, transcriptPath: String? = nil, isLive: Bool = false) {
        self.harness = harness
        self.sessionId = sessionId
        self.title = title
        self.cwd = cwd
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.lastPrompt = lastPrompt
        self.lastReply = lastReply
        self.pendingAction = pendingAction
        self.model = model
        self.tokens = tokens
        self.promptCount = promptCount
        self.pid = pid
        self.transcriptPath = transcriptPath
        self.isLive = isLive
    }

    public var projectName: String { (cwd as NSString).lastPathComponent }
}

public struct UserPrompt: Hashable, Sendable {
    public var harness: Harness
    public var sessionId: String
    public var cwd: String
    public var text: String
    public var timestamp: Date?
    public var previousAssistant: String?

    public init(harness: Harness, sessionId: String, cwd: String, text: String, timestamp: Date?, previousAssistant: String?) {
        self.harness = harness
        self.sessionId = sessionId
        self.cwd = cwd
        self.text = text
        self.timestamp = timestamp
        self.previousAssistant = previousAssistant
    }
}

public struct DailyTokens: Hashable, Sendable {
    public var day: String
    public var harness: Harness
    public var tokens: TokenUsage
}
