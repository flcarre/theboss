import type { Snapshot } from "../api";
import { robotName } from "../game/robotName";
import { tr } from "../i18n";
import { AnalyticsPanel } from "./AnalyticsPanel";
import { DomainPanel } from "./DomainPanel";
import { InboxPanel } from "./InboxPanel";
import { LibraryPanel } from "./LibraryPanel";
import { model, type Panel } from "./model";
import { OverviewPanel } from "./OverviewPanel";
import { AssetIcon, KeyCap, PixelGlyph, type ICON } from "./pixel";
import { RobotPanel } from "./RobotPanel";
import { SettingsPanel } from "./SettingsPanel";
import { HARNESS_NAME } from "./theme";
import { UsagePanel } from "./UsagePanel";

function panelTitle(panel: Panel, snapshot: Snapshot): string {
  switch (panel.kind) {
    case "overview":
      return tr("Agent board");
    case "usage":
      return tr("Boss computer");
    case "library":
      return tr("Rules library");
    case "inbox":
      return tr("Mail");
    case "analytics":
      return tr("Whiteboard");
    case "settings":
      return tr("Settings");
    case "domain":
      return tr("Archives");
    case "robot": {
      const session = snapshot.sessions.find((item) => item.id === panel.sessionId);
      return session ? robotName(session) : tr("Logbook");
    }
  }
}

function panelSubtitle(panel: Panel, snapshot: Snapshot): string {
  switch (panel.kind) {
    case "overview":
      return tr("Every agent session from the last 12 hours");
    case "usage":
      return tr("Plan limits and token consumption");
    case "library":
      return tr("The hidden files that drive your agents");
    case "inbox":
      return tr("Suggested changes, with evidence and the exact diff");
    case "analytics":
      return tr("Is your setup getting better?");
    case "settings":
      return tr("Game, language and privacy");
    case "domain":
      return tr("Local domain model, one per project");
    case "robot": {
      const session = snapshot.sessions.find((item) => item.id === panel.sessionId);
      return session ? `${HARNESS_NAME[session.harness]} · ${session.projectName}` : "";
    }
  }
}

const PANEL_ICON: Record<Panel["kind"], keyof typeof ICON> = {
  overview: "agents",
  usage: "usage",
  library: "rules",
  inbox: "mail",
  analytics: "stats",
  settings: "settings",
  domain: "domain",
  robot: "logbook",
};

function PanelContent({ panel, snapshot }: { panel: Panel; snapshot: Snapshot }) {
  switch (panel.kind) {
    case "overview":
      return <OverviewPanel snapshot={snapshot} />;
    case "usage":
      return <UsagePanel snapshot={snapshot} />;
    case "library":
      return <LibraryPanel snapshot={snapshot} />;
    case "inbox":
      return <InboxPanel snapshot={snapshot} />;
    case "analytics":
      return <AnalyticsPanel snapshot={snapshot} />;
    case "settings":
      return <SettingsPanel snapshot={snapshot} />;
    case "domain":
      return <DomainPanel snapshot={snapshot} />;
    case "robot":
      return <RobotPanel key={panel.sessionId} snapshot={snapshot} sessionId={panel.sessionId} />;
  }
}

export function PanelHost({ panel, snapshot }: { panel: Panel; snapshot: Snapshot }) {
  return (
    <div className="panel-layer">
      <div className="panel-backdrop" onClick={() => model.closePanel()} />
      <section className="panel frame-panel" role="dialog" aria-label={panelTitle(panel, snapshot)}>
        <header className="panel-header">
          <AssetIcon name={PANEL_ICON[panel.kind]} size={34} />
          <div className="panel-heading">
            <h2>{panelTitle(panel, snapshot)}</h2>
            <p>{panelSubtitle(panel, snapshot)}</p>
          </div>
          <button type="button" className="panel-close" onClick={() => model.closePanel()} title={tr("Close")}>
            <KeyCap label="esc" />
            <PixelGlyph name="close" size={26} />
          </button>
        </header>
        <div className={`panel-body panel-${panel.kind}`}>
          <PanelContent panel={panel} snapshot={snapshot} />
        </div>
      </section>
    </div>
  );
}
