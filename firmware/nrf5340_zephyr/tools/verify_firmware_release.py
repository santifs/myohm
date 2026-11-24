#!/usr/bin/env python3
"""Verify a BioMess nRF5340 firmware handoff package."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


REQUIRED_ENTRIES = (
    "firmware/merged.hex",
    "firmware/merged_CPUNET.hex",
    "manifest.json",
    "README.md",
    "ble-contract-summary.json",
    "ble-contract-summary.md",
    "docs/firmware-README.md",
    "docs/quickstart.md",
    "docs/bring-up.md",
    "docs/hardware-v2.md",
    "docs/ble-protocol.md",
    "docs/mobile-integration.md",
    "docs/validation-matrix.md",
    "docs/verification.md",
    "docs/troubleshooting.md",
    "docs/implementation-status.md",
    "tools/README.md",
    "tools/analyze_sweep_csv.py",
    "tools/ble_probe.py",
    "tools/board_validation_report.py",
    "tools/capture_uart.py",
    "tools/describe_ble_contract.py",
    "tools/describe_firmware_release.py",
    "tools/diagnose_debugger.py",
    "tools/flash_firmware.py",
    "tools/generate_sweep_fixture.py",
    "tools/package_firmware_release.py",
    "tools/preflight.py",
    "tools/readiness_report.py",
    "tools/requirements.txt",
    "tools/run_verification.py",
    "tools/scan_advertising.py",
    "tools/setup_python_env.py",
    "tools/summarize_verification.py",
    "tools/test_ad5940_sweep.py",
    "tools/test_auto_mode.py",
    "tools/test_board_health.py",
    "tools/test_board_validation_report.py",
    "tools/test_build_artifacts.py",
    "tools/test_docs_links.py",
    "tools/test_hardware_contract.py",
    "tools/test_led_command.py",
    "tools/test_pmic_battery.py",
    "tools/test_protocol_contract.py",
    "tools/test_protocol_payloads.py",
    "tools/test_python_syntax.py",
    "tools/test_readiness_report.py",
    "tools/test_release_package_fixture.py",
    "tools/test_release_matches_build.py",
    "tools/test_stored_sync.py",
    "tools/test_uart_boot_log.py",
    "tools/verify_firmware_release.py",
    "tools/biomess_ble.py",
)


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def load_json_entry(archive: zipfile.ZipFile, name: str) -> dict[str, object]:
    try:
        return json.loads(archive.read(name).decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{name} is not valid JSON: {exc}") from exc


def verify_python_tool_syntax(archive: zipfile.ZipFile, names: set[str]) -> int:
    python_tools = sorted(name for name in names if name.startswith("tools/") and name.endswith(".py"))
    if not python_tools:
        raise SystemExit("Release package does not include package-local Python tools")
    for name in python_tools:
        source = archive.read(name).decode("utf-8")
        try:
            compile(source, name, "exec")
        except SyntaxError as exc:
            raise SystemExit(f"Python syntax error in release package tool {name}: {exc}") from exc
    return len(python_tools)


def verify_package_local_flasher(package: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="biomess_release_extract_") as temp:
        temp_dir = Path(temp)
        with zipfile.ZipFile(package) as archive:
            archive.extractall(temp_dir)
        summary_json = temp_dir / "flash-dry-run.json"
        command = [
            sys.executable,
            str(temp_dir / "tools/flash_firmware.py"),
            "--hex",
            str(temp_dir / "firmware/merged.hex"),
            "--dry-run",
            "--summary-json",
            str(summary_json),
        ]
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode != 0:
            raise SystemExit("Package-local flasher dry-run failed:\n" + result.stdout[-4000:])
        summary = json.loads(summary_json.read_text(encoding="utf-8"))
        if summary.get("ok") is not True or summary.get("dry_run") is not True:
            raise SystemExit("Package-local flasher dry-run summary must have ok=true and dry_run=true")
        if Path(str(summary.get("hex_path"))).name != "merged.hex":
            raise SystemExit("Package-local flasher dry-run did not target firmware/merged.hex")


def verify_package_local_tool_help(package: Path) -> None:
    tools = [
        "ble_probe.py",
        "scan_advertising.py",
        "test_board_health.py",
        "test_pmic_battery.py",
        "test_led_command.py",
        "test_ad5940_sweep.py",
        "analyze_sweep_csv.py",
        "test_stored_sync.py",
        "readiness_report.py",
    ]
    with tempfile.TemporaryDirectory(prefix="biomess_release_tools_") as temp:
        temp_dir = Path(temp)
        with zipfile.ZipFile(package) as archive:
            archive.extractall(temp_dir)
        for tool in tools:
            command = [sys.executable, str(temp_dir / "tools" / tool), "--help"]
            result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if result.returncode != 0:
                raise SystemExit(f"Package-local tool --help failed for {tool}:\n{result.stdout[-4000:]}")


def verify_package_local_readiness(package: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="biomess_release_readiness_") as temp:
        temp_dir = Path(temp)
        with zipfile.ZipFile(package) as archive:
            archive.extractall(temp_dir)
        summary_json = temp_dir / "readiness.json"
        command = [
            sys.executable,
            str(temp_dir / "tools/readiness_report.py"),
            "--summary-json",
            str(summary_json),
            "--require-handoff",
        ]
        result = subprocess.run(command, cwd=temp_dir, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode != 0:
            raise SystemExit("Package-local readiness report failed:\n" + result.stdout[-4000:])
        summary = json.loads(summary_json.read_text(encoding="utf-8"))
        if summary.get("handoff_ready") is not True:
            raise SystemExit("Package-local readiness summary must have handoff_ready=true")
        if Path(str(summary.get("build_hex"))).name != "merged.hex":
            raise SystemExit("Package-local readiness summary did not target firmware/merged.hex")


def verify_package_local_dependency_hints(archive: zipfile.ZipFile) -> None:
    for name in ("tools/biomess_ble.py", "tools/preflight.py", "tools/capture_uart.py"):
        source = archive.read(name).decode("utf-8")
        if 'Path(__file__).resolve().parent / "requirements.txt"' not in source:
            raise SystemExit(f"{name} must resolve requirements.txt relative to the extracted package")
        if "firmware/nrf5340_zephyr/tools/requirements.txt" in source:
            raise SystemExit(f"{name} must not hardcode repo-only requirements.txt paths")


def step_labels(summary: dict[str, object]) -> set[str]:
    steps = summary.get("steps")
    if not isinstance(steps, list):
        return set()
    return {str(step.get("label")) for step in steps if isinstance(step, dict) and step.get("ok") is True}


def verify_package(package: Path, require_report: bool, require_summary_json: bool, require_build_summary: bool) -> None:
    if not package.exists():
        raise SystemExit(f"Release package does not exist: {package}")
    missing: list[str] = []
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        name_set = set(names)
        duplicates = sorted(name for name in name_set if names.count(name) > 1)
        if duplicates:
            raise SystemExit("Duplicate entries in release package: " + ", ".join(duplicates))

        for entry in REQUIRED_ENTRIES:
            if entry not in name_set:
                missing.append(entry)
        if require_report and "verification-report.md" not in name_set:
            missing.append("verification-report.md")
        if require_summary_json and "verification-summary.json" not in name_set:
            missing.append("verification-summary.json")
        if missing:
            raise SystemExit("Missing release package entries: " + ", ".join(missing))

        manifest = load_json_entry(archive, "manifest.json")
        if manifest.get("board") != "biomess_nrf5340/nrf5340/cpuapp":
            raise SystemExit("manifest.json board must be biomess_nrf5340/nrf5340/cpuapp")
        image = manifest.get("image")
        if not isinstance(image, dict):
            raise SystemExit("manifest.json missing image object")

        merged_hex = archive.read("firmware/merged.hex")
        actual_sha = sha256_bytes(merged_hex)
        expected_sha = image.get("sha256")
        expected_size = image.get("size_bytes")
        if actual_sha != expected_sha:
            raise SystemExit(f"Firmware SHA256 mismatch: manifest={expected_sha} actual={actual_sha}")
        if len(merged_hex) != expected_size:
            raise SystemExit(f"Firmware size mismatch: manifest={expected_size} actual={len(merged_hex)}")
        network_image = manifest.get("network_core_image")
        if not isinstance(network_image, dict):
            raise SystemExit("manifest.json missing network_core_image object")
        network_hex = archive.read("firmware/merged_CPUNET.hex")
        network_actual_sha = sha256_bytes(network_hex)
        network_expected_sha = network_image.get("sha256")
        network_expected_size = network_image.get("size_bytes")
        if network_actual_sha != network_expected_sha:
            raise SystemExit(
                f"Network-core firmware SHA256 mismatch: manifest={network_expected_sha} actual={network_actual_sha}"
            )
        if len(network_hex) != network_expected_size:
            raise SystemExit(
                f"Network-core firmware size mismatch: manifest={network_expected_size} actual={len(network_hex)}"
            )

        summary = None
        if "verification-summary.json" in name_set:
            summary = load_json_entry(archive, "verification-summary.json")
            if "steps" not in summary or "ok" not in summary:
                raise SystemExit("verification-summary.json missing steps/ok fields")
        if require_build_summary:
            if summary is None:
                raise SystemExit("Build-backed release verification requires verification-summary.json")
            labels = step_labels(summary)
            for label in ("firmware build", "firmware build artifacts"):
                if label not in labels:
                    raise SystemExit(f"verification-summary.json missing successful build step: {label}")
        ble_summary = load_json_entry(archive, "ble-contract-summary.json")
        if ble_summary.get("ok") is not True:
            raise SystemExit("ble-contract-summary.json must have ok=true")
        if ble_summary.get("uuid_count") != 16 or ble_summary.get("command_count") != 12:
            raise SystemExit("ble-contract-summary.json has unexpected UUID/command counts")

        docs = manifest.get("docs")
        if not isinstance(docs, list):
            raise SystemExit("manifest.json docs list missing")
        for doc in ["docs/quickstart.md", "docs/mobile-integration.md", "docs/validation-matrix.md"]:
            if doc not in docs:
                raise SystemExit(f"manifest.json docs list must include {doc}")
        tools = manifest.get("tools")
        if not isinstance(tools, list) or "tools/flash_firmware.py" not in tools:
            raise SystemExit("manifest.json tools list must include tools/flash_firmware.py")
        for tool in [
            "tools/analyze_sweep_csv.py",
            "tools/ble_probe.py",
            "tools/scan_advertising.py",
            "tools/describe_firmware_release.py",
            "tools/generate_sweep_fixture.py",
            "tools/readiness_report.py",
            "tools/board_validation_report.py",
            "tools/test_ad5940_sweep.py",
            "tools/test_board_health.py",
            "tools/test_build_artifacts.py",
            "tools/test_hardware_contract.py",
            "tools/test_pmic_battery.py",
            "tools/test_protocol_contract.py",
            "tools/test_protocol_payloads.py",
            "tools/test_readiness_report.py",
            "tools/test_release_matches_build.py",
            "tools/biomess_ble.py",
        ]:
            if tool not in tools:
                raise SystemExit(f"manifest.json tools list must include {tool}")
        if "package_flash_command" not in manifest:
            raise SystemExit("manifest.json missing package_flash_command")
        debugger_commands = manifest.get("package_debugger_check_commands")
        if not isinstance(debugger_commands, list):
            raise SystemExit("manifest.json missing package_debugger_check_commands list")
        for command in [
            "python3 tools/preflight.py --require-board",
            "python3 tools/diagnose_debugger.py --require-board",
        ]:
            if not any(command in str(item) for item in debugger_commands):
                raise SystemExit(f"manifest.json package_debugger_check_commands missing {command}")
        board_commands = manifest.get("package_board_check_commands")
        if not isinstance(board_commands, list):
            raise SystemExit("manifest.json missing package_board_check_commands list")
        for command in [
            "python3 tools/ble_probe.py",
            "python3 tools/scan_advertising.py",
            "python3 tools/test_board_health.py",
            "python3 tools/test_pmic_battery.py",
            "python3 tools/test_led_command.py",
            "python3 tools/test_ad5940_sweep.py",
            "python3 tools/analyze_sweep_csv.py",
            "python3 tools/test_stored_sync.py",
        ]:
            if not any(command in str(item) for item in board_commands):
                raise SystemExit(f"manifest.json package_board_check_commands missing {command}")
        readme = archive.read("README.md").decode("utf-8")
        for token in [
            "Before flashing",
            "Network core image",
            "tools/preflight.py --require-board",
            "tools/diagnose_debugger.py --require-board",
            "tools/readiness_report.py",
            "biomess_package_readiness.json",
            "Do not flash while `nrfjprog --ids` is empty",
            "Package-local board checks",
            "docs/quickstart.md",
            "docs/validation-matrix.md",
            "tools/ble_probe.py",
            "tools/scan_advertising.py",
            "tools/test_board_health.py",
            "tools/test_pmic_battery.py",
            "tools/test_ad5940_sweep.py",
            "tools/analyze_sweep_csv.py",
            "tools/test_stored_sync.py",
            "--address <ble-address>",
            "BioMess",
            "AF00",
            "gatt_validation_ok=true",
            "biomess_advertising_scan.json",
            "biomess_gatt_probe.json",
            "pmic_ok=true",
            "0x4144",
            "frequency_hz",
            "magnitude_ohm",
            "phase_deg",
        ]:
            if token not in readme:
                raise SystemExit(f"README.md missing package-local board check guidance: {token}")
        python_tools_checked = verify_python_tool_syntax(archive, name_set)
        verify_package_local_dependency_hints(archive)
        verify_package_local_flasher(package)
        verify_package_local_tool_help(package)
        verify_package_local_readiness(package)

    print(f"release_package={package}")
    print(f"release_entries={len(name_set)}")
    print(f"firmware_bytes={len(merged_hex)}")
    print(f"firmware_sha256={actual_sha}")
    print(f"release_python_tools_checked={python_tools_checked}")
    print("release_package_flasher_dry_run_ok=true")
    print("release_package_tool_help_ok=true")
    print("release_package_readiness_ok=true")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("packages", type=Path, nargs="+")
    parser.add_argument("--require-report", action="store_true", help="Require verification-report.md in the package.")
    parser.add_argument("--require-summary-json", action="store_true", help="Require verification-summary.json in the package.")
    parser.add_argument("--require-build-summary", action="store_true", help="Require firmware build and build-artifact steps in verification-summary.json.")
    args = parser.parse_args()

    for package in args.packages:
        verify_package(package, args.require_report, args.require_summary_json, args.require_build_summary)
    print("release_package_verify_ok=true")


if __name__ == "__main__":
    main()
