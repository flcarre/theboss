import { StrictMode, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import type { AgentSession, AgentStatus, Harness } from "../api";
import { Game } from "./Game";
import { robotName } from "./robotName";
import type { GameCallbacks, GameHandle, RoomId } from "./types";

const HARNESSES: Harness[] = ["claude", "codex", "gemini", "copilot", "cursor", "pi", "omp"];
const STATUSES: AgentStatus[] = ["working", "needsApproval", "finished"];
const PROJECTS = ["checkout-api", "data-pipeline", "ios-app", "infra", "web-dashboard", "search-service", "", "docs-site", "release-bot", "auth-service"];
const TITLES = [
  "Migrate to Postgres 17",
  "Speed up the nightly aggregation job with incremental windows",
  "Fix the crash on launch",
  "Rotate staging TLS certs",
  "Rebuild the home page",
  "Tune the ranking weights",
  "Add a --json flag",
  "Windows install guide",
  "Release workflow",
  "Passkey sign-in",
];

function makeSession(index: number): AgentSession {
  const harness = HARNESSES[index % HARNESSES.length];
  const status = STATUSES[index % STATUSES.length];
  return {
    id: `session-${index}`,
    harness,
    sessionId: `uuid-${index}-${harness}`,
    title: TITLES[index % TITLES.length],
    cwd: "/tmp",
    projectName: PROJECTS[index % PROJECTS.length],
    status,
    startedAt: null,
    updatedAt: new Date().toISOString(),
    lastPrompt: null,
    lastReply: null,
    pendingAction: null,
    model: null,
    tokens: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    promptCount: 0,
    pid: null,
    transcriptPath: null,
    isLive: true,
  };
}

function DevHarness() {
  const [sessions, setSessions] = useState<AgentSession[]>(() => Array.from({ length: 10 }, (_, i) => makeSession(i)));
  const [inbox, setInbox] = useState(3);
  const [zoom, setZoom] = useState(1.5);
  const [blocked, setBlocked] = useState(false);
  const [log, setLog] = useState<string[]>([]);
  const [nextIndex, setNextIndex] = useState(10);
  const gameRef = useRef<GameHandle>(null);

  const push = (line: string) => setLog((previous) => [line, ...previous].slice(0, 8));

  const callbacks = useMemo<GameCallbacks>(
    () => ({
      onInteract: (interaction, session) => push(`interact ${interaction} ${session ? robotName(session) : "-"}`),
      onWhip: (session) => push(`whip ${session ? robotName(session) : "-"}`),
      onMenu: () => push("menu"),
      onEnterRoom: (room: RoomId) => push(`enter ${room}`),
      onSound: (name) => push(`sound ${name}`),
    }),
    [],
  );

  const cycle = (id: string) =>
    setSessions((previous) =>
      previous.map((s) => (s.id === id ? { ...s, status: STATUSES[(STATUSES.indexOf(s.status) + 1) % STATUSES.length] } : s)),
    );

  return (
    <div style={{ display: "flex", height: "100%" }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <Game ref={gameRef} floorSessions={sessions} inboxCount={inbox} zoom={zoom} inputBlocked={blocked} callbacks={callbacks} />
      </div>
      <div style={{ width: 230, padding: 8, overflow: "auto", display: "flex", flexDirection: "column", gap: 4 }}>
        <button onClick={() => gameRef.current?.enterRoom("office")}>office</button>
        <button onClick={() => gameRef.current?.enterRoom("openSpace")}>open space</button>
        <button onClick={() => gameRef.current?.crackWhip()}>crack whip</button>
        <button onClick={() => gameRef.current?.endConversation()}>end conversation</button>
        <label>
          <input type="checkbox" checked={blocked} onChange={(e) => setBlocked(e.target.checked)} /> input blocked
        </label>
        <label>
          zoom <input type="number" step={0.25} value={zoom} onChange={(e) => setZoom(Number(e.target.value))} style={{ width: 60 }} />
        </label>
        <label>
          inbox <input type="number" value={inbox} onChange={(e) => setInbox(Number(e.target.value))} style={{ width: 60 }} />
        </label>
        <button
          onClick={() => {
            setSessions((previous) => [...previous, makeSession(nextIndex)]);
            setNextIndex((n) => n + 1);
          }}
        >
          add session
        </button>
        <button onClick={() => setSessions((previous) => previous.slice(1))}>remove first</button>
        {sessions.map((s) => (
          <button key={s.id} onClick={() => cycle(s.id)} data-session={s.id}>
            {robotName(s)} {s.status}
          </button>
        ))}
        <pre id="log" style={{ whiteSpace: "pre-wrap" }}>
          {log.join("\n")}
        </pre>
      </div>
    </div>
  );
}

const root = document.getElementById("root");
if (root) {
  createRoot(root).render(
    <StrictMode>
      <DevHarness />
    </StrictMode>,
  );
}
