"use client";

import { useState } from "react";

const COMMANDS = `./scripts/bundle.sh
open build/TheBoss.app`;

export default function Install() {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(COMMANDS);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  };

  return (
    <section className="install" id="install">
      <header className="section-head reveal">
        <p className="eyebrow">06 — Clock in</p>
        <h2>
          Build it, open it,
          <br />
          <em>walk in.</em>
        </h2>
        <p className="lede">A pure Swift package. The Command Line Tools are enough, no Xcode project required.</p>
      </header>

      <div className="install-grid">
        <div className="term reveal">
          <div className="term-bar">
            <i />
            <i />
            <i />
            <span>zsh — theboss</span>
            <button className="term-copy" type="button" onClick={copy}>
              {copied ? "Copied" : "Copy"}
            </button>
          </div>
          <pre className="term-body">
            <span className="t-c"># build a signed .app into build/</span>
            <span><span className="t-p">$</span> ./scripts/bundle.sh</span>
            <span><span className="t-p">$</span> open build/TheBoss.app</span>
            <span>&nbsp;</span>
            <span className="t-c"># or kick the tires with a fake team</span>
            <span><span className="t-p">$</span> python3 scripts/make_demo_home.py build/demo-home</span>
            <span><span className="t-p">$</span> BOSS_HOME=build/demo-home swift run TheBoss</span>
          </pre>
        </div>

        <div className="controls reveal">
          <h3>Controls</h3>
          <dl>
            <dt><span className="key">←↑↓→</span><span className="key">WASD</span></dt>
            <dd>Walk</dd>
            <dt><span className="key">⇧</span></dt>
            <dd>Run</dd>
            <dt><span className="key">Space</span><span className="key">↩</span></dt>
            <dd>Talk</dd>
            <dt><span className="key">Esc</span></dt>
            <dd>Menu</dd>
            <dt><span className="key">⌘1</span><span className="key">⌘5</span></dt>
            <dd>Jump to a screen</dd>
            <dt><span className="key">Click</span></dt>
            <dd>Walk to a robot or a piece of furniture</dd>
          </dl>
        </div>
      </div>
    </section>
  );
}
