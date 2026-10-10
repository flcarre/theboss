import { useEffect, useMemo, useState } from "react";
import type { RuleItem, RuleKind, Snapshot } from "../api";
import { ruleContent } from "../backend";
import { relative, tr, trf } from "../i18n";
import { Chip, EmptyState, HarnessTag, PixelButton, PixelGlyph, SectionTitle } from "./pixel";
import { openInSystem, revealInFolder, tildePath } from "./system";
import { COLOR, HARNESS_COLOR, RULE_KINDS, isMac, ruleKindLabel } from "./theme";

const GLOBAL_SCOPE = "Global";
const CONTENT_LIMIT = 60_000;

const KIND_GLYPH: Record<RuleKind, string> = {
  instructions: "R",
  skill: "S",
  hook: "H",
  agent: "A",
  command: "/",
  settings: "⚙",
};

function scopeLabel(scope: string): string {
  return scope === GLOBAL_SCOPE ? tr("Global") : scope;
}

function compareRules(left: RuleItem, right: RuleItem): number {
  const keys: Array<[string, string]> = [
    [left.scope, right.scope],
    [left.kind, right.kind],
    [left.name, right.name],
  ];
  for (const [a, b] of keys) if (a !== b) return a < b ? -1 : 1;
  return 0;
}

export function LibraryPanel({ snapshot }: { snapshot: Snapshot }) {
  const rules = snapshot.rules;
  const [kind, setKind] = useState<RuleKind | null>(null);
  const [scope, setScope] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const scopes = useMemo(() => {
    const others = [...new Set(rules.map((rule) => rule.scope))].filter((item) => item !== GLOBAL_SCOPE).sort();
    return [GLOBAL_SCOPE, ...others];
  }, [rules]);

  const filtered = useMemo(() => {
    const needle = query.trim().toLocaleLowerCase();
    return rules
      .filter(
        (rule) =>
          (kind === null || rule.kind === kind) &&
          (scope === null || rule.scope === scope) &&
          (needle === "" || rule.name.toLocaleLowerCase().includes(needle) || rule.summary.toLocaleLowerCase().includes(needle)),
      )
      .sort(compareRules);
  }, [rules, kind, scope, query]);

  const selected = rules.find((rule) => rule.id === selectedId) ?? null;

  return (
    <div className="split">
      <div className="split-list library-list">
        <div className="chip-row">
          <Chip text={tr("All")} count={rules.length} color={COLOR.base} selected={kind === null} onClick={() => setKind(null)} />
          {RULE_KINDS.map((item) => {
            const count = rules.filter((rule) => rule.kind === item).length;
            return count > 0 ? (
              <Chip key={item} text={ruleKindLabel(item)} count={count} color={COLOR.base} selected={kind === item} onClick={() => setKind(item)} />
            ) : null;
          })}
        </div>
        <div className="filter-row">
          <select className="pixel-select" value={scope ?? ""} onChange={(event) => setScope(event.target.value || null)}>
            <option value="">{tr("All projects")}</option>
            {scopes.map((item) => (
              <option key={item} value={item}>
                {scopeLabel(item)}
              </option>
            ))}
          </select>
          <label className="search-field">
            <PixelGlyph name="search" size={18} />
            <input value={query} placeholder={tr("Search…")} onChange={(event) => setQuery(event.target.value)} />
            {query && (
              <button type="button" onClick={() => setQuery("")} aria-label={tr("Close")}>
                ✕
              </button>
            )}
          </label>
        </div>
        {!snapshot.insightsReady && rules.length === 0 ? (
          <EmptyState text={tr("Taking inventory…")} />
        ) : filtered.length === 0 ? (
          <EmptyState text={tr("Nothing matches.")} />
        ) : (
          <div className="scroll-area list-stack">
            {filtered.map((rule) => (
              <RuleRow key={rule.id} rule={rule} selected={rule.id === selectedId} onSelect={() => setSelectedId(rule.id)} />
            ))}
          </div>
        )}
      </div>
      <div className="split-divider" />
      {selected ? <RuleDetail key={selected.id} rule={selected} mac={isMac(snapshot.platform)} /> : <EmptyState text={tr("Pick a file on the left to read it.")} />}
    </div>
  );
}

function RuleRow({ rule, selected, onSelect }: { rule: RuleItem; selected: boolean; onSelect: () => void }) {
  return (
    <button type="button" className={`list-row card ${selected ? "is-selected" : ""}`} onClick={onSelect}>
      <span className="rule-glyph" style={{ background: HARNESS_COLOR[rule.harness] }}>
        {KIND_GLYPH[rule.kind]}
      </span>
      <span className="list-row-text">
        <span className="rule-row-head">
          <b>{rule.name}</b>
          <span className="scope-tag">{scopeLabel(rule.scope)}</span>
        </span>
        <span className="rule-summary">{rule.summary || ruleKindLabel(rule.kind)}</span>
      </span>
    </button>
  );
}

function RuleDetail({ rule, mac }: { rule: RuleItem; mac: boolean }) {
  const [content, setContent] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    ruleContent(rule.path).then((text) => {
      if (!alive) return;
      const value = text ?? tr("Unreadable.");
      setContent(value.length > CONTENT_LIMIT ? `${value.slice(0, CONTENT_LIMIT)}\n…` : value);
    });
    return () => {
      alive = false;
    };
  }, [rule.path]);

  return (
    <div className="split-detail rule-detail">
      <div className="detail-head">
        <div className="detail-heading">
          <h3>{rule.name}</h3>
          <code className="path-line">{tildePath(rule.path)}</code>
          <span className="detail-meta">
            <HarnessTag harness={rule.harness} />
            <span>{trf("%@ · %d bytes · modified %@", ruleKindLabel(rule.kind), rule.size, relative(rule.modifiedAt))}</span>
          </span>
        </div>
        <div className="button-row">
          <PixelButton title={tr("Open")} onClick={() => void openInSystem(rule.path)} />
          <PixelButton title={mac ? "Finder" : tr("Show in folder")} tone="card" onClick={() => void revealInFolder(rule.path)} />
        </div>
      </div>
      {rule.kind === "hook" && (
        <div className="stack-6">
          <SectionTitle text={tr("Hook command")} />
          <code className="hook-command card flat">{rule.summary}</code>
        </div>
      )}
      <pre className="file-content card">{content ?? ""}</pre>
    </div>
  );
}
