"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Office, type Target } from "@/lib/office";
import { STAFF, type Robot, type RobotState } from "@/lib/staff";
import Dialog from "./Dialog";

export default function OfficeStage() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const officeRef = useRef<Office | null>(null);
  const robotsRef = useRef<Robot[]>(STAFF.map((r) => ({ ...r })));
  const [counts, setCounts] = useState<Record<RobotState, number>>({ working: 4, waiting: 2, done: 2 });
  const [toast, setToast] = useState<{ text: string; id: number } | null>(null);
  const [target, setTarget] = useState<Target | null>(null);
  const [active, setActive] = useState(false);
  const [night, setNight] = useState(true);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const font = getComputedStyle(document.documentElement).getPropertyValue("--font-pixel").trim() || "monospace";
    const office = new Office(canvas, robotsRef.current, { onCounts: setCounts, onTalk: setTarget, onActive: setActive, onToast: (text) => setToast({ text, id: Date.now() }) }, font);
    officeRef.current = office;
    return () => office.destroy();
  }, []);

  useEffect(() => {
    officeRef.current?.setDialogOpen(target !== null);
  }, [target]);

  useEffect(() => {
    officeRef.current?.setNight(night);
  }, [night]);

  useEffect(() => {
    if (!toast) return;
    const id = setTimeout(() => setToast(null), 2600);
    return () => clearTimeout(id);
  }, [toast]);

  const whip = useCallback(() => {
    officeRef.current?.takeControl();
    officeRef.current?.crackWhip();
  }, []);

  const whipFromDialog = useCallback(() => {
    setTarget(null);
    setTimeout(() => officeRef.current?.crackWhip(), 60);
  }, []);

  const close = useCallback(() => {
    setTarget(null);
    canvasRef.current?.parentElement?.focus({ preventScroll: true });
  }, []);

  const setRobotState = useCallback((id: string, state: RobotState) => {
    officeRef.current?.setRobotState(id, state);
  }, []);

  return (
    <div className="stage-wrap reveal">
      <div
        className={`stage ${active ? "is-active" : ""} ${night ? "is-night" : ""}`}
        tabIndex={0}
        aria-label="Playable pixel office. Click to take control, move with the arrow keys or WASD, press Space to talk."
        onFocus={() => officeRef.current?.takeControl()}
      >
        <canvas ref={canvasRef} className="stage-canvas" />

        <div className="hud hud-tl">
          <span className="hud-chip"><i className="sq sq-wait" /><b>{counts.waiting}</b> waiting</span>
          <span className="hud-chip"><i className="sq sq-work" /><b>{counts.working}</b> working</span>
          <span className="hud-chip"><i className="sq sq-done" /><b>{counts.done}</b> done</span>
          <span className="hud-sep" />
          <span className="hud-chip hud-mail"><img src="/assets/objects/intray.png" alt="In-tray" /><b>3</b></span>
        </div>

        <div className="hud hud-tr" aria-label="Plan usage">
          <div className="gauge-row"><span>Claude Code</span><span className="gauge" style={{ "--v": 42 } as React.CSSProperties}><i /></span><b>42%</b></div>
          <div className="gauge-row"><span>Codex</span><span className="gauge gauge-warn" style={{ "--v": 63 } as React.CSSProperties}><i /></span><b>63%</b></div>
          <div className="gauge-row"><span>Cursor</span><span className="gauge" style={{ "--v": 38 } as React.CSSProperties}><i /></span><b>38%</b></div>
        </div>

        <div className="hud hud-bl" aria-hidden="true">
          <span className="key">←↑↓→</span> Walk <span className="key">Space</span> Talk <span className="key">F</span> Whip
        </div>

        <div className="hud hud-actions">
          <button className="hud-btn hud-whip" type="button" onClick={whip} aria-label="Crack the whip">
            <img src="/assets/characters/boss/rotations/east.png" alt="" />
            Crack the whip
          </button>

          <button className="hud-btn hud-lights" type="button" aria-pressed={!night} onClick={() => setNight((n) => !n)}>
            <span className="switch"><i /></span>
            {night ? "Lights off" : "Lights on"}
          </button>
        </div>

        {!active && !target && (
          <div className="takeover" aria-hidden="true">
            <span className="key">Click</span> to take control
          </div>
        )}

        {toast && (
          <div className="stage-toast" key={toast.id} role="status">
            {toast.text}
          </div>
        )}

        {target && <Dialog target={target} onClose={close} onRobotState={setRobotState} onWhip={whipFromDialog} />}
      </div>
      <p className="stage-caption">
        A playable slice of the app, right in your browser. Go talk to the robots waving at you.
      </p>
    </div>
  );
}
