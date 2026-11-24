#!/usr/bin/env python3
"""Trigger PMIC battery sampling over BLE and validate the C202 payload."""

from __future__ import annotations

import argparse
import asyncio
import sys

sys.dont_write_bytecode = True

from biomess_ble import connect, read_battery


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address")
    parser.add_argument("--name-prefix", default="BioMess")
    args = parser.parse_args()

    async with await connect(args.address, args.name_prefix) as client:
        voltage_mv, percentage = await read_battery(client)
        print(f"battery_voltage_mv={voltage_mv}")
        print(f"battery_percentage={percentage}")
        if voltage_mv == 0:
            raise SystemExit("PMIC battery read returned 0 mV")
        if not 0 <= percentage <= 100:
            raise SystemExit(f"Battery percentage out of range: {percentage}")


if __name__ == "__main__":
    asyncio.run(main())
