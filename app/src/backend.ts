import { invoke } from "@tauri-apps/api/core";
import { api, events } from "./api";
import { mockApi, mockEvents, mockRuleContent } from "./mock";

export const isTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

export type Backend = typeof api;
export type BackendEvents = typeof events;

export const backend: Backend = isTauri ? api : mockApi;
export const backendEvents: BackendEvents = isTauri ? events : mockEvents;

export async function ruleContent(path: string): Promise<string | null> {
  if (!isTauri) return mockRuleContent(path);
  try {
    return await invoke<string>("rule_content", { path });
  } catch {
    return null;
  }
}
