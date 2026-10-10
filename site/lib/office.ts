import { HARNESS_COLOR, HARNESS_ORDER, ROBOT_SCALE, SHEETS, STILLS, type Dir, type SheetName, sheetUrl, stillUrl } from "./sprites";
import { PROP_INFO, WHIP_LINES, type PropInfo, type Robot, type RobotState } from "./staff";

export const WORLD_W = 1152;
export const WORLD_H = 640;
const WALL_BOTTOM = 128;
const FLOOR_TOP = 206;
const FLOOR_BOTTOM = 628;
const CELL = 16;
const MIN_SCALE = 0.6;
const BOSS_HALF_W = 14;
const BOSS_HALF_H = 6;
const TALK_RANGE = 58;

export type Target = { kind: "robot"; robot: Robot } | { kind: "prop"; prop: PropInfo };

export type Callbacks = {
  onCounts: (counts: Record<RobotState, number>) => void;
  onTalk: (target: Target) => void;
  onActive: (active: boolean) => void;
  onToast: (text: string) => void;
};

type Rect = { x: number; y: number; w: number; h: number };
type Point = { x: number; y: number };

type PropDef = {
  id: string;
  img: string;
  x: number;
  base: number;
  bottom: number;
  wall?: boolean;
  flat?: boolean;
  spot?: Point;
  collider?: Rect;
};

type Desk = { x: number; base: number };

type Sparkle = { x: number; y: number; vx: number; vy: number; life: number; color: string };
type Crack = { x: number; y: number; t: number };
type Whip = { t: number; target: Robot | null; struck: boolean };

const OBJECT_BOTTOM: Record<string, number> = {
  archive_cabinet: 99, bookshelf: 117, coffee_machine: 88, desk_worker: 76, intray: 84,
  server_rack: 108, sofa: 61, wall_screen: 81, water_cooler: 80, whiteboard: 104, window_wall: 77,
  door: 120, plant: 76, rug: 57,
};

const WINDOWS = [320, 832];

const DESKS: Desk[] = [
  { x: 192, base: 336 }, { x: 448, base: 336 }, { x: 704, base: 336 }, { x: 960, base: 336 },
  { x: 192, base: 516 }, { x: 448, base: 516 }, { x: 704, base: 516 }, { x: 960, base: 516 },
];

const PROPS: PropDef[] = [
  { id: "window", img: "window_wall", x: 320, base: 104, bottom: 77, wall: true, spot: { x: 320, y: 214 } },
  { id: "screen", img: "wall_screen", x: 576, base: 112, bottom: 81, wall: true, spot: { x: 576, y: 214 } },
  { id: "window", img: "window_wall", x: 832, base: 104, bottom: 77, wall: true, spot: { x: 832, y: 214 } },
  { id: "door", img: "door", x: 704, base: 134, bottom: 120, wall: true, spot: { x: 704, y: 216 } },
  { id: "servers", img: "server_rack", x: 40, base: 200, bottom: 108, spot: { x: 66, y: 216 } },
  { id: "servers", img: "server_rack", x: 92, base: 200, bottom: 108, spot: { x: 66, y: 216 } },
  { id: "bookshelf", img: "bookshelf", x: 190, base: 200, bottom: 117, spot: { x: 190, y: 216 } },
  { id: "archive", img: "archive_cabinet", x: 250, base: 196, bottom: 99, spot: { x: 250, y: 216 } },
  { id: "whiteboard", img: "whiteboard", x: 450, base: 200, bottom: 104, spot: { x: 450, y: 216 } },
  { id: "plant", img: "plant", x: 790, base: 198, bottom: 76, spot: { x: 790, y: 216 } },
  { id: "cooler", img: "water_cooler", x: 930, base: 192, bottom: 80, spot: { x: 930, y: 216 } },
  { id: "coffee", img: "coffee_machine", x: 1000, base: 194, bottom: 88, spot: { x: 1000, y: 216 } },
  { id: "rug", img: "rug", x: 320, base: 452, bottom: 57, flat: true },
  { id: "rug", img: "rug", x: 576, base: 452, bottom: 57, flat: true },
  { id: "rug", img: "rug", x: 832, base: 452, bottom: 57, flat: true },
  { id: "rug", img: "rug", x: 576, base: 636, bottom: 57, flat: true },
  { id: "intray", img: "intray", x: 420, base: 624, bottom: 84, spot: { x: 420, y: 584 }, collider: { x: 398, y: 596, w: 44, h: 30 } },
  { id: "plant", img: "plant", x: 1120, base: 628, bottom: 76, spot: { x: 1100, y: 584 }, collider: { x: 1100, y: 604, w: 40, h: 26 } },
  { id: "sofa", img: "sofa", x: 1010, base: 626, bottom: 61, spot: { x: 1010, y: 578 }, collider: { x: 976, y: 596, w: 68, h: 32 } },
];

const WHIP_FRAME = 0.055;
const WHIP_FRAMES = 8;
const BOOST_SECONDS = 7;
const PLAQUE_W = 128;
const PLAQUE_H = 30;
const ROUNDED = "ui-rounded, 'SF Pro Rounded', 'Nunito', system-ui, sans-serif";
const STATUS_COLOR: Record<RobotState, string> = { working: "#4CD18A", waiting: "#FF9A2E", done: "#A8B0BD" };

const SHADE_SCALE = 0.25;
const FLOOR_URL = "/assets/tiles/carpet_openspace.png";
const WALL_URL = "/assets/walls/wall_openspace.png";
const ATTRACT_PAUSE = 1.6;
const IDLE_BEFORE_ATTRACT = 9;

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}

function intersects(a: Rect, b: Rect) {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

export class Office {
  private ctx: CanvasRenderingContext2D;
  private shade = document.createElement("canvas");
  private images = new Map<string, HTMLImageElement>();
  private colliders: Rect[] = [];
  private blocked: Uint8Array;
  private gridW = Math.ceil(WORLD_W / CELL);
  private gridH = Math.ceil(WORLD_H / CELL);
  private boss = { x: 576, y: 604, dir: "north" as Dir, moving: false, anim: 0 };
  private keys = new Set<string>();
  private path: Point[] = [];
  private pendingTalk: Target | null = null;
  private attract = true;
  private attractWait = 0.6;
  private attractIndex = 0;
  private idle = 0;
  private time = 0;
  private last = 0;
  private raf = 0;
  private running = false;
  private visible = true;
  private scale = 1;
  private cam = { x: 0, y: 0, w: WORLD_W, h: WORLD_H };
  private hover: Target | null = null;
  private nearest: Target | null = null;
  private sparkles: Sparkle[] = [];
  private glows = new Map<string, HTMLCanvasElement>();
  private hearts = new Map<string, number>();
  private boosts = new Map<string, number>();
  private jolts = new Map<string, number>();
  private cracks: Crack[] = [];
  private whip: Whip | null = null;
  private shakeUntil = 0;
  private night = true;
  private dialogOpen = false;
  private active = false;
  private ready = false;
  private coarse = window.matchMedia("(pointer: coarse)").matches;
  private resizeObserver: ResizeObserver;
  private intersection: IntersectionObserver;
  private disposers: (() => void)[] = [];

  constructor(private canvas: HTMLCanvasElement, private robots: Robot[], private cb: Callbacks, private font: string) {
    this.ctx = canvas.getContext("2d")!;
    this.shade.width = WORLD_W * SHADE_SCALE;
    this.shade.height = WORLD_H * SHADE_SCALE;
    this.blocked = new Uint8Array(this.gridW * this.gridH);
    this.buildColliders();
    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(canvas);
    this.intersection = new IntersectionObserver(([entry]) => {
      this.visible = entry.isIntersecting;
      if (this.visible) this.kick();
    });
    this.intersection.observe(canvas);
    this.bindInput();
    this.load();
  }

  destroy() {
    this.running = false;
    cancelAnimationFrame(this.raf);
    this.resizeObserver.disconnect();
    this.intersection.disconnect();
    this.disposers.forEach((d) => d());
  }

  setNight(on: boolean) {
    this.night = on;
    if (!this.running && this.ready) this.draw();
  }

  setDialogOpen(open: boolean) {
    this.dialogOpen = open;
    if (open) {
      this.keys.clear();
      this.boss.moving = false;
    }
    this.idle = 0;
  }

  setRobotState(id: string, state: RobotState) {
    const robot = this.robots.find((r) => r.id === id);
    if (!robot) return;
    robot.state = state;
    const desk = DESKS[robot.desk];
    this.burst(desk.x, desk.base - 90, HARNESS_COLOR[robot.harness]);
    this.hearts.set(robot.id, this.time + 2.2);
    this.emitCounts();
  }

  crackWhip() {
    if (this.whip || this.dialogOpen || !this.ready) return;
    this.path = [];
    this.pendingTalk = null;
    this.idle = 0;
    this.boss.moving = false;
    let target: Robot | null = null;
    let best = TALK_RANGE + 24;
    for (const robot of this.robots) {
      const d = DESKS[robot.desk];
      const dist = Math.hypot(d.x - this.boss.x, d.base + 30 - this.boss.y);
      if (dist < best) {
        best = dist;
        target = robot;
      }
    }
    if (target) this.boss.dir = "north";
    this.whip = { t: 0, target, struck: false };
    this.kick();
  }

  private strike(whip: Whip) {
    whip.struck = true;
    const reach = { south: [0, 46], north: [0, -86], east: [70, -40], west: [-70, -40] }[this.boss.dir];
    const robot = whip.target;
    const impact = robot ? { x: DESKS[robot.desk].x, y: this.robotHead(robot) + 30 } : { x: this.boss.x + reach[0], y: this.boss.y + reach[1] };
    this.cracks.push({ ...impact, t: 0 });
    this.shakeUntil = this.time + 0.16;
    if (!robot) return;
    this.jolts.set(robot.id, this.time + 0.35);
    if (robot.state === "working") this.boosts.set(robot.id, this.time + BOOST_SECONDS);
    if (this.attract) return;
    this.cb.onToast(WHIP_LINES[robot.state](robot.name));
    if (robot.state === "waiting") {
      const target: Target = { kind: "robot", robot };
      setTimeout(() => this.cb.onTalk(target), 650);
    }
  }

  takeControl() {
    if (this.attract) {
      this.path = [];
      this.pendingTalk = null;
    }
    this.attract = false;
    this.idle = 0;
    this.setActive(true);
  }

  private setActive(active: boolean) {
    if (this.active === active) return;
    this.active = active;
    this.cb.onActive(active);
  }

  private async load() {
    const objects = Object.keys(OBJECT_BOTTOM).map((n) => `/assets/objects/${n}.png`);
    const sheets = (Object.keys(SHEETS) as SheetName[]).map(sheetUrl);
    const stills = HARNESS_ORDER.map((h) => stillUrl(h)).concat(stillUrl("boss"));
    const bossStills = (["north", "east", "west"] as const).map((d) => stillUrl("boss", d));
    const emotes = ["alert", "sleep", "heart", "dots", "sweat"].map((e) => `/assets/emotes/${e}.png`);
    const all = [...objects, ...sheets, ...stills, ...bossStills, ...emotes, FLOOR_URL, WALL_URL];
    await Promise.all(all.map(async (src) => this.images.set(src, await loadImage(src))));
    await document.fonts.ready;
    this.ready = true;
    this.emitCounts();
    this.resize();
    this.kick();
  }

  private kick() {
    if (this.running || !this.ready) return;
    this.running = true;
    this.last = performance.now();
    const tick = (now: number) => {
      if (!this.running) return;
      const dt = Math.min(0.05, (now - this.last) / 1000);
      this.last = now;
      this.update(dt);
      this.draw();
      if (this.visible) this.raf = requestAnimationFrame(tick);
      else this.running = false;
    };
    this.raf = requestAnimationFrame(tick);
  }

  private emitCounts() {
    const counts: Record<RobotState, number> = { working: 0, waiting: 0, done: 0 };
    this.robots.forEach((r) => counts[r.state]++);
    this.cb.onCounts(counts);
  }

  private resize() {
    const rect = this.canvas.getBoundingClientRect();
    if (!rect.width) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(rect.width * dpr);
    this.canvas.height = Math.round(rect.height * dpr);
    const fit = Math.max(rect.width / WORLD_W, MIN_SCALE);
    this.scale = fit * dpr;
    this.cam.w = Math.min(WORLD_W, this.canvas.width / this.scale);
    this.cam.h = Math.min(WORLD_H, this.canvas.height / this.scale);
    if (!this.running && this.ready) this.draw();
  }

  private buildColliders() {
    DESKS.forEach((d) => this.colliders.push({ x: d.x - 64, y: d.base - 60, w: 128, h: 66 }));
    PROPS.forEach((p) => p.collider && this.colliders.push(p.collider));
    for (let gy = 0; gy < this.gridH; gy++) {
      for (let gx = 0; gx < this.gridW; gx++) {
        const cx = gx * CELL + CELL / 2;
        const cy = gy * CELL + CELL / 2;
        this.blocked[gy * this.gridW + gx] = this.free(cx, cy) ? 0 : 1;
      }
    }
  }

  private free(x: number, y: number) {
    if (y < FLOOR_TOP || y > FLOOR_BOTTOM || x < 24 || x > WORLD_W - 24) return false;
    const box = { x: x - BOSS_HALF_W, y: y - BOSS_HALF_H, w: BOSS_HALF_W * 2, h: BOSS_HALF_H * 2 };
    return !this.colliders.some((c) => intersects(box, c));
  }

  private bindInput() {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
      const isArrow = key.startsWith("Arrow");
      const isWasd = "wasd".includes(key) && key.length === 1;
      const target = e.target as HTMLElement | null;
      if (target && /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName)) return;
      if (this.dialogOpen) return;
      if (key === "Escape" && this.active) {
        this.setActive(false);
        this.canvas.parentElement?.blur();
        return;
      }
      if ((isArrow || key === "Shift" || key === " " || key === "Enter") && !this.active) return;
      if ((isWasd || key === "f") && !this.visible) return;
      if (key === "f") {
        e.preventDefault();
        if (!this.active) this.takeControl();
        this.crackWhip();
        return;
      }
      if (isArrow || isWasd || key === "Shift") {
        if (isArrow || isWasd) e.preventDefault();
        if (!this.active) this.takeControl();
        this.attract = false;
        this.path = [];
        this.pendingTalk = null;
        this.idle = 0;
        this.keys.add(key);
        this.kick();
      } else if (key === " " || key === "Enter") {
        e.preventDefault();
        if (this.nearest) this.talk(this.nearest);
      }
    };
    const onKeyUp = (e: KeyboardEvent) => {
      const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
      this.keys.delete(key);
    };
    const onBlur = () => this.keys.clear();
    const toWorld = (e: PointerEvent): Point => {
      const rect = this.canvas.getBoundingClientRect();
      const dpr = this.canvas.width / rect.width;
      return {
        x: this.cam.x + ((e.clientX - rect.left) * dpr) / this.scale,
        y: this.cam.y + ((e.clientY - rect.top) * dpr) / this.scale,
      };
    };
    const onPointerDown = (e: PointerEvent) => {
      if (this.dialogOpen) return;
      this.takeControl();
      const p = toWorld(e);
      const hit = this.hitTest(p);
      if (hit) {
        const spot = this.spotFor(hit);
        if (Math.hypot(spot.x - this.boss.x, spot.y - this.boss.y) < TALK_RANGE) {
          this.talk(hit);
          return;
        }
        this.walkTo(spot, hit);
      } else {
        this.walkTo(p, null);
      }
      this.kick();
    };
    const onPointerMove = (e: PointerEvent) => {
      this.hover = this.hitTest(toWorld(e));
      this.canvas.style.cursor = this.hover ? "pointer" : "default";
    };
    const onPointerLeave = () => {
      this.hover = null;
    };
    const onDocPointer = (e: PointerEvent) => {
      if (!this.canvas.parentElement?.contains(e.target as Node)) this.setActive(false);
    };
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    window.addEventListener("blur", onBlur);
    document.addEventListener("pointerdown", onDocPointer);
    this.canvas.addEventListener("pointerdown", onPointerDown);
    this.canvas.addEventListener("pointermove", onPointerMove);
    this.canvas.addEventListener("pointerleave", onPointerLeave);
    this.disposers.push(
      () => window.removeEventListener("keydown", onKeyDown),
      () => window.removeEventListener("keyup", onKeyUp),
      () => window.removeEventListener("blur", onBlur),
      () => document.removeEventListener("pointerdown", onDocPointer),
      () => this.canvas.removeEventListener("pointerdown", onPointerDown),
      () => this.canvas.removeEventListener("pointermove", onPointerMove),
      () => this.canvas.removeEventListener("pointerleave", onPointerLeave),
    );
  }

  private talk(target: Target) {
    const spot = this.spotFor(target);
    const dx = spot.x - this.boss.x;
    if (target.kind === "robot") this.boss.dir = "north";
    else if (Math.abs(dx) > 30) this.boss.dir = dx > 0 ? "east" : "west";
    else this.boss.dir = spot.y < this.boss.y + 4 ? "north" : "south";
    this.boss.moving = false;
    this.path = [];
    this.pendingTalk = null;
    this.cb.onTalk(target);
  }

  private hitTest(p: Point): Target | null {
    for (const robot of this.robots) {
      const d = DESKS[robot.desk];
      if (p.x > d.x - 66 && p.x < d.x + 66 && p.y > d.base - 150 && p.y < d.base + 4) return { kind: "robot", robot };
    }
    for (const prop of PROPS) {
      if (!prop.spot) continue;
      const img = this.images.get(`/assets/objects/${prop.img}.png`);
      if (!img) continue;
      const left = prop.x - img.width / 2;
      const top = prop.base - prop.bottom;
      if (p.x > left + 10 && p.x < left + img.width - 10 && p.y > top + 10 && p.y < prop.base) {
        return { kind: "prop", prop: PROP_INFO[prop.id] };
      }
    }
    return null;
  }

  private spotFor(target: Target): Point {
    if (target.kind === "robot") {
      const d = DESKS[target.robot.desk];
      return { x: d.x, y: d.base + 30 };
    }
    const prop = PROPS.find((p) => p.id === target.prop.id)!;
    return prop.spot ?? { x: prop.x, y: prop.base + 20 };
  }

  private walkTo(goal: Point, talk: Target | null) {
    const path = this.findPath({ x: this.boss.x, y: this.boss.y }, goal);
    this.path = path;
    this.pendingTalk = talk;
  }

  private findPath(from: Point, to: Point): Point[] {
    const gw = this.gridW;
    const toCell = (p: Point) => ({ x: Math.max(0, Math.min(gw - 1, Math.floor(p.x / CELL))), y: Math.max(0, Math.min(this.gridH - 1, Math.floor(p.y / CELL))) });
    const start = toCell(from);
    let goal = toCell(to);
    if (this.blocked[goal.y * gw + goal.x]) {
      let best: { x: number; y: number } | null = null;
      let bestD = Infinity;
      for (let r = 1; r < 8 && !best; r++) {
        for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
          const x = goal.x + dx, y = goal.y + dy;
          if (x < 0 || y < 0 || x >= gw || y >= this.gridH || this.blocked[y * gw + x]) continue;
          const d = dx * dx + dy * dy;
          if (d < bestD) { bestD = d; best = { x, y }; }
        }
      }
      if (!best) return [];
      goal = best;
      to = { x: goal.x * CELL + CELL / 2, y: goal.y * CELL + CELL / 2 };
    }
    const total = gw * this.gridH;
    const g = new Float32Array(total).fill(Infinity);
    const came = new Int32Array(total).fill(-1);
    const closed = new Uint8Array(total);
    const open: number[] = [];
    const h = (i: number) => Math.hypot((i % gw) - goal.x, Math.floor(i / gw) - goal.y);
    const s = start.y * gw + start.x;
    const gi = goal.y * gw + goal.x;
    g[s] = 0;
    open.push(s);
    const f = new Float32Array(total).fill(Infinity);
    f[s] = h(s);
    while (open.length) {
      let bi = 0;
      for (let i = 1; i < open.length; i++) if (f[open[i]] < f[open[bi]]) bi = i;
      const cur = open.splice(bi, 1)[0];
      if (cur === gi) break;
      closed[cur] = 1;
      const cx = cur % gw, cy = Math.floor(cur / gw);
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        if (!dx && !dy) continue;
        const nx = cx + dx, ny = cy + dy;
        if (nx < 0 || ny < 0 || nx >= gw || ny >= this.gridH) continue;
        const ni = ny * gw + nx;
        if (closed[ni] || (this.blocked[ni] && ni !== s)) continue;
        if (dx && dy && (this.blocked[cy * gw + nx] || this.blocked[ny * gw + cx])) continue;
        const cost = g[cur] + (dx && dy ? 1.414 : 1);
        if (cost < g[ni]) {
          g[ni] = cost;
          f[ni] = cost + h(ni);
          came[ni] = cur;
          if (!open.includes(ni)) open.push(ni);
        }
      }
    }
    if (came[gi] === -1 && gi !== s) return [];
    const cells: Point[] = [];
    for (let i = gi; i !== -1 && i !== s; i = came[i]) cells.unshift({ x: (i % gw) * CELL + CELL / 2, y: Math.floor(i / gw) * CELL + CELL / 2 });
    cells[cells.length - 1] = to;
    const smooth: Point[] = [];
    let anchor = from;
    for (let i = 0; i < cells.length; i++) {
      const next = cells[i + 1];
      if (next && this.clearLine(anchor, next)) continue;
      smooth.push(cells[i]);
      anchor = cells[i];
    }
    return smooth;
  }

  private clearLine(a: Point, b: Point) {
    const steps = Math.ceil(Math.hypot(b.x - a.x, b.y - a.y) / 6);
    for (let i = 1; i <= steps; i++) {
      const t = i / steps;
      if (!this.free(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)) return false;
    }
    return true;
  }

  private update(dt: number) {
    this.time += dt;
    const boss = this.boss;
    let vx = 0, vy = 0;
    if (!this.dialogOpen) {
      if (this.keys.has("ArrowLeft") || this.keys.has("a")) vx -= 1;
      if (this.keys.has("ArrowRight") || this.keys.has("d")) vx += 1;
      if (this.keys.has("ArrowUp") || this.keys.has("w")) vy -= 1;
      if (this.keys.has("ArrowDown") || this.keys.has("s")) vy += 1;
    }
    if (this.whip) {
      this.whip.t += dt;
      if (!this.whip.struck && this.whip.t >= WHIP_FRAME * WHIP_FRAMES * 0.6) this.strike(this.whip);
      if (this.whip.t >= WHIP_FRAME * WHIP_FRAMES + 0.08) this.whip = null;
      vx = 0;
      vy = 0;
    }
    this.cracks = this.cracks.filter((c) => (c.t += dt) < 0.7);
    const run = this.keys.has("Shift");
    let speed = run ? 290 : 170;

    if (!vx && !vy && this.path.length && !this.dialogOpen) {
      const next = this.path[0];
      const dx = next.x - boss.x, dy = next.y - boss.y;
      const dist = Math.hypot(dx, dy);
      if (dist < 4) {
        this.path.shift();
        if (!this.path.length && this.pendingTalk) {
          const target = this.pendingTalk;
          this.pendingTalk = null;
          if (this.attract) {
            this.faceTarget(target);
            if (target.kind === "robot" && target.robot.state === "working" && Math.random() < 0.5) this.crackWhip();
          }
          else this.talk(target);
        }
      } else {
        vx = dx / dist;
        vy = dy / dist;
        speed = this.attract ? 130 : 210;
      }
    }

    if (vx || vy) {
      const len = Math.hypot(vx, vy);
      vx /= len;
      vy /= len;
      const nx = boss.x + vx * speed * dt;
      const ny = boss.y + vy * speed * dt;
      if (this.free(nx, boss.y)) boss.x = nx;
      if (this.free(boss.x, ny)) boss.y = ny;
      boss.dir = Math.abs(vx) > Math.abs(vy) * 1.1 ? (vx > 0 ? "east" : "west") : vy > 0 ? "south" : "north";
      boss.moving = true;
      boss.anim += dt * (speed / 170) * 11;
    } else {
      boss.moving = false;
    }

    if (!this.attract && !this.dialogOpen && !boss.moving) {
      this.idle += dt;
      if (this.idle > IDLE_BEFORE_ATTRACT && !this.active) this.attract = true;
    }

    if (this.attract && !this.path.length && !this.dialogOpen) {
      this.attractWait -= dt;
      if (this.attractWait <= 0) {
        const stops: Target[] = [
          ...this.robots.map((robot) => ({ kind: "robot", robot }) as Target),
          { kind: "prop", prop: PROP_INFO.screen },
          { kind: "prop", prop: PROP_INFO.whiteboard },
        ];
        const order = [0, 6, 4, 1, 7, 5, 2, 3];
        const target = stops[order[this.attractIndex % order.length] % stops.length];
        this.attractIndex++;
        this.walkTo(this.spotFor(target), target);
        this.attractWait = ATTRACT_PAUSE;
      }
    }

    this.nearest = null;
    if (!this.dialogOpen && !this.attract) {
      let best = TALK_RANGE;
      const candidates: Target[] = [
        ...this.robots.map((robot) => ({ kind: "robot", robot }) as Target),
        ...PROPS.filter((p) => p.spot).map((p) => ({ kind: "prop", prop: PROP_INFO[p.id] }) as Target),
      ];
      for (const c of candidates) {
        const s = this.spotFor(c);
        const d = Math.hypot(s.x - boss.x, s.y - boss.y);
        if (d < best) { best = d; this.nearest = c; }
      }
    }

    const targetCamX = boss.x - this.cam.w / 2;
    const targetCamY = boss.y - 40 - this.cam.h / 2;
    const clampX = Math.max(0, Math.min(WORLD_W - this.cam.w, targetCamX));
    const clampY = Math.max(0, Math.min(WORLD_H - this.cam.h, targetCamY));
    const k = 1 - Math.pow(0.001, dt);
    this.cam.x += (clampX - this.cam.x) * k;
    this.cam.y += (clampY - this.cam.y) * k;

    this.sparkles = this.sparkles.filter((s) => (s.life -= dt) > 0);
    this.sparkles.forEach((s) => {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vy += 120 * dt;
    });
  }

  private faceTarget(target: Target) {
    const spot = this.spotFor(target);
    this.boss.dir = target.kind === "robot" || spot.y < 260 ? "north" : "south";
  }

  private burst(x: number, y: number, color: string) {
    for (let i = 0; i < 22; i++) {
      const a = Math.random() * Math.PI * 2;
      const v = 60 + Math.random() * 120;
      this.sparkles.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - 90, life: 0.7 + Math.random() * 0.6, color: i % 3 ? "#FFE3A0" : color });
    }
  }

  private img(src: string) {
    return this.images.get(src)!;
  }

  private draw() {
    const ctx = this.ctx;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = "#0E0C1A";
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    const offX = Math.max(0, (this.canvas.width / this.scale - WORLD_W) / 2);
    const offY = Math.max(0, (this.canvas.height / this.scale - WORLD_H) / 2);
    const shaking = this.shakeUntil > this.time;
    const sx = shaking ? Math.round(Math.sin(this.time * 90) * 4) : 0;
    const sy = shaking ? Math.round(Math.cos(this.time * 70) * 2) : 0;
    ctx.setTransform(this.scale, 0, 0, this.scale, (offX - Math.round(this.cam.x) + sx) * this.scale, (offY - Math.round(this.cam.y) + sy) * this.scale);
    ctx.imageSmoothingEnabled = false;

    ctx.drawImage(this.img(FLOOR_URL), 0, WALL_BOTTOM);
    this.drawWall(ctx);
    PROPS.filter((p) => p.flat).forEach((p) => this.drawProp(ctx, p));
    PROPS.filter((p) => p.wall).forEach((p) => this.drawProp(ctx, p));

    type Item = { y: number; draw: () => void };
    const items: Item[] = [];
    PROPS.filter((p) => !p.wall && !p.flat).forEach((p) => items.push({ y: p.base, draw: () => this.drawProp(ctx, p) }));
    DESKS.forEach((d, i) => items.push({ y: d.base, draw: () => this.drawDesk(ctx, d, this.robots.find((r) => r.desk === i)) }));
    this.robots.forEach((r) => items.push({ y: DESKS[r.desk].base - 14, draw: () => this.drawRobot(ctx, r) }));
    items.push({ y: this.boss.y, draw: () => this.drawBoss(ctx) });
    items.sort((a, b) => a.y - b.y).forEach((i) => i.draw());

    if (this.night) this.drawNight(ctx);

    this.robots.forEach((r) => this.drawEmote(ctx, r));
    this.drawCracks(ctx);
    this.drawSparkles(ctx);
    this.drawHighlight(ctx);
  }

  private drawWall(ctx: CanvasRenderingContext2D) {
    const wall = this.img(WALL_URL);
    for (let x = 0; x < WORLD_W; x += wall.width) ctx.drawImage(wall, x, 0);
    ctx.fillStyle = "rgba(20,8,30,0.28)";
    ctx.fillRect(0, WALL_BOTTOM, WORLD_W, 10);
    ctx.fillStyle = "rgba(20,8,30,0.14)";
    ctx.fillRect(0, WALL_BOTTOM + 10, WORLD_W, 6);
  }

  private drawShadow(ctx: CanvasRenderingContext2D, x: number, y: number, w: number) {
    ctx.fillStyle = "rgba(30,12,20,0.28)";
    ctx.beginPath();
    ctx.ellipse(x, y, w / 2, w / 7, 0, 0, Math.PI * 2);
    ctx.fill();
  }

  private drawProp(ctx: CanvasRenderingContext2D, p: PropDef) {
    const img = this.img(`/assets/objects/${p.img}.png`);
    if (!p.wall && !p.flat) this.drawShadow(ctx, p.x, p.base - 2, img.width * 0.55);
    ctx.drawImage(img, Math.round(p.x - img.width / 2), Math.round(p.base - p.bottom));
    if (p.id === "servers") {
      const blink = Math.floor(this.time * 3 + p.x) % 3;
      ctx.fillStyle = blink ? "#4CD18A" : "#4FB3FF";
      ctx.fillRect(p.x - 10, p.base - 70 + blink * 10, 2, 2);
    }
  }

  private drawDesk(ctx: CanvasRenderingContext2D, d: Desk, robot?: Robot) {
    const img = this.img("/assets/objects/desk_worker.png");
    this.drawShadow(ctx, d.x, d.base - 2, 120);
    ctx.drawImage(img, Math.round(d.x - img.width / 2), Math.round(d.base - OBJECT_BOTTOM.desk_worker));
    if (robot) this.drawPlaque(ctx, d, robot);
  }

  private drawPlaque(ctx: CanvasRenderingContext2D, d: Desk, robot: Robot) {
    const x = Math.round(d.x - PLAQUE_W / 2);
    const y = Math.round(d.base - PLAQUE_H + 6);
    ctx.fillStyle = "#2A1840";
    ctx.fillRect(x + 1, y, PLAQUE_W - 2, PLAQUE_H);
    ctx.fillRect(x, y + 1, PLAQUE_W, PLAQUE_H - 2);
    ctx.fillStyle = "#2B2547";
    ctx.fillRect(x + 2, y + 2, PLAQUE_W - 4, PLAQUE_H - 4);
    ctx.fillStyle = "#4E4580";
    ctx.fillRect(x + 2, y + 2, PLAQUE_W - 4, 1);
    ctx.fillStyle = "#1E1A33";
    ctx.fillRect(x + 2, y + PLAQUE_H - 3, PLAQUE_W - 4, 1);
    ctx.fillStyle = STATUS_COLOR[robot.state];
    ctx.fillRect(x + 3, y + 4, 3, PLAQUE_H - 8);
    ctx.fillStyle = "rgba(255,246,236,0.6)";
    ctx.fillRect(x + 3, y + 4, 3, 1);
    ctx.textBaseline = "alphabetic";
    ctx.fillStyle = "#F5B942";
    ctx.font = `800 10px ${ROUNDED}`;
    ctx.fillText(this.fit(ctx, robot.project.toUpperCase(), PLAQUE_W - 18), x + 11, y + 13);
    ctx.fillStyle = "#FFF6EC";
    ctx.font = `600 10px ${ROUNDED}`;
    ctx.fillText(this.fit(ctx, robot.task, PLAQUE_W - 18), x + 11, y + 25);
  }

  private fit(ctx: CanvasRenderingContext2D, text: string, width: number) {
    if (ctx.measureText(text).width <= width) return text;
    let cut = text;
    while (cut.length > 1 && ctx.measureText(`${cut}…`).width > width) cut = cut.slice(0, -1).trimEnd();
    return `${cut}…`;
  }

  private robotSheet(r: Robot): SheetName | null {
    if (r.state === "working") return `robot_${r.harness}_typing_south` as SheetName;
    if (r.state === "waiting") return `robot_${r.harness}_alert_south` as SheetName;
    return null;
  }

  private robotHead(r: Robot) {
    const d = DESKS[r.desk];
    const scale = ROBOT_SCALE[r.harness];
    const still = STILLS[r.harness];
    return d.base - 14 - (still.foot - still.top) * scale;
  }

  private drawRobot(ctx: CanvasRenderingContext2D, r: Robot) {
    const d = DESKS[r.desk];
    const scale = ROBOT_SCALE[r.harness];
    const feet = d.base - 14;
    const jolt = (this.jolts.get(r.id) ?? 0) > this.time ? Math.round(Math.sin(this.time * 80) * 5) : 0;
    const x = d.x + jolt;
    const sheet = this.robotSheet(r);
    if (sheet) {
      const meta = SHEETS[sheet];
      const boosted = (this.boosts.get(r.id) ?? 0) > this.time;
      const fps = r.state === "working" ? (boosted ? 20 : 9) : 7;
      const frame = Math.floor(this.time * fps + r.desk * 3) % meta.frames;
      const size = meta.size * scale;
      ctx.drawImage(this.img(sheetUrl(sheet)), frame * meta.size, 0, meta.size, meta.size, Math.round(x - size / 2), Math.round(feet - meta.foot * scale), size, size);
    } else {
      const img = this.img(stillUrl(r.harness));
      const still = STILLS[r.harness];
      const size = 128 * scale;
      const breathe = Math.round(Math.sin(this.time * 1.6 + r.desk) * 1);
      ctx.globalAlpha = 0.92;
      ctx.drawImage(img, Math.round(x - size / 2), Math.round(feet - still.foot * scale) + breathe, size, size);
      ctx.globalAlpha = 1;
    }
  }

  private drawBoss(ctx: CanvasRenderingContext2D) {
    const b = this.boss;
    this.drawShadow(ctx, b.x, b.y, 40);
    const whipping = this.whip !== null;
    if (whipping || b.moving) {
      const name = `boss_${whipping ? "whip" : "walk"}_${b.dir}` as SheetName;
      const meta = SHEETS[name];
      const frame = whipping ? Math.min(meta.frames - 1, Math.floor(this.whip!.t / WHIP_FRAME)) : Math.floor(b.anim) % meta.frames;
      ctx.drawImage(this.img(sheetUrl(name)), frame * meta.size, 0, meta.size, meta.size, Math.round(b.x - meta.size / 2), Math.round(b.y - meta.foot), meta.size, meta.size);
    } else {
      const img = this.img(stillUrl("boss", b.dir));
      ctx.drawImage(img, Math.round(b.x - 64), Math.round(b.y - STILLS.boss.foot));
    }
  }

  private drawEmote(ctx: CanvasRenderingContext2D, r: Robot) {
    const d = DESKS[r.desk];
    const head = this.robotHead(r);
    const heartUntil = this.hearts.get(r.id) ?? 0;
    const joltUntil = this.jolts.get(r.id) ?? 0;
    let name: string | null = null;
    let bob = 0;
    if (heartUntil > this.time) {
      name = "heart";
      bob = -Math.min(1, heartUntil - this.time) * 4;
    } else if (joltUntil + 0.9 > this.time) {
      name = "sweat";
      bob = -Math.round((this.time - joltUntil + 0.35) * 10);
    } else if (r.state === "waiting") {
      name = "alert";
      bob = Math.round(Math.sin(this.time * 6 + r.desk) * 3);
    } else if (r.state === "done") {
      name = "sleep";
      bob = Math.round(Math.sin(this.time * 1.8) * 3);
    } else if ((this.boosts.get(r.id) ?? 0) > this.time || (this.time + r.desk * 1.7) % 7 < 1.6) {
      name = "dots";
    }
    if (!name) return;
    const img = this.img(`/assets/emotes/${name}.png`);
    ctx.drawImage(img, Math.round(d.x + 14), Math.round(head - 34 + bob), 40, 40);
  }

  private drawCracks(ctx: CanvasRenderingContext2D) {
    this.cracks.forEach((c) => {
      const p = c.t / 0.7;
      const reach = 8 + Math.min(1, c.t / 0.25) * 22;
      ctx.globalAlpha = 1 - Math.max(0, p - 0.5) * 2;
      ctx.fillStyle = "#FFF6EC";
      for (let i = 0; i < 8; i++) {
        const a = (i / 8) * Math.PI * 2 + 0.3;
        const len = i % 2 ? reach * 0.6 : reach;
        for (let k = 6; k < len; k += 3) ctx.fillRect(Math.round(c.x + Math.cos(a) * k), Math.round(c.y + Math.sin(a) * k), 2, 2);
      }
      ctx.fillStyle = "#F5B942";
      ctx.fillRect(Math.round(c.x) - 3, Math.round(c.y) - 3, 6, 6);
      ctx.font = `900 18px ${ROUNDED}`;
      ctx.textBaseline = "middle";
      const ty = Math.round(c.y - 14 - c.t * 28);
      ctx.fillStyle = "#2A1840";
      ctx.fillText("CRACK!", Math.round(c.x + 24), ty + 2);
      ctx.fillStyle = "#F5B942";
      ctx.fillText("CRACK!", Math.round(c.x + 24), ty);
      ctx.globalAlpha = 1;
    });
  }

  private drawSparkles(ctx: CanvasRenderingContext2D) {
    this.sparkles.forEach((s) => {
      const size = s.life > 0.5 ? 3 : 2;
      ctx.fillStyle = s.color;
      const x = Math.round(s.x), y = Math.round(s.y);
      ctx.fillRect(x - size, y, size * 2 + 1, 1);
      ctx.fillRect(x, y - size, 1, size * 2 + 1);
    });
  }

  private drawHighlight(ctx: CanvasRenderingContext2D) {
    const target = this.nearest ?? (this.attract ? null : this.hover);
    if (!target) return;
    const label = (target.kind === "robot" ? target.robot.name : target.prop.title).replace(/f(?=[filt])/g, "f\u200C");
    let x: number, y: number;
    if (target.kind === "robot") {
      const d = DESKS[target.robot.desk];
      x = d.x;
      y = this.robotHead(target.robot) - 40;
    } else {
      const p = PROPS.find((pp) => pp.id === target.prop.id)!;
      const img = this.img(`/assets/objects/${p.img}.png`);
      x = p.x;
      y = p.wall ? p.base + 8 : p.base - p.bottom + img.height * 0.1 - 30;
      if (!p.wall && y < 140) y = p.base + 8;
    }
    ctx.font = `16px ${this.font}`;
    ctx.textBaseline = "middle";
    const showKey = this.nearest === target && !this.coarse;
    const keyW = showKey ? 46 : 0;
    const w = Math.ceil(ctx.measureText(label).width) + 20 + keyW;
    const h = 24;
    const lx = Math.round(x - w / 2), ly = Math.round(y);
    ctx.fillStyle = "#2A1840";
    ctx.fillRect(lx - 2, ly, w + 4, h);
    ctx.fillRect(lx, ly - 2, w, h + 4);
    ctx.fillStyle = "#1E1A33";
    ctx.fillRect(lx, ly, w, h);
    ctx.fillStyle = "#F5B942";
    ctx.fillRect(lx, ly, w, 2);
    ctx.fillStyle = "#FFF6EC";
    ctx.fillText(label, lx + 10, ly + h / 2 + 1);
    if (showKey) {
      const kx = lx + w - keyW + 2;
      ctx.fillStyle = "#F5B942";
      ctx.fillRect(kx, ly + 4, keyW - 10, h - 8);
      ctx.fillStyle = "#2A1840";
      ctx.font = `12px ${this.font}`;
      ctx.fillText("SPACE", kx + 3, ly + h / 2 + 1);
    }
  }

  private glowSprite(rgb: string) {
    let sprite = this.glows.get(rgb);
    if (!sprite) {
      sprite = document.createElement("canvas");
      sprite.width = sprite.height = 128;
      const g = sprite.getContext("2d")!;
      const grad = g.createRadialGradient(64, 64, 0, 64, 64, 64);
      grad.addColorStop(0, `rgba(${rgb},1)`);
      grad.addColorStop(0.55, `rgba(${rgb},0.55)`);
      grad.addColorStop(1, `rgba(${rgb},0)`);
      g.fillStyle = grad;
      g.fillRect(0, 0, 128, 128);
      this.glows.set(rgb, sprite);
    }
    return sprite;
  }

  private drawNight(ctx: CanvasRenderingContext2D) {
    const s = this.shade.getContext("2d")!;
    s.setTransform(SHADE_SCALE, 0, 0, SHADE_SCALE, 0, 0);
    s.globalCompositeOperation = "source-over";
    s.globalAlpha = 1;
    s.clearRect(0, 0, WORLD_W, WORLD_H);
    s.fillStyle = "rgba(10,6,30,0.62)";
    s.fillRect(0, 0, WORLD_W, WORLD_H);
    s.globalCompositeOperation = "destination-out";
    const hole = this.glowSprite("0,0,0");
    const cut = (x: number, y: number, r: number, a: number) => {
      s.globalAlpha = a;
      s.drawImage(hole, x - r, y - r, r * 2, r * 2);
    };
    cut(this.boss.x, this.boss.y - 40, 150, 0.75);
    this.robots.forEach((r) => {
      const d = DESKS[r.desk];
      const pulse = r.state === "waiting" ? 0.75 + Math.sin(this.time * 5) * 0.15 : r.state === "done" ? 0.35 : 0.8;
      cut(d.x, d.base - 54, r.state === "done" ? 80 : 130, pulse);
    });
    cut(576, 90, 120, 0.8);
    WINDOWS.forEach((x) => cut(x, 80, 140, 0.55));
    cut(1000, 160, 70, 0.5);
    cut(704, 90, 80, 0.35);
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(this.shade, 0, 0, WORLD_W, WORLD_H);

    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    const glow = (x: number, y: number, r: number, rgb: string, a: number) => {
      ctx.globalAlpha = a;
      ctx.drawImage(this.glowSprite(rgb), x - r, y - r, r * 2, r * 2);
    };
    this.robots.forEach((r) => {
      const d = DESKS[r.desk];
      if (r.state === "waiting") glow(d.x, d.base - 60, 110, "255,140,50", 0.16 + Math.sin(this.time * 5) * 0.05);
      else if (r.state === "working") glow(d.x, d.base - 50, 100, "90,170,255", 0.12);
    });
    glow(576, 86, 110, "76,209,138", 0.12);
    WINDOWS.forEach((x) => glow(x, 70, 120, "140,160,255", 0.1));
    glow(this.boss.x, this.boss.y - 50, 120, "255,200,120", 0.07);
    ctx.restore();
    ctx.imageSmoothingEnabled = false;
  }
}
