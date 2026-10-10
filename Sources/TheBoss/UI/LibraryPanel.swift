import BossCore
import SwiftUI

struct LibraryPanel: View {
    @ObservedObject var model: GameModel
    @State private var kind: RuleKind?
    @State private var scope: String?
    @State private var query = ""
    @State private var selected: RuleItem?

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
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Ce qui pilote tes agents")
                Text("Fichiers cachés, skills, hooks et réglages lus par Claude Code, Codex, Cursor et Pi.")
                    .font(Theme.body(12)).foregroundStyle(Theme.ink.opacity(0.65))
                HStack(spacing: 6) {
                    Chip(text: "Tout \(model.rules.count)", color: Theme.base, selected: kind == nil) { kind = nil }
                    ForEach(RuleKind.allCases, id: \.self) { item in
                        let count = model.rules.filter { $0.kind == item }.count
                        if count > 0 {
                            Chip(text: "\(item.label) \(count)", color: Theme.base, selected: kind == item) { kind = item }
                        }
                    }
                }
                HStack {
                    Picker("", selection: $scope) {
                        Text("Tous les projets").tag(String?.none)
                        ForEach(scopes, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    TextField("Chercher…", text: $query).textFieldStyle(.roundedBorder)
                }
                if !model.insightsReady && model.rules.isEmpty {
                    EmptyState(text: "Inventaire en cours…")
                } else {
                    List(filtered, selection: Binding(get: { selected?.id }, set: { id in selected = filtered.first { $0.id == id } })) { item in
                        RuleRow(item: item).tag(item.id)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(18)
            .frame(width: 520)
            Rectangle().fill(Theme.ink).frame(width: 3)
            RuleDetail(item: selected)
        }
    }
}

struct RuleRow: View {
    var item: RuleItem

    var glyph: String {
        switch item.kind {
        case .instructions: "R"
        case .skill: "K"
        case .hook: "H"
        case .agent: "A"
        case .command: "/"
        case .settings: "⚙"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(glyph).font(Theme.pixel(14)).foregroundStyle(Theme.cream)
                .frame(width: 24, height: 24).background(Theme.color(for: item.harness))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.name).font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                    Text(item.scope).font(Theme.pixel(11)).foregroundStyle(Theme.ink.opacity(0.55))
                }
                Text(item.summary).font(Theme.body(11)).foregroundStyle(Theme.ink.opacity(0.65)).lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

struct RuleDetail: View {
    var item: RuleItem?
    @State private var content = ""

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(Theme.pixel(20)).foregroundStyle(Theme.ink)
                        Text(item.path.replacingOccurrences(of: Paths.home.path, with: "~")).font(Theme.mono(11)).foregroundStyle(Theme.ink.opacity(0.6)).textSelection(.enabled)
                        Text("\(item.harness.displayName) · \(item.kind.label) · \(item.size) octets · modifié \(relative(item.modifiedAt))")
                            .font(Theme.body(11)).foregroundStyle(Theme.ink.opacity(0.55))
                    }
                    Spacer()
                    PixelButton(title: "Ouvrir") { NSWorkspace.shared.open(URL(fileURLWithPath: item.path)) }
                    PixelButton(title: "Finder", color: Theme.paper) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
                }
                if item.kind == .hook {
                    Text("Commande du hook").font(Theme.pixel(13)).foregroundStyle(Theme.crustDark)
                    Text(item.summary).font(Theme.mono(12)).foregroundStyle(Theme.ink).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.7))
                }
                ScrollView {
                    Text(content).font(Theme.mono(12)).foregroundStyle(Theme.ink).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                .background(Color.white.opacity(0.7))
                .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
            }
            .padding(18)
            .onAppear { load(item) }
            .onChange(of: item.id) { load(item) }
        } else {
            EmptyState(text: "Choisis un fichier à gauche pour le lire.")
        }
    }

    func load(_ item: RuleItem) {
        let text = (try? String(contentsOfFile: item.path, encoding: .utf8)) ?? "Illisible."
        content = text.count > 60_000 ? String(text.prefix(60_000)) + "\n…" : text
    }
}
