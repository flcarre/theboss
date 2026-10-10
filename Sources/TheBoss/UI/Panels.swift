import BossCore
import SwiftUI

struct PanelHost: View {
    @ObservedObject var model: GameModel
    var panel: Panel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PixelImage(image: icon, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.title(22)).foregroundStyle(Theme.cream)
                    Text(subtitle).font(Theme.label(13, .medium)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { model.closePanel() } label: {
                    HStack(spacing: 8) {
                        KeyCap(key: "esc")
                        PixelImage(image: Icon.close, size: 26)
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help(tr("Close"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.base)
            Rectangle().fill(Theme.crust).frame(height: 3)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cream)
                .environment(\.colorScheme, .light)
        }
        .padding(8)
        .background(ZStack { PixelRect(step: 4).fill(Theme.ink); PixelRect(step: 3).fill(Theme.crust).padding(4); PixelRect(step: 2).fill(Theme.ink).padding(6) })
        .frame(maxWidth: 1200, maxHeight: 840)
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
        case .overview: tr("Agent board")
        case .usage: tr("Boss computer")
        case .library: tr("Rules library")
        case .inbox: tr("Mail")
        case .analytics: tr("Whiteboard")
        case .settings: tr("Settings")
        case .domain: tr("Archives")
        case .robot(let id): model.session(id: id).map { RobotName.of($0) } ?? tr("Logbook")
        }
    }

    var subtitle: String {
        switch panel {
        case .overview: tr("Every agent session from the last 12 hours")
        case .usage: tr("Plan limits and token consumption")
        case .library: tr("The hidden files that drive your agents")
        case .inbox: tr("Suggested changes, with evidence and the exact diff")
        case .analytics: tr("Is your setup getting better?")
        case .settings: tr("Game, language and privacy")
        case .domain: tr("Local domain model, one per project")
        case .robot(let id): model.session(id: id).map { "\($0.harness.displayName) · \($0.projectName)" } ?? ""
        }
    }

    var icon: NSImage? {
        switch panel {
        case .overview: Icon.agents
        case .usage: Icon.usage
        case .library: Icon.rules
        case .inbox: Icon.mail
        case .analytics: Icon.stats
        case .settings: Icon.settings
        case .domain: Icon.domain
        case .robot: Icon.logbook
        }
    }
}

struct SectionTitle: View {
    var text: String

    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(Theme.crust).frame(width: 7, height: 7).rotationEffect(.degrees(45))
            Text(text.uppercased()).font(Theme.label(12, .heavy)).tracking(1.1).foregroundStyle(Theme.crustDark)
        }
    }
}

struct Chip: View {
    var text: String
    var count: Int?
    var color: Color
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(text).font(Theme.label(13, .bold))
                if let count {
                    Text("\(count)").font(Theme.label(12, .heavy)).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(selected ? Theme.cream.opacity(0.25) : Theme.ink.opacity(0.08))
                }
            }
            .foregroundStyle(selected ? Theme.cream : Theme.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(selected ? color : Theme.card)
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
            .background(Rectangle().fill(Theme.ink.opacity(selected ? 0 : 0.18)).offset(x: 2, y: 2))
        }
        .buttonStyle(.plain)
    }
}

struct TabItem: Identifiable {
    var id: String
    var title: String
    var count: Int
    var color: Color
}

struct SegmentedTabs: View {
    var items: [TabItem]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let selected = item.id == selection
                Button { selection = item.id } label: {
                    HStack(spacing: 6) {
                        Text(item.title).font(Theme.label(13, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                        Text("\(item.count)").font(Theme.label(12, .heavy)).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(selected ? Theme.cream.opacity(0.25) : Theme.ink.opacity(0.08))
                    }
                    .foregroundStyle(selected ? Theme.cream : Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(selected ? item.color : Theme.card)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < items.count - 1 { Rectangle().fill(Theme.ink).frame(width: 2) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
        .background(Rectangle().fill(Theme.ink.opacity(0.18)).offset(x: 2, y: 2))
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                SegmentedTabs(items: [
                    TabItem(id: "all", title: tr("All"), count: model.sessions.count, color: Theme.base),
                    TabItem(id: AgentStatus.needsApproval.rawValue, title: tr("Waiting"), count: model.needsYou.count, color: Theme.warning),
                    TabItem(id: AgentStatus.working.rawValue, title: tr("Working"), count: model.working.count, color: Theme.success),
                    TabItem(id: AgentStatus.finished.rawValue, title: tr("Done"), count: model.finished.count, color: Theme.muted),
                ], selection: Binding(get: { filter?.rawValue ?? "all" }, set: { filter = AgentStatus(rawValue: $0) }))
                .frame(maxWidth: 560)
                Spacer()
                Text(tr("Refreshed every 2 s")).font(Theme.label(12, .medium)).foregroundStyle(Theme.inkSoft.opacity(0.7))
            }
            if filtered.isEmpty {
                EmptyState(text: model.sessions.isEmpty
                           ? tr("No agent detected yet. Start Claude Code, Codex, Cursor or Pi and your first robot will show up.")
                           : tr("Nothing in this category."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                        ForEach(filtered) { session in
                            AgentTile(session: session)
                                .onTapGesture { model.open(.robot(session.id)) }
                        }
                    }
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                }
            }
        }
        .padding(22)
    }
}

struct AgentTile: View {
    static let height: CGFloat = 152
    var session: AgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PixelImage(image: Theme.robotImage(for: session.harness), size: 60)
                .padding(4)
                .background(Theme.color(for: session.harness).opacity(0.16))
                .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    StatusDot(status: session.status)
                    Text(session.status.label).font(Theme.label(13, .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(relative(session.updatedAt)).font(Theme.label(12, .medium)).foregroundStyle(Theme.inkSoft.opacity(0.7))
                }
                Text(session.title).font(Theme.label(15, .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 7) {
                    HarnessTag(harness: session.harness)
                    Text(session.projectName).font(Theme.label(12, .medium)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    if session.tokens.total > 0 {
                        ViewThatFits(in: .horizontal) {
                            tokenLabel(tr("%@ tokens", formatTokens(session.tokens.total)))
                            tokenLabel(formatTokens(session.tokens.total))
                        }
                    }
                }
                if let pending = session.pendingAction, session.status == .needsApproval {
                    Text(pending).font(Theme.mono(12)).foregroundStyle(Theme.ink).lineLimit(2)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warning.opacity(0.18))
                }
            }
        }
        .padding(14)
        .frame(height: AgentTile.height, alignment: .top)
        .card(fill: session.status == .needsApproval ? Color(hex: 0xFFF1E2) : Theme.card,
              border: session.status == .needsApproval ? Theme.warning : Theme.ink)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.color(for: session.status)).frame(width: 5).padding(.vertical, 2).padding(.leading, 2) }
        .contentShape(Rectangle())
    }

    func tokenLabel(_ text: String) -> some View {
        Text(text).font(Theme.label(12, .medium)).foregroundStyle(Theme.inkSoft.opacity(0.8)).lineLimit(1).fixedSize()
    }
}

struct HarnessTag: View {
    var harness: Harness

    var body: some View {
        Text(harness.displayName).font(Theme.label(11, .heavy)).foregroundStyle(Theme.cream)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.color(for: harness))
    }
}

struct EmptyState: View {
    var text: String

    var body: some View {
        VStack(spacing: 14) {
            PixelImage(image: Icon.sleeping, size: 72)
            Text(text).font(Theme.label(17, .semibold)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                .frame(maxWidth: 420)
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
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    PixelImage(image: Theme.robotImage(for: session.harness), size: 120)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.color(for: session.harness).opacity(0.14))
                        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
                    HStack(spacing: 7) {
                        StatusDot(status: session.status)
                        Text(session.status.label).font(Theme.label(15, .bold)).foregroundStyle(Theme.ink)
                    }
                    Text(session.title).font(Theme.label(16, .bold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 7) {
                        info(tr("Harness"), session.harness.displayName)
                        info(tr("Project"), session.projectName)
                        info(tr("Model"), session.model ?? "—")
                        info(tr("Started"), relative(session.startedAt))
                        info(tr("Last activity"), relative(session.updatedAt))
                        info(tr("Prompts"), "\(session.promptCount)")
                        info(tr("Tokens"), formatTokens(session.tokens.total))
                    }
                    .padding(12)
                    .card(lift: 0)
                    if let pending = session.pendingAction {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Waiting to run")).font(Theme.label(12, .heavy)).foregroundStyle(Theme.crustDark)
                            Text(pending).font(Theme.mono(12)).foregroundStyle(Theme.ink)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warning.opacity(0.18))
                    }
                    Spacer()
                    PixelButton(title: tr("Go to session")) { model.focus(session) }
                    HStack {
                        if !session.cwd.isEmpty {
                            PixelButton(title: tr("Open folder"), color: Theme.card) { NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd)) }
                        }
                        PixelButton(title: tr("Copy resume"), color: Theme.card) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SessionLauncher.resumeCommand(session), forType: .string)
                            model.showToast(tr("Command copied"))
                        }
                    }
                }
                .frame(width: 280)
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: tr("Conversation logbook"))
                    if messages.isEmpty {
                        EmptyState(text: session.harness == .cursor ? tr("Cursor does not let other apps read its conversations.") : tr("No message yet."))
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                                        MessageBubble(message: message, robot: RobotName.of(session)).id(index)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.trailing, 8)
                            }
                            .onAppear { proxy.scrollTo(messages.count - 1, anchor: .bottom) }
                        }
                    }
                }
            }
            .padding(22)
            .onAppear { messages = model.messages(for: session) }
        } else {
            EmptyState(text: tr("This robot has left."))
        }
    }

    func info(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.label(13, .medium)).foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(value).font(Theme.label(13, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
        }
    }
}

struct MessageBubble: View {
    var message: TranscriptMessage
    var robot: String

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 90) }
            VStack(alignment: .leading, spacing: 5) {
                Text(isUser ? tr("You") : robot).font(Theme.label(11, .heavy)).tracking(0.8).foregroundStyle(isUser ? Theme.crustDark : Theme.inkSoft)
                Text(message.text.count > 3000 ? String(message.text.prefix(3000)) + "…" : message.text)
                    .font(Theme.body(14)).foregroundStyle(Theme.ink).lineSpacing(2).textSelection(.enabled)
            }
            .padding(12)
            .card(fill: isUser ? Color(hex: 0xFFF3D6) : Theme.card, lift: 2)
            if !isUser { Spacer(minLength: 90) }
        }
    }
}
