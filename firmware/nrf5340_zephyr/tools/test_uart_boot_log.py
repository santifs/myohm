#!/usr/bin/env python3
"""Validate captured UART boot logs from the BioMess nRF5340 firmware."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class BootCheck:
    name: str
    patterns: tuple[str, ...]
    required: bool = True


BOOT_CHECKS = (
    BootCheck("banner", ("AD5940 Bioimpedance Analyzer",)),
    BootCheck("pmic_ready", ("nPM1304 PMIC ready",)),
    BootCheck("ble_advertising", ("BLE advertising as BioMess", "BLE advertising")),
    BootCheck("spi_ready", ("SPI device ready",)),
    BootCheck("ad5940_gpio_mapping", ("AD5940 GPIOs:",)),
    BootCheck("app_ready", ("Ready. Connect with the BioMess app",)),
)

PMIC_WARNING_PATTERNS = (
    "nPM1304 PMIC is not ready",
    "nPM1304 charger is not ready",
)


def contains_any(text: str, patterns: tuple[str, ...]) -> bool:
    return any(pattern.lower() in text for pattern in patterns)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path, help="UART log captured by capture_uart.py")
    parser.add_argument(
        "--allow-pmic-warning",
        action="store_true",
        help="Do not fail when PMIC-ready text is missing but a PMIC warning is present.",
    )
    args = parser.parse_args()

    if not args.log.exists():
        raise SystemExit(f"UART log does not exist: {args.log}")

    text = args.log.read_text(encoding="utf-8", errors="replace")
    normalized = text.lower()
    missing: list[str] = []

    print(f"uart_log_path={args.log}")
    print(f"uart_log_bytes={len(text.encode('utf-8'))}")

    for check in BOOT_CHECKS:
        present = contains_any(normalized, check.patterns)
        if check.name == "pmic_ready" and not present and args.allow_pmic_warning:
            present = contains_any(normalized, PMIC_WARNING_PATTERNS)
        print(f"{check.name}={str(present).lower()}")
        if check.required and not present:
            missing.append(check.name)

    if missing:
        print("boot_log_ok=false")
        raise SystemExit("Missing required boot log markers: " + ", ".join(missing))

    print("boot_log_ok=true")


if __name__ == "__main__":
    main()
