#!/usr/bin/env python3
"""Validate and summarize an AD5940 sweep CSV captured over BLE."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from statistics import median


REQUIRED_COLUMNS = ("frequency_hz", "magnitude_ohm", "phase_deg")


def read_rows(path: Path) -> list[tuple[float, float, float]]:
    with path.open(newline="") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames is None:
            raise ValueError("CSV is missing a header row")
        missing = [column for column in REQUIRED_COLUMNS if column not in reader.fieldnames]
        if missing:
            raise ValueError("CSV is missing required columns: " + ", ".join(missing))

        rows = []
        for line_number, row in enumerate(reader, start=2):
            try:
                point = tuple(float(row[column]) for column in REQUIRED_COLUMNS)
            except (TypeError, ValueError) as exc:
                raise ValueError(f"Invalid numeric value on line {line_number}: {exc}") from exc
            if not all(math.isfinite(value) for value in point):
                raise ValueError(f"Non-finite value on line {line_number}")
            rows.append(point)
    return rows


def split_repetitions(
    rows: list[tuple[float, float, float]],
    points_per_repetition: int | None,
) -> list[list[tuple[float, float, float]]]:
    if points_per_repetition is not None:
        if points_per_repetition <= 0:
            raise ValueError("--points must be greater than 0")
        if len(rows) % points_per_repetition != 0:
            raise ValueError(f"{len(rows)} rows is not a multiple of --points {points_per_repetition}")
        return [rows[i : i + points_per_repetition] for i in range(0, len(rows), points_per_repetition)]

    groups: list[list[tuple[float, float, float]]] = []
    current: list[tuple[float, float, float]] = []
    previous_freq: float | None = None
    for row in rows:
        freq = row[0]
        if previous_freq is not None and freq < previous_freq:
            groups.append(current)
            current = []
        current.append(row)
        previous_freq = freq
    if current:
        groups.append(current)
    return groups


def validate_groups(groups: list[list[tuple[float, float, float]]]) -> None:
    if not groups:
        raise ValueError("CSV has no data rows")
    expected_len = len(groups[0])
    for rep_index, group in enumerate(groups, start=1):
        if not group:
            raise ValueError(f"Repetition {rep_index} is empty")
        if len(group) != expected_len:
            raise ValueError(f"Repetition {rep_index} has {len(group)} points; expected {expected_len}")
        frequencies = [row[0] for row in group]
        magnitudes = [row[1] for row in group]
        if any(freq <= 0.0 for freq in frequencies):
            raise ValueError(f"Repetition {rep_index} contains non-positive frequency")
        if any(mag <= 0.0 for mag in magnitudes):
            raise ValueError(f"Repetition {rep_index} contains non-positive magnitude")
        if any(b < a for a, b in zip(frequencies, frequencies[1:])):
            raise ValueError(f"Repetition {rep_index} frequencies are not monotonically increasing")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path)
    parser.add_argument("--points", type=int, help="Expected points per repetition. If omitted, frequency resets split repetitions.")
    parser.add_argument("--expected-ohms", type=float, help="Known resistor/phantom magnitude for analog validation.")
    parser.add_argument("--magnitude-tolerance-pct", type=float, default=20.0)
    parser.add_argument("--max-abs-phase-deg", type=float, help="Maximum median absolute phase when using a resistive load.")
    args = parser.parse_args()

    if not args.csv.exists():
        raise SystemExit(f"CSV does not exist: {args.csv}")

    try:
        rows = read_rows(args.csv)
        groups = split_repetitions(rows, args.points)
        validate_groups(groups)
    except ValueError as exc:
        print("sweep_csv_ok=false")
        raise SystemExit(str(exc)) from exc

    frequencies = [row[0] for row in rows]
    magnitudes = [row[1] for row in rows]
    phases = [row[2] for row in rows]
    median_magnitude = median(magnitudes)
    median_phase = median(phases)
    median_abs_phase = median(abs(phase) for phase in phases)

    print(f"sweep_csv={args.csv}")
    print(f"sweep_rows={len(rows)}")
    print(f"sweep_repetitions={len(groups)}")
    print(f"sweep_points_per_repetition={len(groups[0])}")
    print(f"sweep_start_hz={min(frequencies):.6g}")
    print(f"sweep_stop_hz={max(frequencies):.6g}")
    print(f"median_magnitude_ohm={median_magnitude:.6g}")
    print(f"median_phase_deg={median_phase:.6g}")
    print(f"median_abs_phase_deg={median_abs_phase:.6g}")

    if args.expected_ohms is not None:
        if args.expected_ohms <= 0.0:
            raise SystemExit("--expected-ohms must be greater than 0")
        error_pct = abs(median_magnitude - args.expected_ohms) / args.expected_ohms * 100.0
        print(f"expected_ohms={args.expected_ohms:.6g}")
        print(f"median_magnitude_error_pct={error_pct:.6g}")
        if error_pct > args.magnitude_tolerance_pct:
            print("sweep_csv_ok=false")
            raise SystemExit(
                f"Median magnitude error {error_pct:.2f}% exceeds tolerance {args.magnitude_tolerance_pct:.2f}%"
            )
        if args.max_abs_phase_deg is not None and median_abs_phase > args.max_abs_phase_deg:
            print("sweep_csv_ok=false")
            raise SystemExit(
                f"Median absolute phase {median_abs_phase:.2f} deg exceeds limit {args.max_abs_phase_deg:.2f} deg"
            )

    print("sweep_csv_ok=true")


if __name__ == "__main__":
    main()
