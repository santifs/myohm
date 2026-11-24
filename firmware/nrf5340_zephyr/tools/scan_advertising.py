#!/usr/bin/env python3
"""Scan BioMess BLE advertising without opening a GATT connection."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

from biomess_ble import CONTROL_SERVICE, BleakScanner, dependency_install_hint


def bytes_hex(payload: bytes) -> str:
    return payload.hex()


def jsonable(value: Any) -> Any:
    if isinstance(value, bytes):
        return bytes_hex(value)
    if isinstance(value, dict):
        return {str(key): jsonable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [jsonable(item) for item in value]
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return str(value)


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--address", help="Only accept advertisements from this BLE address/identifier.")
    parser.add_argument("--name-prefix", default="BioMess")
    parser.add_argument("--expected-name", default="BioMess")
    parser.add_argument("--service-uuid", default=CONTROL_SERVICE)
    parser.add_argument("--no-name-validate", action="store_true")
    parser.add_argument("--no-service-validate", action="store_true")
    parser.add_argument("--summary-json", type=Path)
    args = parser.parse_args()

    if BleakScanner is None:
        raise SystemExit(f"Missing dependency: {dependency_install_hint()}")

    discovered = await BleakScanner.discover(timeout=args.timeout, return_adv=True)
    service_uuid = args.service_uuid.lower()
    name_prefix = args.name_prefix.upper()
    matches: list[dict[str, Any]] = []

    for device, advertisement in discovered.values():
        address = str(device.address)
        if args.address and address.lower() != args.address.lower():
            continue
        local_name = advertisement.local_name or device.name or ""
        service_uuids = [uuid.lower() for uuid in (advertisement.service_uuids or [])]
        has_name = local_name.upper().startswith(name_prefix)
        has_service = service_uuid in service_uuids
        if not has_name and not has_service:
            continue

        matches.append(
            {
                "address": str(device.address),
                "device_name": device.name,
                "local_name": local_name,
                "rssi": getattr(advertisement, "rssi", getattr(device, "rssi", None)),
                "tx_power": getattr(advertisement, "tx_power", None),
                "service_uuids": service_uuids,
                "manufacturer_data": jsonable(getattr(advertisement, "manufacturer_data", {})),
                "service_data": jsonable(getattr(advertisement, "service_data", {})),
                "matched_name_prefix": has_name,
                "advertises_biomess_service": has_service,
            }
        )

    name_failures = []
    service_failures = []
    if not matches:
        target = f"address '{args.address}'" if args.address else f"name prefix '{args.name_prefix}' or service {service_uuid}"
        service_failures.append(f"no advertisement matched {target}")
    else:
        if not args.no_name_validate and not any(match["local_name"] == args.expected_name for match in matches):
            name_failures.append(f"expected exact local_name '{args.expected_name}' in at least one advertisement")
        if not args.no_service_validate and not any(match["advertises_biomess_service"] for match in matches):
            service_failures.append(f"expected advertised service {service_uuid} in at least one advertisement")

    failures = [*name_failures, *service_failures]
    summary = {
        "ok": not failures,
        "scan_timeout_seconds": args.timeout,
        "devices_seen": len(discovered),
        "matches": matches,
        "match_count": len(matches),
        "expected_name": args.expected_name,
        "service_uuid": service_uuid,
        "address_filter": args.address,
        "name_validation_enabled": not args.no_name_validate,
        "service_validation_enabled": not args.no_service_validate,
        "name_validation_failures": name_failures,
        "service_validation_failures": service_failures,
        "validation_failures": failures,
    }

    print(f"advertising_devices_seen={summary['devices_seen']}")
    print(f"advertising_match_count={summary['match_count']}")
    for match in matches:
        print(
            "advertising_match="
            f"address={match['address']} "
            f"local_name={match['local_name']} "
            f"rssi={match['rssi']} "
            f"advertises_biomess_service={str(match['advertises_biomess_service']).lower()}"
        )
    print(f"advertised_name_validation_ok={str(not name_failures).lower()}")
    print(f"advertised_service_validation_ok={str(not service_failures).lower()}")
    for failure in failures:
        print(f"advertising_validation_failure={failure}")

    if args.summary_json:
        args.summary_json.parent.mkdir(parents=True, exist_ok=True)
        args.summary_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"summary_json={args.summary_json}")

    if failures:
        raise SystemExit("BioMess BLE advertising validation failed")

    print("advertising_scan_ok=true")


if __name__ == "__main__":
    asyncio.run(main())
