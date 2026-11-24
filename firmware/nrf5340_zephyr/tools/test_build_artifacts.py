#!/usr/bin/env python3
"""Validate generated build artifacts for the BioMess nRF5340 firmware."""

from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path


EXPECTED_BOARD = "biomess_nrf5340/nrf5340/cpuapp"
FIRMWARE_DIR = Path(__file__).resolve().parents[1]


def read(path: Path) -> str:
    if not path.exists():
        raise AssertionError(f"Missing build artifact: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assert_contains(path: Path, token: str) -> None:
    text = read(path)
    if token not in text:
        raise AssertionError(f"{path} is missing token: {token}")


def assert_regex(path: Path, pattern: str, label: str) -> None:
    text = read(path)
    if re.search(pattern, text, re.MULTILINE | re.DOTALL) is None:
        raise AssertionError(f"{path} does not match {label}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=FIRMWARE_DIR / "build")
    args = parser.parse_args()

    build = args.build_dir
    merged_hex = build / "merged.hex"
    cmake_cache = build / "CMakeCache.txt"
    sysbuild_config = build / "zephyr/.config"
    app_config = build / "nrf5340_zephyr/zephyr/.config"
    app_dts = build / "nrf5340_zephyr/zephyr/zephyr.dts"
    runners = build / "nrf5340_zephyr/zephyr/runners.yaml"
    domains = build / "domains.yaml"
    status_doc = FIRMWARE_DIR / "docs/implementation-status.md"

    if not merged_hex.exists() or merged_hex.stat().st_size <= 0:
        raise AssertionError(f"merged.hex missing or empty: {merged_hex}")

    assert_contains(cmake_cache, f"BOARD:STRING={EXPECTED_BOARD}")
    assert_contains(cmake_cache, f"CACHED_BOARD:STRING={EXPECTED_BOARD}")
    assert_contains(cmake_cache, "BOARD_ROOT:PATH=")
    assert_contains(sysbuild_config, "SB_CONFIG_NETCORE_HCI_IPC=y")
    assert_contains(sysbuild_config, "# SB_CONFIG_NETCORE_NONE is not set")
    assert_contains(app_config, f'CONFIG_BOARD_TARGET="{EXPECTED_BOARD}"')
    assert_contains(app_config, "CONFIG_SOC_NRF53_CPUNET_ENABLE=y")
    assert_contains(app_config, "CONFIG_BT_HCI_IPC=y")
    assert_contains(app_dts, 'compatible = "biomess,biomess-nrf5340-cpuapp"')
    assert_contains(app_dts, "zephyr,bt-hci = &bt_hci_ipc0")
    assert_regex(app_dts, r"pmic@6b\s*\{[^}]*compatible = \"nordic,npm1304\"", "nPM1304 PMIC node")
    assert_regex(app_dts, r"spi@b000\s*\{[^}]*status = \"okay\"", "SPI2 enabled")
    assert_contains(runners, "board_dir: " + str(FIRMWARE_DIR / "boards/biomess/biomess_nrf5340"))
    assert_contains(runners, "hex_file: " + str(merged_hex))
    assert_contains(domains, "name: nrf5340_zephyr")
    assert_contains(domains, "name: hci_ipc")

    image_sha = sha256_file(merged_hex)
    image_size = merged_hex.stat().st_size
    assert_contains(status_doc, "Current image size and SHA256 are build artifacts")
    assert_contains(status_doc, "make -C firmware/nrf5340_zephyr flash-dry-run")
    assert_contains(status_doc, "tools/flash_firmware.py --dry-run --summary-json /tmp/biomess_flash_dry_run.json")
    status_text = read(status_doc)
    if "Latest verified handoff package:" in status_text:
        raise AssertionError("implementation-status.md must not hard-code a latest release package timestamp")
    assert_contains(status_doc, "make firmware-release-info")
    assert_contains(status_doc, "make firmware-release-matches-build")

    print(f"build_artifacts_board={EXPECTED_BOARD}")
    print(f"build_artifacts_merged_hex={merged_hex}")
    print(f"build_artifacts_merged_hex_bytes={image_size}")
    print(f"build_artifacts_merged_hex_sha256={image_sha}")
    print("build_artifacts_ok=true")


if __name__ == "__main__":
    main()
