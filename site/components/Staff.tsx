import SpriteAnim from "./SpriteAnim";
import { HARNESS_COLOR, HARNESS_NAME, type Harness, type SheetName } from "@/lib/sprites";

type Card = { harness: Harness; flavor: string; reads: string; extra: [string, string]; zoom: number };

const CARDS: Card[] = [
  { harness: "claude", flavor: "Orange, tireless, and polite enough to ask before it runs anything risky.", reads: "~/.claude", extra: ["Limits", "5-hour & weekly, live"], zoom: 1.5 },
  { harness: "codex", flavor: "White and teal. Quiet. Keeps its own rate limits in its logs, so we simply read them.", reads: "~/.codex", extra: ["Limits", "From session logs"], zoom: 1.7 },
  { harness: "gemini", flavor: "White and blue, slim, fast on its feet. Keeps its chats in tidy JSONL files.", reads: "~/.gemini", extra: ["Rules", "GEMINI.md"], zoom: 1.7 },
  { harness: "copilot", flavor: "Grey and violet, with a propeller hat. Lives in your terminal now, not just your editor.", reads: "~/.copilot", extra: ["Rules", ".github instructions"], zoom: 1.55 },
  { harness: "cursor", flavor: "Matte black. Lives in your editor all day, still clocks in on the floor.", reads: "~/.cursor", extra: ["Limits", "Usage summary"], zoom: 1.55 },
];

export default function Staff() {
  return (
    <section className="staff" id="staff">
      <header className="section-head reveal">
        <p className="eyebrow">04 — The staff</p>
        <h2>
          Five harnesses.
          <br />
          <em>One payroll.</em>
        </h2>
        <p className="lede">
          The Boss reads each agent&rsquo;s own session files on disk. No plugin to install, no wrapper around your
          terminal. If it ran on this Mac in the last twelve hours, it has a desk.
        </p>
      </header>

      <div className="cards">
        {CARDS.map((c, i) => (
          <article key={c.harness} className="card reveal" style={{ "--c": HARNESS_COLOR[c.harness], "--i": i } as React.CSSProperties}>
            <span className="card-no">No. {String(i + 1).padStart(3, "0")}</span>
            <div className="card-art">
              <SpriteAnim
                sheet={`robot_${c.harness}_typing_south` as SheetName}
                alt={`robot_${c.harness}_alert_south` as SheetName}
                zoom={c.zoom}
                label={`${HARNESS_NAME[c.harness]} robot`}
              />
            </div>
            <h3>{HARNESS_NAME[c.harness]}</h3>
            <p className="card-flavor">{c.flavor}</p>
            <dl>
              <dt>Reads</dt>
              <dd><code>{c.reads}</code></dd>
              <dt>{c.extra[0]}</dt>
              <dd>{c.extra[1]}</dd>
            </dl>
          </article>
        ))}
      </div>
    </section>
  );
}
