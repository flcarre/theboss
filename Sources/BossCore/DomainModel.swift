import Foundation

public struct DomainFact: Hashable, Sendable, Identifiable {
    public var id: String { source + "|" + text }
    public var text: String
    public var source: String
    public var date: Date?

    public init(text: String, source: String, date: Date? = nil) {
        self.text = text
        self.source = source
        self.date = date
    }
}

public struct DomainModel: Sendable, Identifiable {
    public var id: String { root }
    public var root: String
    public var name: String
    public var intent: String
    public var conventions: [DomainFact]
    public var decisions: [DomainFact]
    public var activity: [DomainFact]
    public var agents: [Harness: Int]
    public var conflicts: [String]

    public var exportPath: String { (root as NSString).appendingPathComponent(".boss/domain.md") }

    public var markdown: String {
        var lines = ["# \(name) · modèle du domaine", ""]
        lines += ["## Intention", "", intent.isEmpty ? "_À écrire._" : intent, ""]
        if !conventions.isEmpty {
            lines += ["## Conventions", ""] + conventions.map { "- \($0.text)" } + [""]
        }
        if !decisions.isEmpty {
            lines += ["## Décisions", ""] + decisions.map { "- \($0.text) (\($0.source))" } + [""]
        }
        if !activity.isEmpty {
            lines += ["## Travaux récents", ""] + activity.prefix(10).map { "- \($0.text) (\($0.source))" } + [""]
        }
        return lines.joined(separator: "\n")
    }
}

public enum DomainModelBuilder {
    static let instructionFiles = ["CLAUDE.md", "AGENTS.md", "CLAUDE.local.md", ".cursorrules", "GEMINI.md"]

    public static func projects(from sessions: [AgentSession]) -> [String] {
        let roots = sessions.map { RulesInventory.projectRoot($0.cwd) }.filter { !$0.isEmpty }
        var seen = Set<String>()
        return roots.filter { seen.insert($0).inserted }
    }

    public static func build(root: String, intent: String, sessions: [AgentSession], suggestions: [Suggestion]) -> DomainModel {
        let fm = FileManager.default
        var conventions: [DomainFact] = []
        var decisions: [DomainFact] = []
        var bulletsByFile: [String: Set<String>] = [:]
        for file in instructionFiles {
            let path = (root as NSString).appendingPathComponent(file)
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            var inLearned = false
            var inCode = false
            for raw in content.components(separatedBy: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("```") { inCode.toggle(); continue }
                if inCode { continue }
                if line.hasPrefix("#") {
                    inLearned = line == SuggestionEngine.learnedSection
                    continue
                }
                guard line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }
                let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard text.count >= 6 else { continue }
                bulletsByFile[file, default: []].insert(normalize(text))
                let fact = DomainFact(text: text, source: file, date: fileModificationDate(path))
                if inLearned { decisions.append(fact) } else { conventions.append(fact) }
            }
        }
        if let rulesDir = try? fm.contentsOfDirectory(atPath: (root as NSString).appendingPathComponent(".cursor/rules")) {
            for file in rulesDir where file.hasSuffix(".mdc") || file.hasSuffix(".md") {
                let path = (root as NSString).appendingPathComponent(".cursor/rules/\(file)")
                let summary = RulesInventory.summary(of: (try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
                if !summary.isEmpty { conventions.append(DomainFact(text: summary, source: ".cursor/rules/\(file)")) }
            }
        }
        let name = (root as NSString).lastPathComponent
        for suggestion in suggestions where suggestion.kind == .learnedRule && suggestion.project == name && suggestion.status != .dismissed {
            let status = suggestion.status == .applied ? "appliquée" : "en attente"
            if !decisions.contains(where: { normalize($0.text) == normalize(suggestion.title) }) {
                decisions.append(DomainFact(text: suggestion.title, source: "courrier · \(status)", date: suggestion.createdAt))
            }
        }
        let projectSessions = sessions.filter { RulesInventory.projectRoot($0.cwd) == root }
            .sorted { $0.updatedAt > $1.updatedAt }
        let activity = projectSessions.map { DomainFact(text: $0.title, source: $0.harness.displayName, date: $0.updatedAt) }
        var agents: [Harness: Int] = [:]
        for session in projectSessions { agents[session.harness, default: 0] += 1 }
        return DomainModel(root: root, name: name, intent: intent, conventions: conventions, decisions: decisions,
                           activity: activity, agents: agents, conflicts: conflicts(bulletsByFile))
    }

    static func conflicts(_ bulletsByFile: [String: Set<String>]) -> [String] {
        guard let claude = bulletsByFile["CLAUDE.md"], let agents = bulletsByFile["AGENTS.md"], !claude.isEmpty, !agents.isEmpty else { return [] }
        let onlyClaude = claude.subtracting(agents).count
        let onlyAgents = agents.subtracting(claude).count
        guard onlyClaude > 0 || onlyAgents > 0 else { return [] }
        return ["CLAUDE.md et AGENTS.md divergent : \(onlyClaude) règle\(onlyClaude > 1 ? "s" : "") seulement pour Claude, \(onlyAgents) seulement pour les autres agents."]
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
