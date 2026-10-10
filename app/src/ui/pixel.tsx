import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import type { AgentStatus, Harness } from "../api";
import { COLOR, HARNESS_COLOR, HARNESS_NAME, STATUS_COLOR } from "./theme";

const OUTLINE = COLOR.ink;
const CREAM = COLOR.cream;

function shade(hex: string, factor: number): string {
  const value = parseInt(hex.slice(1), 16);
  const channel = (shift: number) => Math.floor(((value >> shift) & 0xff) * factor);
  return `rgb(${channel(16)}, ${channel(8)}, ${channel(0)})`;
}

type GlyphSpec = { rows: string[]; color: string; width: number; height: number; base?: string[]; baseOffset?: number };

const BUBBLE = [
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

const GLYPHS = {
  close: {
    rows: ["XX......XX", "X#X....X#X", ".X#X..X#X.", "..X#XX#X..", "...X##X...", "...X##X...", "..X#XX#X..", ".X#X..X#X.", "X#X....X#X", "XX......XX"],
    color: "#F0532E",
    width: 16,
    height: 16,
  },
  back: {
    rows: ["....XX......", "...X#X......", "..X##XXXXXX.", ".X########X.", "X#########oX", ".X###oooooX.", "..X#oXXXXX..", "...XoX......", "....XX......"],
    color: "#F5B942",
    width: 16,
    height: 16,
  },
  search: {
    rows: ["..XXXX....", ".XwwwwX...", "Xww##wwX..", "Xw#..#wX..", "Xw#..#wX..", ".Xw##wX...", "..XXXXoX..", "......XoX.", ".......XoX", "........XX"],
    color: "#7FB3E0",
    width: 16,
    height: 16,
  },
  bell: {
    rows: ["....XX....", "...X##X...", "..X####X..", ".X######X.", ".X######X.", ".X######X.", "X########X", "XooooooooX", ".XXXXXXXX.", "....XX...."],
    color: "#F5B942",
    width: 16,
    height: 16,
  },
  sleeping: {
    rows: ["......#####", ".........#.", "........#..", ".......####", "####.......", "..#........", ".#.........", "####......."],
    color: "#4F7BD9",
    width: 22,
    height: 18,
    base: BUBBLE,
    baseOffset: 2,
  },
} satisfies Record<string, GlyphSpec>;

export type GlyphName = keyof typeof GLYPHS;

function glyphRects(spec: GlyphSpec): Array<{ x: number; y: number; fill: string }> {
  const cells: Array<{ x: number; y: number; fill: string }> = [];
  if (spec.base) {
    spec.base.forEach((row, y) =>
      Array.from(row).forEach((cell, x) => {
        const fill = cell === "X" ? OUTLINE : cell === "W" ? CREAM : cell === "S" ? "#D9CFC2" : null;
        if (fill) cells.push({ x, y, fill });
      }),
    );
  }
  const glyphWidth = spec.rows[0]?.length ?? 0;
  const originX = Math.floor((spec.width - glyphWidth) / 2);
  const originY = spec.base ? (spec.baseOffset ?? 0) : Math.floor((spec.height - spec.rows.length) / 2);
  spec.rows.forEach((row, y) =>
    Array.from(row).forEach((cell, x) => {
      const fill =
        cell === "#" ? spec.color : cell === "X" ? OUTLINE : cell === "o" ? shade(spec.color, 0.7) : cell === "w" ? CREAM : null;
      if (fill) cells.push({ x: originX + x, y: originY + y, fill });
    }),
  );
  return cells;
}

export function PixelGlyph({ name, size }: { name: GlyphName; size: number }) {
  const spec: GlyphSpec = GLYPHS[name];
  const scale = size / Math.max(spec.width, spec.height);
  return (
    <svg
      className="pixel-glyph"
      width={spec.width * scale}
      height={spec.height * scale}
      viewBox={`0 0 ${spec.width} ${spec.height}`}
      shapeRendering="crispEdges"
      aria-hidden="true"
    >
      {glyphRects(spec).map((cell, index) => (
        <rect key={index} x={cell.x} y={cell.y} width={1} height={1} fill={cell.fill} />
      ))}
    </svg>
  );
}

const trimmedResults = new Map<string, string>();
const trimmedJobs = new Map<string, Promise<string>>();

function trimImage(src: string): Promise<string> {
  const pending = trimmedJobs.get(src);
  if (pending) return pending;
  const job = new Promise<string>((resolve) => {
    const image = new Image();
    image.onload = () => {
      const canvas = document.createElement("canvas");
      canvas.width = image.naturalWidth;
      canvas.height = image.naturalHeight;
      const context = canvas.getContext("2d");
      if (!context) return resolve(src);
      context.drawImage(image, 0, 0);
      const { data, width, height } = context.getImageData(0, 0, canvas.width, canvas.height);
      let minX = width;
      let minY = height;
      let maxX = -1;
      let maxY = -1;
      for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
          if (data[(y * width + x) * 4 + 3] > 8) {
            minX = Math.min(minX, x);
            maxX = Math.max(maxX, x);
            minY = Math.min(minY, y);
            maxY = Math.max(maxY, y);
          }
        }
      }
      if (maxX < 0) return resolve(src);
      const cropped = document.createElement("canvas");
      cropped.width = maxX - minX + 1;
      cropped.height = maxY - minY + 1;
      cropped.getContext("2d")?.drawImage(canvas, minX, minY, cropped.width, cropped.height, 0, 0, cropped.width, cropped.height);
      resolve(cropped.toDataURL("image/png"));
    };
    image.onerror = () => resolve(src);
    image.src = src;
  }).then((url) => {
    trimmedResults.set(src, url);
    return url;
  });
  trimmedJobs.set(src, job);
  return job;
}

export function PixelImage({ src, size, trimmed = false, className }: { src: string; size: number; trimmed?: boolean; className?: string }) {
  const [url, setUrl] = useState<string | null>(() => (trimmed ? (trimmedResults.get(src) ?? null) : src));
  useEffect(() => {
    if (!trimmed) {
      setUrl(src);
      return;
    }
    let alive = true;
    const cached = trimmedResults.get(src);
    if (cached) setUrl(cached);
    else trimImage(src).then((result) => alive && setUrl(result));
    return () => {
      alive = false;
    };
  }, [src, trimmed]);
  return (
    <span className={`pixel-image ${className ?? ""}`} style={{ width: size, height: size }}>
      {url && <img src={url} alt="" draggable={false} />}
    </span>
  );
}

export const ICON = {
  agents: "/assets/icons/agents.png",
  mail: "/assets/icons/mail.png",
  usage: "/assets/icons/usage.png",
  rules: "/assets/icons/rules.png",
  stats: "/assets/icons/stats.png",
  settings: "/assets/icons/settings.png",
  domain: "/assets/icons/domain.png",
  logbook: "/assets/icons/logbook.png",
} as const;

export function AssetIcon({ name, size }: { name: keyof typeof ICON; size: number }) {
  return <PixelImage src={ICON[name]} size={size} trimmed />;
}

export type ButtonTone = "crust" | "card" | "success";

export function PixelButton({
  title,
  tone = "crust",
  onClick,
  help,
  disabled,
}: {
  title: string;
  tone?: ButtonTone;
  onClick: () => void;
  help?: string;
  disabled?: boolean;
}) {
  return (
    <button type="button" className={`pixel-button tone-${tone}`} onClick={onClick} title={help} disabled={disabled}>
      {title}
    </button>
  );
}

export function StatusDot({ status }: { status: AgentStatus }) {
  return <span className="status-dot" style={{ background: STATUS_COLOR[status] }} />;
}

export function Gauge({ fraction, color, className }: { fraction: number; color: string; className?: string }) {
  const segments = 20;
  const filled = Math.round(Math.min(Math.max(fraction, 0), 1) * segments);
  return (
    <span className={`gauge ${className ?? ""}`} role="meter" aria-valuenow={Math.round(fraction * 100)} aria-valuemin={0} aria-valuemax={100}>
      {Array.from({ length: segments }, (_, index) => (
        <i key={index} style={index < filled ? { background: color } : undefined} />
      ))}
    </span>
  );
}

export function KeyCap({ label }: { label: string }) {
  return <kbd className="keycap">{label}</kbd>;
}

export function SectionTitle({ text, children }: { text: string; children?: ReactNode }) {
  return (
    <div className="section-title">
      <i />
      <span>{text}</span>
      {children}
    </div>
  );
}

export function CountBadge({ value }: { value: number }) {
  return <span className="count-badge">{value}</span>;
}

export function Chip({
  text,
  count,
  color,
  selected,
  onClick,
}: {
  text: string;
  count?: number;
  color: string;
  selected: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      className={`chip ${selected ? "is-selected" : ""}`}
      style={selected ? ({ "--chip-color": color } as CSSProperties) : undefined}
      onClick={onClick}
    >
      <span>{text}</span>
      {count !== undefined && <b>{count}</b>}
    </button>
  );
}

export type TabItem = { id: string; title: string; count: number; color: string };

export function SegmentedTabs({ items, selection, onSelect }: { items: TabItem[]; selection: string; onSelect: (id: string) => void }) {
  return (
    <div className="segmented-frame">
      <div className="segmented" role="tablist">
        {items.map((item) => {
          const selected = item.id === selection;
          return (
            <button
              key={item.id}
              type="button"
              role="tab"
              aria-selected={selected}
              className={selected ? "is-selected" : ""}
              style={selected ? ({ "--tab-color": item.color } as CSSProperties) : undefined}
              onClick={() => onSelect(item.id)}
            >
              <span>{item.title}</span>
              <b>{item.count}</b>
            </button>
          );
        })}
      </div>
    </div>
  );
}

export function HarnessTag({ harness }: { harness: Harness }) {
  return (
    <span className="harness-tag" style={{ background: HARNESS_COLOR[harness] }}>
      {HARNESS_NAME[harness]}
    </span>
  );
}

export function EmptyState({ text }: { text: string }) {
  return (
    <div className="empty-state">
      <PixelGlyph name="sleeping" size={72} />
      <p>{text}</p>
    </div>
  );
}

export function InlineCode({ text }: { text: string }) {
  const parts = text.split("`");
  return (
    <>
      {parts.map((part, index) => (index % 2 === 1 ? <code key={index}>{part}</code> : <span key={index}>{part}</span>))}
    </>
  );
}

export function FitText({ long, short, className }: { long: string; short: string; className?: string }) {
  const ref = useRef<HTMLSpanElement>(null);
  const [useShort, setUseShort] = useState(false);
  useLayoutEffect(() => {
    const element = ref.current;
    const row = element?.parentElement;
    if (!element || !row) return;
    const measure = () => {
      setUseShort(false);
      requestAnimationFrame(() => {
        const squeezed = Array.from(row.children).some((child) => child.scrollWidth > child.clientWidth + 1);
        if (squeezed || row.scrollWidth > row.clientWidth + 1) setUseShort(true);
      });
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(row);
    return () => observer.disconnect();
  }, [long, short]);
  return (
    <span ref={ref} className={className}>
      {useShort ? short : long}
    </span>
  );
}
