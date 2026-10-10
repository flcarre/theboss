import BossCore
import Charts
import SwiftUI

struct AnalyticsPanel: View {
    @ObservedObject var model: GameModel

    var body: some View {
        if let report = model.analytics {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        trendCard(report.trend)
                        TokenStat(label: tr("Prompts · 7 days"), value: "\(report.promptsThisWeek)", tint: Theme.info)
                        TokenStat(label: tr("Corrections · 7 days"), value: "\(report.correctionsThisWeek)", tint: Theme.pink)
                        TokenStat(label: tr("Rules applied"), value: "\(model.suggestions.filter { $0.status == .applied }.count)", tint: Theme.success)
                        TokenStat(label: tr("Whips cracked"), value: "\(model.whipCount)", tint: Theme.crustDark)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    SectionTitle(text: tr("Corrections per 100 prompts, by day")).padding(.top, 6)
                    Chart(report.days) { day in
                        BarMark(x: .value("Day", DayFormat.date(day.day), unit: .day), y: .value("Rate", day.correctionRate * 100))
                            .foregroundStyle(Theme.pink)
                    }
                    .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel().font(Theme.label(11, .medium)).foregroundStyle(Theme.inkSoft) } }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(Theme.label(11, .medium)).foregroundStyle(Theme.inkSoft) } }
                    .frame(height: 190)
                    .padding(14)
                    .card()
                    SectionTitle(text: tr("Prompts sent per day")).padding(.top, 6)
                    Chart(report.days) { day in
                        BarMark(x: .value("Day", DayFormat.date(day.day), unit: .day), y: .value("Prompts", day.prompts))
                            .foregroundStyle(by: .value("Kind", tr("Prompts")))
                        BarMark(x: .value("Day", DayFormat.date(day.day), unit: .day), y: .value("Corrections", day.corrections))
                            .foregroundStyle(by: .value("Kind", tr("Corrections")))
                    }
                    .chartForegroundStyleScale(domain: [tr("Prompts"), tr("Corrections")], range: [Theme.info, Theme.warning])
                    .chartLegend(position: .bottom)
                    .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel().font(Theme.label(11, .medium)).foregroundStyle(Theme.inkSoft) } }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(Theme.label(11, .medium)).foregroundStyle(Theme.inkSoft) } }
                    .frame(height: 190)
                    .padding(14)
                    .card()
                    Text(tr("A correction is a message where you push back on the agent (“no”, “I told you”, “stop”…). The fewer there are, the better your setup understands what you want."))
                        .font(Theme.body(13)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
            }
        } else {
            EmptyState(text: tr("Reading your last 30 days of conversations…"))
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
        return VStack(alignment: .leading, spacing: 6) {
            Text(tr("Trend").uppercased()).font(Theme.label(11, .heavy)).tracking(0.9).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 8) {
                Text(arrow).font(Theme.title(24)).foregroundStyle(color)
                Text(trend.label).font(Theme.label(15, .bold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
        .overlay(alignment: .top) { Rectangle().fill(color).frame(height: 4).padding(.horizontal, 2).padding(.top, 2) }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsCard(tr("Language")) {
                    Picker(tr("Language"), selection: $model.settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                }
                settingsCard(tr("Game")) {
                    Toggle(tr("Notify me when a robot is waiting or done"), isOn: $model.settings.notifications)
                    Toggle(tr("Sounds"), isOn: $model.settings.sounds)
                    row(tr("Zoom")) {
                        Picker(tr("Zoom"), selection: $model.settings.zoom) {
                            Text(tr("× 1 (native pixels)")).tag(1.0)
                            Text("× 1.5").tag(1.5)
                            Text("× 2").tag(2.0)
                        }
                        .labelsHidden().frame(width: 200)
                    }
                    row(tr("Finished robots stay in the open space for")) {
                        Picker(tr("Finished robots"), selection: $model.settings.finishedHours) {
                            Text(tr("1 hour")).tag(1.0)
                            Text(tr("6 hours")).tag(6.0)
                            Text(tr("12 hours")).tag(12.0)
                        }
                        .labelsHidden().frame(width: 140)
                    }
                }
                settingsCard(tr("Rule writing")) {
                    Toggle(tr("Rewrite new rules with Claude automatically"), isOn: $model.settings.autoRefine)
                    note(tr("Optional. The Boss runs Claude Code locally (Haiku model, on your plan) with the conversation excerpts used as evidence. Off by default; the “Rewrite with Claude” button in the mail always works on demand."))
                }
                settingsCard(tr("Privacy")) {
                    note(tr("Everything stays on your Mac. The Boss reads the transcripts of Claude Code (~/.claude), Codex (~/.codex), Gemini CLI (~/.gemini), Copilot CLI (~/.copilot), Cursor (~/.cursor), Pi (~/.pi) and omp (~/.omp), and keeps them in a local SQLite database."))
                    note(tr("Claude limits come from Anthropic's API with the Claude Code token read from the keychain; Codex limits are read from its logs. Nothing is sent anywhere else."))
                    Text(Paths.appSupport.appendingPathComponent("boss.sqlite").path.replacingOccurrences(of: Paths.home.path, with: "~")).font(Theme.mono(12)).foregroundStyle(Theme.inkSoft).textSelection(.enabled)
                }
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .toggleStyle(.switch)
        .font(Theme.label(14, .medium))
        .foregroundStyle(Theme.ink)
        .onChange(of: model.settings) { model.saveSettings() }
    }

    func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: title)
            VStack(alignment: .leading, spacing: 12) { content() }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label)
            Spacer()
            control()
        }
    }

    func note(_ text: String) -> some View {
        Text(text).font(Theme.body(13)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
    }
}
