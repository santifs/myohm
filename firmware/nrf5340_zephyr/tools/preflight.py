#!/usr/bin/env python3
"""Check local tools and board-visible interfaces before firmware bring-up."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


DEFAULT_WEST = Path("/opt/nordic/ncs/toolchains/0c0f19d91c/bin/west")
DEFAULT_NRFJPROG = Path("/usr/local/bin/nrfjprog")
DEFAULT_ZEPHYR_SDK = Path("/opt/nordic/ncs/toolchains/0c0f19d91c/opt/zephyr-sdk")
REQUIREMENTS = Path(__file__).resolve().parent / "requirements.txt"
SERIAL_DEBUG_MARKERS = ("usbmodem", "jlink", "j-link", "debug")


def dependency_install_hint() -> str:
    return f"python3 -m pip install -r {REQUIREMENTS}"


def check_python_module(name: str) -> bool:
    try:
        __import__(name)
    except Exception:
        return False
    return True


def run_text(command: list[str]) -> tuple[int, str]:
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except FileNotFoundError as exc:
        return 127, str(exc)
    return result.returncode, result.stdout.strip()


def list_serial_ports() -> list[str]:
    if sys.platform == "darwin":
        return sorted(str(path) for path in Path("/dev").glob("cu.*"))
    return sorted(str(path) for path in Path("/dev").glob("ttyACM*")) + sorted(str(path) for path in Path("/dev").glob("ttyUSB*"))


def is_debug_like_serial_port(port: str) -> bool:
    return any(marker in port.lower() for marker in SERIAL_DEBUG_MARKERS)


def print_bool(name: str, value: bool) -> None:
    print(f"{name}={'true' if value else 'false'}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--west", type=Path, default=DEFAULT_WEST)
    parser.add_argument("--nrfjprog", type=Path, default=DEFAULT_NRFJPROG)
    parser.add_argument("--zephyr-sdk", type=Path, default=DEFAULT_ZEPHYR_SDK)
    parser.add_argument("--require-board", action="store_true", help="Exit non-zero if no nRF debugger is detected.")
    parser.add_argument("--require-bleak", action="store_true", help="Exit non-zero if bleak is not importable.")
    parser.add_argument("--require-pyserial", action="store_true", help="Exit non-zero if pyserial is not importable.")
    args = parser.parse_args()

    west_path = args.west if args.west.exists() else Path(shutil.which("west") or "")
    nrfjprog_path = args.nrfjprog if args.nrfjprog.exists() else Path(shutil.which("nrfjprog") or "")

    print_bool("west_available", bool(west_path and west_path.exists()))
    if west_path and west_path.exists():
        print(f"west_path={west_path}")

    print_bool("zephyr_sdk_available", args.zephyr_sdk.exists())
    if args.zephyr_sdk.exists():
        print(f"zephyr_sdk={args.zephyr_sdk}")

    print_bool("nrfjprog_available", bool(nrfjprog_path and nrfjprog_path.exists()))
    ids: list[str] = []
    if nrfjprog_path and nrfjprog_path.exists():
        code, output = run_text([str(nrfjprog_path), "--ids"])
        print(f"nrfjprog_ids_exit={code}")
        ids = [line.strip() for line in output.splitlines() if line.strip()]
        if ids:
            print("nrfjprog_ids=" + ",".join(ids))
        else:
            print("nrfjprog_ids=")

    bleak_available = check_python_module("bleak")
    pyserial_available = check_python_module("serial")
    print_bool("bleak_available", bleak_available)
    print_bool("pyserial_available", pyserial_available)

    ports = list_serial_ports()
    debug_like_ports = [port for port in ports if is_debug_like_serial_port(port)]
    print("serial_ports=" + ",".join(ports))
    print(f"serial_port_count={len(ports)}")
    print(f"debug_like_serial_port_count={len(debug_like_ports)}")
    print_bool("serial_debug_port_visible", bool(debug_like_ports))
    print("debug_like_serial_ports=" + ",".join(debug_like_ports))

    if args.require_board and not ids:
        if debug_like_ports:
            raise SystemExit(
                "No nRF debugger detected by nrfjprog --ids, although a debug-like serial port is visible. "
                "Check that USB is connected to a J-Link/nRF debug probe endpoint, not only UART/CDC; "
                "then run firmware/nrf5340_zephyr/tools/diagnose_debugger.py for details."
            )
        raise SystemExit(
            "No nRF debugger detected by nrfjprog --ids. "
            "Run firmware/nrf5340_zephyr/tools/diagnose_debugger.py for USB/J-Link details."
        )
    if args.require_bleak and not bleak_available:
        raise SystemExit(f"Missing dependency: {dependency_install_hint()}")
    if args.require_pyserial and not pyserial_available:
        raise SystemExit(f"Missing dependency: {dependency_install_hint()}")

    print("preflight_ok=true")


if __name__ == "__main__":
    main()
