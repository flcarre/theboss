import type { Interaction, RoomId } from "./types";

export const TILE_SIZE = 64;

export type Facing = "south" | "north" | "east" | "west";

export const FACINGS: Facing[] = ["south", "north", "east", "west"];

export const FACING_DELTA: Record<Facing, { dx: number; dy: number }> = {
  south: { dx: 0, dy: -1 },
  north: { dx: 0, dy: 1 },
  east: { dx: 1, dy: 0 },
  west: { dx: -1, dy: 0 },
};

export type Tile = { c: number; r: number };

export type PropInteraction = Exclude<Interaction, "robot">;

export type TileInteraction = { kind: PropInteraction } | { kind: "robot"; slot: number };

export type FloorStyle = "parquet" | "carpet";

export type Prop = {
  name: string;
  texture: string;
  x: number;
  baseY: number;
  blocks: Tile[];
  interaction: PropInteraction | null;
  interactCells: Tile[];
  flat: boolean;
  onWall: boolean;
};

export type Exit = { trigger: Tile; direction: Facing; to: RoomId; spawn: Tile; spawnFacing: Facing };

export type DeskSlot = { index: number; deskTile: Tile };

export type Room = {
  id: RoomId;
  cols: number;
  walkRows: number;
  floor: FloorStyle;
  wallTexture: string;
  props: Prop[];
  exits: Exit[];
  desks: DeskSlot[];
  doormat: Tile | null;
};

export function tile(c: number, r: number): Tile {
  return { c, r };
}

export function moved(from: Tile, facing: Facing): Tile {
  const delta = FACING_DELTA[facing];
  return { c: from.c + delta.dx, r: from.r + delta.dy };
}

export function sameTile(a: Tile, b: Tile): boolean {
  return a.c === b.c && a.r === b.r;
}

export function tileKey(t: Tile): string {
  return `${t.c},${t.r}`;
}

export function robotTile(desk: DeskSlot): Tile {
  return { c: desk.deskTile.c, r: desk.deskTile.r + 1 };
}

export function deskCenterX(desk: DeskSlot): number {
  return desk.deskTile.c + 1;
}

export function deskCells(desk: DeskSlot): Tile[] {
  const robot = robotTile(desk);
  return [desk.deskTile, tile(desk.deskTile.c + 1, desk.deskTile.r), robot, tile(robot.c + 1, robot.r)];
}

export function roomRows(room: Room): number {
  return room.walkRows + 2;
}

type PropSpec = Partial<Pick<Prop, "blocks" | "interaction" | "interactCells" | "flat" | "onWall">> &
  Pick<Prop, "name" | "texture" | "x" | "baseY">;

function prop(spec: PropSpec): Prop {
  return {
    blocks: [],
    interaction: null,
    interactCells: [],
    flat: false,
    onWall: false,
    ...spec,
  };
}

const blockedCache = new WeakMap<Room, Set<string>>();

function blockedTiles(room: Room): Set<string> {
  const cached = blockedCache.get(room);
  if (cached) return cached;
  const set = new Set<string>();
  for (const p of room.props) for (const b of p.blocks) set.add(tileKey(b));
  for (const desk of room.desks) for (const cell of deskCells(desk)) set.add(tileKey(cell));
  blockedCache.set(room, set);
  return set;
}

export function isWalkable(room: Room, t: Tile): boolean {
  return t.c >= 0 && t.c < room.cols && t.r >= 0 && t.r < room.walkRows && !blockedTiles(room).has(tileKey(t));
}

export type InteractionTarget = { interaction: TileInteraction; cells: Tile[] };

export function interactionTargetAt(room: Room, t: Tile): InteractionTarget | null {
  for (const desk of room.desks) {
    const cells = deskCells(desk);
    if (cells.some((cell) => sameTile(cell, t))) return { interaction: { kind: "robot", slot: desk.index }, cells };
  }
  for (const p of room.props) {
    if (!p.interaction) continue;
    const cells = [...p.blocks, ...p.interactCells];
    if (cells.some((b) => sameTile(b, t))) return { interaction: { kind: p.interaction }, cells };
  }
  return null;
}

export function interactionAt(room: Room, t: Tile): TileInteraction | null {
  return interactionTargetAt(room, t)?.interaction ?? null;
}

export function sameInteraction(a: TileInteraction | null, b: TileInteraction | null): boolean {
  if (!a || !b) return a === b;
  if (a.kind === "robot" && b.kind === "robot") return a.slot === b.slot;
  return a.kind === b.kind;
}

export function exitFrom(room: Room, t: Tile, facing: Facing): Exit | null {
  return room.exits.find((e) => sameTile(e.trigger, t) && e.direction === facing) ?? null;
}

export const OFFICE: Room = {
  id: "office",
  cols: 12,
  walkRows: 7,
  floor: "parquet",
  wallTexture: "walls/wall_office.png",
  props: [
    prop({ name: "Window", texture: "objects/window_wall.png", x: 3.5, baseY: 7.3, interaction: "window", interactCells: [tile(3, 7)], onWall: true }),
    prop({ name: "Door", texture: "objects/door.png", x: 10.5, baseY: 7.0, onWall: true }),
    prop({ name: "Whiteboard", texture: "objects/whiteboard.png", x: 5.5, baseY: 6.0, blocks: [tile(5, 6), tile(6, 6)], interaction: "analytics" }),
    prop({ name: "Rules library", texture: "objects/bookshelf.png", x: 8.0, baseY: 6.0, blocks: [tile(7, 6), tile(8, 6)], interaction: "library" }),
    prop({ name: "In-tray", texture: "objects/intray.png", x: 1.5, baseY: 6.0, blocks: [tile(1, 6)], interaction: "inbox" }),
    prop({ name: "Plant", texture: "objects/plant.png", x: 0.5, baseY: 6.0, blocks: [tile(0, 6)], interaction: "plant" }),
    prop({ name: "Archives", texture: "objects/archive_cabinet.png", x: 3.5, baseY: 6.0, blocks: [tile(3, 6)], interaction: "archives" }),
    prop({ name: "Plant", texture: "objects/plant.png", x: 11.5, baseY: 6.0, blocks: [tile(11, 6)], interaction: "plant" }),
    prop({ name: "Rug", texture: "objects/rug.png", x: 6.0, baseY: 1.55, flat: true }),
    prop({
      name: "Boss desk",
      texture: "objects/desk_boss.png",
      x: 6.0,
      baseY: 3.0,
      blocks: [tile(5, 3), tile(6, 3), tile(5, 4), tile(6, 4)],
      interaction: "usage",
    }),
    prop({ name: "Sofa", texture: "objects/sofa.png", x: 1.0, baseY: 1.0, blocks: [tile(0, 1), tile(1, 1)], interaction: "sofa" }),
    prop({ name: "Plant", texture: "objects/plant.png", x: 2.5, baseY: 1.0, blocks: [tile(2, 1)], interaction: "plant" }),
    prop({ name: "Server rack", texture: "objects/server_rack.png", x: 11.5, baseY: 1.0, blocks: [tile(11, 1)], interaction: "servers" }),
  ],
  exits: [{ trigger: tile(10, 6), direction: "north", to: "openSpace", spawn: tile(9, 0), spawnFacing: "north" }],
  desks: [],
  doormat: null,
};

function openSpaceDesks(): DeskSlot[] {
  const desks: DeskSlot[] = [];
  for (const row of [1, 4, 7]) {
    for (const col of [6, 11, 2, 15]) desks.push({ index: desks.length, deskTile: tile(col, row) });
  }
  return desks;
}

export const OPEN_SPACE: Room = {
  id: "openSpace",
  cols: 20,
  walkRows: 10,
  floor: "carpet",
  wallTexture: "walls/wall_openspace.png",
  props: [
    prop({
      name: "Agent board",
      texture: "objects/wall_screen.png",
      x: 9.5,
      baseY: 10.15,
      interaction: "overview",
      interactCells: [tile(8, 10), tile(9, 10), tile(10, 10)],
      onWall: true,
    }),
    prop({ name: "Window", texture: "objects/window_wall.png", x: 4.5, baseY: 10.3, interaction: "window", interactCells: [tile(4, 10)], onWall: true }),
    prop({ name: "Window", texture: "objects/window_wall.png", x: 14.5, baseY: 10.3, interaction: "window", interactCells: [tile(14, 10)], onWall: true }),
    prop({ name: "Server rack", texture: "objects/server_rack.png", x: 0.5, baseY: 9.0, blocks: [tile(0, 9)], interaction: "servers" }),
    prop({ name: "Server rack", texture: "objects/server_rack.png", x: 1.5, baseY: 9.0, blocks: [tile(1, 9)], interaction: "servers" }),
    prop({ name: "Water cooler", texture: "objects/water_cooler.png", x: 17.5, baseY: 9.0, blocks: [tile(17, 9)], interaction: "water" }),
    prop({ name: "Coffee machine", texture: "objects/coffee_machine.png", x: 18.5, baseY: 9.0, blocks: [tile(18, 9)], interaction: "coffee" }),
    prop({ name: "Plant", texture: "objects/plant.png", x: 19.5, baseY: 9.0, blocks: [tile(19, 9)], interaction: "plant" }),
    prop({ name: "Sofa", texture: "objects/sofa.png", x: 18.0, baseY: 0.2, blocks: [tile(17, 0), tile(18, 0)], interaction: "sofa" }),
    prop({ name: "Plant", texture: "objects/plant.png", x: 19.5, baseY: 0.0, blocks: [tile(19, 0)], interaction: "plant" }),
    prop({ name: "Plant", texture: "objects/plant.png", x: 0.5, baseY: 0.0, blocks: [tile(0, 0)], interaction: "plant" }),
    prop({ name: "Plant", texture: "objects/plant.png", x: 0.5, baseY: 5.0, blocks: [tile(0, 5)], interaction: "plant" }),
    prop({ name: "Plant", texture: "objects/plant.png", x: 19.5, baseY: 5.0, blocks: [tile(19, 5)], interaction: "plant" }),
    prop({ name: "Rug", texture: "objects/rug.png", x: 9.5, baseY: 5.6, flat: true }),
    prop({ name: "Rug", texture: "objects/rug.png", x: 9.5, baseY: 2.6, flat: true }),
    prop({ name: "Sofa", texture: "objects/sofa.png", x: 9.5, baseY: 9.0, blocks: [tile(9, 9)], interaction: "sofa" }),
  ],
  exits: [{ trigger: tile(9, 0), direction: "south", to: "office", spawn: tile(10, 6), spawnFacing: "south" }],
  desks: openSpaceDesks(),
  doormat: tile(9, 0),
};

export const SPAWNS: Record<RoomId, { spawn: Tile; facing: Facing }> = {
  office: { spawn: tile(6, 1), facing: "north" },
  openSpace: { spawn: tile(9, 0), facing: "north" },
};

export function roomFor(id: RoomId): Room {
  return id === "office" ? OFFICE : OPEN_SPACE;
}
