import Foundation

public enum RuleKind: String, CaseIterable, Sendable, Codable {
    case instructions, skill, hook, agent, command, settings

    public var label: String {
        switch self {
        case .instructions: tr("Rules")
        case .skill: tr("Skills")
        case .hook: tr("Hooks")
        case .agent: tr("Subagents")
        case .command: tr("Commands")
        case .settings: tr("Settings")
        }
    }
}

public struct RuleItem: Identifiable, Hashable, Sendable {
    public var id: String { path + "#" + name }
    public var kind: RuleKind
    public var harness: Harness
    public var scope: String
    public var name: String
    public var path: String
    public var summary: String
    public var size: Int
    public var modifiedAt: Date?

    public init(kind: RuleKind, harness: Harness, scope: String, name: String, path: String, summary: String, size: Int, modifiedAt: Date?) {
        self.kind = kind
        self.harness = harness
        self.scope = scope
        self.name = name
        self.path = path
        self.summary = summary
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public struct RulesInventory: Sendable {
    public static let globalScope = "Global"

    public init() {}

    public func scan(projects: [String]) -> [RuleItem] {
        var items: [RuleItem] = []
        items += globalItems()
        for project in Set(projects.map(Self.projectRoot)).sorted() where !project.isEmpty {
            items += projectItems(root: project)
        }
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    public static func projectRoot(_ cwd: String) -> String {
        guard !cwd.isEmpty else { return "" }
        if let range = cwd.range(of: "/.claude/worktrees/") {
            return String(cwd[..<range.lowerBound])
        }
        var url = URL(fileURLWithPath: cwd)
        let fm = FileManager.default
        while url.path != "/" {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) { return url.path }
            url.deleteLastPathComponent()
        }
        return cwd
    }

    func globalItems() -> [RuleItem] {
        let scope = Self.globalScope
        var items: [RuleItem] = []
        items += file(Paths.claude.appendingPathComponent("CLAUDE.md"), kind: .instructions, harness: .claude, scope: scope)
        items += file(Paths.claude.appendingPathComponent("settings.json"), kind: .settings, harness: .claude, scope: scope)
        items += hooks(in: Paths.claude.appendingPathComponent("settings.json"), harness: .claude, scope: scope)
        items += skills(in: Paths.claude.appendingPathComponent("skills"), harness: .claude, scope: scope)
        items += markdownFiles(in: Paths.claude.appendingPathComponent("agents"), kind: .agent, harness: .claude, scope: scope)
        items += markdownFiles(in: Paths.claude.appendingPathComponent("commands"), kind: .command, harness: .claude, scope: scope)
        items += markdownFiles(in: Paths.claude.appendingPathComponent("rules"), kind: .instructions, harness: .claude, scope: scope)
        items += file(Paths.codex.appendingPathComponent("AGENTS.md"), kind: .instructions, harness: .codex, scope: scope)
        items += file(Paths.codex.appendingPathComponent("config.toml"), kind: .settings, harness: .codex, scope: scope)
        items += codexHooks(Paths.codex.appendingPathComponent("hooks.json"), scope: scope)
        items += skills(in: Paths.codex.appendingPathComponent("skills"), harness: .codex, scope: scope)
        items += markdownFiles(in: Paths.cursor.appendingPathComponent("rules"), kind: .instructions, harness: .cursor, scope: scope)
        items += file(Paths.pi.appendingPathComponent("agent/AGENTS.md"), kind: .instructions, harness: .pi, scope: scope)
        items += file(Paths.omp.appendingPathComponent("agent/AGENTS.md"), kind: .instructions, harness: .omp, scope: scope)
        let gemini = Paths.gemini
        items += file(gemini.appendingPathComponent("GEMINI.md"), kind: .instructions, harness: .gemini, scope: scope)
        items += file(gemini.appendingPathComponent("settings.json"), kind: .settings, harness: .gemini, scope: scope)
        items += hooks(in: gemini.appendingPathComponent("settings.json"), harness: .gemini, scope: scope)
        items += markdownFiles(in: gemini.appendingPathComponent("commands"), kind: .command, harness: .gemini, scope: scope, extensions: ["toml"])
        items += markdownFiles(in: gemini.appendingPathComponent("agents"), kind: .agent, harness: .gemini, scope: scope)
        items += skills(in: gemini.appendingPathComponent("skills"), harness: .gemini, scope: scope)
        let copilot = Paths.copilot
        items += file(copilot.appendingPathComponent("copilot-instructions.md"), kind: .instructions, harness: .copilot, scope: scope)
        items += markdownFiles(in: copilot.appendingPathComponent("instructions"), kind: .instructions, harness: .copilot, scope: scope)
        items += file(copilot.appendingPathComponent("settings.json"), kind: .settings, harness: .copilot, scope: scope)
        items += hooks(in: copilot.appendingPathComponent("settings.json"), harness: .copilot, scope: scope)
        items += file(copilot.appendingPathComponent("mcp-config.json"), kind: .settings, harness: .copilot, scope: scope)
        items += markdownFiles(in: copilot.appendingPathComponent("agents"), kind: .agent, harness: .copilot, scope: scope)
        items += markdownFiles(in: copilot.appendingPathComponent("hooks"), kind: .hook, harness: .copilot, scope: scope, extensions: ["json"])
        items += skills(in: copilot.appendingPathComponent("skills"), harness: .copilot, scope: scope)
        return items
    }

    func projectItems(root: String) -> [RuleItem] {
        let base = URL(fileURLWithPath: root)
        let scope = (root as NSString).lastPathComponent
        var items: [RuleItem] = []
        items += file(base.appendingPathComponent("CLAUDE.md"), kind: .instructions, harness: .claude, scope: scope)
        items += file(base.appendingPathComponent("CLAUDE.local.md"), kind: .instructions, harness: .claude, scope: scope)
        items += file(base.appendingPathComponent(".claude/CLAUDE.md"), kind: .instructions, harness: .claude, scope: scope)
        items += file(base.appendingPathComponent("AGENTS.md"), kind: .instructions, harness: .codex, scope: scope)
        items += file(base.appendingPathComponent("GEMINI.md"), kind: .instructions, harness: .gemini, scope: scope)
        items += file(base.appendingPathComponent(".gemini/settings.json"), kind: .settings, harness: .gemini, scope: scope)
        items += hooks(in: base.appendingPathComponent(".gemini/settings.json"), harness: .gemini, scope: scope)
        items += markdownFiles(in: base.appendingPathComponent(".gemini/commands"), kind: .command, harness: .gemini, scope: scope, extensions: ["toml"])
        items += markdownFiles(in: base.appendingPathComponent(".github/instructions"), kind: .instructions, harness: .copilot, scope: scope)
        items += markdownFiles(in: base.appendingPathComponent(".github/agents"), kind: .agent, harness: .copilot, scope: scope)
        items += markdownFiles(in: base.appendingPathComponent(".github/hooks"), kind: .hook, harness: .copilot, scope: scope, extensions: ["json"])
        items += file(base.appendingPathComponent(".github/copilot/settings.json"), kind: .settings, harness: .copilot, scope: scope)
        items += file(base.appendingPathComponent(".cursorrules"), kind: .instructions, harness: .cursor, scope: scope)
        items += file(base.appendingPathComponent(".github/copilot-instructions.md"), kind: .instructions, harness: .copilot, scope: scope)
        for name in ["settings.json", "settings.local.json"] {
            let url = base.appendingPathComponent(".claude/\(name)")
            items += file(url, kind: .settings, harness: .claude, scope: scope)
            items += hooks(in: url, harness: .claude, scope: scope)
        }
        items += skills(in: base.appendingPathComponent(".claude/skills"), harness: .claude, scope: scope)
        items += skills(in: base.appendingPathComponent(".agents/skills"), harness: .codex, scope: scope)
        items += markdownFiles(in: base.appendingPathComponent(".claude/agents"), kind: .agent, harness: .claude, scope: scope)
        items += markdownFiles(in: base.appendingPathComponent(".claude/commands"), kind: .command, harness: .claude, scope: scope)
        items += markdownFiles(in: base.appendingPathComponent(".claude/rules"), kind: .instructions, harness: .claude, scope: scope)
        items += markdownFiles(in: base.appendingPathComponent(".cursor/rules"), kind: .instructions, harness: .cursor, scope: scope)
        return items
    }

    func file(_ url: URL, kind: RuleKind, harness: Harness, scope: String, name: String? = nil) -> [RuleItem] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return [] }
        let attributes = try? fm.attributesOfItem(atPath: url.path)
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return [RuleItem(kind: kind, harness: harness, scope: scope, name: name ?? url.lastPathComponent, path: url.path,
                         summary: Self.summary(of: content), size: (attributes?[.size] as? NSNumber)?.intValue ?? 0,
                         modifiedAt: attributes?[.modificationDate] as? Date)]
    }

    func markdownFiles(in dir: URL, kind: RuleKind, harness: Harness, scope: String, extensions: Set<String> = ["md", "mdc"]) -> [RuleItem] {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var items: [RuleItem] = []
        for case let url as URL in enumerator where extensions.contains(url.pathExtension) {
            items += file(url, kind: kind, harness: harness, scope: scope, name: url.deletingPathExtension().lastPathComponent)
        }
        return items
    }

    func skills(in dir: URL, harness: Harness, scope: String) -> [RuleItem] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return entries.flatMap { entry -> [RuleItem] in
            let skill = entry.appendingPathComponent("SKILL.md")
            let resolved = skill.resolvingSymlinksInPath()
            return file(resolved, kind: .skill, harness: harness, scope: scope, name: entry.lastPathComponent).map {
                var item = $0
                item.path = skill.path
                return item
            }
        }
    }

    func hooks(in settings: URL, harness: Harness, scope: String) -> [RuleItem] {
        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return [] }
        var items: [RuleItem] = []
        for (event, value) in hooks.sorted(by: { $0.key < $1.key }) {
            for group in value as? [[String: Any]] ?? [] {
                let matcher = group["matcher"] as? String
                for hook in group["hooks"] as? [[String: Any]] ?? [] {
                    let command = (hook["command"] as? String) ?? (hook["type"] as? String) ?? "?"
                    let name = matcher.map { $0.isEmpty ? event : "\(event) · \($0)" } ?? event
                    items.append(RuleItem(kind: .hook, harness: harness, scope: scope, name: name, path: settings.path,
                                          summary: command.singleLine.truncated(160), size: command.count,
                                          modifiedAt: fileModificationDate(settings.path)))
                }
            }
        }
        return items
    }

    func codexHooks(_ url: URL, scope: String) -> [RuleItem] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let dict = json as? [String: Any], dict["hooks"] != nil {
            return hooks(in: url, harness: .codex, scope: scope)
        }
        return file(url, kind: .hook, harness: .codex, scope: scope)
    }

    public static func summary(of content: String) -> String {
        var body = content
        if body.hasPrefix("---"), let end = body.range(of: "\n---", range: body.index(body.startIndex, offsetBy: 3)..<body.endIndex) {
            let front = String(body[body.startIndex..<end.lowerBound])
            if let description = front.split(separator: "\n").first(where: { $0.hasPrefix("description:") }) {
                return String(description.dropFirst("description:".count)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'")).truncated(160)
            }
            body = String(body[end.upperBound...])
        }
        let line = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("{") && !$0.hasPrefix("[") } ?? ""
        return line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).truncated(160)
    }
}
