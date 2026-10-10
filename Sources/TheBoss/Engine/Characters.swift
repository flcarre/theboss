import BossCore
import SpriteKit

let tileSize: CGFloat = 64

func position(of tile: Tile) -> CGPoint {
    CGPoint(x: CGFloat(tile.c) * tileSize + tileSize / 2, y: CGFloat(tile.r) * tileSize)
}

func depth(forBaseY y: CGFloat) -> CGFloat { 10_000 - y }

final class PlayerNode: SKNode {
    private let sprite = SKSpriteNode()
    private let shadow = SKSpriteNode(texture: PixelArt.shadow(width: 44, height: 12))
    private var walkFrames: [Facing: [SKTexture]] = [:]
    private var idle: [Facing: SKTexture] = [:]
    private(set) var facing: Facing = .south
    private(set) var isMoving = false
    var tile = Tile(c: 0, r: 0)

    override init() {
        super.init()
        for facing in Facing.allCases {
            idle[facing] = Assets.texture("characters/boss/rotations/\(facing.rawValue).png")
            walkFrames[facing] = Assets.frames("characters/boss/walk/\(facing.rawValue)")
        }
        shadow.position = CGPoint(x: 0, y: 6)
        shadow.zPosition = -1
        addChild(shadow)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.position = CGPoint(x: 0, y: -4)
        addChild(sprite)
        face(.south)
    }

    required init?(coder: NSCoder) { fatalError() }

    func face(_ facing: Facing) {
        self.facing = facing
        if !isMoving, let texture = idle[facing] {
            sprite.texture = texture
            sprite.size = texture.size()
        }
    }

    func place(at tile: Tile) {
        self.tile = tile
        position = TheBoss.position(of: tile)
        zPosition = depth(forBaseY: position.y)
    }

    func walk(to tile: Tile, duration: TimeInterval, completion: @escaping () -> Void) {
        isMoving = true
        self.tile = tile
        let target = TheBoss.position(of: tile)
        if let frames = walkFrames[facing], !frames.isEmpty, sprite.action(forKey: "walk") == nil {
            sprite.run(.repeatForever(.animate(with: frames, timePerFrame: 0.075, resize: true, restore: false)), withKey: "walk")
        }
        let move = SKAction.customAction(withDuration: duration) { [weak self] node, elapsed in
            guard let self else { return }
            let start = node.userData?["start"] as? CGPoint ?? node.position
            let t = CGFloat(elapsed / CGFloat(duration))
            let x = (start.x + (target.x - start.x) * t).rounded()
            let y = (start.y + (target.y - start.y) * t).rounded()
            node.position = CGPoint(x: x, y: y)
            self.zPosition = depth(forBaseY: y)
        }
        userData = ["start": position]
        run(.sequence([move, .run { [weak self] in
            guard let self else { return }
            self.position = target
            self.zPosition = depth(forBaseY: target.y)
            self.isMoving = false
            completion()
        }]))
    }

    func stopWalking() {
        sprite.removeAction(forKey: "walk")
        face(facing)
    }
}

enum RobotLook {
    static func folder(for harness: Harness) -> String {
        switch harness {
        case .claude, .pi: "robot_claude"
        case .codex, .omp: "robot_codex"
        case .cursor: "robot_cursor"
        }
    }

    static func tint(for harness: Harness) -> NSColor? {
        switch harness {
        case .pi: NSColor(srgbRed: 0.55, green: 0.42, blue: 0.95, alpha: 1)
        case .omp: NSColor(srgbRed: 0.35, green: 0.85, blue: 0.45, alpha: 1)
        default: nil
        }
    }

    static func color(for status: AgentStatus) -> UInt32 {
        switch status {
        case .working: 0x4CD18A
        case .needsApproval: 0xFF9A2E
        case .finished: 0xA8B0BD
        }
    }
}

final class RobotNode: SKNode {
    static let standBehindDesk: CGFloat = 10
    let slot: DeskSlot
    private(set) var session: AgentSession
    private let sprite = SKSpriteNode()
    private let emote = SKSpriteNode()
    private let light = SKSpriteNode()
    private let glow = SKSpriteNode(texture: PixelArt.glow(width: 48, height: 22, color: 0x7FD8FF))
    private let nameplate = SKLabelNode()
    private var renderedStatus: AgentStatus?

    init(session: AgentSession, slot: DeskSlot) {
        self.session = session
        self.slot = slot
        super.init()
        let folder = RobotLook.folder(for: session.harness)
        let rest = Assets.texture("characters/\(folder)/rotations/south.png")
        sprite.texture = rest
        sprite.size = rest.size()
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.position = .zero
        if let tint = RobotLook.tint(for: session.harness) {
            sprite.color = tint
            sprite.colorBlendFactor = 0.45
        }
        addChild(sprite)
        glow.position = CGPoint(x: -22, y: 30)
        glow.zPosition = 30
        glow.blendMode = .add
        addChild(glow)
        emote.anchorPoint = CGPoint(x: 0.5, y: 0)
        emote.position = CGPoint(x: 40, y: 96)
        emote.zPosition = 50
        addChild(emote)
        light.texture = nil
        light.position = CGPoint(x: -34, y: 100)
        light.zPosition = 51
        addChild(light)
        nameplate.fontName = Theme.pixelFontName
        nameplate.fontSize = 13
        nameplate.fontColor = NSColor(srgbRed: 1, green: 0.965, blue: 0.925, alpha: 1)
        nameplate.position = CGPoint(x: 0, y: 124)
        nameplate.zPosition = 52
        nameplate.alpha = 0
        addChild(nameplate)
        position = CGPoint(x: CGFloat(slot.centerX) * tileSize, y: CGFloat(slot.deskTile.r) * tileSize + 10 + RobotNode.standBehindDesk)
        zPosition = depth(forBaseY: CGFloat(slot.deskTile.r) * tileSize + 10) - 1
        update(session)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ session: AgentSession) {
        self.session = session
        nameplate.text = session.projectName.isEmpty ? session.harness.displayName : session.projectName
        guard renderedStatus != session.status else { return }
        renderedStatus = session.status
        let folder = RobotLook.folder(for: session.harness)
        sprite.removeAllActions()
        emote.removeAllActions()
        sprite.position = .zero
        let lightTexture = PixelArt.statusLight(RobotLook.color(for: session.status))
        light.texture = lightTexture
        light.size = lightTexture.size()
        switch session.status {
        case .working:
            let frames = Assets.frames("characters/\(folder)/typing/south")
            if frames.count > 1 {
                sprite.position.y = -(frames[0].size().height - 128) / 2
                sprite.run(.repeatForever(.animate(with: frames, timePerFrame: 0.09, resize: true, restore: false)))
            } else {
                sprite.run(.repeatForever(.sequence([.moveBy(x: 0, y: 2, duration: 0.12), .moveBy(x: 0, y: -2, duration: 0.12)])))
            }
            glow.isHidden = false
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.4), .fadeAlpha(to: 1, duration: 0.4)])))
            emote.isHidden = true
        case .needsApproval:
            let frames = Assets.frames("characters/\(folder)/alert/south")
            if frames.count > 1 {
                sprite.position.y = -(frames[0].size().height - 128) / 2
                sprite.run(.repeatForever(.sequence([.animate(with: frames, timePerFrame: 0.1, resize: true, restore: false), .wait(forDuration: 0.6)])))
            } else {
                sprite.run(.repeatForever(.sequence([.moveBy(x: 0, y: 6, duration: 0.1), .moveBy(x: 0, y: -6, duration: 0.1), .wait(forDuration: 0.5)])))
            }
            glow.isHidden = true
            show(emote: "exclamation", bounce: true)
        case .finished:
            let rest = Assets.texture("characters/\(folder)/rotations/south.png")
            sprite.texture = rest
            sprite.size = rest.size()
            sprite.run(.repeatForever(.sequence([.wait(forDuration: 1.2), .moveBy(x: 0, y: -1, duration: 0), .wait(forDuration: 1.2), .moveBy(x: 0, y: 1, duration: 0)])))
            glow.isHidden = true
            show(emote: "dodo", bounce: false)
        }
    }

    private func show(emote name: String, bounce: Bool) {
        let texture = Assets.texture("tbfc/emotes/emotes_bulles_\(name).png")
        emote.texture = texture
        emote.size = CGSize(width: texture.size().width * 0.5, height: texture.size().height * 0.5)
        emote.isHidden = false
        emote.position = CGPoint(x: 40, y: 96)
        if bounce {
            emote.run(.repeatForever(.sequence([.moveBy(x: 0, y: 6, duration: 0.18), .moveBy(x: 0, y: -6, duration: 0.18), .wait(forDuration: 0.3)])))
        } else {
            emote.alpha = 0
            emote.run(.repeatForever(.sequence([.wait(forDuration: 2.5), .fadeIn(withDuration: 0.2), .wait(forDuration: 2), .fadeOut(withDuration: 0.3)])))
        }
    }

    func setHighlighted(_ highlighted: Bool) {
        nameplate.run(.fadeAlpha(to: highlighted ? 1 : 0, duration: 0.12))
    }

    func turn(toward facing: Facing) {
        let folder = RobotLook.folder(for: session.harness)
        sprite.removeAllActions()
        sprite.position = .zero
        let texture = Assets.texture("characters/\(folder)/rotations/\(facing.rawValue).png")
        sprite.texture = texture
        sprite.size = texture.size()
        renderedStatus = nil
    }

    func resume() { update(session) }

    func appear() {
        alpha = 0
        let sparkle = SKSpriteNode()
        let frames = (1...6).map { Assets.texture("tbfc/fx/effets_1_scintillement_\($0).png") }
        sparkle.position = CGPoint(x: 0, y: 60)
        sparkle.zPosition = 60
        addChild(sparkle)
        sparkle.run(.sequence([.animate(with: frames, timePerFrame: 0.07, resize: true, restore: false), .removeFromParent()]))
        run(.fadeIn(withDuration: 0.3))
    }

    func leave(completion: @escaping () -> Void) {
        let frames = (1...6).map { Assets.texture("tbfc/fx/effets_1_fumee_\($0).png") }
        let puff = SKSpriteNode()
        puff.position = CGPoint(x: position.x, y: position.y + 50)
        puff.zPosition = zPosition + 1
        parent?.addChild(puff)
        puff.run(.sequence([.animate(with: frames, timePerFrame: 0.07, resize: true, restore: false), .removeFromParent()]))
        run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent(), .run(completion)]))
    }
}
