import { useCallback, useEffect, useMemo } from "react";
import { Game } from "./game/Game";
import type { GameCallbacks, GameHandle } from "./game/types";
import { unlockAudio } from "./sound";
import { floorSessions, model, openSuggestions, useBoss } from "./ui/model";
import { DialogBox, HintBar, StartMenu, StatusHUD, ToastView, UsageHUD } from "./ui/Overlays";
import { PanelHost } from "./ui/PanelHost";

export function App() {
  const state = useBoss();
  const { snapshot, panel, dialog, menuOpen } = state;

  useEffect(() => model.start(), []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      unlockAudio();
      if (model.handleKey(event)) {
        event.preventDefault();
        event.stopPropagation();
      }
    };
    const onPointerDown = () => unlockAudio();
    window.addEventListener("keydown", onKeyDown, true);
    window.addEventListener("pointerdown", onPointerDown, true);
    return () => {
      window.removeEventListener("keydown", onKeyDown, true);
      window.removeEventListener("pointerdown", onPointerDown, true);
    };
  }, []);

  const attachGame = useCallback((handle: GameHandle | null) => model.attachGame(handle), []);

  const callbacks = useMemo<GameCallbacks>(
    () => ({
      onInteract: (interaction, session) => model.interact(interaction, session),
      onWhip: (session) => model.whip(session),
      onMenu: () => model.openMenu(),
      onEnterRoom: (room) => model.enterRoom(room),
      onSound: (name) => model.play(name),
    }),
    [],
  );

  const sessions = snapshot?.sessions;
  const finishedHours = snapshot?.settings.finishedHours;
  const floor = useMemo(() => floorSessions(snapshot), [sessions, finishedHours]);
  const inboxCount = openSuggestions(snapshot).length;
  const inputBlocked = panel !== null || dialog !== null || menuOpen;

  useEffect(() => {
    if (inputBlocked) return;
    const focused = document.activeElement;
    if (focused instanceof HTMLElement && focused !== document.body) focused.blur();
  }, [inputBlocked]);

  return (
    <div className="app">
      <div className="game-layer">
        <Game
          ref={attachGame}
          floorSessions={floor}
          inboxCount={inboxCount}
          zoom={snapshot?.settings.zoom ?? 1.5}
          inputBlocked={inputBlocked}
          callbacks={callbacks}
        />
      </div>
      {snapshot && (
        <>
          <div className="hud-row">
            <StatusHUD snapshot={snapshot} />
            <UsageHUD snapshot={snapshot} />
          </div>
          {!dialog && !panel && <HintBar room={state.room} snapshot={snapshot} />}
          {menuOpen && <StartMenu snapshot={snapshot} index={state.menuIndex} />}
          {dialog && <DialogBox dialog={dialog} page={state.dialogPage} choice={state.dialogChoice} />}
          {panel && <PanelHost panel={panel} snapshot={snapshot} />}
        </>
      )}
      {state.toast && <ToastView toast={state.toast} />}
    </div>
  );
}
