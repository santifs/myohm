#!/usr/bin/env python3
"""Run an AD5940 sweep through the same BLE streaming path used by Android/iOS."""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from biomess_ble import configure_sweep, connect, parse_points, run_measurement, write_csv


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address")
    parser.add_argument("--name-prefix", default="BioMess")
    parser.add_argument("--points", type=int, default=None)
    parser.add_argument("--start-hz", type=float, default=None)
    parser.add_argument("--stop-hz", type=float, default=None)
    parser.add_argument("--repetitions", type=int, default=None)
    parser.add_argument("--timeout", type=float, default=45.0)
    parser.add_argument("--csv", type=Path, default=Path("sweep.csv"))
    args = parser.parse_args()

    async with await connect(args.address, args.name_prefix) as client:
        config = await configure_sweep(
            client,
            points=args.points,
            start_hz=args.start_hz,
            stop_hz=args.stop_hz,
            repetitions=args.repetitions,
        )
        expected_points = int(config["points"]) * int(config["repetitions"])
        expected_bytes = expected_points * 12
        print(f"expected_points={expected_points}")
        print(f"expected_bytes={expected_bytes}")

        payload = await run_measurement(client, expected_bytes, timeout=args.timeout)
        points = parse_points(payload)
        write_csv(points, args.csv)

        print(f"received_points={len(points)}")
        print(f"csv={args.csv}")
        if len(points) != expected_points:
            raise SystemExit(f"Expected {expected_points} points, got {len(points)}")
        if any(point.frequency <= 0 for point in points):
            raise SystemExit("At least one point has non-positive frequency")


if __name__ == "__main__":
    asyncio.run(main())
