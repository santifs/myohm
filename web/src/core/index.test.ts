import { describe, expect, it } from "vitest";
import {
  DEFAULT_CONFIG,
  exportCsv,
  exportJson,
  exportFilteredJson,
  filterPoints,
  loadHistory,
  saveHistory,
  simulateMeasurement,
  summarize,
  summarizeByFrequency,
  validateConfig,
  type MeasurementPoint,
} from "./index";

describe("core measurement model", () => {
  it("accepts firmware boundaries and rejects invalid values", () => {
    expect(() =>
      validateConfig({ startHz: 1, endHz: 2, points: 2, repetitions: 1 }),
    ).not.toThrow();
    expect(() =>
      validateConfig({ startHz: 1, endHz: 2, points: 100, repetitions: 10 }),
    ).not.toThrow();
    for (const config of [
      { startHz: 0, endHz: 2, points: 2, repetitions: 1 },
      { startHz: 2, endHz: 2, points: 2, repetitions: 1 },
      { startHz: 1, endHz: 2, points: 1, repetitions: 1 },
      { startHz: 1, endHz: 2, points: 101, repetitions: 1 },
      { startHz: 1, endHz: 2, points: 2.5, repetitions: 1 },
      { startHz: 1, endHz: 2, points: 2, repetitions: 0 },
      { startHz: 1, endHz: 2, points: 2, repetitions: Number.NaN },
    ])
      expect(() => validateConfig(config)).toThrow();
  });

  it("simulates deterministically in repetition-major order with signed phase", () => {
    const first = simulateMeasurement(
      { ...DEFAULT_CONFIG, points: 3, repetitions: 2 },
      "rc",
    );
    const second = simulateMeasurement(
      { ...DEFAULT_CONFIG, points: 3, repetitions: 2 },
      "rc",
    );
    expect(first.points).toEqual(second.points);
    expect(first.source).toBe("simulation");
    expect(
      first.points.map(({ repetition, index }) => [repetition, index]),
    ).toEqual([
      [0, 0],
      [0, 1],
      [0, 2],
      [1, 0],
      [1, 1],
      [1, 2],
    ]);
    expect(first.points[0].phase).toBeLessThan(0);
    expect(first.points[0].reactance).toBeLessThan(0);
  });

  it("reports validity and maximum sample CV grouped by actual frequency", () => {
    const point = (
      index: number,
      repetition: number,
      magnitude: number,
      valid = true,
    ): MeasurementPoint => ({
      frequency: 100 + index,
      magnitude,
      phase: 0,
      resistance: magnitude,
      reactance: 0,
      index,
      repetition,
      valid,
    });
    expect(
      summarize([
        point(0, 0, 10),
        point(1, 0, 20),
        point(0, 1, 12),
        point(1, 1, 20),
        point(1, 2, 999, false),
      ]),
    ).toEqual({
      validCount: 4,
      invalidCount: 1,
      maxCvPercent: (Math.sqrt(2) / 11) * 100,
    });
    expect(summarize([point(0, 0, 10)])).toEqual({
      validCount: 1,
      invalidCount: 0,
      maxCvPercent: null,
    });
  });

  it("neutralizes spreadsheet formulas in device identifiers without changing raw JSON or numeric phase", () => {
    const run = simulateMeasurement({ ...DEFAULT_CONFIG, points: 2, repetitions: 1 }, "rc");
    for (const serial of ["=1+1", "+1+1", "-1+1", "@SUM(1)", "  =1+1", "\t=1+1"]) {
      const record = { ...run, serial };
      expect(exportCsv(record)).toContain(`,'${serial},`);
      expect(JSON.parse(exportJson(record)).serial).toBe(serial);
    }
    expect(exportCsv({ ...run, serial: "board-01" })).toContain(",board-01,");
    expect(exportCsv(run)).toContain(`,${run.points[0].phase},`);
  });

  it("exports portable CSV and lossless JSON", () => {
    const run = simulateMeasurement(
      { startHz: 10, endHz: 100, points: 2, repetitions: 1 },
      "resistor",
    );
    expect(exportCsv(run)).toMatch(
      /^run_id,started_at,source,simulation_pattern,serial,frequency_hz,magnitude_ohm,phase_deg,resistance_ohm,reactance_ohm,repetition,index,valid\n/,
    );
    expect(exportCsv(run)).toContain(",simulation,resistor,,");
    expect(exportCsv(run).trim().split("\n")).toHaveLength(3);
    expect(JSON.parse(exportJson(run))).toEqual(run);
  });

  it("builds one statistical row per frequency and filters raw rows", () => {
    const run = simulateMeasurement({ startHz: 10, endHz: 100, points: 2, repetitions: 3 }, "resistor");
    const rows = summarizeByFrequency(run.points);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ frequency: 10, count: 3, validCount: 3 });
    expect(rows[0].magnitudeSd).toBeGreaterThan(0);
    const filtered = filterPoints(run.points, { repetition: 1, minHz: 50, validity: "valid" });
    expect(filtered).toHaveLength(1);
    expect(filtered[0]).toMatchObject({ repetition: 1, index: 1 });
    expect(exportCsv(run, filtered).trim().split("\n")).toHaveLength(2);
    expect(JSON.parse(exportFilteredJson(run, filtered)).points).toEqual(filtered);
  });

  it("loads only versioned history and treats quota errors as recoverable", () => {
    const run = simulateMeasurement({ startHz: 10, endHz: 100, points: 2, repetitions: 1 }, "rc");
    let stored = "";
    const storage = { getItem: () => stored || null, setItem: (_key: string, value: string) => { stored = value; } };
    expect(saveHistory(storage, [run])).toBe(true);
    expect(loadHistory(storage)).toEqual([run]);
    stored = JSON.stringify({ version: 999, runs: [run] });
    expect(loadHistory(storage)).toEqual([]);
    expect(saveHistory({ setItem: () => { throw new DOMException("full", "QuotaExceededError"); } }, [run])).toBe(false);
  });
});
