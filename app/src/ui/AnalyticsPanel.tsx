import type { CSSProperties } from "react";
import type { Snapshot, Trend } from "../api";
import { formatDayShort, tr } from "../i18n";
import { BarChart } from "./BarChart";
import { EmptyState, SectionTitle } from "./pixel";
import { COLOR, trendLabel } from "./theme";
import { TokenStat } from "./UsagePanel";

function trendStyle(trend: Trend): { color: string; arrow: string } {
  switch (trend.kind) {
    case "improving":
      return { color: COLOR.success, arrow: "↘" };
    case "degrading":
      return { color: COLOR.danger, arrow: "↗" };
    case "stable":
      return { color: COLOR.info, arrow: "→" };
    case "notEnoughData":
      return { color: COLOR.muted, arrow: "…" };
  }
}

function formatCount(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

export function AnalyticsPanel({ snapshot }: { snapshot: Snapshot }) {
  const report = snapshot.analytics;
  if (!report) return <EmptyState text={tr("Reading your last 30 days of conversations…")} />;
  const trend = trendStyle(report.trend);
  const applied = snapshot.suggestions.filter((suggestion) => suggestion.status === "applied").length;
  const prompts = tr("Prompts");
  const corrections = tr("Corrections");
  return (
    <div className="scroll-area padded">
      <div className="stack-18">
        <div className="equal-row" style={{ "--columns": 5 } as CSSProperties}>
          <div className="token-stat card trend-card" style={{ "--tint": trend.color } as CSSProperties}>
            <span>{tr("Trend")}</span>
            <div className="trend-value">
              <i style={{ color: trend.color }}>{trend.arrow}</i>
              <b>{trendLabel(report.trend)}</b>
            </div>
          </div>
          <TokenStat label={tr("Prompts · 7 days")} value={String(report.promptsThisWeek)} tint={COLOR.info} />
          <TokenStat label={tr("Corrections · 7 days")} value={String(report.correctionsThisWeek)} tint={COLOR.pink} />
          <TokenStat label={tr("Rules applied")} value={String(applied)} tint={COLOR.success} />
          <TokenStat label={tr("Whips cracked")} value={String(snapshot.whipCount)} tint={COLOR.crustDark} />
        </div>
        <SectionTitle text={tr("Corrections per 100 prompts, by day")} />
        <BarChart
          height={150}
          labelEvery={4}
          formatValue={formatCount}
          data={report.days.map((day) => ({
            key: day.day,
            label: formatDayShort(day.day),
            segments: [{ label: corrections, color: COLOR.pink, value: day.prompts === 0 ? 0 : (day.corrections / day.prompts) * 100 }],
          }))}
        />
        <SectionTitle text={tr("Prompts sent per day")} />
        <BarChart
          height={150}
          labelEvery={4}
          formatValue={formatCount}
          legendShape="circle"
          legend={[
            { label: prompts, color: COLOR.info },
            { label: corrections, color: COLOR.warning },
          ]}
          data={report.days.map((day) => ({
            key: day.day,
            label: formatDayShort(day.day),
            segments: [
              { label: prompts, color: COLOR.info, value: day.prompts },
              { label: corrections, color: COLOR.warning, value: day.corrections },
            ],
          }))}
        />
        <p className="note">
          {tr(
            "A correction is a message where you push back on the agent (“no”, “I told you”, “stop”…). The fewer there are, the better your setup understands what you want.",
          )}
        </p>
      </div>
    </div>
  );
}
