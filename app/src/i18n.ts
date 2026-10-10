import type { Language } from "./api";
import french from "../../shared/fr.json";

const frenchTable: Record<string, string> = french;

let language: Language = "en";

export function setLanguage(next: Language): void {
  language = next;
  document.documentElement.lang = next;
}

export function currentLanguage(): Language {
  return language;
}

export function currentLocale(): string {
  return language === "fr" ? "fr-FR" : "en-US";
}

export function tr(key: string): string {
  return language === "fr" ? (frenchTable[key] ?? key) : key;
}

export function trf(key: string, ...args: Array<string | number>): string {
  let index = 0;
  return tr(key).replace(/%[@d]/g, (placeholder) => {
    const value = args[index++];
    if (value === undefined) return placeholder;
    return placeholder === "%d" ? String(Math.trunc(Number(value))) : String(value);
  });
}

export function formatTokens(value: number): string {
  if (value >= 1_000_000_000) return `${(value / 1_000_000_000).toFixed(1)} G`;
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)} M`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)} k`;
  return String(value);
}

export function formatNumber(value: number): string {
  return new Intl.NumberFormat(currentLocale()).format(value);
}

const RELATIVE_STEPS: Array<{ unit: Intl.RelativeTimeFormatUnit; seconds: number; limit: number }> = [
  { unit: "second", seconds: 1, limit: 60 },
  { unit: "minute", seconds: 60, limit: 3600 },
  { unit: "hour", seconds: 3600, limit: 86400 },
  { unit: "day", seconds: 86400, limit: 7 * 86400 },
  { unit: "week", seconds: 7 * 86400, limit: 30 * 86400 },
  { unit: "month", seconds: 30 * 86400, limit: 365 * 86400 },
  { unit: "year", seconds: 365 * 86400, limit: Number.POSITIVE_INFINITY },
];

export function relative(date: string | null | undefined, now: number = Date.now()): string {
  if (!date) return "—";
  const time = Date.parse(date);
  if (Number.isNaN(time)) return "—";
  const delta = (time - now) / 1000;
  const magnitude = Math.abs(delta);
  const step = RELATIVE_STEPS.find((candidate) => magnitude < candidate.limit) ?? RELATIVE_STEPS[RELATIVE_STEPS.length - 1];
  const amount = Math.round(delta / step.seconds);
  const formatter = new Intl.RelativeTimeFormat(currentLocale(), { style: "short", numeric: "always" });
  return formatter.format(amount === 0 ? (delta < 0 ? -0 : 0) : amount, step.unit);
}

export function dayKey(date: Date): string {
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${date.getFullYear()}-${month}-${day}`;
}

export function parseDayKey(key: string): Date {
  const [year, month, day] = key.split("-").map(Number);
  return new Date(year, (month ?? 1) - 1, day ?? 1);
}

export function formatDayShort(key: string): string {
  return new Intl.DateTimeFormat(currentLocale(), { month: "short", day: "numeric" }).format(parseDayKey(key));
}
