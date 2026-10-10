import BossCore
import SwiftUI

struct InboxPanel: View {
    @ObservedObject var model: GameModel
    @State private var tab: SuggestionStatus = .new
    @State private var selectedId: String?

    var items: [Suggestion] { model.suggestions.filter { $0.status == tab } }
    var selected: Suggestion? { items.first { $0.id == selectedId } ?? items.first }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                SegmentedTabs(items: [
                    tabItem(.new, tr("New"), Theme.pink),
                    tabItem(.saved, tr("Later"), Theme.base),
                    tabItem(.applied, tr("Applied"), Theme.base),
                    tabItem(.dismissed, tr("Dismissed"), Theme.base),
                ], selection: Binding(get: { tab.rawValue }, set: { tab = SuggestionStatus(rawValue: $0) ?? .new; selectedId = nil }))
                if !model.insightsReady {
                    EmptyState(text: tr("The mailman is reading your conversations…"))
                } else if items.isEmpty {
                    EmptyState(text: tab == .new ? tr("Nothing to review. Your agents are behaving.") : tr("Empty."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(items) { item in
                                SuggestionRow(suggestion: item, selected: item.id == selected?.id)
                                    .onTapGesture { selectedId = item.id }
                            }
                        }
                        .padding(.trailing, 6)
                        .padding(.bottom, 6)
                    }
                }
            }
            .padding(20)
            .frame(width: 460)
            Rectangle().fill(Theme.ink).frame(width: 3)
            if let selected {
                SuggestionDetail(model: model, suggestion: selected)
            } else {
                EmptyState(text: tr("Pick a letter."))
            }
        }
    }

    func tabItem(_ status: SuggestionStatus, _ label: String, _ color: Color) -> TabItem {
        TabItem(id: status.rawValue, title: label, count: model.suggestions.filter { $0.status == status }.count, color: color)
    }
}

struct SuggestionRow: View {
    var suggestion: Suggestion
    var selected: Bool

    var kindLabel: String { suggestion.kind == .learnedRule ? tr("Learned rule") : tr("Setup fix") }

    var detail: String {
        if suggestion.evidence.isEmpty { return tr("%@ · setup check", suggestion.project) }
        return suggestion.evidence.count == 1 ? tr("%@ · 1 piece of evidence", suggestion.project) : tr("%@ · %d pieces of evidence", suggestion.project, suggestion.evidence.count)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PixelImage(image: suggestion.kind == .learnedRule ? Icon.mail : Icon.settings, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(kindLabel.uppercased()).font(Theme.label(10, .heavy)).tracking(0.9).foregroundStyle(Theme.crustDark)
                Text(suggestion.title).font(Theme.label(14, .bold)).foregroundStyle(Theme.ink).lineLimit(2)
                Text(detail).font(Theme.label(12, .medium)).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .card(fill: selected ? Color(hex: 0xFFF1C9) : Theme.card, border: selected ? Theme.crustDark : Theme.ink, lift: selected ? 0 : 2)
        .contentShape(Rectangle())
    }
}

struct SuggestionDetail: View {
    @ObservedObject var model: GameModel
    var suggestion: Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.title).font(Theme.label(20, .bold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text(suggestion.rationale).font(Theme.body(14)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !suggestion.evidence.isEmpty {
                        SectionTitle(text: tr("Evidence"))
                        ForEach(Array(suggestion.evidence.prefix(6).enumerated()), id: \.offset) { _, evidence in
                            VStack(alignment: .leading, spacing: 8) {
                                if let context = evidence.context {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(tr("Agent")).font(Theme.label(11, .heavy)).foregroundStyle(Theme.inkSoft).frame(width: 46, alignment: .leading)
                                        Text(context).font(Theme.body(13)).foregroundStyle(Theme.inkSoft)
                                    }
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Text(tr("You")).font(Theme.label(11, .heavy)).foregroundStyle(Theme.crustDark).frame(width: 46, alignment: .leading)
                                    Text(evidence.quote).font(Theme.body(14, weight: .semibold)).foregroundStyle(Theme.ink)
                                }
                                HStack(spacing: 6) {
                                    HarnessTag(harness: evidence.harness)
                                    Text(relative(evidence.date)).font(Theme.label(11, .medium)).foregroundStyle(Theme.inkSoft)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(lift: 2)
                        }
                    }
                    SectionTitle(text: tr("Exact diff · %@", suggestion.displayPath))
                    DiffView(lines: suggestion.status == .applied ? [] : suggestion.diff)
                }
                .padding(.trailing, 6)
                .padding(.bottom, 6)
            }
            HStack(spacing: 10) {
                if suggestion.status != .applied {
                    PixelButton(title: tr("Apply"), color: Theme.success) { model.setStatus(.applied, for: suggestion) }
                }
                if suggestion.status != .saved && suggestion.status != .applied {
                    PixelButton(title: tr("Later"), color: Theme.card) { model.setStatus(.saved, for: suggestion) }
                }
                if suggestion.status != .dismissed && suggestion.status != .applied {
                    PixelButton(title: tr("Dismiss"), color: Theme.card) { model.setStatus(.dismissed, for: suggestion) }
                }
                if suggestion.status == .dismissed || suggestion.status == .saved {
                    PixelButton(title: tr("Restore"), color: Theme.card) { model.setStatus(.new, for: suggestion) }
                }
                Spacer()
                if suggestion.kind == .learnedRule && suggestion.status != .applied {
                    if model.refining.contains(suggestion.id) {
                        Text(tr("Claude is thinking…")).font(Theme.label(14, .medium)).foregroundStyle(Theme.inkSoft)
                    } else {
                        PixelButton(title: suggestion.refinedRule == nil ? tr("Rewrite with Claude") : tr("Rewrite again"), color: Theme.card) {
                            model.refine(suggestion)
                        }
                        .help(tr("Runs Claude Code locally (Haiku model, your plan) to write a clear rule from the evidence."))
                    }
                }
                PixelButton(title: tr("Open file"), color: Theme.card) {
                    let url = URL(fileURLWithPath: suggestion.filePath)
                    if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
                    else { NSWorkspace.shared.open(url.deletingLastPathComponent()) }
                }
            }
        }
        .padding(20)
    }
}

struct DiffView: View {
    var lines: [DiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if lines.isEmpty {
                Text(tr("Nothing to change: the file is already up to date.")).font(Theme.body(13)).foregroundStyle(Theme.textSecondary).padding(12)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text.isEmpty ? " " : line.text)
                    .font(Theme.mono(13))
                    .foregroundStyle(color(line.kind))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    .background(background(line.kind))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
        .card(fill: Color(hex: 0x1E1A33))
    }

    func color(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: Color(hex: 0x8FF0B4)
        case .removed: Color(hex: 0xFFA8A8)
        case .header: Theme.crust
        case .context: Color(hex: 0xD6D0EC)
        }
    }

    func background(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: Theme.success.opacity(0.18)
        case .removed: Theme.danger.opacity(0.18)
        default: .clear
        }
    }
}
