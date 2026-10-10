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
                Button(tr("Agent board")) { model.open(.overview) }.keyboardShortcut("1")
                Button(tr("Mail")) { model.open(.inbox) }.keyboardShortcut("2")
                Button(tr("Usage")) { model.open(.usage) }.keyboardShortcut("3")
                Button(tr("Rules")) { model.open(.library) }.keyboardShortcut("4")
                Button(tr("Stats")) { model.open(.analytics) }.keyboardShortcut("5")
                Button(tr("Archives")) { model.open(.domain) }.keyboardShortcut("6")
                Button(tr("Settings")) { model.open(.settings) }.keyboardShortcut(",")
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
