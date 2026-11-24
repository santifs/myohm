#!/usr/bin/env python3
"""Run a quick BLE health check covering PMIC battery read and AD5940 identity."""

from __future__ import annotations

import argparse
import asyncio
import sys

sys.dont_write_bytecode = True

from biomess_ble import connect, read_board_health


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address")
    parser.add_argument("--name-prefix", default="BioMess")
    args = parser.parse_args()

    async with await connect(args.address, args.name_prefix) as client:
        health = await read_board_health(client)

    print(f"health_flags=0x{health.flags:04x}")
    print(f"pmic_ok={str(health.pmic_ok).lower()}")
    print(f"battery_voltage_mv={health.battery_voltage_mv}")
    print(f"battery_percentage={health.battery_percentage}")
    print(f"ad5940_adi_id=0x{health.ad5940_adi_id:04x}")
    print(f"ad5940_chip_id=0x{health.ad5940_chip_id:04x}")
    print(f"ad5940_adi_id_ok={str(health.ad5940_adi_id_ok).lower()}")
    print(f"ad5940_chip_id_known={str(health.ad5940_chip_id_known).lower()}")

    if not health.pmic_ok:
        raise SystemExit("PMIC health check failed")
    if health.battery_voltage_mv == 0:
        raise SystemExit("PMIC health check returned 0 mV")
    if not 0 <= health.battery_percentage <= 100:
        raise SystemExit(f"Battery percentage out of range: {health.battery_percentage}")
    if not health.ad5940_adi_id_ok:
        raise SystemExit("AD5940 ADIID check failed")
    if not health.ad5940_chip_id_known:
        raise SystemExit("AD5940 CHIPID part check failed")


if __name__ == "__main__":
    asyncio.run(main())
