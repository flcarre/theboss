import type { AgentSession, Harness } from "../api";

const ROBOT_PREFIX: Record<Harness, string> = {
  claude: "CLAUDE",
  codex: "CODEX",
  gemini: "GEMINI",
  copilot: "COPILOT",
  cursor: "CURSOR",
  pi: "PI",
  omp: "OMP",
};

const ROBOT_FOLDER: Record<Harness, string> = {
  claude: "robot_claude",
  pi: "robot_claude",
  codex: "robot_codex",
  omp: "robot_codex",
  cursor: "robot_cursor",
  gemini: "robot_gemini",
  copilot: "robot_copilot",
};

const ROBOT_TINT: Partial<Record<Harness, string>> = {
  pi: "rgb(140, 107, 242)",
  omp: "rgb(89, 217, 115)",
};

const utf8 = new TextEncoder();

export function stableNumber(id: string): number {
  let hash = 2166136261;
  for (const byte of utf8.encode(id)) hash = Math.imul((hash ^ byte) >>> 0, 16777619) >>> 0;
  return (hash % 900) + 100;
}

export function robotName(session: Pick<AgentSession, "harness" | "sessionId">): string {
  return `${ROBOT_PREFIX[session.harness]}-${stableNumber(session.sessionId)}`;
}

export function robotFolder(harness: Harness): string {
  return ROBOT_FOLDER[harness];
}

export function robotTint(harness: Harness): string | null {
  return ROBOT_TINT[harness] ?? null;
}

export function robotPortrait(harness: Harness): string {
  return `/assets/characters/${robotFolder(harness)}/rotations/south.png`;
}
