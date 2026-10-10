import Foundation

enum RoomID: String {
    case office, openSpace
}

enum Interaction: Equatable {
    case usage, library, inbox, analytics, overview, coffee, water, sofa, servers, window, plant
    case robot(slot: Int)
}

struct Tile: Hashable {
    var c: Int
    var r: Int

    func moved(_ facing: Facing) -> Tile { Tile(c: c + facing.delta.dx, r: r + facing.delta.dy) }
}

struct Prop {
    var name: String
    var texture: String
    var x: Double
    var baseY: Double
    var blocks: [Tile] = []
    var interaction: Interaction?
    var interactCells: [Tile] = []
    var flat = false
    var onWall = false
}

struct Exit {
    var trigger: Tile
    var direction: Facing
    var to: RoomID
    var spawn: Tile
    var spawnFacing: Facing
}

struct DeskSlot {
    var index: Int
    var deskTile: Tile

    var robotTile: Tile { Tile(c: deskTile.c, r: deskTile.r + 1) }
    var centerX: Double { Double(deskTile.c) + 1 }
}

struct Room {
    var id: RoomID
    var cols: Int
    var walkRows: Int
    var wall: WallStyle
    var floorTiles: [String]
    var props: [Prop]
    var exits: [Exit]
    var desks: [DeskSlot] = []
    var doormat: Tile?

    var rows: Int { walkRows + 2 }

    var blocked: Set<Tile> {
        var set = Set(props.flatMap(\.blocks))
        for desk in desks {
            set.insert(desk.deskTile)
            set.insert(Tile(c: desk.deskTile.c + 1, r: desk.deskTile.r))
            set.insert(desk.robotTile)
            set.insert(Tile(c: desk.robotTile.c + 1, r: desk.robotTile.r))
        }
        return set
    }

    func isWalkable(_ tile: Tile) -> Bool {
        tile.c >= 0 && tile.c < cols && tile.r >= 0 && tile.r < walkRows && !blocked.contains(tile)
    }

    func interaction(at tile: Tile) -> Interaction? {
        for desk in desks {
            let cells = [desk.deskTile, Tile(c: desk.deskTile.c + 1, r: desk.deskTile.r), desk.robotTile, Tile(c: desk.robotTile.c + 1, r: desk.robotTile.r)]
            if cells.contains(tile) { return .robot(slot: desk.index) }
        }
        for prop in props where prop.interaction != nil {
            if prop.blocks.contains(tile) || prop.interactCells.contains(tile) { return prop.interaction }
        }
        return nil
    }

    func exit(from tile: Tile, facing: Facing) -> Exit? {
        exits.first { $0.trigger == tile && $0.direction == facing }
    }

    static let office = Room(
        id: .office, cols: 12, walkRows: 7, wall: .office,
        floorTiles: ["tbfc/floor/parquet_1.png", "tbfc/floor/parquet_2.png", "tbfc/floor/parquet_3.png", "tbfc/floor/parquet_4.png"],
        props: [
            Prop(name: "Fenêtre", texture: "objects/window_wall.png", x: 3.5, baseY: 7.3, interaction: .window,
                 interactCells: [Tile(c: 3, r: 7)], onWall: true),
            Prop(name: "Porte", texture: "tbfc/decor/brique_mecanismes_porte_fermee.png", x: 10.5, baseY: 7.0, onWall: true),
            Prop(name: "Tableau blanc", texture: "objects/whiteboard.png", x: 5.5, baseY: 6.0,
                 blocks: [Tile(c: 5, r: 6), Tile(c: 6, r: 6)], interaction: .analytics),
            Prop(name: "Bibliothèque des règles", texture: "objects/bookshelf.png", x: 8.0, baseY: 6.0,
                 blocks: [Tile(c: 7, r: 6), Tile(c: 8, r: 6)], interaction: .library),
            Prop(name: "Bannette", texture: "objects/intray.png", x: 1.5, baseY: 6.0,
                 blocks: [Tile(c: 1, r: 6)], interaction: .inbox),
            Prop(name: "Plante", texture: "tbfc/decor/decor_interieur_plante_en_pot.png", x: 0.5, baseY: 6.0,
                 blocks: [Tile(c: 0, r: 6)], interaction: .plant),
            Prop(name: "Plante", texture: "tbfc/decor/decor_interieur_plante_en_pot.png", x: 11.5, baseY: 6.0,
                 blocks: [Tile(c: 11, r: 6)], interaction: .plant),
            Prop(name: "Tapis", texture: "tbfc/decor/decor_interieur_tapis.png", x: 6.0, baseY: 1.55, flat: true),
            Prop(name: "Bureau du boss", texture: "objects/desk_boss.png", x: 6.0, baseY: 3.0,
                 blocks: [Tile(c: 5, r: 3), Tile(c: 6, r: 3), Tile(c: 5, r: 4), Tile(c: 6, r: 4)], interaction: .usage),
            Prop(name: "Canapé", texture: "objects/sofa.png", x: 1.0, baseY: 1.0,
                 blocks: [Tile(c: 0, r: 1), Tile(c: 1, r: 1)], interaction: .sofa),
            Prop(name: "Plante", texture: "tbfc/decor/decor_interieur_plante_en_pot.png", x: 2.5, baseY: 1.0,
                 blocks: [Tile(c: 2, r: 1)], interaction: .plant),
            Prop(name: "Baie", texture: "objects/server_rack.png", x: 11.5, baseY: 1.0,
                 blocks: [Tile(c: 11, r: 1)], interaction: .servers),
        ],
        exits: [Exit(trigger: Tile(c: 10, r: 6), direction: .north, to: .openSpace, spawn: Tile(c: 9, r: 0), spawnFacing: .north)]
    )

    static let openSpace: Room = {
        var desks: [DeskSlot] = []
        var index = 0
        for row in [1, 4, 7] {
            for col in [6, 11, 2, 15] {
                desks.append(DeskSlot(index: index, deskTile: Tile(c: col, r: row)))
                index += 1
            }
        }
        return Room(
            id: .openSpace, cols: 20, walkRows: 10, wall: .openSpace,
            floorTiles: ["tbfc/floor/damier_1.png", "tbfc/floor/damier_2.png", "tbfc/floor/damier_3.png", "tbfc/floor/damier_4.png"],
            props: [
                Prop(name: "Écran des agents", texture: "objects/wall_screen.png", x: 9.5, baseY: 10.15,
                     interaction: .overview, interactCells: [Tile(c: 8, r: 10), Tile(c: 9, r: 10), Tile(c: 10, r: 10)], onWall: true),
                Prop(name: "Fenêtre", texture: "objects/window_wall.png", x: 4.5, baseY: 10.3, interaction: .window,
                     interactCells: [Tile(c: 4, r: 10)], onWall: true),
                Prop(name: "Fenêtre", texture: "objects/window_wall.png", x: 14.5, baseY: 10.3, interaction: .window,
                     interactCells: [Tile(c: 14, r: 10)], onWall: true),
                Prop(name: "Baie", texture: "objects/server_rack.png", x: 0.5, baseY: 9.0,
                     blocks: [Tile(c: 0, r: 9)], interaction: .servers),
                Prop(name: "Baie", texture: "objects/server_rack.png", x: 1.5, baseY: 9.0,
                     blocks: [Tile(c: 1, r: 9)], interaction: .servers),
                Prop(name: "Fontaine", texture: "objects/water_cooler.png", x: 17.5, baseY: 9.0,
                     blocks: [Tile(c: 17, r: 9)], interaction: .water),
                Prop(name: "Machine à café", texture: "objects/coffee_machine.png", x: 18.5, baseY: 9.0,
                     blocks: [Tile(c: 18, r: 9)], interaction: .coffee),
                Prop(name: "Plante", texture: "tbfc/decor/decor_interieur_plante_en_pot.png", x: 19.5, baseY: 9.0,
                     blocks: [Tile(c: 19, r: 9)], interaction: .plant),
                Prop(name: "Canapé", texture: "objects/sofa.png", x: 18.0, baseY: 0.2,
                     blocks: [Tile(c: 17, r: 0), Tile(c: 18, r: 0)], interaction: .sofa),
                Prop(name: "Plante", texture: "tbfc/decor/decor_interieur_plante_en_pot.png", x: 19.5, baseY: 0.0,
                     blocks: [Tile(c: 19, r: 0)], interaction: .plant),
                Prop(name: "Plante", texture: "tbfc/decor/decor_interieur_plante_en_pot.png", x: 0.5, baseY: 0.0,
                     blocks: [Tile(c: 0, r: 0)], interaction: .plant),
                Prop(name: "Plante", texture: "tbfc/decor/decor_interieur_plante_en_pot.png", x: 0.5, baseY: 5.0,
                     blocks: [Tile(c: 0, r: 5)], interaction: .plant),
                Prop(name: "Plante", texture: "tbfc/decor/decor_interieur_plante_en_pot.png", x: 19.5, baseY: 5.0,
                     blocks: [Tile(c: 19, r: 5)], interaction: .plant),
                Prop(name: "Tapis", texture: "tbfc/decor/decor_interieur_tapis.png", x: 9.5, baseY: 5.6, flat: true),
                Prop(name: "Tapis", texture: "tbfc/decor/decor_interieur_tapis.png", x: 9.5, baseY: 2.6, flat: true),
                Prop(name: "Canapé", texture: "objects/sofa.png", x: 9.5, baseY: 9.0,
                     blocks: [Tile(c: 9, r: 9)], interaction: .sofa),
            ],
            exits: [Exit(trigger: Tile(c: 9, r: 0), direction: .south, to: .office, spawn: Tile(c: 10, r: 6), spawnFacing: .south)],
            desks: desks,
            doormat: Tile(c: 9, r: 0)
        )
    }()

    static func room(_ id: RoomID) -> Room {
        switch id {
        case .office: office
        case .openSpace: openSpace
        }
    }
}
