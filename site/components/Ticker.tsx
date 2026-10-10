import { HARNESS_NAME, type Harness, stillUrl } from "@/lib/sprites";

const ORDER: Harness[] = ["claude", "codex", "cursor", "pi", "omp"];

export default function Ticker() {
  const row = [...ORDER, ...ORDER, ...ORDER, ...ORDER];
  return (
    <section className="ticker" aria-label="Works with Claude Code, Codex, Cursor, Pi and omp">
      <div className="ticker-track" aria-hidden="true">
        {row.map((h, i) => (
          <span key={i}>
            <img src={stillUrl(h)} alt="" />
            {HARNESS_NAME[h]}
          </span>
        ))}
      </div>
    </section>
  );
}
