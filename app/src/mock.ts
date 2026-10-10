import type {
  AgentSession,
  AgentStatus,
  AnalyticsReport,
  DailyTokens,
  DayStat,
  DiffLine,
  DomainFact,
  DomainModel,
  FocusResult,
  Harness,
  Language,
  Platform,
  ProviderUsage,
  RuleItem,
  RuleKind,
  Settings,
  Snapshot,
  Suggestion,
  SuggestionStatus,
  TranscriptMessage,
  UsageReport,
} from "./api";
import type { Backend, BackendEvents } from "./backend";

type Listener<T> = (value: T) => void;

const params = new URLSearchParams(typeof window === "undefined" ? "" : window.location.search);
const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
const startedAt = Date.now();

function pickPlatform(): Platform {
  const requested = params.get("platform");
  return requested === "linux" || requested === "windows" || requested === "macos" ? requested : "macos";
}

function pickLanguage(): Language {
  return params.get("lang") === "fr" ? "fr" : "en";
}

const platform = pickPlatform();
const home = platform === "windows" ? "C:\\Users\\boss" : platform === "linux" ? "/home/boss" : "/Users/boss";
const separator = platform === "windows" ? "\\" : "/";

function join(...parts: string[]): string {
  return parts.join(separator);
}

function projectRoot(project: string): string {
  return join(home, "code", project);
}

function ago(milliseconds: number): string {
  return new Date(Date.now() - milliseconds).toISOString();
}

function ahead(milliseconds: number): string {
  return new Date(Date.now() + milliseconds).toISOString();
}

function seeded(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function localDayKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

type SessionSeed = {
  harness: Harness;
  title: string;
  project: string;
  status: AgentStatus;
  minutesAgo: number;
  tokens: number;
  prompts: number;
  model: string | null;
  pending?: string;
  lastPrompt?: string;
  lastReply?: string;
  live?: boolean;
};

const SESSION_SEEDS: SessionSeed[] = [
  {
    harness: "copilot",
    title: "Passkey sign-in",
    project: "auth-service",
    status: "needsApproval",
    minutesAgo: 2,
    tokens: 0,
    prompts: 6,
    model: "gpt-5",
    pending: "shell · npx prisma migrate dev --name add_passkeys",
    lastPrompt: "Add passkey sign-in next to the password flow, behind the PASSKEYS flag.",
    live: true,
  },
  {
    harness: "claude",
    title: "Refund ledger",
    project: "checkout-api",
    status: "needsApproval",
    minutesAgo: 3,
    tokens: 560_300,
    prompts: 14,
    model: "claude-opus-5-5",
    pending: 'Bash · psql "$DATABASE_URL" -f migrations/042_refund_ledger.sql',
    lastPrompt: "Write the refund ledger migration and the double-entry checks. Refunds are negative entries.",
    live: true,
  },
  {
    harness: "omp",
    title: "Move CDN module",
    project: "infra",
    status: "needsApproval",
    minutesAgo: 4,
    tokens: 170_000,
    prompts: 5,
    model: "claude-sonnet-5",
    pending: "bash · terraform apply -target=module.cdn envs/staging",
    live: true,
  },
  {
    harness: "cursor",
    title: "Dark-mode charts",
    project: "web-dashboard",
    status: "working",
    minutesAgo: 0.07,
    tokens: 0,
    prompts: 3,
    model: null,
    live: true,
  },
  {
    harness: "claude",
    title: "Billing page redo",
    project: "web-dashboard",
    status: "working",
    minutesAgo: 0.15,
    tokens: 306_700,
    prompts: 9,
    model: "claude-opus-5-5",
    lastPrompt: "Redo the billing page with the new Table and Card components. Keep the invoice download link where it is.",
    live: true,
  },
  {
    harness: "copilot",
    title: "Release workflow",
    project: "release-bot",
    status: "working",
    minutesAgo: 0.65,
    tokens: 0,
    prompts: 4,
    model: "gpt-5",
    live: true,
  },
  {
    harness: "claude",
    title: "Offline crash fix",
    project: "ios-app",
    status: "working",
    minutesAgo: 0.8,
    tokens: 414_000,
    prompts: 11,
    model: "claude-opus-5-5",
    lastPrompt: "No, I told you: always write a test that reproduces the crash before fixing it.",
    live: true,
  },
  {
    harness: "gemini",
    title: "Fuzzy search",
    project: "search-service",
    status: "working",
    minutesAgo: 1,
    tokens: 241_500,
    prompts: 7,
    model: "gemini-3-pro",
    lastPrompt: "Add typo tolerance to product search, max two edits, and keep exact matches first.",
    live: true,
  },
  {
    harness: "codex",
    title: "Faster nightly job",
    project: "data-pipeline",
    status: "working",
    minutesAgo: 1.1,
    tokens: 250_100,
    prompts: 6,
    model: "gpt-5-codex",
    lastPrompt: "Speed up the nightly aggregation job. It must finish before 6 am.",
    live: true,
  },
  {
    harness: "gemini",
    title: "Pricing page copy",
    project: "marketing-site",
    status: "finished",
    minutesAgo: 58,
    tokens: 144_100,
    prompts: 5,
    model: "gemini-3-pro",
    lastReply: "The three plans now read the same way, and the FAQ answers the refund question in one line.",
  },
  {
    harness: "codex",
    title: "IAM role audit",
    project: "infra",
    status: "finished",
    minutesAgo: 64,
    tokens: 271_400,
    prompts: 8,
    model: "gpt-5-codex",
    lastReply: "Four roles still had s3:* on every bucket. I narrowed them and listed the changes in AUDIT.md.",
  },
  {
    harness: "pi",
    title: "Rounding tests",
    project: "checkout-api",
    status: "finished",
    minutesAgo: 70,
    tokens: 159_600,
    prompts: 4,
    model: "claude-sonnet-5",
    lastReply: "All rounding cases pass: half-even on every currency, including JPY with zero decimals.",
  },
  {
    harness: "claude",
    title: "Windows install guide",
    project: "docs-site",
    status: "finished",
    minutesAgo: 9 * 60,
    tokens: 98_200,
    prompts: 3,
    model: "claude-opus-5-5",
    lastReply: "The Windows section is written, with the winget command and the PATH fix.",
  },
];

function sessionId(seed: SessionSeed, index: number): string {
  const random = seeded(index * 977 + seed.title.length);
  return Array.from({ length: 4 }, () => Math.floor(random() * 0xffff).toString(16).padStart(4, "0")).join("-");
}

function buildSession(seed: SessionSeed, index: number): AgentSession {
  const id = sessionId(seed, index);
  const input = Math.round(seed.tokens * 0.62);
  const output = Math.round(seed.tokens * 0.05);
  const cacheRead = Math.round(seed.tokens * 0.28);
  return {
    id: `${seed.harness}:${id}`,
    harness: seed.harness,
    sessionId: id,
    title: seed.title,
    cwd: projectRoot(seed.project),
    projectName: seed.project,
    status: seed.status,
    startedAt: ago(seed.minutesAgo * MINUTE + 40 * MINUTE),
    updatedAt: ago(seed.minutesAgo * MINUTE),
    lastPrompt: seed.lastPrompt ?? null,
    lastReply: seed.lastReply ?? null,
    pendingAction: seed.pending ?? null,
    model: seed.model,
    tokens: { input, output, cacheRead, cacheWrite: Math.max(0, seed.tokens - input - output - cacheRead) },
    promptCount: seed.prompts,
    pid: seed.live ? 41_000 + index : null,
    transcriptPath: null,
    isLive: seed.live ?? false,
  };
}

const HARNESS_DAILY: Array<{ harness: Harness; base: number; spread: number }> = [
  { harness: "claude", base: 2_400_000, spread: 2_000_000 },
  { harness: "codex", base: 260_000, spread: 260_000 },
  { harness: "gemini", base: 160_000, spread: 260_000 },
  { harness: "copilot", base: 220_000, spread: 240_000 },
  { harness: "cursor", base: 40_000, spread: 60_000 },
  { harness: "pi", base: 60_000, spread: 90_000 },
  { harness: "omp", base: 50_000, spread: 70_000 },
];

function buildDaily(): DailyTokens[] {
  const random = seeded(42);
  const today = new Date();
  const rows: DailyTokens[] = [];
  for (let offset = 29; offset >= 0; offset--) {
    const date = new Date(today.getFullYear(), today.getMonth(), today.getDate() - offset);
    const weekend = date.getDay() === 0 || date.getDay() === 6;
    const damp = weekend ? 0.25 : offset === 0 ? 0.6 : 1;
    for (const { harness, base, spread } of HARNESS_DAILY) {
      if (weekend && harness !== "claude" && random() < 0.5) continue;
      const total = Math.round((base + random() * spread) * damp);
      const output = Math.round(total * 0.027);
      const input = Math.round(total * 0.3);
      rows.push({ day: localDayKey(date), harness, tokens: { input, output, cacheRead: total - input - output, cacheWrite: 0 } });
    }
  }
  return rows;
}

function healthyProviders(): ProviderUsage[] {
  return [
    {
      harness: "claude",
      state: { kind: "ok" },
      plan: "max",
      observedAt: ago(MINUTE),
      windows: [
        { label: "5 h", usedPercent: 42, resetsAt: ahead(2 * HOUR + 10 * MINUTE), windowMinutes: 300 },
        { label: "Week", usedPercent: 67, resetsAt: ahead(3 * DAY + 2 * HOUR), windowMinutes: 10080 },
        { label: "Week · Opus", usedPercent: 23, resetsAt: ahead(3 * DAY + 2 * HOUR), windowMinutes: 10080 },
      ],
    },
    {
      harness: "codex",
      state: { kind: "ok" },
      plan: "pro",
      observedAt: ago(9 * MINUTE),
      windows: [
        { label: "5 h", usedPercent: 74, resetsAt: ahead(HOUR + 5 * MINUTE), windowMinutes: 300 },
        { label: "Week", usedPercent: 31, resetsAt: ahead(4 * DAY + 3 * HOUR), windowMinutes: 10080 },
      ],
    },
    {
      harness: "cursor",
      state: { kind: "ok" },
      plan: "pro",
      observedAt: ago(MINUTE),
      windows: [
        { label: "Monthly plan", usedPercent: 38, resetsAt: ahead(8 * DAY), windowMinutes: null },
        { label: "On-demand", usedPercent: 6, resetsAt: ahead(8 * DAY), windowMinutes: null },
      ],
    },
  ];
}

function brokenProviders(): ProviderUsage[] {
  return [
    { harness: "claude", state: { kind: "tokenExpired" }, plan: "max", observedAt: ago(40 * MINUTE), windows: [] },
    {
      harness: "codex",
      state: { kind: "ok" },
      plan: "pro",
      observedAt: ago(9 * MINUTE),
      windows: [{ label: "5 h", usedPercent: 93, resetsAt: ahead(20 * MINUTE), windowMinutes: 300 }],
    },
    { harness: "cursor", state: { kind: "signedOut" }, plan: null, observedAt: null, windows: [] },
    { harness: "gemini", state: { kind: "noData" }, plan: null, observedAt: null, windows: [] },
    { harness: "copilot", state: { kind: platform === "macos" ? "keychainBlocked" : "notInstalled" }, plan: null, observedAt: null, windows: [] },
  ];
}

function buildUsage(): UsageReport {
  return { providers: params.get("usage") === "broken" ? brokenProviders() : healthyProviders(), daily: buildDaily() };
}

type RuleSeed = [RuleKind, Harness, string, string, string, string];

const RULE_SEEDS: RuleSeed[] = [
  ["instructions", "claude", "Global", "CLAUDE.md", ".claude/CLAUDE.md", "Personal rules for every project"],
  ["settings", "claude", "Global", "settings.json", ".claude/settings.json", '"permissions": { "allow": ["Bash(pnpm test:*)"] }'],
  ["hook", "claude", "Global", "PostToolUse · Edit", ".claude/settings.json", "pnpm lint --fix --quiet"],
  ["skill", "claude", "Global", "release-notes", ".claude/skills/release-notes/SKILL.md", ""],
  ["command", "claude", "Global", "review", ".claude/commands/review.md", "Review the staged diff like a senior engineer."],
  ["instructions", "codex", "Global", "AGENTS.md", ".codex/AGENTS.md", "Answer briefly. Never push to main."],
  ["instructions", "gemini", "Global", "GEMINI.md", ".gemini/GEMINI.md", "Use the project's formatter before saying a task is done."],
  ["agent", "claude", "checkout-api", "ledger-auditor", "code/checkout-api/.claude/agents/ledger-auditor.md", "Reviews any change touching the ledger tables for double-entry and sign errors."],
  ["command", "claude", "checkout-api", "new-migration", "code/checkout-api/.claude/commands/new-migration.md", "Scaffold the next numbered SQL migration with up/down sections."],
  ["hook", "claude", "checkout-api", "PostToolUse · Edit|Write", "code/checkout-api/.claude/settings.json", "pnpm lint --fix --quiet"],
  ["hook", "claude", "checkout-api", "PreToolUse · Bash", "code/checkout-api/.claude/settings.json", "./scripts/guard-prod-db.sh"],
  ["instructions", "codex", "checkout-api", "AGENTS.md", "code/checkout-api/AGENTS.md", "checkout-api"],
  ["instructions", "claude", "checkout-api", "CLAUDE.md", "code/checkout-api/CLAUDE.md", "checkout-api"],
  ["instructions", "cursor", "checkout-api", "payments", "code/checkout-api/.cursor/rules/payments.mdc", "Payments code must go through PaymentsGateway and use integer cents."],
  ["skill", "claude", "checkout-api", "stripe-webhooks", "code/checkout-api/.claude/skills/stripe-webhooks/SKILL.md", "How to add or change a Stripe webhook handler safely (signature check, idempotency, replay tests)."],
  ["instructions", "claude", "data-pipeline", "CLAUDE.md", "code/data-pipeline/CLAUDE.md", "data-pipeline"],
  ["skill", "codex", "data-pipeline", "backfill", "code/data-pipeline/.codex/skills/backfill/SKILL.md", "Run a partitioned backfill without locking the warehouse."],
  ["instructions", "claude", "web-dashboard", "CLAUDE.md", "code/web-dashboard/CLAUDE.md", "web-dashboard"],
  ["instructions", "copilot", "web-dashboard", "copilot-instructions.md", "code/web-dashboard/.github/copilot-instructions.md", "Use the design-system components, never raw HTML tables."],
  ["hook", "gemini", "search-service", "AfterTool · write_file", "code/search-service/.gemini/settings.json", "make fmt"],
  ["instructions", "claude", "ios-app", "CLAUDE.md", "code/ios-app/CLAUDE.md", "ios-app"],
  ["agent", "claude", "ios-app", "crash-reproducer", "code/ios-app/.claude/agents/crash-reproducer.md", "Writes a failing XCTest from a crash log before anyone touches the fix."],
  ["instructions", "pi", "infra", "AGENTS.md", "code/infra/AGENTS.md", "infra"],
];

function buildRules(): RuleItem[] {
  return RULE_SEEDS.map(([kind, harness, scope, name, relativePath, summary], index) => {
    const path = join(home, ...relativePath.split("/"));
    return {
      id: `${path}#${name}`,
      kind,
      harness,
      scope,
      name,
      path,
      summary,
      size: 180 + ((index * 337) % 2400),
      modifiedAt: ago((index + 1) * 13 * HOUR),
    };
  });
}

const RULE_BODIES: Record<string, string> = {
  "stripe-webhooks": [
    "---",
    "name: stripe-webhooks",
    "description: How to add or change a Stripe webhook handler safely (signature check, idempotency, replay tests).",
    "---",
    "",
    "# Stripe webhooks",
    "",
    "1. Verify the signature with `verifyStripeSignature` before parsing.",
    "2. Store the event id in `processed_events` and bail out if it is already there.",
    "3. Add a replay test under test/webhooks.",
  ].join("\n"),
  "CLAUDE.md": [
    "# checkout-api",
    "",
    "- Money is always an integer number of minor units (cents). Never use floats for amounts.",
    "- Every endpoint validates its body with a zod schema from src/schemas.",
    "- Database changes go through a numbered SQL migration in migrations/.",
    "- Run `pnpm test` and `pnpm lint` before saying a task is done.",
    "",
    "## Learned rules",
    "",
    "- Log the idempotency key on every write endpoint.",
    "- Keep refund amounts signed: refunds are negative ledger entries.",
  ].join("\n"),
};

export async function mockRuleContent(path: string): Promise<string> {
  const rule = state.rules.find((item) => item.path === path);
  if (!rule) return "";
  if (rule.kind === "hook") return JSON.stringify({ hooks: { [rule.name.split(" · ")[0]]: [{ matcher: rule.name.split(" · ")[1] ?? "", hooks: [{ type: "command", command: rule.summary }] }] } }, null, 2);
  const body = rule.scope === "checkout-api" ? RULE_BODIES[rule.name] : undefined;
  return body ?? `# ${rule.name}\n\n${rule.summary}\n\n- Keep answers short.\n- Run the tests before saying a task is done.\n`;
}

function diffForRule(displayPath: string, context: string[], added: string[], start: number): DiffLine[] {
  return [
    { kind: "header", text: `--- a/${displayPath}` },
    { kind: "header", text: `+++ b/${displayPath}` },
    { kind: "header", text: `@@ -${start},${context.length} +${start},${context.length + added.length} @@` },
    ...context.map((text): DiffLine => ({ kind: "context", text: ` ${text}` })),
    ...added.map((text): DiffLine => ({ kind: "added", text: `+${text}` })),
  ];
}

type SuggestionSeed = Omit<Suggestion, "id" | "createdAt" | "refinedRule" | "filePath" | "displayPath"> & { file: string; hoursAgo: number };

const SUGGESTION_SEEDS: SuggestionSeed[] = [
  {
    kind: "learnedRule",
    title: "Never call Stripe directly from a controller.",
    rationale: "You corrected the agent 2 times on this in checkout-api. A written rule saves you from repeating it.",
    project: "checkout-api",
    file: "code/checkout-api/CLAUDE.md",
    operation: { type: "appendRule", rule: "Never call Stripe directly from a controller." },
    evidence: [
      {
        quote: "No, never call Stripe directly from a controller. Go through PaymentsGateway so we can swap providers.",
        context: "I call stripe.refunds.create() straight from RefundsController to keep it simple.",
        harness: "claude",
        sessionId: "a1",
        date: ago(8 * DAY),
      },
      {
        quote: "Why did you import Stripe in the controller? Never call Stripe directly from a controller.",
        context: "Added the Stripe SDK import to RefundsController and wired the refund call.",
        harness: "claude",
        sessionId: "a2",
        date: ago(2 * DAY),
      },
    ],
    status: "new",
    diff: [],
    hoursAgo: 3,
  },
  {
    kind: "learnedRule",
    title: "Never edit a live index mapping.",
    rationale: "You corrected the agent 2 times on this in search-service. A written rule saves you from repeating it.",
    project: "search-service",
    file: "code/search-service/GEMINI.md",
    operation: { type: "appendRule", rule: "Never edit a live index mapping." },
    evidence: [
      { quote: "Stop, never edit the live mapping. Create a new index and switch the alias.", context: "Updating the products mapping in place to add the fuzzy analyzer.", harness: "gemini", sessionId: "g1", date: ago(4 * DAY) },
      { quote: "Again: don't touch the live index mapping, reindex behind an alias.", context: null, harness: "gemini", sessionId: "g2", date: ago(DAY) },
    ],
    status: "new",
    diff: [],
    hoursAgo: 5,
  },
  {
    kind: "learnedRule",
    title: "Use async/await instead of completion handlers in new code.",
    rationale: "You corrected the agent 2 times on this in ios-app. A written rule saves you from repeating it.",
    project: "ios-app",
    file: "code/ios-app/CLAUDE.md",
    operation: { type: "appendRule", rule: "Use async/await instead of completion handlers in new code." },
    evidence: [
      { quote: "No completion handlers in new code, use async/await.", context: "Added fetchProfile(completion:) to ProfileService.", harness: "claude", sessionId: "i1", date: ago(6 * DAY) },
      { quote: "I told you, async/await only for new code.", context: "Wrapped the sync call in a completion handler for consistency.", harness: "claude", sessionId: "i2", date: ago(3 * DAY) },
    ],
    status: "new",
    diff: [],
    hoursAgo: 7,
  },
  {
    kind: "learnedRule",
    title: "Prefer polars over pandas for anything over a million rows.",
    rationale: "You corrected the agent on this in data-pipeline. A written rule keeps it from happening again.",
    project: "data-pipeline",
    file: "code/data-pipeline/AGENTS.md",
    operation: { type: "appendRule", rule: "Prefer polars over pandas for anything over a million rows." },
    evidence: [{ quote: "Not pandas, this table has 40M rows. Use polars.", context: "Loading the events table with pandas.read_parquet().", harness: "codex", sessionId: "c1", date: ago(2 * DAY) }],
    status: "new",
    diff: [],
    hoursAgo: 9,
  },
  {
    kind: "setupFix",
    title: "Describe the release-notes skill",
    rationale: "Without a name/description header, the agent does not know when to use this skill.",
    project: "Global",
    file: ".claude/skills/release-notes/SKILL.md",
    operation: { type: "addFrontmatter", name: "release-notes", description: "Write the release notes from the merged PRs since the last tag." },
    evidence: [],
    status: "new",
    diff: [],
    hoursAgo: 20,
  },
  {
    kind: "setupFix",
    title: "Make Gemini read AGENTS.md",
    rationale: "marketing-site has an AGENTS.md but no GEMINI.md: Gemini CLI does not read your rules in this project.",
    project: "marketing-site",
    file: "code/marketing-site/GEMINI.md",
    operation: { type: "createFile", body: "@AGENTS.md\n" },
    evidence: [],
    status: "new",
    diff: [],
    hoursAgo: 22,
  },
  {
    kind: "setupFix",
    title: "Share the CLAUDE.md rules with other agents",
    rationale: "Codex and Pi read AGENTS.md, which data-pipeline lacks: they work without the CLAUDE.md rules.",
    project: "data-pipeline",
    file: "code/data-pipeline/AGENTS.md",
    operation: { type: "createFile", body: "@CLAUDE.md\n" },
    evidence: [],
    status: "new",
    diff: [],
    hoursAgo: 23,
  },
  {
    kind: "setupFix",
    title: "Remove a broken import",
    rationale: "docs-site/CLAUDE.md points to a file that no longer exists: the agent silently loses that part of its rules.",
    project: "docs-site",
    file: "code/docs-site/CLAUDE.md",
    operation: { type: "removeLines", lines: ["@docs/old-style-guide.md"] },
    evidence: [],
    status: "new",
    diff: [],
    hoursAgo: 26,
  },
  {
    kind: "learnedRule",
    title: "Log the idempotency key on every write endpoint.",
    rationale: "You corrected the agent 3 times on this in checkout-api. A written rule saves you from repeating it.",
    project: "checkout-api",
    file: "code/checkout-api/CLAUDE.md",
    operation: { type: "appendRule", rule: "Log the idempotency key on every write endpoint." },
    evidence: [{ quote: "You forgot to log the idempotency key again.", context: null, harness: "claude", sessionId: "a3", date: ago(12 * DAY) }],
    status: "applied",
    diff: [],
    hoursAgo: 240,
  },
  {
    kind: "learnedRule",
    title: "Keep refund amounts signed: refunds are negative ledger entries.",
    rationale: "You corrected the agent 2 times on this in checkout-api. A written rule saves you from repeating it.",
    project: "checkout-api",
    file: "code/checkout-api/CLAUDE.md",
    operation: { type: "appendRule", rule: "Keep refund amounts signed: refunds are negative ledger entries." },
    evidence: [{ quote: "Refunds are negative, don't store abs().", context: "Storing the refund amount as a positive value.", harness: "claude", sessionId: "a4", date: ago(11 * DAY) }],
    status: "applied",
    diff: [],
    hoursAgo: 230,
  },
  {
    kind: "setupFix",
    title: "Make Claude Code read AGENTS.md",
    rationale: "infra has an AGENTS.md but no CLAUDE.md: Claude Code does not read your rules in this project.",
    project: "infra",
    file: "code/infra/CLAUDE.md",
    operation: { type: "createFile", body: "@AGENTS.md\n" },
    evidence: [],
    status: "applied",
    diff: [],
    hoursAgo: 200,
  },
];

function displayPathOf(relativePath: string): string {
  return `~/${relativePath}`;
}

function diffFor(seed: SuggestionSeed, displayPath: string, rule: string | null): DiffLine[] {
  switch (seed.operation.type) {
    case "appendRule":
      return diffForRule(
        displayPath,
        ["", "- Log the idempotency key on every write endpoint.", "- Keep refund amounts signed: refunds are negative ledger entries."],
        [`- ${rule ?? seed.operation.rule}`],
        13,
      );
    case "createFile":
      return [
        { kind: "header", text: "--- /dev/null" },
        { kind: "header", text: `+++ b/${displayPath}` },
        { kind: "header", text: "@@ -0,0 +1,1 @@" },
        ...seed.operation.body.trimEnd().split("\n").map((text): DiffLine => ({ kind: "added", text: `+${text}` })),
      ];
    case "removeLines":
      return [
        { kind: "header", text: `--- a/${displayPath}` },
        { kind: "header", text: `+++ b/${displayPath}` },
        { kind: "header", text: "@@ -1,5 +1,4 @@" },
        { kind: "context", text: " # docs-site" },
        { kind: "context", text: " " },
        ...seed.operation.lines.map((text): DiffLine => ({ kind: "removed", text: `-${text}` })),
        { kind: "context", text: " - Every page needs a description in its frontmatter." },
      ];
    case "addFrontmatter":
      return [
        { kind: "header", text: `--- a/${displayPath}` },
        { kind: "header", text: `+++ b/${displayPath}` },
        { kind: "header", text: "@@ -1,3 +1,7 @@" },
        { kind: "added", text: "+---" },
        { kind: "added", text: `+name: ${seed.operation.name}` },
        { kind: "added", text: `+description: ${seed.operation.description}` },
        { kind: "added", text: "+---" },
        { kind: "context", text: " # Release notes" },
        { kind: "context", text: " " },
        { kind: "context", text: " Group the merged PRs by label, newest first." },
      ];
  }
}

function buildSuggestions(): Suggestion[] {
  return SUGGESTION_SEEDS.map((seed, index) => {
    const { file, hoursAgo, ...rest } = seed;
    const displayPath = displayPathOf(file);
    return {
      ...rest,
      id: `suggestion-${index}`,
      createdAt: ago(hoursAgo * HOUR),
      refinedRule: null,
      filePath: join(home, ...file.split("/")),
      displayPath,
      diff: seed.status === "applied" ? [] : diffFor(seed, displayPath, null),
    };
  });
}

function buildAnalytics(): AnalyticsReport {
  const random = seeded(7);
  const today = new Date();
  const days: DayStat[] = [];
  for (let offset = 27; offset >= 0; offset--) {
    const date = new Date(today.getFullYear(), today.getMonth(), today.getDate() - offset);
    const weekend = date.getDay() === 0 || date.getDay() === 6;
    const prompts = weekend ? 8 + Math.floor(random() * 8) : 32 + Math.floor(random() * 22);
    const rate = Math.max(0.02, 0.2 - (27 - offset) * 0.005 + (random() - 0.5) * 0.08);
    days.push({ day: localDayKey(date), prompts, corrections: Math.round(prompts * rate), tokens: 0 });
  }
  const lastWeek = days.slice(-7);
  return {
    days,
    trend: { kind: "improving", delta: -0.42 },
    promptsThisWeek: lastWeek.reduce((sum, day) => sum + day.prompts, 0),
    correctionsThisWeek: lastWeek.reduce((sum, day) => sum + day.corrections, 0),
  };
}

const DEFAULT_SETTINGS: Settings = {
  notifications: true,
  sounds: true,
  zoom: 1.5,
  finishedHours: 6,
  autoRefine: false,
  language: pickLanguage(),
};

type MockState = {
  sessions: AgentSession[];
  usage: UsageReport;
  rules: RuleItem[];
  suggestions: Suggestion[];
  analytics: AnalyticsReport;
  settings: Settings;
  whipCount: number;
  refining: string[];
  repairingClaude: boolean;
  intents: Record<string, string>;
  exported: Record<string, string>;
};

const state: MockState = {
  sessions: SESSION_SEEDS.map(buildSession),
  usage: buildUsage(),
  rules: buildRules(),
  suggestions: buildSuggestions(),
  analytics: buildAnalytics(),
  settings: DEFAULT_SETTINGS,
  whipCount: 3,
  refining: [],
  repairingClaude: false,
  intents: {
    [projectRoot("checkout-api")]:
      "Let merchants refund any payment, fully or partially, in under a second, with a ledger that always balances. Correctness of money beats speed of shipping.",
  },
  exported: {},
};

const snapshotListeners = new Set<Listener<Snapshot>>();
const toastListeners = new Set<Listener<string>>();
const panelListeners = new Set<Listener<string>>();
const soundListeners = new Set<Listener<string>>();

function snapshot(): Snapshot {
  return {
    platform,
    sessions: state.sessions,
    usage: params.get("usage") === "loading" ? null : state.usage,
    rules: state.rules,
    suggestions: state.suggestions,
    analytics: state.analytics,
    insightsReady: params.get("insights") !== "loading",
    settings: state.settings,
    whipCount: state.whipCount,
    installedHarnesses: ["claude", "codex", "gemini", "copilot", "cursor", "pi", "omp"],
    refining: state.refining,
    repairingClaude: state.repairingClaude,
  };
}

function emit(): void {
  const current = snapshot();
  snapshotListeners.forEach((listener) => listener(current));
}

function toast(text: string): void {
  toastListeners.forEach((listener) => listener(text));
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function tick(): void {
  state.sessions = state.sessions.map((session) => {
    if (session.status !== "working") return session;
    return { ...session, updatedAt: new Date().toISOString(), tokens: { ...session.tokens, output: session.tokens.output + (session.tokens.output > 0 ? 180 : 0) } };
  });
  emit();
}

if (typeof window !== "undefined" && !("__TAURI_INTERNALS__" in window)) {
  window.setInterval(tick, 2000);
}

function messagesFor(session: AgentSession): TranscriptMessage[] {
  if (session.harness === "cursor") return [];
  const opening = session.lastPrompt ?? `${session.title}, please.`;
  const minutes = (Date.now() - startedAt) / MINUTE;
  const stamp = (offset: number) => ago((offset + minutes) * MINUTE);
  const thread: TranscriptMessage[] = [
    { role: "user", text: opening, timestamp: stamp(38) },
    { role: "assistant", text: `On it. I'll start by reading the code around “${session.title.toLowerCase()}” in ${session.projectName}.`, timestamp: stamp(37) },
    { role: "tool", text: "Read src/index.ts (212 lines)", timestamp: stamp(36) },
    {
      role: "assistant",
      text: "I found where it happens. The current code mixes two concerns, so I'll split it first, then add a test that fails before the change.",
      timestamp: stamp(30),
    },
    { role: "user", text: "Good. Keep the public API unchanged.", timestamp: stamp(28) },
    { role: "assistant", text: "Understood: the exported functions keep their signatures. The test is written and fails as expected.", timestamp: stamp(20) },
  ];
  if (session.pendingAction) thread.push({ role: "assistant", text: `I need to run this next:\n${session.pendingAction}`, timestamp: stamp(session.status === "needsApproval" ? 3 : 10) });
  if (session.lastReply) thread.push({ role: "assistant", text: session.lastReply, timestamp: stamp(1) });
  return thread;
}

function resumeCommand(session: AgentSession): string {
  const cd = session.cwd ? `cd '${session.cwd}' && ` : "";
  const commands: Record<Harness, string> = {
    claude: `claude --resume ${session.sessionId}`,
    codex: `codex resume ${session.sessionId}`,
    gemini: `gemini --resume ${session.sessionId}`,
    copilot: `copilot --resume ${session.sessionId}`,
    cursor: `cursor-agent resume ${session.sessionId}`,
    pi: "pi --continue",
    omp: "omp --continue",
  };
  return cd + commands[session.harness];
}

function domainRoots(): string[] {
  const seen = new Set<string>();
  for (const session of state.sessions) seen.add(session.cwd);
  return [...seen];
}

function nameOf(root: string): string {
  return root.split(separator).pop() ?? root;
}

const CONVENTIONS: Record<string, DomainFact[]> = {
  "checkout-api": [
    { text: "Money is always an integer number of minor units (cents). Never use floats for amounts.", source: "CLAUDE.md", date: null },
    { text: "Every endpoint validates its body with a zod schema from src/schemas.", source: "CLAUDE.md", date: null },
    { text: "Database changes go through a numbered SQL migration in migrations/.", source: "CLAUDE.md", date: null },
    { text: "Run `pnpm test` and `pnpm lint` before saying a task is done.", source: "CLAUDE.md", date: null },
    { text: "Money is always an integer number of minor units (cents). Never use floats for amounts.", source: "AGENTS.md", date: null },
    { text: "Run `pnpm test` before saying a task is done.", source: "AGENTS.md", date: null },
    { text: "Commit messages follow Conventional Commits.", source: "AGENTS.md", date: null },
    { text: "Payments code must go through PaymentsGateway and use integer cents.", source: ".cursor/rules/payments.mdc", date: null },
  ],
  "web-dashboard": [
    { text: "Use the design-system components, never raw HTML tables.", source: "copilot-instructions.md", date: null },
    { text: "Charts use the shared palette from src/theme/colors.ts.", source: "CLAUDE.md", date: null },
  ],
  "data-pipeline": [{ text: "Every job is idempotent and can be re-run for a single partition.", source: "CLAUDE.md", date: null }],
};

function buildDomain(root: string): DomainModel {
  const name = nameOf(root);
  const sessions = state.sessions.filter((session) => session.cwd === root);
  const agents: Partial<Record<Harness, number>> = {};
  for (const session of sessions) agents[session.harness] = (agents[session.harness] ?? 0) + 1;
  const decisions: DomainFact[] = state.suggestions
    .filter((suggestion) => suggestion.project === name && suggestion.kind === "learnedRule" && suggestion.status !== "dismissed")
    .map((suggestion) => ({
      text: suggestion.refinedRule ?? suggestion.title,
      source: suggestion.status === "applied" ? "CLAUDE.md" : "mail · pending",
      date: suggestion.createdAt,
    }));
  const activity: DomainFact[] = sessions.map((session) => ({
    text: session.title,
    source: `${session.harness === "claude" ? "Claude Code" : session.harness} · ${session.status === "finished" ? "done" : session.status === "working" ? "working" : "waiting"}`,
    date: session.updatedAt,
  }));
  const intent = state.intents[root] ?? "";
  const conventions = CONVENTIONS[name] ?? [];
  const markdown = [
    `# ${name} · domain model`,
    "",
    "## Intent",
    "",
    intent || "_To be written._",
    "",
    "## Conventions",
    "",
    ...conventions.map((fact) => `- ${fact.text}`),
    "",
    "## Decisions",
    "",
    ...decisions.map((fact) => `- ${fact.text}`),
    "",
    "## Recent work",
    "",
    ...activity.map((fact) => `- ${fact.text}`),
    "",
  ].join("\n");
  const previous = state.exported[root] ?? "";
  const exportDiff: DiffLine[] =
    previous === markdown
      ? []
      : [
          { kind: "header", text: previous ? "--- a/.boss/domain.md" : "--- /dev/null" },
          { kind: "header", text: "+++ b/.boss/domain.md" },
          { kind: "header", text: `@@ -0,0 +1,${markdown.split("\n").length} @@` },
          ...markdown.split("\n").map((text): DiffLine => ({ kind: "added", text: `+${text}` })),
        ];
  return {
    root,
    name,
    intent,
    conventions,
    decisions,
    activity,
    agents,
    conflicts: name === "checkout-api" ? ["CLAUDE.md and AGENTS.md disagree: 5 rules only for Claude, 2 only for the other agents."] : [],
    exportPath: join(root, ".boss", "domain.md"),
    markdown,
    exportDiff,
  };
}

function setStatus(id: string, status: SuggestionStatus): void {
  state.suggestions = state.suggestions.map((suggestion) =>
    suggestion.id === id ? { ...suggestion, status, diff: status === "applied" ? [] : suggestion.diff } : suggestion,
  );
}

export const mockApi: Backend = {
  snapshot: async () => snapshot(),
  messages: async (sessionId: string) => {
    const session = state.sessions.find((item) => item.id === sessionId);
    return session ? messagesFor(session) : [];
  },
  setSuggestionStatus: async (id: string, status: SuggestionStatus) => {
    await wait(80);
    setStatus(id, status);
    emit();
  },
  refineSuggestion: async (id: string) => {
    state.refining = [...state.refining, id];
    emit();
    await wait(1600);
    state.refining = state.refining.filter((item) => item !== id);
    state.suggestions = state.suggestions.map((suggestion) => {
      if (suggestion.id !== id || suggestion.operation.type !== "appendRule") return suggestion;
      const refined = `${suggestion.operation.rule.replace(/\.$/, "")}: go through the dedicated gateway or service layer instead.`;
      const seed = SUGGESTION_SEEDS[Number(id.split("-")[1])];
      return { ...suggestion, refinedRule: refined, diff: seed ? diffFor(seed, suggestion.displayPath, refined) : suggestion.diff };
    });
    emit();
    toast(state.settings.language === "fr" ? "Règle reformulée par Claude" : "Rule rewritten by Claude");
  },
  domainProjects: async () => domainRoots(),
  domainModel: async (root: string) => buildDomain(root),
  saveIntent: async (root: string, intent: string) => {
    state.intents = { ...state.intents, [root]: intent };
  },
  exportDomain: async (root: string) => {
    const model = buildDomain(root);
    state.exported = { ...state.exported, [root]: model.markdown };
    return `${model.name}/.boss/domain.md`;
  },
  saveSettings: async (settings: Settings) => {
    state.settings = settings;
    emit();
  },
  recordWhip: async () => {
    state.whipCount += 1;
    emit();
    return state.whipCount;
  },
  focusSession: async (sessionId: string): Promise<FocusResult> => {
    const session = state.sessions.find((item) => item.id === sessionId);
    return { opened: false, command: session ? resumeCommand(session) : "" };
  },
  openClaudeLogin: async () => {
    console.info("[browser mode] claude auth login");
  },
  repairClaudeUsage: async () => {
    state.repairingClaude = true;
    emit();
    await wait(2000);
    state.repairingClaude = false;
    state.usage = { ...state.usage, providers: healthyProviders() };
    emit();
    toast(state.settings.language === "fr" ? "Jeton Claude rafraîchi" : "Claude token refreshed");
  },
  refreshUsage: async () => {
    await wait(300);
    emit();
  },
};

export const mockEvents: BackendEvents = {
  onSnapshot: async (handler: Listener<Snapshot>) => {
    snapshotListeners.add(handler);
    return () => snapshotListeners.delete(handler);
  },
  onToast: async (handler: Listener<string>) => {
    toastListeners.add(handler);
    return () => toastListeners.delete(handler);
  },
  onOpenPanel: async (handler: Listener<string>) => {
    panelListeners.add(handler);
    return () => panelListeners.delete(handler);
  },
  onSound: async (handler: Listener<string>) => {
    soundListeners.add(handler);
    return () => soundListeners.delete(handler);
  },
};
