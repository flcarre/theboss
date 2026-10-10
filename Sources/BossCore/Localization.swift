import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case french = "fr"

    public var displayName: String {
        switch self {
        case .english: "English"
        case .french: "Français"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }
}

public enum Localizer {
    nonisolated(unsafe) public static var language: AppLanguage = .english

    public static func text(_ key: String) -> String {
        language == .french ? (FrenchStrings.table[key] ?? key) : key
    }
}

public func tr(_ key: String) -> String {
    Localizer.text(key)
}

public func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: Localizer.text(key), locale: Localizer.language.locale, arguments: arguments)
}
