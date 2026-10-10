import { useState, type CSSProperties } from "react";
import type { AgentSession, AgentStatus, Snapshot } from "../api";
import { robotPortrait } from "../game/robotName";
import { formatTokens, relative, tr, trf } from "../i18n";
import { finishedSessions, model, needsYou, workingSessions } from "./model";
import { EmptyState, FitText, HarnessTag, PixelImage, SegmentedTabs, StatusDot } from "./pixel";
import { COLOR, HARNESS_COLOR, STATUS_COLOR, statusLabel, totalTokens, withAlpha } from "./theme";

type Filter = AgentStatus | "all";

export function OverviewPanel({ snapshot }: { snapshot: Snapshot }) {
  const [filter, setFilter] = useState<Filter>("all");
  const sessions = snapshot.sessions;
  const filtered = filter === "all" ? sessions : sessions.filter((session) => session.status === filter);
  return (
    <div className="overview">
      <div className="overview-bar">
        <div className="overview-tabs">
          <SegmentedTabs
            items={[
              { id: "all", title: tr("All"), count: sessions.length, color: COLOR.base },
              { id: "needsApproval", title: tr("Waiting"), count: needsYou(snapshot).length, color: COLOR.warning },
              { id: "working", title: tr("Working"), count: workingSessions(snapshot).length, color: COLOR.success },
              { id: "finished", title: tr("Done"), count: finishedSessions(snapshot).length, color: COLOR.muted },
            ]}
            selection={filter}
            onSelect={(id) => setFilter(id as Filter)}
          />
        </div>
        <span className="muted-note">{tr("Refreshed every 2 s")}</span>
      </div>
      {filtered.length === 0 ? (
        <EmptyState
          text={
            sessions.length === 0
              ? tr("No agent detected yet. Start Claude Code, Codex, Cursor or Pi and your first robot will show up.")
              : tr("Nothing in this category.")
          }
        />
      ) : (
        <div className="scroll-area">
          <div className="agent-grid">
            {filtered.map((session) => (
              <AgentTile key={session.id} session={session} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function AgentTile({ session }: { session: AgentSession }) {
  const waiting = session.status === "needsApproval";
  const tokens = totalTokens(session.tokens);
  return (
    <button
      type="button"
      className={`agent-tile card ${waiting ? "is-waiting" : ""}`}
      style={{ "--status-color": STATUS_COLOR[session.status] } as CSSProperties}
      onClick={() => model.open({ kind: "robot", sessionId: session.id })}
    >
      <span className="agent-portrait" style={{ background: withAlpha(HARNESS_COLOR[session.harness], 0.16) }}>
        <PixelImage src={robotPortrait(session.harness)} size={60} />
      </span>
      <span className="agent-info">
        <span className="agent-status">
          <StatusDot status={session.status} />
          <b>{statusLabel(session.status)}</b>
          <small>{relative(session.updatedAt)}</small>
        </span>
        <span className="agent-title">{session.title}</span>
        <span className="agent-meta">
          <HarnessTag harness={session.harness} />
          <span className="agent-project">{session.projectName}</span>
          {tokens > 0 && <FitText className="agent-tokens" long={trf("%@ tokens", formatTokens(tokens))} short={formatTokens(tokens)} />}
        </span>
        {waiting && session.pendingAction && <code className="agent-pending">{session.pendingAction}</code>}
      </span>
    </button>
  );
}
