import { forwardRef, useEffect, useImperativeHandle, useRef } from "react";
import { preloadAll } from "./assets";
import { WorldScene } from "./scene";
import type { GameHandle, GameProps } from "./types";

const MAX_STEP = 0.1;

function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement || target.isContentEditable;
}

export const Game = forwardRef<GameHandle, GameProps>(function Game(props, ref) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const sceneRef = useRef<WorldScene | null>(null);
  const propsRef = useRef(props);
  propsRef.current = props;

  useImperativeHandle(
    ref,
    () => ({
      endConversation: () => sceneRef.current?.endConversation(),
      crackWhip: () => sceneRef.current?.crackWhip(),
      enterRoom: (room) => sceneRef.current?.enterRoom(room),
    }),
    [],
  );

  useEffect(() => {
    const canvas = canvasRef.current;
    const context = canvas?.getContext("2d");
    if (!canvas || !context) return;
    const scene = new WorldScene({
      callbacks: () => propsRef.current.callbacks,
      inputBlocked: () => propsRef.current.inputBlocked,
    });
    sceneRef.current = scene;
    scene.setZoom(propsRef.current.zoom);
    scene.setInbox(propsRef.current.inboxCount);
    scene.setFloor(propsRef.current.floorSessions);
    void preloadAll();

    let frame = 0;
    let last = performance.now();
    let size = { width: 0, height: 0, dpr: 0 };

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      if (rect.width === size.width && rect.height === size.height && dpr === size.dpr) return;
      size = { width: rect.width, height: rect.height, dpr };
      canvas.width = Math.max(1, Math.round(rect.width * dpr));
      canvas.height = Math.max(1, Math.round(rect.height * dpr));
      scene.setViewport({ cssWidth: rect.width, cssHeight: rect.height, dpr });
    };

    const loop = (time: number) => {
      const dt = Math.min(MAX_STEP, Math.max(0, (time - last) / 1000));
      last = time;
      resize();
      scene.tick(dt);
      scene.render(context);
      frame = requestAnimationFrame(loop);
    };

    const start = () => {
      if (frame || document.hidden) return;
      last = performance.now();
      frame = requestAnimationFrame(loop);
    };

    const stop = () => {
      cancelAnimationFrame(frame);
      frame = 0;
    };

    const onVisibility = () => {
      if (document.hidden) {
        stop();
        scene.releaseKeys();
      } else start();
    };

    const onKeyDown = (event: KeyboardEvent) => {
      if (isTypingTarget(event.target)) return;
      if (scene.handleKeyDown(event)) event.preventDefault();
    };

    const onKeyUp = (event: KeyboardEvent) => {
      scene.handleKeyUp(event);
    };

    const onBlur = () => scene.releaseKeys();

    const localPoint = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      return { x: event.clientX - rect.left, y: event.clientY - rect.top };
    };

    const onPointerDown = (event: PointerEvent) => {
      if (event.button !== 0 || propsRef.current.inputBlocked) return;
      const point = localPoint(event);
      scene.handlePointerDown(point.x, point.y);
    };

    const onPointerMove = (event: PointerEvent) => {
      const point = localPoint(event);
      canvas.style.cursor = !propsRef.current.inputBlocked && scene.isClickable(point.x, point.y) ? "pointer" : "default";
    };

    const observer = new ResizeObserver(resize);
    observer.observe(canvas);
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    window.addEventListener("blur", onBlur);
    document.addEventListener("visibilitychange", onVisibility);
    canvas.addEventListener("pointerdown", onPointerDown);
    canvas.addEventListener("pointermove", onPointerMove);
    resize();
    start();

    return () => {
      stop();
      observer.disconnect();
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      window.removeEventListener("blur", onBlur);
      document.removeEventListener("visibilitychange", onVisibility);
      canvas.removeEventListener("pointerdown", onPointerDown);
      canvas.removeEventListener("pointermove", onPointerMove);
      scene.dispose();
      sceneRef.current = null;
    };
  }, []);

  useEffect(() => {
    sceneRef.current?.setFloor(props.floorSessions);
  }, [props.floorSessions]);

  useEffect(() => {
    sceneRef.current?.setInbox(props.inboxCount);
  }, [props.inboxCount]);

  useEffect(() => {
    sceneRef.current?.setZoom(props.zoom);
  }, [props.zoom]);

  useEffect(() => {
    if (props.inputBlocked) sceneRef.current?.releaseKeys();
  }, [props.inputBlocked]);

  return <canvas ref={canvasRef} style={{ display: "block", width: "100%", height: "100%", imageRendering: "pixelated", touchAction: "none" }} />;
});
