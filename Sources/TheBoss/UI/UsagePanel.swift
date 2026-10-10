import BossCore
import Charts
import SwiftUI

struct UsagePanel: View {
    @ObservedObject var model: GameModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    SectionTitle(text: "Limites de tes forfaits")
                    Spacer()
                    PixelButton(title: "Rafraîchir", color: Theme.paper) { model.refreshUsage(force: true) }
                }
                if let usage = model.usage {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                        ForEach(usage.providers, id: \.harness) { ProviderCard(model: model, provider: $0) }
                    }
                    SectionTitle(text: "Consommation de tokens")
                    HStack(spacing: 16) {
                        TokenStat(label: "Aujourd'hui", value: usage.today.total)
                        TokenStat(label: "7 jours", value: usage.tokens(lastDays: 7).total)
                        TokenStat(label: "30 jours", value: usage.tokens(lastDays: 30).total)
                        TokenStat(label: "Sorties · 7 j", value: usage.tokens(lastDays: 7).output)
                    }
                    TokenChart(daily: usage.daily)
                        .frame(height: 220)
                } else {
                    EmptyState(text: "Lecture des compteurs…")
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PixelImage(image: Theme.robotImage(for: provider.harness), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.harness.displayName).font(Theme.pixel(18)).foregroundStyle(Theme.ink)
                    Text(provider.plan.map { "Forfait \($0.capitalized)" } ?? " ").font(Theme.body(12)).foregroundStyle(Theme.ink.opacity(0.6))
                }
                Spacer()
                if let observed = provider.observedAt {
                    Text(relative(observed)).font(Theme.body(11)).foregroundStyle(Theme.ink.opacity(0.5))
                }
            }
            if provider.state == .ok {
                ForEach(provider.windows, id: \.label) { window in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(window.label).font(Theme.pixel(14)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(Int(window.usedPercent.rounded())) %").font(Theme.pixel(16)).foregroundStyle(gaugeColor(window.usedPercent))
                        }
                        Gauge8(fraction: window.usedPercent / 100, color: gaugeColor(window.usedPercent)).frame(height: 18)
                        if let reset = window.resetsAt {
                            Text("Remise à zéro \(relative(reset))").font(Theme.body(11)).foregroundStyle(Theme.ink.opacity(0.55))
                        }
                    }
                }
            } else {
                Text(provider.state.problem ?? "").font(Theme.body(13, weight: .semibold)).foregroundStyle(provider.state == .notInstalled ? Theme.ink.opacity(0.6) : Theme.warning)
                ForEach(Array(provider.state.fixSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)").font(Theme.pixel(13)).foregroundStyle(Theme.cream).frame(width: 20, height: 20).background(Theme.base)
                        Text(LocalizedStringKey(step)).font(Theme.body(12)).foregroundStyle(Theme.ink)
                    }
                }
                if provider.harness == .claude && provider.state == .tokenExpired {
                    if model.repairingClaude {
                        Text("Claude Code se reconnecte…").font(Theme.pixel(13)).foregroundStyle(Theme.ink.opacity(0.6))
                    } else {
                        HStack {
                            PixelButton(title: "Réparer automatiquement") { model.repairClaudeUsage() }
                                .help("Lance Claude Code une fois en local (modèle Haiku) : il rafraîchit son jeton dans le trousseau.")
                            PixelButton(title: "Se reconnecter", color: Theme.paper) { model.openClaudeLogin() }
                                .help("Ouvre le Terminal sur claude auth login.")
                        }
                    }
                }
                if provider.harness == .claude && provider.state == .signedOut {
                    PixelButton(title: "Se reconnecter") { model.openClaudeLogin() }
                }
                if provider.state == .keychainBlocked {
                    PixelButton(title: "Ouvrir Trousseaux d'accès", color: Theme.paper) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.paper.opacity(0.5))
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
    }
}

struct TokenStat: View {
    var label: String
    var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(Theme.pixel(12)).foregroundStyle(Theme.ink.opacity(0.6))
            Text(formatTokens(value)).font(Theme.pixel(26)).foregroundStyle(Theme.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.opacity(0.5))
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
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
                BarMark(x: .value("Jour", point.0, unit: .day), y: .value("Tokens", point.2))
                    .foregroundStyle(by: .value("Harnais", point.1.displayName))
            }
        }
        .chartForegroundStyleScale(domain: Harness.allCases.map(\.displayName), range: Harness.allCases.map(Theme.color(for:)))
        .chartLegend(position: .bottom) { LegendRow() }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Theme.ink.opacity(0.12))
                AxisValueLabel { if let v = value.as(Int.self) { Text(formatTokens(v)).font(Theme.pixel(11)).foregroundStyle(Theme.ink.opacity(0.7)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(Theme.pixel(11)).foregroundStyle(Theme.ink.opacity(0.7))
            }
        }
        .padding(12)
        .background(Theme.paper.opacity(0.4))
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
    }
}

struct LegendRow: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(Harness.allCases, id: \.self) { harness in
                HStack(spacing: 5) {
                    Rectangle().fill(Theme.color(for: harness)).frame(width: 10, height: 10)
                    Text(harness.displayName).font(Theme.pixel(11)).foregroundStyle(Theme.ink.opacity(0.75))
                }
            }
        }
    }
}
