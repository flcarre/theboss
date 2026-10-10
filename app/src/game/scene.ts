import type { AgentSession } from "../api";
import { bottomPadding, hasFailed, image, onAssetLoaded, type Sprite } from "./assets";
import { depth, positionOf, Player, Robot, smokePuff } from "./characters";
import { carpet, crack, doormat, edge, exclamation, parquet, shadow, wall } from "./pixelArt";
import { DrawList, drawSprite, ROUNDED_FONT, sampleKeyframes, type Keyframe } from "./render";
import {
  deskCenterX,
  exitFrom,
  FACING_DELTA,
  interactionAt,
  interactionTargetAt,
  isWalkable,
  moved,
  OPEN_SPACE,
  OFFICE,
  roomFor,
  roomRows,
  sameInteraction,
  sameTile,
  SPAWNS,
  TILE_SIZE,
  tileKey,
  type Exit,
  type Facing,
  type Room,
  type Tile,
  type TileInteraction,
} from "./rooms";
import type { GameCallbacks, RoomId } from "./types";

const BACKGROUND = "rgb(20, 17, 38)";
const WALK_DURATION = 0.24;
const RUN_DURATION = 0.13;
const FADE_DURATION = 0.22;
const SHAKE: Keyframe[] = [
  { t: 0, x: 0, y: 0 },
  { t: 0.03, x: 4, y: 0 },
  { t: 0.07, x: -4, y: 2 },
  { t: 0.1, x: 0, y: 0 },
];
const CRACK_COLOR = "rgb(245, 186, 66)";

const DIRECTION_CODES: Record<string, Facing> = {
  ArrowLeft: "west",
  KeyA: "west",
  ArrowRight: "east",
  KeyD: "east",
  ArrowDown: "south",
  KeyS: "south",
  ArrowUp: "north",
  KeyW: "north",
};
const INTERACT_CODES = new Set(["Space", "Enter", "NumpadEnter", "KeyE", "KeyZ"]);
const MENU_CODES = new Set(["Escape", "Tab", "KeyX"]);
const WHIP_CODE = "KeyF";

type Effect =
  | { kind: "crack"; x: number; y: number; start: number }
  | { kind: "label"; x: number; y: number; start: number; text: string }
  | { kind: "smoke"; x: number; y: number; z: number; start: number };

type Arrival = { kind: "interact"; facing: Facing; interaction: TileInteraction } | { kind: "exit"; exit: Exit };

type Goal = { tile: Tile; arrival: Arrival | null };

export type SceneHost = {
  callbacks: () => GameCallbacks;
  inputBlocked: () => boolean;
};

export type Viewport = { cssWidth: number; cssHeight: number; dpr: number };

function facingBetween(from: Tile, to: Tile): Facing {
  if (to.c > from.c) return "east";
  if (to.c < from.c) return "west";
  return to.r > from.r ? "north" : "south";
}

function crackLabel(): string {
  return document.documentElement.lang.toLowerCase().startsWith("fr") ? "CLAC !" : "CRACK!";
}

export class WorldScene {
  room: Room = OFFICE;
  private readonly player = new Player();
  private robots = new Map<string, Robot>();
  private leavingRobots: Robot[] = [];
  private slots = new Map<string, number>();
  private floorSessions: AgentSession[] = [];
  private heldKeys: Facing[] = [];
  private tappedKey: Facing | null = null;
  private running = false;
  private transitioning = false;
  private fader: { start: number; exit: Exit; built: boolean } | null = null;
  private inboxCount = 0;
  private inboxBadge: { x: number; y: number; z: number } | null = null;
  private inboxBounceStart = 0;
  private highlighted: Robot | null = null;
  private talkingRobot: Robot | null = null;
  private zoom = 1.5;
  private camera = { x: 0, y: 0 };
  private viewport: Viewport = { cssWidth: 1280, cssHeight: 800, dpr: 1 };
  private now = 0;
  private shakeStart: number | null = null;
  private effects: Effect[] = [];
  private path: Tile[] = [];
  private arrival: Arrival | null = null;
  private staticLayer: HTMLCanvasElement = document.createElement("canvas");
  private staticDirty = true;
  private readonly disposeAssetListener: () => void;

  constructor(private readonly host: SceneHost) {
    this.disposeAssetListener = onAssetLoaded(() => {
      this.staticDirty = true;
      this.refreshInboxBadge();
    });
    const office = SPAWNS.office;
    this.build("office", office.spawn, office.facing);
  }

  dispose(): void {
    this.disposeAssetListener();
  }

  get currentRoom(): RoomId {
    return this.room.id;
  }

  build(id: RoomId, spawn: Tile, facing: Facing): void {
    this.robots.clear();
    this.leavingRobots = [];
    this.highlighted = null;
    this.talkingRobot = null;
    this.effects = [];
    this.path = [];
    this.arrival = null;
    this.room = roomFor(id);
    this.staticDirty = true;
    this.refreshInboxBadge();
    this.player.reset();
    this.player.place(spawn);
    this.player.face(facing);
    if (this.room.id === "openSpace") this.layoutRobots(false);
    this.updateCamera();
    this.host.callbacks().onEnterRoom(this.room.id);
  }

  enterRoom(id: RoomId): void {
    this.transitioning = false;
    this.fader = null;
    this.heldKeys = [];
    this.tappedKey = null;
    const spawn = SPAWNS[id];
    this.build(id, spawn.spawn, spawn.facing);
  }

  setViewport(viewport: Viewport): void {
    this.viewport = viewport;
    this.updateCamera();
  }

  setZoom(zoom: number): void {
    this.zoom = zoom > 0 ? zoom : 1.5;
    this.updateCamera();
  }

  setInbox(count: number): void {
    if (count === this.inboxCount) return;
    this.inboxCount = count;
    this.inboxBounceStart = this.now;
  }

  setFloor(sessions: AgentSession[]): void {
    this.floorSessions = sessions;
    const ids = new Set(sessions.map((s) => s.id));
    for (const id of [...this.slots.keys()]) if (!ids.has(id)) this.slots.delete(id);
    const capacity = OPEN_SPACE.desks.length;
    for (const session of sessions) {
      if (this.slots.has(session.id)) continue;
      const used = new Set(this.slots.values());
      for (let free = 0; free < capacity; free++) {
        if (!used.has(free)) {
          this.slots.set(session.id, free);
          break;
        }
      }
    }
    if (this.room.id === "openSpace") this.layoutRobots(true);
  }

  endConversation(): void {
    this.talkingRobot?.resume(this.now);
    this.talkingRobot = null;
  }

  releaseKeys(): void {
    this.heldKeys = [];
    this.tappedKey = null;
    this.path = [];
    this.arrival = null;
  }

  private layoutRobots(animated: boolean): void {
    const ids = new Set(this.floorSessions.map((s) => s.id));
    for (const [id, robot] of [...this.robots]) {
      if (ids.has(id)) continue;
      this.robots.delete(id);
      if (this.highlighted === robot) this.highlighted = null;
      if (this.talkingRobot === robot) this.talkingRobot = null;
      if (animated) {
        robot.leave(this.now);
        this.leavingRobots.push(robot);
        this.effects.push({ kind: "smoke", x: robot.x, y: robot.y + 50, z: robot.z + 1, start: this.now });
      }
    }
    for (const session of this.floorSessions) {
      const slotIndex = this.slots.get(session.id);
      if (slotIndex === undefined || slotIndex >= this.room.desks.length) continue;
      const existing = this.robots.get(session.id);
      if (existing) {
        if (existing.slot.index === slotIndex) {
          if (this.talkingRobot !== existing) existing.update(session, this.now);
          continue;
        }
        this.robots.delete(session.id);
      }
      const robot = new Robot(session, this.room.desks[slotIndex], this.now);
      this.robots.set(session.id, robot);
      if (animated) robot.appear(this.now);
    }
  }

  private robotAtSlot(slot: number): Robot | null {
    for (const robot of this.robots.values()) if (robot.slot.index === slot) return robot;
    return null;
  }

  private robotFacing(t: Tile): Robot | null {
    const interaction = interactionAt(this.room, t);
    return interaction?.kind === "robot" ? this.robotAtSlot(interaction.slot) : null;
  }

  tick(dt: number): void {
    this.now += dt;
    this.player.advance(dt);
    for (const robot of this.robots.values()) robot.advance(dt, this.now);
    for (const robot of this.leavingRobots) robot.advance(dt, this.now);
    this.leavingRobots = this.leavingRobots.filter((robot) => !robot.removed);
    this.advanceFader();
    this.update();
    this.updateCamera();
  }

  private advanceFader(): void {
    if (!this.fader) return;
    const elapsed = this.now - this.fader.start;
    if (!this.fader.built && elapsed >= FADE_DURATION) {
      this.fader.built = true;
      const exit = this.fader.exit;
      this.build(exit.to, exit.spawn, exit.spawnFacing);
      this.fader.start = this.now - FADE_DURATION;
      return;
    }
    if (this.fader.built && elapsed >= FADE_DURATION * 2) {
      this.fader = null;
      this.transitioning = false;
    }
  }

  private faderAlpha(): number {
    if (!this.fader) return 0;
    const elapsed = this.now - this.fader.start;
    if (elapsed <= FADE_DURATION) return Math.min(1, elapsed / FADE_DURATION);
    return Math.max(0, 1 - (elapsed - FADE_DURATION) / FADE_DURATION);
  }

  private update(): void {
    const player = this.player;
    if (this.transitioning || this.host.inputBlocked()) {
      if (!player.isMoving) player.stopWalking();
      if (this.host.inputBlocked()) {
        this.path = [];
        this.arrival = null;
      }
      return;
    }
    if (!player.isMoving && !player.isWhipping) {
      const direction = this.heldKeys[this.heldKeys.length - 1] ?? this.tappedKey;
      this.tappedKey = null;
      if (direction) {
        this.path = [];
        this.arrival = null;
        this.step(direction);
      } else if (this.path.length) {
        this.followPath();
      } else if (this.arrival) {
        this.arrive(this.arrival);
      } else {
        player.stopWalking();
      }
    }
    this.updateHighlight();
  }

  private step(direction: Facing): void {
    const player = this.player;
    player.face(direction);
    const exit = exitFrom(this.room, player.tile, direction);
    if (exit) {
      this.transition(exit);
      return;
    }
    const target = moved(player.tile, direction);
    if (!isWalkable(this.room, target)) {
      player.stopWalking();
      return;
    }
    player.walkTo(target, this.running ? RUN_DURATION : WALK_DURATION, this.now);
  }

  private followPath(): void {
    const next = this.path.shift();
    if (!next) return;
    if (!isWalkable(this.room, next)) {
      this.path = [];
      this.arrival = null;
      this.player.stopWalking();
      return;
    }
    this.player.face(facingBetween(this.player.tile, next));
    this.player.walkTo(next, this.running ? RUN_DURATION : WALK_DURATION, this.now);
  }

  private arrive(arrival: Arrival): void {
    this.arrival = null;
    if (arrival.kind === "exit") {
      this.step(arrival.exit.direction);
      return;
    }
    this.player.face(arrival.facing);
    this.player.stopWalking();
    const front = moved(this.player.tile, arrival.facing);
    if (sameInteraction(interactionAt(this.room, front), arrival.interaction)) this.trigger(arrival.interaction);
  }

  private transition(exit: Exit): void {
    this.transitioning = true;
    this.heldKeys = [];
    this.tappedKey = null;
    this.path = [];
    this.arrival = null;
    this.player.stopWalking();
    this.host.callbacks().onSound("pop");
    this.fader = { start: this.now, exit, built: false };
  }

  private updateHighlight(): void {
    const target = this.robotFacing(moved(this.player.tile, this.player.facing));
    if (target === this.highlighted) return;
    this.highlighted?.setHighlighted(false);
    target?.setHighlighted(true);
    this.highlighted = target;
  }

  private updateCamera(): void {
    const worldWidth = this.room.cols * TILE_SIZE;
    const worldHeight = roomRows(this.room) * TILE_SIZE;
    const viewWidth = this.viewport.cssWidth / this.zoom;
    const viewHeight = this.viewport.cssHeight / this.zoom;
    let x = this.player.x;
    let y = this.player.y + 64;
    if (worldWidth + 32 <= viewWidth) x = worldWidth / 2;
    else x = Math.min(Math.max(x, viewWidth / 2 - 16), worldWidth - viewWidth / 2 + 16);
    if (worldHeight + 32 <= viewHeight) y = worldHeight / 2 - 8;
    else y = Math.min(Math.max(y, viewHeight / 2 - 16), worldHeight - viewHeight / 2 + 16);
    this.camera = { x: Math.round(x), y: Math.round(y) };
  }

  crackWhip(): void {
    const player = this.player;
    if (player.isMoving || player.isWhipping || this.transitioning) return;
    this.heldKeys = [];
    this.tappedKey = null;
    this.path = [];
    this.arrival = null;
    let target = moved(player.tile, player.facing);
    let robot = this.robotFacing(target);
    if (!robot) {
      for (const facing of ["north", "east", "west", "south"] as Facing[]) {
        const candidate = this.robotFacing(moved(player.tile, facing));
        if (candidate) {
          player.face(facing);
          target = moved(player.tile, facing);
          robot = candidate;
          break;
        }
      }
    }
    const struck = robot;
    const front = target;
    player.crackWhip(() => {
      let impact: { x: number; y: number };
      if (struck && this.robots.get(struck.session.id) === struck) {
        impact = { x: struck.x, y: struck.y + 70 };
        struck.whipped(this.now);
      } else {
        const p = positionOf(front);
        impact = { x: p.x, y: p.y + 50 };
      }
      this.effects.push({ kind: "crack", x: impact.x, y: impact.y, start: this.now });
      this.effects.push({ kind: "label", x: impact.x + 26, y: impact.y + 18, start: this.now, text: crackLabel() });
      this.shakeStart = this.now;
      const callbacks = this.host.callbacks();
      callbacks.onSound("whip");
      callbacks.onWhip(struck?.session ?? null);
    });
  }

  interact(): void {
    const interaction = interactionAt(this.room, moved(this.player.tile, this.player.facing));
    if (interaction) this.trigger(interaction);
  }

  private trigger(interaction: TileInteraction): void {
    const callbacks = this.host.callbacks();
    let session: AgentSession | null = null;
    if (interaction.kind === "robot") {
      const robot = this.robotAtSlot(interaction.slot);
      if (!robot) {
        callbacks.onInteract("robot", null);
        return;
      }
      session = robot.session;
      this.talkingRobot = robot;
      robot.turn("south");
    }
    this.heldKeys = [];
    this.tappedKey = null;
    this.path = [];
    this.arrival = null;
    this.player.stopWalking();
    callbacks.onInteract(interaction.kind, session);
  }

  handleKeyDown(event: KeyboardEvent): boolean {
    if (event.metaKey || event.ctrlKey || event.altKey) return false;
    this.running = event.shiftKey;
    if (this.host.inputBlocked()) return false;
    const direction = DIRECTION_CODES[event.code];
    if (direction) {
      if (!this.heldKeys.includes(direction)) {
        this.heldKeys.push(direction);
        this.tappedKey = direction;
      }
      return true;
    }
    if (event.repeat) return INTERACT_CODES.has(event.code) || MENU_CODES.has(event.code) || event.code === WHIP_CODE;
    if (INTERACT_CODES.has(event.code)) {
      this.interact();
      return true;
    }
    if (MENU_CODES.has(event.code)) {
      this.host.callbacks().onMenu();
      return true;
    }
    if (event.code === WHIP_CODE) {
      this.crackWhip();
      return true;
    }
    return false;
  }

  handleKeyUp(event: KeyboardEvent): void {
    this.running = event.shiftKey;
    const direction = DIRECTION_CODES[event.code];
    if (direction) this.heldKeys = this.heldKeys.filter((held) => held !== direction);
  }

  private screenToTile(cssX: number, cssY: number): Tile {
    const x = this.camera.x + (cssX - this.viewport.cssWidth / 2) / this.zoom;
    const y = this.camera.y - (cssY - this.viewport.cssHeight / 2) / this.zoom;
    return { c: Math.floor(x / TILE_SIZE), r: Math.floor(y / TILE_SIZE) };
  }

  private exitAt(t: Tile): Exit | null {
    const below = { c: t.c, r: t.r - 1 };
    for (const exit of this.room.exits) {
      const beyond = moved(exit.trigger, exit.direction);
      if (sameTile(t, beyond) || sameTile(below, beyond)) return exit;
      if (this.room.doormat && sameTile(t, exit.trigger) && sameTile(this.room.doormat, exit.trigger)) return exit;
    }
    return null;
  }

  isClickable(cssX: number, cssY: number): boolean {
    const t = this.screenToTile(cssX, cssY);
    return interactionAt(this.room, t) !== null || interactionAt(this.room, { c: t.c, r: t.r - 1 }) !== null || this.exitAt(t) !== null;
  }

  handlePointerDown(cssX: number, cssY: number): void {
    if (this.host.inputBlocked() || this.transitioning) return;
    const t = this.screenToTile(cssX, cssY);
    const target = interactionTargetAt(this.room, t) ?? interactionTargetAt(this.room, { c: t.c, r: t.r - 1 });
    if (target) {
      this.walkToInteraction(target.interaction, target.cells);
      return;
    }
    const exit = this.exitAt(t);
    if (exit) {
      this.walkTo([{ tile: exit.trigger, arrival: { kind: "exit", exit } }]);
      return;
    }
    if (isWalkable(this.room, t)) this.walkTo([{ tile: t, arrival: null }]);
  }

  private walkToInteraction(interaction: TileInteraction, cells: Tile[]): void {
    const goals: Goal[] = [];
    for (const cell of cells) {
      for (const facing of Object.keys(FACING_DELTA) as Facing[]) {
        const delta = FACING_DELTA[facing];
        const stand = { c: cell.c - delta.dx, r: cell.r - delta.dy };
        if (!isWalkable(this.room, stand)) continue;
        if (!sameInteraction(interactionAt(this.room, cell), interaction)) continue;
        goals.push({ tile: stand, arrival: { kind: "interact", facing, interaction } });
      }
    }
    if (!this.walkTo(goals)) this.trigger(interaction);
  }

  private walkTo(goals: Goal[]): boolean {
    if (!goals.length) return false;
    const start = this.player.tile;
    const goalByKey = new Map<string, Goal>();
    for (const goal of goals) if (!goalByKey.has(tileKey(goal.tile))) goalByKey.set(tileKey(goal.tile), goal);
    const startGoal = goalByKey.get(tileKey(start));
    if (startGoal) {
      this.path = [];
      this.arrival = startGoal.arrival;
      if (!this.arrival && !this.player.isMoving) this.player.stopWalking();
      return true;
    }
    const previous = new Map<string, Tile | null>([[tileKey(start), null]]);
    const queue: Tile[] = [start];
    let found: Goal | null = null;
    while (queue.length && !found) {
      const current = queue.shift();
      if (!current) break;
      for (const facing of ["north", "south", "east", "west"] as Facing[]) {
        const next = moved(current, facing);
        const key = tileKey(next);
        if (previous.has(key) || !isWalkable(this.room, next)) continue;
        previous.set(key, current);
        const goal = goalByKey.get(key);
        if (goal) {
          found = goal;
          break;
        }
        queue.push(next);
      }
    }
    if (!found) return false;
    const path: Tile[] = [];
    for (let cursor: Tile | null = found.tile; cursor && !sameTile(cursor, start); cursor = previous.get(tileKey(cursor)) ?? null) path.unshift(cursor);
    this.path = path;
    this.arrival = found.arrival;
    return true;
  }

  private refreshInboxBadge(): void {
    this.inboxBadge = null;
    const tray = this.room.props.find((p) => p.interaction === "inbox");
    if (!tray) return;
    const source = image(tray.texture);
    if (!source) return;
    const x = tray.x * TILE_SIZE;
    const y = tray.baseY * TILE_SIZE + 8;
    this.inboxBadge = { x: x + 18, y: y + source.height - 4, z: depth(y) + 1 };
  }

  private renderStatic(): void {
    const room = this.room;
    const width = room.cols * TILE_SIZE;
    const height = roomRows(room) * TILE_SIZE;
    const canvas = this.staticLayer;
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, width, height);
    ctx.setTransform(1, 0, 0, 1, 0, height);
    for (let c = 0; c < room.cols; c++) {
      for (let r = 0; r < room.walkRows; r++) {
        const variant = (((c * 73 + r * 151 + c * r * 7) % 97) % 4);
        const texture = room.floor === "parquet" ? parquet(variant) : carpet(variant);
        drawSprite(ctx, { sprite: texture, x: c * TILE_SIZE, y: r * TILE_SIZE, anchorX: 0, anchorY: 0 });
      }
    }
    const wallImage: Sprite | null = image(room.wallTexture) ?? (hasFailed(room.wallTexture) ? wall(room.id) : null);
    if (wallImage) {
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, -(room.walkRows * TILE_SIZE + wallImage.height), width, wallImage.height);
      ctx.clip();
      for (let x = 0; x < width; x += wallImage.width) {
        drawSprite(ctx, { sprite: wallImage, x, y: room.walkRows * TILE_SIZE, anchorX: 0, anchorY: 0 });
      }
      ctx.restore();
    }
    for (const p of room.props.filter((prop) => prop.onWall)) {
      const source = image(p.texture);
      if (source) drawSprite(ctx, { sprite: source, x: p.x * TILE_SIZE, y: p.baseY * TILE_SIZE, anchorX: 0.5, anchorY: 0 });
    }
    if (room.doormat) drawSprite(ctx, { sprite: doormat(), x: room.doormat.c * TILE_SIZE + TILE_SIZE / 2, y: 4, anchorX: 0.5, anchorY: 0 });
    for (const p of room.props.filter((prop) => prop.flat)) {
      const source = image(p.texture);
      if (source) drawSprite(ctx, { sprite: source, x: p.x * TILE_SIZE, y: p.baseY * TILE_SIZE, anchorX: 0.5, anchorY: 0 });
    }
    for (const p of room.props.filter((prop) => !prop.flat && !prop.onWall)) {
      const source = image(p.texture);
      if (!source) continue;
      const y = p.baseY * TILE_SIZE + 8;
      drawSprite(ctx, { sprite: shadow(Math.trunc(source.width * 0.8), 14), x: p.x * TILE_SIZE, y: y + 6 });
    }
    for (const desk of room.desks) {
      const y = desk.deskTile.r * TILE_SIZE + 10;
      drawSprite(ctx, { sprite: shadow(110, 14), x: deskCenterX(desk) * TILE_SIZE, y: y + 6 });
    }
    this.staticDirty = false;
  }

  private collectWorld(list: DrawList, offsetX: number, offsetY: number): void {
    const room = this.room;
    const width = room.cols * TILE_SIZE;
    const height = roomRows(room) * TILE_SIZE;
    const layer = this.staticLayer;
    list.push(-1000, (ctx) => ctx.drawImage(layer, offsetX, -(height + offsetY)));
    for (const [x, w] of [
      [-8, 8],
      [width, 8],
    ]) {
      list.sprite(9_999, { sprite: edge(w, height + 8), x: x + offsetX, y: -8 + offsetY, anchorX: 0, anchorY: 0 });
    }
    list.sprite(9_999, { sprite: edge(width + 16, 8), x: -8 + offsetX, y: -8 + offsetY, anchorX: 0, anchorY: 0 });

    for (const p of room.props) {
      if (p.flat || p.onWall) continue;
      const source = image(p.texture);
      if (!source) continue;
      const y = p.baseY * TILE_SIZE + 8;
      const anchorY = bottomPadding(p.texture) / Math.max(source.height, 1);
      list.sprite(depth(y), { sprite: source, x: p.x * TILE_SIZE + offsetX, y: y + offsetY, anchorX: 0.5, anchorY });
    }
    const deskImage = image("objects/desk_worker.png");
    if (deskImage) {
      const anchorY = bottomPadding("objects/desk_worker.png") / Math.max(deskImage.height, 1);
      for (const desk of room.desks) {
        const y = desk.deskTile.r * TILE_SIZE + 10;
        list.sprite(depth(y), { sprite: deskImage, x: deskCenterX(desk) * TILE_SIZE + offsetX, y: y + offsetY, anchorX: 0.5, anchorY });
      }
    }
    if (this.inboxBadge && this.inboxCount > 0) {
      const t = (this.now - this.inboxBounceStart) % 1.2;
      const bounce = t < 0.2 ? (t / 0.2) * 5 : t < 0.4 ? (1 - (t - 0.2) / 0.2) * 5 : 0;
      const badge = this.inboxBadge;
      list.sprite(badge.z, { sprite: exclamation(), x: badge.x + offsetX, y: badge.y + bounce + offsetY, anchorX: 0.5, anchorY: 0, scale: 2 });
    }
    for (const robot of this.robots.values()) robot.draw(list, this.now, offsetX, offsetY);
    for (const robot of this.leavingRobots) robot.draw(list, this.now, offsetX, offsetY);
    this.player.draw(list, this.now, offsetX, offsetY);
    this.collectEffects(list, offsetX, offsetY);
  }

  private collectEffects(list: DrawList, offsetX: number, offsetY: number): void {
    this.effects = this.effects.filter((effect) => {
      const elapsed = this.now - effect.start;
      switch (effect.kind) {
        case "smoke":
          return smokePuff(list, effect.x + offsetX, effect.y + offsetY, effect.z, elapsed);
        case "crack": {
          const index = Math.floor(elapsed / 0.05);
          if (index >= 5) return false;
          list.sprite(20_000, { sprite: crack(index), x: effect.x + offsetX, y: effect.y + offsetY, scale: 2 });
          return true;
        }
        case "label": {
          if (elapsed >= 0.6) return false;
          const rise = Math.min(1, elapsed / 0.5) * 14;
          const alpha = elapsed < 0.3 ? 1 : Math.max(0, 1 - (elapsed - 0.3) / 0.3);
          const x = effect.x + offsetX;
          const y = effect.y + rise + offsetY;
          list.push(20_001, (ctx) => {
            ctx.globalAlpha = alpha;
            ctx.font = `900 18px ${ROUNDED_FONT}`;
            ctx.textAlign = "center";
            ctx.textBaseline = "alphabetic";
            ctx.fillStyle = CRACK_COLOR;
            ctx.fillText(effect.text, x, -y);
            ctx.globalAlpha = 1;
            ctx.textAlign = "left";
          });
          return true;
        }
      }
    });
  }

  render(ctx: CanvasRenderingContext2D): void {
    if (this.staticDirty) this.renderStatic();
    const { dpr } = this.viewport;
    const canvasWidth = ctx.canvas.width;
    const canvasHeight = ctx.canvas.height;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = "source-over";
    ctx.fillStyle = BACKGROUND;
    ctx.fillRect(0, 0, canvasWidth, canvasHeight);
    const scale = this.zoom * dpr;
    const shake = this.shakeStart === null ? { x: 0, y: 0 } : sampleKeyframes(SHAKE, this.now - this.shakeStart);
    if (this.shakeStart !== null && this.now - this.shakeStart > 0.1) this.shakeStart = null;
    ctx.setTransform(scale, 0, 0, scale, Math.round(canvasWidth / 2 - this.camera.x * scale), Math.round(canvasHeight / 2 + this.camera.y * scale));
    ctx.imageSmoothingEnabled = false;
    const list = new DrawList();
    this.collectWorld(list, shake.x, shake.y);
    list.flush(ctx);
    const fade = this.faderAlpha();
    if (fade > 0) {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.globalAlpha = fade;
      ctx.fillStyle = "#000";
      ctx.fillRect(0, 0, canvasWidth, canvasHeight);
      ctx.globalAlpha = 1;
    }
  }
}
