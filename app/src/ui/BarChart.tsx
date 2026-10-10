import type { CSSProperties } from "react";

export type BarSegment = { value: number; color: string; label: string };
export type BarDatum = { key: string; label: string; segments: BarSegment[] };
export type LegendItem = { label: string; color: string };

function niceScale(max: number, targetTicks: number): { top: number; ticks: number[] } {
  if (max <= 0) return { top: 1, ticks: [0, 1] };
  const raw = max / targetTicks;
  const magnitude = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 2.5, 5, 10].map((factor) => factor * magnitude).find((candidate) => candidate >= raw) ?? 10 * magnitude;
  const top = Math.ceil(max / step) * step;
  const ticks: number[] = [];
  for (let value = 0; value <= top + step / 1000; value += step) ticks.push(Number(value.toFixed(6)));
  return { top, ticks };
}

export function BarChart({
  data,
  height,
  labelEvery,
  formatValue,
  legend,
  legendShape = "square",
}: {
  data: BarDatum[];
  height: number;
  labelEvery: number;
  formatValue: (value: number) => string;
  legend?: LegendItem[];
  legendShape?: "square" | "circle";
}) {
  const max = Math.max(0, ...data.map((datum) => datum.segments.reduce((sum, segment) => sum + segment.value, 0)));
  const { top, ticks } = niceScale(max, 3);
  const columns = { gridTemplateColumns: `repeat(${Math.max(data.length, 1)}, minmax(0, 1fr))` } as CSSProperties;
  return (
    <div className="bar-chart card">
      <div className="chart-body">
        <div className="chart-plot" style={{ height }}>
          {ticks.map((tick) => (
            <i key={tick} className="chart-gridline" style={{ bottom: `${(tick / top) * 100}%` }} />
          ))}
          <div className="chart-bars" style={columns}>
            {data.map((datum) => {
              const total = datum.segments.reduce((sum, segment) => sum + segment.value, 0);
              const tooltip = [datum.label, ...datum.segments.filter((segment) => segment.value > 0).map((segment) => `${segment.label}: ${formatValue(segment.value)}`)].join("\n");
              return (
                <div key={datum.key} className="chart-bar" title={tooltip}>
                  <div className="chart-stack" style={{ height: `${(total / top) * 100}%` }}>
                    {datum.segments.map((segment) =>
                      segment.value > 0 ? (
                        <span key={segment.label} style={{ flexGrow: segment.value, background: segment.color }} />
                      ) : null,
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
        <div className="chart-axis" style={{ height }}>
          {ticks.map((tick) => (
            <span key={tick} style={{ bottom: `${(tick / top) * 100}%` }}>
              {formatValue(tick)}
            </span>
          ))}
        </div>
      </div>
      <div className="chart-labels" style={columns}>
        {data.map((datum, index) => (
          <span key={datum.key}>{index % labelEvery === 0 ? datum.label : ""}</span>
        ))}
      </div>
      {legend && (
        <div className={`chart-legend legend-${legendShape}`}>
          {legend.map((item) => (
            <span key={item.label}>
              <i style={{ background: item.color }} />
              {item.label}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}
