import Foundation

struct ClaudeLiveSession {
    var pid: Int32
    var sessionId: String
    var cwd: String
    var name: String?
    var status: String?
    var startedAt: Date?
    var updatedAt: Date?
}

final class ClaudeSource {
    private var states: [String: TranscriptState] = [:]
    private let recentWindow: TimeInterval
    var keepMessages = true

    init(recentWindow: TimeInterval = 12 * 3600) {
        self.recentWindow = recentWindow
    }

    var projectsDir: URL { Paths.claude.appendingPathComponent("projects") }

    func liveSessions() -> [ClaudeLiveSession] {
        let dir = Paths.claude.appendingPathComponent("sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = (json["pid"] as? NSNumber)?.int32Value,
                  let sessionId = json["sessionId"] as? String,
                  isProcessAlive(pid) else { return nil }
            return ClaudeLiveSession(pid: pid, sessionId: sessionId, cwd: json["cwd"] as? String ?? "",
                                     name: json["name"] as? String, status: json["status"] as? String,
                                     startedAt: ISODate.parse(json["startedAt"]), updatedAt: ISODate.parse(json["updatedAt"]))
        }
    }

    func transcriptFiles(modifiedWithin window: TimeInterval?) -> [URL] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else { return [] }
        let cutoff = window.map { Date().addingTimeInterval(-$0) }
        var result: [URL] = []
        for project in projects {
            guard let files = try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                if let cutoff {
                    let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    if date < cutoff { continue }
                }
                result.append(file)
            }
        }
        return result
    }

    func sessions() -> [AgentSession] {
        let live = liveSessions()
        let liveById = Dictionary(live.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
        var pathsById: [String: URL] = [:]
        for file in transcriptFiles(modifiedWithin: recentWindow) {
            pathsById[file.deletingPathExtension().lastPathComponent] = file
        }
        for session in live where pathsById[session.sessionId] == nil {
            if let file = locateTranscript(sessionId: session.sessionId) { pathsById[session.sessionId] = file }
        }

        var result: [AgentSession] = []
        for (sessionId, url) in pathsById {
            let state = parse(path: url.path)
            if state.prompts.isEmpty && liveById[sessionId] == nil { continue }
            let liveInfo = liveById[sessionId]
            let modified = fileModificationDate(url.path) ?? state.lastActivity ?? Date()
            let status = Self.status(live: liveInfo, state: state, modified: modified)
            result.append(AgentSession(
                harness: .claude, sessionId: sessionId,
                title: liveInfo?.name ?? state.displayTitle,
                cwd: liveInfo?.cwd ?? state.cwd ?? "",
                status: status, startedAt: state.startedAt ?? liveInfo?.startedAt,
                updatedAt: max(modified, liveInfo?.updatedAt ?? .distantPast),
                lastPrompt: state.lastPrompt, lastReply: state.lastAssistantText,
                pendingAction: status == .needsApproval ? state.pendingDescription : nil,
                model: state.model, tokens: state.tokens, promptCount: state.prompts.count,
                pid: liveInfo?.pid, transcriptPath: url.path, isLive: liveInfo != nil))
        }
        for session in live where pathsById[session.sessionId] == nil {
            result.append(AgentSession(harness: .claude, sessionId: session.sessionId,
                                       title: session.name ?? "Nouvelle session", cwd: session.cwd,
                                       status: Self.map(session.status) ?? .finished, startedAt: session.startedAt,
                                       updatedAt: session.updatedAt ?? Date(), pid: session.pid, isLive: true))
        }
        return result
    }

    static func map(_ liveStatus: String?) -> AgentStatus? {
        switch liveStatus {
        case "busy", "running", "working": .working
        case "waiting", "needs_input", "awaiting_approval", "waiting_for_permission": .needsApproval
        case "idle": .finished
        default: nil
        }
    }

    static func status(live: ClaudeLiveSession?, state: TranscriptState, modified: Date) -> AgentStatus {
        if let mapped = map(live?.status) { return mapped }
        let idle = Date().timeIntervalSince(modified)
        if !state.pendingTools.isEmpty && idle > 8 && live != nil { return .needsApproval }
        if idle < 15 { return .working }
        return .finished
    }

    func locateTranscript(sessionId: String) -> URL? {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else { return nil }
        for project in projects {
            let candidate = project.appendingPathComponent("\(sessionId).jsonl")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    func messages(sessionId: String) -> [TranscriptMessage] {
        guard let url = locateTranscript(sessionId: sessionId) else { return [] }
        return parse(path: url.path).messages
    }

    func parse(path: String) -> TranscriptState {
        var state = states[path] ?? TranscriptState(keepMessages: keepMessages)
        let (lines, reset) = state.tail.readNewLines(path: path)
        if reset { state.reset() }
        for line in lines { Self.consume(line: line, into: &state) }
        states[path] = state
        return state
    }

    func allPrompts(within window: TimeInterval) -> [UserPrompt] {
        transcriptFiles(modifiedWithin: window).flatMap { parse(path: $0.path).prompts }
    }

    func tokensByDay(within window: TimeInterval) -> [String: TokenUsage] {
        var result: [String: TokenUsage] = [:]
        for file in transcriptFiles(modifiedWithin: window) {
            for (day, usage) in parse(path: file.path).tokensByDay {
                result[day, default: TokenUsage()] = result[day, default: TokenUsage()] + usage
            }
        }
        return result
    }

    static let interestingMarkers = ["\"user\"", "\"assistant\"", "\"custom-title\"", "\"summary\""]

    static func consume(line: Data, into state: inout TranscriptState) {
        guard interestingMarkers.contains(where: { line.containsBytes($0) }) else { return }
        if line.containsBytes("\"tool_result\""), !line.containsBytes("\"assistant\"") {
            let compact = !line.containsBytes("\": \"")
            if compact {
                for id in line.captures(after: "\"tool_use_id\":\"") { state.pendingTools.removeValue(forKey: id) }
                if let stamp = line.captures(after: "\"timestamp\":\"", limit: 1).first { state.touch(ISODate.parse(stamp)) }
                if state.sessionId == nil, let id = line.captures(after: "\"sessionId\":\"", limit: 1).first { state.sessionId = id }
                if state.cwd == nil, let cwd = line.captures(after: "\"cwd\":\"", limit: 1).first { state.cwd = cwd }
                return
            }
        }
        guard let object = JSONLTail.object(line) else { return }
        consume(object, into: &state)
    }

    static func consume(_ object: [String: Any], into state: inout TranscriptState) {
        let type = object["type"] as? String
        let date = ISODate.parse(object["timestamp"])
        if state.sessionId == nil, let id = object["sessionId"] as? String { state.sessionId = id }
        if state.cwd == nil, let cwd = object["cwd"] as? String { state.cwd = cwd }

        switch type {
        case "custom-title":
            if let title = object["customTitle"] as? String { state.title = title }
        case "summary":
            if state.title == nil, let summary = object["summary"] as? String { state.title = summary }
        case "user":
            state.touch(date)
            guard object["isSidechain"] as? Bool != true,
                  let message = object["message"] as? [String: Any] else { return }
            if let blocks = message["content"] as? [[String: Any]] {
                for block in blocks where block["type"] as? String == "tool_result" {
                    if let id = block["tool_use_id"] as? String { state.pendingTools.removeValue(forKey: id) }
                }
            }
            if object["isMeta"] as? Bool == true || object["isCompactSummary"] as? Bool == true { return }
            let raw = ContentText.extract(message["content"], acceptedTypes: ["text"])
            if let text = ContentText.cleanUserText(raw) {
                state.recordPrompt(harness: .claude, text: text, at: date)
            }
        case "assistant":
            state.touch(date)
            guard object["isSidechain"] as? Bool != true,
                  let message = object["message"] as? [String: Any] else { return }
            if let model = message["model"] as? String, !model.hasPrefix("<") { state.model = model }
            if let id = message["id"] as? String, let usage = message["usage"] as? [String: Any] {
                let current = TokenUsage(input: usage["input_tokens"] as? Int ?? 0,
                                         output: usage["output_tokens"] as? Int ?? 0,
                                         cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                                         cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0)
                let previous = state.usageById[id] ?? TokenUsage()
                state.addUsage(current - previous, at: date)
                state.usageById[id] = current
            }
            if let blocks = message["content"] as? [[String: Any]] {
                for block in blocks where block["type"] as? String == "tool_use" {
                    guard let id = block["id"] as? String else { continue }
                    let name = block["name"] as? String ?? "outil"
                    let input = block["input"] as? [String: Any] ?? [:]
                    let detail = (input["command"] as? String) ?? (input["file_path"] as? String) ?? (input["description"] as? String) ?? ""
                    state.pendingTools[id] = (name, detail.singleLine.truncated(120), date)
                }
            }
            let text = ContentText.extract(message["content"], acceptedTypes: ["text"])
            if !text.isEmpty { state.recordReply(text, at: date) }
        default:
            break
        }
    }
}
