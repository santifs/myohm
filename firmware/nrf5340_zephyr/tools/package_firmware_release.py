#!/usr/bin/env python3
"""Create a handoff package for a BioMess nRF5340 firmware image."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path

sys.dont_write_bytecode = True

import describe_ble_contract


REPO_ROOT = Path(__file__).resolve().parents[3]
FIRMWARE_DIR = REPO_ROOT / "firmware/nrf5340_zephyr"
DEFAULT_HEX = FIRMWARE_DIR / "build/merged.hex"
DEFAULT_NETWORK_HEX = FIRMWARE_DIR / "build/merged_CPUNET.hex"
DEFAULT_OUTPUT_DIR = FIRMWARE_DIR / "build/releases"
DEFAULT_BOARD = "biomess_nrf5340/nrf5340/cpuapp"
DEFAULT_DOCS = (
    FIRMWARE_DIR / "README.md",
    FIRMWARE_DIR / "docs/quickstart.md",
    FIRMWARE_DIR / "docs/bring-up.md",
    FIRMWARE_DIR / "docs/hardware-v2.md",
    FIRMWARE_DIR / "docs/ble-protocol.md",
    FIRMWARE_DIR / "docs/mobile-integration.md",
    FIRMWARE_DIR / "docs/validation-matrix.md",
    FIRMWARE_DIR / "docs/verification.md",
    FIRMWARE_DIR / "docs/troubleshooting.md",
    FIRMWARE_DIR / "docs/implementation-status.md",
    FIRMWARE_DIR / "tools/README.md",
)
DEFAULT_TOOLS = tuple(sorted((FIRMWARE_DIR / "tools").glob("*.py"))) + (
    FIRMWARE_DIR / "tools/requirements.txt",
)
REQUIRED_TOOL_NAMES = (
    "tools/analyze_sweep_csv.py",
    "tools/ble_probe.py",
    "tools/board_validation_report.py",
    "tools/capture_uart.py",
    "tools/describe_firmware_release.py",
    "tools/diagnose_debugger.py",
    "tools/flash_firmware.py",
    "tools/generate_sweep_fixture.py",
    "tools/readiness_report.py",
    "tools/run_verification.py",
    "tools/scan_advertising.py",
    "tools/test_ad5940_sweep.py",
    "tools/test_board_health.py",
    "tools/test_board_validation_report.py",
    "tools/test_build_artifacts.py",
    "tools/test_hardware_contract.py",
    "tools/test_pmic_battery.py",
    "tools/test_protocol_contract.py",
    "tools/test_protocol_payloads.py",
    "tools/test_readiness_report.py",
    "tools/test_release_package_fixture.py",
    "tools/test_release_matches_build.py",
    "tools/biomess_ble.py",
)


def run_text(command: list[str]) -> str:
    try:
        result = subprocess.run(command, cwd=REPO_ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except FileNotFoundError:
        return ""
    return result.stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_metadata() -> dict[str, str | bool]:
    status = run_text(["git", "status", "--short"])
    return {
        "commit": run_text(["git", "rev-parse", "HEAD"]),
        "branch": run_text(["git", "branch", "--show-current"]),
        "dirty": bool(status),
        "status_short": status,
    }


def nrfjprog_ids() -> list[str]:
    output = run_text(["nrfjprog", "--ids"])
    return [line.strip() for line in output.splitlines() if line.strip()]


def build_manifest(hex_path: Path, network_hex_path: Path | None, report_path: Path | None) -> dict[str, object]:
    missing_tools = [name for name in REQUIRED_TOOL_NAMES if not (FIRMWARE_DIR / name).exists()]
    if missing_tools:
        raise SystemExit("Missing required release tools: " + ", ".join(missing_tools))

    stat = hex_path.stat()
    network_image = None
    if network_hex_path is not None and network_hex_path.exists():
        network_stat = network_hex_path.stat()
        network_image = {
            "path": str(network_hex_path.relative_to(REPO_ROOT)),
            "size_bytes": network_stat.st_size,
            "sha256": sha256_file(network_hex_path),
        }
    return {
        "package_created_utc": datetime.now(timezone.utc).isoformat(),
        "repo_root": str(REPO_ROOT),
        "firmware_dir": str(FIRMWARE_DIR),
        "board": DEFAULT_BOARD,
        "image": {
            "path": str(hex_path.relative_to(REPO_ROOT)),
            "size_bytes": stat.st_size,
            "sha256": sha256_file(hex_path),
        },
        "network_core_image": network_image,
        "verification_report": str(report_path) if report_path else None,
        "nrfjprog_ids": nrfjprog_ids(),
        "git": git_metadata(),
        "flash_command": "west flash -d firmware/nrf5340_zephyr/build",
        "package_flash_command": (
            "python3 tools/flash_firmware.py "
            "--log /tmp/biomess_flash.log "
            "--summary-json /tmp/biomess_flash.json"
        ),
        "package_debugger_check_commands": [
            "python3 tools/preflight.py --require-board",
            "python3 tools/diagnose_debugger.py --require-board",
        ],
        "package_board_check_commands": [
            "python3 tools/scan_advertising.py --summary-json /tmp/biomess_advertising_scan.json",
            "python3 tools/ble_probe.py --summary-json /tmp/biomess_gatt_probe.json",
            "python3 tools/test_board_health.py",
            "python3 tools/test_pmic_battery.py",
            "python3 tools/test_led_command.py",
            (
                "python3 tools/test_ad5940_sweep.py "
                "--points 48 --start-hz 4000 --stop-hz 198000 "
                "--repetitions 5 --csv /tmp/biomess_sweep.csv"
            ),
            (
                "python3 tools/analyze_sweep_csv.py /tmp/biomess_sweep.csv "
                "--points 48 --expected-ohms 10000 "
                "--magnitude-tolerance-pct 20 --max-abs-phase-deg 15"
            ),
            "python3 tools/test_stored_sync.py",
        ],
        "full_board_verification_command": (
            "firmware/nrf5340_zephyr/.venv/bin/python "
            "firmware/nrf5340_zephyr/tools/run_verification.py "
            "--flash --uart --ble --report /tmp/biomess_board_verification.md"
        ),
        "docs": [str(path.relative_to(FIRMWARE_DIR)) for path in DEFAULT_DOCS if path.exists()],
        "tools": [str(path.relative_to(FIRMWARE_DIR)) for path in DEFAULT_TOOLS if path.exists()],
    }


def build_summary(manifest: dict[str, object]) -> str:
    image = manifest["image"]
    git = manifest["git"]
    assert isinstance(image, dict)
    assert isinstance(git, dict)

    debugger_ids = manifest["nrfjprog_ids"]
    assert isinstance(debugger_ids, list)
    debugger_text = ", ".join(str(item) for item in debugger_ids) if debugger_ids else "none detected"
    package_debugger_check_commands = manifest["package_debugger_check_commands"]
    package_board_check_commands = manifest["package_board_check_commands"]
    network_image = manifest.get("network_core_image")
    assert isinstance(package_debugger_check_commands, list)
    assert isinstance(package_board_check_commands, list)
    network_line = "- Network core image: not packaged"
    if isinstance(network_image, dict):
        network_line = (
            f"- Network core image: `{network_image['path']}` "
            f"(`{network_image['size_bytes']}` bytes, SHA256 `{network_image['sha256']}`)"
        )

    return "\n".join(
        [
            "# BioMess firmware handoff package",
            "",
            f"- Created UTC: `{manifest['package_created_utc']}`",
            f"- Image: `{image['path']}`",
            network_line,
            f"- Board: `{manifest['board']}`",
            f"- Size: `{image['size_bytes']}` bytes",
            f"- SHA256: `{image['sha256']}`",
            f"- Git branch: `{git.get('branch')}`",
            f"- Git commit: `{git.get('commit')}`",
            f"- Git dirty: `{str(git.get('dirty')).lower()}`",
            f"- nRF debugger IDs at packaging time: `{debugger_text}`",
            "",
            "## Before flashing",
            "",
            "The package can be inspected without programming the board. First install the Python dependencies and require a real Nordic/J-Link debugger:",
            "",
            "```bash",
            "python3 -m pip install -r tools/requirements.txt",
            "python3 tools/readiness_report.py --summary-json /tmp/biomess_package_readiness.json",
            *[str(command) for command in package_debugger_check_commands],
            "```",
            "",
            "Do not flash while `nrfjprog --ids` is empty. A USB serial endpoint alone is not enough; `readiness_report.py` prints the next command and `diagnose_debugger.py` separates serial visibility from debugger visibility.",
            "",
            "## Flash",
            "",
            "From the full repo checkout, prefer the Make target or direct flasher:",
            "",
            "```bash",
            "make firmware-flash",
            "```",
            "",
            "After extracting this zip, install the Python dependencies and run the package-local flasher against the included image:",
            "",
            "```bash",
            "python3 -m pip install -r tools/requirements.txt",
            str(manifest["package_flash_command"]),
            "```",
            "",
            "Use `--dry-run` first to print the exact command, image size, SHA256 and visible debugger IDs without programming:",
            "",
            "```bash",
            "python3 tools/flash_firmware.py --dry-run --summary-json /tmp/biomess_flash_dry_run.json",
            "```",
            "",
            "## Package-local board checks",
            "",
            "After flashing and rebooting the board, these commands run directly from the extracted package. Add `--address <ble-address>` to any BLE command when scanning finds more than one device.",
            "",
            "```bash",
            *[str(command) for command in package_board_check_commands],
            "```",
            "",
            "| Check | Expected evidence |",
            "| --- | --- |",
            "| BLE/GATT probe | Connects to `BioMess`, lists services `AF00`, `AF01`, `AF02`, `AF03`, prints `gatt_validation_ok=true` and writes `/tmp/biomess_gatt_probe.json`. |",
            "| Board health | `pmic_ok=true`, AD5940 ADIID `0x4144`, known CHIPID. |",
            "| PMIC battery | Voltage greater than `0` mV and percentage in `0..100`. |",
            "| LED command | Command `0x64` is acknowledged and the board LED blinks. |",
            "| AD5940 sweep | Captures `frequency_hz`, `magnitude_ohm`, `phase_deg` CSV rows. |",
            "| Sweep CSV analysis | Magnitude/phase are plausible for the known resistor or phantom load. |",
            "| Stored sync | Commands `0x07/0x08/0x09` return and clear stored records with valid CRC. |",
            "",
            "## Full board verification",
            "",
            "From the full repo checkout, the one-command board validation runner captures flash, UART and BLE evidence in one Markdown/JSON report:",
            "",
            "```bash",
            str(manifest["full_board_verification_command"]),
            "```",
            "",
            "Read `docs/quickstart.md` for the shortest command path, then `docs/bring-up.md` when validating a new PCB. Use `docs/validation-matrix.md` to map every firmware, BLE, PMIC, AD5940, sweep, mobile and handoff requirement to the expected evidence.",
            "",
        ]
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hex", type=Path, default=DEFAULT_HEX, help="Firmware hex image to package.")
    parser.add_argument(
        "--network-hex",
        type=Path,
        default=DEFAULT_NETWORK_HEX,
        help="Network-core hex image to package when present.",
    )
    parser.add_argument("--report", type=Path, help="Optional verification report to include.")
    parser.add_argument("--summary-json", type=Path, help="Optional JSON verification summary to include.")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--name", default="biomess-nrf5340-firmware")
    args = parser.parse_args()

    hex_path = args.hex.resolve()
    if not hex_path.exists():
        raise SystemExit(f"Firmware image does not exist: {hex_path}")
    network_hex_path = args.network_hex.resolve() if args.network_hex and args.network_hex.exists() else None
    if args.report is not None and not args.report.exists():
        raise SystemExit(f"Verification report does not exist: {args.report}")
    if args.summary_json is not None and not args.summary_json.exists():
        raise SystemExit(f"Verification summary JSON does not exist: {args.summary_json}")

    manifest = build_manifest(hex_path, network_hex_path, args.report.resolve() if args.report else None)
    manifest["verification_summary_json"] = str(args.summary_json.resolve()) if args.summary_json else None
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    package_dir = args.output_dir.resolve()
    package_dir.mkdir(parents=True, exist_ok=True)
    package_path = package_dir / f"{args.name}-{timestamp}.zip"

    manifest_text = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    summary_text = build_summary(manifest)
    ble_uuid_rows = describe_ble_contract.uuid_rows()
    ble_command_rows = describe_ble_contract.command_rows()
    ble_contract_summary = {
        "ok": describe_ble_contract.all_rows_ok(ble_uuid_rows) and describe_ble_contract.all_rows_ok(ble_command_rows),
        "device_name": "BioMess",
        "uuid_count": len(ble_uuid_rows),
        "command_count": len(ble_command_rows),
        "uuid_rows": ble_uuid_rows,
        "command_rows": ble_command_rows,
    }

    with zipfile.ZipFile(package_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(hex_path, "firmware/merged.hex")
        if network_hex_path is not None:
            archive.write(network_hex_path, "firmware/merged_CPUNET.hex")
        archive.writestr("manifest.json", manifest_text)
        archive.writestr("README.md", summary_text)
        archive.writestr("ble-contract-summary.json", json.dumps(ble_contract_summary, indent=2, sort_keys=True) + "\n")
        archive.writestr(
            "ble-contract-summary.md",
            "\n".join(
                [
                    "# BioMess BLE contract summary",
                    "",
                    "Generated during firmware package creation from firmware, Android and iOS sources.",
                    "",
                    f"- Device name: `{ble_contract_summary['device_name']}`",
                    f"- UUIDs checked: `{ble_contract_summary['uuid_count']}`",
                    f"- Commands checked: `{ble_contract_summary['command_count']}`",
                    f"- Contract OK: `{str(ble_contract_summary['ok']).lower()}`",
                    "",
                    "Run `firmware/nrf5340_zephyr/tools/describe_ble_contract.py` from the full repo for a fresh source-level summary.",
                    "",
                ]
            ),
        )
        if args.report is not None:
            archive.write(args.report.resolve(), "verification-report.md")
        if args.summary_json is not None:
            archive.write(args.summary_json.resolve(), "verification-summary.json")
        for doc_path in DEFAULT_DOCS:
            if doc_path.exists():
                archive_name = str(doc_path.relative_to(FIRMWARE_DIR))
                if archive_name == "README.md":
                    archive_name = "docs/firmware-README.md"
                archive.write(doc_path, archive_name)
        for tool_path in DEFAULT_TOOLS:
            if tool_path.exists():
                archive.write(tool_path, str(tool_path.relative_to(FIRMWARE_DIR)))

    print(f"release_package={package_path}")
    print(f"image_sha256={manifest['image']['sha256']}")
    print(f"release_package_bytes={package_path.stat().st_size}")
    print("release_package_ok=true")


if __name__ == "__main__":
    main()
