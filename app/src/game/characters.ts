import type { AgentSession, AgentStatus, Harness } from "../api";
import { bottomPadding, colorized, framePaths, image, type Sprite } from "./assets";
import { exclamation, glow, plate, PLAQUE_WIDTH, sleeping, smoke, sparkle, STATUS_COLOR, statusLight, sweat } from "./pixelArt";
import { DrawList, drawSprite, lerp, ROUNDED_FONT, sampleKeyframes, type Keyframe } from "./render";
import { robotFolder, robotTint } from "./robotName";
import { deskCenterX, TILE_SIZE, type DeskSlot, type Facing, type Tile } from "./rooms";

export function positionOf(t: Tile): { x: number; y: number } {
  return { x: t.c * TILE_SIZE + TILE_SIZE / 2, y: t.r * TILE_SIZE };
}

export function depth(baseY: number): number {
  return 10_000 - baseY;
}

const HARNESS_DISPLAY: Record<Harness, string> = {
  claude: "Claude Code",
  codex: "Codex",
  gemini: "Gemini",
  copilot: "Copilot",
  cursor: "Cursor",
  pi: "Pi",
  omp: "omp",
};

const FEET_Y = 10;
const WALK_FRAME_TIME = 0.075;
const WHIP_FRAME_TIME = 0.055;

type Walk = { fromX: number; fromY: number; toX: number; toY: number; elapsed: number; duration: number };
type WhipSwing = { facing: Facing; elapsed: number; struck: boolean; onStrike: () => void };

export class Player {
  tile: Tile = { c: 0, r: 0 };
  facing: Facing = "south";
  x = 0;
  y = 0;
  private walk: Walk | null = null;
  private walkAnimation: { facing: Facing; start: number } | null = null;
  private swing: WhipSwing | null = null;

  get isMoving(): boolean {
    return this.walk !== null;
  }

  get isWhipping(): boolean {
    return this.swing !== null;
  }

  get z(): number {
    return depth(this.y);
  }

  place(t: Tile): void {
    this.tile = t;
    const p = positionOf(t);
    this.x = p.x;
    this.y = p.y;
    this.walk = null;
  }

  face(facing: Facing): void {
    this.facing = facing;
  }

  walkTo(t: Tile, duration: number, now: number): void {
    this.tile = t;
    const target = positionOf(t);
    this.walk = { fromX: this.x, fromY: this.y, toX: target.x, toY: target.y, elapsed: 0, duration };
    if (!this.walkAnimation || this.walkAnimation.facing !== this.facing) this.walkAnimation = { facing: this.facing, start: now };
  }

  stopWalking(): void {
    this.walkAnimation = null;
  }

  reset(): void {
    this.walk = null;
    this.walkAnimation = null;
    this.swing = null;
  }

  crackWhip(onStrike: () => void): void {
    this.walkAnimation = null;
    this.swing = { facing: this.facing, elapsed: 0, struck: false, onStrike };
  }

  advance(dt: number): void {
    if (this.walk) {
      const walk = this.walk;
      walk.elapsed += dt;
      if (walk.elapsed >= walk.duration) {
        this.x = walk.toX;
        this.y = walk.toY;
        this.walk = null;
      } else {
        const t = walk.elapsed / walk.duration;
        this.x = Math.round(walk.fromX + (walk.toX - walk.fromX) * t);
        this.y = Math.round(walk.fromY + (walk.toY - walk.fromY) * t);
      }
    }
    if (this.swing) {
      const swing = this.swing;
      swing.elapsed += dt;
      const frames = framePaths(`characters/boss/whip/${swing.facing}`).length;
      const strikeAt = frames > 1 ? WHIP_FRAME_TIME * frames * 0.6 : 0.15;
      const endAt = frames > 1 ? WHIP_FRAME_TIME * frames : 0.15;
      if (!swing.struck && swing.elapsed >= strikeAt) {
        swing.struck = true;
        swing.onStrike();
      }
      if (swing.elapsed >= endAt) this.swing = null;
    }
  }

  draw(list: DrawList, now: number, offsetX: number, offsetY: number): void {
    const restPath = `characters/boss/rotations/${this.facing}.png`;
    const rest = image(restPath);
    const restPadding = bottomPadding(restPath);
    let sprite: Sprite | null = rest;
    let spriteY = FEET_Y - restPadding;
    if (this.swing) {
      const paths = framePaths(`characters/boss/whip/${this.swing.facing}`);
      const index = Math.min(paths.length - 1, Math.floor(this.swing.elapsed / WHIP_FRAME_TIME));
      const frame = paths.length > 1 ? image(paths[index]) : null;
      if (frame) {
        const paddings = paths.map(bottomPadding).sort((a, b) => a - b);
        sprite = frame;
        spriteY = FEET_Y - paddings[Math.floor(paddings.length / 2)];
      }
    } else if (this.walkAnimation) {
      const paths = framePaths(`characters/boss/walk/${this.walkAnimation.facing}`);
      const index = Math.floor((now - this.walkAnimation.start) / WALK_FRAME_TIME) % Math.max(1, paths.length);
      const frame = paths.length ? image(paths[index]) : null;
      const first = paths.length ? image(paths[0]) : null;
      if (frame && first) {
        sprite = frame;
        spriteY = FEET_Y - restPadding - (first.height - (rest?.height ?? first.height)) / 2;
      }
    }
    if (!sprite) return;
    list.sprite(this.z, { sprite, x: this.x + offsetX, y: this.y + offsetY + spriteY, anchorX: 0.5, anchorY: 0 });
  }
}

type RobotPose =
  | { kind: "typing"; start: number; frameTime: number; frenzyUntil: number | null }
  | { kind: "alert"; start: number }
  | { kind: "sleep"; start: number }
  | { kind: "turned"; facing: Facing };

type Emote = { kind: "exclamation" | "sleeping"; start: number } | null;

const ALERT_FRAME_TIME = 0.1;
const ALERT_PAUSE = 0.6;
const TYPING_FRAME_TIME = 0.09;
const FRENZY_FRAME_TIME = 0.04;
const FRENZY_LOOPS = 10;
const TINT_FACTOR = 0.45;
const JOLT: Keyframe[] = [
  { t: 0, x: 0, y: 0 },
  { t: 0.03, x: -5, y: 0 },
  { t: 0.08, x: 5, y: 0 },
  { t: 0.13, x: -4, y: 0 },
  { t: 0.17, x: 0, y: 0 },
];

const measureCanvas = document.createElement("canvas").getContext("2d");
const fitCache = new Map<string, string>();

export function singleLineTruncated(text: string, limit: number): string {
  const line = text
    .split(/\r\n|\r|\n|\u2028|\u2029/u)
    .map((part) => part.trim())
    .filter((part) => part.length > 0)
    .join(" ");
  const characters = Array.from(line);
  return characters.length > limit ? `${characters.slice(0, limit - 1).join("")}…` : line;
}

function fitText(text: string, font: string, width: number): string {
  const key = `${font}|${width}|${text}`;
  const hit = fitCache.get(key);
  if (hit !== undefined) return hit;
  const result = computeFit(text, font, width);
  if (fitCache.size > 512) fitCache.clear();
  fitCache.set(key, result);
  return result;
}

function computeFit(text: string, font: string, width: number): string {
  const line = singleLineTruncated(text, 200);
  if (!measureCanvas) return line;
  measureCanvas.font = font;
  if (measureCanvas.measureText(line).width <= width) return line;
  const characters = Array.from(line);
  for (let count = characters.length - 1; count >= 1; count--) {
    const candidate = `${characters.slice(0, count).join("").trim()}…`;
    if (measureCanvas.measureText(candidate).width <= width) return candidate;
  }
  return "…";
}

export const PROJECT_FONT = `800 10px ${ROUNDED_FONT}`;
export const TASK_FONT = `600 10px ${ROUNDED_FONT}`;

export class Robot {
  readonly slot: DeskSlot;
  session: AgentSession;
  alpha = 1;
  leaving = false;
  removed = false;
  private renderedStatus: AgentStatus | null = null;
  private pose: RobotPose = { kind: "sleep", start: 0 };
  private emote: Emote = null;
  private glowVisible = false;
  private glowStart = 0;
  private fade: { from: number; to: number; start: number; duration: number } | null = null;
  private whippedAt: number | null = null;
  private sweats: number[] = [];
  private appearedAt: number | null = null;
  private highlighted = false;
  private plaqueScale = 1;
  private plaqueText: { key: string; project: string; task: string } = { key: "", project: "", task: "" };

  constructor(session: AgentSession, slot: DeskSlot, now: number) {
    this.session = session;
    this.slot = slot;
    this.update(session, now);
  }

  get x(): number {
    return deskCenterX(this.slot) * TILE_SIZE;
  }

  get y(): number {
    return this.slot.deskTile.r * TILE_SIZE + 20;
  }

  get z(): number {
    return depth(this.slot.deskTile.r * TILE_SIZE + 10) - 1;
  }

  private get folder(): string {
    return robotFolder(this.session.harness);
  }

  update(session: AgentSession, now: number): void {
    this.session = session;
    if (this.renderedStatus === session.status) return;
    this.renderedStatus = session.status;
    switch (session.status) {
      case "working":
        this.pose = { kind: "typing", start: now, frameTime: TYPING_FRAME_TIME, frenzyUntil: null };
        this.glowVisible = true;
        this.glowStart = now;
        this.emote = null;
        break;
      case "needsApproval":
        this.pose = { kind: "alert", start: now };
        this.glowVisible = false;
        this.emote = { kind: "exclamation", start: now };
        break;
      case "finished":
        this.pose = { kind: "sleep", start: now };
        this.glowVisible = false;
        this.emote = { kind: "sleeping", start: now };
        break;
    }
  }

  resume(now: number): void {
    this.update(this.session, now);
  }

  turn(facing: Facing): void {
    this.pose = { kind: "turned", facing };
    this.emote = null;
    this.renderedStatus = null;
  }

  setHighlighted(highlighted: boolean): void {
    this.highlighted = highlighted;
  }

  whipped(now: number): void {
    this.whippedAt = now;
    this.sweats.push(now);
    if (this.session.status !== "working" || this.pose.kind !== "typing") return;
    if (framePaths(`characters/${this.folder}/typing/south`).length <= 1) return;
    const frames = framePaths(`characters/${this.folder}/typing/south`).length;
    this.pose = { kind: "typing", start: now, frameTime: FRENZY_FRAME_TIME, frenzyUntil: now + FRENZY_FRAME_TIME * frames * FRENZY_LOOPS };
  }

  appear(now: number): void {
    this.alpha = 0;
    this.appearedAt = now;
    this.fade = { from: 0, to: 1, start: now, duration: 0.3 };
  }

  leave(now: number): void {
    this.leaving = true;
    this.fade = { from: this.alpha, to: 0, start: now, duration: 0.25 };
  }

  advance(dt: number, now: number): void {
    if (this.fade) {
      const k = (now - this.fade.start) / this.fade.duration;
      this.alpha = lerp(this.fade.from, this.fade.to, k);
      if (k >= 1) {
        this.fade = null;
        if (this.leaving) this.removed = true;
      }
    }
    if (this.pose.kind === "typing" && this.pose.frenzyUntil !== null && now >= this.pose.frenzyUntil) {
      this.renderedStatus = null;
      this.resume(now);
    }
    const targetScale = this.highlighted ? 1.08 : 1;
    const step = (0.08 / 0.1) * dt;
    this.plaqueScale = this.plaqueScale < targetScale ? Math.min(targetScale, this.plaqueScale + step) : Math.max(targetScale, this.plaqueScale - step);
    this.sweats = this.sweats.filter((start) => now - start < 1.45);
  }

  private spriteFrame(now: number): { path: string; offsetY: number } {
    const restPath = `characters/${this.folder}/rotations/south.png`;
    switch (this.pose.kind) {
      case "typing": {
        const paths = framePaths(`characters/${this.folder}/typing/south`);
        if (paths.length <= 1) return { path: restPath, offsetY: Math.floor(((now - this.pose.start) / 0.12) % 2) === 0 ? 0 : 2 };
        const index = Math.floor((now - this.pose.start) / this.pose.frameTime) % paths.length;
        return { path: paths[index], offsetY: -((image(paths[0])?.height ?? 128) - 128) / 2 };
      }
      case "alert": {
        const paths = framePaths(`characters/${this.folder}/alert/south`);
        if (paths.length <= 1) {
          const t = (now - this.pose.start) % 0.7;
          return { path: restPath, offsetY: t < 0.1 ? t * 60 : t < 0.2 ? (0.2 - t) * 60 : 0 };
        }
        const cycle = paths.length * ALERT_FRAME_TIME + ALERT_PAUSE;
        const t = (now - this.pose.start) % cycle;
        const index = Math.min(paths.length - 1, Math.floor(t / ALERT_FRAME_TIME));
        return { path: paths[index], offsetY: -((image(paths[0])?.height ?? 128) - 128) / 2 };
      }
      case "sleep": {
        const t = (now - this.pose.start) % 2.4;
        return { path: restPath, offsetY: t < 1.2 ? 0 : -1 };
      }
      case "turned":
        return { path: `characters/${this.folder}/rotations/${this.pose.facing}.png`, offsetY: 0 };
    }
  }

  private spriteTexture(path: string, now: number): Sprite | null {
    const source = image(path);
    if (!source) return null;
    const tint = robotTint(this.session.harness);
    const baseFactor = tint ? TINT_FACTOR : 0;
    if (this.whippedAt !== null) {
      const elapsed = now - this.whippedAt;
      if (elapsed < 0.23) {
        const factor = elapsed < 0.03 ? lerp(baseFactor, 0.7, elapsed / 0.03) : lerp(0.7, baseFactor, (elapsed - 0.03) / 0.2);
        return colorized(path, source, "#ffffff", factor);
      }
    }
    return tint ? colorized(path, source, tint, TINT_FACTOR) : source;
  }

  draw(list: DrawList, now: number, offsetX: number, offsetY: number): void {
    const alpha = this.alpha;
    if (alpha <= 0) return;
    const baseX = this.x + offsetX;
    const baseY = this.y + offsetY;
    const z = this.z;
    const frame = this.spriteFrame(now);
    const jolt = this.whippedAt !== null ? sampleKeyframes(JOLT, now - this.whippedAt).x : 0;
    const texture = this.spriteTexture(frame.path, now);
    if (texture) list.sprite(z, { sprite: texture, x: baseX + jolt, y: baseY + frame.offsetY, anchorX: 0.5, anchorY: 0, alpha });

    if (this.glowVisible) {
      const t = (now - this.glowStart) % 0.8;
      const glowAlpha = t < 0.4 ? lerp(1, 0.6, t / 0.4) : lerp(0.6, 1, (t - 0.4) / 0.4);
      list.sprite(z + 30, { sprite: glow(48, 22, 0x7fd8ff), x: baseX - 22, y: baseY + 30, alpha: alpha * glowAlpha, additive: true });
    }

    if (this.emote) this.drawEmote(list, now, baseX, baseY, z, alpha);

    list.sprite(z + 51, { sprite: statusLight(STATUS_COLOR[this.session.status]), x: baseX - 34, y: baseY + 100, alpha });

    for (const start of this.sweats) {
      const elapsed = now - start;
      const rise = Math.min(1, elapsed / 0.25) * 8;
      const sweatAlpha = elapsed < 1.15 ? 1 : lerp(1, 0, (elapsed - 1.15) / 0.3);
      list.sprite(z + 55, { sprite: sweat(), x: baseX - 38, y: baseY + 96 + rise, anchorX: 0.5, anchorY: 0, scale: 2, alpha: alpha * sweatAlpha });
    }

    if (this.appearedAt !== null) {
      const index = Math.floor((now - this.appearedAt) / 0.07);
      if (index < 6) list.sprite(z + 60, { sprite: sparkle(index), x: baseX, y: baseY + 60 });
      else this.appearedAt = null;
    }

    this.drawPlaque(list, baseX, baseY - 2, z + 60, alpha);
  }

  private drawEmote(list: DrawList, now: number, x: number, y: number, z: number, alpha: number): void {
    if (!this.emote) return;
    const elapsed = now - this.emote.start;
    if (this.emote.kind === "exclamation") {
      const t = elapsed % 0.66;
      const bounce = t < 0.18 ? (t / 0.18) * 6 : t < 0.36 ? (1 - (t - 0.18) / 0.18) * 6 : 0;
      list.sprite(z + 50, { sprite: exclamation(), x: x + 40, y: y + 96 + bounce, anchorX: 0.5, anchorY: 0, scale: 2, alpha });
      return;
    }
    const t = elapsed % 5;
    const emoteAlpha = t < 2.5 ? 0 : t < 2.7 ? (t - 2.5) / 0.2 : t < 4.7 ? 1 : 1 - (t - 4.7) / 0.3;
    list.sprite(z + 50, { sprite: sleeping(), x: x + 40, y: y + 96, anchorX: 0.5, anchorY: 0, scale: 2, alpha: alpha * emoteAlpha });
  }

  private plaqueLines(): { project: string; task: string } {
    const project = this.session.projectName.trim().length ? this.session.projectName : HARNESS_DISPLAY[this.session.harness];
    const key = `${project}\u0000${this.session.title}`;
    if (this.plaqueText.key !== key) {
      const width = PLAQUE_WIDTH - 18;
      this.plaqueText = {
        key,
        project: fitText(project.toUpperCase(), PROJECT_FONT, width),
        task: fitText(this.session.title, TASK_FONT, width),
      };
    }
    return this.plaqueText;
  }

  private drawPlaque(list: DrawList, x: number, y: number, z: number, alpha: number): void {
    const lines = this.plaqueLines();
    const background = plate(this.session.status);
    const scale = this.plaqueScale;
    list.push(z, (ctx) => {
      drawSprite(ctx, { sprite: background, x, y, scale, alpha });
      ctx.globalAlpha = alpha;
      ctx.textBaseline = "alphabetic";
      ctx.textAlign = "left";
      const left = x + (-PLAQUE_WIDTH / 2 + 11) * scale;
      ctx.save();
      ctx.translate(left, -y);
      ctx.scale(scale, scale);
      ctx.font = PROJECT_FONT;
      ctx.fillStyle = "rgb(245, 186, 66)";
      ctx.fillText(lines.project, 0, -3);
      ctx.font = TASK_FONT;
      ctx.fillStyle = "rgb(255, 246, 236)";
      ctx.fillText(lines.task, 0, 10);
      ctx.restore();
      ctx.globalAlpha = 1;
    });
  }
}

export function smokePuff(list: DrawList, x: number, y: number, z: number, elapsed: number): boolean {
  const index = Math.floor(elapsed / 0.07);
  if (index >= 6) return false;
  list.sprite(z, { sprite: smoke(index), x, y });
  return true;
}
