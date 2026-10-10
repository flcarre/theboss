import type { CSSProperties } from "react";
import { SHEETS, type SheetName, sheetUrl } from "@/lib/sprites";

type Props = { sheet: SheetName; alt?: SheetName; zoom?: number; fps?: number; className?: string; label?: string };

export default function SpriteAnim({ sheet, alt, zoom = 1, fps = 9, className, label }: Props) {
  const meta = SHEETS[sheet];
  const style = {
    "--sheet": `url(${sheetUrl(sheet)})`,
    "--sheet-alt": `url(${sheetUrl(alt ?? sheet)})`,
    "--frames": meta.frames,
    "--w": `${meta.size * zoom}px`,
    "--dur": `${meta.frames / fps}s`,
  } as CSSProperties;
  return <span className={`sprite ${className ?? ""}`} style={style} role={label ? "img" : undefined} aria-label={label} aria-hidden={label ? undefined : true} />;
}
