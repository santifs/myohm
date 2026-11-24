#!/usr/bin/env python3
"""Generate a deterministic AD5940 sweep CSV fixture for offline analyzer checks."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def frequency_at(start_hz: float, stop_hz: float, index: int, points: int) -> float:
    if points == 1:
        return start_hz
    ratio = index / (points - 1)
    return start_hz * ((stop_hz / start_hz) ** ratio)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=Path("/tmp/biomess_sweep_fixture.csv"))
    parser.add_argument("--points", type=int, default=48)
    parser.add_argument("--repetitions", type=int, default=5)
    parser.add_argument("--start-hz", type=float, default=4000.0)
    parser.add_argument("--stop-hz", type=float, default=198000.0)
    parser.add_argument("--ohms", type=float, default=10000.0)
    parser.add_argument("--phase-deg", type=float, default=0.0)
    parser.add_argument("--magnitude-ripple-pct", type=float, default=0.5)
    parser.add_argument("--phase-ripple-deg", type=float, default=0.25)
    args = parser.parse_args()

    if args.points < 2:
        raise SystemExit("--points must be at least 2")
    if args.repetitions < 1:
        raise SystemExit("--repetitions must be at least 1")
    if args.start_hz <= 0.0 or args.stop_hz <= 0.0 or args.stop_hz <= args.start_hz:
        raise SystemExit("--start-hz and --stop-hz must be positive and increasing")
    if args.ohms <= 0.0:
        raise SystemExit("--ohms must be greater than 0")

    rows = []
    for rep in range(args.repetitions):
        for point in range(args.points):
            freq = frequency_at(args.start_hz, args.stop_hz, point, args.points)
            angle = 2.0 * math.pi * (point / args.points) + rep * 0.17
            magnitude = args.ohms * (1.0 + (args.magnitude_ripple_pct / 100.0) * math.sin(angle))
            phase = args.phase_deg + args.phase_ripple_deg * math.cos(angle)
            rows.append((freq, magnitude, phase))

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["frequency_hz", "magnitude_ohm", "phase_deg"])
        for row in rows:
            writer.writerow([f"{row[0]:.9g}", f"{row[1]:.9g}", f"{row[2]:.9g}"])

    print(f"sweep_fixture_csv={args.csv}")
    print(f"sweep_fixture_rows={len(rows)}")
    print(f"sweep_fixture_repetitions={args.repetitions}")
    print(f"sweep_fixture_points_per_repetition={args.points}")
    print(f"sweep_fixture_expected_ohms={args.ohms:.9g}")
    print("sweep_fixture_ok=true")


if __name__ == "__main__":
    main()
