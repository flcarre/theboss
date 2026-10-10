import { HARNESS_COLOR, HARNESS_NAME, type Harness } from "@/lib/sprites";

const thumb = (who: Harness | "boss") => `/assets/thumbs/${who === "boss" ? "boss" : `robot_${who}`}.png`;

type Status = "wait" | "work" | "done";
type Row = { harness: Harness; title: string; project: string; ago: string; pending?: string };
type Window = { harness: Harness; label: string; used: number };

const SECTIONS: { status: Status; title: string; rows: Row[] }[] = [
  {
    status: "wait",
    title: "Needs you",
    rows: [
      { harness: "claude", title: "Migrate the database to Postgres 17", project: "checkout-api", ago: "12 sec. ago", pending: "psql -f migrations/017_pg17.sql" },
      { harness: "claude", title: "Rotate the staging TLS certificates", project: "infra", ago: "2 min. ago", pending: "terraform apply -target=module.tls" },
    ],
  },
  {
    status: "work",
    title: "Working",
    rows: [
      { harness: "codex", title: "Speed up the nightly aggregation job", project: "data-pipeline", ago: "3 sec. ago" },
      { harness: "gemini", title: "Tune the ranking weights", project: "search-service", ago: "8 sec. ago" },
      { harness: "cursor", title: "Rebuild the home page", project: "web-dashboard", ago: "21 sec. ago" },
      { harness: "claude", title: "Fix the crash on launch", project: "ios-app", ago: "1 min. ago" },
    ],
  },
  {
    status: "done",
    title: "Recently done",
    rows: [
      { harness: "copilot", title: "Add a --json flag to the CLI", project: "cli-tools", ago: "6 min. ago" },
      { harness: "codex", title: "Write the Windows install guide", project: "docs-site", ago: "18 min. ago" },
    ],
  },
];

const WINDOWS: Window[] = [
  { harness: "claude", label: "5 h", used: 42 },
  { harness: "claude", label: "Week", used: 78 },
  { harness: "codex", label: "5 h", used: 93 },
  { harness: "codex", label: "Week", used: 31 },
];

const HEAD = [".....####.....", ".....####.....", "......##......", ".############.", "##############", "##..######..##", "##..######..##", "##############", "###........###", "##############", ".############."];
const BANG = ["##", "##", "##", "##", "##", "##", "..", "##", "##"];

function gaugeClass(used: number) {
  return used >= 90 ? "g-bad" : used >= 70 ? "g-warn" : "g-ok";
}

export function RobotGlyph({ alert }: { alert: boolean }) {
  const cells: [number, number][] = [];
  HEAD.forEach((row, y) => [...row].forEach((c, x) => c === "#" && cells.push([x, y + 3])));
  if (alert) BANG.forEach((row, y) => [...row].forEach((c, x) => c === "#" && cells.push([x + 16, y + 4])));
  return (
    <svg className="mb-glyph" viewBox={`0 0 ${alert ? 19 : 14} 16`} aria-hidden="true" shapeRendering="crispEdges">
      {cells.map(([x, y]) => (
        <rect key={`${x}-${y}`} x={x} y={y} width="1" height="1" />
      ))}
    </svg>
  );
}

export default function MenuBarPanel() {
  return (
    <div className="mb-panel" role="img" aria-label="The Boss menu bar panel: two agents need you, four are working, two recently finished, with plan limits">
      <div className="mb-head">
        <span className="mb-avatar">
          <img src={thumb("boss")} alt="" />
        </span>
        <div>
          <b>The Boss</b>
          <span>2 waiting · 4 working · 2 done</span>
        </div>
        <span className="mb-mail">
          <img src="/assets/icons/mail.png" alt="" />3
        </span>
      </div>
      <div className="mb-body">
        {SECTIONS.map((section) => (
          <div key={section.status} className={`mb-section s-${section.status}`}>
            <p className="mb-section-title">
              <i />
              {section.title}
            </p>
            {section.rows.map((row) => (
              <div key={row.title} className="mb-row">
                <span className="mb-thumb" style={{ "--c": HARNESS_COLOR[row.harness] } as React.CSSProperties}>
                  <img src={thumb(row.harness)} alt="" />
                </span>
                <span className="mb-text">
                  <b>{row.title}</b>
                  <span>
                    {HARNESS_NAME[row.harness]} · {row.project}
                  </span>
                  {row.pending && <code>{row.pending}</code>}
                </span>
                <small>{row.ago}</small>
              </div>
            ))}
          </div>
        ))}
      </div>
      <div className="mb-usage">
        {WINDOWS.map((w) => (
          <div key={`${w.harness}-${w.label}`} className={`mb-limit ${gaugeClass(w.used)}`}>
            <i style={{ background: HARNESS_COLOR[w.harness] }} />
            <b>{HARNESS_NAME[w.harness]}</b>
            <span>{w.label}</span>
            <span className="mb-gauge">
              {Array.from({ length: 20 }, (_, i) => (
                <em key={i} className={i < Math.round((w.used / 100) * 20) ? "on" : ""} />
              ))}
            </span>
            <strong>{w.used} %</strong>
          </div>
        ))}
      </div>
      <div className="mb-foot">
        <span className="mb-open">Open the office</span>
        <span className="mb-quit">Quit</span>
      </div>
    </div>
  );
}
