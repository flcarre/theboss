import Foundation

public enum SuggestionStatus: String, Codable, Sendable {
    case new, applied, dismissed, saved
}

public enum SuggestionKind: String, Codable, Sendable {
    case learnedRule, setupFix
}

public enum SuggestionOperation: Codable, Hashable, Sendable {
    case appendRule(String)
    case createFile(String)
    case removeLines([String])
    case addFrontmatter(name: String, description: String)

    public func apply(to current: String?) -> String {
        let content = current ?? ""
        switch self {
        case .appendRule(let rule):
            return SuggestionEngine.appending(rule: rule, to: content)
        case .createFile(let body):
            return content.isEmpty ? body : content
        case .removeLines(let lines):
            let remove = Set(lines)
            return content.components(separatedBy: "\n").filter { !remove.contains($0) }.joined(separator: "\n")
        case .addFrontmatter(let name, let description):
            if content.hasPrefix("---") { return content }
            return "---\nname: \(name)\ndescription: \(description)\n---\n\n" + content
        }
    }
}

public struct Evidence: Codable, Hashable, Sendable {
    public var quote: String
    public var context: String?
    public var harness: Harness
    public var sessionId: String
    public var date: Date?
}

public struct Suggestion: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: SuggestionKind
    public var title: String
    public var rationale: String
    public var project: String
    public var filePath: String
    public var operation: SuggestionOperation
    public var evidence: [Evidence]
    public var status: SuggestionStatus
    public var createdAt: Date
    public var refinedRule: String?

    public mutating func refine(with rule: String) {
        refinedRule = rule
        title = rule
        if case .appendRule = operation { operation = .appendRule(rule) }
    }

    public var currentContent: String? { try? String(contentsOfFile: filePath, encoding: .utf8) }

    public var proposedContent: String { operation.apply(to: currentContent) }

    public var diff: [DiffLine] {
        let old = currentContent ?? ""
        return UnifiedDiff.lines(old: old, new: proposedContent, path: displayPath)
    }

    public var displayPath: String {
        let home = Paths.home.path
        return filePath.hasPrefix(home) ? "~" + filePath.dropFirst(home.count) : filePath
    }

    public func apply() throws {
        let new = proposedContent
        let url = URL(fileURLWithPath: filePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try new.write(to: url, atomically: true, encoding: .utf8)
    }
}

public struct SuggestionEngine: Sendable {
    public static let learnedSections = ["## Learned rules", "## Règles apprises"]
    public static var learnedSection: String { tr("## Learned rules") }

    public init() {}

    public func corrections(from prompts: [UserPrompt]) -> [Correction] {
        prompts.compactMap(CorrectionDetector.detect)
    }

    public func suggestions(prompts: [UserPrompt], sessions: [AgentSession]) -> [Suggestion] {
        learnedRules(from: corrections(from: prompts)) + setupFixes(sessions: sessions)
    }

    func learnedRules(from corrections: [Correction]) -> [Suggestion] {
        var clusters: [(project: String, harness: Harness, rule: String, items: [Correction])] = []
        for correction in corrections {
            guard let rule = correction.rule else { continue }
            let project = RulesInventory.projectRoot(correction.prompt.cwd)
            if let index = clusters.firstIndex(where: { $0.project == project && CorrectionDetector.similarity($0.rule, rule) >= 0.45 }) {
                clusters[index].items.append(correction)
            } else {
                clusters.append((project, correction.prompt.harness, rule, [correction]))
            }
        }
        return clusters.compactMap { cluster in
            let target = Self.targetFile(project: cluster.project, harness: cluster.harness)
            let existing = (try? String(contentsOfFile: target, encoding: .utf8)) ?? ""
            if Self.alreadyCovered(rule: cluster.rule, in: existing) { return nil }
            var seenQuotes = Set<String>()
            let unique = cluster.items.filter { seenQuotes.insert($0.prompt.text.lowercased()).inserted }
            let evidence = unique.map {
                Evidence(quote: $0.prompt.text.truncated(400), context: $0.prompt.previousAssistant?.singleLine.truncated(240),
                         harness: $0.prompt.harness, sessionId: $0.prompt.sessionId, date: $0.prompt.timestamp)
            }
            let projectName = cluster.project.isEmpty ? RulesInventory.globalScope : (cluster.project as NSString).lastPathComponent
            let count = unique.count
            return Suggestion(
                id: Self.stableId("rule", target, cluster.rule),
                kind: .learnedRule,
                title: cluster.rule,
                rationale: count > 1
                    ? tr("You corrected the agent %d times on this in %@. A written rule saves you from repeating it.", count, projectName)
                    : tr("You corrected the agent on this in %@. A written rule keeps it from happening again.", projectName),
                project: projectName, filePath: target, operation: .appendRule(cluster.rule),
                evidence: evidence, status: .new,
                createdAt: cluster.items.compactMap(\.prompt.timestamp).max() ?? Date())
        }
    }

    func setupFixes(sessions: [AgentSession]) -> [Suggestion] {
        var result: [Suggestion] = []
        let fm = FileManager.default
        var harnessesByProject: [String: Set<Harness>] = [:]
        for session in sessions where !session.cwd.isEmpty {
            harnessesByProject[RulesInventory.projectRoot(session.cwd), default: []].insert(session.harness)
        }
        for (project, harnesses) in harnessesByProject where fm.fileExists(atPath: project) {
            let name = (project as NSString).lastPathComponent
            let claudeMd = (project as NSString).appendingPathComponent("CLAUDE.md")
            let agentsMd = (project as NSString).appendingPathComponent("AGENTS.md")
            let hasClaude = fm.fileExists(atPath: claudeMd)
            let hasAgents = fm.fileExists(atPath: agentsMd)
            if harnesses.contains(.claude) && hasAgents && !hasClaude {
                result.append(Suggestion(
                    id: Self.stableId("fix", claudeMd, "import-agents"), kind: .setupFix,
                    title: tr("Make Claude Code read AGENTS.md"),
                    rationale: tr("%@ has an AGENTS.md but no CLAUDE.md: Claude Code does not read your rules in this project.", name),
                    project: name, filePath: claudeMd, operation: .createFile("@AGENTS.md\n"), evidence: [],
                    status: .new, createdAt: Self.stamp(agentsMd)))
            }
            if (harnesses.contains(.codex) || harnesses.contains(.pi) || harnesses.contains(.omp)) && hasClaude && !hasAgents,
               let body = try? String(contentsOfFile: claudeMd, encoding: .utf8) {
                result.append(Suggestion(
                    id: Self.stableId("fix", agentsMd, "mirror-claude"), kind: .setupFix,
                    title: tr("Share the CLAUDE.md rules with other agents"),
                    rationale: tr("Codex and Pi read AGENTS.md, which %@ lacks: they work without the CLAUDE.md rules.", name),
                    project: name, filePath: agentsMd, operation: .createFile(body), evidence: [],
                    status: .new, createdAt: Self.stamp(claudeMd)))
            }
            let geminiMd = (project as NSString).appendingPathComponent("GEMINI.md")
            if harnesses.contains(.gemini) && hasAgents && !fm.fileExists(atPath: geminiMd) {
                result.append(Suggestion(
                    id: Self.stableId("fix", geminiMd, "import-agents"), kind: .setupFix,
                    title: tr("Make Gemini read AGENTS.md"),
                    rationale: tr("%@ has an AGENTS.md but no GEMINI.md: Gemini CLI does not read your rules in this project.", name),
                    project: name, filePath: geminiMd, operation: .createFile("@AGENTS.md\n"), evidence: [],
                    status: .new, createdAt: Self.stamp(agentsMd)))
            }
            if hasClaude {
                result += brokenImports(file: claudeMd, project: name)
            }
        }
        result += brokenImports(file: Paths.claude.appendingPathComponent("CLAUDE.md").path, project: RulesInventory.globalScope)
        for root in [Paths.claude.appendingPathComponent("skills"), Paths.codex.appendingPathComponent("skills")] {
            result += skillsWithoutDescription(in: root)
        }
        return result
    }

    func brokenImports(file: String, project: String) -> [Suggestion] {
        guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { return [] }
        let base = (file as NSString).deletingLastPathComponent
        var inCode = false
        var broken: [String] = []
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("```") { inCode.toggle() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !inCode, trimmed.hasPrefix("@"), !trimmed.contains(" ") else { continue }
            var target = String(trimmed.dropFirst())
            if target.hasPrefix("~/") { target = Paths.home.path + target.dropFirst(1) }
            let resolved = target.hasPrefix("/") ? target : (base as NSString).appendingPathComponent(target)
            if !FileManager.default.fileExists(atPath: resolved) { broken.append(line) }
        }
        guard !broken.isEmpty else { return [] }
        return [Suggestion(
            id: Self.stableId("fix", file, broken.joined()), kind: .setupFix,
            title: broken.count == 1 ? tr("Remove a broken import") : tr("Remove %d broken imports", broken.count),
            rationale: tr("%@ points to a file that no longer exists: the agent silently loses that part of its rules.",
                          broken.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")),
            project: project, filePath: file, operation: .removeLines(broken), evidence: [], status: .new, createdAt: Self.stamp(file))]
    }

    func skillsWithoutDescription(in root: URL) -> [Suggestion] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return entries.compactMap { entry in
            let skill = entry.appendingPathComponent("SKILL.md").resolvingSymlinksInPath()
            guard let content = try? String(contentsOf: skill, encoding: .utf8), !content.hasPrefix("---") else { return nil }
            let heading = content.split(separator: "\n").first { $0.hasPrefix("#") }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) } ?? entry.lastPathComponent
            return Suggestion(
                id: Self.stableId("fix", skill.path, "frontmatter"), kind: .setupFix,
                title: tr("Describe the %@ skill", entry.lastPathComponent),
                rationale: tr("Without a name/description header, the agent does not know when to use this skill."),
                project: RulesInventory.globalScope, filePath: skill.path,
                operation: .addFrontmatter(name: entry.lastPathComponent, description: heading),
                evidence: [], status: .new, createdAt: Self.stamp(skill.path))
        }
    }

    static func stamp(_ path: String) -> Date {
        fileModificationDate(path) ?? .distantPast
    }

    static func targetFile(project: String, harness: Harness) -> String {
        if project.isEmpty {
            return harness == .claude ? Paths.claude.appendingPathComponent("CLAUDE.md").path : Paths.codex.appendingPathComponent("AGENTS.md").path
        }
        let fm = FileManager.default
        let claude = (project as NSString).appendingPathComponent("CLAUDE.md")
        let agents = (project as NSString).appendingPathComponent("AGENTS.md")
        if let content = try? String(contentsOfFile: claude, encoding: .utf8), content.contains("@AGENTS.md") { return agents }
        if harness == .claude { return claude }
        if fm.fileExists(atPath: agents) || !fm.fileExists(atPath: claude) { return agents }
        return claude
    }

    static func alreadyCovered(rule: String, in content: String) -> Bool {
        content.components(separatedBy: "\n").contains { CorrectionDetector.similarity($0, rule) >= 0.6 }
    }

    static func appending(rule: String, to content: String) -> String {
        let bullet = "- \(rule)"
        var lines = content.isEmpty ? [] : content.components(separatedBy: "\n")
        while lines.last?.isEmpty == true { lines.removeLast() }
        if let header = lines.firstIndex(where: { learnedSections.contains($0) }) {
            var insert = header + 1
            while insert < lines.count && !lines[insert].hasPrefix("#") { insert += 1 }
            while insert > header + 1 && lines[insert - 1].isEmpty { insert -= 1 }
            lines.insert(bullet, at: insert)
        } else {
            if !lines.isEmpty { lines.append("") }
            lines.append(learnedSection)
            lines.append("")
            lines.append(bullet)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func stableId(_ parts: String...) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in parts.joined(separator: "|").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }
}
