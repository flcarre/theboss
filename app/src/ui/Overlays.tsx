import { useEffect, useMemo, useState } from "react";
import type { Snapshot } from "../api";
import type { RoomId } from "../game/types";
import { tr } from "../i18n";
import { AssetIcon, Gauge, KeyCap, PixelGlyph, PixelImage, type ICON } from "./pixel";
import {
  MENU_ENTRIES,
  model,
  needsYou,
  openSuggestions,
  workingSessions,
  finishedSessions,
  type Dialog,
  type MenuEntry,
  type Toast,
} from "./model";
import { COLOR, HARNESS_COLOR, HARNESS_NAME, gaugeColor, isMac } from "./theme";

function shortcutHint(snapshot: Snapshot, macKey: string, otherKey: string): string {
  return tr(isMac(snapshot.platform) ? macKey : otherKey);
}

export function StatusHUD({ snapshot }: { snapshot: Snapshot }) {
  const waiting = needsYou(snapshot).length;
  const working = workingSessions(snapshot).length;
  const done = finishedSessions(snapshot).length;
  const mail = openSuggestions(snapshot).length;
  return (
    <div className="hud status-hud frame-dark">
      <button
        type="button"
        className="hud-counters"
        onClick={() => model.open({ kind: "overview" })}
        title={shortcutHint(snapshot, "Agent board (⌘1)", "Agent board (Ctrl+1)")}
      >
        <Counter value={waiting} label={tr("waiting")} color={COLOR.warning} />
        <Counter value={working} label={tr("working")} color={COLOR.success} />
        <Counter value={done} label={tr("done")} color={COLOR.muted} />
      </button>
      <span className="hud-divider" />
      <button
        type="button"
        className="hud-mail"
        onClick={() => model.open({ kind: "inbox" })}
        title={shortcutHint(snapshot, "Mail: suggestions to review (⌘2)", "Mail: suggestions to review (Ctrl+2)")}
      >
        <AssetIcon name="mail" size={24} />
        <b className={mail === 0 ? "is-empty" : ""}>{mail}</b>
      </button>
    </div>
  );
}

function Counter({ value, label, color }: { value: number; label: string; color: string }) {
  return (
    <span className="hud-counter">
      <i style={{ background: color }} />
      <b>{value}</b>
      <span>{label}</span>
    </span>
  );
}

export function UsageHUD({ snapshot }: { snapshot: Snapshot }) {
  const providers = (snapshot.usage?.providers ?? []).filter((provider) => provider.state.kind === "ok" && provider.windows.length > 0);
  if (providers.length === 0) return null;
  return (
    <button
      type="button"
      className="hud usage-hud frame-dark"
      onClick={() => model.open({ kind: "usage" })}
      title={shortcutHint(snapshot, "Boss computer: usage (⌘3)", "Boss computer: usage (Ctrl+3)")}
    >
      {providers.map((provider) => {
        const window = provider.windows[0];
        return (
          <span key={provider.harness} className="usage-hud-row">
            <i style={{ background: HARNESS_COLOR[provider.harness] }} />
            <b>{HARNESS_NAME[provider.harness]}</b>
            <span>{window.label}</span>
            <Gauge fraction={window.usedPercent / 100} color={gaugeColor(window.usedPercent)} />
            <strong>{Math.round(window.usedPercent)} %</strong>
          </span>
        );
      })}
    </button>
  );
}

export function HintBar({ room, snapshot }: { room: RoomId; snapshot: Snapshot }) {
  return (
    <div className="hint-bar">
      <Hint keyLabel="←↑↓→" label={tr("Walk")} />
      <Hint keyLabel={isMac(snapshot.platform) ? "⇧" : tr("Shift")} label={tr("Run")} />
      <Hint keyLabel={tr("Space")} label={tr("Talk")} />
      <Hint keyLabel="F" label={tr("Whip")} />
      <Hint keyLabel="esc" label={tr("Menu")} />
      <span className="hint-room">{room === "office" ? tr("Your office") : tr("Open space")}</span>
    </div>
  );
}

function Hint({ keyLabel, label }: { keyLabel: string; label: string }) {
  return (
    <span className="hint">
      <KeyCap label={keyLabel} />
      <span>{label}</span>
    </span>
  );
}

export function ToastView({ toast }: { toast: Toast }) {
  return (
    <div className="toast-layer" aria-live="polite">
      <div key={toast.id} className="toast frame-dark">
        <PixelGlyph name="bell" size={20} />
        <span>{toast.text}</span>
      </div>
    </div>
  );
}

const TYPE_INTERVAL = 16;
const TYPE_STEP = 2;

export function DialogBox({ dialog, page, choice }: { dialog: Dialog; page: number; choice: number }) {
  const text = dialog.pages[Math.min(page, dialog.pages.length - 1)] ?? "";
  const characters = useMemo(() => Array.from(text), [text]);
  const [visible, setVisible] = useState(0);
  const complete = visible >= characters.length;
  const isLastPage = page >= dialog.pages.length - 1;
  const showsChoices = isLastPage && dialog.choices.length > 0 && complete;

  useEffect(() => {
    setVisible(0);
  }, [dialog.id, page]);

  useEffect(() => {
    if (complete) return;
    const timer = window.setInterval(() => setVisible((count) => Math.min(characters.length, count + TYPE_STEP)), TYPE_INTERVAL);
    return () => window.clearInterval(timer);
  }, [complete, characters.length]);

  useEffect(() => {
    model.setDialogReveal({ complete, reveal: () => setVisible(characters.length) });
  }, [complete, characters.length]);

  useEffect(() => () => model.setDialogReveal(null), []);

  const tap = () => {
    if (showsChoices) return;
    if (!complete) setVisible(characters.length);
    else model.advanceDialog();
  };

  return (
    <div className="dialog-layer">
      <div className={`dialog frame-cream ${dialog.speaker ? "has-speaker" : ""}`} role="dialog" aria-label={dialog.speaker ?? undefined} onClick={tap}>
        {dialog.speaker && <span className="dialog-speaker">{dialog.speaker}</span>}
        {dialog.portrait && (
          <span className="dialog-portrait">
            <PixelImage src={dialog.portrait} size={92} />
          </span>
        )}
        <div className="dialog-main">
          <p className="dialog-text">{characters.slice(0, visible).join("")}</p>
          <div className="dialog-footer">
            {dialog.pages.length > 1 && (
              <span className="dialog-page">
                {page + 1}/{dialog.pages.length}
              </span>
            )}
            {complete && !showsChoices && <span className="dialog-caret">▼</span>}
          </div>
        </div>
        {showsChoices && (
          <>
            <span className="dialog-divider" />
            <ul className="dialog-choices" onClick={(event) => event.stopPropagation()}>
              {dialog.choices.map((item, index) => (
                <li
                  key={item.title}
                  className={index === choice ? "is-selected" : ""}
                  onMouseEnter={() => model.setDialogChoice(index)}
                  onClick={() => model.chooseDialog(index)}
                >
                  <span className="dialog-arrow">▶</span>
                  <span>{item.title}</span>
                </li>
              ))}
            </ul>
          </>
        )}
      </div>
    </div>
  );
}

const MENU_ICON: Record<Exclude<MenuEntry, "close">, keyof typeof ICON> = {
  agents: "agents",
  inbox: "mail",
  usage: "usage",
  rules: "rules",
  stats: "stats",
  domain: "domain",
  settings: "settings",
};

function menuTitle(entry: MenuEntry): string {
  switch (entry) {
    case "agents":
      return tr("Agents");
    case "inbox":
      return tr("Mail");
    case "usage":
      return tr("Usage");
    case "rules":
      return tr("Rules");
    case "stats":
      return tr("Stats");
    case "domain":
      return tr("Domain");
    case "settings":
      return tr("Settings");
    case "close":
      return tr("Back");
  }
}

function menuSubtitle(entry: MenuEntry): string {
  switch (entry) {
    case "agents":
      return tr("All your robots and their status");
    case "inbox":
      return tr("Suggestions to review");
    case "usage":
      return tr("Plan limits, tokens");
    case "rules":
      return tr("Rules, skills, hooks");
    case "stats":
      return tr("Corrections and trend");
    case "domain":
      return tr("Domain model per project");
    case "settings":
      return tr("Language, sound, zoom");
    case "close":
      return tr("Close the menu");
  }
}

export function StartMenu({ snapshot, index }: { snapshot: Snapshot; index: number }) {
  const waiting = needsYou(snapshot).length;
  const mail = openSuggestions(snapshot).length;
  return (
    <div className="menu-layer">
      <ul className="start-menu frame-cream" role="menu">
        {MENU_ENTRIES.map((entry, position) => {
          const selected = position === index;
          return (
            <li
              key={entry}
              role="menuitem"
              className={selected ? "is-selected" : ""}
              onMouseEnter={() => model.setMenuIndex(position)}
              onClick={() => model.select(entry)}
            >
              {entry === "close" ? <PixelGlyph name="back" size={28} /> : <AssetIcon name={MENU_ICON[entry]} size={28} />}
              <span className="menu-text">
                <b>{menuTitle(entry)}</b>
                {selected && <small>{menuSubtitle(entry)}</small>}
              </span>
              {entry === "agents" && waiting > 0 && <span className="menu-badge tone-warning">{waiting}</span>}
              {entry === "inbox" && mail > 0 && <span className="menu-badge tone-pink">{mail}</span>}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
