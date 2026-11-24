#!/usr/bin/env python3
"""Start auto mode and wait for one firmware-initiated measurement stream."""

from __future__ import annotations

import argparse
import asyncio
import sys

sys.dont_write_bytecode = True

from biomess_ble import connect, parse_points, read_config, start_auto_mode, stop_auto_mode, wait_measurement_stream


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", help="BLE address/identifier. If omitted, scans for BioMess.")
    parser.add_argument("--name-prefix", default="BioMess")
    parser.add_argument("--interval", type=int, default=60)
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    async with await connect(args.address, args.name_prefix) as client:
        config = await read_config(client)
        expected_bytes = int(config["points"]) * int(config["repetitions"]) * 12
        print(f"expected_bytes={expected_bytes}")
        await start_auto_mode(client, args.interval)
        try:
            payload = await wait_measurement_stream(client, expected_bytes=expected_bytes, timeout=args.timeout)
        finally:
            await stop_auto_mode(client)
        points = parse_points(payload)
        print(f"auto_mode_points_received={len(points)}")


if __name__ == "__main__":
    asyncio.run(main())
