import type { DiffLine } from "../api";
import { tr } from "../i18n";

export function DiffView({ lines }: { lines: DiffLine[] }) {
  return (
    <div className="diff-view card">
      {lines.length === 0 && <p className="diff-empty">{tr("Nothing to change: the file is already up to date.")}</p>}
      {lines.map((line, index) => (
        <div key={index} className={`diff-line diff-${line.kind}`}>
          {line.text || " "}
        </div>
      ))}
    </div>
  );
}
