#!/usr/bin/env python3
"""Capture BioMess firmware UART logs for bring-up reports."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

try:
    import serial
    from serial.tools import list_ports
except ImportError:  # pragma: no cover - only used on machines without pyserial
    serial = None
    list_ports = None


PREFERRED_PORT_MARKERS = (
    "usbmodem",
    "jlink",
    "j-link",
    "debug",
)
REQUIREMENTS = Path(__file__).resolve().parent / "requirements.txt"


def dependency_install_hint() -> str:
    return f"python3 -m pip install -r {REQUIREMENTS}"


def find_port() -> str:
    if list_ports is None:
        raise RuntimeError(f"Missing dependency: {dependency_install_hint()}")

    ports = list(list_ports.comports())
    if not ports:
        raise RuntimeError("No serial ports found")

    for port in ports:
        haystack = " ".join(
            str(value).lower()
            for value in (port.device, port.description, port.manufacturer, port.product)
            if value
        )
        if any(marker in haystack for marker in PREFERRED_PORT_MARKERS):
            return port.device

    return ports[0].device


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Serial port. If omitted, auto-detects USB/J-Link/debug ports.")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=10.0)
    parser.add_argument("--output", type=Path, help="Optional file to write captured text.")
    args = parser.parse_args()

    if serial is None:
        raise SystemExit(f"Missing dependency: {dependency_install_hint()}")

    port = args.port or find_port()
    deadline = time.monotonic() + args.seconds
    chunks: list[str] = []

    print(f"uart_port={port}")
    print(f"uart_baud={args.baud}")
    print(f"capture_seconds={args.seconds:g}")

    with serial.Serial(port, args.baud, timeout=0.2) as ser:
        while time.monotonic() < deadline:
            data = ser.read(512)
            if not data:
                continue
            text = data.decode("utf-8", errors="replace")
            chunks.append(text)
            print(text, end="", flush=True)

    captured = "".join(chunks)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(captured, encoding="utf-8")
        print(f"\nuart_log_path={args.output}")

    if "BioMess" in captured or "AD5940" in captured or "BLE advertising" in captured:
        print("uart_capture_ok=true")
    else:
        print("uart_capture_ok=false")


if __name__ == "__main__":
    main()
