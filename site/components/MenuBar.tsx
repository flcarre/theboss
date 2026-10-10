import MenuBarPanel, { RobotGlyph } from "./MenuBarPanel";

const POINTS = [
  { title: "Needs you, first", body: "Every waiting agent with the exact command it wants to run. Click a row to land in that session." },
  { title: "Working and recently done", body: "Who's busy, who just finished, and how long ago each one last moved." },
  { title: "Limits before the wall", body: "Claude and Codex, five-hour and weekly windows, going green, orange, then red." },
  { title: "Mail on the badge", body: "Open suggestions are one click away. Notifications and a Dock badge cover the rest." },
];

export default function MenuBar() {
  return (
    <section className="menubar" id="menubar">
      <div className="menubar-grid">
        <div className="menubar-copy">
          <header className="section-head reveal">
            <p className="eyebrow">03 — Out of the office</p>
            <h2>
              Leave the office.
              <br />
              <em>Keep an ear open.</em>
            </h2>
            <p className="lede">
              The Boss lives in your menu bar too. A tiny pixel robot counts who&rsquo;s working, and raises a
              <b className="menubar-bang"> ! </b>with a number the moment one of them is waiting on you.
            </p>
          </header>
          <ul className="menubar-points">
            {POINTS.map((p, i) => (
              <li key={p.title} className="reveal" style={{ "--i": i } as React.CSSProperties}>
                <b>{p.title}</b>
                <span>{p.body}</span>
              </li>
            ))}
          </ul>
        </div>

        <div className="desk-mac reveal">
          <div className="desk-bar">
            <span className="desk-apple" aria-hidden="true" />
            <b>Terminal</b>
            <span className="desk-hide">Shell</span>
            <span className="desk-hide">Edit</span>
            <span className="desk-spacer" />
            <span className="desk-dot" />
            <span className="desk-dot" />
            <span className="desk-extra">
              <RobotGlyph alert />
              2
            </span>
            <span className="desk-dot" />
            <span className="desk-time">Fri 23:41</span>
          </div>
          <div className="desk-area">
            <div className="desk-toast">
              <img src="/assets/AppIcon.png" alt="" />
              <div>
                <b>CLAUDE-209 needs you</b>
                <span>
                  checkout-api wants to run <code>psql -f migrations/017_pg17.sql</code>
                </span>
              </div>
              <small>now</small>
            </div>
            <MenuBarPanel />
            <div className="desk-dock" aria-hidden="true">
              <span />
              <span />
              <span className="desk-dock-boss">
                <img src="/assets/AppIcon.png" alt="" />
                <i>2</i>
              </span>
              <span />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
