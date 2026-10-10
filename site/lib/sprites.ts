export type SheetName =
  | "boss_walk_east" | "boss_walk_north" | "boss_walk_south" | "boss_walk_west"
  | "robot_claude_alert_south" | "robot_claude_typing_south"
  | "robot_codex_alert_south" | "robot_codex_typing_south"
  | "robot_cursor_alert_south" | "robot_cursor_typing_south"
  | "robot_omp_alert_south" | "robot_omp_typing_south"
  | "robot_pi_alert_south" | "robot_pi_typing_south";

export type Sheet = { size: number; frames: number; top: number; foot: number };

export const SHEETS: Record<SheetName, Sheet> = {
  boss_walk_east: { size: 128, frames: 8, top: 19, foot: 118 },
  boss_walk_north: { size: 128, frames: 8, top: 17, foot: 116 },
  boss_walk_south: { size: 128, frames: 8, top: 18, foot: 116 },
  boss_walk_west: { size: 128, frames: 8, top: 20, foot: 117 },
  robot_claude_alert_south: { size: 144, frames: 9, top: 19, foot: 119 },
  robot_claude_typing_south: { size: 144, frames: 9, top: 20, foot: 119 },
  robot_codex_alert_south: { size: 128, frames: 9, top: 22, foot: 105 },
  robot_codex_typing_south: { size: 128, frames: 9, top: 23, foot: 105 },
  robot_cursor_alert_south: { size: 140, frames: 9, top: 19, foot: 111 },
  robot_cursor_typing_south: { size: 140, frames: 9, top: 18, foot: 111 },
  robot_omp_alert_south: { size: 164, frames: 9, top: 24, foot: 140 },
  robot_omp_typing_south: { size: 164, frames: 9, top: 24, foot: 140 },
  robot_pi_alert_south: { size: 172, frames: 9, top: 24, foot: 147 },
  robot_pi_typing_south: { size: 172, frames: 9, top: 23, foot: 147 },
};

export type Harness = "claude" | "codex" | "cursor" | "pi" | "omp";

export const STILLS: Record<Harness | "boss", { top: number; foot: number }> = {
  boss: { top: 17, foot: 112 },
  claude: { top: 13, foot: 111 },
  codex: { top: 27, foot: 105 },
  cursor: { top: 14, foot: 105 },
  omp: { top: 6, foot: 122 },
  pi: { top: 4, foot: 125 },
};

export const ROBOT_SCALE: Record<Harness, number> = {
  claude: 1,
  codex: 1.08,
  cursor: 1,
  pi: 0.82,
  omp: 0.86,
};

export const HARNESS_NAME: Record<Harness, string> = {
  claude: "Claude Code",
  codex: "Codex",
  cursor: "Cursor",
  pi: "Pi",
  omp: "omp",
};

export const HARNESS_COLOR: Record<Harness, string> = {
  claude: "#D9773F",
  codex: "#3FBFA8",
  cursor: "#9AA3AD",
  pi: "#8C6BF2",
  omp: "#5BD16E",
};

export const sheetUrl = (name: SheetName) => `/assets/sheets/${name}.png`;
export const stillUrl = (who: Harness | "boss", dir = "south") =>
  `/assets/characters/${who === "boss" ? "boss" : `robot_${who}`}/rotations/${dir}.png`;
