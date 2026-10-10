import { HARNESS_NAME, HARNESS_ORDER as ORDER, stillUrl } from "@/lib/sprites";

export default function Ticker() {
  const row = [...ORDER, ...ORDER, ...ORDER];
  return (
    <section className="ticker" aria-label="Works with Claude Code, Codex, Gemini CLI, Copilot CLI, Cursor, Pi and omp">
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
