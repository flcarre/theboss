import Foundation

public struct Correction: Hashable, Sendable {
    public var prompt: UserPrompt
    public var rule: String?
    public var score: Int
}

public enum CorrectionDetector {
    static let openers = [
        "non", "no", "nope", "nan", "stop", "arrête", "arrete", "attends", "wait", "pas ça", "pas ca",
        "c'est pas", "ce n'est pas", "c'est faux", "faux", "wrong", "that's wrong", "that's not", "not what i",
        "je t'ai dit", "je t'avais dit", "i told you", "i said", "on a dit", "j'ai dit", "pourquoi tu", "why did you",
        "why are you", "tu as oublié", "t'as oublié", "you forgot", "encore", "again", "revert", "annule", "undo",
    ]

    static let ruleMarkers = [
        "toujours", "jamais", "always", "never", "don't", "do not", "n'utilise pas", "n'ajoute pas", "ne touche pas",
        "ne mets pas", "ne fais pas", "il ne faut pas", "évite", "evite", "avoid", "prefer", "préfère", "prefere",
        "instead of", "plutôt que", "plutot que", "au lieu de", "n'oublie pas", "remember to", "make sure",
        "assure-toi", "à chaque fois", "a chaque fois", "every time", "each time", "no more", "arrête de", "arrete de",
        "stop using", "stop adding", "by default", "par défaut",
    ]

    static let specificMarkers = ["http", "/issues/", "/pull/", "ce fichier", "this file", "cette pr", "this pr", "ce ticket", "la version d'avant"]

    static let correctionPhrases = [
        "je t'ai dit", "je t'avais dit", "i told you", "i said", "on a dit", "tu as oublié", "t'as oublié",
        "you forgot", "pas comme ça", "pas comme ca", "c'est pas ce que", "that's not what", "not what i asked",
        "pourquoi tu as", "why did you", "tu n'aurais pas dû", "you shouldn't have", "you should not have",
        "encore une fois", "once again", "combien de fois", "how many times",
    ]

    public static func detect(_ prompt: UserPrompt) -> Correction? {
        let text = prompt.text
        guard text.count >= 6, text.count <= 700, !text.hasPrefix("/") else { return nil }
        let lower = text.lowercased()
        var score = 0
        let head = String(lower.prefix(24))
        if openers.contains(where: { opener in
            head == opener || head.hasPrefix(opener + " ") || head.hasPrefix(opener + ",") || head.hasPrefix(opener + ".") || head.hasPrefix(opener + "!")
        }) {
            score += 2
        }
        score += correctionPhrases.filter { lower.contains($0) }.count * 2
        let rule = extractRule(text)
        if rule != nil { score += 1 }
        guard score >= 2 else { return nil }
        return Correction(prompt: prompt, rule: rule, score: score)
    }

    static func extractRule(_ text: String) -> String? {
        let sentences = text
            .replacingOccurrences(of: "\n", with: ". ")
            .split(whereSeparator: { ".!?;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 8 }
        let candidates = sentences.filter { sentence in
            let lower = sentence.lowercased()
            return ruleMarkers.contains(where: { lower.contains($0) }) && !specificMarkers.contains(where: { lower.contains($0) })
        }
        guard let best = candidates.max(by: { markerCount($0) < markerCount($1) }) else { return nil }
        let cleaned = clean(best)
        guard cleaned.count >= 8, cleaned.count <= 220 else { return nil }
        return cleaned
    }

    static func markerCount(_ sentence: String) -> Int {
        let lower = sentence.lowercased()
        return ruleMarkers.filter { lower.contains($0) }.count
    }

    static func clean(_ sentence: String) -> String {
        var text = sentence
        let strip = ["non,", "non ", "no,", "no ", "nope,", "nan,", "stop,", "attends,", "wait,", "mais ", "but ",
                     "je t'ai dit de ", "je t'ai dit que ", "je t'ai dit ", "i told you to ", "i told you ", "i said ",
                     "on a dit ", "j'ai dit ", "encore une fois,", "encore une fois ", "again,", "please ", "stp ", "s'il te plaît "]
        var changed = true
        while changed {
            changed = false
            for prefix in strip where text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        guard let first = text.first else { return text }
        text = first.uppercased() + text.dropFirst()
        if !text.hasSuffix(".") { text += "." }
        return text
    }

    static func words(_ text: String) -> Set<String> {
        let stop: Set<String> = ["le", "la", "les", "de", "des", "un", "une", "et", "à", "a", "en", "the", "a", "an", "to", "of",
                                 "and", "in", "on", "is", "it", "pas", "ne", "you", "tu", "je", "i", "que", "qui", "pour", "for"]
        return Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stop.contains($0) })
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let wa = words(a), wb = words(b)
        guard !wa.isEmpty, !wb.isEmpty else { return 0 }
        return Double(wa.intersection(wb).count) / Double(wa.union(wb).count)
    }
}
