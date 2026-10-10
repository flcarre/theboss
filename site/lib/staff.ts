import type { Harness } from "./sprites";

export type RobotState = "working" | "waiting" | "done";

export type Robot = {
  id: string;
  harness: Harness;
  project: string;
  task: string;
  state: RobotState;
  desk: number;
  pending?: string;
  resume?: string;
  working: string;
};

export const STAFF: Robot[] = [
  {
    id: "claude-checkout",
    harness: "claude",
    project: "checkout-api",
    task: "Migrate the database to Postgres 17",
    state: "waiting",
    desk: 1,
    pending: "psql -f migrations/017_pg17.sql",
    working: "Running the migration now. Indexes next, then I'll check the slow queries.",
  },
  {
    id: "codex-pipeline",
    harness: "codex",
    project: "data-pipeline",
    task: "Speed up the nightly aggregation job",
    state: "working",
    desk: 0,
    working: "Heads down on the nightly aggregation job. 41 messages in, 63% of my five-hour budget used.",
  },
  {
    id: "cursor-dashboard",
    harness: "cursor",
    project: "web-dashboard",
    task: "Rebuild the home page with the new components",
    state: "working",
    desk: 2,
    working: "Rebuilding the home page with the new components. I'll wave if I need you.",
  },
  {
    id: "pi-ios",
    harness: "pi",
    project: "ios-app",
    task: "Fix the crash on launch",
    state: "working",
    desk: 3,
    working: "Writing the failing test first, like you told me. Twice.",
  },
  {
    id: "claude-infra",
    harness: "claude",
    project: "infra",
    task: "Rotate the staging TLS certificates",
    state: "waiting",
    desk: 4,
    pending: "terraform apply -target=module.tls",
    working: "Applying. Staging certificates rotate in about two minutes.",
  },
  {
    id: "omp-docs",
    harness: "omp",
    project: "docs-site",
    task: "Add the Windows install section",
    state: "done",
    desk: 5,
    resume: "omp --resume 8f2c1a",
    working: "Back on it. Adding screenshots to the Windows section.",
  },
];

export type PropInfo = { id: string; title: string; text: string; href?: string; cta?: string };

export const PROP_INFO: Record<string, PropInfo> = {
  screen: { id: "screen", title: "The wall screen", text: "Everyone who clocked in during the last twelve hours, at a glance.", href: "#tour", cta: "See it" },
  bookshelf: { id: "bookshelf", title: "The bookshelf", text: "CLAUDE.md, AGENTS.md, skills, hooks, subagents. Every rule your agents quietly follow.", href: "#tour", cta: "See it" },
  archive: { id: "archive", title: "The archive cabinet", text: "One source of truth per project. Intent, conventions, decisions.", href: "#tour", cta: "See it" },
  whiteboard: { id: "whiteboard", title: "The whiteboard", text: "Corrections per hundred prompts. The line is going down. Nice.", href: "#rules", cta: "See why" },
  intray: { id: "intray", title: "The in-tray", text: "Three letters. One of them is a rule you keep repeating.", href: "#rules", cta: "Open it" },
  coffee: { id: "coffee", title: "The coffee machine", text: "Purely decorative. Like most standups." },
  cooler: { id: "cooler", title: "The water cooler", text: "Nobody gossips here. They're robots." },
  servers: { id: "servers", title: "Server racks", text: "Blinking lights for ambience. Everything actually runs on your Mac.", href: "#local", cta: "Privacy" },
  sofa: { id: "sofa", title: "The sofa", text: "The boss's nap spot. Off limits during deploys." },
  window: { id: "window", title: "The window", text: "It's late. The robots don't mind." },
};
