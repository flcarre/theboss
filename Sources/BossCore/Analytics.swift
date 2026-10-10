import Foundation

public struct DayStat: Hashable, Sendable, Identifiable {
    public var id: String { day }
    public var day: String
    public var prompts: Int
    public var corrections: Int
    public var tokens: Int

    public var correctionRate: Double { prompts == 0 ? 0 : Double(corrections) / Double(prompts) }
}

public enum Trend: Sendable {
    case improving(Double), degrading(Double), stable, notEnoughData

    public var label: String {
        switch self {
        case .improving: tr("Your setup is improving")
        case .degrading: tr("Your setup is getting worse")
        case .stable: tr("Your setup is stable")
        case .notEnoughData: tr("Not enough data yet")
        }
    }
}

public struct AnalyticsReport: Sendable {
    public var days: [DayStat]
    public var trend: Trend
    public var correctionsThisWeek: Int
    public var promptsThisWeek: Int
}

public enum Analytics {
    public static func build(store: Store, daily: [DailyTokens], days count: Int = 28, now: Date = Date()) -> AnalyticsReport {
        let since = Calendar.current.startOfDay(for: now.addingTimeInterval(-Double(count - 1) * 86400))
        let stats = store.dailyPromptStats(since: since)
        var tokensByDay: [String: Int] = [:]
        for entry in daily { tokensByDay[entry.day, default: 0] += entry.tokens.total }
        let days = (0..<count).map { offset -> DayStat in
            let key = DayKey.of(since.addingTimeInterval(Double(offset) * 86400 + 3600))
            let stat = stats[key]
            return DayStat(day: key, prompts: stat?.prompts ?? 0, corrections: stat?.corrections ?? 0, tokens: tokensByDay[key] ?? 0)
        }
        let recent = days.suffix(7)
        let previous = days.dropLast(7).suffix(7)
        return AnalyticsReport(days: days, trend: trend(recent: Array(recent), previous: Array(previous)),
                               correctionsThisWeek: recent.reduce(0) { $0 + $1.corrections },
                               promptsThisWeek: recent.reduce(0) { $0 + $1.prompts })
    }

    static func trend(recent: [DayStat], previous: [DayStat]) -> Trend {
        let recentPrompts = recent.reduce(0) { $0 + $1.prompts }
        let previousPrompts = previous.reduce(0) { $0 + $1.prompts }
        guard recentPrompts >= 10, previousPrompts >= 10 else { return .notEnoughData }
        let recentRate = Double(recent.reduce(0) { $0 + $1.corrections }) / Double(recentPrompts)
        let previousRate = Double(previous.reduce(0) { $0 + $1.corrections }) / Double(previousPrompts)
        let delta = recentRate - previousRate
        if delta <= -0.02 { return .improving(-delta) }
        if delta >= 0.02 { return .degrading(delta) }
        return .stable
    }
}
