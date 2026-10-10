import AppKit
import BossCore
import SpriteKit
import SwiftUI

@MainActor
enum DebugDriver {
    static func runIfRequested(model: GameModel) {
        guard let script = ProcessInfo.processInfo.environment["BOSS_SCRIPT"] else { return }
        let outDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BOSS_SNAP_DIR"] ?? NSTemporaryDirectory())
        let steps = script.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for step in steps {
                let parts = step.split(separator: ":").map(String.init)
                switch parts.first {
                case "wait":
                    let seconds = Double(parts[safe: 1] ?? "1") ?? 1
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                case "hold":
                    let code = UInt16(parts[safe: 1] ?? "0") ?? 0
                    let seconds = Double(parts[safe: 2] ?? "0.3") ?? 0.3
                    send(code, down: true, model: model)
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    send(code, down: false, model: model)
                    try? await Task.sleep(nanoseconds: 350_000_000)
                case "tap":
                    let code = UInt16(parts[safe: 1] ?? "49") ?? 49
                    send(code, down: true, model: model)
                    send(code, down: false, model: model)
                    try? await Task.sleep(nanoseconds: 250_000_000)
                case "panel":
                    switch parts[safe: 1] {
                    case "usage": model.open(.usage)
                    case "library": model.open(.library)
                    case "inbox": model.open(.inbox)
                    case "analytics": model.open(.analytics)
                    case "overview": model.open(.overview)
                    case "settings": model.open(.settings)
                    case "domain": model.open(.domain)
                    case "robot": if let first = model.sessions.first { model.open(.robot(first.id)) }
                    default: model.closePanel()
                    }
                case "room":
                    if parts[safe: 1] == "openSpace" {
                        model.scene.build(.openSpace, spawn: Tile(c: 9, r: 0), facing: .north)
                    } else {
                        model.scene.build(.office, spawn: Tile(c: 6, r: 1), facing: .north)
                    }
                case "snap":
                    snapshot(name: parts[safe: 1] ?? "snap", to: outDir)
                case "apply":
                    let title = parts.dropFirst().joined(separator: ":")
                    if let target = model.openSuggestions.first(where: { $0.title.contains(title) }) { model.setStatus(.applied, for: target) }
                case "lang":
                    model.settings.language = AppLanguage(rawValue: parts[safe: 1] ?? "en") ?? .english
                    model.saveSettings()
                case "repair":
                    model.repairClaudeUsage()
                case "refine":
                    if let first = model.openSuggestions.first(where: { $0.kind == .learnedRule }) { model.refine(first) }
                case "zoom":
                    model.scene.setZoom(CGFloat(Double(parts[safe: 1] ?? "1") ?? 1))
                case "snapmenu":
                    let renderer = ImageRenderer(content: MenuBarContent(model: model).environment(\.colorScheme, .dark))
                    renderer.scale = 2
                    if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent("menu.png"))
                    }
                    for alert in [false, true] {
                        let icon = MenuBarIcon.image(alert: alert)
                        if let tiff = icon.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                            try? bitmap.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent("menuicon-\(alert).png"))
                        }
                    }
                case "quit":
                    NSApp.terminate(nil)
                default:
                    break
                }
            }
        }
    }

    static func send(_ code: UInt16, down: Bool, model: GameModel) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let event = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ",
                                           isARepeat: false, keyCode: code) else { return }
        if down {
            _ = model.handleKey(event)
        } else {
            model.scene.handleKeyUp(event)
        }
    }

    static func snapshot(name: String, to dir: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let content = window.contentView,
              let skView = findSKView(in: content),
              let scene = skView.scene else { return }
        let scale = window.backingScaleFactor
        let size = content.bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        if let camera = scene.camera {
            let visible = CGRect(x: camera.position.x - scene.size.width * camera.xScale / 2,
                                 y: camera.position.y - scene.size.height * camera.yScale / 2,
                                 width: scene.size.width * camera.xScale, height: scene.size.height * camera.yScale)
            if let texture = skView.texture(from: scene, crop: visible) {
                let cg = texture.cgImage()
                let frame = skView.convert(skView.bounds, to: content)
                NSGraphicsContext.current?.imageInterpolation = .none
                NSImage(cgImage: cg, size: frame.size).draw(in: frame)
            }
        }
        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: rep)
            let overlay = NSImage(size: size)
            overlay.addRepresentation(rep)
            overlay.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
        _ = scale
    }

    static func findSKView(in view: NSView) -> SKView? {
        if let sk = view as? SKView { return sk }
        for sub in view.subviews { if let found = findSKView(in: sub) { return found } }
        return nil
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
