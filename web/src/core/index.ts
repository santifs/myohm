export interface SweepConfig {
  startHz: number;
  endHz: number;
  points: number;
  repetitions: number;
}

export interface MeasurementPoint {
  frequency: number;
  magnitude: number;
  phase: number;
  resistance: number;
  reactance: number;
  repetition: number;
  index: number;
  valid: boolean;
}

export interface MeasurementRun {
  id: string;
  startedAt: string;
  source: "ble" | "simulation";
  config: SweepConfig;
  points: MeasurementPoint[];
  serial?: string;
  simulationPattern?: "resistor" | "rc";
  rawChunks: number[][];
  timing?: MeasurementTiming;
  name?: string;
  notes?: string;
}

export interface MeasurementTiming {
  configMs?: number;
  firstDataMs?: number;
  receiveMs?: number;
  totalMs: number;
}

export interface FrequencySummary {
  frequency: number;
  count: number;
  validCount: number;
  magnitude: number;
  phase: number;
  resistance: number;
  reactance: number;
  magnitudeSd: number | null;
  phaseSd: number | null;
}

export interface PointFilters {
  repetition?: number | null;
  minHz?: number | null;
  maxHz?: number | null;
  validity?: "all" | "valid" | "invalid";
}

export const HISTORY_STORAGE_KEY = "biomess.history.v1";
export const HISTORY_VERSION = 1;

export const MAX_SWEEP_FREQUENCY_HZ = 198_000;

export const DEFAULT_CONFIG: Readonly<SweepConfig> = Object.freeze({
  startHz: 4_000,
  endHz: MAX_SWEEP_FREQUENCY_HZ,
  points: 48,
  repetitions: 5,
});

export function validateConfig(config: SweepConfig): void {
  if (!Number.isFinite(config.startHz) || config.startHz <= 0) {
    throw new RangeError("startHz must be a positive finite number");
  }
  if (!Number.isFinite(config.endHz) || config.endHz <= config.startHz) {
    throw new RangeError("endHz must be a finite number greater than startHz");
  }
  if (
    !Number.isInteger(config.points) ||
    config.points < 2 ||
    config.points > 100
  ) {
    throw new RangeError("points must be an integer from 2 to 100");
  }
  if (
    !Number.isInteger(config.repetitions) ||
    config.repetitions < 1 ||
    config.repetitions > 10
  ) {
    throw new RangeError("repetitions must be an integer from 1 to 10");
  }
}

export function simulateMeasurement(
  config: SweepConfig,
  pattern: "resistor" | "rc",
): MeasurementRun {
  validateConfig(config);
  const points: MeasurementPoint[] = [];
  const ratio = config.endHz / config.startHz;

  for (let repetition = 0; repetition < config.repetitions; repetition += 1) {
    for (let index = 0; index < config.points; index += 1) {
      const frequency = config.startHz * ratio ** (index / (config.points - 1));
      const repetitionScale =
        1 + (repetition - (config.repetitions - 1) / 2) * 0.004;
      let resistance: number;
      let reactance: number;
      if (pattern === "resistor") {
        resistance = 1_000 * repetitionScale;
        reactance = 0;
      } else {
        const seriesResistance = 100;
        const parallelResistance = 400;
        const capacitance = 10e-9;
        const omegaRc =
          2 * Math.PI * frequency * parallelResistance * capacitance;
        resistance =
          (seriesResistance + parallelResistance / (1 + omegaRc ** 2)) *
          repetitionScale;
        reactance =
          ((-parallelResistance * omegaRc) / (1 + omegaRc ** 2)) *
          repetitionScale;
      }
      const magnitude = Math.hypot(resistance, reactance);
      const phase = (Math.atan2(reactance, resistance) * 180) / Math.PI;
      points.push({
        frequency,
        magnitude,
        phase,
        resistance,
        reactance,
        repetition,
        index,
        valid: true,
      });
    }
  }

  return {
    id: globalThis.crypto?.randomUUID?.() ?? `sim-${Date.now()}`,
    startedAt: new Date().toISOString(),
    source: "simulation",
    config: { ...config },
    points,
    simulationPattern: pattern,
    rawChunks: [],
  };
}

export function summarize(points: MeasurementPoint[]): {
  validCount: number;
  invalidCount: number;
  maxCvPercent: number | null;
} {
  const valid = points.filter(
    (point) => point.valid && Number.isFinite(point.magnitude),
  );
  const groups = new Map<number, number[]>();
  for (const point of valid) {
    const values = groups.get(point.frequency) ?? [];
    values.push(point.magnitude);
    groups.set(point.frequency, values);
  }

  let maxCvPercent: number | null = null;
  for (const values of groups.values()) {
    if (values.length < 2) continue;
    const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
    if (mean === 0) continue;
    const variance =
      values.reduce((sum, value) => sum + (value - mean) ** 2, 0) /
      (values.length - 1);
    const cv = (Math.sqrt(variance) / Math.abs(mean)) * 100;
    maxCvPercent = maxCvPercent === null ? cv : Math.max(maxCvPercent, cv);
  }

  return {
    validCount: valid.length,
    invalidCount: points.length - valid.length,
    maxCvPercent,
  };
}

function mean(values: number[]): number {
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function sampleSd(values: number[]): number | null {
  if (values.length < 2) return null;
  const average = mean(values);
  return Math.sqrt(
    values.reduce((sum, value) => sum + (value - average) ** 2, 0) /
      (values.length - 1),
  );
}

export function summarizeByFrequency(points: MeasurementPoint[]): FrequencySummary[] {
  const groups = new Map<number, MeasurementPoint[]>();
  for (const point of points) {
    const group = groups.get(point.frequency) ?? [];
    group.push(point);
    groups.set(point.frequency, group);
  }
  return [...groups.entries()]
    .sort(([a], [b]) => a - b)
    .map(([frequency, group]) => {
      const valid = group.filter((point) =>
        point.valid && [point.magnitude, point.phase, point.resistance, point.reactance]
          .every(Number.isFinite),
      );
      const values = (key: keyof MeasurementPoint) =>
        valid.map((point) => point[key] as number);
      return {
        frequency,
        count: group.length,
        validCount: valid.length,
        magnitude: valid.length ? mean(values("magnitude")) : Number.NaN,
        phase: valid.length ? mean(values("phase")) : Number.NaN,
        resistance: valid.length ? mean(values("resistance")) : Number.NaN,
        reactance: valid.length ? mean(values("reactance")) : Number.NaN,
        magnitudeSd: sampleSd(values("magnitude")),
        phaseSd: sampleSd(values("phase")),
      };
    });
}

export function filterPoints(points: MeasurementPoint[], filters: PointFilters): MeasurementPoint[] {
  return points.filter((point) =>
    (filters.repetition == null || point.repetition === filters.repetition) &&
    (filters.minHz == null || point.frequency >= filters.minHz) &&
    (filters.maxHz == null || point.frequency <= filters.maxHz) &&
    (filters.validity === undefined || filters.validity === "all" ||
      (filters.validity === "valid" ? point.valid : !point.valid)),
  );
}

function csvCell(value: string | number | boolean): string {
  // Device-provided identifiers are untrusted spreadsheet input. Preserve raw
  // identifiers in JSON while preventing formula interpretation in CSV readers.
  const raw = String(value);
  const text = typeof value === "string" && /^[\s]*[=+@-]|^[\t\r\n]/.test(raw)
    ? `'${raw}` : raw;
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

export function exportCsv(run: MeasurementRun, points = run.points): string {
  const header = [
    "run_id",
    "started_at",
    "source",
    "simulation_pattern",
    "serial",
    "frequency_hz",
    "magnitude_ohm",
    "phase_deg",
    "resistance_ohm",
    "reactance_ohm",
    "repetition",
    "index",
    "valid",
  ];
  const rows = points.map((point) =>
    [
      run.id,
      run.startedAt,
      run.source,
      run.simulationPattern ?? "",
      run.serial ?? "",
      point.frequency,
      point.magnitude,
      point.phase,
      point.resistance,
      point.reactance,
      point.repetition,
      point.index,
      point.valid,
    ]
      .map(csvCell)
      .join(","),
  );
  return `${header.join(",")}\n${rows.join("\n")}\n`;
}

export function exportJson(run: MeasurementRun): string {
  return JSON.stringify(run, null, 2);
}

export function exportFilteredJson(run: MeasurementRun, points: MeasurementPoint[]): string {
  return JSON.stringify({ ...run, points, rawChunks: [] }, null, 2);
}

interface StoredHistory { version: number; runs: MeasurementRun[] }

export function loadHistory(storage: Pick<Storage, "getItem">): MeasurementRun[] {
  try {
    const raw = storage.getItem(HISTORY_STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as Partial<StoredHistory>;
    if (parsed.version !== HISTORY_VERSION || !Array.isArray(parsed.runs)) return [];
    return parsed.runs.filter((run): run is MeasurementRun =>
      Boolean(run && typeof run.id === "string" && Array.isArray(run.points) && run.config),
    );
  } catch {
    return [];
  }
}

export function saveHistory(storage: Pick<Storage, "setItem">, runs: MeasurementRun[]): boolean {
  try {
    storage.setItem(HISTORY_STORAGE_KEY, JSON.stringify({ version: HISTORY_VERSION, runs }));
    return true;
  } catch {
    return false;
  }
}
