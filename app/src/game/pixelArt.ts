import type { AgentStatus } from "../api";

export type Rgba = { r: number; g: number; b: number; a: number };

export function rgba(hex: number, alpha = 255): Rgba {
  return { r: (hex >> 16) & 0xff, g: (hex >> 8) & 0xff, b: hex & 0xff, a: alpha };
}

export function shade(hex: number, factor: number): number {
  const r = Math.floor(((hex >> 16) & 0xff) * factor);
  const g = Math.floor(((hex >> 8) & 0xff) * factor);
  const b = Math.floor((hex & 0xff) * factor);
  return (r << 16) | (g << 8) | b;
}

export const OUTLINE = rgba(0x2a1840);

export const STATUS_COLOR: Record<AgentStatus, number> = {
  working: 0x4cd18a,
  needsApproval: 0xff9a2e,
  finished: 0xa8b0bd,
};

export class PixelCanvas {
  readonly pixels: Uint8ClampedArray;

  constructor(
    readonly width: number,
    readonly height: number,
    fill: Rgba | null = null,
  ) {
    this.pixels = new Uint8ClampedArray(width * height * 4);
    if (fill) this.rect(0, 0, width, height, fill);
  }

  set(x: number, y: number, color: Rgba): void {
    if (x < 0 || y < 0 || x >= this.width || y >= this.height) return;
    const i = (y * this.width + x) * 4;
    this.pixels[i] = color.r;
    this.pixels[i + 1] = color.g;
    this.pixels[i + 2] = color.b;
    this.pixels[i + 3] = color.a;
  }

  rect(x: number, y: number, w: number, h: number, color: Rgba): void {
    for (let yy = y; yy < y + h; yy++) for (let xx = x; xx < x + w; xx++) this.set(xx, yy, color);
  }

  toCanvas(): HTMLCanvasElement {
    const canvas = document.createElement("canvas");
    canvas.width = this.width;
    canvas.height = this.height;
    const context = canvas.getContext("2d");
    if (context) context.putImageData(new ImageData(new Uint8ClampedArray(this.pixels), this.width, this.height), 0, 0);
    return canvas;
  }
}

const cache = new Map<string, HTMLCanvasElement>();

function cached(key: string, make: () => PixelCanvas): HTMLCanvasElement {
  const hit = cache.get(key);
  if (hit) return hit;
  const canvas = make().toCanvas();
  cache.set(key, canvas);
  return canvas;
}

export function noise(x: number, y: number, seed: number): number {
  let h = (Math.imul(x, 374761393) + Math.imul(y, 668265263) + Math.imul(seed, 2147483647)) >>> 0;
  h = Math.imul((h ^ (h >>> 13)) >>> 0, 1274126177) >>> 0;
  return ((h ^ (h >>> 16)) >>> 0) & 0xffff;
}

export type WallStyle = {
  trim: number;
  trimLight: number;
  paper: number;
  paperStripe: number;
  rail: number;
  railLight: number;
  railShadow: number;
  panel: number;
  panelLine: number;
  panelLight: number;
  base: number;
  baseDark: number;
};

export const WALL_STYLES: Record<"office" | "openSpace", WallStyle> = {
  office: {
    trim: 0x2b2547,
    trimLight: 0x4e4580,
    paper: 0xeadfc8,
    paperStripe: 0xdccdae,
    rail: 0xc9832a,
    railLight: 0xf5b942,
    railShadow: 0x9a6420,
    panel: 0x9a6420,
    panelLine: 0x6a4218,
    panelLight: 0xc9832a,
    base: 0x6a4218,
    baseDark: 0x3a2410,
  },
  openSpace: {
    trim: 0x2b2547,
    trimLight: 0x4e4580,
    paper: 0xd9deea,
    paperStripe: 0xc7cedf,
    rail: 0x7a6fb0,
    railLight: 0xb9b0d6,
    railShadow: 0x4e4580,
    panel: 0x4e4580,
    panelLine: 0x3a3260,
    panelLight: 0x7a6fb0,
    base: 0x3a3260,
    baseDark: 0x1e1a33,
  },
};

export function missing(): HTMLCanvasElement {
  return cached("missing", () => {
    const c = new PixelCanvas(16, 16);
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) c.set(x, y, (Math.floor(x / 4) + Math.floor(y / 4)) % 2 === 0 ? rgba(0xff00ff) : rgba(0));
    return c;
  });
}

export function wall(styleName: "office" | "openSpace", width = 64, height = 128): HTMLCanvasElement {
  return cached(`wall-${styleName}-${width}-${height}`, () => {
    const style = WALL_STYLES[styleName];
    const c = new PixelCanvas(width, height);
    c.rect(0, 0, width, 8, rgba(style.trim));
    c.rect(0, 7, width, 1, rgba(style.trimLight));
    c.rect(0, 8, width, 76, rgba(style.paper));
    for (let x = 6; x < width; x += 16) c.rect(x, 8, 2, 76, rgba(style.paperStripe));
    for (let y = 16; y < 82; y += 12) {
      for (let x = Math.floor(y / 12) % 2 === 0 ? 14 : 2; x < width; x += 16) c.set(x, y, rgba(style.paperStripe));
    }
    c.rect(0, 84, width, 1, rgba(style.railLight));
    c.rect(0, 85, width, 2, rgba(style.rail));
    c.rect(0, 87, width, 1, rgba(style.railShadow));
    c.rect(0, 88, width, 32, rgba(style.panel));
    for (let x = 0; x < width; x += 32) {
      c.rect(x + 3, 91, 26, 1, rgba(style.panelLight));
      c.rect(x + 3, 91, 1, 25, rgba(style.panelLight));
      c.rect(x + 3, 116, 26, 1, rgba(style.panelLine));
      c.rect(x + 28, 91, 1, 26, rgba(style.panelLine));
    }
    c.rect(0, 120, width, 6, rgba(style.base));
    c.rect(0, 126, width, 2, rgba(style.baseDark));
    return c;
  });
}

export function shadow(width: number, height: number): HTMLCanvasElement {
  return cached(`shadow-${width}-${height}`, () => {
    const c = new PixelCanvas(width, height);
    const rx = width / 2;
    const ry = height / 2;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const dx = (x + 0.5 - rx) / rx;
        const dy = (y + 0.5 - ry) / ry;
        if (dx * dx + dy * dy <= 1) c.set(x, y, rgba(0x1e1a33, 90));
      }
    }
    return c;
  });
}

export function edge(width: number, height: number): HTMLCanvasElement {
  return cached(`edge-${width}-${height}`, () => {
    const c = new PixelCanvas(width, height, rgba(0x2b2547));
    c.rect(0, 0, width, 1, rgba(0x4e4580));
    return c;
  });
}

export function glow(width: number, height: number, color: number): HTMLCanvasElement {
  return cached(`glow-${width}-${height}-${color}`, () => {
    const c = new PixelCanvas(width, height);
    const rx = width / 2;
    const ry = height / 2;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const dx = (x + 0.5 - rx) / rx;
        const dy = (y + 0.5 - ry) / ry;
        const d = dx * dx + dy * dy;
        if (d <= 1) c.set(x, y, rgba(color, d < 0.35 ? 70 : d < 0.7 ? 45 : 22));
      }
    }
    return c;
  });
}

export function doormat(): HTMLCanvasElement {
  return cached("doormat", () => {
    const c = new PixelCanvas(64, 40, rgba(0x5c4033));
    c.rect(0, 0, 64, 1, OUTLINE);
    c.rect(0, 39, 64, 1, OUTLINE);
    c.rect(0, 0, 1, 40, OUTLINE);
    c.rect(63, 0, 1, 40, OUTLINE);
    for (let y = 4; y < 36; y += 4) c.rect(4, y, 56, 1, rgba(0x7a5a45));
    c.rect(3, 3, 58, 1, rgba(0xc9832a));
    c.rect(3, 36, 58, 1, rgba(0x3a2410));
    return c;
  });
}

function paintRows(c: PixelCanvas, rows: string[], ox: number, oy: number, palette: Record<string, Rgba>): void {
  rows.forEach((row, y) => {
    [...row].forEach((ch, x) => {
      const color = palette[ch];
      if (color) c.set(ox + x, oy + y, color);
    });
  });
}

export function statusLight(color: number): HTMLCanvasElement {
  return cached(`light-${color}`, () => {
    const c = new PixelCanvas(10, 10);
    const shape = ["..XXXXXX..", ".XooooooX.", "XoohhoooOX", "XohhooooOX", "XoooooooOX", "XoooooooOX", "XooooooOOX", "XooooOOOOX", ".XOOOOOOX.", "..XXXXXX.."];
    paintRows(c, shape, 0, 0, { X: OUTLINE, o: rgba(color), O: rgba(shade(color, 0.7)), h: rgba(0xfff6ec) });
    return c;
  });
}

const BUBBLE_SHAPE = [
  "..XXXXXXXXXXXXXXXXXX..",
  ".XWWWWWWWWWWWWWWWWWWX.",
  "XWWWWWWWWWWWWWWWWWWWWX",
  "XWWWWWWWWWWWWWWWWWWWWX",
  "XWWWWWWWWWWWWWWWWWWWWX",
  "XWWWWWWWWWWWWWWWWWWWWX",
  "XWWWWWWWWWWWWWWWWWWWWX",
  "XWWWWWWWWWWWWWWWWWWWWX",
  "XWWWWWWWWWWWWWWWWWWWWX",
  "XWWWWWWWWWWWWWWWWWWWWX",
  "XWWWWWWWWWWWWWWWWWWWWX",
  "XWWWWWWWWWWWWWWWWWWWWX",
  "XSWWWWWWWWWWWWWWWWWWSX",
  ".XSSSSSWWWWWSSSSSSSSX.",
  "..XXXXXXSWWSXXXXXXXX..",
  ".......XSWSX..........",
  "........XSX...........",
  ".........X............",
];

function bubble(glyph: string[], color: number): PixelCanvas {
  const c = new PixelCanvas(22, 18);
  paintRows(c, BUBBLE_SHAPE, 0, 0, { X: OUTLINE, W: rgba(0xfff6ec), S: rgba(0xd9cfc2) });
  const originX = Math.floor((22 - (glyph[0]?.length ?? 0)) / 2);
  paintRows(c, glyph, originX, 2, { "#": rgba(color) });
  paintRows(c, glyph, originX, 2, { o: rgba(shade(color, 0.7)) });
  return c;
}

export function exclamation(): HTMLCanvasElement {
  return cached("bubble!", () =>
    bubble(["..##..", ".####.", ".####.", ".####.", "..##..", "..##..", "..oo..", "......", "..##..", "..oo.."], 0xf0532e),
  );
}

export function sleeping(): HTMLCanvasElement {
  return cached("bubbleZ", () =>
    bubble(["......#####", ".........#.", "........#..", ".......####", "####.......", "..#........", ".#.........", "####......."], 0x4f7bd9),
  );
}

export function sparkle(frame: number): HTMLCanvasElement {
  return cached(`sparkle${frame}`, () => {
    const c = new PixelCanvas(48, 48);
    const radius = 4 + frame * 4;
    const colors = [0xfff6ec, 0xf5b942, 0x7fd8ff];
    for (let i = 0; i < 8; i++) {
      const angle = (i * Math.PI) / 4 + frame * 0.3;
      const x = 24 + Math.trunc(radius * Math.cos(angle));
      const y = 24 + Math.trunc(radius * Math.sin(angle));
      const color = rgba(colors[(i + frame) % colors.length], frame > 4 ? 140 : 255);
      c.rect(x - 1, y, 3, 1, color);
      c.rect(x, y - 1, 1, 3, color);
    }
    return c;
  });
}

export function smoke(frame: number): HTMLCanvasElement {
  return cached(`smoke${frame}`, () => {
    const c = new PixelCanvas(48, 48);
    const radius = 6 + frame * 3;
    for (let y = 0; y < 48; y++) {
      for (let x = 0; x < 48; x++) {
        for (let puff = 0; puff < 3; puff++) {
          const cx = 24 + (puff - 1) * radius * 0.7;
          const cy = 30 - frame * 2 - (puff % 2) * 4;
          const d = Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
          if (d < radius * 0.55) c.set(x, y, rgba(d < radius * 0.35 ? 0xe9e4f7 : 0xb9b0d6, Math.max(0, 200 - frame * 32)));
        }
      }
    }
    return c;
  });
}

function glyph(rows: string[], color: number, size = 16): PixelCanvas {
  const c = new PixelCanvas(size, size);
  const ox = Math.floor((size - (rows[0]?.length ?? 0)) / 2);
  const oy = Math.floor((size - rows.length) / 2);
  paintRows(c, rows, ox, oy, { "#": rgba(color), X: OUTLINE, o: rgba(shade(color, 0.7)), w: rgba(0xfff6ec) });
  return c;
}

export function sweat(): HTMLCanvasElement {
  return cached("sweat", () => glyph(["...X...", "..XwX..", ".Xw#oX.", "Xw##ooX", "X####oX", "X###ooX", ".XoooX.", "..XXX.."], 0x7fc8f0, 9));
}

export function crack(frame: number): HTMLCanvasElement {
  return cached(`crack${frame}`, () => {
    const c = new PixelCanvas(56, 56);
    const reach = 8 + frame * 7;
    const colors = [0xfff6ec, 0xf5b942, 0xf0532e];
    for (let i = 0; i < 10; i++) {
      const angle = (i * Math.PI) / 5 + 0.2;
      for (let r = Math.max(2, reach - 10); r < reach; r++) {
        const x = 28 + Math.trunc(r * Math.cos(angle));
        const y = 28 + Math.trunc(r * Math.sin(angle));
        c.set(x, y, rgba(colors[(i + frame) % colors.length], frame > 3 ? 120 : 255));
      }
    }
    if (frame < 3) c.rect(25, 25, 6, 6, rgba(0xfff6ec));
    return c;
  });
}

export const PLAQUE_WIDTH = 128;
export const PLAQUE_HEIGHT = 32;

export function plate(status: AgentStatus): HTMLCanvasElement {
  return cached(`plate-${status}`, () => {
    const w = PLAQUE_WIDTH;
    const h = PLAQUE_HEIGHT;
    const c = new PixelCanvas(w, h);
    c.rect(1, 0, w - 2, h, OUTLINE);
    c.rect(0, 1, w, h - 2, OUTLINE);
    c.rect(2, 2, w - 4, h - 4, rgba(0x2b2547));
    c.rect(2, 2, w - 4, 1, rgba(0x4e4580));
    c.rect(2, h - 3, w - 4, 1, rgba(0x1e1a33));
    c.rect(3, 4, 3, h - 8, rgba(STATUS_COLOR[status]));
    c.rect(3, 4, 3, 1, rgba(0xfff6ec, 160));
    return c;
  });
}

export function parquet(variant: number): HTMLCanvasElement {
  return cached(`parquet${variant}`, () => {
    const c = new PixelCanvas(64, 64);
    const shades = [0xb9783f, 0xa9693a, 0xc5864a, 0xae7041];
    for (let row = 0; row < 4; row++) {
      const y0 = row * 16;
      const offset = ((row + variant) % 2) * 32 + ((variant * 11 + row * 7) % 16);
      for (let x = 0; x < 64; x++) {
        const plank = Math.floor((x + offset) / 48);
        const base = shades[(plank + row + variant) % shades.length];
        for (let y = y0; y < y0 + 16; y++) {
          let color = rgba(base);
          const n = noise(x + variant * 64, y, 7) % 100;
          if (n < 7) color = rgba(shade(base, 0.86));
          if ((y - y0 === 5 || y - y0 === 11) && noise(Math.floor(x / 6), y, plank) % 3 === 0) color = rgba(shade(base, 0.9));
          c.set(x, y, color);
        }
        if ((x + offset) % 48 === 0) {
          for (let y = y0; y < y0 + 16; y++) c.set(x, y, rgba(0x5a3420));
        }
      }
      for (let x = 0; x < 64; x++) c.set(x, y0 + 15, rgba(0x6b3f25));
      for (let x = 0; x < 64; x++) if (noise(x, y0, 3) % 5 !== 0) c.set(x, y0, rgba(0xd3965a));
    }
    return c;
  });
}

export function carpet(variant: number): HTMLCanvasElement {
  return cached(`carpet${variant}`, () => {
    const c = new PixelCanvas(64, 64);
    for (let y = 0; y < 64; y++) {
      for (let x = 0; x < 64; x++) {
        const tileIndex = (Math.floor(x / 32) + Math.floor(y / 32) + variant) % 2;
        const base = tileIndex === 0 ? 0x5b6b8c : 0x55647f;
        const n = noise(x + variant * 64, y, 11) % 100;
        let color = base;
        if (n < 18) color = shade(base, 0.88);
        if (n > 92) color = 0x6e7fa3;
        if (tileIndex === 0 && (x + y) % 8 === 0) color = shade(base, 0.92);
        if (x % 32 === 0 || y % 32 === 0) color = 0x46536c;
        c.set(x, y, rgba(color));
      }
    }
    return c;
  });
}
