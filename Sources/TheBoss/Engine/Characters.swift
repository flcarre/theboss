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
    private var walkingFacing: Facing?
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
            sprite.position.y = -4
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
        if let frames = walkFrames[facing], !frames.isEmpty, sprite.action(forKey: "walk") == nil || walkingFacing != facing {
            walkingFacing = facing
            sprite.position.y = -4 - (frames[0].size().height - 128) / 2
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

    func crackWhip(completion: @escaping () -> Void) {
        let frames = Assets.frames("characters/boss/whip/\(facing.rawValue)")
        sprite.removeAction(forKey: "walk")
        guard frames.count > 1 else {
            run(.sequence([.wait(forDuration: 0.15), .run(completion)]))
            return
        }
        let offset = (frames[0].size().height - 128) / 2
        sprite.position.y = -4 - offset
        sprite.run(.sequence([
            .animate(with: frames, timePerFrame: 0.055, resize: true, restore: false),
            .run { [weak self] in
                self?.sprite.position.y = -4
                self?.face(self?.facing ?? .south)
            },
        ]))
        run(.sequence([.wait(forDuration: 0.055 * Double(frames.count) * 0.6), .run(completion)]))
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
        case .gemini: "robot_gemini"
        case .copilot: "robot_copilot"
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
    private let plaque = DeskPlaque()
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
        plaque.position = CGPoint(x: 0, y: -2)
        plaque.zPosition = 60
        addChild(plaque)
        position = CGPoint(x: CGFloat(slot.centerX) * tileSize, y: CGFloat(slot.deskTile.r) * tileSize + 10 + RobotNode.standBehindDesk)
        zPosition = depth(forBaseY: CGFloat(slot.deskTile.r) * tileSize + 10) - 1
        update(session)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ session: AgentSession) {
        self.session = session
        plaque.show(project: session.projectName.isEmpty ? session.harness.displayName : session.projectName,
                    task: session.title, status: session.status)
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
        let texture = name == "exclamation" ? ProceduralArt.exclamation : ProceduralArt.sleeping
        emote.texture = texture
        emote.size = CGSize(width: texture.size().width * 2, height: texture.size().height * 2)
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
        plaque.setHighlighted(highlighted)
    }

    func whipped(boost: Bool) {
        sprite.run(.sequence([
            .moveBy(x: -5, y: 0, duration: 0.03), .moveBy(x: 10, y: 0, duration: 0.05),
            .moveBy(x: -9, y: 0, duration: 0.05), .moveBy(x: 4, y: 0, duration: 0.04),
        ]))
        sprite.run(.sequence([.colorize(with: .white, colorBlendFactor: 0.7, duration: 0.03), .colorize(withColorBlendFactor: RobotLook.tint(for: session.harness) == nil ? 0 : 0.45, duration: 0.2)]))
        let sweat = SKSpriteNode(texture: ProceduralArt.sweat)
        sweat.size = CGSize(width: sweat.size.width * 2, height: sweat.size.height * 2)
        sweat.anchorPoint = CGPoint(x: 0.5, y: 0)
        sweat.position = CGPoint(x: -38, y: 96)
        sweat.zPosition = 55
        addChild(sweat)
        sweat.run(.sequence([.moveBy(x: 0, y: 8, duration: 0.25), .wait(forDuration: 0.9), .fadeOut(withDuration: 0.3), .removeFromParent()]))
        guard boost, session.status == .working else { return }
        let folder = RobotLook.folder(for: session.harness)
        let frames = Assets.frames("characters/\(folder)/typing/south")
        guard frames.count > 1 else { return }
        sprite.removeAction(forKey: "typing")
        sprite.run(.sequence([
            .repeat(.animate(with: frames, timePerFrame: 0.04, resize: true, restore: false), count: 10),
            .run { [weak self] in self?.renderedStatus = nil; self?.resume() },
        ]), withKey: "frenzy")
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
        let frames = (0..<6).map { ProceduralArt.sparkle(frame: $0) }
        sparkle.position = CGPoint(x: 0, y: 60)
        sparkle.zPosition = 60
        addChild(sparkle)
        sparkle.run(.sequence([.animate(with: frames, timePerFrame: 0.07, resize: true, restore: false), .removeFromParent()]))
        run(.fadeIn(withDuration: 0.3))
    }

    func leave(completion: @escaping () -> Void) {
        let frames = (0..<6).map { ProceduralArt.smoke(frame: $0) }
        let puff = SKSpriteNode()
        puff.position = CGPoint(x: position.x, y: position.y + 50)
        puff.zPosition = zPosition + 1
        parent?.addChild(puff)
        puff.run(.sequence([.animate(with: frames, timePerFrame: 0.07, resize: true, restore: false), .removeFromParent()]))
        run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent(), .run(completion)]))
    }
}

final class DeskPlaque: SKNode {
    static let size = CGSize(width: 128, height: 32)
    private let background = SKSpriteNode()
    private let projectLabel = SKLabelNode()
    private let taskLabel = SKLabelNode()
    private var rendered: (String, String, AgentStatus)?

    override init() {
        super.init()
        addChild(background)
        for (label, weight, y) in [(projectLabel, NSFont.Weight.heavy, CGFloat(3)), (taskLabel, NSFont.Weight.semibold, CGFloat(-10))] {
            label.fontName = Theme.roundedFontName(size: 10, weight: weight)
            label.fontSize = 10
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .baseline
            label.position = CGPoint(x: -Self.size.width / 2 + 11, y: y)
            label.zPosition = 1
            addChild(label)
        }
        projectLabel.fontColor = NSColor(srgbRed: 0.96, green: 0.73, blue: 0.26, alpha: 1)
        taskLabel.fontColor = NSColor(srgbRed: 1, green: 0.965, blue: 0.925, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(project: String, task: String, status: AgentStatus) {
        if let rendered, rendered == (project, task, status) { return }
        rendered = (project, task, status)
        let texture = Self.plate(status: status)
        background.texture = texture
        background.size = texture.size()
        let width = Self.size.width - 18
        projectLabel.text = Self.fit(project.uppercased(), font: NSFont.systemFont(ofSize: 10, weight: .heavy), width: width)
        taskLabel.text = Self.fit(task, font: NSFont.systemFont(ofSize: 10, weight: .semibold), width: width)
    }

    func setHighlighted(_ highlighted: Bool) {
        run(.scale(to: highlighted ? 1.08 : 1, duration: 0.1))
    }

    static func fit(_ text: String, font: NSFont, width: CGFloat) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let line = text.singleLineTruncated(200)
        if (line as NSString).size(withAttributes: attributes).width <= width { return line }
        var count = line.count
        while count > 1 {
            count -= 1
            let candidate = String(line.prefix(count)).trimmingCharacters(in: .whitespaces) + "…"
            if (candidate as NSString).size(withAttributes: attributes).width <= width { return candidate }
        }
        return "…"
    }

    static func plate(status: AgentStatus) -> SKTexture {
        ProceduralArt.cached("plate-\(status.rawValue)") {
            let w = Int(size.width), h = Int(size.height)
            var c = PixelCanvas(width: w, height: h)
            c.rect(1, 0, w - 2, h, PixelArt.outline)
            c.rect(0, 1, w, h - 2, PixelArt.outline)
            c.rect(2, 2, w - 4, h - 4, RGBA(0x2B2547))
            c.rect(2, 2, w - 4, 1, RGBA(0x4E4580))
            c.rect(2, h - 3, w - 4, 1, RGBA(0x1E1A33))
            c.rect(3, 4, 3, h - 8, RGBA(RobotLook.color(for: status)))
            c.rect(3, 4, 3, 1, RGBA(0xFFF6EC, alpha: 160))
            return c
        }
    }
}
