#!/usr/bin/env python3
"""Scan/connect and print BioMess BLE services plus basic configuration."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from biomess_ble import (
    connect,
    find_device_advertisement,
    read_config,
    service_contract_from_bleak,
    validate_gatt_contract,
)


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", help="BLE address/identifier. If omitted, scans for BioMess.")
    parser.add_argument("--name-prefix", default="BioMess")
    parser.add_argument("--expected-name", default="BioMess", help="Require this exact advertised name when scanning.")
    parser.add_argument("--no-name-validate", action="store_true", help="Do not require the expected advertised name.")
    parser.add_argument("--no-validate", action="store_true", help="Only print discovered services; do not require the BioMess app GATT contract.")
    parser.add_argument("--summary-json", type=Path, help="Write discovered GATT/config summary as JSON.")
    args = parser.parse_args()

    discovered_name = None
    target = args.address
    name_failures: list[str] = []
    if target is None:
        device, discovered_name = await find_device_advertisement(name_prefix=args.name_prefix)
        target = device
        if not args.no_name_validate and discovered_name != args.expected_name:
            name_failures.append(f"advertised name expected '{args.expected_name}', found '{discovered_name}'")

    async with await connect(target, args.name_prefix) as client:
        print(f"connected: {client.address}")
        if discovered_name is not None:
            print(f"advertised_name={discovered_name}")
        print(f"advertised_name_validation_enabled={str(not args.no_name_validate and args.address is None).lower()}")
        print(f"advertised_name_validation_failures={len(name_failures)}")
        for failure in name_failures:
            print(f"advertised_name_failure={failure}")
        print(f"advertised_name_validation_ok={str(not name_failures).lower()}")
        services = service_contract_from_bleak(client.services)
        for service in client.services:
            print(f"[service] {service.uuid}")
            for characteristic in service.characteristics:
                print(f"  [char] {characteristic.uuid} props={','.join(characteristic.properties)}")

        failures = [] if args.no_validate else validate_gatt_contract(services)
        validation_failures = [*name_failures, *failures]
        print(f"\ngatt_services={len(services)}")
        print(f"gatt_characteristics={sum(len(chars) for chars in services.values())}")
        print(f"gatt_validation_enabled={str(not args.no_validate).lower()}")
        print(f"gatt_validation_failures={len(failures)}")
        for failure in failures:
            print(f"gatt_contract_failure={failure}")
        print(f"gatt_validation_ok={str(not failures).lower()}")
        if validation_failures:
            if args.summary_json:
                args.summary_json.parent.mkdir(parents=True, exist_ok=True)
                args.summary_json.write_text(
                    json.dumps(
                        {
                            "ok": False,
                            "address": str(client.address),
                            "advertised_name": discovered_name,
                            "advertised_name_expected": args.expected_name,
                            "advertised_name_validation_enabled": not args.no_name_validate and args.address is None,
                            "advertised_name_validation_failures": name_failures,
                            "validation_enabled": not args.no_validate,
                            "validation_failures": validation_failures,
                            "services": {
                                service_uuid: {
                                    char_uuid: sorted(props)
                                    for char_uuid, props in characteristics.items()
                                }
                                for service_uuid, characteristics in services.items()
                            },
                            "config": None,
                        },
                        indent=2,
                        sort_keys=True,
                    )
                    + "\n",
                    encoding="utf-8",
                )
                print(f"summary_json={args.summary_json}")
            raise SystemExit("BioMess BLE validation failed")

        print("\nconfiguration:")
        config = await read_config(client)
        for key, value in config.items():
            print(f"  {key}: {value}")
        if args.summary_json:
            args.summary_json.parent.mkdir(parents=True, exist_ok=True)
            args.summary_json.write_text(
                json.dumps(
                        {
                            "ok": not failures,
                            "address": str(client.address),
                            "advertised_name": discovered_name,
                            "advertised_name_expected": args.expected_name,
                            "advertised_name_validation_enabled": not args.no_name_validate and args.address is None,
                            "advertised_name_validation_failures": name_failures,
                            "validation_enabled": not args.no_validate,
                            "validation_failures": failures,
                            "services": {
                            service_uuid: {
                                char_uuid: sorted(props)
                                for char_uuid, props in characteristics.items()
                            }
                            for service_uuid, characteristics in services.items()
                        },
                        "config": config,
                    },
                    indent=2,
                    sort_keys=True,
                )
                + "\n",
                encoding="utf-8",
            )
            print(f"summary_json={args.summary_json}")
        print("ble_probe_ok=true")


if __name__ == "__main__":
    asyncio.run(main())
