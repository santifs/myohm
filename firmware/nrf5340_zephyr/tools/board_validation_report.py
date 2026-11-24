#!/usr/bin/env python3
"""Create a board validation report from flash, runner, release and sweep artifacts."""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import zipfile
from pathlib import Path


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
UART_MARKERS = (
    "BLE advertising as BioMess",
    "AD5940 GPIOs:",
    "Ready. Connect with the BioMess app",
)
BLE_PROBE_MARKERS = (
    "advertised_name_validation_ok=true",
    "gatt_validation_ok=true",
    "ble_probe_ok=true",
)
BLE_ADVERTISING_MARKERS = (
    "advertised_name_validation_ok=true",
    "advertised_service_validation_ok=true",
    "advertising_scan_ok=true",
)


def load_json(path: Path) -> dict[str, object]:
    if not path.exists():
        raise SystemExit(f"JSON file does not exist: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def status(ok: bool | None) -> str:
    if ok is True:
        return "PASS"
    if ok is False:
        return "FAIL"
    return "INFO"


def add_check(checks: list[dict[str, object]], area: str, ok: bool | None, evidence: str, detail: str) -> None:
    checks.append({"area": area, "ok": ok, "evidence": evidence, "detail": detail})


def step_map(summary: dict[str, object]) -> dict[str, dict[str, object]]:
    steps = summary.get("steps")
    if not isinstance(steps, list):
        return {}
    mapped: dict[str, dict[str, object]] = {}
    for step in steps:
        if isinstance(step, dict) and isinstance(step.get("label"), str):
            mapped[str(step["label"])] = step
    return mapped


def step_ok(summary: dict[str, object] | None, label: str) -> bool:
    if summary is None:
        return False
    step = step_map(summary).get(label)
    return isinstance(step, dict) and step.get("ok") is True


def step_stdout(summary: dict[str, object] | None, label: str) -> str:
    if summary is None:
        return ""
    step = step_map(summary).get(label)
    if not isinstance(step, dict):
        return ""
    stdout = step.get("stdout_tail")
    return stdout if isinstance(stdout, str) else ""


def inspect_step_markers(
    summary: dict[str, object],
    checks: list[dict[str, object]],
    area: str,
    step_label: str,
    markers: tuple[str, ...],
    evidence: str,
) -> None:
    stdout = step_stdout(summary, step_label)
    missing = [marker for marker in markers if marker not in stdout]
    add_check(checks, area, not missing, evidence, f"missing_markers={','.join(missing) or 'none'}")


def inspect_ble_probe_summary(path: Path, checks: list[dict[str, object]]) -> bool:
    if not path.exists():
        add_check(checks, "BLE/GATT probe JSON evidence", False, str(path), "missing JSON evidence")
        return False
    data = load_json(path)
    expected_name = data.get("advertised_name_expected")
    actual_name = data.get("advertised_name")
    name_enabled = data.get("advertised_name_validation_enabled") is True
    name_failures = data.get("advertised_name_validation_failures")
    gatt_failures = data.get("validation_failures")
    ok = (
        data.get("ok") is True
        and expected_name == "BioMess"
        and (not name_enabled or actual_name == expected_name)
        and isinstance(name_failures, list)
        and not name_failures
        and isinstance(gatt_failures, list)
        and not gatt_failures
    )
    detail = (
        f"ok={data.get('ok')} advertised_name={actual_name} expected={expected_name} "
        f"name_validation_enabled={name_enabled} name_failures={len(name_failures) if isinstance(name_failures, list) else 'invalid'} "
        f"gatt_failures={len(gatt_failures) if isinstance(gatt_failures, list) else 'invalid'}"
    )
    add_check(checks, "BLE/GATT probe JSON evidence", ok, str(path), detail)
    return ok


def inspect_advertising_summary(path: Path, checks: list[dict[str, object]]) -> bool:
    if not path.exists():
        add_check(checks, "BLE advertising JSON evidence", False, str(path), "missing JSON evidence")
        return False
    data = load_json(path)
    name_failures = data.get("name_validation_failures")
    service_failures = data.get("service_validation_failures")
    matches = data.get("matches")
    has_biomess_match = False
    if isinstance(matches, list):
        for match in matches:
            if not isinstance(match, dict):
                continue
            if match.get("local_name") == "BioMess" and match.get("advertises_biomess_service") is True:
                has_biomess_match = True
                break
    ok = (
        data.get("ok") is True
        and isinstance(matches, list)
        and bool(matches)
        and has_biomess_match
        and isinstance(name_failures, list)
        and not name_failures
        and isinstance(service_failures, list)
        and not service_failures
    )
    detail = (
        f"ok={data.get('ok')} match_count={data.get('match_count')} "
        f"has_biomess_match={has_biomess_match} "
        f"name_failures={len(name_failures) if isinstance(name_failures, list) else 'invalid'} "
        f"service_failures={len(service_failures) if isinstance(service_failures, list) else 'invalid'}"
    )
    add_check(checks, "BLE advertising JSON evidence", ok, str(path), detail)
    return ok


def inspect_flash(path: Path, checks: list[dict[str, object]]) -> dict[str, object]:
    data = load_json(path)
    ok = data.get("ok") is True and data.get("dry_run") is False
    detail = (
        f"exit_code={data.get('exit_code')} dry_run={data.get('dry_run')} "
        f"hex_sha256={data.get('hex_sha256')} ids={data.get('nrfjprog_ids')}"
    )
    add_check(checks, "flash", ok, str(path), detail)
    return data


def inspect_ble_evidence(data: dict[str, object], checks: list[dict[str, object]], evidence: str) -> None:
    advertising_summary = data.get("advertising_summary_json")
    if isinstance(advertising_summary, str) and inspect_advertising_summary(Path(advertising_summary), checks):
        pass
    else:
        inspect_step_markers(data, checks, "BLE advertising stdout evidence", "BLE advertising scan", BLE_ADVERTISING_MARKERS, evidence)
    ble_summary = data.get("ble_probe_summary_json")
    if isinstance(ble_summary, str) and inspect_ble_probe_summary(Path(ble_summary), checks):
        pass
    else:
        inspect_step_markers(data, checks, "BLE/GATT probe stdout evidence", "BLE/GATT probe", BLE_PROBE_MARKERS, evidence)


def inspect_verification(
    path: Path,
    checks: list[dict[str, object]],
    require_full_board: bool,
    require_ble_board: bool,
) -> dict[str, object]:
    data = load_json(path)
    add_check(checks, "verification runner", data.get("ok") is True, str(path), f"steps={len(step_map(data))}")

    if require_ble_board:
        add_check(checks, "BLE-board mode", data.get("ble_enabled") is True, str(path), f"ble_enabled={data.get('ble_enabled')}")
        steps = step_map(data)
        for label in BLE_BOARD_STEPS:
            step = steps.get(label)
            ok = isinstance(step, dict) and step.get("ok") is True
            detail = "missing step" if step is None else f"exit_code={step.get('exit_code')}"
            add_check(checks, label, ok, str(path), detail)
        inspect_ble_evidence(data, checks, str(path))

    if require_full_board:
        flags = [
            ("flash_requested", data.get("flash_requested") is True),
            ("uart_capture_enabled", data.get("uart_capture_enabled") is True),
            ("ble_enabled", data.get("ble_enabled") is True),
        ]
        for name, ok in flags:
            add_check(checks, "full-board mode", ok, str(path), f"{name}={data.get(name)}")

        steps = step_map(data)
        for label in FULL_BOARD_STEPS:
            step = steps.get(label)
            ok = isinstance(step, dict) and step.get("ok") is True
            detail = "missing step" if step is None else f"exit_code={step.get('exit_code')}"
            add_check(checks, label, ok, str(path), detail)
        if not require_ble_board:
            inspect_ble_evidence(data, checks, str(path))
    return data


def inspect_release(path: Path, checks: list[dict[str, object]]) -> dict[str, object]:
    if not path.exists():
        raise SystemExit(f"Release package does not exist: {path}")
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        manifest = json.loads(archive.read("manifest.json").decode("utf-8"))
        image = manifest.get("image")
        if not isinstance(image, dict):
            add_check(checks, "release package", False, str(path), "manifest.json missing image")
            return manifest
        firmware = archive.read("firmware/merged.hex")
        expected_sha = image.get("sha256")
        actual_sha = sha256_bytes(firmware)
        required = {
            "firmware/merged.hex",
            "firmware/merged_CPUNET.hex",
            "manifest.json",
            "ble-contract-summary.json",
            "ble-contract-summary.md",
            "tools/analyze_sweep_csv.py",
            "tools/scan_advertising.py",
            "tools/describe_firmware_release.py",
            "tools/flash_firmware.py",
            "tools/generate_sweep_fixture.py",
            "tools/board_validation_report.py",
            "tools/requirements.txt",
            "tools/test_build_artifacts.py",
            "tools/test_hardware_contract.py",
            "tools/test_pmic_battery.py",
            "tools/test_protocol_contract.py",
            "tools/test_protocol_payloads.py",
            "tools/verify_firmware_release.py",
            "docs/hardware-v2.md",
            "docs/verification.md",
            "docs/mobile-integration.md",
        }
        missing = sorted(required - names)
        network_image = manifest.get("network_core_image")
        network_ok = False
        if isinstance(network_image, dict) and "firmware/merged_CPUNET.hex" in names:
            network = archive.read("firmware/merged_CPUNET.hex")
            network_ok = (
                sha256_bytes(network) == network_image.get("sha256")
                and len(network) == network_image.get("size_bytes")
            )
        ok = not missing and actual_sha == expected_sha and len(firmware) == image.get("size_bytes") and network_ok
        detail = f"entries={len(names)} missing={','.join(missing) or 'none'} sha256={actual_sha} network_ok={network_ok}"
        add_check(checks, "release package", ok, str(path), detail)
        return manifest


def inspect_sweep(path: Path, checks: list[dict[str, object]]) -> None:
    if not path.exists():
        raise SystemExit(f"Sweep CSV does not exist: {path}")
    with path.open(newline="") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames is None:
            add_check(checks, "sweep csv", False, str(path), "missing header")
            return
        required = {"frequency_hz", "magnitude_ohm", "phase_deg"}
        missing = required - set(reader.fieldnames)
        rows: list[tuple[float, float, float]] = []
        for row in reader:
            try:
                point = tuple(float(row[column]) for column in ("frequency_hz", "magnitude_ohm", "phase_deg"))
            except (KeyError, TypeError, ValueError):
                add_check(checks, "sweep csv", False, str(path), "invalid numeric row")
                return
            rows.append(point)

    finite = all(all(math.isfinite(value) for value in point) for point in rows)
    positive = all(point[0] > 0.0 and point[1] > 0.0 for point in rows)
    ok = not missing and bool(rows) and finite and positive
    detail = f"rows={len(rows)} missing={','.join(sorted(missing)) or 'none'} finite={finite} positive={positive}"
    add_check(checks, "sweep csv", ok, str(path), detail)


def inspect_uart(path: Path, checks: list[dict[str, object]]) -> None:
    if not path.exists():
        raise SystemExit(f"UART log does not exist: {path}")
    text = path.read_text(encoding="utf-8", errors="replace")
    missing = [marker for marker in UART_MARKERS if marker not in text]
    add_check(checks, "uart log", not missing, str(path), f"missing={','.join(missing) or 'none'}")


def render_markdown(checks: list[dict[str, object]], require_full_board: bool, require_ble_board: bool) -> str:
    lines = [
        "# BioMess board validation report",
        "",
        f"- Created UTC: `{datetime.now(timezone.utc).isoformat()}`",
        f"- Full-board mode: `{str(require_full_board).lower()}`",
        f"- BLE-board mode: `{str(require_ble_board).lower()}`",
        "",
        "| Area | Status | Evidence | Detail |",
        "| --- | --- | --- | --- |",
    ]
    for check in checks:
        lines.append(
            f"| {check['area']} | {status(check['ok'])} | `{check['evidence']}` | {str(check['detail']).replace('|', '/')} |"
        )
    failed = [check for check in checks if check["ok"] is False]
    lines.extend(["", "## Result", "", f"`board_validation_ok={'false' if failed else 'true'}`", ""])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flash-json", type=Path, help="JSON summary from flash_firmware.py.")
    parser.add_argument("--verification-json", type=Path, help="JSON summary from run_verification.py.")
    parser.add_argument("--release-package", type=Path, help="Firmware handoff zip to include in evidence.")
    parser.add_argument("--sweep-csv", type=Path, help="Captured AD5940 sweep CSV to include in evidence.")
    parser.add_argument("--uart-log", type=Path, help="Captured UART log to include in evidence.")
    parser.add_argument("--require-ble-board", action="store_true", help="Require BLE, PMIC, LED, AD5940 sweep and stored-sync checks, without UART.")
    parser.add_argument("--require-full-board", action="store_true", help="Require flash, UART, BLE, PMIC, AD5940 and sync checks.")
    parser.add_argument("--output", type=Path, required=True, help="Markdown report path.")
    parser.add_argument("--summary-json", type=Path, help="Machine-readable summary path.")
    args = parser.parse_args()

    checks: list[dict[str, object]] = []
    verification_data: dict[str, object] | None = None
    if args.verification_json:
        verification_data = inspect_verification(args.verification_json, checks, args.require_full_board, args.require_ble_board)
    elif args.require_full_board or args.require_ble_board:
        add_check(checks, "verification runner", False, "missing", "pass --verification-json from run_verification.py")

    if args.flash_json:
        inspect_flash(args.flash_json, checks)
    elif args.require_full_board:
        if step_ok(verification_data, "firmware flash"):
            add_check(checks, "flash", True, str(args.verification_json), "covered by run_verification.py firmware flash step")
        else:
            add_check(checks, "flash", False, "missing", "pass --flash-json or a --verification-json with firmware flash")

    if args.release_package:
        inspect_release(args.release_package, checks)
    if args.sweep_csv:
        inspect_sweep(args.sweep_csv, checks)
    if args.uart_log:
        inspect_uart(args.uart_log, checks)

    if not checks:
        raise SystemExit("No evidence provided. Pass at least one --*-json, --release-package, --sweep-csv or --uart-log.")

    failed = [check for check in checks if check["ok"] is False]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render_markdown(checks, args.require_full_board, args.require_ble_board), encoding="utf-8")

    summary = {
        "ok": not failed,
        "require_full_board": args.require_full_board,
        "require_ble_board": args.require_ble_board,
        "output": str(args.output),
        "checks": checks,
        "failed_checks": len(failed),
    }
    if args.summary_json:
        args.summary_json.parent.mkdir(parents=True, exist_ok=True)
        args.summary_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"board_validation_report={args.output}")
    if args.summary_json:
        print(f"board_validation_summary_json={args.summary_json}")
    print(f"board_validation_failed_checks={len(failed)}")
    print(f"board_validation_ok={'false' if failed else 'true'}")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
