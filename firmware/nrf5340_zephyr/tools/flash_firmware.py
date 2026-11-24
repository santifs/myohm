#!/usr/bin/env python3
"""Flash a BioMess nRF5340 firmware image with an auditable log."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve()
PACKAGE_ROOT = SCRIPT_PATH.parents[1]
if PACKAGE_ROOT.name == "nrf5340_zephyr" and SCRIPT_PATH.parents[2].name == "firmware":
    REPO_ROOT = SCRIPT_PATH.parents[3]
    FIRMWARE_DIR = PACKAGE_ROOT
else:
    REPO_ROOT = PACKAGE_ROOT
    FIRMWARE_DIR = PACKAGE_ROOT
PACKAGE_HEX = PACKAGE_ROOT / "firmware/merged.hex"
PACKAGE_NET_HEX = PACKAGE_ROOT / "firmware/merged_CPUNET.hex"
REPO_HEX = FIRMWARE_DIR / "build/merged.hex"
REPO_NET_HEX = FIRMWARE_DIR / "build/merged_CPUNET.hex"
DEFAULT_HEX = PACKAGE_HEX if PACKAGE_HEX.exists() and not REPO_HEX.exists() else REPO_HEX
DEFAULT_NET_HEX = PACKAGE_NET_HEX if PACKAGE_NET_HEX.exists() and not REPO_NET_HEX.exists() else REPO_NET_HEX
DEFAULT_BUILD_DIR = FIRMWARE_DIR / "build"
DEFAULT_NRFJPROG = Path("/usr/local/bin/nrfjprog")
DEFAULT_WEST = Path("/opt/nordic/ncs/toolchains/0c0f19d91c/bin/west")
DEFAULT_NCS_DIR = Path("/opt/nordic/ncs/v3.3.0")
DEFAULT_ZEPHYR_SDK = Path("/opt/nordic/ncs/toolchains/0c0f19d91c/opt/zephyr-sdk")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_tool(path: Path, fallback_name: str) -> Path | None:
    if path.exists():
        return path
    found = shutil.which(fallback_name)
    return Path(found) if found else None


def run_text(command: list[str], cwd: Path | None = None, env: dict[str, str] | None = None) -> tuple[int, str]:
    try:
        result = subprocess.run(
            command,
            cwd=str(cwd) if cwd else None,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    except FileNotFoundError as exc:
        return 127, str(exc)
    return result.returncode, result.stdout or ""


def nrfjprog_ids(nrfjprog: Path | None) -> tuple[int, list[str], str]:
    if nrfjprog is None:
        return 127, [], "nrfjprog not found"
    code, output = run_text([str(nrfjprog), "--ids"])
    ids = [line.strip() for line in output.splitlines() if line.strip()]
    return code, ids, output


def zephyr_env(zephyr_sdk: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["ZEPHYR_TOOLCHAIN_VARIANT"] = "zephyr"
    env["ZEPHYR_SDK_INSTALL_DIR"] = str(zephyr_sdk)
    return env


def extract_hex_from_package(package_path: Path, output_dir: Path) -> tuple[Path, Path | None]:
    if not package_path.exists():
        raise SystemExit(f"Release package does not exist: {package_path}")
    with zipfile.ZipFile(package_path, "r") as archive:
        names = set(archive.namelist())
        if "firmware/merged.hex" not in names:
            raise SystemExit("Release package is missing firmware/merged.hex")
        archive.extract("firmware/merged.hex", output_dir)
        if "firmware/merged_CPUNET.hex" in names:
            archive.extract("firmware/merged_CPUNET.hex", output_dir)

        manifest: dict[str, object] | None = None
        if "manifest.json" in names:
            manifest = json.loads(archive.read("manifest.json").decode("utf-8"))

    hex_path = output_dir / "firmware/merged.hex"
    net_hex_path = output_dir / "firmware/merged_CPUNET.hex"
    if not net_hex_path.exists():
        net_hex_path = None
    if manifest:
        image = manifest.get("image")
        if isinstance(image, dict):
            expected_size = image.get("size_bytes")
            expected_sha = image.get("sha256")
            if isinstance(expected_size, int) and hex_path.stat().st_size != expected_size:
                raise SystemExit("Release package firmware size does not match manifest.json")
            if isinstance(expected_sha, str) and sha256_file(hex_path) != expected_sha:
                raise SystemExit("Release package firmware SHA256 does not match manifest.json")
        network_image = manifest.get("network_core_image")
        if isinstance(network_image, dict):
            if net_hex_path is None:
                raise SystemExit("Release package manifest expects firmware/merged_CPUNET.hex")
            expected_size = network_image.get("size_bytes")
            expected_sha = network_image.get("sha256")
            if isinstance(expected_size, int) and net_hex_path.stat().st_size != expected_size:
                raise SystemExit("Release package network-core firmware size does not match manifest.json")
            if isinstance(expected_sha, str) and sha256_file(net_hex_path) != expected_sha:
                raise SystemExit("Release package network-core firmware SHA256 does not match manifest.json")
    return hex_path, net_hex_path


def nrfjprog_program_command(args: argparse.Namespace, nrfjprog: Path | None, hex_path: Path, *, coprocessor: str, reset: bool) -> list[str]:
    command = [str(nrfjprog or args.nrfjprog), "--program", str(hex_path)]
    command.append("--sectorerase" if args.sectorerase else "--chiperase")
    command.extend(["--coprocessor", coprocessor])
    command.append("--verify")
    if args.snr:
        command.extend(["--snr", args.snr])
    if reset:
        command.append("--reset")
    return command


def build_commands(args: argparse.Namespace, hex_path: Path, net_hex_path: Path | None) -> list[list[str]]:
    if args.method == "nrfjprog":
        nrfjprog = resolve_tool(args.nrfjprog, "nrfjprog")
        if nrfjprog is None and not args.dry_run:
            raise SystemExit("nrfjprog not found")
        commands: list[list[str]] = []
        if net_hex_path is not None and net_hex_path.exists():
            commands.append(
                nrfjprog_program_command(args, nrfjprog, net_hex_path, coprocessor="CP_NETWORK", reset=False)
            )
        commands.append(nrfjprog_program_command(args, nrfjprog, hex_path, coprocessor="CP_APPLICATION", reset=args.reset))
        return commands

    west = resolve_tool(args.west, "west")
    if west is None and not args.dry_run:
        raise SystemExit("west not found")
    command = [str(west or args.west), "flash", "-d", str(args.build_dir)]
    if args.snr:
        command.extend(["--dev-id", args.snr])
    return [command]


def write_text_if_requested(path: Path | None, text: str) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def write_json_if_requested(path: Path | None, data: dict[str, object]) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--hex", type=Path, default=DEFAULT_HEX, help="Hex image to program.")
    source.add_argument("--package", type=Path, help="Release zip containing firmware/merged.hex.")
    parser.add_argument("--method", choices=("nrfjprog", "west"), default="nrfjprog")
    parser.add_argument("--nrfjprog", type=Path, default=DEFAULT_NRFJPROG)
    parser.add_argument("--west", type=Path, default=DEFAULT_WEST)
    parser.add_argument("--ncs-dir", type=Path, default=DEFAULT_NCS_DIR)
    parser.add_argument("--zephyr-sdk", type=Path, default=DEFAULT_ZEPHYR_SDK)
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    parser.add_argument("--snr", help="Debugger serial number. Required if more than one debugger is visible.")
    parser.add_argument("--sectorerase", action="store_true", help="Use sector erase instead of chip erase with nrfjprog.")
    parser.add_argument("--no-reset", dest="reset", action="store_false", help="Do not reset after nrfjprog verification.")
    parser.add_argument("--dry-run", action="store_true", help="Print and log what would be flashed without programming.")
    parser.add_argument("--allow-no-debugger", action="store_true", help="Continue even when nrfjprog --ids is empty.")
    parser.add_argument("--log", type=Path, help="Write combined command output to this text file.")
    parser.add_argument("--summary-json", type=Path, help="Write a machine-readable flash summary.")
    parser.set_defaults(reset=True)
    args = parser.parse_args()

    started_utc = datetime.now(timezone.utc).isoformat()
    temp_context = tempfile.TemporaryDirectory(prefix="biomess-flash-") if args.package else None
    try:
        if args.package and temp_context:
            hex_path, net_hex_path = extract_hex_from_package(args.package.resolve(), Path(temp_context.name))
        else:
            hex_path = args.hex.resolve()
            net_hex_path = DEFAULT_NET_HEX.resolve() if DEFAULT_NET_HEX.exists() else None
        if not hex_path.exists():
            raise SystemExit(f"Firmware image does not exist: {hex_path}")
        if hex_path.stat().st_size <= 0:
            raise SystemExit(f"Firmware image is empty: {hex_path}")
        if net_hex_path is not None and net_hex_path.stat().st_size <= 0:
            raise SystemExit(f"Network-core firmware image is empty: {net_hex_path}")

        nrfjprog = resolve_tool(args.nrfjprog, "nrfjprog")
        ids_code, ids, ids_output = nrfjprog_ids(nrfjprog)
        preflight_error: str | None = None
        if ids_code != 0 and not args.allow_no_debugger and not args.dry_run:
            preflight_error = f"nrfjprog --ids failed:\n{ids_output}"
        if not ids and not args.allow_no_debugger and not args.dry_run:
            preflight_error = (
                "No nRF debugger detected by nrfjprog --ids. "
                "Run firmware/nrf5340_zephyr/tools/diagnose_debugger.py before flashing."
            )
        if len(ids) > 1 and not args.snr and not args.dry_run:
            preflight_error = "More than one nRF debugger is visible; pass --snr <debugger-serial>."

        commands = build_commands(args, hex_path, net_hex_path)
        command_text = " && ".join(" ".join(command) for command in commands)
        hex_sha = sha256_file(hex_path)
        hex_size = hex_path.stat().st_size
        net_hex_sha = sha256_file(net_hex_path) if net_hex_path is not None else ""
        net_hex_size = net_hex_path.stat().st_size if net_hex_path is not None else 0

        preamble = "\n".join(
            [
                f"started_utc={started_utc}",
                f"repo_root={REPO_ROOT}",
                f"hex_path={hex_path}",
                f"hex_size_bytes={hex_size}",
                f"hex_sha256={hex_sha}",
                f"network_hex_path={net_hex_path or ''}",
                f"network_hex_size_bytes={net_hex_size}",
                f"network_hex_sha256={net_hex_sha}",
                "nrfjprog_ids=" + ",".join(ids),
                f"dry_run={'true' if args.dry_run else 'false'}",
                f"flash_command={command_text}",
                "",
            ]
        )
        print(preamble, end="")

        output = ""
        exit_code = 0
        duration_s = 0.0
        if preflight_error:
            exit_code = 1
            output = preflight_error + "\n"
            print(output, end="")
        elif not args.dry_run:
            started = time.monotonic()
            env = zephyr_env(args.zephyr_sdk) if args.method == "west" else None
            cwd = args.ncs_dir if args.method == "west" else None
            output_parts: list[str] = []
            for command in commands:
                exit_code, command_output = run_text(command, cwd=cwd, env=env)
                output_parts.append(command_output)
                if command_output:
                    print(command_output, end="" if command_output.endswith("\n") else "\n")
                if exit_code != 0:
                    break
            output = "".join(output_parts)
            duration_s = time.monotonic() - started

        ok = exit_code == 0
        finished_utc = datetime.now(timezone.utc).isoformat()
        tail = "\n".join(
            [
                "",
                f"exit_code={exit_code}",
                f"duration_seconds={duration_s:.3f}",
                f"finished_utc={finished_utc}",
                f"flash_ok={'true' if ok else 'false'}",
                "",
            ]
        )
        print(tail, end="")

        log_text = preamble + output + tail
        write_text_if_requested(args.log, log_text)

        summary = {
            "started_utc": started_utc,
            "finished_utc": finished_utc,
            "ok": ok,
            "dry_run": args.dry_run,
            "method": args.method,
            "repository": str(REPO_ROOT),
            "hex_path": str(hex_path),
            "hex_size_bytes": hex_size,
            "hex_sha256": hex_sha,
            "network_hex_path": str(net_hex_path) if net_hex_path else None,
            "network_hex_size_bytes": net_hex_size,
            "network_hex_sha256": net_hex_sha,
            "package": str(args.package.resolve()) if args.package else None,
            "nrfjprog_ids": ids,
            "command": commands[-1],
            "commands": commands,
            "exit_code": exit_code,
            "duration_seconds": round(duration_s, 3),
            "stdout_tail": output[-4000:],
            "log": str(args.log) if args.log else None,
        }
        write_json_if_requested(args.summary_json, summary)
        if args.log:
            print(f"log_path={args.log}")
        if args.summary_json:
            print(f"summary_json_path={args.summary_json}")
        if not ok:
            raise SystemExit(exit_code)
    finally:
        if temp_context:
            temp_context.cleanup()


if __name__ == "__main__":
    main()
