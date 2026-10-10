import AppKit
import BossCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let icon = Assets.image("AppIcon.png") { NSApp.applicationIconImage = icon }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct TheBossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: GameModel

    init() {
        Theme.registerFonts()
        _model = StateObject(wrappedValue: GameModel())
    }

    var body: some Scene {
        Window("The Boss", id: "office") {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    model.start()
                    DebugDriver.runIfRequested(model: model)
                }
        }
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Écran des agents") { model.open(.overview) }.keyboardShortcut("1")
                Button("Courrier") { model.open(.inbox) }.keyboardShortcut("2")
                Button("Usage") { model.open(.usage) }.keyboardShortcut("3")
                Button("Règles") { model.open(.library) }.keyboardShortcut("4")
                Button("Stats") { model.open(.analytics) }.keyboardShortcut("5")
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: GameModel

    var body: some View {
        if model.needsYou.isEmpty {
            Text("◉ \(model.working.count)")
        } else {
            Text("⚠ \(model.needsYou.count) · ◉ \(model.working.count)")
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var model: GameModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE BOSS").font(Theme.pixel(18)).foregroundStyle(Theme.crust)
            if model.sessions.isEmpty {
                Text("Aucun agent en vue.").font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
            }
            ForEach(model.sessions.prefix(8)) { session in
                Button {
                    model.focus(session)
                } label: {
                    HStack(spacing: 8) {
                        StatusDot(status: session.status)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.title).font(Theme.body(12, weight: .semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                            Text("\(session.harness.displayName) · \(session.projectName) · \(session.status.label)")
                                .font(Theme.body(10)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            if let providers = model.usage?.providers.filter({ $0.state == .ok }), !providers.isEmpty {
                Rectangle().fill(Theme.outline).frame(height: 2)
                ForEach(providers, id: \.harness) { provider in
                    ForEach(provider.windows.prefix(2), id: \.label) { window in
                        HStack {
                            Text("\(provider.harness.displayName) · \(window.label)").font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(Int(window.usedPercent)) %").font(Theme.pixel(13)).foregroundStyle(gaugeColor(window.usedPercent))
                        }
                    }
                }
            }
            Rectangle().fill(Theme.outline).frame(height: 2)
            HStack {
                Button("Ouvrir le bureau") {
                    openWindow(id: "office")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }
            }
            .font(Theme.pixel(13))
        }
        .padding(14)
        .frame(width: 330)
        .background(Theme.base)
    }
}
