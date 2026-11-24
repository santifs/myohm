#!/usr/bin/env python3
"""Build and verify a synthetic handoff package without Nordic SDK or board hardware."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


FIRMWARE_DIR = Path(__file__).resolve().parents[1]
TOOLS_DIR = FIRMWARE_DIR / "tools"
DEFAULT_BOARD = "biomess_nrf5340/nrf5340/cpuapp"


def run(command: list[str]) -> str:
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    result = subprocess.run(
        command,
        cwd=FIRMWARE_DIR.parents[1],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        raise SystemExit(result.stdout)
    return result.stdout


def main() -> None:
    build_dir = FIRMWARE_DIR / "build"
    build_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="release-fixture-", dir=build_dir) as temp:
        temp_dir = Path(temp)
        hex_path = temp_dir / "merged.hex"
        network_hex_path = temp_dir / "merged_CPUNET.hex"
        report_path = temp_dir / "verification-report.md"
        summary_path = temp_dir / "verification-summary.json"
        output_dir = temp_dir / "releases"

        hex_path.write_text(":00000001FF\n", encoding="ascii")
        network_hex_path.write_text(":00000001FF\n", encoding="ascii")
        report_path.write_text("# Synthetic firmware verification report\n\n`verification_ok=true`\n", encoding="utf-8")
        summary_path.write_text(
            json.dumps(
                {
                    "ok": True,
                    "board": DEFAULT_BOARD,
                    "flash_requested": False,
                    "uart_capture_enabled": False,
                    "ble_enabled": False,
                    "steps": [
                        {"label": "firmware build", "ok": True, "exit_code": 0},
                        {"label": "firmware build artifacts", "ok": True, "exit_code": 0},
                    ],
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )

        package_output = run(
            [
                sys.executable,
                str(TOOLS_DIR / "package_firmware_release.py"),
                "--hex",
                str(hex_path),
                "--network-hex",
                str(network_hex_path),
                "--report",
                str(report_path),
                "--summary-json",
                str(summary_path),
                "--output-dir",
                str(output_dir),
                "--name",
                "biomess-nrf5340-firmware-fixture",
            ]
        )
        package_lines = [line for line in package_output.splitlines() if line.startswith("release_package=")]
        if not package_lines:
            raise SystemExit("package_firmware_release.py did not print release_package=")
        package = Path(package_lines[-1].split("=", 1)[1])

        verify_output = run(
            [
                sys.executable,
                str(TOOLS_DIR / "verify_firmware_release.py"),
                str(package),
                "--require-report",
                "--require-summary-json",
                "--require-build-summary",
            ]
        )
        if "release_package_verify_ok=true" not in verify_output:
            raise SystemExit("verify_firmware_release.py did not confirm the synthetic package")

        print(f"release_fixture_package={package}")
        print("release_fixture_package_verify_ok=true")
        print("release_package_fixture_ok=true")


if __name__ == "__main__":
    main()
