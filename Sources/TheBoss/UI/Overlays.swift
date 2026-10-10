import BossCore
import SwiftUI

struct RootView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        ZStack {
            GameView(model: model)
            VStack {
                HStack(alignment: .top) {
                    StatusHUD(model: model)
                    Spacer()
                    UsageHUD(model: model)
                }
                Spacer()
                if model.dialog == nil && model.panel == nil {
                    HintBar(room: model.room, language: model.settings.language)
                }
            }
            .padding(14)
            if let toast = model.toast {
                VStack {
                    HStack(spacing: 10) {
                        PixelImage(image: Icon.bell, size: 20)
                        Text(toast).font(Theme.label(15)).foregroundStyle(Theme.cream)
                    }
                    .darkPixelFrame(padding: 14)
                    .padding(.top, 92)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
            if model.menuOpen {
                HStack {
                    Spacer()
                    StartMenu(model: model).padding(.trailing, 18).padding(.top, 90)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            if let dialog = model.dialog {
                VStack {
                    Spacer()
                    DialogBox(model: model, dialog: dialog).padding(18)
                }
            }
            if let panel = model.panel {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.closePanel() }
                PanelHost(model: model, panel: panel)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 28)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .environment(\.locale, model.settings.language.locale)
        .animation(.easeOut(duration: 0.12), value: model.panel)
        .animation(.easeOut(duration: 0.15), value: model.toast)
    }
}

struct StatusHUD: View {
    @ObservedObject var model: GameModel

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 16) {
                counter(model.needsYou.count, tr("waiting"), Theme.warning)
                counter(model.working.count, tr("working"), Theme.success)
                counter(model.finished.count, tr("done"), Theme.muted)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.open(.overview) }
            .help(tr("Agent board (⌘1)"))
            Rectangle().fill(Theme.outline).frame(width: 2, height: 22)
            Button {
                model.open(.inbox)
            } label: {
                HStack(spacing: 7) {
                    PixelImage(image: Icon.mail, size: 24)
                    Text("\(model.openSuggestions.count)").font(Theme.title(18))
                        .foregroundStyle(model.openSuggestions.isEmpty ? Theme.textSecondary : Theme.crust)
                }
            }
            .buttonStyle(.plain)
            .help(tr("Mail: suggestions to review (⌘2)"))
        }
        .frame(height: HUD.height)
        .darkPixelFrame(padding: 12)
    }

    func counter(_ value: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(color).frame(width: 12, height: 12).overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
            Text("\(value)").font(Theme.title(18)).foregroundStyle(Theme.cream)
            Text(label).font(Theme.label(13, .medium)).foregroundStyle(Theme.textSecondary)
        }
    }
}

enum HUD {
    static let height: CGFloat = 26
}

struct UsageHUD: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let providers = (model.usage?.providers ?? []).filter { $0.state == .ok && !$0.windows.isEmpty }
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(providers, id: \.harness) { provider in
                    if let window = provider.windows.first {
                        HStack(spacing: 8) {
                            Rectangle().fill(Theme.color(for: provider.harness)).frame(width: 4, height: 18)
                            Text(provider.harness.displayName).font(Theme.label(13)).foregroundStyle(Theme.cream)
                                .frame(width: 92, alignment: .leading)
                            Text(window.label).font(Theme.label(11, .medium)).foregroundStyle(Theme.textSecondary)
                                .frame(width: 40, alignment: .leading)
                            Gauge8(fraction: window.usedPercent / 100, color: gaugeColor(window.usedPercent))
                                .frame(width: 110, height: 14)
                            Text("\(Int(window.usedPercent.rounded())) %").font(Theme.label(13, .bold)).foregroundStyle(Theme.cream)
                                .monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            .darkPixelFrame(padding: 12)
            .contentShape(Rectangle())
            .onTapGesture { model.open(.usage) }
            .help(tr("Boss computer: usage (⌘3)"))
        }
    }
}

struct KeyCap: View {
    var key: String

    var body: some View {
        Text(key).font(Theme.label(12, .bold)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.paper)
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
            .background(Rectangle().fill(Theme.ink).offset(y: 2))
    }
}

struct HintBar: View {
    var room: RoomID
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 18) {
            hint("←↑↓→", tr("Walk"))
            hint("⇧", tr("Run"))
            hint(tr("Space"), tr("Talk"))
            hint("F", tr("Whip"))
            hint("esc", tr("Menu"))
            Spacer()
            Text(room == .office ? tr("Your office") : tr("Open space")).font(Theme.title(18)).foregroundStyle(Theme.crust)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.night.opacity(0.82))
        .overlay(Rectangle().fill(Theme.crust).frame(height: 2), alignment: .top)
    }

    func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 7) {
            KeyCap(key: key)
            Text(label).font(Theme.label(13, .medium)).foregroundStyle(Theme.cream.opacity(0.85))
        }
    }
}

struct DialogBox: View {
    @ObservedObject var model: GameModel
    var dialog: Dialog
    @State private var visible = 0
    @State private var blink = false
    private let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()

    private var text: String { dialog.pages[min(model.dialogPage, dialog.pages.count - 1)] }
    private var isLastPage: Bool { model.dialogPage >= dialog.pages.count - 1 }
    private var showsChoices: Bool { isLastPage && !dialog.choices.isEmpty && visible >= text.count }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
                if let portrait = dialog.portrait {
                    PixelImage(image: portrait, size: 92)
                        .padding(4)
                        .background(Theme.paper)
                        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 3))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(text.prefix(visible)))
                        .font(Theme.label(19, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                    HStack {
                        if dialog.pages.count > 1 {
                            Text("\(model.dialogPage + 1)/\(dialog.pages.count)").font(Theme.label(12, .medium)).foregroundStyle(Theme.inkSoft.opacity(0.7))
                        }
                        Spacer()
                        if visible >= text.count && !showsChoices {
                            Text("▼").font(Theme.label(16)).foregroundStyle(Theme.pink).opacity(blink ? 1 : 0.25)
                        }
                    }
                }
            if showsChoices {
                Rectangle().fill(Theme.ink.opacity(0.18)).frame(width: 2).padding(.vertical, -6)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(dialog.choices.enumerated()), id: \.element.id) { index, choice in
                        let selected = index == model.dialogChoice
                        HStack(spacing: 8) {
                            Text("▶").font(Theme.label(13)).foregroundStyle(Theme.pink).opacity(selected ? 1 : 0)
                            Text(choice.title).font(Theme.label(16, selected ? .bold : .medium)).foregroundStyle(Theme.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(selected ? Theme.paper : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.dialogChoice = index
                            model.advanceDialog()
                        }
                        .onHover { if $0 { model.dialogChoice = index } }
                    }
                }
                .frame(width: 240, alignment: .leading)
            }
        }
        .frame(minHeight: 112)
        .pixelFrame(padding: 24)
        .overlay(alignment: .topLeading) {
            if let speaker = dialog.speaker {
                Text(speaker).font(Theme.title(16)).foregroundStyle(Theme.cream)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.base)
                    .overlay(Rectangle().stroke(Theme.crust, lineWidth: 2))
                    .offset(x: 26, y: -14)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !showsChoices { tap() } }
        .onReceive(timer) { _ in
            if visible < text.count { visible += 2 } else { blink.toggle() }
        }
        .onChange(of: model.dialogPage) { visible = 0 }
        .onChange(of: dialog.id) { visible = 0 }
    }

    private func tap() {
        if visible < text.count { visible = text.count } else { model.advanceDialog() }
    }
}

struct StartMenu: View {
    @ObservedObject var model: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(MenuEntry.allCases.enumerated()), id: \.element) { index, entry in
                let selected = index == model.menuIndex
                HStack(spacing: 10) {
                    PixelImage(image: entry.icon, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title).font(Theme.label(17, .bold)).foregroundStyle(Theme.ink)
                        if selected {
                            Text(entry.subtitle).font(Theme.label(11, .medium)).foregroundStyle(Theme.inkSoft).lineLimit(1).fixedSize()
                        }
                    }
                    Spacer(minLength: 8)
                    badge(for: entry)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(selected ? Theme.paper : Color.clear)
                .overlay(alignment: .leading) {
                    if selected { Rectangle().fill(Theme.pink).frame(width: 4) }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.select(entry) }
                .onHover { if $0 { model.menuIndex = index } }
            }
        }
        .frame(minWidth: 280)
        .fixedSize()
        .pixelFrame(padding: 12)
    }

    @ViewBuilder
    func badge(for entry: MenuEntry) -> some View {
        switch entry {
        case .agents where !model.needsYou.isEmpty:
            Text("\(model.needsYou.count)").font(Theme.label(13, .bold)).foregroundStyle(Theme.cream).padding(.horizontal, 7).padding(.vertical, 1).background(Theme.warning)
        case .inbox where !model.openSuggestions.isEmpty:
            Text("\(model.openSuggestions.count)").font(Theme.label(13, .bold)).foregroundStyle(Theme.cream).padding(.horizontal, 7).padding(.vertical, 1).background(Theme.pink)
        default:
            EmptyView()
        }
    }
}
