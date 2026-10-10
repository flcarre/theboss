import { writeText } from "@tauri-apps/plugin-clipboard-manager";
import { openPath, revealItemInDir } from "@tauri-apps/plugin-opener";
import { isTauri } from "../backend";

export async function openInSystem(path: string): Promise<boolean> {
  if (!isTauri) {
    console.info("[browser mode] open", path);
    return true;
  }
  try {
    await openPath(path);
    return true;
  } catch {
    return false;
  }
}

export async function openFileOrFolder(path: string): Promise<void> {
  if (await openInSystem(path)) return;
  await openInSystem(parentFolder(path));
}

export async function revealInFolder(path: string): Promise<void> {
  if (!isTauri) {
    console.info("[browser mode] reveal", path);
    return;
  }
  try {
    await revealItemInDir(path);
  } catch {
    await openInSystem(parentFolder(path));
  }
}

export async function copyText(text: string): Promise<void> {
  if (isTauri) {
    await writeText(text);
    return;
  }
  navigator.clipboard?.writeText(text).catch(() => console.info("[browser mode] copy", text));
}

export function parentFolder(path: string): string {
  const trimmed = path.replace(/[\\/]+$/, "");
  const cut = Math.max(trimmed.lastIndexOf("/"), trimmed.lastIndexOf("\\"));
  return cut > 0 ? trimmed.slice(0, cut) : trimmed;
}

export function lastPathComponent(path: string): string {
  const trimmed = path.replace(/[\\/]+$/, "");
  const cut = Math.max(trimmed.lastIndexOf("/"), trimmed.lastIndexOf("\\"));
  return cut >= 0 ? trimmed.slice(cut + 1) : trimmed;
}

const HOME_PREFIX = /^(\/Users\/[^/]+|\/home\/[^/]+|\/root|[A-Za-z]:\\Users\\[^\\]+)(?=$|[\\/])/;

export function tildePath(path: string): string {
  return path.replace(HOME_PREFIX, "~");
}

export function shellQuote(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`;
}
