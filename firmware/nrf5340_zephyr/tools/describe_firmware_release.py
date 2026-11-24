#!/usr/bin/env python3
"""Print a concise, machine-readable summary of a BioMess firmware release zip."""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
FIRMWARE_DIR = REPO_ROOT / "firmware/nrf5340_zephyr"
DEFAULT_RELEASE_DIR = FIRMWARE_DIR / "build/releases"
FULL_BOARD_STEPS = {
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
}


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def latest_release() -> Path:
    packages = sorted(DEFAULT_RELEASE_DIR.glob("biomess-nrf5340-firmware-*.zip"), key=lambda path: path.stat().st_mtime)
    if not packages:
        raise SystemExit(f"No release packages found under {DEFAULT_RELEASE_DIR}")
    return packages[-1]


def load_json_entry(archive: zipfile.ZipFile, name: str) -> dict[str, object] | None:
    try:
        return json.loads(archive.read(name).decode("utf-8"))
    except KeyError:
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


def bool_text(value: object) -> str:
    return str(value is True).lower()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", nargs="?", type=Path, help="Release zip. Defaults to the newest local release.")
    args = parser.parse_args()

    package = args.package or latest_release()
    if not package.exists():
        raise SystemExit(f"Release package does not exist: {package}")

    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        manifest = load_json_entry(archive, "manifest.json")
        if manifest is None:
            raise SystemExit("Release package is missing manifest.json")
        image = manifest.get("image")
        if not isinstance(image, dict):
            raise SystemExit("manifest.json is missing image object")
        network_image = manifest.get("network_core_image")
        firmware = archive.read("firmware/merged.hex")
        actual_sha = sha256_bytes(firmware)
        summary = load_json_entry(archive, "verification-summary.json")

    steps = step_map(summary)
    missing_full_board = sorted(label for label in FULL_BOARD_STEPS if steps.get(label, {}).get("ok") is not True)
    summary_ok = summary.get("ok") is True if summary else False
    full_board_flags = (
        bool(summary and summary.get("flash_requested") is True),
        bool(summary and summary.get("uart_capture_enabled") is True),
        bool(summary and summary.get("ble_enabled") is True),
    )
    full_board_complete = summary_ok and all(full_board_flags) and not missing_full_board

    print(f"release_package={package}")
    print(f"release_entries={len(names)}")
    print(f"release_created_utc={manifest.get('package_created_utc')}")
    print(f"release_board={manifest.get('board')}")
    print(f"firmware_bytes={len(firmware)}")
    print(f"firmware_sha256={actual_sha}")
    print(f"firmware_sha256_matches_manifest={bool_text(actual_sha == image.get('sha256'))}")
    print(f"manifest_firmware_bytes={image.get('size_bytes')}")
    if isinstance(network_image, dict):
        print(f"network_firmware_bytes={network_image.get('size_bytes')}")
        print(f"network_firmware_sha256={network_image.get('sha256')}")
    print(f"git_commit={manifest.get('git', {}).get('commit') if isinstance(manifest.get('git'), dict) else ''}")
    print(f"git_dirty={manifest.get('git', {}).get('dirty') if isinstance(manifest.get('git'), dict) else ''}")
    print(f"nrfjprog_ids_at_packaging={','.join(str(item) for item in manifest.get('nrfjprog_ids', []))}")
    print(f"verification_summary_present={bool_text(summary is not None)}")
    print(f"verification_summary_ok={bool_text(summary_ok)}")
    if summary:
        print(f"verification_steps={len(steps)}")
        print(f"verification_flash_requested={bool_text(summary.get('flash_requested'))}")
        print(f"verification_uart_enabled={bool_text(summary.get('uart_capture_enabled'))}")
        print(f"verification_ble_enabled={bool_text(summary.get('ble_enabled'))}")
    print(f"full_board_validation_complete={bool_text(full_board_complete)}")
    print(f"missing_full_board_steps={','.join(missing_full_board) if missing_full_board else 'none'}")
    print("release_info_ok=true")


if __name__ == "__main__":
    main()
