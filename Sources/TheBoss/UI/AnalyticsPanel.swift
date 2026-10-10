import BossCore
import Charts
import SwiftUI

struct AnalyticsPanel: View {
    @ObservedObject var model: GameModel

    var body: some View {
        if let report = model.analytics {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        trendCard(report.trend)
                        TokenStat(label: "Prompts · 7 j", value: report.promptsThisWeek)
                        TokenStat(label: "Corrections · 7 j", value: report.correctionsThisWeek)
                        TokenStat(label: "Règles appliquées", value: model.suggestions.filter { $0.status == .applied }.count)
                    }
                    SectionTitle(text: "Corrections pour 100 prompts, par jour")
                    Chart(report.days) { day in
                        BarMark(x: .value("Jour", DayFormat.date(day.day), unit: .day), y: .value("Taux", day.correctionRate * 100))
                            .foregroundStyle(Theme.pink)
                    }
                    .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.ink.opacity(0.12)); AxisValueLabel().font(Theme.pixel(11)).foregroundStyle(Theme.ink.opacity(0.7)) } }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(Theme.pixel(11)).foregroundStyle(Theme.ink.opacity(0.7)) } }
                    .frame(height: 200)
                    .padding(12)
                    .background(Theme.paper.opacity(0.4))
                    .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
                    SectionTitle(text: "Prompts envoyés par jour")
                    Chart(report.days) { day in
                        BarMark(x: .value("Jour", DayFormat.date(day.day), unit: .day), y: .value("Prompts", day.prompts))
                            .foregroundStyle(Theme.info)
                        BarMark(x: .value("Jour", DayFormat.date(day.day), unit: .day), y: .value("Corrections", day.corrections))
                            .foregroundStyle(Theme.warning)
                    }
                    .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.ink.opacity(0.12)); AxisValueLabel().font(Theme.pixel(11)).foregroundStyle(Theme.ink.opacity(0.7)) } }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(Theme.pixel(11)).foregroundStyle(Theme.ink.opacity(0.7)) } }
                    .frame(height: 200)
                    .padding(12)
                    .background(Theme.paper.opacity(0.4))
                    .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
                    Text("Une correction, c'est un message où tu reprends l'agent (« non », « je t'ai dit », « stop »…). Moins il y en a, mieux ton setup comprend ce que tu veux.")
                        .font(Theme.body(12)).foregroundStyle(Theme.ink.opacity(0.65))
                }
                .padding(22)
            }
        } else {
            EmptyState(text: "Je relis tes 30 derniers jours de conversations…")
        }
    }

    func trendCard(_ trend: Trend) -> some View {
        let color: Color
        let arrow: String
        switch trend {
        case .improving: color = Theme.success; arrow = "↘"
        case .degrading: color = Theme.danger; arrow = "↗"
        case .stable: color = Theme.info; arrow = "→"
        case .notEnoughData: color = Theme.muted; arrow = "…"
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("TENDANCE").font(Theme.pixel(12)).foregroundStyle(Theme.ink.opacity(0.6))
            HStack {
                Text(arrow).font(Theme.pixel(26)).foregroundStyle(color)
                Text(trend.label).font(Theme.pixel(16)).foregroundStyle(Theme.ink)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.15))
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
    }
}

enum DayFormat {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func date(_ key: String) -> Date { formatter.date(from: key) ?? Date() }
}

struct SettingsPanel: View {
    @ObservedObject var model: GameModel

    var body: some View {
        Form {
            Section {
                Toggle("Notifications quand un robot attend ou finit", isOn: $model.settings.notifications)
                Toggle("Sons", isOn: $model.settings.sounds)
                Picker("Zoom", selection: $model.settings.zoom) {
                    Text("× 1 (pixel natif)").tag(1.0)
                    Text("× 1,5").tag(1.5)
                    Text("× 2").tag(2.0)
                }
                Picker("Robots finis gardés dans l'open space", selection: $model.settings.finishedHours) {
                    Text("1 heure").tag(1.0)
                    Text("6 heures").tag(6.0)
                    Text("12 heures").tag(12.0)
                }
            } header: {
                Text("JEU").font(Theme.pixel(14))
            }
            Section {
                Toggle("Reformuler automatiquement les nouvelles règles avec Claude", isOn: $model.settings.autoRefine)
                Text("Optionnel. The Boss lance Claude Code en local (modèle Haiku, sur ton forfait) avec les extraits de conversation qui servent de preuve. Désactivé par défaut ; le bouton « Reformuler avec Claude » du courrier marche toujours à la demande.")
                    .font(Theme.body(12))
            } header: {
                Text("RÉDACTION DES RÈGLES").font(Theme.pixel(14))
            }
            Section {
                Text("Tout reste sur ton Mac. The Boss lit les transcripts de Claude Code (~/.claude), Codex (~/.codex), Cursor (~/.cursor), Pi (~/.pi) et omp (~/.omp), et les range dans une base SQLite locale.")
                    .font(Theme.body(12))
                Text("Les limites Claude viennent de l'API d'Anthropic avec le jeton de Claude Code lu dans le trousseau ; celles de Codex sont lues dans ses journaux. Rien n'est envoyé ailleurs.")
                    .font(Theme.body(12))
                Text("Base locale : \(Paths.appSupport.appendingPathComponent("boss.sqlite").path)").font(Theme.mono(11)).textSelection(.enabled)
            } header: {
                Text("CONFIDENTIALITÉ").font(Theme.pixel(14))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(10)
        .onChange(of: model.settings) { model.saveSettings() }
    }
}
