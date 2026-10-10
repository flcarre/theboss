import { FACINGS } from "./rooms";

export type Sprite = HTMLImageElement | HTMLCanvasElement;

const ASSET_ROOT = "/assets/";

const ROBOT_FOLDERS = ["robot_claude", "robot_codex", "robot_cursor", "robot_gemini", "robot_copilot"];

const FRAME_COUNTS: Record<string, number> = Object.fromEntries([
  ...FACINGS.flatMap((facing) => [
    [`characters/boss/walk/${facing}`, 8],
    [`characters/boss/whip/${facing}`, 8],
  ]),
  ...ROBOT_FOLDERS.flatMap((folder) => [
    [`characters/${folder}/typing/south`, 9],
    [`characters/${folder}/alert/south`, 9],
  ]),
]);

const OBJECTS = [
  "archive_cabinet",
  "bookshelf",
  "coffee_machine",
  "desk_boss",
  "desk_worker",
  "door",
  "intray",
  "plant",
  "rug",
  "server_rack",
  "sofa",
  "wall_screen",
  "water_cooler",
  "whiteboard",
  "window_wall",
];

const images = new Map<string, HTMLImageElement>();
const failed = new Set<string>();
const paddings = new Map<string, number>();
const tinted = new Map<string, HTMLCanvasElement>();
const listeners = new Set<() => void>();

export function assetUrl(path: string): string {
  return `${ASSET_ROOT}${path}`;
}

export function framePaths(directory: string): string[] {
  const count = FRAME_COUNTS[directory] ?? 0;
  return Array.from({ length: count }, (_, index) => `${directory}/${index}.png`);
}

function load(path: string): Promise<void> {
  if (images.has(path) || failed.has(path)) return Promise.resolve();
  return new Promise((resolve) => {
    const image = new Image();
    image.decoding = "async";
    image.onload = () => {
      images.set(path, image);
      listeners.forEach((listener) => listener());
      resolve();
    };
    image.onerror = () => {
      failed.add(path);
      resolve();
    };
    image.src = assetUrl(path);
  });
}

export function preloadAll(): Promise<void> {
  const paths = [
    ...OBJECTS.map((name) => `objects/${name}.png`),
    "walls/wall_office.png",
    "walls/wall_openspace.png",
    ...FACINGS.map((facing) => `characters/boss/rotations/${facing}.png`),
    ...ROBOT_FOLDERS.flatMap((folder) => FACINGS.map((facing) => `characters/${folder}/rotations/${facing}.png`)),
    ...Object.keys(FRAME_COUNTS).flatMap(framePaths),
  ];
  return Promise.all(paths.map(load)).then(() => undefined);
}

export function onAssetLoaded(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function image(path: string): HTMLImageElement | null {
  const hit = images.get(path);
  if (hit) return hit;
  void load(path);
  return null;
}

export function hasFailed(path: string): boolean {
  return failed.has(path);
}

export function bottomPadding(path: string): number {
  const cachedValue = paddings.get(path);
  if (cachedValue !== undefined) return cachedValue;
  const source = image(path);
  if (!source) return 0;
  const canvas = document.createElement("canvas");
  canvas.width = source.naturalWidth;
  canvas.height = source.naturalHeight;
  const context = canvas.getContext("2d", { willReadFrequently: true });
  if (!context) return 0;
  context.drawImage(source, 0, 0);
  const data = context.getImageData(0, 0, canvas.width, canvas.height).data;
  let padding = 0;
  rows: for (let y = canvas.height - 1; y >= 0; y--) {
    for (let x = 0; x < canvas.width; x++) {
      if (data[(y * canvas.width + x) * 4 + 3] > 0) break rows;
    }
    padding += 1;
  }
  paddings.set(path, padding);
  return padding;
}

export function colorized(path: string, source: Sprite, color: string, factor: number): HTMLCanvasElement {
  const step = Math.round(factor * 20) / 20;
  const key = `${path}|${color}|${step}`;
  const hit = tinted.get(key);
  if (hit) return hit;
  const canvas = document.createElement("canvas");
  canvas.width = source.width;
  canvas.height = source.height;
  const context = canvas.getContext("2d");
  if (context) {
    context.imageSmoothingEnabled = false;
    context.drawImage(source, 0, 0);
    context.globalCompositeOperation = "source-atop";
    context.globalAlpha = step;
    context.fillStyle = color;
    context.fillRect(0, 0, canvas.width, canvas.height);
  }
  tinted.set(key, canvas);
  return canvas;
}
