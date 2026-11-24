#!/usr/bin/env python3
"""Summarize firmware handoff and board-readiness state from local evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path

try:
    from serial.tools import list_ports
except ImportError:  # pragma: no cover - readiness still works without pyserial
    list_ports = None


FIRMWARE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_BUILD_HEX = FIRMWARE_DIR / "build/merged.hex"
DEFAULT_PACKAGE_HEX = FIRMWARE_DIR / "firmware/merged.hex"
DEFAULT_PACKAGE_MANIFEST = FIRMWARE_DIR / "manifest.json"
DEFAULT_RELEASE_DIR = FIRMWARE_DIR / "build/releases"
SERIAL_DEBUG_MARKERS = ("usbmodem", "jlink", "j-link", "debug")
FULL_BOARD_STEPS = (
    "firmware flash",
    "UART capture",
    "UART boot log check",
    "BLE advertising scan",
    "BLE/GATT probe",
    "board health",
    "PMIC battery",
    "LED command",
    "AD5940 sweep",
    "AD5940 sweep CSV analysis",
    "stored sync",
)
OUTPUT_CONTRACT_KEYS = (
    "readiness_handoff_ready",
    "readiness_board_ready_to_flash",
    "readiness_full_board_validation_complete",
    "readiness_serial_debug_port_visible",
    "readiness_next_step",
    "readiness_report_ok=true",
)


def bool_text(value: bool) -> str:
    return "true" if value else "false"


def run_text(command: list[str]) -> tuple[int, str]:
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except FileNotFoundError as exc:
        return 127, str(exc)
    return result.returncode, result.stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def latest_release() -> Path | None:
    packages = sorted(DEFAULT_RELEASE_DIR.glob("biomess-nrf5340-firmware-*.zip"), key=lambda path: path.stat().st_mtime)
    return packages[-1] if packages else None


def load_json_entry(archive: zipfile.ZipFile, name: str) -> dict[str, object] | None:
    try:
        return json.loads(archive.read(name).decode("utf-8"))
    except (KeyError, json.JSONDecodeError):
        return None


def step_map(summary: dict[str, object] | None) -> dict[str, dict[str, object]]:
    if not summary:
        return {}
    steps = summary.get("steps")
    if not isinstance(steps, list):
        return {}
    mapped: dict[str, dict[str, object]] = {}
    for step in steps:
        if isinstance(step, dict) and isinstance(step.get("label"), str):
            mapped[str(step["label"])] = step
    return mapped


def inspect_release(package: Path | None, build_sha: str | None, build_size: int | None) -> dict[str, object]:
    data: dict[str, object] = {
        "release_package": str(package) if package else "",
        "release_exists": package is not None and package.exists(),
        "release_entries": 0,
        "release_sha256": "",
        "release_bytes": 0,
        "release_matches_build": False,
        "release_verification_summary_ok": False,
        "release_full_board_validation_complete": False,
        "release_missing_full_board_steps": list(FULL_BOARD_STEPS),
        "release_error": "",
    }
    if package is None or not package.exists():
        return data

    try:
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            if "firmware/merged.hex" not in names:
                data.update({"release_entries": len(names), "release_error": "missing firmware/merged.hex"})
                return data
            firmware = archive.read("firmware/merged.hex")
            summary = load_json_entry(archive, "verification-summary.json")
    except zipfile.BadZipFile:
        data["release_error"] = "invalid zip file"
        return data

    release_sha = sha256_bytes(firmware)
    release_size = len(firmware)
    steps = step_map(summary)
    missing = sorted(label for label in FULL_BOARD_STEPS if steps.get(label, {}).get("ok") is not True)
    summary_ok = summary.get("ok") is True if summary else False
    full_board_flags = (
        bool(summary and summary.get("flash_requested") is True),
        bool(summary and summary.get("uart_capture_enabled") is True),
        bool(summary and summary.get("ble_enabled") is True),
    )

    data.update(
        {
            "release_entries": len(names),
            "release_sha256": release_sha,
            "release_bytes": release_size,
            "release_matches_build": bool(build_sha and build_size and release_sha == build_sha and release_size == build_size),
            "release_verification_summary_ok": summary_ok,
            "release_full_board_validation_complete": bool(summary_ok and all(full_board_flags) and not missing),
            "release_missing_full_board_steps": missing,
            "release_error": "" if summary else "missing or invalid verification-summary.json",
        }
    )
    return data


def inspect_extracted_package(build_sha: str | None, build_size: int | None) -> dict[str, object]:
    data: dict[str, object] = {
        "release_package": str(FIRMWARE_DIR),
        "release_exists": DEFAULT_PACKAGE_MANIFEST.exists() and DEFAULT_PACKAGE_HEX.exists(),
        "release_entries": 0,
        "release_sha256": "",
        "release_bytes": 0,
        "release_matches_build": False,
        "release_verification_summary_ok": False,
        "release_full_board_validation_complete": False,
        "release_missing_full_board_steps": list(FULL_BOARD_STEPS),
        "release_error": "",
    }
    if not data["release_exists"]:
        data["release_error"] = "missing manifest.json or firmware/merged.hex"
        return data

    try:
        manifest = json.loads(DEFAULT_PACKAGE_MANIFEST.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        manifest = {}
        data["release_error"] = "invalid manifest.json"
    image = manifest.get("image") if isinstance(manifest, dict) else {}
    image_sha = image.get("sha256") if isinstance(image, dict) else None
    image_size = image.get("size_bytes") if isinstance(image, dict) else None
    firmware = DEFAULT_PACKAGE_HEX.read_bytes()
    release_sha = sha256_bytes(firmware)
    release_size = len(firmware)
    summary = None
    summary_path = FIRMWARE_DIR / "verification-summary.json"
    if summary_path.exists():
        try:
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            summary = None
    steps = step_map(summary)
    missing = sorted(label for label in FULL_BOARD_STEPS if steps.get(label, {}).get("ok") is not True)
    summary_ok = summary.get("ok") is True if summary else False
    full_board_flags = (
        bool(summary and summary.get("flash_requested") is True),
        bool(summary and summary.get("uart_capture_enabled") is True),
        bool(summary and summary.get("ble_enabled") is True),
    )

    data.update(
        {
            "release_entries": sum(1 for path in FIRMWARE_DIR.rglob("*") if path.is_file()),
            "release_sha256": release_sha,
            "release_bytes": release_size,
            "release_matches_build": bool(
                build_sha
                and build_size
                and release_sha == build_sha
                and release_size == build_size
                and (image_sha in (None, release_sha))
                and (image_size in (None, release_size))
            ),
            "release_verification_summary_ok": summary_ok,
            "release_full_board_validation_complete": bool(summary_ok and all(full_board_flags) and not missing),
            "release_missing_full_board_steps": missing,
            "release_error": data["release_error"] or ("" if summary else "missing or invalid verification-summary.json"),
        }
    )
    return data


def inspect_debugger() -> dict[str, object]:
    code, output = run_text(["nrfjprog", "--ids"])
    ids = [line.strip() for line in output.splitlines() if line.strip()]
    ports = serial_ports()
    debug_like_ports = [port for port in ports if is_debug_like_port(port)]
    return {
        "nrfjprog_ids_exit": code,
        "nrfjprog_ids": ids,
        "debugger_visible": code == 0 and bool(ids),
        "serial_port_count": len(ports),
        "debug_like_serial_port_count": len(debug_like_ports),
        "serial_debug_port_visible": bool(debug_like_ports),
        "debug_like_serial_ports": [str(port.get("device", "")) for port in debug_like_ports],
    }


def serial_ports() -> list[dict[str, str]]:
    if list_ports is not None:
        return [
            {
                "device": str(port.device or ""),
                "description": str(port.description or ""),
                "manufacturer": str(port.manufacturer or ""),
                "product": str(port.product or ""),
                "serial_number": str(port.serial_number or ""),
            }
            for port in list_ports.comports()
        ]
    if sys.platform == "darwin":
        return [{"device": str(path)} for path in sorted(Path("/dev").glob("cu.*"))]
    return [{"device": str(path)} for path in sorted(Path("/dev").glob("ttyACM*")) + sorted(Path("/dev").glob("ttyUSB*"))]


def is_debug_like_port(port: dict[str, str]) -> bool:
    haystack = " ".join(str(value) for value in port.values()).lower()
    return any(marker in haystack for marker in SERIAL_DEBUG_MARKERS)


def next_step(handoff_ready: bool, debugger_visible: bool, serial_debug_port_visible: bool, full_board_complete: bool) -> str:
    if not handoff_ready:
        return "run make firmware-package and make firmware-verify-release"
    if not debugger_visible:
        if serial_debug_port_visible:
            return "serial/debug-like port is visible but nrfjprog has no debugger ID; check J-Link/debug USB, probe power and reset"
        return "connect a real nRF/J-Link debugger, then run make firmware-preflight-board"
    if not full_board_complete:
        return "run make firmware-board-full and make firmware-board-report"
    return "full board validation evidence is complete"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-hex", type=Path, default=DEFAULT_BUILD_HEX)
    parser.add_argument("--release-package", type=Path, help="Release zip. Defaults to newest local release.")
    parser.add_argument("--summary-json", type=Path, help="Write machine-readable readiness summary.")
    parser.add_argument("--require-handoff", action="store_true", help="Exit non-zero unless build and latest release are handoff-ready.")
    parser.add_argument("--require-board", action="store_true", help="Exit non-zero unless nrfjprog sees a debugger.")
    parser.add_argument("--require-full-board", action="store_true", help="Exit non-zero unless release summary includes full board evidence.")
    args = parser.parse_args()

    build_hex = args.build_hex
    if build_hex == DEFAULT_BUILD_HEX and not build_hex.exists() and DEFAULT_PACKAGE_HEX.exists():
        build_hex = DEFAULT_PACKAGE_HEX
    build_exists = build_hex.exists()
    build_sha = sha256_file(build_hex) if build_exists else None
    build_size = build_hex.stat().st_size if build_exists else None
    package = args.release_package or latest_release()
    release = inspect_release(package, build_sha, build_size) if package else inspect_extracted_package(build_sha, build_size)
    debugger = inspect_debugger()

    handoff_ready = bool(build_exists and release["release_matches_build"] and release["release_verification_summary_ok"])
    debugger_visible = bool(debugger["debugger_visible"])
    full_board_complete = bool(release["release_full_board_validation_complete"])
    serial_debug_port_visible = bool(debugger["serial_debug_port_visible"])

    summary: dict[str, object] = {
        "build_hex": str(build_hex),
        "build_hex_exists": build_exists,
        "build_hex_bytes": build_size or 0,
        "build_hex_sha256": build_sha or "",
        **release,
        **debugger,
        "handoff_ready": handoff_ready,
        "board_ready_to_flash": debugger_visible,
        "full_board_validation_complete": full_board_complete,
        "next_step": next_step(handoff_ready, debugger_visible, serial_debug_port_visible, full_board_complete),
    }

    for key, value in summary.items():
        if isinstance(value, bool):
            print(f"readiness_{key}={bool_text(value)}")
        elif isinstance(value, list):
            print(f"readiness_{key}={','.join(str(item) for item in value) if value else ''}")
        else:
            print(f"readiness_{key}={value}")
    print("readiness_report_ok=true")

    if args.summary_json:
        args.summary_json.parent.mkdir(parents=True, exist_ok=True)
        args.summary_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"readiness_summary_json={args.summary_json}")

    failures: list[str] = []
    if args.require_handoff and not handoff_ready:
        failures.append("handoff is not ready")
    if args.require_board and not debugger_visible:
        failures.append("nrfjprog --ids has no debugger ID")
    if args.require_full_board and not full_board_complete:
        failures.append("full board validation evidence is incomplete")
    if failures:
        raise SystemExit("; ".join(failures))


if __name__ == "__main__":
    main()
