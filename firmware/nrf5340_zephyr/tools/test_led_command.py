#!/usr/bin/env python3
"""Send the firmware LED blink command (0x64) as a quick write-path test."""

from __future__ import annotations

import argparse
import asyncio
import sys

sys.dont_write_bytecode = True

from biomess_ble import CMD_LED_BLINK, CONTROL_COMMAND, connect


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address")
    parser.add_argument("--name-prefix", default="BioMess")
    args = parser.parse_args()

    async with await connect(args.address, args.name_prefix) as client:
        await client.write_gatt_char(CONTROL_COMMAND, bytes([CMD_LED_BLINK]), response=True)
        print("led_blink_command_sent=true")


if __name__ == "__main__":
    asyncio.run(main())
