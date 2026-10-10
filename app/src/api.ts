import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export type Harness = "claude" | "codex" | "gemini" | "copilot" | "cursor" | "pi" | "omp";
export type AgentStatus = "working" | "needsApproval" | "finished";
export type Language = "en" | "fr";
export type Platform = "macos" | "linux" | "windows";

export type TokenUsage = { input: number; output: number; cacheRead: number; cacheWrite: number };

export type AgentSession = {
  id: string;
  harness: Harness;
  sessionId: string;
  title: string;
  cwd: string;
  projectName: string;
  status: AgentStatus;
  startedAt: string | null;
  updatedAt: string;
  lastPrompt: string | null;
  lastReply: string | null;
  pendingAction: string | null;
  model: string | null;
  tokens: TokenUsage;
  promptCount: number;
  pid: number | null;
  transcriptPath: string | null;
  isLive: boolean;
};

export type TranscriptMessage = { role: "user" | "assistant" | "tool"; text: string; timestamp: string | null };

export type RateWindow = { label: string; usedPercent: number; resetsAt: string | null; windowMinutes: number | null };

export type UsageState =
  | { kind: "ok" | "notInstalled" | "signedOut" | "keychainBlocked" | "tokenExpired" | "noData" }
  | { kind: "failed"; message: string };

export type ProviderUsage = {
  harness: Harness;
  state: UsageState;
  plan: string | null;
  windows: RateWindow[];
  observedAt: string | null;
};

export type DailyTokens = { day: string; harness: Harness; tokens: TokenUsage };
export type UsageReport = { providers: ProviderUsage[]; daily: DailyTokens[] };

export type RuleKind = "instructions" | "skill" | "hook" | "agent" | "command" | "settings";
export type RuleItem = {
  id: string;
  kind: RuleKind;
  harness: Harness;
  scope: string;
  name: string;
  path: string;
  summary: string;
  size: number;
  modifiedAt: string | null;
};

export type SuggestionStatus = "new" | "applied" | "dismissed" | "saved";
export type SuggestionKind = "learnedRule" | "setupFix";
export type SuggestionOperation =
  | { type: "appendRule"; rule: string }
  | { type: "createFile"; body: string }
  | { type: "removeLines"; lines: string[] }
  | { type: "addFrontmatter"; name: string; description: string };
export type Evidence = { quote: string; context: string | null; harness: Harness; sessionId: string; date: string | null };
export type DiffLine = { kind: "context" | "added" | "removed" | "header"; text: string };

export type Suggestion = {
  id: string;
  kind: SuggestionKind;
  title: string;
  rationale: string;
  project: string;
  filePath: string;
  operation: SuggestionOperation;
  evidence: Evidence[];
  status: SuggestionStatus;
  createdAt: string;
  refinedRule: string | null;
  displayPath: string;
  diff: DiffLine[];
};

export type DayStat = { day: string; prompts: number; corrections: number; tokens: number };
export type Trend = { kind: "improving" | "degrading"; delta: number } | { kind: "stable" | "notEnoughData" };
export type AnalyticsReport = { days: DayStat[]; trend: Trend; correctionsThisWeek: number; promptsThisWeek: number };

export type DomainFact = { text: string; source: string; date: string | null };
export type DomainModel = {
  root: string;
  name: string;
  intent: string;
  conventions: DomainFact[];
  decisions: DomainFact[];
  activity: DomainFact[];
  agents: Partial<Record<Harness, number>>;
  conflicts: string[];
  exportPath: string;
  markdown: string;
  exportDiff: DiffLine[];
};

export type Settings = {
  notifications: boolean;
  sounds: boolean;
  zoom: number;
  finishedHours: number;
  autoRefine: boolean;
  language: Language;
};

export type Snapshot = {
  platform: Platform;
  sessions: AgentSession[];
  usage: UsageReport | null;
  rules: RuleItem[];
  suggestions: Suggestion[];
  analytics: AnalyticsReport | null;
  insightsReady: boolean;
  settings: Settings;
  whipCount: number;
  installedHarnesses: Harness[];
  refining: string[];
  repairingClaude: boolean;
};

export type FocusResult = { opened: boolean; command: string };

export const api = {
  snapshot: () => invoke<Snapshot>("snapshot"),
  messages: (sessionId: string) => invoke<TranscriptMessage[]>("messages", { sessionId }),
  setSuggestionStatus: (id: string, status: SuggestionStatus) => invoke<void>("set_suggestion_status", { id, status }),
  refineSuggestion: (id: string) => invoke<void>("refine_suggestion", { id }),
  domainProjects: () => invoke<string[]>("domain_projects"),
  domainModel: (root: string) => invoke<DomainModel>("domain_model", { root }),
  saveIntent: (root: string, intent: string) => invoke<void>("save_intent", { root, intent }),
  exportDomain: (root: string) => invoke<string>("export_domain", { root }),
  saveSettings: (settings: Settings) => invoke<void>("save_settings", { settings }),
  recordWhip: () => invoke<number>("record_whip"),
  focusSession: (sessionId: string) => invoke<FocusResult>("focus_session", { sessionId }),
  openClaudeLogin: () => invoke<void>("open_claude_login"),
  repairClaudeUsage: () => invoke<void>("repair_claude_usage"),
  refreshUsage: (force: boolean) => invoke<void>("refresh_usage", { force }),
};

export const events = {
  onSnapshot: (handler: (snapshot: Snapshot) => void): Promise<UnlistenFn> =>
    listen<Snapshot>("snapshot", (event) => handler(event.payload)),
  onToast: (handler: (text: string) => void): Promise<UnlistenFn> => listen<string>("toast", (event) => handler(event.payload)),
  onOpenPanel: (handler: (panel: string) => void): Promise<UnlistenFn> =>
    listen<string>("open-panel", (event) => handler(event.payload)),
  onSound: (handler: (name: string) => void): Promise<UnlistenFn> => listen<string>("sound", (event) => handler(event.payload)),
};
