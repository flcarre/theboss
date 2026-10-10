import OfficeStage from "./OfficeStage";

export default function Hero() {
  return (
    <section className="hero">
      <div className="hero-copy">
        <p className="kicker reveal">
          <span className="kicker-dot" />
          A desktop app for people who manage coding agents
        </p>
        <h1 className="hero-title reveal">
          <span className="line">You&rsquo;re the</span>
          <span className="line">
            <em>boss</em>
            <img className="hero-face" src="/assets/fox_portrait.png" alt="" width={96} height={96} /> now.
          </span>
        </h1>
        <div className="hero-side reveal">
          <p>
            Every Claude Code, Codex, Gemini, Copilot and Cursor session becomes a little robot at a desk. Walk
            the floor to see who&rsquo;s typing, who&rsquo;s waving for your OK, and who already clocked out. Then crack
            the whip.
          </p>
          <div className="hero-ctas">
            <a className="btn btn-gold" href="#download">Get The Boss</a>
            <a className="link-arrow" href="#tour">
              Take the tour <span aria-hidden="true">→</span>
            </a>
          </div>
          <ul className="hero-facts">
            <li>macOS · Windows · Linux</li>
            <li>Runs 100% local</li>
            <li>Free download</li>
          </ul>
        </div>
      </div>
      <OfficeStage />
    </section>
  );
}
