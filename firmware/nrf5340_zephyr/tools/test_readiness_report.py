#!/usr/bin/env python3
"""Exercise readiness_report.py with synthetic release evidence."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent
READINESS = TOOLS_DIR / "readiness_report.py"
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


def run(command: list[str], expect_ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if expect_ok and result.returncode != 0:
        raise SystemExit(f"Command failed with exit {result.returncode}: {' '.join(command)}\n{result.stdout}")
    if not expect_ok and result.returncode == 0:
        raise SystemExit(f"Command unexpectedly succeeded: {' '.join(command)}\n{result.stdout}")
    return result


def write_release(package: Path, firmware: bytes, *, full_board: bool = False, summary_ok: bool = True) -> None:
    steps = FULL_BOARD_STEPS if full_board else ("offline protocol contract",)
    summary = {
        "ok": summary_ok,
        "flash_requested": full_board,
        "uart_capture_enabled": full_board,
        "ble_enabled": full_board,
        "steps": [{"label": label, "ok": True} for label in steps],
    }
    with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("firmware/merged.hex", firmware)
        archive.writestr("verification-summary.json", json.dumps(summary))


def load_summary(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def test_handoff_ready_fixture(temp_dir: Path) -> None:
    firmware = b":020000040000FA\n"
    build_hex = temp_dir / "build.hex"
    release = temp_dir / "release.zip"
    summary_json = temp_dir / "readiness.json"
    build_hex.write_bytes(firmware)
    write_release(release, firmware)

    result = run(
        [
            sys.executable,
            str(READINESS),
            "--build-hex",
            str(build_hex),
            "--release-package",
            str(release),
            "--summary-json",
            str(summary_json),
            "--require-handoff",
        ]
    )
    if "readiness_handoff_ready=true" not in result.stdout:
        raise SystemExit("readiness_report.py did not report handoff readiness for a matching release")
    if "readiness_serial_debug_port_visible=" not in result.stdout:
        raise SystemExit("readiness_report.py did not print serial debug port visibility")
    summary = load_summary(summary_json)
    if summary.get("release_matches_build") is not True or summary.get("handoff_ready") is not True:
        raise SystemExit("readiness summary JSON did not preserve handoff-ready evidence")
    for key in ("serial_port_count", "debug_like_serial_port_count", "serial_debug_port_visible", "debug_like_serial_ports"):
        if key not in summary:
            raise SystemExit(f"readiness summary JSON is missing debugger/serial evidence: {key}")
    if summary.get("full_board_validation_complete") is not False:
        raise SystemExit("readiness must not mark full-board validation complete from offline-only evidence")


def test_full_board_fixture(temp_dir: Path) -> None:
    firmware = b":020000040000FA\n"
    build_hex = temp_dir / "full-build.hex"
    release = temp_dir / "full-release.zip"
    build_hex.write_bytes(firmware)
    write_release(release, firmware, full_board=True)

    result = run(
        [
            sys.executable,
            str(READINESS),
            "--build-hex",
            str(build_hex),
            "--release-package",
            str(release),
            "--require-handoff",
            "--require-full-board",
        ]
    )
    if "readiness_full_board_validation_complete=true" not in result.stdout:
        raise SystemExit("readiness_report.py did not accept complete full-board release evidence")


def test_mismatched_release_fails_handoff(temp_dir: Path) -> None:
    build_hex = temp_dir / "build.hex"
    release = temp_dir / "mismatch.zip"
    build_hex.write_bytes(b":020000040000FA\n")
    write_release(release, b":020000040001F9\n")

    result = run(
        [
            sys.executable,
            str(READINESS),
            "--build-hex",
            str(build_hex),
            "--release-package",
            str(release),
            "--require-handoff",
        ],
        expect_ok=False,
    )
    if "readiness_handoff_ready=false" not in result.stdout:
        raise SystemExit("readiness_report.py did not report handoff false for mismatched firmware")
    if "handoff is not ready" not in result.stdout:
        raise SystemExit("readiness_report.py did not fail with a clear handoff error")


def test_malformed_release_fails_handoff_without_traceback(temp_dir: Path) -> None:
    build_hex = temp_dir / "build.hex"
    build_hex.write_bytes(b":020000040000FA\n")

    missing_firmware = temp_dir / "missing-firmware.zip"
    missing_summary = temp_dir / "missing-summary.zip"
    bad_zip = temp_dir / "not-a-zip.zip"
    missing_summary_json = temp_dir / "missing-summary-readiness.json"
    build = [sys.executable, str(READINESS), "--build-hex", str(build_hex), "--require-handoff"]

    with zipfile.ZipFile(missing_firmware, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("verification-summary.json", json.dumps({"ok": True, "steps": []}))
    bad_zip.write_text("not a zip\n", encoding="utf-8")
    with zipfile.ZipFile(missing_summary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("firmware/merged.hex", build_hex.read_bytes())

    missing_firmware_result = run([*build, "--release-package", str(missing_firmware)], expect_ok=False)
    if "readiness_release_error=missing firmware/merged.hex" not in missing_firmware_result.stdout:
        raise SystemExit("readiness_report.py did not explain missing firmware/merged.hex")
    if "Traceback" in missing_firmware_result.stdout:
        raise SystemExit("readiness_report.py must not traceback on malformed releases")

    bad_zip_result = run([*build, "--release-package", str(bad_zip)], expect_ok=False)
    if "readiness_release_error=invalid zip file" not in bad_zip_result.stdout:
        raise SystemExit("readiness_report.py did not explain an invalid zip file")

    missing_summary_result = run(
        [
            *build,
            "--release-package",
            str(missing_summary),
            "--summary-json",
            str(missing_summary_json),
        ],
        expect_ok=False,
    )
    if "readiness_release_error=missing or invalid verification-summary.json" not in missing_summary_result.stdout:
        raise SystemExit("readiness_report.py did not explain missing verification-summary.json")
    summary = load_summary(missing_summary_json)
    if summary.get("release_matches_build") is not True or summary.get("handoff_ready") is not False:
        raise SystemExit("readiness summary must preserve hash match while rejecting missing verification summary")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="biomess_readiness_fixture_") as temp:
        temp_dir = Path(temp)
        test_handoff_ready_fixture(temp_dir)
        test_full_board_fixture(temp_dir)
        test_mismatched_release_fails_handoff(temp_dir)
        test_malformed_release_fails_handoff_without_traceback(temp_dir)
    print("readiness_report_contract_ok=true")


if __name__ == "__main__":
    main()
