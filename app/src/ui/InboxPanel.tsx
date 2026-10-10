import { useState } from "react";
import type { Snapshot, Suggestion, SuggestionStatus } from "../api";
import { relative, tr, trf } from "../i18n";
import { DiffView } from "./DiffView";
import { model } from "./model";
import { AssetIcon, EmptyState, HarnessTag, PixelButton, SectionTitle, SegmentedTabs, type TabItem } from "./pixel";
import { openFileOrFolder } from "./system";
import { COLOR } from "./theme";

const STATUSES: SuggestionStatus[] = ["new", "saved", "applied", "dismissed"];
const EVIDENCE_LIMIT = 6;

function isStatus(value: string): value is SuggestionStatus {
  return (STATUSES as string[]).includes(value);
}

export function InboxPanel({ snapshot }: { snapshot: Snapshot }) {
  const [tab, setTab] = useState<SuggestionStatus>("new");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const items = snapshot.suggestions.filter((suggestion) => suggestion.status === tab);
  const selected = items.find((suggestion) => suggestion.id === selectedId) ?? items[0] ?? null;

  const tabItem = (status: SuggestionStatus, title: string, color: string): TabItem => ({
    id: status,
    title,
    count: snapshot.suggestions.filter((suggestion) => suggestion.status === status).length,
    color,
  });

  return (
    <div className="split">
      <div className="split-list inbox-list">
        <SegmentedTabs
          items={[
            tabItem("new", tr("New"), COLOR.pink),
            tabItem("saved", tr("Later"), COLOR.base),
            tabItem("applied", tr("Applied"), COLOR.base),
            tabItem("dismissed", tr("Dismissed"), COLOR.base),
          ]}
          selection={tab}
          onSelect={(id) => {
            if (isStatus(id)) setTab(id);
            setSelectedId(null);
          }}
        />
        {!snapshot.insightsReady ? (
          <EmptyState text={tr("The mailman is reading your conversations…")} />
        ) : items.length === 0 ? (
          <EmptyState text={tab === "new" ? tr("Nothing to review. Your agents are behaving.") : tr("Empty.")} />
        ) : (
          <div className="scroll-area list-stack">
            {items.map((suggestion) => (
              <SuggestionRow
                key={suggestion.id}
                suggestion={suggestion}
                selected={suggestion.id === selected?.id}
                onSelect={() => setSelectedId(suggestion.id)}
              />
            ))}
          </div>
        )}
      </div>
      <div className="split-divider" />
      {selected ? (
        <SuggestionDetail key={selected.id} suggestion={selected} refining={snapshot.refining.includes(selected.id)} />
      ) : (
        <EmptyState text={tr("Pick a letter.")} />
      )}
    </div>
  );
}

function SuggestionRow({ suggestion, selected, onSelect }: { suggestion: Suggestion; selected: boolean; onSelect: () => void }) {
  const kindLabel = suggestion.kind === "learnedRule" ? tr("Learned rule") : tr("Setup fix");
  const detail =
    suggestion.evidence.length === 0
      ? trf("%@ · setup check", suggestion.project)
      : suggestion.evidence.length === 1
        ? trf("%@ · 1 piece of evidence", suggestion.project)
        : trf("%@ · %d pieces of evidence", suggestion.project, suggestion.evidence.length);
  return (
    <button type="button" className={`list-row card suggestion-row ${selected ? "is-selected" : ""}`} onClick={onSelect}>
      <AssetIcon name={suggestion.kind === "learnedRule" ? "mail" : "settings"} size={32} />
      <span className="list-row-text">
        <small className="kicker">{kindLabel}</small>
        <b className="suggestion-title">{suggestion.title}</b>
        <span className="suggestion-detail">{detail}</span>
      </span>
    </button>
  );
}

function SuggestionDetail({ suggestion, refining }: { suggestion: Suggestion; refining: boolean }) {
  const status = suggestion.status;
  return (
    <div className="split-detail suggestion-detail-panel">
      <div className="stack-6">
        <h3 className="detail-title">{suggestion.title}</h3>
        <p className="detail-rationale">{suggestion.rationale}</p>
      </div>
      <div className="scroll-area stack-16">
        {suggestion.evidence.length > 0 && (
          <>
            <SectionTitle text={tr("Evidence")} />
            {suggestion.evidence.slice(0, EVIDENCE_LIMIT).map((evidence, index) => (
              <div key={index} className="evidence card">
                {evidence.context && (
                  <div className="evidence-line">
                    <b>{tr("Agent")}</b>
                    <p className="evidence-context">{evidence.context}</p>
                  </div>
                )}
                <div className="evidence-line">
                  <b className="is-you">{tr("You")}</b>
                  <p className="evidence-quote">{evidence.quote}</p>
                </div>
                <div className="evidence-meta">
                  <HarnessTag harness={evidence.harness} />
                  <span>{relative(evidence.date)}</span>
                </div>
              </div>
            ))}
          </>
        )}
        <SectionTitle text={trf("Exact diff · %@", suggestion.displayPath)} />
        <DiffView lines={status === "applied" ? [] : suggestion.diff} />
      </div>
      <div className="action-bar">
        {status !== "applied" && <PixelButton title={tr("Apply")} tone="success" onClick={() => void model.setSuggestionStatus(suggestion, "applied")} />}
        {status !== "saved" && status !== "applied" && (
          <PixelButton title={tr("Later")} tone="card" onClick={() => void model.setSuggestionStatus(suggestion, "saved")} />
        )}
        {status !== "dismissed" && status !== "applied" && (
          <PixelButton title={tr("Dismiss")} tone="card" onClick={() => void model.setSuggestionStatus(suggestion, "dismissed")} />
        )}
        {(status === "dismissed" || status === "saved") && (
          <PixelButton title={tr("Restore")} tone="card" onClick={() => void model.setSuggestionStatus(suggestion, "new")} />
        )}
        <span className="spacer" />
        {suggestion.kind === "learnedRule" &&
          status !== "applied" &&
          (refining ? (
            <span className="quiet-line">{tr("Claude is thinking…")}</span>
          ) : (
            <PixelButton
              title={suggestion.refinedRule === null ? tr("Rewrite with Claude") : tr("Rewrite again")}
              tone="card"
              onClick={() => model.refine(suggestion)}
              help={tr("Runs Claude Code locally (Haiku model, your plan) to write a clear rule from the evidence.")}
            />
          ))}
        <PixelButton title={tr("Open file")} tone="card" onClick={() => void openFileOrFolder(suggestion.filePath)} />
      </div>
    </div>
  );
}
