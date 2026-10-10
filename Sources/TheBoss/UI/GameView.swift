import SpriteKit
import SwiftUI

final class GameSKView: SKView {
    weak var model: GameModel?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let model else { return super.keyDown(with: event) }
        if !MainActor.assumeIsolated({ model.handleKey(event) }) {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        MainActor.assumeIsolated { model?.scene.handleKeyUp(event) }
    }

    override func flagsChanged(with event: NSEvent) {
        MainActor.assumeIsolated { model?.scene.handleFlags(event) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

struct GameView: NSViewRepresentable {
    @ObservedObject var model: GameModel

    func makeNSView(context: Context) -> GameSKView {
        let view = GameSKView()
        view.model = model
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.presentScene(model.scene)
        return view
    }

    func updateNSView(_ view: GameSKView, context: Context) {
        if model.panel == nil, view.window?.firstResponder !== view {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        if model.isInputBlocked { model.scene.releaseKeys() }
    }
}
