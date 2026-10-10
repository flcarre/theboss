import AppKit
import BossCore
import SwiftUI

enum Theme {
    static let ink = Color(hex: 0x2A1840)
    static let night = Color(hex: 0x1E1A33)
    static let base = Color(hex: 0x2B2547)
    static let raised = Color(hex: 0x3A3260)
    static let outline = Color(hex: 0x4E4580)
    static let cream = Color(hex: 0xFFF6EC)
    static let paper = Color(hex: 0xFCE7B0)
    static let crust = Color(hex: 0xF5B942)
    static let crustDark = Color(hex: 0xC9832A)
    static let pink = Color(hex: 0xFF6B9A)
    static let textSecondary = Color(hex: 0xB9B0D6)
    static let success = Color(hex: 0x4CD18A)
    static let warning = Color(hex: 0xFF9A2E)
    static let danger = Color(hex: 0xFF5A5A)
    static let info = Color(hex: 0x4FB3FF)
    static let muted = Color(hex: 0xA8B0BD)

    static let inkSoft = Color(hex: 0x4A3D66)
    static let card = Color(hex: 0xFFFDF8)
    static let line = Color(hex: 0x2A1840, alpha: 0.14)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
    static func label(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded) }
    static func body(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .rounded) }

    static func roundedFontName(size: CGFloat, weight: NSFont.Weight) -> String {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) }
        return (rounded ?? base).fontName
    }
    static func mono(_ size: CGFloat = 12) -> Font { .system(size: size, design: .monospaced) }

    static func color(for status: AgentStatus) -> Color {
        switch status {
        case .working: success
        case .needsApproval: warning
        case .finished: muted
        }
    }

    static func color(for harness: Harness) -> Color {
        switch harness {
        case .claude: Color(hex: 0xD9773F)
        case .codex: Color(hex: 0x3FBFA8)
        case .gemini: Color(hex: 0x4F7BD9)
        case .copilot: Color(hex: 0x8A63D2)
        case .cursor: Color(hex: 0x9AA3AD)
        case .pi: Color(hex: 0x8C6BF2)
        case .omp: Color(hex: 0x5BD16E)
        }
    }

    static func robotImage(for harness: Harness) -> NSImage? {
        Assets.image("characters/\(RobotLook.folder(for: harness))/rotations/south.png")
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

struct PixelFrame: ViewModifier {
    var fill: Color = Theme.cream
    var border: Color = Theme.ink
    var accent: Color = Theme.crust
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    PixelRect(step: 4).fill(border)
                    PixelRect(step: 4).fill(accent).padding(4)
                    PixelRect(step: 3).fill(border).padding(7)
                    PixelRect(step: 2).fill(fill).padding(9)
                }
            )
    }
}

struct PixelRect: Shape {
    var step: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = step
        path.move(to: CGPoint(x: rect.minX + s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + s))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - s))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + s))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s))
        path.closeSubpath()
        return path
    }
}

struct CardStyle: ViewModifier {
    var fill: Color
    var border: Color
    var lift: CGFloat

    func body(content: Content) -> some View {
        content
            .background(fill)
            .overlay(Rectangle().stroke(border, lineWidth: 2))
            .background(Rectangle().fill(Theme.ink.opacity(0.18)).offset(x: lift, y: lift))
    }
}

extension View {
    func card(fill: Color = Theme.card, border: Color = Theme.ink, lift: CGFloat = 3) -> some View {
        modifier(CardStyle(fill: fill, border: border, lift: lift))
    }

    func pixelFrame(fill: Color = Theme.cream, accent: Color = Theme.crust, padding: CGFloat = 14) -> some View {
        modifier(PixelFrame(fill: fill, accent: accent, padding: padding))
    }

    func darkPixelFrame(padding: CGFloat = 12) -> some View {
        modifier(PixelFrame(fill: Theme.base, border: Theme.ink, accent: Theme.crust, padding: padding))
    }
}

struct PixelImage: View {
    var image: NSImage?
    var size: CGFloat

    var body: some View {
        if let image {
            Image(nsImage: image).interpolation(.none).resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

struct PixelButton: View {
    var title: String
    var color: Color = Theme.crust
    var textColor: Color = Theme.ink
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.label(14, .bold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        PixelRect(step: 3).fill(Theme.ink)
                        PixelRect(step: 2).fill(color).padding(3)
                        Rectangle().fill(Color.white.opacity(0.25)).frame(height: 2).padding(.horizontal, 6).frame(maxHeight: .infinity, alignment: .top).padding(.top, 5)
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

struct StatusDot: View {
    var status: AgentStatus

    var body: some View {
        Rectangle().fill(Theme.color(for: status)).frame(width: 11, height: 11)
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
    }
}

struct Gauge8: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            let segments = 20
            let filled = Int((min(max(fraction, 0), 1) * Double(segments)).rounded())
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { index in
                    Rectangle().fill(index < filled ? color : Theme.ink.opacity(0.18))
                }
            }
            .padding(3)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Rectangle().stroke(Theme.ink, lineWidth: 2))
        }
    }
}

enum Icon {
    static var agents: NSImage? { Assets.trimmed("icons/agents.png") }
    static var mail: NSImage? { Assets.trimmed("icons/mail.png") }
    static var usage: NSImage? { Assets.trimmed("icons/usage.png") }
    static var rules: NSImage? { Assets.trimmed("icons/rules.png") }
    static var stats: NSImage? { Assets.trimmed("icons/stats.png") }
    static var settings: NSImage? { Assets.trimmed("icons/settings.png") }
    static var domain: NSImage? { Assets.trimmed("icons/domain.png") }
    static var logbook: NSImage? { Assets.trimmed("icons/logbook.png") }
    static var back: NSImage? { ProceduralArt.backIcon }
    static var close: NSImage? { ProceduralArt.closeIcon }
    static var search: NSImage? { ProceduralArt.searchIcon }
    static var bell: NSImage? { ProceduralArt.bellIcon }
    static var sleeping: NSImage? { ProceduralArt.image("sleepBubble", scale: 3) { ProceduralArt.bubble(["......#####", ".........#.", "........#..", ".......####", "####.......", "..#........", ".#.........", "####......."], color: 0x4F7BD9) } }
}

func gaugeColor(_ percent: Double) -> Color {
    percent >= 90 ? Theme.danger : percent >= 70 ? Theme.warning : Theme.success
}

func formatTokens(_ value: Int) -> String {
    switch value {
    case 1_000_000_000...: String(format: "%.1f G", Double(value) / 1_000_000_000)
    case 1_000_000...: String(format: "%.1f M", Double(value) / 1_000_000)
    case 1_000...: String(format: "%.1f k", Double(value) / 1_000)
    default: "\(value)"
    }
}

func relative(_ date: Date?) -> String {
    guard let date else { return "—" }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Localizer.language.locale
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}
