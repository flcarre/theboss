import type { Sprite } from "./assets";

export const ROUNDED_FONT = "ui-rounded, 'SF Pro Rounded', 'Nunito', 'Varela Round', system-ui, sans-serif";

export type SpriteDraw = {
  sprite: Sprite;
  x: number;
  y: number;
  anchorX?: number;
  anchorY?: number;
  scale?: number;
  alpha?: number;
  additive?: boolean;
};

export type DrawFn = (ctx: CanvasRenderingContext2D) => void;

export class DrawList {
  private items: { z: number; seq: number; draw: DrawFn }[] = [];

  push(z: number, draw: DrawFn): void {
    this.items.push({ z, seq: this.items.length, draw });
  }

  sprite(z: number, spec: SpriteDraw): void {
    this.push(z, (ctx) => drawSprite(ctx, spec));
  }

  flush(ctx: CanvasRenderingContext2D): void {
    this.items.sort((a, b) => a.z - b.z || a.seq - b.seq);
    for (const item of this.items) item.draw(ctx);
    this.items = [];
  }
}

export function drawSprite(ctx: CanvasRenderingContext2D, spec: SpriteDraw): void {
  const alpha = spec.alpha ?? 1;
  if (alpha <= 0) return;
  const scale = spec.scale ?? 1;
  const width = spec.sprite.width * scale;
  const height = spec.sprite.height * scale;
  const left = spec.x - (spec.anchorX ?? 0.5) * width;
  const bottom = spec.y - (spec.anchorY ?? 0.5) * height;
  ctx.globalAlpha = alpha;
  if (spec.additive) ctx.globalCompositeOperation = "lighter";
  ctx.drawImage(spec.sprite, left, -(bottom + height), width, height);
  if (spec.additive) ctx.globalCompositeOperation = "source-over";
  ctx.globalAlpha = 1;
}

export type Keyframe = { t: number; x: number; y: number };

export function sampleKeyframes(frames: Keyframe[], elapsed: number): { x: number; y: number } {
  const last = frames[frames.length - 1];
  if (elapsed >= last.t) return { x: last.x, y: last.y };
  for (let i = 1; i < frames.length; i++) {
    const next = frames[i];
    if (elapsed <= next.t) {
      const previous = frames[i - 1];
      const span = next.t - previous.t;
      const k = span > 0 ? (elapsed - previous.t) / span : 1;
      return { x: previous.x + (next.x - previous.x) * k, y: previous.y + (next.y - previous.y) * k };
    }
  }
  return { x: last.x, y: last.y };
}

export function lerp(from: number, to: number, k: number): number {
  return from + (to - from) * Math.min(1, Math.max(0, k));
}
