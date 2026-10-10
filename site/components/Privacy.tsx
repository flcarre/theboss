const PATHS = ["~/.claude", "~/.codex", "~/.gemini", "~/.copilot", "~/.cursor", "~/.pi", "~/.omp"];

export default function Privacy() {
  return (
    <section className="local" id="local">
      <div className="local-grid">
        <div className="local-door reveal" aria-hidden="true">
          <span className="local-glow" />
          <img src="/assets/door.png" alt="" />
          <span className="local-plaque">BOSS</span>
        </div>
        <div className="reveal">
          <p className="eyebrow">06 — Privacy</p>
          <h2>
            Nothing leaves
            <br />
            <em>the building.</em>
          </h2>
          <p className="lede">
            The Boss reads what your agents already wrote to disk and keeps its own notes in a single SQLite file on your
            Mac. No account. No telemetry. No cloud.
          </p>
          <ul className="keyring">
            {PATHS.map((p) => (
              <li key={p}>
                <code>{p}</code>
              </li>
            ))}
            <li className="keyring-own">
              <code>~/Library/Application Support/TheBoss/boss.sqlite</code>
            </li>
          </ul>
          <p className="fineprint">
            The one call out: Claude plan limits come from Anthropic&rsquo;s API, using the token Claude Code already keeps
            in your Keychain. Rephrasing a rule with Claude is optional and goes through your local Claude Code.
          </p>
        </div>
      </div>
    </section>
  );
}
