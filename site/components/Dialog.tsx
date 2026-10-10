"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { Target } from "@/lib/office";
import type { RobotState } from "@/lib/staff";
import { HARNESS_COLOR, HARNESS_NAME, stillUrl } from "@/lib/sprites";

type Choice = { label: string; run: () => void };
type Page = { text: string; code?: string; choices: Choice[] };

type Props = {
  target: Target;
  onClose: () => void;
  onRobotState: (id: string, state: RobotState) => void;
};

export default function Dialog({ target, onClose, onRobotState }: Props) {
  const [reply, setReply] = useState<string | null>(null);
  const [typed, setTyped] = useState(0);
  const [choice, setChoice] = useState(0);

  const answer = useCallback(
    (text: string, state?: RobotState) => {
      if (target.kind === "robot" && state) onRobotState(target.robot.id, state);
      setReply(text);
    },
    [target, onRobotState],
  );

  const page: Page = useMemo(() => {
    if (reply) return { text: reply, choices: [{ label: "Close", run: onClose }] };
    if (target.kind === "prop") {
      const { prop } = target;
      const choices: Choice[] = [];
      if (prop.href) {
        choices.push({
          label: prop.cta ?? "See it",
          run: () => {
            onClose();
            document.querySelector(prop.href!)?.scrollIntoView({ behavior: "smooth" });
          },
        });
      }
      choices.push({ label: "Close", run: onClose });
      return { text: prop.text, choices };
    }
    const r = target.robot;
    if (r.state === "waiting") {
      return {
        text: `Boss! “${r.task}”. I need your OK before I run this:`,
        code: r.pending,
        choices: [
          { label: "Approve", run: () => answer(r.working, "working") },
          { label: "Not now", run: onClose },
        ],
      };
    }
    if (r.state === "done") {
      return {
        text: `Zzz… oh, hi boss. “${r.task}” is done. Resume me anytime with:`,
        code: r.resume,
        choices: [
          { label: "Resume", run: () => answer(r.working, "working") },
          { label: "Let it sleep", run: onClose },
        ],
      };
    }
    return { text: r.working, choices: [{ label: "Carry on", run: onClose }] };
  }, [target, reply, onClose, answer]);

  const full = page.text.length;
  const done = typed >= full;

  useEffect(() => {
    setTyped(0);
    setChoice(0);
  }, [page]);

  useEffect(() => {
    if (done) return;
    const id = setInterval(() => setTyped((t) => Math.min(full, t + 2)), 22);
    return () => clearInterval(id);
  }, [done, full]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        onClose();
      } else if (e.key === " " || e.key === "Enter") {
        e.preventDefault();
        if (!done) setTyped(full);
        else page.choices[choice]?.run();
      } else if (["ArrowRight", "ArrowDown", "d", "s"].includes(e.key)) {
        e.preventDefault();
        setChoice((c) => (c + 1) % page.choices.length);
      } else if (["ArrowLeft", "ArrowUp", "a", "w"].includes(e.key)) {
        e.preventDefault();
        setChoice((c) => (c - 1 + page.choices.length) % page.choices.length);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [done, full, page, choice, onClose]);

  const isRobot = target.kind === "robot";
  const face = isRobot ? stillUrl(target.robot.harness) : "/assets/boss_portrait.png";
  const name = isRobot ? HARNESS_NAME[target.robot.harness] : target.prop.title;
  const sub = isRobot ? target.robot.project : "Inner monologue";
  const color = isRobot ? HARNESS_COLOR[target.robot.harness] : "#F5B942";

  return (
    <div className="dialog" role="dialog" aria-label={`${name}, ${sub}`} onPointerDown={(e) => e.stopPropagation()}>
      <div className={`dialog-face ${isRobot ? "is-robot" : ""}`} style={{ "--c": color } as React.CSSProperties}>
        <img src={face} alt="" />
      </div>
      <div className="dialog-body">
        <p className="dialog-name">
          <b style={{ color }}>{name}</b>
          <span>{sub}</span>
        </p>
        <p className="dialog-text" aria-live="polite">
          {page.text.slice(0, typed)}
          {!done && <span className="dialog-cursor" />}
        </p>
        {page.code && done && <code className="dialog-code">$ {page.code}</code>}
        {done && (
          <div className="dialog-choices">
            {page.choices.map((c, i) => (
              <button key={c.label} type="button" className={i === choice ? "is-on" : ""} onMouseEnter={() => setChoice(i)} onClick={c.run}>
                {c.label}
              </button>
            ))}
          </div>
        )}
      </div>
      {done && <span className="dialog-caret" aria-hidden="true">▼</span>}
    </div>
  );
}
