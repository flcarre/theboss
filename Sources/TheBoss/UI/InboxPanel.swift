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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    tabChip(.new, "Nouvelles")
                    tabChip(.saved, "Plus tard")
                    tabChip(.applied, "Appliquées")
                    tabChip(.dismissed, "Ignorées")
                }
                if !model.insightsReady {
                    EmptyState(text: "Le facteur lit tes conversations…")
                } else if items.isEmpty {
                    EmptyState(text: tab == .new ? "Rien à relire. Tes agents se tiennent bien." : "Vide.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(items) { item in
                                SuggestionRow(suggestion: item, selected: item.id == selected?.id)
                                    .onTapGesture { selectedId = item.id }
                            }
                        }
                        .padding(2)
                    }
                }
            }
            .padding(18)
            .frame(width: 400)
            Rectangle().fill(Theme.ink).frame(width: 3)
            if let selected {
                SuggestionDetail(model: model, suggestion: selected)
            } else {
                EmptyState(text: "Choisis une lettre.")
            }
        }
    }

    func tabChip(_ status: SuggestionStatus, _ label: String) -> some View {
        let count = model.suggestions.filter { $0.status == status }.count
        return Chip(text: "\(label) \(count)", color: status == .new ? Theme.pink : Theme.base, selected: tab == status) {
            tab = status
            selectedId = nil
        }
    }
}

struct SuggestionRow: View {
    var suggestion: Suggestion
    var selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PixelImage(image: Assets.image(suggestion.kind == .learnedRule ? "tbfc/icons/icones_ecrans_messages.png" : "tbfc/icons/icones_ecrans_parametres.png"), size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.kind == .learnedRule ? "RÈGLE APPRISE" : "RÉGLAGE À CORRIGER").font(Theme.pixel(11)).foregroundStyle(Theme.crustDark)
                Text(suggestion.title).font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                Text("\(suggestion.project) · \(suggestion.evidence.isEmpty ? "contrôle du setup" : "\(suggestion.evidence.count) preuve\(suggestion.evidence.count > 1 ? "s" : "")")")
                    .font(Theme.body(11)).foregroundStyle(Theme.ink.opacity(0.55))
            }
            Spacer()
        }
        .padding(10)
        .background(selected ? Theme.crust.opacity(0.35) : Theme.paper.opacity(0.5))
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: selected ? 3 : 2))
        .contentShape(Rectangle())
    }
}

struct SuggestionDetail: View {
    @ObservedObject var model: GameModel
    var suggestion: Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.title).font(Theme.pixel(21)).foregroundStyle(Theme.ink)
            Text(suggestion.rationale).font(Theme.body(13)).foregroundStyle(Theme.ink.opacity(0.8))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !suggestion.evidence.isEmpty {
                        SectionTitle(text: "Preuves")
                        ForEach(Array(suggestion.evidence.prefix(6).enumerated()), id: \.offset) { _, evidence in
                            VStack(alignment: .leading, spacing: 6) {
                                if let context = evidence.context {
                                    Text("L'agent : « \(context) »").font(Theme.body(11)).foregroundStyle(Theme.ink.opacity(0.55))
                                }
                                Text("Toi : « \(evidence.quote) »").font(Theme.body(13, weight: .medium)).foregroundStyle(Theme.ink)
                                Text("\(evidence.harness.displayName) · \(relative(evidence.date))").font(Theme.pixel(11)).foregroundStyle(Theme.ink.opacity(0.5))
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.paper.opacity(0.6))
                            .overlay(Rectangle().stroke(Theme.ink.opacity(0.6), lineWidth: 2))
                        }
                    }
                    SectionTitle(text: "Diff exact · \(suggestion.displayPath)")
                    DiffView(lines: suggestion.status == .applied ? [] : suggestion.diff)
                }
            }
            HStack(spacing: 10) {
                if suggestion.status != .applied {
                    PixelButton(title: "Appliquer", color: Theme.success) { model.setStatus(.applied, for: suggestion) }
                }
                if suggestion.status != .saved && suggestion.status != .applied {
                    PixelButton(title: "Plus tard", color: Theme.paper) { model.setStatus(.saved, for: suggestion) }
                }
                if suggestion.status != .dismissed && suggestion.status != .applied {
                    PixelButton(title: "Ignorer", color: Theme.paper) { model.setStatus(.dismissed, for: suggestion) }
                }
                if suggestion.status == .dismissed || suggestion.status == .saved {
                    PixelButton(title: "Remettre", color: Theme.paper) { model.setStatus(.new, for: suggestion) }
                }
                Spacer()
                if suggestion.kind == .learnedRule && suggestion.status != .applied {
                    if model.refining.contains(suggestion.id) {
                        Text("Claude réfléchit…").font(Theme.pixel(14)).foregroundStyle(Theme.ink.opacity(0.6))
                    } else {
                        PixelButton(title: suggestion.refinedRule == nil ? "Reformuler avec Claude" : "Reformuler encore", color: Theme.paper) {
                            model.refine(suggestion)
                        }
                        .help("Lance Claude Code en local (modèle Haiku, ton forfait) pour écrire une règle claire à partir des preuves.")
                    }
                }
                PixelButton(title: "Ouvrir le fichier", color: Theme.paper) {
                    let url = URL(fileURLWithPath: suggestion.filePath)
                    if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
                    else { NSWorkspace.shared.open(url.deletingLastPathComponent()) }
                }
            }
        }
        .padding(18)
    }
}

struct DiffView: View {
    var lines: [DiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if lines.isEmpty {
                Text("Aucun changement à faire : le fichier est déjà à jour.").font(Theme.body(12)).foregroundStyle(Theme.ink.opacity(0.6)).padding(10)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text.isEmpty ? " " : line.text)
                    .font(Theme.mono(12))
                    .foregroundStyle(color(line.kind))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 1)
                    .background(background(line.kind))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 6)
        .background(Color(hex: 0x1E1A33))
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
    }

    func color(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: Color(hex: 0x8FF0B4)
        case .removed: Color(hex: 0xFF9A9A)
        case .header: Theme.crust
        case .context: Theme.textSecondary
        }
    }

    func background(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: Theme.success.opacity(0.16)
        case .removed: Theme.danger.opacity(0.16)
        default: .clear
        }
    }
}
