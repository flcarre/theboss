import BossCore
import SpriteKit

@MainActor
protocol WorldSceneDelegate: AnyObject {
    var isInputBlocked: Bool { get }
    func world(didInteract interaction: Interaction, session: AgentSession?)
    func world(didWhip session: AgentSession?)
    func worldDidRequestMenu()
    func world(didEnter room: RoomID)
}

final class WorldScene: SKScene {
    weak var controller: WorldSceneDelegate?
    private(set) var room: Room = .office
    private let world = SKNode()
    private let cameraNode = SKCameraNode()
    private let fader = SKSpriteNode(color: .black, size: CGSize(width: 4000, height: 4000))
    private let player = PlayerNode()
    private var robots: [String: RobotNode] = [:]
    private var slots: [String: Int] = [:]
    private var floorSessions: [AgentSession] = []
    private var heldKeys: [Facing] = []
    private var running = false
    private var transitioning = false
    private var inboxBadge = SKSpriteNode()
    private var inboxCount = 0
    private var highlighted: RobotNode?
    private var talkingRobot: RobotNode?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = NSColor(srgbRed: 0.078, green: 0.067, blue: 0.149, alpha: 1)
        addChild(world)
        addChild(cameraNode)
        camera = cameraNode
        fader.zPosition = 100_000
        fader.alpha = 0
        cameraNode.addChild(fader)
        build(.office, spawn: Tile(c: 6, r: 1), facing: .north)
    }

    required init?(coder: NSCoder) { fatalError() }

    func build(_ id: RoomID, spawn: Tile, facing: Facing) {
        world.removeAllChildren()
        robots.removeAll()
        highlighted = nil
        room = Room.room(id)
        let floor = SKNode()
        floor.zPosition = -1000
        world.addChild(floor)
        for c in 0..<room.cols {
            for r in 0..<room.walkRows {
                let variant = (c * 73 + r * 151 + c * r * 7) % 97 % 4
                let texture = room.floor == .parquet ? ProceduralArt.parquet(variant: variant) : ProceduralArt.carpet(variant: variant)
                let tile = SKSpriteNode(texture: texture)
                tile.anchorPoint = .zero
                tile.position = CGPoint(x: CGFloat(c) * tileSize, y: CGFloat(r) * tileSize)
                floor.addChild(tile)
            }
        }
        let wallTexture = PixelArt.wall(room.wall)
        for c in 0..<room.cols {
            let wall = SKSpriteNode(texture: wallTexture)
            wall.anchorPoint = .zero
            wall.position = CGPoint(x: CGFloat(c) * tileSize, y: CGFloat(room.walkRows) * tileSize)
            wall.zPosition = -900
            world.addChild(wall)
        }
        let height = CGFloat(room.rows) * tileSize
        let width = CGFloat(room.cols) * tileSize
        for (x, w) in [(-8.0, 8.0), (Double(width), 8.0)] {
            let edge = SKSpriteNode(texture: PixelArt.edge(width: Int(w), height: Int(height) + 8))
            edge.anchorPoint = .zero
            edge.position = CGPoint(x: x, y: -8)
            edge.zPosition = 9_999
            world.addChild(edge)
        }
        let bottom = SKSpriteNode(texture: PixelArt.edge(width: Int(width) + 16, height: 8))
        bottom.anchorPoint = .zero
        bottom.position = CGPoint(x: -8, y: -8)
        bottom.zPosition = 9_999
        world.addChild(bottom)

        if let mat = room.doormat {
            let node = SKSpriteNode(texture: PixelArt.doormat())
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.position = CGPoint(x: CGFloat(mat.c) * tileSize + tileSize / 2, y: 4)
            node.zPosition = -500
            world.addChild(node)
        }

        for prop in room.props {
            let node = SKSpriteNode(texture: Assets.texture(prop.texture))
            node.name = prop.name
            node.anchorPoint = CGPoint(x: 0.5, y: prop.onWall || prop.flat ? 0 : Assets.bottomPadding(prop.texture) / max(node.size.height, 1))
            node.position = CGPoint(x: CGFloat(prop.x) * tileSize, y: CGFloat(prop.baseY) * tileSize + (prop.onWall || prop.flat ? 0 : 8))
            node.zPosition = prop.flat ? -400 : prop.onWall ? -800 : depth(forBaseY: node.position.y)
            if !prop.flat && !prop.onWall {
                let shadow = SKSpriteNode(texture: PixelArt.shadow(width: Int(node.size.width * 0.8), height: 14))
                shadow.position = CGPoint(x: node.position.x, y: node.position.y + 6)
                shadow.zPosition = -300
                world.addChild(shadow)
            }
            if let interaction = prop.interaction {
                node.userData = ["interaction": "\(interaction)"]
            }
            world.addChild(node)
            if prop.interaction == .inbox {
                inboxBadge = SKSpriteNode(texture: ProceduralArt.exclamation)
                inboxBadge.setScale(2)
                inboxBadge.anchorPoint = CGPoint(x: 0.5, y: 0)
                inboxBadge.position = CGPoint(x: node.position.x + 18, y: node.position.y + node.size.height - 4)
                inboxBadge.zPosition = node.zPosition + 1
                world.addChild(inboxBadge)
                updateInboxBadge()
            }
        }

        for desk in room.desks {
            let node = SKSpriteNode(texture: Assets.texture("objects/desk_worker.png"))
            node.anchorPoint = CGPoint(x: 0.5, y: Assets.bottomPadding("objects/desk_worker.png") / max(node.size.height, 1))
            node.position = CGPoint(x: CGFloat(desk.centerX) * tileSize, y: CGFloat(desk.deskTile.r) * tileSize + 10)
            node.zPosition = depth(forBaseY: node.position.y)
            world.addChild(node)
            let shadow = SKSpriteNode(texture: PixelArt.shadow(width: 110, height: 14))
            shadow.position = CGPoint(x: node.position.x, y: node.position.y + 6)
            shadow.zPosition = -300
            world.addChild(shadow)
        }

        player.removeFromParent()
        player.removeAllActions()
        player.stopWalking()
        world.addChild(player)
        player.place(at: spawn)
        player.face(facing)
        if room.id == .openSpace { layoutRobots(animated: false) }
        updateCamera(force: true)
        controller?.world(didEnter: room.id)
    }

    func setInbox(count: Int) {
        inboxCount = count
        updateInboxBadge()
    }

    private func updateInboxBadge() {
        inboxBadge.isHidden = inboxCount == 0
        inboxBadge.removeAllActions()
        if inboxCount > 0 {
            inboxBadge.run(.repeatForever(.sequence([.moveBy(x: 0, y: 5, duration: 0.2), .moveBy(x: 0, y: -5, duration: 0.2), .wait(forDuration: 0.8)])))
        }
    }

    func setFloor(_ sessions: [AgentSession]) {
        floorSessions = sessions
        let ids = Set(sessions.map(\.id))
        for id in slots.keys where !ids.contains(id) { slots.removeValue(forKey: id) }
        let capacity = Room.openSpace.desks.count
        for session in sessions where slots[session.id] == nil {
            let used = Set(slots.values)
            if let free = (0..<capacity).first(where: { !used.contains($0) }) { slots[session.id] = free }
        }
        if room.id == .openSpace { layoutRobots(animated: true) }
    }

    private func layoutRobots(animated: Bool) {
        let ids = Set(floorSessions.map(\.id))
        for (id, node) in robots where !ids.contains(id) {
            robots.removeValue(forKey: id)
            if animated { node.leave {} } else { node.removeFromParent() }
        }
        for session in floorSessions {
            guard let slotIndex = slots[session.id], slotIndex < room.desks.count else { continue }
            if let node = robots[session.id] {
                if node.slot.index == slotIndex {
                    if talkingRobot !== node { node.update(session) }
                    continue
                }
                node.removeFromParent()
            }
            let node = RobotNode(session: session, slot: room.desks[slotIndex])
            world.addChild(node)
            robots[session.id] = node
            if animated { node.appear() }
        }
    }

    func robot(atSlot slot: Int) -> RobotNode? {
        robots.values.first { $0.slot.index == slot }
    }

    func endConversation() {
        talkingRobot?.resume()
        talkingRobot = nil
    }

    override func update(_ currentTime: TimeInterval) {
        updateCamera(force: false)
        guard !transitioning, controller?.isInputBlocked != true else {
            if !player.isMoving { player.stopWalking() }
            return
        }
        if !player.isMoving {
            if let direction = heldKeys.last {
                step(direction)
            } else {
                player.stopWalking()
            }
        }
        updateHighlight()
    }

    private func step(_ direction: Facing) {
        player.face(direction)
        if let exit = room.exit(from: player.tile, facing: direction) {
            transition(exit)
            return
        }
        let target = player.tile.moved(direction)
        guard room.isWalkable(target) else {
            player.stopWalking()
            return
        }
        player.walk(to: target, duration: running ? 0.13 : 0.24) {}
    }

    private func transition(_ exit: Exit) {
        transitioning = true
        heldKeys.removeAll()
        player.stopWalking()
        NSSound(named: "Pop")?.play()
        fader.run(.sequence([
            .fadeIn(withDuration: 0.22),
            .run { [weak self] in self?.build(exit.to, spawn: exit.spawn, facing: exit.spawnFacing) },
            .fadeOut(withDuration: 0.22),
            .run { [weak self] in self?.transitioning = false },
        ]))
    }

    private func updateHighlight() {
        let front = player.tile.moved(player.facing)
        var target: RobotNode?
        if case .robot(let slot) = room.interaction(at: front) { target = robot(atSlot: slot) }
        if target !== highlighted {
            highlighted?.setHighlighted(false)
            target?.setHighlighted(true)
            highlighted = target
        }
    }

    private func updateCamera(force: Bool) {
        let worldWidth = CGFloat(room.cols) * tileSize
        let worldHeight = CGFloat(room.rows) * tileSize
        let scale = cameraNode.xScale
        let viewWidth = size.width * scale
        let viewHeight = size.height * scale
        var target = player.position
        target.y += 64
        if worldWidth + 32 <= viewWidth {
            target.x = worldWidth / 2
        } else {
            target.x = min(max(target.x, viewWidth / 2 - 16), worldWidth - viewWidth / 2 + 16)
        }
        if worldHeight + 32 <= viewHeight {
            target.y = worldHeight / 2 - 8
        } else {
            target.y = min(max(target.y, viewHeight / 2 - 16), worldHeight - viewHeight / 2 + 16)
        }
        target.x = target.x.rounded()
        target.y = target.y.rounded()
        cameraNode.position = target
    }

    func setZoom(_ zoom: CGFloat) {
        cameraNode.setScale(1 / zoom)
        updateCamera(force: true)
    }

    func crackWhip() {
        guard !player.isMoving, !transitioning else { return }
        heldKeys.removeAll()
        let target = player.tile.moved(player.facing)
        var robot: RobotNode?
        if case .robot(let slot) = room.interaction(at: target) { robot = self.robot(atSlot: slot) }
        player.crackWhip { [weak self] in
            guard let self else { return }
            let impact: CGPoint
            if let robot {
                impact = CGPoint(x: robot.position.x, y: robot.position.y + 70)
                robot.whipped(boost: true)
            } else {
                let front = TheBoss.position(of: target)
                impact = CGPoint(x: front.x, y: front.y + 50)
            }
            let crack = SKSpriteNode()
            crack.position = impact
            crack.zPosition = 20_000
            crack.setScale(2)
            self.world.addChild(crack)
            crack.run(.sequence([.animate(with: (0..<5).map { ProceduralArt.crack(frame: $0) }, timePerFrame: 0.05, resize: true, restore: false), .removeFromParent()]))
            let label = SKLabelNode(text: tr("CRACK!"))
            label.fontName = Theme.roundedFontName(size: 18, weight: .black)
            label.fontSize = 18
            label.fontColor = NSColor(srgbRed: 0.96, green: 0.73, blue: 0.26, alpha: 1)
            label.position = CGPoint(x: impact.x + 26, y: impact.y + 18)
            label.zPosition = 20_001
            self.world.addChild(label)
            label.run(.sequence([.group([.moveBy(x: 0, y: 14, duration: 0.5), .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.3)])]), .removeFromParent()]))
            self.shakeCamera()
            self.controller?.world(didWhip: robot?.session)
        }
    }

    private func shakeCamera() {
        world.run(.sequence([.moveBy(x: 4, y: 0, duration: 0.03), .moveBy(x: -8, y: 2, duration: 0.04), .moveBy(x: 4, y: -2, duration: 0.03), .move(to: .zero, duration: 0)]))
    }

    func interact() {
        let target = player.tile.moved(player.facing)
        guard let interaction = room.interaction(at: target) else { return }
        trigger(interaction)
    }

    private func trigger(_ interaction: Interaction) {
        var session: AgentSession?
        if case .robot(let slot) = interaction {
            guard let robot = robot(atSlot: slot) else {
                controller?.world(didInteract: interaction, session: nil)
                return
            }
            session = robot.session
            talkingRobot = robot
            robot.turn(toward: .south)
        }
        heldKeys.removeAll()
        player.stopWalking()
        controller?.world(didInteract: interaction, session: session)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }
        running = event.modifierFlags.contains(.shift)
        if let direction = Self.direction(for: event.keyCode) {
            if !heldKeys.contains(direction) { heldKeys.append(direction) }
            return true
        }
        guard !event.isARepeat, controller?.isInputBlocked != true else { return false }
        switch event.keyCode {
        case 49, 36, 14, 6, 76:
            interact()
            return true
        case 53, 48, 7:
            controller?.worldDidRequestMenu()
            return true
        case 3:
            crackWhip()
            return true
        default:
            return false
        }
    }

    func handleKeyUp(_ event: NSEvent) {
        if let direction = Self.direction(for: event.keyCode) {
            heldKeys.removeAll { $0 == direction }
        }
    }

    func handleFlags(_ event: NSEvent) {
        running = event.modifierFlags.contains(.shift)
    }

    func releaseKeys() {
        heldKeys.removeAll()
    }

    static func direction(for keyCode: UInt16) -> Facing? {
        switch keyCode {
        case 123, 0: .west
        case 124, 2: .east
        case 125, 1: .south
        case 126, 13: .north
        default: nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard controller?.isInputBlocked != true else { return }
        let location = event.location(in: world)
        let tile = Tile(c: Int(floor(location.x / tileSize)), r: Int(floor(location.y / tileSize)))
        if let interaction = room.interaction(at: tile) ?? room.interaction(at: Tile(c: tile.c, r: tile.r - 1)) {
            trigger(interaction)
        }
    }
}
