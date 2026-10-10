import AppKit
import BossCore
import SwiftUI

enum MenuBarIcon {
    static let head = [
        ".....####.....",
        ".....####.....",
        "......##......",
        ".############.",
        "##############",
        "##..######..##",
        "##..######..##",
        "##############",
        "###........###",
        "##############",
        ".############.",
    ]

    static let bang = ["##", "##", "##", "##", "##", "##", "..", "##", "##"]

    static func image(alert: Bool) -> NSImage {
        let scale = 2
        let width = alert ? 19 : 14
        let height = 16
        var canvas = PixelCanvas(width: width * scale, height: height * scale)
        func plot(_ rows: [String], dx: Int, dy: Int) {
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    canvas.rect((dx + x) * scale, (dy + y) * scale, scale, scale, RGBA(0x000000))
                }
            }
        }
        plot(head, dx: 0, dy: 3)
        if alert { plot(bang, dx: 16, dy: 4) }
        let image = NSImage(cgImage: canvas.cgImage, size: NSSize(width: width, height: height))
        image.isTemplate = true
        return image
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let waiting = model.needsYou.count
        let working = model.working.count
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image(alert: waiting > 0))
            if waiting > 0 {
                Text("\(waiting)")
            } else if working > 0 {
                Text("\(working)")
            }
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var model: GameModel
    @Environment(\.openWindow) private var openWindow

    var recentDone: [AgentSession] { Array(model.finished.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.outline)
            VStack(alignment: .leading, spacing: 14) {
                if model.sessions.isEmpty {
                    Text(tr("No agent in sight.")).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 20)
                }
                section(tr("Needs you"), color: Theme.warning, sessions: model.needsYou)
                section(tr("Working"), color: Theme.success, sessions: Array(model.working.prefix(5)))
                section(tr("Recently done"), color: Theme.muted, sessions: recentDone)
            }
            .padding(14)
            usage
            footer
        }
        .frame(width: 360)
        .background(Theme.night)
    }

    var header: some View {
        HStack(spacing: 10) {
            PixelImage(image: Assets.trimmed("characters/boss/rotations/south.png"), size: 34)
                .padding(3)
                .background(Theme.base)
                .overlay(Rectangle().stroke(Theme.crust, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text("The Boss").font(Theme.title(17)).foregroundStyle(Theme.crust)
                Text(summary).font(Theme.label(12, .medium)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if !model.openSuggestions.isEmpty {
                Button {
                    show(.inbox)
                } label: {
                    HStack(spacing: 5) {
                        PixelImage(image: Icon.mail, size: 18)
                        Text("\(model.openSuggestions.count)").font(Theme.label(13, .heavy)).foregroundStyle(Theme.ink)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.crust)
                }
                .buttonStyle(.plain)
                .help(tr("Mail: suggestions to review (⌘2)"))
            }
        }
        .padding(14)
    }

    var summary: String {
        tr("%d waiting · %d working · %d done", model.needsYou.count, model.working.count, model.finished.count)
    }

    @ViewBuilder
    func section(_ title: String, color: Color, sessions: [AgentSession]) -> some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Rectangle().fill(color).frame(width: 8, height: 8)
                    Text(title.uppercased()).font(Theme.label(10, .heavy)).tracking(1).foregroundStyle(color)
                }
                ForEach(sessions) { session in
                    MenuSessionRow(session: session) { model.focus(session) }
                }
            }
        }
    }

    @ViewBuilder
    var usage: some View {
        let providers = (model.usage?.providers ?? []).filter { $0.state == .ok && !$0.windows.isEmpty }
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(providers, id: \.harness) { provider in
                    ForEach(provider.windows.prefix(2), id: \.label) { window in
                        HStack(spacing: 8) {
                            Rectangle().fill(Theme.color(for: provider.harness)).frame(width: 3, height: 14)
                            Text(provider.harness.displayName).font(Theme.label(12)).foregroundStyle(Theme.cream)
                                .frame(width: 86, alignment: .leading)
                            Text(window.label).font(Theme.label(11, .medium)).foregroundStyle(Theme.textSecondary)
                                .lineLimit(1).fixedSize()
                                .frame(minWidth: 44, alignment: .leading)
                            Gauge8(fraction: window.usedPercent / 100, color: gaugeColor(window.usedPercent)).frame(height: 12)
                            Text("\(Int(window.usedPercent.rounded())) %").font(Theme.label(12, .bold)).foregroundStyle(gaugeColor(window.usedPercent))
                                .monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(14)
            .background(Theme.base)
        }
    }

    var footer: some View {
        HStack(spacing: 10) {
            Button { show(nil) } label: {
                Text(tr("Open the office")).font(Theme.label(13, .bold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 8).background(Theme.crust)
            }
            .buttonStyle(.plain)
            Button { NSApp.terminate(nil) } label: {
                Text(tr("Quit")).font(Theme.label(13, .bold)).foregroundStyle(Theme.cream)
                    .padding(.horizontal, 16).padding(.vertical, 8).background(Theme.raised)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.night)
    }

    func show(_ panel: Panel?) {
        openWindow(id: "office")
        NSApp.activate(ignoringOtherApps: true)
        if let panel { model.open(panel) }
    }
}

struct MenuSessionRow: View {
    var session: AgentSession
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                PixelImage(image: Theme.robotIcon(for: session.harness), size: 28)
                    .padding(2)
                    .background(Theme.color(for: session.harness).opacity(0.2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(Theme.label(13, .semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                    Text("\(session.harness.displayName) · \(session.projectName)").font(Theme.label(11, .medium))
                        .foregroundStyle(Theme.textSecondary).lineLimit(1)
                    if session.status == .needsApproval, let pending = session.pendingAction {
                        Text(pending).font(Theme.mono(11)).foregroundStyle(Theme.warning).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Text(relative(session.updatedAt)).font(Theme.label(10, .medium)).foregroundStyle(Theme.textSecondary)
            }
            .padding(8)
            .background(hovering ? Theme.raised : Theme.base)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.color(for: session.status)).frame(width: 3) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tr("Go to session"))
    }
}
