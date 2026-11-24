#!/usr/bin/env python3
"""Run the BioMess firmware verification flow from one command."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
FIRMWARE_DIR = REPO_ROOT / "firmware/nrf5340_zephyr"
TOOLS_DIR = FIRMWARE_DIR / "tools"
ANDROID_DIR = REPO_ROOT / "mobile/android"
IOS_PACKAGE_DIR = REPO_ROOT / "mobile/ios/VolumHealthAppPackage"
DEFAULT_NCS_DIR = Path("/opt/nordic/ncs/v3.3.0")
DEFAULT_WEST = Path("/opt/nordic/ncs/toolchains/0c0f19d91c/bin/west")
DEFAULT_ZEPHYR_SDK = Path("/opt/nordic/ncs/toolchains/0c0f19d91c/opt/zephyr-sdk")
DEFAULT_BOARD = "biomess_nrf5340/nrf5340/cpuapp"


def append_report(report: list[str] | None, text: str = "") -> None:
    if report is not None:
        report.append(text)


def run(
    label: str,
    command: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    report: list[str] | None = None,
    summary_steps: list[dict[str, object]] | None = None,
) -> None:
    print(f"\n== {label} ==", flush=True)
    command_text = " ".join(command)
    print(command_text, flush=True)

    append_report(report, f"## {label}")
    append_report(report)
    append_report(report, "```bash")
    append_report(report, command_text)
    append_report(report, "```")
    append_report(report)

    child_env = dict(env or os.environ)
    child_env["PYTHONDONTWRITEBYTECODE"] = "1"

    started = time.monotonic()
    result = subprocess.run(
        command,
        cwd=str(cwd or REPO_ROOT),
        env=child_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    duration_s = time.monotonic() - started

    if result.stdout:
        print(result.stdout, end="", flush=True)

    append_report(report, f"Exit code: `{result.returncode}`")
    append_report(report)
    append_report(report, "```text")
    append_report(report, (result.stdout or "").rstrip())
    append_report(report, "```")
    append_report(report)

    if summary_steps is not None:
        stdout = result.stdout or ""
        summary_steps.append(
            {
                "label": label,
                "command": command,
                "cwd": str(cwd or REPO_ROOT),
                "exit_code": result.returncode,
                "duration_seconds": round(duration_s, 3),
                "ok": result.returncode == 0,
                "stdout_tail": stdout[-4000:],
            }
        )

    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, command, output=result.stdout)


def zephyr_env(zephyr_sdk: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["ZEPHYR_TOOLCHAIN_VARIANT"] = "zephyr"
    env["ZEPHYR_SDK_INSTALL_DIR"] = str(zephyr_sdk)
    return env


def android_env() -> dict[str, str]:
    env = os.environ.copy()
    if sys.platform == "darwin":
        try:
            result = subprocess.run(
                ["/usr/libexec/java_home", "-v", "17+"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=True,
            )
        except (FileNotFoundError, subprocess.CalledProcessError):
            return env

        java_home = result.stdout.strip()
        if java_home:
            env["JAVA_HOME"] = java_home
            env["PATH"] = str(Path(java_home) / "bin") + os.pathsep + env.get("PATH", "")
    return env


def build_command(west: Path, build_dir: Path, board: str) -> list[str]:
    return [
        str(west),
        "build",
        "--pristine=auto",
        "-b",
        board,
        "-s",
        str(FIRMWARE_DIR),
        "-d",
        str(build_dir),
        "--",
        f"-DBOARD_ROOT={FIRMWARE_DIR}",
    ]


def flash_command(west: Path, build_dir: Path) -> list[str]:
    return [str(west), "flash", "-d", str(build_dir)]


def python_tool(script: str, *args: str) -> list[str]:
    return [sys.executable, str(TOOLS_DIR / script), *args]


def ble_args(address: str | None, name_prefix: str) -> list[str]:
    args = ["--name-prefix", name_prefix]
    if address:
        args.extend(["--address", address])
    return args


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true", help="Do not run west build.")
    parser.add_argument("--flash", action="store_true", help="Flash the existing/built image before BLE tests.")
    parser.add_argument("--ble", action="store_true", help="Run BLE board tests after offline checks.")
    parser.add_argument("--uart", action="store_true", help="Capture UART logs after optional flash/build.")
    parser.add_argument("--mobile", action="store_true", help="Run both Android and iOS mobile compatibility builds.")
    parser.add_argument("--mobile-tests", action="store_true", help="Run Android core-ble unit tests and iOS Swift package tests.")
    parser.add_argument("--android", action="store_true", help="Run Android :core-ble Kotlin compile.")
    parser.add_argument("--ios", action="store_true", help="Run iOS Swift package build.")
    parser.add_argument("--include-auto", action="store_true", help="Also run the 60s auto-mode test.")
    parser.add_argument("--address", help="BLE address/identifier. If omitted, scripts scan for BioMess.")
    parser.add_argument("--name-prefix", default="BioMess")
    parser.add_argument("--serial-port", help="UART serial port. If omitted, capture_uart.py auto-detects.")
    parser.add_argument("--uart-seconds", type=float, default=10.0)
    parser.add_argument("--uart-log", type=Path, default=Path("/tmp/biomess_uart.log"))
    parser.add_argument("--fixture-sweep-csv", default="/tmp/biomess_sweep_fixture.csv")
    parser.add_argument("--sweep-csv", default="/tmp/biomess_sweep.csv")
    parser.add_argument("--advertising-summary-json", type=Path, help="Write passive BLE advertising JSON evidence.")
    parser.add_argument("--ble-summary-json", type=Path, help="Write BLE/GATT probe JSON evidence. Defaults next to --report or /tmp.")
    parser.add_argument("--board", default=DEFAULT_BOARD, help="Zephyr board target.")
    parser.add_argument("--west", type=Path, default=DEFAULT_WEST)
    parser.add_argument("--zephyr-sdk", type=Path, default=DEFAULT_ZEPHYR_SDK)
    parser.add_argument("--ncs-dir", type=Path, default=DEFAULT_NCS_DIR)
    parser.add_argument("--build-dir", type=Path, default=FIRMWARE_DIR / "build")
    parser.add_argument("--report", type=Path, help="Write a Markdown verification report to this path.")
    parser.add_argument("--summary-json", type=Path, help="Write a machine-readable JSON summary. Defaults to report path with .json suffix.")
    args = parser.parse_args()

    started_utc = datetime.now(timezone.utc).isoformat()
    summary_json = args.summary_json
    if summary_json is None and args.report is not None:
        summary_json = args.report.with_suffix(".json")
    ble_summary_json = args.ble_summary_json
    if ble_summary_json is None:
        ble_summary_json = args.report.with_name("biomess_gatt_probe.json") if args.report else Path("/tmp/biomess_gatt_probe.json")
    advertising_summary_json = args.advertising_summary_json
    if advertising_summary_json is None:
        advertising_summary_json = args.report.with_name("biomess_advertising_scan.json") if args.report else Path("/tmp/biomess_advertising_scan.json")

    summary: dict[str, object] = {
        "started_utc": started_utc,
        "finished_utc": None,
        "ok": False,
        "repository": str(REPO_ROOT),
        "firmware_dir": str(FIRMWARE_DIR),
        "board": args.board,
        "zephyr_sdk": str(args.zephyr_sdk),
        "ble_enabled": args.ble,
        "uart_capture_enabled": args.uart,
        "flash_requested": args.flash,
        "android_check_enabled": args.mobile or args.android,
        "ios_check_enabled": args.mobile or args.ios,
        "mobile_tests_enabled": args.mobile_tests,
        "report": str(args.report) if args.report else None,
        "advertising_summary_json": str(advertising_summary_json) if args.ble else None,
        "ble_probe_summary_json": str(ble_summary_json) if args.ble else None,
        "steps": [],
    }
    summary_steps = summary["steps"]
    assert isinstance(summary_steps, list)

    report: list[str] | None = None
    if args.report is not None:
        report = [
            "# BioMess firmware verification report",
            "",
            f"- Timestamp UTC: `{started_utc}`",
            f"- Repository: `{REPO_ROOT}`",
            f"- Firmware dir: `{FIRMWARE_DIR}`",
            f"- Board: `{args.board}`",
            f"- Zephyr SDK: `{args.zephyr_sdk}`",
            f"- BLE enabled: `{args.ble}`",
            f"- UART capture enabled: `{args.uart}`",
            f"- Flash requested: `{args.flash}`",
            f"- Android check enabled: `{args.mobile or args.android}`",
            f"- iOS check enabled: `{args.mobile or args.ios}`",
            f"- Mobile tests enabled: `{args.mobile_tests}`",
            "",
        ]

    try:
        preflight_args = ["--west", str(args.west), "--zephyr-sdk", str(args.zephyr_sdk)]
        if args.flash:
            preflight_args.append("--require-board")
        if args.ble:
            preflight_args.append("--require-bleak")
        if args.uart:
            preflight_args.append("--require-pyserial")
        run("environment preflight", python_tool("preflight.py", *preflight_args), report=report, summary_steps=summary_steps)
        run("offline payload parser", python_tool("test_protocol_payloads.py"), report=report, summary_steps=summary_steps)
        run("offline protocol contract", python_tool("test_protocol_contract.py"), report=report, summary_steps=summary_steps)
        run("offline BLE contract summary", python_tool("describe_ble_contract.py"), report=report, summary_steps=summary_steps)
        run("offline hardware contract", python_tool("test_hardware_contract.py"), report=report, summary_steps=summary_steps)
        run("documentation links", python_tool("test_docs_links.py"), report=report, summary_steps=summary_steps)
        run("python syntax", python_tool("test_python_syntax.py"), report=report, summary_steps=summary_steps)
        run("offline board validation report fixture", python_tool("test_board_validation_report.py"), report=report, summary_steps=summary_steps)
        run("offline readiness report fixture", python_tool("test_readiness_report.py"), report=report, summary_steps=summary_steps)
        run("offline release package fixture", python_tool("test_release_package_fixture.py"), report=report, summary_steps=summary_steps)
        run(
            "offline sweep fixture",
            python_tool(
                "generate_sweep_fixture.py",
                "--csv",
                args.fixture_sweep_csv,
                "--points",
                "48",
                "--repetitions",
                "5",
                "--ohms",
                "10000",
            ),
            report=report,
            summary_steps=summary_steps,
        )
        run(
            "offline sweep fixture analysis",
            python_tool(
                "analyze_sweep_csv.py",
                args.fixture_sweep_csv,
                "--points",
                "48",
                "--expected-ohms",
                "10000",
                "--magnitude-tolerance-pct",
                "2",
                "--max-abs-phase-deg",
                "1",
            ),
            report=report,
            summary_steps=summary_steps,
        )

        if not args.skip_build:
            run(
                "firmware build",
                build_command(args.west, args.build_dir, args.board),
                cwd=args.ncs_dir,
                env=zephyr_env(args.zephyr_sdk),
                report=report,
                summary_steps=summary_steps,
            )
            run(
                "firmware build artifacts",
                python_tool("test_build_artifacts.py", "--build-dir", str(args.build_dir)),
                report=report,
                summary_steps=summary_steps,
            )

        if args.mobile or args.android:
            run(
                "Android core-ble compile",
                ["./gradlew", ":core-ble:compileDebugKotlin"],
                cwd=ANDROID_DIR,
                env=android_env(),
                report=report,
                summary_steps=summary_steps,
            )

        if args.mobile or args.ios:
            run("iOS Swift package build", ["swift", "build"], cwd=IOS_PACKAGE_DIR, report=report, summary_steps=summary_steps)

        if args.mobile_tests:
            run(
                "Android core-ble unit tests",
                ["./gradlew", ":core-ble:testDebugUnitTest"],
                cwd=ANDROID_DIR,
                env=android_env(),
                report=report,
                summary_steps=summary_steps,
            )
            run("iOS Swift package tests", ["swift", "test"], cwd=IOS_PACKAGE_DIR, report=report, summary_steps=summary_steps)

        if args.flash:
            run(
                "firmware flash",
                flash_command(args.west, args.build_dir),
                cwd=args.ncs_dir,
                env=zephyr_env(args.zephyr_sdk),
                report=report,
                summary_steps=summary_steps,
            )

        if args.uart:
            uart_args = ["--seconds", str(args.uart_seconds), "--output", str(args.uart_log)]
            if args.serial_port:
                uart_args.extend(["--port", args.serial_port])
            run("UART capture", python_tool("capture_uart.py", *uart_args), report=report, summary_steps=summary_steps)
            run("UART boot log check", python_tool("test_uart_boot_log.py", str(args.uart_log)), report=report, summary_steps=summary_steps)

        if args.ble:
            shared = ble_args(args.address, args.name_prefix)
            advertising_args = [
                "--name-prefix",
                args.name_prefix,
                "--summary-json",
                str(advertising_summary_json),
            ]
            if args.address:
                advertising_args.extend(["--address", args.address])
            run(
                "BLE advertising scan",
                python_tool("scan_advertising.py", *advertising_args),
                report=report,
                summary_steps=summary_steps,
            )
            run(
                "BLE/GATT probe",
                python_tool("ble_probe.py", *shared, "--summary-json", str(ble_summary_json)),
                report=report,
                summary_steps=summary_steps,
            )
            run("board health", python_tool("test_board_health.py", *shared), report=report, summary_steps=summary_steps)
            run("PMIC battery", python_tool("test_pmic_battery.py", *shared), report=report, summary_steps=summary_steps)
            run("LED command", python_tool("test_led_command.py", *shared), report=report, summary_steps=summary_steps)
            run(
                "AD5940 sweep",
                python_tool(
                    "test_ad5940_sweep.py",
                    *shared,
                    "--points",
                    "48",
                    "--start-hz",
                    "4000",
                    "--stop-hz",
                    "198000",
                    "--repetitions",
                    "5",
                    "--csv",
                    args.sweep_csv,
                ),
                report=report,
                summary_steps=summary_steps,
            )
            run(
                "AD5940 sweep CSV analysis",
                python_tool("analyze_sweep_csv.py", args.sweep_csv, "--points", "48"),
                report=report,
                summary_steps=summary_steps,
            )
            run("stored sync", python_tool("test_stored_sync.py", *shared, "--count", "1"), report=report, summary_steps=summary_steps)
            if args.include_auto:
                run(
                    "auto mode",
                    python_tool("test_auto_mode.py", *shared, "--interval", "60", "--timeout", "90"),
                    report=report,
                    summary_steps=summary_steps,
                )

        print("\nverification_ok=true", flush=True)
        summary["ok"] = True
        append_report(report, "## Result")
        append_report(report)
        append_report(report, "`verification_ok=true`")
        append_report(report)
    finally:
        summary["finished_utc"] = datetime.now(timezone.utc).isoformat()
        if args.report is not None and report is not None:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text("\n".join(report), encoding="utf-8")
            print(f"report_path={args.report}", flush=True)
        if summary_json is not None:
            summary_json.parent.mkdir(parents=True, exist_ok=True)
            summary_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            print(f"summary_json_path={summary_json}", flush=True)


if __name__ == "__main__":
    main()
