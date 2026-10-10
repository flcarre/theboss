"use client";

import { useState } from "react";

const QUOTES = [
  { text: <>no, write a failing test that reproduces the bug <mark>before</mark> you fix it</>, who: "Claude Code", color: "#D9773F", where: "ios-app · Tuesday" },
  { text: <>I told you: test first, <mark>then</mark> the fix.</>, who: "Codex", color: "#3FBFA8", where: "checkout-api · Thursday" },
  { text: <>stop. where&rsquo;s the <mark>regression test?</mark></>, who: "Claude Code", color: "#D9773F", where: "ios-app · today" },
];

const TREND = [16.4, 17.1, 15.8, 16.9, 15.2, 14.6, 15.1, 13.9, 14.2, 13.1, 12.4, 12.9, 11.8, 11.2, 11.6, 10.7, 10.1, 10.6, 9.8, 9.9, 9.6];

function steppedPath(values: number[], w: number, h: number) {
  const max = 20;
  const min = 6;
  const step = w / values.length;
  const y = (v: number) => Math.round(h - ((v - min) / (max - min)) * h);
  let d = `M0 ${y(values[0])}`;
  values.forEach((v, i) => {
    d += ` H${Math.round(i * step)} V${y(v)}`;
  });
  d += ` H${w}`;
  return d;
}

type Status = "open" | "applied" | "later" | "ignored";

export default function Rules() {
  const [status, setStatus] = useState<Status>("open");
  const line = steppedPath(TREND, 420, 130);
  const area = `${line} V140 H0 Z`;

  return (
    <section className="rules" id="rules">
      <div className="rules-inner">
        <header className="section-head reveal">
          <p className="eyebrow">05 — Learned rules</p>
          <h2>
            You&rsquo;ve said this
            <br />
            <em>before.</em>
          </h2>
          <p className="lede">
            Every &ldquo;no, I told you&hellip;&rdquo; is a rule your setup doesn&rsquo;t know yet. The Boss spots the
            pattern across sessions and harnesses, drafts the rule, and shows you exactly where it would go.
          </p>
        </header>

        <div className="rules-grid">
          <div className="quotes">
            {QUOTES.map((q, i) => (
              <figure key={i} className="quote reveal" style={{ "--i": i } as React.CSSProperties}>
                <blockquote>{q.text}</blockquote>
                <figcaption>
                  <i className="dot" style={{ background: q.color }} />
                  {q.who} · {q.where}
                </figcaption>
              </figure>
            ))}
          </div>

          <article className={`letter reveal is-${status}`}>
            <div className="letter-stamp" aria-hidden="true">
              {status === "applied" ? "Applied" : status === "later" ? "Later" : status === "ignored" ? "Tossed" : ""}
            </div>
            <p className="letter-kind">Learned rule · 3 pieces of evidence</p>
            <h3>Reproduce bugs with a failing test first</h3>
            <p className="letter-file">
              <code>ios-app/CLAUDE.md</code>
            </p>
            <pre className="diff">
              <span className="d-hunk">@@ -12,3 +12,5 @@ ## Workflow</span>
              <span className="d-ctx">  - Keep pull requests small and focused.</span>
              <span className="d-ctx">  - Run the linter before committing.</span>
              <span className="d-add">+ - Before fixing a bug, write a test that</span>
              <span className="d-add">+   reproduces it and watch it fail. Then fix.</span>
            </pre>
            <div className="letter-actions">
              {status === "open" ? (
                <>
                  <button className="btn btn-gold btn-sm" type="button" onClick={() => setStatus("applied")}>Apply</button>
                  <button className="btn btn-ghost btn-sm" type="button" onClick={() => setStatus("later")}>Later</button>
                  <button className="btn btn-ghost btn-sm" type="button" onClick={() => setStatus("ignored")}>Ignore</button>
                </>
              ) : (
                <button className="btn btn-ghost btn-sm" type="button" onClick={() => setStatus("open")}>Undo</button>
              )}
            </div>
            <p className="letter-note" aria-live="polite">
              {status === "applied" && <>Written to CLAUDE.md. The robot at ios-app looks relieved.</>}
              {status === "later" && <>Back in the in-tray. It&rsquo;ll wait.</>}
              {status === "ignored" && <>Tossed. It won&rsquo;t come back unless you keep saying it.</>}
              {status === "open" && <>Optional: let Claude Code rephrase the rule locally before you apply it.</>}
            </p>
            {status === "applied" && <img className="letter-heart" src="/assets/emotes/heart.png" alt="" />}
          </article>
        </div>

        <div className="trend reveal">
          <div className="trend-copy">
            <p className="trend-num">−35%</p>
            <p>
              corrections per hundred prompts over three weeks, straight from the whiteboard. Your agents didn&rsquo;t get
              smarter. Your setup did.
            </p>
          </div>
          <svg className="trend-chart" viewBox="0 0 420 140" preserveAspectRatio="none" aria-hidden="true">
            <path className="trend-area" d={area} />
            <path className="trend-line" d={line} pathLength={1} />
          </svg>
        </div>
      </div>
    </section>
  );
}
