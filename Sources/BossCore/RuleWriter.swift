import Foundation

public enum RuleWriter {
    public static func claudeExecutable() -> String? {
        let candidates = [Paths.home.appendingPathComponent(".local/bin/claude").path, "/opt/homebrew/bin/claude",
                          "/usr/local/bin/claude", Paths.home.appendingPathComponent(".claude/local/claude").path]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static var workingDirectory: URL {
        let dir = Paths.appSupport.appendingPathComponent("rule-writer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func prompt(for suggestion: Suggestion) -> String {
        let quotes = suggestion.evidence.prefix(5).map { evidence -> String in
            var block = "- The developer wrote: \"\(evidence.quote)\""
            if let context = evidence.context { block += "\n  right after the agent said: \"\(context)\"" }
            return block
        }.joined(separator: "\n")
        return """
        A developer had to correct their coding agent. Here are their messages:
        \(quotes)

        Write ONE general rule to add to the project's \(URL(fileURLWithPath: suggestion.filePath).lastPathComponent) file so the agent never repeats this mistake.
        Constraints: a single imperative sentence, 25 words at most, in the developer's language, without naming a file, ticket or date.
        If no general rule emerges, answer exactly NONE.
        Answer with the rule only, no quotes or bullet.
        """
    }

    public static func refreshClaudeLogin(timeout: TimeInterval = 60) async -> Bool {
        guard let executable = claudeExecutable() else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-p", "Reply with just ok.", "--model", "haiku"]
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if process.isRunning { process.terminate(); return false }
        guard let output = process.standardOutput as? Pipe else { return process.terminationStatus == 0 }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return process.terminationStatus == 0 && !looksLikeError(text)
    }

    public static func refine(_ suggestion: Suggestion, timeout: TimeInterval = 90) async -> Result<String?, Error> {
        guard let executable = claudeExecutable() else {
            return .failure(NSError(domain: "TheBoss", code: 1, userInfo: [NSLocalizedDescriptionKey: tr("Claude Code was not found on this Mac.")]))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-p", prompt(for: suggestion), "--model", "haiku"]
        process.currentDirectoryURL = workingDirectory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failure(error)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if process.isRunning {
            process.terminate()
            return .failure(NSError(domain: "TheBoss", code: 2, userInfo: [NSLocalizedDescriptionKey: tr("Claude did not answer in time.")]))
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus != 0 || looksLikeError(text) {
            let detail = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? "erreur inconnue"
            return .failure(NSError(domain: "TheBoss", code: 3, userInfo: [NSLocalizedDescriptionKey: tr("Claude Code failed: %@", detail)]))
        }
        return .success(clean(text))
    }

    static func looksLikeError(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["failed to authenticate", "invalid api key", "please run /login", "oauth", "api error", "credit balance"].contains { lower.contains($0) }
    }

    static func clean(_ text: String) -> String? {
        var line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").first.map(String.init) ?? ""
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "-•*«»\"' ").union(.whitespaces))
        if line.isEmpty || line.uppercased().hasPrefix("NONE") { return nil }
        if !line.hasSuffix(".") { line += "." }
        return line
    }
}
