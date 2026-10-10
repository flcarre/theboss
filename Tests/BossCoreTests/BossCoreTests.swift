import Foundation
import Testing
@testable import BossCore

func makeHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("boss-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    Paths.home = home
    return home
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func jsonLine(_ object: [String: Any]) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
}

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastAuthorization: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct BossCoreTests {
    @Test func detectsCorrectionsAndExtractsRules() {
        let prompt = UserPrompt(harness: .claude, sessionId: "s", cwd: "/p",
                                text: "Non, n'utilise jamais de force push sur main.", timestamp: nil, previousAssistant: nil)
        let correction = CorrectionDetector.detect(prompt)
        #expect(correction != nil)
        #expect(correction?.rule == "N'utilise jamais de force push sur main.")

        let task = UserPrompt(harness: .claude, sessionId: "s", cwd: "/p",
                              text: "Ajoute un bouton d'export CSV sur la page des flows", timestamp: nil, previousAssistant: nil)
        #expect(CorrectionDetector.detect(task) == nil)
    }

    @Test func ignoresSpecificOneOffInstructions() {
        let prompt = UserPrompt(harness: .claude, sessionId: "s", cwd: "/p",
                                text: "non, toujours relire https://example.com/issues/12 avant", timestamp: nil, previousAssistant: nil)
        #expect(CorrectionDetector.detect(prompt)?.rule == nil)
    }

    @Test func appendsLearnedRulesUnderOneSection() {
        let first = SuggestionEngine.appending(rule: "Toujours lancer les tests.", to: "# Projet\n\nIntro.\n")
        #expect(first == "# Projet\n\nIntro.\n\n## Règles apprises\n\n- Toujours lancer les tests.\n")
        let second = SuggestionEngine.appending(rule: "Jamais de console.log.", to: first)
        #expect(second.components(separatedBy: SuggestionEngine.learnedSection).count == 2)
        #expect(second.hasSuffix("- Toujours lancer les tests.\n- Jamais de console.log.\n"))
    }

    @Test func unifiedDiffShowsAddedAndRemovedLines() {
        let lines = UnifiedDiff.lines(old: "a\nb\nc", new: "a\nB\nc\nd", path: "f.md")
        let added = lines.filter { $0.kind == .added }.map(\.text)
        let removed = lines.filter { $0.kind == .removed }.map(\.text)
        #expect(added == ["+B", "+d"])
        #expect(removed == ["-b"])
        #expect(lines.first?.text == "--- a/f.md")
        #expect(UnifiedDiff.lines(old: "same", new: "same", path: "f").isEmpty)
    }

    @Test func parsesClaudeTranscriptWithUsageDedupeAndPendingTool() throws {
        let home = try makeHome()
        let project = home.appendingPathComponent(".claude/projects/-repo")
        let now = ISO8601DateFormatter().string(from: Date())
        let lines = [
            jsonLine(["type": "custom-title", "customTitle": "Fix login", "sessionId": "abc"]),
            jsonLine(["type": "user", "sessionId": "abc", "cwd": "/repo", "timestamp": now,
                      "message": ["role": "user", "content": "Non, je t'ai dit de toujours écrire les tests d'abord."]]),
            jsonLine(["type": "assistant", "timestamp": now, "message": ["id": "m1", "model": "claude-x",
                      "content": [["type": "text", "text": "D'accord."]], "usage": ["input_tokens": 10, "output_tokens": 5]]]),
            jsonLine(["type": "assistant", "timestamp": now, "message": ["id": "m1", "model": "claude-x",
                      "content": [["type": "tool_use", "id": "t1", "name": "Bash", "input": ["command": "rm -rf build"]]],
                      "usage": ["input_tokens": 10, "output_tokens": 20]]]),
        ]
        try write(lines.joined(separator: "\n") + "\n", to: project.appendingPathComponent("abc.jsonl"))
        let source = ClaudeSource()
        let state = source.parse(path: project.appendingPathComponent("abc.jsonl").path)
        #expect(state.displayTitle == "Fix login")
        #expect(state.tokens.total == 30)
        #expect(state.prompts.count == 1)
        #expect(state.pendingDescription == "Bash · rm -rf build")
        #expect(state.model == "claude-x")

        let more = jsonLine(["type": "user", "timestamp": now, "message": ["role": "user",
                             "content": [["type": "tool_result", "tool_use_id": "t1", "content": "ok"]]]])
        let handle = try FileHandle(forWritingTo: project.appendingPathComponent("abc.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((more + "\n").utf8))
        try handle.close()
        #expect(source.parse(path: project.appendingPathComponent("abc.jsonl").path).pendingTools.isEmpty)

        let sessions = source.sessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.cwd == "/repo")
    }

    @Test func mapsLiveClaudeStatuses() {
        #expect(ClaudeSource.map("busy") == .working)
        #expect(ClaudeSource.map("waiting") == .needsApproval)
        #expect(ClaudeSource.map("idle") == .finished)
        #expect(ClaudeSource.map(nil) == nil)
    }

    @Test func parsesCodexRolloutStatusAndRateLimits() throws {
        let home = try makeHome()
        let file = home.appendingPathComponent(".codex/sessions/2026/10/10/rollout-x.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let reset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let lines = [
            jsonLine(["type": "session_meta", "timestamp": now, "payload": ["id": "cx1", "cwd": "/repo", "timestamp": now]]),
            jsonLine(["type": "event_msg", "timestamp": now, "payload": ["type": "task_started"]]),
            jsonLine(["type": "response_item", "timestamp": now, "payload": ["type": "message", "role": "user",
                      "content": [["type": "input_text", "text": "Refactor the parser"]]]]),
            jsonLine(["type": "event_msg", "timestamp": now, "payload": ["type": "token_count",
                      "info": ["total_token_usage": ["input_tokens": 100, "cached_input_tokens": 40, "output_tokens": 10]],
                      "rate_limits": ["primary": ["used_percent": 42.0, "window_minutes": 300, "resets_at": reset],
                                      "secondary": ["used_percent": 7.0, "window_minutes": 10080, "resets_at": reset],
                                      "plan_type": "plus"]]]),
            jsonLine(["type": "response_item", "timestamp": now, "payload": ["type": "function_call", "call_id": "c1",
                      "name": "request_user_input", "arguments": "{}"]]),
        ]
        try write(lines.joined(separator: "\n") + "\n", to: file)
        let source = CodexSource()
        let sessions = source.sessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.status == .needsApproval)
        #expect(sessions.first?.tokens.total == 110)
        let limits = try #require(source.latestRateLimits())
        #expect(limits.plan == "plus")
        #expect(limits.windows.map(\.label) == ["5 h", "Semaine"])
        #expect(limits.windows.first?.usedPercent == 42)
    }

    @Test func inventoriesHooksSkillsAndRules() throws {
        let home = try makeHome()
        try write("# Global rules\n", to: home.appendingPathComponent(".claude/CLAUDE.md"))
        try write(jsonLine(["hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "lint.sh"]]]]]]),
                  to: home.appendingPathComponent(".claude/settings.json"))
        try write("---\nname: deploy\ndescription: Ship to prod\n---\n# Deploy\n", to: home.appendingPathComponent(".claude/skills/deploy/SKILL.md"))
        let project = home.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try write("Use pnpm.\n", to: project.appendingPathComponent("AGENTS.md"))
        let items = RulesInventory().scan(projects: [project.path])
        #expect(items.contains { $0.kind == .hook && $0.name == "PreToolUse · Bash" && $0.summary == "lint.sh" })
        #expect(items.contains { $0.kind == .skill && $0.name == "deploy" && $0.summary == "Ship to prod" })
        #expect(items.contains { $0.kind == .instructions && $0.scope == "repo" && $0.name == "AGENTS.md" })
    }

    @Test func proposesSetupFixes() throws {
        let home = try makeHome()
        let project = home.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try write("Use pnpm.\n", to: project.appendingPathComponent("AGENTS.md"))
        try write("@docs/missing.md\n# Me\n", to: home.appendingPathComponent(".claude/CLAUDE.md"))
        let session = AgentSession(harness: .claude, sessionId: "s", title: "t", cwd: project.path, status: .finished, updatedAt: Date())
        let fixes = SuggestionEngine().setupFixes(sessions: [session])
        let importFix = try #require(fixes.first { $0.title == "Faire lire AGENTS.md à Claude Code" })
        #expect(importFix.proposedContent == "@AGENTS.md\n")
        let broken = try #require(fixes.first { $0.title.contains("import cassé") })
        #expect(broken.proposedContent == "# Me\n")
        try broken.apply()
        #expect(try String(contentsOf: home.appendingPathComponent(".claude/CLAUDE.md"), encoding: .utf8) == "# Me\n")
    }

    @Test func learnedRuleSuggestionsSkipRulesAlreadyWritten() throws {
        let home = try makeHome()
        let project = home.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let prompts = [
            UserPrompt(harness: .claude, sessionId: "s", cwd: project.path, text: "Non, toujours utiliser pnpm et jamais npm.", timestamp: Date(), previousAssistant: "npm install"),
            UserPrompt(harness: .claude, sessionId: "s", cwd: project.path, text: "je t'ai dit: toujours utiliser pnpm, jamais npm", timestamp: Date(), previousAssistant: nil),
        ]
        let suggestions = SuggestionEngine().learnedRules(from: SuggestionEngine().corrections(from: prompts))
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.evidence.count == 2)
        #expect(suggestions.first?.filePath == project.appendingPathComponent("CLAUDE.md").path)

        try write("- Toujours utiliser pnpm et jamais npm.\n", to: project.appendingPathComponent("CLAUDE.md"))
        #expect(SuggestionEngine().learnedRules(from: SuggestionEngine().corrections(from: prompts)).isEmpty)
    }

    @Test func storeKeepsSuggestionStatusAndPromptStats() throws {
        let home = try makeHome()
        let store = Store(url: home.appendingPathComponent("test.sqlite"))
        let suggestion = Suggestion(id: "x", kind: .learnedRule, title: "Rule", rationale: "Why", project: "p",
                                    filePath: home.appendingPathComponent("CLAUDE.md").path, operation: .appendRule("Rule."),
                                    evidence: [], status: .dismissed, createdAt: Date())
        store.save(suggestion)
        #expect(store.savedSuggestions().first?.status == .dismissed)
        store.record(prompts: [
            UserPrompt(harness: .claude, sessionId: "s", cwd: "/p", text: "Non, jamais ça.", timestamp: Date(), previousAssistant: nil),
            UserPrompt(harness: .claude, sessionId: "s", cwd: "/p", text: "Ajoute une page", timestamp: Date(), previousAssistant: nil),
        ])
        let today = store.dailyPromptStats(since: Date().addingTimeInterval(-3600))
        #expect(today.values.first?.prompts == 2)
        #expect(today.values.first?.corrections == 1)
        store.setSetting("k", "v")
        #expect(store.setting("k") == "v")
    }

    @Test func parsesClaudeUsageWindows() {
        let data = Data(#"{"five_hour":{"utilization":12.5,"resets_at":"2026-10-10T08:00:00Z"},"seven_day":{"utilization":40,"resets_at":null},"extra_usage":{"is_enabled":false}}"#.utf8)
        let windows = UsageService.parseClaudeWindows(data)
        #expect(windows.map(\.label) == ["5 h", "Semaine"])
        #expect(windows.first?.usedPercent == 12.5)
        #expect(windows.first?.resetsAt != nil)
    }

    @Test func ruleWriterRejectsCliErrorsAndCleansRules() {
        #expect(RuleWriter.looksLikeError("Failed to authenticate: OAuth session expired and could not be refreshed."))
        #expect(RuleWriter.clean("- « Toujours lancer les tests avant de pousser »\n") == "Toujours lancer les tests avant de pousser.")
        #expect(RuleWriter.clean("NONE") == nil)
    }

    @Test func parsesCursorTokenAndUsage() {
        let payload = Data(#"{"sub":"auth0|user_42"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        #expect(CursorAuth.userId(fromJWT: "h.\(payload).s") == "user_42")
        let data = Data(#"{"gpt-4":{"numRequests":250,"maxRequestUsage":500},"startOfMonth":"2026-10-01T00:00:00.000Z"}"#.utf8)
        let windows = UsageService.parseCursorWindows(data)
        #expect(windows.count == 1)
        #expect(windows.first?.usedPercent == 50)
        #expect(windows.first?.resetsAt != nil)
    }

    @Test func buildsLocalDomainModel() throws {
        let home = try makeHome()
        let project = home.appendingPathComponent("shop")
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try write("# Shop\n\n- Use pnpm for everything.\n- Prices are stored in cents.\n\n## Règles apprises\n\n- Toujours écrire le test d'abord.\n",
                  to: project.appendingPathComponent("CLAUDE.md"))
        try write("- Use pnpm for everything.\n", to: project.appendingPathComponent("AGENTS.md"))
        let session = AgentSession(harness: .codex, sessionId: "c", title: "Checkout refactor", cwd: project.appendingPathComponent("src").path,
                                   status: .working, updatedAt: Date())
        let model = DomainModelBuilder.build(root: project.path, intent: "Sell socks.", sessions: [session], suggestions: [])
        #expect(model.conventions.map(\.text).contains("Prices are stored in cents."))
        #expect(model.decisions.map(\.text) == ["Toujours écrire le test d'abord."])
        #expect(model.activity.map(\.text) == ["Checkout refactor"])
        #expect(model.agents[.codex] == 1)
        #expect(model.conflicts.count == 1)
        #expect(model.markdown.contains("## Intention\n\nSell socks."))
        #expect(DomainModelBuilder.projects(from: [session]) == [project.path])
    }

    @Test func readsPiOmpAndCursorSessions() throws {
        let home = try makeHome()
        let now = ISO8601DateFormatter().string(from: Date())
        let lines = [
            jsonLine(["type": "session", "id": "pi-1", "timestamp": now, "cwd": "/work/api"]),
            jsonLine(["type": "message", "timestamp": now, "message": ["role": "user", "content": [["type": "text", "text": "Ajoute la pagination"]]]]),
            jsonLine(["type": "message", "timestamp": now, "message": ["role": "assistant", "model": "gpt-x",
                      "content": [["type": "toolCall", "id": "call1", "name": "bash", "arguments": ["command": "npm test"]]],
                      "usage": ["input": 100, "output": 20, "cacheRead": 5, "cacheWrite": 0]]]),
        ]
        try write(lines.joined(separator: "\n") + "\n", to: home.appendingPathComponent(".pi/agent/sessions/--work-api--/s.jsonl"))
        try write(lines.joined(separator: "\n") + "\n", to: home.appendingPathComponent(".omp/agent/sessions/--work-api--/s.jsonl"))
        try write("", to: home.appendingPathComponent(".cursor/chats/abc/chat1/store.db"))
        let sessions = AgentMonitor().sessions()
        let pi = try #require(sessions.first { $0.harness == .pi })
        #expect(pi.cwd == "/work/api")
        #expect(pi.title == "Ajoute la pagination")
        #expect(pi.tokens.total == 125)
        #expect(pi.model == "gpt-x")
        #expect(pi.status == .working)
        #expect(sessions.contains { $0.harness == .omp && $0.sessionId == "pi-1" })
        #expect(sessions.contains { $0.harness == .cursor && $0.status == .working })
    }

    @Test func claudeUsageGaugeEndToEndWithStubbedApi() async throws {
        _ = try makeHome()
        try FileManager.default.createDirectory(at: Paths.claude, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let credentials = Data(#"{"claudeAiOauth":{"accessToken":"tok-123","expiresAt":4102444800000,"subscriptionType":"team"}}"#.utf8)
        StubProtocol.status = 200
        StubProtocol.body = Data(#"{"five_hour":{"utilization":37,"resets_at":"2026-10-10T12:00:00Z"},"seven_day":{"utilization":12,"resets_at":"2026-10-14T00:00:00Z"}}"#.utf8)
        let service = UsageService(monitor: AgentMonitor(), liveMonitor: nil, session: URLSession(configuration: configuration),
                                   readCredentials: { .found(credentials) })
        let report = await service.report(force: true)
        let claude = try #require(report.providers.first { $0.harness == .claude })
        #expect(claude.state == .ok)
        #expect(claude.plan == "team")
        #expect(claude.windows.map(\.usedPercent) == [37, 12])
        #expect(StubProtocol.lastAuthorization == "Bearer tok-123")

        StubProtocol.status = 401
        let expired = await UsageService(monitor: AgentMonitor(), liveMonitor: nil, session: URLSession(configuration: configuration),
                                         readCredentials: { .found(credentials) }).report(force: true)
        #expect(expired.providers.first { $0.harness == .claude }?.state == .tokenExpired)

        let missing = await UsageService(monitor: AgentMonitor(), liveMonitor: nil, session: URLSession(configuration: configuration),
                                         readCredentials: { .missing }).report(force: true)
        #expect(missing.providers.first { $0.harness == .claude }?.state == .signedOut)
    }
}
