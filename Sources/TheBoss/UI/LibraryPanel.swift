import BossCore
import SwiftUI

struct LibraryPanel: View {
    @ObservedObject var model: GameModel
    @State private var kind: RuleKind?
    @State private var scope: String?
    @State private var query = ""
    @State private var selectedId: String?

    var scopes: [String] {
        let all = Set(model.rules.map(\.scope))
        return [RulesInventory.globalScope] + all.subtracting([RulesInventory.globalScope]).sorted()
    }

    var filtered: [RuleItem] {
        model.rules.filter { item in
            (kind == nil || item.kind == kind) && (scope == nil || item.scope == scope)
                && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query) || item.summary.localizedCaseInsensitiveContains(query))
        }
        .sorted { ($0.scope, $0.kind.rawValue, $0.name) < ($1.scope, $1.kind.rawValue, $1.name) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(text: tr("All"), count: model.rules.count, color: Theme.base, selected: kind == nil) { kind = nil }
                        ForEach(RuleKind.allCases, id: \.self) { item in
                            let count = model.rules.filter { $0.kind == item }.count
                            if count > 0 {
                                Chip(text: item.label, count: count, color: Theme.base, selected: kind == item) { kind = item }
                            }
                        }
                    }
                    .padding(.bottom, 4)
                    .padding(.trailing, 4)
                }
                HStack(spacing: 10) {
                    Picker("", selection: $scope) {
                        Text(tr("All projects")).tag(String?.none)
                        ForEach(scopes, id: \.self) { Text($0 == RulesInventory.globalScope ? tr("Global") : $0).tag(String?.some($0)) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    SearchField(text: $query, placeholder: tr("Search…"))
                }
                if !model.insightsReady && model.rules.isEmpty {
                    EmptyState(text: tr("Taking inventory…"))
                } else if filtered.isEmpty {
                    EmptyState(text: tr("Nothing matches."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filtered) { item in
                                RuleRow(item: item, selected: item.id == selectedId)
                                    .onTapGesture { selectedId = item.id }
                            }
                        }
                        .padding(.trailing, 6)
                        .padding(.bottom, 6)
                    }
                }
            }
            .padding(20)
            .frame(width: 500)
            Rectangle().fill(Theme.ink).frame(width: 3)
            RuleDetail(item: model.rules.first { $0.id == selectedId })
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            PixelImage(image: Icon.search, size: 18)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.label(14, .medium))
            if !text.isEmpty {
                Button { text = "" } label: { Text("✕").font(Theme.label(12, .bold)).foregroundStyle(Theme.inkSoft) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Theme.card)
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
    }
}

struct RuleRow: View {
    var item: RuleItem
    var selected: Bool

    var glyph: String {
        switch item.kind {
        case .instructions: "R"
        case .skill: "S"
        case .hook: "H"
        case .agent: "A"
        case .command: "/"
        case .settings: "⚙"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(glyph).font(Theme.label(13, .heavy)).foregroundStyle(Theme.cream)
                .frame(width: 26, height: 26).background(Theme.color(for: item.harness))
                .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name).font(Theme.label(14, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                    Text(item.scope == RulesInventory.globalScope ? tr("Global") : item.scope)
                        .font(Theme.label(11, .heavy)).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Theme.ink.opacity(0.07))
                }
                Text(item.summary.isEmpty ? item.kind.label : item.summary).font(Theme.body(13)).foregroundStyle(Theme.inkSoft).lineLimit(2)
            }
        }
        .padding(10)
        .card(fill: selected ? Color(hex: 0xFFF1C9) : Theme.card, border: selected ? Theme.crustDark : Theme.ink, lift: selected ? 0 : 2)
        .contentShape(Rectangle())
    }
}

struct RuleDetail: View {
    var item: RuleItem?
    @State private var content = ""

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name).font(Theme.label(20, .bold)).foregroundStyle(Theme.ink)
                        Text(item.path.replacingOccurrences(of: Paths.home.path, with: "~")).font(Theme.mono(12)).foregroundStyle(Theme.inkSoft).textSelection(.enabled)
                        HStack(spacing: 8) {
                            HarnessTag(harness: item.harness)
                            Text(tr("%@ · %d bytes · modified %@", item.kind.label, item.size, relative(item.modifiedAt)))
                                .font(Theme.label(12, .medium)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer()
                    PixelButton(title: tr("Open")) { NSWorkspace.shared.open(URL(fileURLWithPath: item.path)) }
                    PixelButton(title: "Finder", color: Theme.card) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
                }
                if item.kind == .hook {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(text: tr("Hook command"))
                        Text(item.summary).font(Theme.mono(13)).foregroundStyle(Theme.ink).textSelection(.enabled)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading).card(lift: 0)
                    }
                }
                ScrollView {
                    Text(content).font(Theme.mono(13)).foregroundStyle(Theme.ink).lineSpacing(2).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                .card()
            }
            .padding(20)
            .onAppear { load(item) }
            .onChange(of: item.id) { load(item) }
        } else {
            EmptyState(text: tr("Pick a file on the left to read it."))
        }
    }

    func load(_ item: RuleItem) {
        let text = (try? String(contentsOfFile: item.path, encoding: .utf8)) ?? tr("Unreadable.")
        content = text.count > 60_000 ? String(text.prefix(60_000)) + "\n…" : text
    }
}
