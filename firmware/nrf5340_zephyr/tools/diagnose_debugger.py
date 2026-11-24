#!/usr/bin/env python3
"""Diagnose nRF5340 debugger visibility before flashing."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from serial.tools import list_ports
except ImportError:  # pragma: no cover - diagnostic still works without pyserial
    list_ports = None


DEFAULT_NRFJPROG = Path("/usr/local/bin/nrfjprog")
JLINK_CANDIDATES = (
    Path("/Applications/SEGGER/JLink/JLinkExe"),
    Path("/opt/SEGGER/JLink/JLinkExe"),
)
SERIAL_DEBUG_MARKERS = ("usbmodem", "jlink", "j-link", "debug")


def run_text(command: list[str], timeout: float = 8.0) -> tuple[int, str]:
    try:
        result = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        return 127, str(exc)
    except subprocess.TimeoutExpired as exc:
        return 124, (exc.stdout or "") + "\ncommand timed out"
    return result.returncode, result.stdout.strip()


def first_existing_tool(default_path: Path, names: tuple[str, ...]) -> Path | None:
    if default_path.exists():
        return default_path
    for name in names:
        found = shutil.which(name)
        if found:
            return Path(found)
    return None


def find_jlink() -> Path | None:
    for path in JLINK_CANDIDATES:
        if path.exists():
            return path
    found = shutil.which("JLinkExe") or shutil.which("JLink")
    return Path(found) if found else None


def serial_ports() -> list[dict[str, str]]:
    if list_ports is not None:
        ports = []
        for port in list_ports.comports():
            ports.append(
                {
                    "device": str(port.device or ""),
                    "description": str(port.description or ""),
                    "manufacturer": str(port.manufacturer or ""),
                    "product": str(port.product or ""),
                    "serial_number": str(port.serial_number or ""),
                    "vid": f"0x{port.vid:04x}" if port.vid is not None else "",
                    "pid": f"0x{port.pid:04x}" if port.pid is not None else "",
                }
            )
        return ports

    if sys.platform == "darwin":
        return [{"device": str(path)} for path in sorted(Path("/dev").glob("cu.*"))]
    return [{"device": str(path)} for path in sorted(Path("/dev").glob("ttyACM*")) + sorted(Path("/dev").glob("ttyUSB*"))]


def is_debug_like(port: dict[str, str]) -> bool:
    haystack = " ".join(port.values()).lower()
    return any(marker in haystack for marker in SERIAL_DEBUG_MARKERS)


def print_section(name: str) -> None:
    print(f"\n[{name}]")


def write_summary_json(path: Path, summary: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nrfjprog", type=Path, default=DEFAULT_NRFJPROG)
    parser.add_argument("--include-usb-tree", action="store_true", help="On macOS, print a short system_profiler USB tree.")
    parser.add_argument("--require-board", action="store_true", help="Exit non-zero if nrfjprog does not list a debugger.")
    parser.add_argument("--summary-json", type=Path, help="Write a machine-readable debugger diagnosis summary.")
    args = parser.parse_args()

    nrfjprog = first_existing_tool(args.nrfjprog, ("nrfjprog",))
    jlink = find_jlink()
    summary: dict[str, object] = {
        "nrfjprog_path": str(nrfjprog or ""),
        "jlink_path": str(jlink or ""),
        "nrfjprog_available": nrfjprog is not None,
        "jlink_available": jlink is not None,
    }

    print_section("tools")
    print(f"nrfjprog_path={nrfjprog or ''}")
    print(f"jlink_path={jlink or ''}")

    ids: list[str] = []
    if nrfjprog is not None:
        code, version = run_text([str(nrfjprog), "--version"])
        summary["nrfjprog_version_exit"] = code
        print(f"nrfjprog_version_exit={code}")
        if version:
            first_line = version.splitlines()[0]
            summary["nrfjprog_version"] = first_line
            print(f"nrfjprog_version={first_line}")
        code, output = run_text([str(nrfjprog), "--ids"])
        summary["nrfjprog_ids_exit"] = code
        print(f"nrfjprog_ids_exit={code}")
        ids = [line.strip() for line in output.splitlines() if line.strip()]
        summary["nrfjprog_ids"] = ids
        print("nrfjprog_ids=" + ",".join(ids))
    else:
        summary["nrfjprog_ids_exit"] = 127
        summary["nrfjprog_ids"] = []
        print("nrfjprog_available=false")

    if jlink is not None:
        code, output = run_text([str(jlink), "-?"])
        summary["jlink_probe_exit"] = code
        print(f"jlink_probe_exit={code}")
        if output:
            first_line = output.splitlines()[0]
            summary["jlink_probe_output"] = first_line
            print("jlink_probe_output=" + first_line)

    print_section("serial_ports")
    ports = serial_ports()
    debug_like = [port for port in ports if is_debug_like(port)]
    summary["serial_ports"] = ports
    summary["debug_like_serial_ports"] = debug_like
    print(f"serial_port_count={len(ports)}")
    print(f"debug_like_serial_port_count={len(debug_like)}")
    for index, port in enumerate(ports):
        prefix = f"serial_port_{index}"
        print(f"{prefix}_device={port.get('device', '')}")
        for key in ("description", "manufacturer", "product", "serial_number", "vid", "pid"):
            if port.get(key):
                print(f"{prefix}_{key}={port[key]}")

    if args.include_usb_tree and sys.platform == "darwin":
        print_section("usb_tree")
        code, output = run_text(["system_profiler", "SPUSBDataType", "-detailLevel", "mini"], timeout=20.0)
        print(f"system_profiler_usb_exit={code}")
        for line in output.splitlines()[:120]:
            print(line)

    print_section("assessment")
    debugger_visible = bool(ids)
    serial_debug_port_visible = bool(debug_like)
    print(f"debugger_visible={str(debugger_visible).lower()}")
    print(f"serial_debug_port_visible={str(serial_debug_port_visible).lower()}")

    if ids:
        next_step = "run run_verification.py --flash --uart --ble"
        checks: list[str] = []
    elif debug_like:
        next_step = "serial port is visible but nrfjprog has no debugger ID; check that the USB endpoint is a J-Link/debug probe, not only UART/CDC"
        checks = [
            "confirm the cable is connected to the J-Link/debug USB connector or external probe",
            "confirm the BioMess board/debug probe is powered and not held in reset",
            "close other Nordic/J-Link tools that may own the probe",
            "install or repair SEGGER J-Link plus Nordic Command Line Tools if J-Link is missing",
        ]
    else:
        next_step = "no debug-like serial port or nrfjprog ID found; check USB cable, power and probe connection"
        checks = []

    print(f"next_step={next_step}")
    for index, check in enumerate(checks, start=1):
        print(f"check_{index}={check}")

    summary.update(
        {
            "debugger_visible": debugger_visible,
            "serial_debug_port_visible": serial_debug_port_visible,
            "next_step": next_step,
            "checks": checks,
            "debugger_diagnostics_ok": True,
        }
    )
    print("debugger_diagnostics_ok=true")
    if args.summary_json:
        write_summary_json(args.summary_json, summary)
        print(f"summary_json_path={args.summary_json}")

    if args.require_board and not ids:
        raise SystemExit("No nRF debugger detected by nrfjprog --ids")


if __name__ == "__main__":
    main()
