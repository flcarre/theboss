import type { AgentSession } from "../api";

export type RoomId = "office" | "openSpace";

export type Interaction =
  | "usage"
  | "library"
  | "inbox"
  | "analytics"
  | "overview"
  | "archives"
  | "coffee"
  | "water"
  | "sofa"
  | "servers"
  | "window"
  | "plant"
  | "robot";

export type GameCallbacks = {
  onInteract: (interaction: Interaction, session: AgentSession | null) => void;
  onWhip: (session: AgentSession | null) => void;
  onMenu: () => void;
  onEnterRoom: (room: RoomId) => void;
  onSound: (name: SoundName) => void;
};

export type SoundName = "tink" | "pop" | "glass" | "whip";

export type GameProps = {
  floorSessions: AgentSession[];
  inboxCount: number;
  zoom: number;
  inputBlocked: boolean;
  callbacks: GameCallbacks;
};

export type GameHandle = {
  endConversation: () => void;
  crackWhip: () => void;
  enterRoom: (room: RoomId) => void;
};

export const OPEN_SPACE_DESKS = 12;
