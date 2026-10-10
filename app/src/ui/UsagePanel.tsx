import type { CSSProperties } from "react";
import type { DailyTokens, Platform, ProviderUsage, Snapshot, UsageState } from "../api";
import { robotPortrait } from "../game/robotName";
import { dayKey, formatDayShort, formatTokens, relative, tr, trf } from "../i18n";
import { BarChart, type BarDatum } from "./BarChart";
import { model } from "./model";
import { EmptyState, Gauge, InlineCode, PixelButton, PixelImage, SectionTitle } from "./pixel";
import { openInSystem } from "./system";
import {
  COLOR,
  HARNESSES,
  HARNESS_COLOR,
  HARNESS_NAME,
  capitalized,
  gaugeColor,
  isMac,
  tokensLastDays,
  tokensToday,
  totalTokens,
  withAlpha,
} from "./theme";

const CHART_DAYS = 14;

export function UsagePanel({ snapshot }: { snapshot: Snapshot }) {
  const usage = snapshot.usage;
  return (
    <div className="scroll-area padded">
      <div className="stack-18">
        <div className="row-between">
          <SectionTitle text={tr("Plan limits")} />
          <PixelButton title={tr("Refresh")} tone="card" onClick={() => model.refreshUsage(true)} />
        </div>
        {usage ? (
          <>
            <div className="equal-row provider-row">
              {usage.providers.map((provider) => (
                <ProviderCard key={provider.harness} provider={provider} snapshot={snapshot} />
              ))}
            </div>
            <SectionTitle text={tr("Token consumption")} />
            <div className="equal-row" style={{ "--columns": 4 } as CSSProperties}>
              <TokenStat label={tr("Today")} value={formatTokens(totalTokens(tokensToday(usage)))} />
              <TokenStat label={tr("7 days")} value={formatTokens(totalTokens(tokensLastDays(usage, 7)))} />
              <TokenStat label={tr("30 days")} value={formatTokens(totalTokens(tokensLastDays(usage, 30)))} />
              <TokenStat label={tr("Output · 7 days")} value={formatTokens(tokensLastDays(usage, 7).output)} />
            </div>
            <BarChart
              data={chartData(usage.daily)}
              height={170}
              labelEvery={2}
              formatValue={formatTokens}
              legend={HARNESSES.map((harness) => ({ label: HARNESS_NAME[harness], color: HARNESS_COLOR[harness] }))}
            />
          </>
        ) : (
          <EmptyState text={tr("Reading the counters…")} />
        )}
      </div>
    </div>
  );
}

function chartData(daily: DailyTokens[]): BarDatum[] {
  const today = new Date();
  return Array.from({ length: CHART_DAYS }, (_, index) => {
    const date = new Date(today.getFullYear(), today.getMonth(), today.getDate() - (CHART_DAYS - 1 - index));
    const key = dayKey(date);
    const entries = daily.filter((entry) => entry.day === key);
    return {
      key,
      label: formatDayShort(key),
      segments: HARNESSES.map((harness) => ({
        label: HARNESS_NAME[harness],
        color: HARNESS_COLOR[harness],
        value: entries.filter((entry) => entry.harness === harness).reduce((sum, entry) => sum + totalTokens(entry.tokens), 0),
      })),
    };
  });
}

function problemText(state: UsageState, platform: Platform): string | null {
  switch (state.kind) {
    case "ok":
      return null;
    case "notInstalled":
      return tr(isMac(platform) ? "Not installed on this Mac." : "Not installed on this computer.");
    case "signedOut":
      return tr("Claude Code is signed out.");
    case "keychainBlocked":
      return tr("macOS is blocking the keychain read.");
    case "tokenExpired":
      return tr("The sign-in token has expired.");
    case "noData":
      return tr("No usage data yet.");
    case "failed":
      return state.message;
  }
}

function fixSteps(state: UsageState, platform: Platform): string[] {
  switch (state.kind) {
    case "signedOut":
      return [
        tr("Open a terminal and run `claude auth status --text`."),
        tr("If it says “not logged in”, run `claude auth login`."),
        tr("Come back here: the gauge fills on the next refresh."),
      ];
    case "keychainBlocked":
      if (!isMac(platform)) return [];
      return [
        tr("Open Keychain Access and search for “Claude Code-credentials”."),
        tr("Access Control tab: add The Boss to “Always allow access by these applications”."),
        tr("If several items start with that name, do it for each one."),
        tr("This does not change your Claude account and does not sign you in."),
      ];
    case "tokenExpired":
      return [
        tr("Click “Fix automatically”: Claude Code refreshes its token."),
        tr("If that fails, run `claude auth login` in a terminal."),
        tr("Come back here: the gauge updates on its own."),
      ];
    case "noData":
      return [tr("Start a session: limits arrive with the agent's first reply.")];
    default:
      return [];
  }
}

function ProviderCard({ provider, snapshot }: { provider: ProviderUsage; snapshot: Snapshot }) {
  const mac = isMac(snapshot.platform);
  const state = provider.state;
  return (
    <div className="provider-card card">
      <div className="provider-head">
        <span className="provider-portrait" style={{ background: withAlpha(HARNESS_COLOR[provider.harness], 0.16) }}>
          <PixelImage src={robotPortrait(provider.harness)} size={46} />
        </span>
        <span className="provider-name">
          <b>{HARNESS_NAME[provider.harness]}</b>
          <span>{provider.plan ? trf("%@ plan", capitalized(provider.plan)) : " "}</span>
        </span>
        {provider.observedAt && <small>{relative(provider.observedAt)}</small>}
      </div>
      {state.kind === "ok" ? (
        provider.windows.map((window) => (
          <div key={window.label} className="provider-window">
            <div className="provider-window-head">
              <b>{window.label}</b>
              <strong>{Math.round(window.usedPercent)} %</strong>
            </div>
            <Gauge fraction={window.usedPercent / 100} color={gaugeColor(window.usedPercent)} className="gauge-large" />
            {window.resetsAt && <small>{trf("Resets %@", relative(window.resetsAt))}</small>}
          </div>
        ))
      ) : (
        <>
          <p className={`provider-problem ${state.kind === "notInstalled" ? "is-quiet" : ""}`}>{problemText(state, snapshot.platform)}</p>
          {fixSteps(state, snapshot.platform).map((step, index) => (
            <div key={step} className="fix-step">
              <span>{index + 1}</span>
              <p>
                <InlineCode text={step} />
              </p>
            </div>
          ))}
          {provider.harness === "claude" &&
            state.kind === "tokenExpired" &&
            (snapshot.repairingClaude ? (
              <p className="quiet-line">{tr("Claude Code is reconnecting…")}</p>
            ) : (
              <div className="button-row">
                <PixelButton
                  title={tr("Fix automatically")}
                  onClick={() => model.repairClaudeUsage()}
                  help={tr(
                    mac
                      ? "Runs Claude Code once locally (Haiku model): it refreshes its token in the keychain."
                      : "Runs Claude Code once locally (Haiku model): it refreshes its saved token.",
                  )}
                />
                <PixelButton
                  title={tr("Sign in again")}
                  tone="card"
                  onClick={() => model.openClaudeLogin()}
                  help={tr(mac ? "Opens Terminal on claude auth login." : "Opens a terminal on claude auth login.")}
                />
              </div>
            ))}
          {provider.harness === "claude" && state.kind === "signedOut" && (
            <div className="button-row">
              <PixelButton title={tr("Sign in again")} onClick={() => model.openClaudeLogin()} />
            </div>
          )}
          {state.kind === "keychainBlocked" && mac && (
            <div className="button-row">
              <PixelButton
                title={tr("Open Keychain Access")}
                tone="card"
                onClick={() => void openInSystem("/System/Applications/Utilities/Keychain Access.app")}
              />
            </div>
          )}
        </>
      )}
    </div>
  );
}

export function TokenStat({ label, value, tint = COLOR.crust }: { label: string; value: string; tint?: string }) {
  return (
    <div className="token-stat card" style={{ "--tint": tint } as CSSProperties}>
      <span>{label}</span>
      <b>{value}</b>
    </div>
  );
}
