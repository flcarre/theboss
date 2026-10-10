import BossCore
import SwiftUI

struct PanelHost: View {
    @ObservedObject var model: GameModel
    var panel: Panel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PixelImage(image: Assets.image(icon), size: 30)
                Text(title).font(Theme.pixel(24)).foregroundStyle(Theme.cream)
                Spacer()
                Text("Échap").font(Theme.pixel(12)).foregroundStyle(Theme.textSecondary)
                Button { model.closePanel() } label: {
                    PixelImage(image: Assets.image("tbfc/icons/icones_actions_fermer.png"), size: 28)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.base)
            Rectangle().fill(Theme.crust).frame(height: 3)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cream)
                .environment(\.colorScheme, .light)
        }
        .padding(8)
        .background(ZStack { PixelRect(step: 4).fill(Theme.ink); PixelRect(step: 3).fill(Theme.crust).padding(4); PixelRect(step: 2).fill(Theme.ink).padding(6) })
        .frame(maxWidth: 1180, maxHeight: 820)
    }

    @ViewBuilder var content: some View {
        switch panel {
        case .overview: OverviewPanel(model: model)
        case .usage: UsagePanel(model: model)
        case .library: LibraryPanel(model: model)
        case .inbox: InboxPanel(model: model)
        case .analytics: AnalyticsPanel(model: model)
        case .settings: SettingsPanel(model: model)
        case .domain: DomainPanel(model: model)
        case .robot(let id): RobotPanel(model: model, sessionId: id)
        }
    }

    var title: String {
        switch panel {
        case .overview: "Écran des agents"
        case .usage: "Ordinateur du boss · Usage"
        case .library: "Bibliothèque des règles"
        case .inbox: "Courrier · Suggestions"
        case .analytics: "Tableau blanc · Stats"
        case .settings: "Réglages"
        case .domain: "Archives · Modèle du domaine"
        case .robot(let id): model.session(id: id).map { RobotName.of($0) + " · journal" } ?? "Journal"
        }
    }

    var icon: String {
        switch panel {
        case .overview: "tbfc/icons/icones_ecrans_equipe.png"
        case .usage: "tbfc/icons/icones_ecrans_classement.png"
        case .library: "tbfc/icons/icones_ecrans_quetes.png"
        case .inbox: "tbfc/icons/icones_ecrans_messages.png"
        case .analytics: "tbfc/icons/icones_ecrans_succes.png"
        case .settings: "tbfc/icons/icones_ecrans_parametres.png"
        case .domain: "tbfc/icons/icones_ecrans_carte.png"
        case .robot: "tbfc/icons/icones_ecrans_album.png"
        }
    }
}

struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(Theme.pixel(15)).foregroundStyle(Theme.crustDark)
    }
}

struct Chip: View {
    var text: String
    var color: Color
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text).font(Theme.pixel(14))
                .foregroundStyle(selected ? Theme.cream : Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(selected ? color : Theme.paper)
                .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

struct OverviewPanel: View {
    @ObservedObject var model: GameModel
    @State private var filter: AgentStatus?

    var filtered: [AgentSession] {
        guard let filter else { return model.sessions }
        return model.sessions.filter { $0.status == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Chip(text: "Tous \(model.sessions.count)", color: Theme.base, selected: filter == nil) { filter = nil }
                Chip(text: "Attendent \(model.needsYou.count)", color: Theme.warning, selected: filter == .needsApproval) { filter = .needsApproval }
                Chip(text: "Au travail \(model.working.count)", color: Theme.success, selected: filter == .working) { filter = .working }
                Chip(text: "Finis \(model.finished.count)", color: Theme.muted, selected: filter == .finished) { filter = .finished }
                Spacer()
                Text("Sessions des 12 dernières heures · mise à jour toutes les 2 s").font(Theme.body(12)).foregroundStyle(Theme.ink.opacity(0.6))
            }
            if filtered.isEmpty {
                EmptyState(text: model.sessions.isEmpty ? "Aucun agent détecté. Lance Claude Code, Codex, Cursor ou Pi et ton premier robot arrivera." : "Rien dans cette catégorie.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                        ForEach(filtered) { session in
                            AgentTile(session: session)
                                .onTapGesture { model.open(.robot(session.id)) }
                        }
                    }
                    .padding(4)
                }
            }
        }
        .padding(20)
    }
}

struct AgentTile: View {
    var session: AgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PixelImage(image: Theme.robotImage(for: session.harness), size: 64)
                .background(Theme.color(for: session.harness).opacity(0.18))
                .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    StatusDot(status: session.status)
                    Text(session.status.label).font(Theme.pixel(14)).foregroundStyle(Theme.color(for: session.status).opacity(session.status == .finished ? 1 : 1))
                    Spacer()
                    Text(relative(session.updatedAt)).font(Theme.body(11)).foregroundStyle(Theme.ink.opacity(0.55))
                }
                Text(session.title).font(Theme.body(14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                HStack(spacing: 6) {
                    Text(session.harness.displayName).font(Theme.pixel(12)).foregroundStyle(Theme.cream)
                        .padding(.horizontal, 5).background(Theme.color(for: session.harness))
                    Text(session.projectName).font(Theme.body(12)).foregroundStyle(Theme.ink.opacity(0.7)).lineLimit(1)
                    Spacer()
                    if session.tokens.total > 0 {
                        Text(formatTokens(session.tokens.total) + " tk").font(Theme.mono(11)).foregroundStyle(Theme.ink.opacity(0.6))
                    }
                }
                if let pending = session.pendingAction, session.status == .needsApproval {
                    Text("⚠ " + pending).font(Theme.mono(11)).foregroundStyle(Theme.warning).lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(session.status == .needsApproval ? Theme.warning.opacity(0.12) : Theme.paper.opacity(0.55))
        .overlay(Rectangle().stroke(session.status == .needsApproval ? Theme.warning : Theme.ink, lineWidth: 2))
        .contentShape(Rectangle())
    }
}

struct EmptyState: View {
    var text: String
    var body: some View {
        VStack(spacing: 14) {
            PixelImage(image: Assets.image("tbfc/emotes/emotes_bulles_dodo.png"), size: 72)
            Text(text).font(Theme.pixel(18)).foregroundStyle(Theme.ink.opacity(0.7)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct RobotPanel: View {
    @ObservedObject var model: GameModel
    var sessionId: String
    @State private var messages: [TranscriptMessage] = []

    var body: some View {
        if let session = model.session(id: sessionId) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    PixelImage(image: Theme.robotImage(for: session.harness), size: 128)
                        .frame(maxWidth: .infinity)
                        .background(Theme.color(for: session.harness).opacity(0.15))
                        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
                    HStack { StatusDot(status: session.status); Text(session.status.label).font(Theme.pixel(16)).foregroundStyle(Theme.ink) }
                    Text(session.title).font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.ink)
                    info("Harnais", session.harness.displayName)
                    info("Projet", session.projectName)
                    info("Modèle", session.model ?? "—")
                    info("Démarré", relative(session.startedAt))
                    info("Activité", relative(session.updatedAt))
                    info("Prompts", "\(session.promptCount)")
                    info("Tokens", formatTokens(session.tokens.total))
                    if let pending = session.pendingAction {
                        Text("En attente : \(pending)").font(Theme.mono(11)).foregroundStyle(Theme.warning)
                    }
                    Spacer()
                    PixelButton(title: "Aller à la session") { model.focus(session) }
                    if !session.cwd.isEmpty {
                        PixelButton(title: "Ouvrir le dossier", color: Theme.paper) { NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd)) }
                    }
                    PixelButton(title: "Copier la reprise", color: Theme.paper) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SessionLauncher.resumeCommand(session), forType: .string)
                        model.showToast("Commande copiée")
                    }
                }
                .frame(width: 260)
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: "Journal de la conversation (local)")
                    if messages.isEmpty {
                        EmptyState(text: session.harness == .cursor ? "Cursor ne laisse pas lire ses conversations." : "Pas encore de message.")
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                                        MessageBubble(message: message).id(index)
                                    }
                                }
                                .padding(6)
                            }
                            .onAppear { proxy.scrollTo(messages.count - 1, anchor: .bottom) }
                        }
                    }
                }
            }
            .padding(20)
            .onAppear { messages = model.messages(for: session) }
        } else {
            EmptyState(text: "Ce robot est parti.")
        }
    }

    func info(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.pixel(13)).foregroundStyle(Theme.ink.opacity(0.6))
            Spacer()
            Text(value).font(Theme.body(12, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
        }
    }
}

struct MessageBubble: View {
    var message: TranscriptMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? "TOI" : "ROBOT").font(Theme.pixel(11)).foregroundStyle(Theme.ink.opacity(0.55))
                Text(message.text.count > 3000 ? String(message.text.prefix(3000)) + "…" : message.text)
                    .font(Theme.body(13)).foregroundStyle(Theme.ink).textSelection(.enabled)
            }
            .padding(10)
            .background(message.role == .user ? Theme.paper : Color.white.opacity(0.7))
            .overlay(Rectangle().stroke(Theme.ink.opacity(0.8), lineWidth: 2))
            if message.role != .user { Spacer(minLength: 80) }
        }
    }
}
