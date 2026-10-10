"use client";

import { useEffect, useRef, useState } from "react";

type Step = { shot: string; label: string; title: string; key?: string; prop: string; propClass?: string; body: React.ReactNode };

const STEPS: Step[] = [
  {
    shot: "open-space",
    label: "Open space",
    title: "The open space",
    prop: "/assets/characters/robot_claude/rotations/south.png",
    body: (
      <>One robot per live session, at its own desk. Typing means working. Waving with a <b>!</b> means it&rsquo;s waiting for your approval. Snoozing means it&rsquo;s done.</>
    ),
  },
  {
    shot: "dialog",
    label: "Talking to a robot",
    title: "Talk to a robot",
    prop: "/assets/boss_portrait.png",
    body: (
      <>Walk up and press Space. You get the task, your last order, the action it&rsquo;s stuck on and the whole conversation. Jump back into the session, open its folder, or copy the resume command.</>
    ),
  },
  {
    shot: "overview",
    label: "Wall screen",
    title: "The wall screen",
    key: "⌘1",
    prop: "/assets/objects/wall_screen.png",
    propClass: "is-wide",
    body: <>Every agent from the last twelve hours, on one wall. Filter by working, waiting or done, and walk straight to the one that matters.</>,
  },
  {
    shot: "usage",
    label: "Your computer",
    title: "Your computer",
    key: "⌘3",
    prop: "/assets/objects/desk_boss.png",
    body: <>Plan limits for Claude, Codex and Cursor with their reset times, and the tokens you burned each day. No more guessing whether the weekly cap is about to hit.</>,
  },
  {
    shot: "library",
    label: "Bookshelf",
    title: "The bookshelf",
    key: "⌘4",
    prop: "/assets/objects/bookshelf.png",
    body: <>Every hidden file steering your agents: CLAUDE.md, AGENTS.md, Cursor rules, skills, hooks, subagents, commands and settings. One shelf, per project.</>,
  },
  {
    shot: "inbox",
    label: "In-tray",
    title: "The in-tray",
    key: "⌘2",
    prop: "/assets/objects/intray.png",
    body: <>Suggestions with receipts: rules learned from your corrections and broken settings to fix, each with the evidence and the exact diff. Apply, keep for later, or toss.</>,
  },
  {
    shot: "analytics",
    label: "Whiteboard",
    title: "The whiteboard",
    key: "⌘5",
    prop: "/assets/objects/whiteboard.png",
    body: <>Corrections per hundred prompts, day after day. A falling line means your setup finally understands you. A rising one means you&rsquo;re repeating yourself.</>,
  },
  {
    shot: "domain",
    label: "Archive cabinet",
    title: "The archive cabinet",
    prop: "/assets/objects/archive_cabinet.png",
    body: (
      <>A local domain model, one source of truth per project: intent, written conventions, learned decisions, recent work, and where CLAUDE.md and AGENTS.md disagree. Export it to <code>.boss/domain.md</code> with a diff.</>
    ),
  },
];

export default function Tour() {
  const [active, setActive] = useState(0);
  const refs = useRef<(HTMLLIElement | null)[]>([]);

  useEffect(() => {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) setActive(Number((e.target as HTMLElement).dataset.index));
        });
      },
      { rootMargin: "-45% 0px -45% 0px" },
    );
    refs.current.forEach((el) => el && io.observe(el));
    return () => io.disconnect();
  }, []);

  return (
    <section className="tour" id="tour">
      <header className="section-head reveal">
        <p className="eyebrow">01 — The floor</p>
        <h2>
          Every piece of furniture
          <br />
          <em>is a feature.</em>
        </h2>
        <p className="lede">
          No dashboard with forty tabs. You walk up to things. The wall screen knows who&rsquo;s on shift, your computer
          knows your plan limits, the in-tray knows what you keep repeating.
        </p>
      </header>

      <div className="tour-grid">
        <ol className="tour-steps">
          {STEPS.map((s, i) => (
            <li
              key={s.shot}
              ref={(el) => {
                refs.current[i] = el;
              }}
              data-index={i}
              className={`tour-step ${i === active ? "is-active" : ""}`}
            >
              <span className="tour-num">{String(i + 1).padStart(2, "0")}</span>
              <div className={`tour-prop ${s.propClass ?? ""}`}>
                <img src={s.prop} alt="" />
              </div>
              <div className="tour-text">
                <h3>
                  {s.title}
                  {s.key && <span className="key key-sm">{s.key}</span>}
                </h3>
                <p>{s.body}</p>
                <img className="tour-inline" src={`/assets/screens/${s.shot}.webp`} alt={`${s.title} in The Boss`} loading="lazy" />
              </div>
            </li>
          ))}
        </ol>

        <div className="tour-screen-wrap">
          <figure className="tour-screen">
            <div className="tour-screen-bar">
              <i />
              <i />
              <i />
              <span>The Boss — {STEPS[active].label}</span>
            </div>
            <div className="tour-screen-img">
              {STEPS.map((s, i) => (
                <img
                  key={s.shot}
                  src={`/assets/screens/${s.shot}.webp`}
                  alt={i === active ? `${s.title} in The Boss` : ""}
                  className={i === active ? "is-on" : ""}
                  loading={i < 2 ? "eager" : "lazy"}
                />
              ))}
            </div>
            <div className="tour-progress" style={{ "--p": (active + 1) / STEPS.length } as React.CSSProperties} />
          </figure>
        </div>
      </div>
    </section>
  );
}
