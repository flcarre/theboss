export type Harness = "claude" | "codex" | "gemini" | "copilot" | "cursor";
export type Dir = "south" | "north" | "east" | "west";

export type SheetName =
  | `boss_walk_${Dir}`
  | `boss_whip_${Dir}`
  | `robot_${Harness}_typing_south`
  | `robot_${Harness}_alert_south`;

export type Sheet = { size: number; frames: number; top: number; foot: number };

export const SHEETS: Record<SheetName, Sheet> = {
  boss_walk_south: { size: 140, frames: 8, top: 22, foot: 123 },
  boss_walk_north: { size: 140, frames: 8, top: 21, foot: 124 },
  boss_walk_east: { size: 140, frames: 8, top: 21, foot: 120 },
  boss_walk_west: { size: 140, frames: 8, top: 20, foot: 118 },
  boss_whip_south: { size: 140, frames: 8, top: 21, foot: 123 },
  boss_whip_north: { size: 140, frames: 8, top: 20, foot: 115 },
  boss_whip_east: { size: 140, frames: 8, top: 21, foot: 118 },
  boss_whip_west: { size: 140, frames: 8, top: 21, foot: 118 },
  robot_claude_typing_south: { size: 144, frames: 9, top: 20, foot: 119 },
  robot_claude_alert_south: { size: 144, frames: 9, top: 19, foot: 119 },
  robot_codex_typing_south: { size: 128, frames: 9, top: 23, foot: 105 },
  robot_codex_alert_south: { size: 128, frames: 9, top: 22, foot: 105 },
  robot_cursor_typing_south: { size: 140, frames: 9, top: 18, foot: 111 },
  robot_cursor_alert_south: { size: 140, frames: 9, top: 19, foot: 111 },
  robot_gemini_typing_south: { size: 128, frames: 9, top: 24, foot: 104 },
  robot_gemini_alert_south: { size: 128, frames: 9, top: 23, foot: 104 },
  robot_copilot_typing_south: { size: 136, frames: 9, top: 18, foot: 116 },
  robot_copilot_alert_south: { size: 136, frames: 9, top: 17, foot: 116 },
};

export const STILLS: Record<Harness | "boss", { top: number; foot: number }> = {
  boss: { top: 18, foot: 114 },
  claude: { top: 13, foot: 111 },
  codex: { top: 27, foot: 105 },
  gemini: { top: 26, foot: 104 },
  copilot: { top: 20, foot: 112 },
  cursor: { top: 14, foot: 105 },
};

export const ROBOT_SCALE: Record<Harness, number> = {
  claude: 1,
  codex: 1.08,
  gemini: 1.08,
  copilot: 1,
  cursor: 1,
};

export const HARNESS_ORDER: Harness[] = ["claude", "codex", "gemini", "copilot", "cursor"];

export const HARNESS_NAME: Record<Harness, string> = {
  claude: "Claude Code",
  codex: "Codex",
  gemini: "Gemini",
  copilot: "Copilot",
  cursor: "Cursor",
};

export const HARNESS_COLOR: Record<Harness, string> = {
  claude: "#D9773F",
  codex: "#3FBFA8",
  gemini: "#4F7BD9",
  copilot: "#8A63D2",
  cursor: "#9AA3AD",
};

export const sheetUrl = (name: SheetName) => `/assets/sheets/${name}.png`;
export const stillUrl = (who: Harness | "boss", dir: Dir = "south") =>
  `/assets/characters/${who === "boss" ? "boss" : `robot_${who}`}/rotations/${dir}.png`;
