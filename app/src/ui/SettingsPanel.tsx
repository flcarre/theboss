import type { ReactNode } from "react";
import type { Language, Platform, Snapshot } from "../api";
import { tr } from "../i18n";
import { model } from "./model";
import { SectionTitle } from "./pixel";
import { isMac } from "./theme";

const LANGUAGES: Array<{ id: Language; name: string }> = [
  { id: "en", name: "English" },
  { id: "fr", name: "Français" },
];

const ZOOMS = [1, 1.5, 2];
const FINISHED_HOURS = [1, 6, 12];

function databasePath(platform: Platform): string {
  switch (platform) {
    case "macos":
      return "~/Library/Application Support/TheBoss/boss.sqlite";
    case "linux":
      return "~/.local/share/TheBoss/boss.sqlite";
    case "windows":
      return "%APPDATA%\\TheBoss\\boss.sqlite";
  }
}

function zoomLabel(zoom: number): string {
  return zoom === 1 ? tr("× 1 (native pixels)") : `× ${zoom}`;
}

function hoursLabel(hours: number): string {
  return hours === 1 ? tr("1 hour") : hours === 6 ? tr("6 hours") : tr("12 hours");
}

export function SettingsPanel({ snapshot }: { snapshot: Snapshot }) {
  const settings = snapshot.settings;
  const mac = isMac(snapshot.platform);
  return (
    <div className="scroll-area padded">
      <div className="settings stack-18">
        <SettingsCard title={tr("Language")}>
          <div className="segmented language-picker" role="radiogroup" aria-label={tr("Language")}>
            {LANGUAGES.map((language) => (
              <button
                key={language.id}
                type="button"
                role="radio"
                aria-checked={settings.language === language.id}
                className={settings.language === language.id ? "is-selected" : ""}
                onClick={() => model.updateSettings({ language: language.id })}
              >
                <span>{language.name}</span>
              </button>
            ))}
          </div>
        </SettingsCard>
        <SettingsCard title={tr("Game")}>
          <Toggle
            label={tr("Notify me when a robot is waiting or done")}
            checked={settings.notifications}
            onChange={(notifications) => model.updateSettings({ notifications })}
          />
          <Toggle label={tr("Sounds")} checked={settings.sounds} onChange={(sounds) => model.updateSettings({ sounds })} />
          <SettingRow label={tr("Zoom")}>
            <select
              className="pixel-select select-zoom"
              aria-label={tr("Zoom")}
              value={String(settings.zoom)}
              onChange={(event) => model.updateSettings({ zoom: Number(event.target.value) })}
            >
              {ZOOMS.map((zoom) => (
                <option key={zoom} value={String(zoom)}>
                  {zoomLabel(zoom)}
                </option>
              ))}
            </select>
          </SettingRow>
          <SettingRow label={tr("Finished robots stay in the open space for")}>
            <select
              className="pixel-select select-hours"
              aria-label={tr("Finished robots")}
              value={String(settings.finishedHours)}
              onChange={(event) => model.updateSettings({ finishedHours: Number(event.target.value) })}
            >
              {FINISHED_HOURS.map((hours) => (
                <option key={hours} value={String(hours)}>
                  {hoursLabel(hours)}
                </option>
              ))}
            </select>
          </SettingRow>
        </SettingsCard>
        <SettingsCard title={tr("Rule writing")}>
          <Toggle
            label={tr("Rewrite new rules with Claude automatically")}
            checked={settings.autoRefine}
            onChange={(autoRefine) => model.updateSettings({ autoRefine })}
          />
          <p className="note">
            {tr(
              "Optional. The Boss runs Claude Code locally (Haiku model, on your plan) with the conversation excerpts used as evidence. Off by default; the “Rewrite with Claude” button in the mail always works on demand.",
            )}
          </p>
        </SettingsCard>
        <SettingsCard title={tr("Privacy")}>
          <p className="note">
            {tr(
              mac
                ? "Everything stays on your Mac. The Boss reads the transcripts of Claude Code (~/.claude), Codex (~/.codex), Gemini CLI (~/.gemini), Copilot CLI (~/.copilot), Cursor (~/.cursor), Pi (~/.pi) and omp (~/.omp), and keeps them in a local SQLite database."
                : "Everything stays on your computer. The Boss reads the transcripts of Claude Code (~/.claude), Codex (~/.codex), Gemini CLI (~/.gemini), Copilot CLI (~/.copilot), Cursor (~/.cursor), Pi (~/.pi) and omp (~/.omp), and keeps them in a local SQLite database.",
            )}
          </p>
          <p className="note">
            {tr(
              mac
                ? "Claude limits come from Anthropic's API with the Claude Code token read from the keychain; Codex limits are read from its logs. Nothing is sent anywhere else."
                : "Claude limits come from Anthropic's API with the Claude Code token read from its credentials file; Codex limits are read from its logs. Nothing is sent anywhere else.",
            )}
          </p>
          <code className="path-line selectable">{databasePath(snapshot.platform)}</code>
        </SettingsCard>
      </div>
    </div>
  );
}

function SettingsCard({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="settings-card card">
      <SectionTitle text={title} />
      <div className="stack-12">{children}</div>
    </section>
  );
}

function SettingRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="setting-row">
      <span>{label}</span>
      {children}
    </div>
  );
}

function Toggle({ label, checked, onChange }: { label: string; checked: boolean; onChange: (value: boolean) => void }) {
  return (
    <label className="setting-row toggle-row">
      <span>{label}</span>
      <input type="checkbox" className="pixel-switch" role="switch" checked={checked} onChange={(event) => onChange(event.target.checked)} />
    </label>
  );
}
