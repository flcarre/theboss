import type { AgentStatus, Harness, Platform, RuleKind, TokenUsage, Trend, UsageReport } from "../api";
import { dayKey, tr } from "../i18n";

export const HARNESSES: Harness[] = ["claude", "codex", "gemini", "copilot", "cursor", "pi", "omp"];

export const HARNESS_NAME: Record<Harness, string> = {
  claude: "Claude Code",
  codex: "Codex",
  gemini: "Gemini",
  copilot: "Copilot",
  cursor: "Cursor",
  pi: "Pi",
  omp: "omp",
};

export const HARNESS_COLOR: Record<Harness, string> = {
  claude: "#D9773F",
  codex: "#3FBFA8",
  gemini: "#4F7BD9",
  copilot: "#8A63D2",
  cursor: "#9AA3AD",
  pi: "#8C6BF2",
  omp: "#5BD16E",
};

export const COLOR = {
  ink: "#2A1840",
  night: "#1E1A33",
  base: "#2B2547",
  raised: "#3A3260",
  outline: "#4E4580",
  cream: "#FFF6EC",
  paper: "#FCE7B0",
  crust: "#F5B942",
  crustDark: "#C9832A",
  pink: "#FF6B9A",
  textSecondary: "#B9B0D6",
  success: "#4CD18A",
  warning: "#FF9A2E",
  danger: "#FF5A5A",
  info: "#4FB3FF",
  muted: "#A8B0BD",
  inkSoft: "#4A3D66",
  card: "#FFFDF8",
} as const;

export const STATUS_COLOR: Record<AgentStatus, string> = {
  working: COLOR.success,
  needsApproval: COLOR.warning,
  finished: COLOR.muted,
};

export function statusLabel(status: AgentStatus): string {
  switch (status) {
    case "working":
      return tr("Working");
    case "needsApproval":
      return tr("Needs your approval");
    case "finished":
      return tr("Done");
  }
}

export const RULE_KINDS: RuleKind[] = ["instructions", "skill", "hook", "agent", "command", "settings"];

export function ruleKindLabel(kind: RuleKind): string {
  switch (kind) {
    case "instructions":
      return tr("Rules");
    case "skill":
      return tr("Skills");
    case "hook":
      return tr("Hooks");
    case "agent":
      return tr("Subagents");
    case "command":
      return tr("Commands");
    case "settings":
      return tr("Settings");
  }
}

export function trendLabel(trend: Trend): string {
  switch (trend.kind) {
    case "improving":
      return tr("Your setup is improving");
    case "degrading":
      return tr("Your setup is getting worse");
    case "stable":
      return tr("Your setup is stable");
    case "notEnoughData":
      return tr("Not enough data yet");
  }
}

export function gaugeColor(percent: number): string {
  return percent >= 90 ? COLOR.danger : percent >= 70 ? COLOR.warning : COLOR.success;
}

export function totalTokens(tokens: TokenUsage): number {
  return tokens.input + tokens.output + tokens.cacheRead + tokens.cacheWrite;
}

export function sumTokens(values: TokenUsage[]): TokenUsage {
  return values.reduce(
    (sum, value) => ({
      input: sum.input + value.input,
      output: sum.output + value.output,
      cacheRead: sum.cacheRead + value.cacheRead,
      cacheWrite: sum.cacheWrite + value.cacheWrite,
    }),
    { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  );
}

export function tokensOnDay(usage: UsageReport, day: string): TokenUsage {
  return sumTokens(usage.daily.filter((entry) => entry.day === day).map((entry) => entry.tokens));
}

export function tokensToday(usage: UsageReport): TokenUsage {
  return tokensOnDay(usage, dayKey(new Date()));
}

export function tokensLastDays(usage: UsageReport, days: number): TokenUsage {
  const now = new Date();
  const cutoff = dayKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() - (days - 1)));
  return sumTokens(usage.daily.filter((entry) => entry.day >= cutoff).map((entry) => entry.tokens));
}

export function isMac(platform: Platform | undefined): boolean {
  return platform === "macos";
}

export function capitalized(text: string): string {
  return text
    .split(" ")
    .map((word) => (word ? word[0].toUpperCase() + word.slice(1).toLowerCase() : word))
    .join(" ");
}

export function withAlpha(hex: string, alpha: number): string {
  const value = parseInt(hex.replace("#", ""), 16);
  return `rgba(${(value >> 16) & 0xff}, ${(value >> 8) & 0xff}, ${value & 0xff}, ${alpha})`;
}
