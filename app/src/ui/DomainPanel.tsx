import { useCallback, useEffect, useRef, useState } from "react";
import type { DomainFact, DomainModel, Harness, Snapshot } from "../api";
import { backend } from "../backend";
import { tr, trf } from "../i18n";
import { DiffView } from "./DiffView";
import { errorText, model } from "./model";
import { AssetIcon, CountBadge, EmptyState, HarnessTag, PixelButton, SectionTitle } from "./pixel";
import { lastPathComponent, tildePath } from "./system";

const INTENT_SAVE_DELAY = 400;
const FACT_LIMIT = 40;
const ACTIVITY_LIMIT = 12;

function belongsTo(cwd: string, root: string): boolean {
  return cwd === root || cwd.startsWith(`${root}/`) || cwd.startsWith(`${root}\\`);
}

export function DomainPanel({ snapshot }: { snapshot: Snapshot }) {
  const [projects, setProjects] = useState<string[] | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [domain, setDomain] = useState<DomainModel | null>(null);
  const [intent, setIntent] = useState("");
  const [showExport, setShowExport] = useState(false);
  const pendingIntent = useRef<{ root: string; intent: string } | null>(null);
  const saveTimer = useRef<number | null>(null);

  const flushIntent = useCallback(async () => {
    if (saveTimer.current !== null) window.clearTimeout(saveTimer.current);
    saveTimer.current = null;
    const pending = pendingIntent.current;
    pendingIntent.current = null;
    if (pending) await backend.saveIntent(pending.root, pending.intent).catch(() => undefined);
  }, []);

  const select = useCallback(
    async (root: string) => {
      await flushIntent();
      setSelected(root);
      setShowExport(false);
      try {
        const built = await backend.domainModel(root);
        setDomain(built);
        setIntent(built.intent);
      } catch (error) {
        model.showToast(errorText(error));
      }
    },
    [flushIntent],
  );

  useEffect(() => {
    let alive = true;
    backend
      .domainProjects()
      .then((roots) => {
        if (!alive) return;
        setProjects(roots);
        if (roots[0]) void select(roots[0]);
      })
      .catch(() => alive && setProjects([]));
    return () => {
      alive = false;
      void flushIntent();
    };
  }, [select, flushIntent]);

  const editIntent = (value: string) => {
    if (!selected) return;
    setIntent(value);
    pendingIntent.current = { root: selected, intent: value };
    if (saveTimer.current !== null) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => void flushIntent(), INTENT_SAVE_DELAY);
  };

  const refresh = async (root: string) => {
    const built = await backend.domainModel(root);
    setDomain(built);
  };

  const toggleExport = async () => {
    if (!domain) return;
    if (!showExport) {
      await flushIntent();
      await refresh(domain.root).catch(() => undefined);
    }
    setShowExport(!showExport);
  };

  const writeExport = async () => {
    if (!domain) return;
    await flushIntent();
    if (await model.exportDomain(domain.root)) await refresh(domain.root).catch(() => undefined);
  };

  const roots = projects ?? [];
  return (
    <div className="split">
      <div className="split-list domain-list">
        <p className="note">
          {tr("One source of truth per project: what you want, the written conventions, the learned decisions, the work in progress.")}
        </p>
        {projects !== null && roots.length === 0 && <EmptyState text={tr("No project yet: start an agent inside a repository.")} />}
        <div className="scroll-area list-stack">
          {roots.map((root) => {
            const count = snapshot.sessions.filter((session) => belongsTo(session.cwd, root)).length;
            return (
              <button key={root} type="button" className={`list-row card project-row ${root === selected ? "is-selected" : ""}`} onClick={() => void select(root)}>
                <AssetIcon name="domain" size={22} />
                <b>{lastPathComponent(root)}</b>
                <small>{count === 1 ? tr("1 session") : trf("%d sessions", count)}</small>
              </button>
            );
          })}
        </div>
      </div>
      <div className="split-divider" />
      {domain ? (
        <div className="split-detail scroll-area padded">
          <div className="stack-18">
            <div className="domain-head">
              <div className="detail-heading">
                <h3 className="domain-name">{domain.name}</h3>
                <code className="path-line">{tildePath(domain.root)}</code>
              </div>
              <div className="domain-agents">
                {(Object.entries(domain.agents) as Array<[Harness, number]>)
                  .sort((left, right) => right[1] - left[1])
                  .map(([harness, count]) => (
                    <span key={harness} className="domain-agent">
                      <HarnessTag harness={harness} />
                      <small>× {count}</small>
                    </span>
                  ))}
              </div>
            </div>
            <div className="stack-8">
              <SectionTitle text={tr("Project intent")} />
              <textarea className="intent-editor card flat" value={intent} onChange={(event) => editIntent(event.target.value)} rows={3} />
              <p className="hint-line">
                {tr("What the project must achieve, for whom, and what matters most. Your agents will read it if you export the model.")}
              </p>
            </div>
            {domain.conflicts.map((conflict) => (
              <p key={conflict} className="conflict">
                {conflict}
              </p>
            ))}
            <FactSection title={tr("Written conventions")} facts={domain.conventions} empty={tr("No written rule for this project.")} />
            <FactSection title={tr("Learned decisions")} facts={domain.decisions} empty={tr("No learned rule yet.")} />
            <FactSection title={tr("Recent work")} facts={domain.activity.slice(0, ACTIVITY_LIMIT)} empty={tr("No recent session.")} />
            <div className="button-row">
              <PixelButton title={showExport ? tr("Hide preview") : tr("Export for the agents")} tone="card" onClick={() => void toggleExport()} />
            </div>
            {showExport && (
              <>
                <SectionTitle text={trf("Exact diff · %@", `${domain.name}/.boss/domain.md`)} />
                <DiffView lines={domain.exportDiff} />
                <div className="button-row">
                  <PixelButton title={tr("Write the file")} tone="success" onClick={() => void writeExport()} />
                </div>
              </>
            )}
          </div>
        </div>
      ) : (
        <EmptyState text={tr("Pick a project.")} />
      )}
    </div>
  );
}

function FactSection({ title, facts, empty }: { title: string; facts: DomainFact[]; empty: string }) {
  return (
    <div className="stack-8">
      <SectionTitle text={title}>
        <CountBadge value={facts.length} />
      </SectionTitle>
      <div className="fact-list card">
        {facts.length === 0 && <p className="fact-empty">{empty}</p>}
        {facts.slice(0, FACT_LIMIT).map((fact, index) => (
          <div key={`${fact.source}-${index}`} className="fact-row">
            <i>▸</i>
            <span>{fact.text}</span>
            <small>{fact.source}</small>
          </div>
        ))}
      </div>
    </div>
  );
}
