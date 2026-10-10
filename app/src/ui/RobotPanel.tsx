import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { AgentSession, Harness, Platform, Snapshot, TranscriptMessage } from "../api";
import { backend } from "../backend";
import { robotName, robotPortrait } from "../game/robotName";
import { formatTokens, relative, tr } from "../i18n";
import { model } from "./model";
import { EmptyState, PixelButton, PixelImage, SectionTitle, StatusDot } from "./pixel";
import { openInSystem, shellQuote } from "./system";
import { HARNESS_COLOR, HARNESS_NAME, statusLabel, totalTokens, withAlpha } from "./theme";

const MESSAGE_LIMIT = 3000;

function resumeArguments(harness: Harness, sessionId: string): string {
  switch (harness) {
    case "claude":
      return `claude --resume ${sessionId}`;
    case "codex":
      return `codex resume ${sessionId}`;
    case "gemini":
      return `gemini --resume ${sessionId}`;
    case "copilot":
      return `copilot --resume ${sessionId}`;
    case "pi":
      return "pi --continue";
    case "omp":
      return "omp --continue";
    case "cursor":
      return `cursor-agent resume ${sessionId}`;
  }
}

export function resumeCommand(session: AgentSession, platform: Platform): string {
  const command = resumeArguments(session.harness, session.sessionId);
  if (!session.cwd) return command;
  if (platform === "windows") return `cd "${session.cwd}"; ${command}`;
  return `cd ${shellQuote(session.cwd)} && ${command}`;
}

export function RobotPanel({ snapshot, sessionId }: { snapshot: Snapshot; sessionId: string }) {
  const session = snapshot.sessions.find((item) => item.id === sessionId);
  const [messages, setMessages] = useState<TranscriptMessage[] | null>(null);

  useEffect(() => {
    let alive = true;
    backend
      .messages(sessionId)
      .then((result) => alive && setMessages(result))
      .catch(() => alive && setMessages([]));
    return () => {
      alive = false;
    };
  }, [sessionId]);

  if (!session) return <EmptyState text={tr("This robot has left.")} />;

  return (
    <div className="robot-panel">
      <aside className="robot-side">
        <span className="robot-portrait" style={{ background: withAlpha(HARNESS_COLOR[session.harness], 0.14) }}>
          <PixelImage src={robotPortrait(session.harness)} size={120} />
        </span>
        <span className="robot-status">
          <StatusDot status={session.status} />
          <b>{statusLabel(session.status)}</b>
        </span>
        <h3 className="robot-title">{session.title}</h3>
        <dl className="info-card card flat">
          <Info label={tr("Harness")} value={HARNESS_NAME[session.harness]} />
          <Info label={tr("Project")} value={session.projectName} />
          <Info label={tr("Model")} value={session.model ?? "—"} />
          <Info label={tr("Started")} value={relative(session.startedAt)} />
          <Info label={tr("Last activity")} value={relative(session.updatedAt)} />
          <Info label={tr("Prompts")} value={String(session.promptCount)} />
          <Info label={tr("Tokens")} value={formatTokens(totalTokens(session.tokens))} />
        </dl>
        {session.pendingAction && (
          <div className="pending-box">
            <b>{tr("Waiting to run")}</b>
            <code>{session.pendingAction}</code>
          </div>
        )}
        <div className="robot-actions">
          <PixelButton title={tr("Go to session")} onClick={() => void model.focus(session)} />
          <div className="button-row">
            {session.cwd && <PixelButton title={tr("Open folder")} tone="card" onClick={() => void openInSystem(session.cwd)} />}
            <PixelButton title={tr("Copy resume")} tone="card" onClick={() => void model.copyCommand(resumeCommand(session, snapshot.platform))} />
          </div>
        </div>
      </aside>
      <div className="robot-log">
        <SectionTitle text={tr("Conversation logbook")} />
        {messages === null ? null : messages.length === 0 ? (
          <EmptyState text={session.harness === "cursor" ? tr("Cursor does not let other apps read its conversations.") : tr("No message yet.")} />
        ) : (
          <MessageList messages={messages} robot={robotName(session)} />
        )}
      </div>
    </div>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="info-row">
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

function MessageList({ messages, robot }: { messages: TranscriptMessage[]; robot: string }) {
  const scroller = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const element = scroller.current;
    if (element) element.scrollTop = element.scrollHeight;
  }, [messages]);
  return (
    <div className="scroll-area message-list" ref={scroller}>
      {messages.map((message, index) => {
        const isUser = message.role === "user";
        const text = message.text.length > MESSAGE_LIMIT ? `${message.text.slice(0, MESSAGE_LIMIT)}…` : message.text;
        return (
          <div key={index} className={`message ${isUser ? "from-user" : "from-robot"}`}>
            <div className="message-bubble card">
              <b>{isUser ? tr("You") : robot}</b>
              <p>{text}</p>
            </div>
          </div>
        );
      })}
    </div>
  );
}
