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
                    HintBar(room: model.room)
                }
            }
            .padding(14)
            if let toast = model.toast {
                VStack {
                    Text(toast).font(Theme.pixel(15)).foregroundStyle(Theme.cream).darkPixelFrame(padding: 12)
                        .padding(.top, 86)
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
        .animation(.easeOut(duration: 0.12), value: model.panel)
        .animation(.easeOut(duration: 0.15), value: model.toast)
    }
}

struct StatusHUD: View {
    @ObservedObject var model: GameModel

    var body: some View {
        HStack(spacing: 14) {
            counter(model.needsYou.count, "attendent", Theme.warning)
            counter(model.working.count, "bossent", Theme.success)
            counter(model.finished.count, "finis", Theme.muted)
            Rectangle().fill(Theme.outline).frame(width: 2, height: 22)
            Button {
                model.open(.inbox)
            } label: {
                HStack(spacing: 6) {
                    PixelImage(image: Assets.image("tbfc/icons/icones_ecrans_messages.png"), size: 22)
                    Text("\(model.openSuggestions.count)").font(Theme.pixel(18)).foregroundStyle(model.openSuggestions.isEmpty ? Theme.textSecondary : Theme.crust)
                }
            }
            .buttonStyle(.plain)
            .help("Suggestions à relire")
        }
        .darkPixelFrame(padding: 12)
        .onTapGesture { model.open(.overview) }
    }

    func counter(_ value: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 12, height: 12).overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
            Text("\(value)").font(Theme.pixel(20)).foregroundStyle(Theme.cream)
            Text(label).font(Theme.pixel(13)).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct UsageHUD: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let providers = (model.usage?.providers ?? []).filter { $0.state == .ok && !$0.windows.isEmpty }
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(providers, id: \.harness) { provider in
                    if let window = provider.windows.first {
                        HStack(spacing: 8) {
                            Text(provider.harness.displayName).font(Theme.pixel(12)).foregroundStyle(Theme.textSecondary).frame(width: 84, alignment: .leading)
                            Gauge8(fraction: window.usedPercent / 100, color: gaugeColor(window.usedPercent))
                                .frame(width: 110, height: 14)
                            Text("\(Int(window.usedPercent))%").font(Theme.pixel(13)).foregroundStyle(Theme.cream).frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
            .darkPixelFrame(padding: 10)
            .onTapGesture { model.open(.usage) }
        }
    }
}

struct HintBar: View {
    var room: RoomID

    var body: some View {
        HStack(spacing: 18) {
            hint("←↑↓→", "Marcher")
            hint("⇧", "Courir")
            hint("Espace", "Parler")
            hint("Échap", "Menu")
            Spacer()
            Text(room == .office ? "TON BUREAU" : "OPEN SPACE").font(Theme.pixel(14)).foregroundStyle(Theme.crust)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.night.opacity(0.75))
    }

    func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key).font(Theme.pixel(12)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.paper)
            Text(label).font(Theme.pixel(12)).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct DialogBox: View {
    @ObservedObject var model: GameModel
    var dialog: Dialog
    @State private var visible = 0
    @State private var blink = false
    private let timer = Timer.publish(every: 0.018, on: .main, in: .common).autoconnect()

    private var text: String { dialog.pages[min(model.dialogPage, dialog.pages.count - 1)] }
    private var isLastPage: Bool { model.dialogPage >= dialog.pages.count - 1 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                if let portrait = dialog.portrait {
                    PixelImage(image: portrait, size: 96)
                        .background(Theme.paper)
                        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 3))
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let speaker = dialog.speaker {
                        Text(speaker).font(Theme.pixel(16)).foregroundStyle(Theme.crustDark)
                    }
                    Text(String(text.prefix(visible)))
                        .font(Theme.pixel(21))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                    HStack {
                        Spacer()
                        if visible >= text.count && (!isLastPage || dialog.choices.isEmpty) {
                            Text("▼").font(Theme.pixel(16)).foregroundStyle(Theme.pink).opacity(blink ? 1 : 0.2)
                        }
                    }
                }
            }
            .pixelFrame(padding: 22)
            .contentShape(Rectangle())
            .onTapGesture { tap() }

            if isLastPage && !dialog.choices.isEmpty && visible >= text.count {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(dialog.choices.enumerated()), id: \.element.id) { index, choice in
                        HStack(spacing: 6) {
                            Text("▶").font(Theme.pixel(14)).foregroundStyle(Theme.pink).opacity(index == model.dialogChoice ? 1 : 0)
                            Text(choice.title).font(Theme.pixel(17)).foregroundStyle(Theme.ink)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.dialogChoice = index
                            model.advanceDialog()
                        }
                        .onHover { if $0 { model.dialogChoice = index } }
                    }
                }
                .frame(minWidth: 210, alignment: .leading)
                .pixelFrame(padding: 18)
            }
        }
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
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(MenuEntry.allCases.enumerated()), id: \.element) { index, entry in
                HStack(spacing: 8) {
                    Text("▶").font(Theme.pixel(14)).foregroundStyle(Theme.pink).opacity(index == model.menuIndex ? 1 : 0)
                    PixelImage(image: Assets.image(entry.icon), size: 26)
                    Text(entry.rawValue.uppercased()).font(Theme.pixel(18)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    badge(for: entry)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture { model.select(entry) }
                .onHover { if $0 { model.menuIndex = index } }
            }
        }
        .frame(width: 230)
        .pixelFrame(padding: 18)
    }

    @ViewBuilder
    func badge(for entry: MenuEntry) -> some View {
        switch entry {
        case .agents where !model.needsYou.isEmpty:
            Text("\(model.needsYou.count)").font(Theme.pixel(13)).foregroundStyle(Theme.cream).padding(.horizontal, 6).background(Theme.warning)
        case .inbox where !model.openSuggestions.isEmpty:
            Text("\(model.openSuggestions.count)").font(Theme.pixel(13)).foregroundStyle(Theme.cream).padding(.horizontal, 6).background(Theme.pink)
        default:
            EmptyView()
        }
    }
}
