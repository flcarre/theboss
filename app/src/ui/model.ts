import { useSyncExternalStore } from "react";
import type { AgentSession, Settings, Snapshot, Suggestion, SuggestionStatus } from "../api";
import { backend, backendEvents } from "../backend";
import type { GameHandle, Interaction, RoomId, SoundName } from "../game/types";
import { OPEN_SPACE_DESKS } from "../game/types";
import { robotName, robotPortrait } from "../game/robotName";
import { formatTokens, setLanguage, tr, trf } from "../i18n";
import { playSound, setSoundsEnabled } from "../sound";
import { copyText, openInSystem } from "./system";
import { HARNESS_NAME, isMac, tokensToday, totalTokens } from "./theme";

export type PanelId = "overview" | "usage" | "library" | "inbox" | "analytics" | "settings" | "domain";
export type Panel = { kind: PanelId } | { kind: "robot"; sessionId: string };

export type DialogChoice = { title: string; action: () => void };
export type Dialog = { id: number; speaker: string | null; portrait: string | null; pages: string[]; choices: DialogChoice[] };

export type MenuEntry = "agents" | "inbox" | "usage" | "rules" | "stats" | "domain" | "settings" | "close";
export const MENU_ENTRIES: MenuEntry[] = ["agents", "inbox", "usage", "rules", "stats", "domain", "settings", "close"];

export type Toast = { id: number; text: string };

export type ViewState = {
  snapshot: Snapshot | null;
  room: RoomId;
  panel: Panel | null;
  dialog: Dialog | null;
  dialogPage: number;
  dialogChoice: number;
  menuOpen: boolean;
  menuIndex: number;
  toast: Toast | null;
};

type DialogReveal = { complete: boolean; reveal: () => void };

const TOAST_DURATION = 3500;
const SOUND_NAMES: SoundName[] = ["tink", "pop", "glass", "whip"];

function isSoundName(value: string): value is SoundName {
  return (SOUND_NAMES as string[]).includes(value);
}
const ADVANCE_CODES = new Set(["Space", "Enter", "NumpadEnter", "KeyE", "KeyZ"]);
const UP_CODES = new Set(["ArrowUp", "KeyW"]);
const DOWN_CODES = new Set(["ArrowDown", "KeyS"]);
const DIALOG_CLOSE_CODES = new Set(["Escape", "KeyX"]);
const MENU_CLOSE_CODES = new Set(["Escape", "Tab", "KeyX"]);
const SHORTCUT_PANELS: Record<string, PanelId> = {
  Digit1: "overview",
  Digit2: "inbox",
  Digit3: "usage",
  Digit4: "library",
  Digit5: "analytics",
  Digit6: "domain",
  Comma: "settings",
};
const PANEL_ALIASES: Record<string, PanelId> = {
  overview: "overview",
  agents: "overview",
  usage: "usage",
  library: "library",
  rules: "library",
  inbox: "inbox",
  mail: "inbox",
  analytics: "analytics",
  stats: "analytics",
  settings: "settings",
  domain: "domain",
  archives: "domain",
};

export function errorText(error: unknown): string {
  if (typeof error === "string") return error;
  if (error instanceof Error) return error.message;
  return String(error);
}

export function needsYou(snapshot: Snapshot | null): AgentSession[] {
  return snapshot?.sessions.filter((session) => session.status === "needsApproval") ?? [];
}

export function workingSessions(snapshot: Snapshot | null): AgentSession[] {
  return snapshot?.sessions.filter((session) => session.status === "working") ?? [];
}

export function finishedSessions(snapshot: Snapshot | null): AgentSession[] {
  return snapshot?.sessions.filter((session) => session.status === "finished") ?? [];
}

export function openSuggestions(snapshot: Snapshot | null): Suggestion[] {
  return snapshot?.suggestions.filter((suggestion) => suggestion.status === "new") ?? [];
}

export function floorSessions(snapshot: Snapshot | null, now: number = Date.now()): AgentSession[] {
  if (!snapshot) return [];
  const cutoff = now - snapshot.settings.finishedHours * 3600 * 1000;
  return snapshot.sessions
    .filter((session) => session.status !== "finished" || session.isLive || Date.parse(session.updatedAt) > cutoff)
    .slice(0, OPEN_SPACE_DESKS);
}

export function singleLineTruncated(text: string, limit: number): string {
  const line = text
    .split(/\r?\n/)
    .map((part) => part.trim())
    .filter((part) => part.length > 0)
    .join(" ");
  const characters = Array.from(line);
  return characters.length > limit ? `${characters.slice(0, limit - 1).join("")}…` : line;
}

export class BossModel {
  private state: ViewState = {
    snapshot: null,
    room: "office",
    panel: null,
    dialog: null,
    dialogPage: 0,
    dialogChoice: 0,
    menuOpen: false,
    menuIndex: 0,
    toast: null,
  };
  private listeners = new Set<() => void>();
  private game: GameHandle | null = null;
  private toastTimer: number | null = null;
  private dialogReveal: DialogReveal | null = null;
  private sequence = 0;

  getState = (): ViewState => this.state;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  private set(patch: Partial<ViewState>): void {
    this.state = { ...this.state, ...patch };
    this.listeners.forEach((listener) => listener());
  }

  get snapshot(): Snapshot | null {
    return this.state.snapshot;
  }

  get isInputBlocked(): boolean {
    return this.state.panel !== null || this.state.dialog !== null || this.state.menuOpen;
  }

  attachGame(handle: GameHandle | null): void {
    this.game = handle;
  }

  setDialogReveal(reveal: DialogReveal | null): void {
    this.dialogReveal = reveal;
  }

  start(): () => void {
    let disposed = false;
    const unlisteners: Array<() => void> = [];
    const keep = (promise: Promise<() => void>) =>
      promise.then((unlisten) => (disposed ? unlisten() : unlisteners.push(unlisten))).catch(() => undefined);
    keep(backendEvents.onSnapshot((snapshot) => this.applySnapshot(snapshot)));
    keep(backendEvents.onToast((text) => this.showToast(text)));
    keep(backendEvents.onOpenPanel((name) => this.openNamedPanel(name)));
    keep(backendEvents.onSound((name) => this.playNamed(name)));
    backend
      .snapshot()
      .then((snapshot) => {
        if (!disposed && !this.state.snapshot) this.applySnapshot(snapshot);
      })
      .catch((error: unknown) => this.showToast(errorText(error)));
    return () => {
      disposed = true;
      unlisteners.forEach((unlisten) => unlisten());
    };
  }

  applySnapshot(snapshot: Snapshot): void {
    setLanguage(snapshot.settings.language);
    setSoundsEnabled(snapshot.settings.sounds);
    this.set({ snapshot });
  }

  play(name: SoundName): void {
    playSound(name);
  }

  playNamed(name: string): void {
    if (isSoundName(name)) this.play(name);
  }

  showToast(text: string): void {
    if (this.toastTimer !== null) window.clearTimeout(this.toastTimer);
    this.set({ toast: { id: ++this.sequence, text } });
    this.toastTimer = window.setTimeout(() => {
      this.toastTimer = null;
      this.set({ toast: null });
    }, TOAST_DURATION);
  }

  updateSettings(patch: Partial<Settings>): void {
    const snapshot = this.state.snapshot;
    if (!snapshot) return;
    const settings = { ...snapshot.settings, ...patch };
    setLanguage(settings.language);
    setSoundsEnabled(settings.sounds);
    this.set({ snapshot: { ...snapshot, settings } });
    backend.saveSettings(settings).catch((error: unknown) => this.showToast(errorText(error)));
  }

  enterRoom(room: RoomId): void {
    this.set({ room });
  }

  open(panel: Panel): void {
    this.set({ menuOpen: false, dialog: null, panel });
    this.play("pop");
  }

  openNamedPanel(name: string): void {
    const id = PANEL_ALIASES[name];
    if (id) this.open({ kind: id });
    else if (name.startsWith("robot:")) this.open({ kind: "robot", sessionId: name.slice("robot:".length) });
  }

  closePanel(): void {
    this.set({ panel: null });
    this.game?.endConversation();
    this.play("tink");
  }

  openMenu(): void {
    this.play("tink");
    this.set({ menuIndex: 0, menuOpen: true });
  }

  closeMenu(): void {
    this.set({ menuOpen: false });
  }

  say(speaker: string | null, pages: string[], options: { portrait?: string; choices?: DialogChoice[] } = {}): void {
    this.set({
      menuOpen: false,
      dialogPage: 0,
      dialogChoice: 0,
      dialog: { id: ++this.sequence, speaker, portrait: options.portrait ?? null, pages, choices: options.choices ?? [] },
    });
  }

  closeDialog(): void {
    this.set({ dialog: null });
    this.game?.endConversation();
  }

  advanceDialog(): void {
    const { dialog, dialogPage, dialogChoice } = this.state;
    if (!dialog) return;
    if (dialogPage < dialog.pages.length - 1) {
      this.set({ dialogPage: dialogPage + 1 });
      this.play("tink");
      return;
    }
    const choice = dialog.choices[dialogChoice];
    this.closeDialog();
    choice?.action();
  }

  revealOrAdvance(): void {
    if (this.dialogReveal && !this.dialogReveal.complete) this.dialogReveal.reveal();
    else this.advanceDialog();
  }

  setDialogChoice(index: number): void {
    if (index !== this.state.dialogChoice) this.set({ dialogChoice: index });
  }

  chooseDialog(index: number): void {
    this.set({ dialogChoice: index });
    this.advanceDialog();
  }

  moveDialogChoice(delta: number): void {
    const { dialog, dialogPage, dialogChoice } = this.state;
    if (!dialog || dialog.choices.length === 0 || dialogPage !== dialog.pages.length - 1) return;
    this.set({ dialogChoice: (dialogChoice + delta + dialog.choices.length) % dialog.choices.length });
    this.play("tink");
  }

  moveMenu(delta: number): void {
    this.set({ menuIndex: (this.state.menuIndex + delta + MENU_ENTRIES.length) % MENU_ENTRIES.length });
    this.play("tink");
  }

  setMenuIndex(index: number): void {
    if (index !== this.state.menuIndex) this.set({ menuIndex: index });
  }

  select(entry: MenuEntry): void {
    this.set({ menuOpen: false });
    switch (entry) {
      case "agents":
        return this.open({ kind: "overview" });
      case "inbox":
        return this.open({ kind: "inbox" });
      case "usage":
        return this.open({ kind: "usage" });
      case "rules":
        return this.open({ kind: "library" });
      case "stats":
        return this.open({ kind: "analytics" });
      case "domain":
        return this.open({ kind: "domain" });
      case "settings":
        return this.open({ kind: "settings" });
      case "close":
        return this.play("tink");
    }
  }

  handleKey(event: KeyboardEvent): boolean {
    const modifier = isMac(this.state.snapshot?.platform) ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey;
    if (modifier && !event.altKey && !event.shiftKey) {
      const target = SHORTCUT_PANELS[event.code];
      if (target) {
        this.open({ kind: target });
        return true;
      }
      return false;
    }
    if (event.metaKey || event.ctrlKey || event.altKey) return false;
    if (this.state.panel) {
      if (event.code === "Escape") {
        this.closePanel();
        return true;
      }
      return false;
    }
    if (this.state.dialog) {
      if (event.repeat && ADVANCE_CODES.has(event.code)) return true;
      if (ADVANCE_CODES.has(event.code)) this.revealOrAdvance();
      else if (UP_CODES.has(event.code)) this.moveDialogChoice(-1);
      else if (DOWN_CODES.has(event.code)) this.moveDialogChoice(1);
      else if (DIALOG_CLOSE_CODES.has(event.code)) this.closeDialog();
      return true;
    }
    if (this.state.menuOpen) {
      if (UP_CODES.has(event.code)) this.moveMenu(-1);
      else if (DOWN_CODES.has(event.code)) this.moveMenu(1);
      else if (ADVANCE_CODES.has(event.code) && !event.repeat) this.select(MENU_ENTRIES[this.state.menuIndex]);
      else if (MENU_CLOSE_CODES.has(event.code)) this.closeMenu();
      return true;
    }
    return false;
  }

  session(id: string): AgentSession | undefined {
    return this.state.snapshot?.sessions.find((session) => session.id === id);
  }

  whip(session: AgentSession | null): void {
    backend.recordWhip().catch(() => undefined);
    if (!session) return;
    const name = robotName(session);
    switch (session.status) {
      case "needsApproval":
        this.showToast(trf("%@ jumps: taking you to its session to approve.", name));
        void this.focus(session);
        return;
      case "working":
        this.showToast(trf("%@ types twice as fast. For a while.", name));
        return;
      case "finished":
        this.showToast(trf("%@ wakes up with a start. It had already finished.", name));
        return;
    }
  }

  interact(interaction: Interaction, session: AgentSession | null): void {
    this.play("tink");
    const snapshot = this.state.snapshot;
    switch (interaction) {
      case "usage":
        return this.open({ kind: "usage" });
      case "library":
        return this.open({ kind: "library" });
      case "analytics":
        return this.open({ kind: "analytics" });
      case "overview":
        return this.open({ kind: "overview" });
      case "archives":
        return this.open({ kind: "domain" });
      case "inbox": {
        if (!snapshot?.insightsReady) {
          return this.say(null, [tr("The mailman is still sorting the mail… (reading your conversations)")]);
        }
        const hasSaved = snapshot.suggestions.some((suggestion) => suggestion.status === "saved");
        if (openSuggestions(snapshot).length === 0 && !hasSaved) {
          return this.say(null, [tr("The in-tray is empty."), tr("Your agents learned nothing new this week. Correct them and the mail will come.")], {
            choices: [
              { title: tr("See history"), action: () => this.open({ kind: "inbox" }) },
              { title: tr("Close"), action: () => undefined },
            ],
          });
        }
        return this.open({ kind: "inbox" });
      }
      case "robot":
        if (session) return this.talk(session);
        return this.say(null, [tr("A free desk."), tr("Start an agent (Claude Code, Codex, Cursor, Pi…) and a robot will settle here.")]);
      case "coffee": {
        const today = snapshot?.usage ? totalTokens(tokensToday(snapshot.usage)) : 0;
        return this.say(null, [tr("The machine spits out a scalding espresso."), trf("Meanwhile, your robots swallowed %@ tokens today.", formatTokens(today))]);
      }
      case "water":
        return this.say(null, [tr("Glug glug."), tr("Robots don't drink water. They prefer fresh context.")]);
      case "sofa": {
        const working = workingSessions(snapshot).length;
        const crew =
          working === 0
            ? tr("Nobody is working. Enjoy.")
            : working === 1
              ? tr("1 robot is working for you. Enjoy.")
              : trf("%d robots are working for you. Enjoy.", working);
        return this.say(null, [tr("You flop onto the sofa."), crew]);
      }
      case "servers": {
        const installed = (snapshot?.installedHarnesses ?? []).map((harness) => HARNESS_NAME[harness]).join(", ");
        const mac = isMac(snapshot?.platform);
        return this.say(null, [
          tr("The racks are purring."),
          trf(mac ? "Harnesses found on this Mac: %@." : "Harnesses found on this computer: %@.", installed || tr("none")),
          tr(
            mac
              ? "Everything stays here: your conversations are read locally and kept in a SQLite database on your Mac."
              : "Everything stays here: your conversations are read locally and kept in a SQLite database on this computer.",
          ),
        ]);
      }
      case "window":
        return this.say(null, [tr("It's sunny outside."), tr("Your robots never see the sun. That's why they work so well.")]);
      case "plant":
        return this.say(null, [tr("A green plant."), tr("It looks healthier than your context window.")]);
    }
  }

  talk(session: AgentSession): void {
    const pages: string[] = [];
    const project = session.projectName || tr("a project");
    switch (session.status) {
      case "working":
        pages.push(trf("I'm working on “%@” in %@.", session.title, project));
        if (session.lastPrompt) pages.push(trf("Your last order: “%@”", singleLineTruncated(session.lastPrompt, 180)));
        break;
      case "needsApproval":
        pages.push(trf("Boss! I need your approval in %@.", project));
        if (session.pendingAction) pages.push(trf("I want to run: %@", singleLineTruncated(session.pendingAction, 180)));
        pages.push(trf("Approve me in %@ and I'll get back to it.", HARNESS_NAME[session.harness]));
        break;
      case "finished":
        pages.push(trf("I finished “%@” in %@.", session.title, project));
        if (session.lastReply) pages.push(trf("My last words: “%@”", singleLineTruncated(session.lastReply, 200)));
        break;
    }
    const choices: DialogChoice[] = [
      { title: tr("Read the logbook"), action: () => this.open({ kind: "robot", sessionId: session.id }) },
      { title: tr("Go to session"), action: () => void this.focus(session) },
    ];
    if (session.cwd) choices.push({ title: tr("Open folder"), action: () => void openInSystem(session.cwd) });
    choices.push({
      title: tr("Crack the whip"),
      action: () => {
        this.game?.endConversation();
        this.game?.crackWhip();
      },
    });
    choices.push({ title: tr("Nothing, carry on"), action: () => undefined });
    this.say(robotName(session), pages, { portrait: robotPortrait(session.harness), choices });
  }

  async focus(session: AgentSession): Promise<void> {
    try {
      const result = await backend.focusSession(session.id);
      if (result.opened) {
        this.showToast(tr("Session opened"));
        return;
      }
      await copyText(result.command);
      this.showToast(trf("Command copied: %@", result.command));
    } catch (error) {
      this.showToast(errorText(error));
    }
  }

  async copyCommand(command: string): Promise<void> {
    await copyText(command);
    this.showToast(tr("Command copied"));
  }

  async setSuggestionStatus(suggestion: Suggestion, status: SuggestionStatus): Promise<void> {
    try {
      await backend.setSuggestionStatus(suggestion.id, status);
    } catch (error) {
      this.showToast(errorText(error));
      return;
    }
    switch (status) {
      case "applied":
        this.showToast(trf("Written to %@", suggestion.displayPath));
        this.play("glass");
        return;
      case "saved":
        this.showToast(tr("Saved for later"));
        return;
      case "dismissed":
        this.showToast(tr("Suggestion dismissed"));
        return;
      case "new":
        return;
    }
  }

  refine(suggestion: Suggestion): void {
    if (this.state.snapshot?.refining.includes(suggestion.id)) return;
    backend.refineSuggestion(suggestion.id).catch((error: unknown) => this.showToast(errorText(error)));
  }

  async exportDomain(root: string): Promise<boolean> {
    try {
      const written = await backend.exportDomain(root);
      this.showToast(trf("Model written to %@", written));
      this.play("glass");
      return true;
    } catch (error) {
      this.showToast(errorText(error));
      return false;
    }
  }

  refreshUsage(force: boolean): void {
    backend.refreshUsage(force).catch((error: unknown) => this.showToast(errorText(error)));
  }

  repairClaudeUsage(): void {
    if (this.state.snapshot?.repairingClaude) return;
    backend.repairClaudeUsage().catch((error: unknown) => this.showToast(errorText(error)));
  }

  openClaudeLogin(): void {
    backend.openClaudeLogin().catch((error: unknown) => this.showToast(errorText(error)));
  }
}

export const model = new BossModel();

export function useBoss(): ViewState {
  return useSyncExternalStore(model.subscribe, model.getState);
}
