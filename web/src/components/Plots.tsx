import { useMemo } from "react";
import type { MeasurementPoint, MeasurementRun } from "../core";
const fmt = (n: number) => n >= 1000 ? `${Number((n / 1000).toPrecision(3))}k` : Number(n.toPrecision(3)).toString();
const colors = ["#008d8d", "#cf6a32"];
const box = { left: 62, right: 414, top: 22, bottom: 220 }, width = box.right - box.left, height = box.bottom - box.top;
const fractions = [0, .25, .5, .75, 1];
export function logTicks(min: number, max: number): number[] { const ticks: number[] = []; for (let e = Math.floor(Math.log10(min)); e <= Math.ceil(Math.log10(max)); e += 1) for (const f of [1, 2, 5]) { const v = f * 10 ** e; if (v >= min && v <= max) ticks.push(v); } return ticks; }
function extent(values: number[], zero = false): [number, number] { let min = Math.min(...values), max = Math.max(...values); if (zero) { min = Math.min(0, min); max = Math.max(0, max); } const p = Math.max((max - min) * .07, Math.abs(max || 1) * .02, 1e-6); return [min - p, max + p]; }
function path(points: MeasurementPoint[], x: (p: MeasurementPoint) => number, y: (p: MeasurementPoint) => number) { return points.map((p, i) => `${i ? "L" : "M"}${x(p).toFixed(2)},${y(p).toFixed(2)}`).join(" "); }
type Series = { run: MeasurementRun; runIndex: number; repetition: number; points: MeasurementPoint[] };
function BodePanel({ series, field, title, unit, minF, maxF }: { series: Series[]; field: "magnitude" | "phase"; title: string; unit: string; minF: number; maxF: number }) {
  const values = series.flatMap((s) => s.points.map((p) => p[field])), [minY, maxY] = extent(values, field === "phase");
  const logMin = Math.log10(minF), logSpan = Math.log10(maxF) - logMin || 1;
  const x = (p: MeasurementPoint) => box.left + ((Math.log10(p.frequency) - logMin) / logSpan) * width;
  const y = (p: MeasurementPoint) => box.bottom - ((p[field] - minY) / (maxY - minY || 1)) * height;
  return <section className="plot-panel"><h3>{title}</h3><svg viewBox="0 0 440 268" role="img" aria-label={`${title} por frecuencia, eje logarítmico`}>
    {fractions.map((f) => <g key={f}><path className="gridline" d={`M${box.left} ${box.bottom - f * height}H${box.right}`} /><text x={box.left - 8} y={box.bottom - f * height + 4} textAnchor="end">{fmt(minY + f * (maxY - minY))}</text></g>)}
    {logTicks(minF, maxF).map((tick) => { const px = box.left + ((Math.log10(tick) - logMin) / logSpan) * width; return <g key={tick}><path className="gridline" d={`M${px} ${box.top}V${box.bottom}`} /><text x={px} y="239" textAnchor="middle">{fmt(tick)}</text></g>; })}
    {series.map((s) => <g key={`${s.run.id}-${s.repetition}`} opacity={s.repetition ? .35 : 1}><path className="data-line" stroke={colors[s.runIndex]} d={path(s.points, x, y)} />{s.points.map((p) => <circle key={p.index} className="plot-point" fill={colors[s.runIndex]} cx={x(p)} cy={y(p)} r="2.5"><title>{`${fmt(p.frequency)} Hz · ${fmt(p[field])} ${unit} · rep. ${p.repetition + 1}`}</title></circle>)}</g>)}
    <text x={(box.left + box.right) / 2} y="261" textAnchor="middle">Frecuencia (Hz) · log</text><text x="13" y="121" transform="rotate(-90 13 121)" textAnchor="middle">{unit}</text>
  </svg></section>;
}
export default function Plots({ runs }: { runs: MeasurementRun[] }) {
  const series = useMemo(() => runs.slice(0, 2).flatMap((run, runIndex) => { const reps = new Map<number, MeasurementPoint[]>(); for (const p of run.points) if (p.valid) { const list = reps.get(p.repetition) ?? []; list.push(p); reps.set(p.repetition, list); } return [...reps.entries()].map(([repetition, points]) => ({ run, runIndex, repetition, points })); }), [runs]);
  const all = series.flatMap((s) => s.points); if (!all.length) return <div className="plot-empty"><strong>Tu próxima medición empieza aquí</strong><p>Conecta una PCB o activa el modo simulado.<br />Verás módulo, fase y Nyquist.</p></div>;
  const rawMinF = Math.min(...all.map((p) => p.frequency)), rawMaxF = Math.max(...all.map((p) => p.frequency)); const minF = 10 ** Math.floor(Math.log10(rawMinF)), maxF = 10 ** Math.ceil(Math.log10(rawMaxF));
  const [rawMinR, rawMaxR] = extent(all.map((p) => p.resistance), true), [rawMinX, rawMaxX] = extent(all.map((p) => -p.reactance), true); const scale = Math.min(width / (rawMaxR - rawMinR), height / (rawMaxX - rawMinX)); const visibleR = width / scale, visibleX = height / scale, minR = (rawMinR + rawMaxR - visibleR) / 2, minX = (rawMinX + rawMaxX - visibleX) / 2;
  const nx = (p: MeasurementPoint) => box.left + (p.resistance - minR) * scale, ny = (p: MeasurementPoint) => box.bottom - (-p.reactance - minX) * scale;
  return <><div className="plot-legend">{runs.slice(0, 2).map((run, i) => <span key={run.id} style={{ color: colors[i] }}>● {run.name || `Medición ${i + 1}`}</span>)}</div><div className="bode-plots"><BodePanel series={series} field="magnitude" title="Módulo" unit="|Z| (Ω)" minF={minF} maxF={maxF} /><BodePanel series={series} field="phase" title="Fase" unit="Fase (°)" minF={minF} maxF={maxF} /></div>
    <section className="plot-panel nyquist"><h3>Diagrama de Nyquist</h3><div className="legend">Una curva por repetición · misma escala px/Ω</div><svg viewBox="0 0 440 268" role="img" aria-label="Nyquist con igual escala en ambos ejes">{fractions.map((f) => <g key={f}><path className="gridline" d={`M${box.left} ${box.bottom - f * height}H${box.right} M${box.left + f * width} ${box.top}V${box.bottom}`} /><text x={box.left - 8} y={box.bottom - f * height + 4} textAnchor="end">{fmt(minX + f * visibleX)}</text><text x={box.left + f * width} y="239" textAnchor="middle">{fmt(minR + f * visibleR)}</text></g>)}{series.map((s) => <g key={`${s.run.id}-${s.repetition}`} opacity={s.repetition ? .4 : 1}><path className="data-line" stroke={colors[s.runIndex]} d={path(s.points, nx, ny)} />{s.points.map((p) => <circle key={p.index} className="plot-point" fill={colors[s.runIndex]} cx={nx(p)} cy={ny(p)} r={Math.abs(p.reactance) < 1e-9 ? 3.2 : 2.5}><title>{`${fmt(p.frequency)} Hz · R ${fmt(p.resistance)} Ω · X ${fmt(p.reactance)} Ω · rep. ${p.repetition + 1}`}</title></circle>)}</g>)}<text x="238" y="261" textAnchor="middle">R (Ω)</text><text x="13" y="121" transform="rotate(-90 13 121)" textAnchor="middle">−X (Ω)</text></svg></section>
  </>;
}
