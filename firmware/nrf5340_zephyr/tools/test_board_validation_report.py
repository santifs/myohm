#!/usr/bin/env python3
"""Offline contract test for board_validation_report.py full-board evidence handling."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent
SCRIPT = TOOLS_DIR / "board_validation_report.py"
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
BLE_BOARD_STEPS = (
    "BLE advertising scan",
    "BLE/GATT probe",
    "board health",
    "PMIC battery",
    "LED command",
    "AD5940 sweep",
    "AD5940 sweep CSV analysis",
    "stored sync",
)


def write_summary(path: Path, labels: tuple[str, ...]) -> None:
    def stdout_tail(label: str) -> str:
        if label == "BLE advertising scan":
            return "\n".join(
                [
                    "advertised_name_validation_ok=true",
                    "advertised_service_validation_ok=true",
                    "advertising_scan_ok=true",
                ]
            )
        if label == "BLE/GATT probe":
            return "\n".join(
                [
                    "advertised_name_validation_ok=true",
                    "gatt_validation_ok=true",
                    "ble_probe_ok=true",
                ]
            )
        return f"{label} ok"

    summary = {
        "ok": True,
        "flash_requested": True,
        "uart_capture_enabled": True,
        "ble_enabled": True,
        "steps": [
            {
                "label": label,
                "command": ["fixture", label],
                "cwd": str(TOOLS_DIR),
                "exit_code": 0,
                "duration_seconds": 0.001,
                "ok": True,
                "stdout_tail": stdout_tail(label),
            }
            for label in labels
        ],
    }
    path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


def write_summary_with_ble_probe_output(path: Path, stdout_tail: str) -> None:
    write_summary(path, FULL_BOARD_STEPS)
    summary = json.loads(path.read_text(encoding="utf-8"))
    for step in summary["steps"]:
        if step["label"] == "BLE/GATT probe":
            step["stdout_tail"] = stdout_tail
    path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


def write_summary_with_ble_probe_json(path: Path, ble_json: Path) -> None:
    write_summary_with_ble_probe_output(path, "")
    summary = json.loads(path.read_text(encoding="utf-8"))
    summary["ble_probe_summary_json"] = str(ble_json)
    path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    ble_json.write_text(
        json.dumps(
            {
                "ok": True,
                "advertised_name": "BioMess",
                "advertised_name_expected": "BioMess",
                "advertised_name_validation_enabled": True,
                "advertised_name_validation_failures": [],
                "validation_failures": [],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def write_summary_with_advertising_json(path: Path, advertising_json: Path) -> None:
    write_summary(path, FULL_BOARD_STEPS)
    summary = json.loads(path.read_text(encoding="utf-8"))
    summary["advertising_summary_json"] = str(advertising_json)
    path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    advertising_json.write_text(
        json.dumps(
            {
                "ok": True,
                "match_count": 1,
                "matches": [
                    {
                        "address": "AA:BB:CC:DD:EE:FF",
                        "local_name": "BioMess",
                        "advertises_biomess_service": True,
                    }
                ],
                "name_validation_failures": [],
                "service_validation_failures": [],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def run_report(tmp: Path, summary: Path, name: str, mode: str = "--require-full-board") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--verification-json",
            str(summary),
            mode,
            "--output",
            str(tmp / f"{name}.md"),
            "--summary-json",
            str(tmp / f"{name}.json"),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="biomess-board-report-") as tmp_name:
        tmp = Path(tmp_name)

        complete = tmp / "complete.json"
        write_summary(complete, FULL_BOARD_STEPS)
        complete_result = run_report(tmp, complete, "complete")
        if complete_result.returncode != 0:
            raise AssertionError(complete_result.stdout)
        report = (tmp / "complete.md").read_text(encoding="utf-8")
        if "board_validation_ok=true" not in report:
            raise AssertionError("Complete full-board fixture must pass board validation")
        if "covered by run_verification.py firmware flash step" not in report:
            raise AssertionError("Runner firmware flash step must count as flash evidence")
        if "BLE/GATT probe stdout evidence" not in report or "missing_markers=none" not in report:
            raise AssertionError("Complete full-board fixture must require BLE probe marker evidence")
        if "BLE advertising stdout evidence" not in report or "missing_markers=none" not in report:
            raise AssertionError("Complete full-board fixture must require BLE advertising marker evidence")

        complete_advertising_json = tmp / "complete-advertising-json.json"
        advertising_json = tmp / "biomess_advertising_scan.json"
        write_summary_with_advertising_json(complete_advertising_json, advertising_json)
        complete_advertising_result = run_report(tmp, complete_advertising_json, "complete-advertising-json")
        if complete_advertising_result.returncode != 0:
            raise AssertionError(complete_advertising_result.stdout)
        complete_advertising_report = (tmp / "complete-advertising-json.md").read_text(encoding="utf-8")
        if "BLE advertising JSON evidence" not in complete_advertising_report:
            raise AssertionError("Board report must accept structured BLE advertising JSON evidence")

        complete_json = tmp / "complete-ble-json.json"
        ble_probe_json = tmp / "biomess_gatt_probe.json"
        write_summary_with_ble_probe_json(complete_json, ble_probe_json)
        complete_json_result = run_report(tmp, complete_json, "complete-ble-json")
        if complete_json_result.returncode != 0:
            raise AssertionError(complete_json_result.stdout)
        complete_json_report = (tmp / "complete-ble-json.md").read_text(encoding="utf-8")
        if "BLE/GATT probe JSON evidence" not in complete_json_report:
            raise AssertionError("Board report must accept structured BLE probe JSON evidence")

        missing_flash = tmp / "missing-flash.json"
        write_summary(missing_flash, tuple(label for label in FULL_BOARD_STEPS if label != "firmware flash"))
        missing_result = run_report(tmp, missing_flash, "missing-flash")
        if missing_result.returncode == 0:
            raise AssertionError("Missing firmware flash step must fail full-board validation")
        missing_report = (tmp / "missing-flash.md").read_text(encoding="utf-8")
        if "pass --flash-json or a --verification-json with firmware flash" not in missing_report:
            raise AssertionError("Missing flash evidence report must explain accepted evidence")

        missing_ble_marker = tmp / "missing-ble-marker.json"
        write_summary_with_ble_probe_output(missing_ble_marker, "gatt_validation_ok=true\nble_probe_ok=true")
        missing_ble_result = run_report(tmp, missing_ble_marker, "missing-ble-marker")
        if missing_ble_result.returncode == 0:
            raise AssertionError("Missing advertised-name BLE marker must fail full-board validation")
        missing_ble_report = (tmp / "missing-ble-marker.md").read_text(encoding="utf-8")
        if "advertised_name_validation_ok=true" not in missing_ble_report:
            raise AssertionError("Missing BLE marker report must name the required advertised-name evidence")

        missing_advertising = tmp / "missing-advertising.json"
        write_summary(missing_advertising, tuple(label for label in FULL_BOARD_STEPS if label != "BLE advertising scan"))
        missing_advertising_result = run_report(tmp, missing_advertising, "missing-advertising")
        if missing_advertising_result.returncode == 0:
            raise AssertionError("Missing BLE advertising scan step must fail full-board validation")
        missing_advertising_report = (tmp / "missing-advertising.md").read_text(encoding="utf-8")
        if "BLE advertising scan" not in missing_advertising_report:
            raise AssertionError("Missing advertising evidence report must name the required step")

        ble_only = tmp / "ble-only.json"
        write_summary(ble_only, BLE_BOARD_STEPS)
        ble_summary = json.loads(ble_only.read_text(encoding="utf-8"))
        ble_summary["flash_requested"] = False
        ble_summary["uart_capture_enabled"] = False
        ble_summary["ble_enabled"] = True
        ble_only.write_text(json.dumps(ble_summary, indent=2) + "\n", encoding="utf-8")
        ble_only_result = run_report(tmp, ble_only, "ble-only", "--require-ble-board")
        if ble_only_result.returncode != 0:
            raise AssertionError(ble_only_result.stdout)
        ble_only_report = (tmp / "ble-only.md").read_text(encoding="utf-8")
        if "BLE-board mode: `true`" not in ble_only_report or "board_validation_ok=true" not in ble_only_report:
            raise AssertionError("BLE-board fixture must pass without UART or flash evidence")

        ble_missing_pmic = tmp / "ble-missing-pmic.json"
        write_summary(ble_missing_pmic, tuple(label for label in BLE_BOARD_STEPS if label != "PMIC battery"))
        ble_missing_summary = json.loads(ble_missing_pmic.read_text(encoding="utf-8"))
        ble_missing_summary["flash_requested"] = False
        ble_missing_summary["uart_capture_enabled"] = False
        ble_missing_summary["ble_enabled"] = True
        ble_missing_pmic.write_text(json.dumps(ble_missing_summary, indent=2) + "\n", encoding="utf-8")
        ble_missing_result = run_report(tmp, ble_missing_pmic, "ble-missing-pmic", "--require-ble-board")
        if ble_missing_result.returncode == 0:
            raise AssertionError("Missing PMIC battery step must fail BLE-board validation")
        ble_missing_report = (tmp / "ble-missing-pmic.md").read_text(encoding="utf-8")
        if "PMIC battery" not in ble_missing_report:
            raise AssertionError("BLE-board missing-step report must name the missing PMIC battery step")

    print("board_validation_report_contract_ok=true")


if __name__ == "__main__":
    main()
