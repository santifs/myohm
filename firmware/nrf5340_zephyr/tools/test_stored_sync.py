#!/usr/bin/env python3
"""Validate stored-measurement sync over the 0xC000 BLE command channel."""

from __future__ import annotations

import argparse
import asyncio
import sys

sys.dont_write_bytecode = True

from biomess_ble import (
    clear_stored,
    connect,
    get_stored_count,
    read_stored_batch,
)


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", help="BLE address/identifier. If omitted, scans for BioMess.")
    parser.add_argument("--name-prefix", default="BioMess")
    parser.add_argument("--offset", type=int, default=0)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--clear", action="store_true", help="Clear stored measurements before reading count.")
    args = parser.parse_args()

    async with await connect(args.address, args.name_prefix) as client:
        if args.clear:
            remaining = await clear_stored(client)
            print(f"stored_count_after_clear={remaining}")

        available = await get_stored_count(client)
        print(f"stored_count={available}")

        if available == 0:
            print("stored_batch_skipped=true")
            return

        if args.offset >= available:
            print("stored_batch_skipped=true")
            print(f"reason=offset {args.offset} is outside available range 0..{available - 1}")
            return

        read_count = min(args.count, available - args.offset)
        if read_count <= 0:
            print("stored_batch_skipped=true")
            print("reason=requested count resolves to zero")
            return

        records = await read_stored_batch(client, offset=args.offset, count=read_count)
        print(f"stored_records_received={len(records)}")
        for index, record in enumerate(records):
            print(
                "record_{idx}=session:{session} seq:{seq} reps:{reps} battery:{battery} crc:{crc}".format(
                    idx=index,
                    session=record.session_id,
                    seq=record.sequence_number,
                    reps=record.num_repetitions,
                    battery=record.battery_percentage,
                    crc="ok" if record.crc16_valid else "bad",
                )
            )
        if not all(record.crc16_valid for record in records):
            raise SystemExit("At least one stored measurement CRC is invalid")


if __name__ == "__main__":
    asyncio.run(main())
