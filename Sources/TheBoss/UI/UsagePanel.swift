import BossCore
import Charts
import SwiftUI

struct UsagePanel: View {
    @ObservedObject var model: GameModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SectionTitle(text: tr("Plan limits"))
                    Spacer()
                    PixelButton(title: tr("Refresh"), color: Theme.card) { model.refreshUsage(force: true) }
                }
                if let usage = model.usage {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(usage.providers, id: \.harness) { ProviderCard(model: model, provider: $0) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    SectionTitle(text: tr("Token consumption")).padding(.top, 6)
                    HStack(alignment: .top, spacing: 16) {
                        TokenStat(label: tr("Today"), value: formatTokens(usage.today.total))
                        TokenStat(label: tr("7 days"), value: formatTokens(usage.tokens(lastDays: 7).total))
                        TokenStat(label: tr("30 days"), value: formatTokens(usage.tokens(lastDays: 30).total))
                        TokenStat(label: tr("Output · 7 days"), value: formatTokens(usage.tokens(lastDays: 7).output))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    TokenChart(daily: usage.daily)
                        .frame(height: 220)
                } else {
                    EmptyState(text: tr("Reading the counters…"))
                }
            }
            .padding(22)
        }
    }
}

struct ProviderCard: View {
    @ObservedObject var model: GameModel
    var provider: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PixelImage(image: Theme.robotImage(for: provider.harness), size: 46)
                    .background(Theme.color(for: provider.harness).opacity(0.16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.harness.displayName).font(Theme.label(18, .bold)).foregroundStyle(Theme.ink)
                    Text(provider.plan.map { tr("%@ plan", $0.capitalized) } ?? " ").font(Theme.label(13, .medium)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if let observed = provider.observedAt {
                    Text(relative(observed)).font(Theme.label(12, .medium)).foregroundStyle(Theme.inkSoft.opacity(0.7))
                }
            }
            if provider.state == .ok {
                ForEach(provider.windows, id: \.label) { window in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(window.label).font(Theme.label(14, .bold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(Int(window.usedPercent.rounded())) %").font(Theme.title(20)).foregroundStyle(Theme.ink)
                        }
                        Gauge8(fraction: window.usedPercent / 100, color: gaugeColor(window.usedPercent)).frame(height: 18)
                        if let reset = window.resetsAt {
                            Text(tr("Resets %@", relative(reset))).font(Theme.label(12, .medium)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            } else {
                Text(provider.state.problem ?? "").font(Theme.label(14, .bold)).foregroundStyle(provider.state == .notInstalled ? Theme.inkSoft : Color(hex: 0xC2410C))
                ForEach(Array(provider.state.fixSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)").font(Theme.label(12, .heavy)).foregroundStyle(Theme.cream).frame(width: 20, height: 20).background(Theme.base)
                        Text(LocalizedStringKey(step)).font(Theme.body(14)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if provider.harness == .claude && provider.state == .tokenExpired {
                    if model.repairingClaude {
                        Text(tr("Claude Code is reconnecting…")).font(Theme.label(14, .medium)).foregroundStyle(Theme.inkSoft)
                    } else {
                        HStack {
                            PixelButton(title: tr("Fix automatically")) { model.repairClaudeUsage() }
                                .help(tr("Runs Claude Code once locally (Haiku model): it refreshes its token in the keychain."))
                            PixelButton(title: tr("Sign in again"), color: Theme.card) { model.openClaudeLogin() }
                                .help(tr("Opens Terminal on claude auth login."))
                        }
                    }
                }
                if provider.harness == .claude && provider.state == .signedOut {
                    PixelButton(title: tr("Sign in again")) { model.openClaudeLogin() }
                }
                if provider.state == .keychainBlocked {
                    PixelButton(title: tr("Open Keychain Access"), color: Theme.card) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}

struct TokenStat: View {
    var label: String
    var value: String
    var tint: Color = Theme.crust

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Theme.label(11, .heavy)).tracking(0.9).foregroundStyle(Theme.inkSoft)
            Text(value).font(Theme.title(26)).foregroundStyle(Theme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
        .overlay(alignment: .top) { Rectangle().fill(tint).frame(height: 4).padding(.horizontal, 2).padding(.top, 2) }
    }
}

struct TokenChart: View {
    var daily: [DailyTokens]

    var body: some View {
        let cutoff = Date().addingTimeInterval(-13 * 86400)
        let formatter = DateFormatter()
        let points = daily.compactMap { entry -> (Date, Harness, Int)? in
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: entry.day), date >= Calendar.current.startOfDay(for: cutoff) else { return nil }
            return (date, entry.harness, entry.tokens.total)
        }
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                BarMark(x: .value("Day", point.0, unit: .day), y: .value("Tokens", point.2))
                    .foregroundStyle(by: .value("Harness", point.1.displayName))
            }
        }
        .chartForegroundStyleScale(domain: Harness.allCases.map(\.displayName), range: Harness.allCases.map(Theme.color(for:)))
        .chartLegend(position: .bottom) { LegendRow() }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Theme.ink.opacity(0.12))
                AxisValueLabel { if let v = value.as(Int.self) { Text(formatTokens(v)).font(Theme.label(12)).foregroundStyle(Theme.ink.opacity(0.7)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(Theme.label(12)).foregroundStyle(Theme.ink.opacity(0.7))
            }
        }
        .padding(14)
        .card()
    }
}

struct LegendRow: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(Harness.allCases, id: \.self) { harness in
                HStack(spacing: 5) {
                    Rectangle().fill(Theme.color(for: harness)).frame(width: 10, height: 10)
                    Text(harness.displayName).font(Theme.label(12)).foregroundStyle(Theme.ink.opacity(0.75))
                }
            }
        }
    }
}
