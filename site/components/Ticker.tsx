import { HARNESS_NAME, HARNESS_ORDER as ORDER, stillUrl } from "@/lib/sprites";

const HALF = [...ORDER, ...ORDER, ...ORDER];

export default function Ticker() {
  return (
    <section className="ticker" aria-label="Works with Claude Code, Codex, Gemini CLI, Copilot CLI, Cursor, Pi and omp">
      <div className="ticker-track" aria-hidden="true">
        {[0, 1].map((half) => (
          <div key={half} className="ticker-half">
            {HALF.map((h, i) => (
              <span key={i} className={i % 2 ? "is-alt" : ""}>
                <img src={stillUrl(h)} alt="" />
                {HARNESS_NAME[h]}
              </span>
            ))}
          </div>
        ))}
      </div>
    </section>
  );
}
