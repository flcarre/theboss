import SpriteAnim from "./SpriteAnim";
import { stillUrl } from "@/lib/sprites";

const MENU = [
  { status: "wait", title: "Migrate the database to Postgres 17", sub: "Claude Code · checkout-api · waiting" },
  { status: "wait", title: "Rotate the staging TLS certificates", sub: "Claude Code · infra · waiting" },
  { status: "work", title: "Speed up the nightly aggregation job", sub: "Codex · data-pipeline · working" },
  { status: "work", title: "Rebuild the home page", sub: "Cursor · web-dashboard · working" },
  { status: "work", title: "Fix the crash on launch", sub: "Pi · ios-app · working" },
  { status: "done", title: "Add the Windows install section", sub: "omp · docs-site · done" },
];

export default function Moods() {
  return (
    <section className="moods" id="moods">
      <header className="section-head reveal">
        <p className="eyebrow">02 — Read the room</p>
        <h2>
          Three moods.
          <br />
          <em>Zero dashboards.</em>
        </h2>
      </header>

      <div className="moods-floor reveal">
        <figure className="mood">
          <div className="mood-sprite">
            <img className="mood-emote" src="/assets/emotes/dots.png" alt="" />
            <SpriteAnim sheet="robot_codex_typing_south" zoom={2} />
          </div>
          <figcaption>
            <span className="mood-tag tag-work">Working</span>
            <h3>Heads down.</h3>
            <p>It&rsquo;s typing. Leave it be. You can still peek at the transcript without breaking its focus.</p>
          </figcaption>
        </figure>
        <figure className="mood mood-hot">
          <div className="mood-sprite">
            <img className="mood-emote bob" src="/assets/emotes/alert.png" alt="" />
            <SpriteAnim sheet="robot_claude_alert_south" zoom={1.8} fps={7} />
          </div>
          <figcaption>
            <span className="mood-tag tag-wait">Needs you</span>
            <h3>Waving at you.</h3>
            <p>It wants to run something and needs your OK. A notification pops, the Dock badge ticks up, and it keeps waving until you show up.</p>
          </figcaption>
        </figure>
        <figure className="mood">
          <div className="mood-sprite">
            <img className="mood-emote float" src="/assets/emotes/sleep.png" alt="" />
            <img className="mood-still" src={stillUrl("omp")} alt="" />
          </div>
          <figcaption>
            <span className="mood-tag tag-done">Done</span>
            <h3>Clocked out.</h3>
            <p>The work is finished. It dozes at its desk until you resume it or the session ages off the floor.</p>
          </figcaption>
        </figure>
      </div>

      <div className="mac reveal">
        <div className="mac-screen">
          <div className="mac-menubar">
            <span className="mac-apple" aria-hidden="true" />
            <b>Terminal</b>
            <span className="mac-hide">Shell</span>
            <span className="mac-hide">Edit</span>
            <span className="mac-hide">View</span>
            <span className="mac-spacer" />
            <span className="mac-extra">⚠ 2 · ◉ 3</span>
            <span className="mac-time">Fri 23:41</span>
          </div>
          <div className="mac-desk">
            <div className="mac-dropdown">
              <p className="mac-title">THE BOSS</p>
              <ul>
                {MENU.map((m) => (
                  <li key={m.title}>
                    <i className={`dot dot-${m.status}`} />
                    <div>
                      <b>{m.title}</b>
                      <span>{m.sub}</span>
                    </div>
                  </li>
                ))}
              </ul>
              <div className="mac-rule" />
              <div className="mac-usage"><span>Claude Code · 5 hours</span><b className="c-ok">42 %</b></div>
              <div className="mac-usage"><span>Codex · 5 hours</span><b className="c-warn">63 %</b></div>
              <div className="mac-rule" />
              <div className="mac-actions"><span>Open the office</span><span>Quit</span></div>
            </div>
            <div className="mac-toast">
              <img src="/assets/AppIcon.png" alt="" />
              <div>
                <b>Claude Code needs you</b>
                <span>
                  checkout-api wants to run <code>psql -f migrations/017_pg17.sql</code>
                </span>
              </div>
              <small>now</small>
            </div>
            <div className="mac-dock" aria-hidden="true">
              <span className="mac-dock-app" />
              <span className="mac-dock-app" />
              <span className="mac-dock-icon">
                <img src="/assets/AppIcon.png" alt="" />
                <i>2</i>
              </span>
              <span className="mac-dock-app" />
            </div>
          </div>
        </div>
        <p className="mac-caption">
          Menu bar, Dock badge and notifications. Leave the office, keep your ears open.
        </p>
      </div>
    </section>
  );
}
