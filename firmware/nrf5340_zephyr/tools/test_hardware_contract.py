#!/usr/bin/env python3
"""Offline checks for BioMess nRF5340 devicetree and hardware pin contracts."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
FIRMWARE_DIR = REPO_ROOT / "firmware/nrf5340_zephyr"
CPUAPP_OVERLAY = FIRMWARE_DIR / "boards/nrf5340dk_nrf5340_cpuapp.overlay"
CPUAPP_NS_OVERLAY = FIRMWARE_DIR / "boards/nrf5340dk_nrf5340_cpuapp_ns.overlay"
BIOMESS_CPUAPP_DTS = FIRMWARE_DIR / "boards/biomess/biomess_nrf5340/biomess_nrf5340_nrf5340_cpuapp.dts"
BIOMESS_CPUNET_DTS = FIRMWARE_DIR / "boards/biomess/biomess_nrf5340/biomess_nrf5340_nrf5340_cpunet.dts"
BIOMESS_BOARD_YML = FIRMWARE_DIR / "boards/biomess/biomess_nrf5340/board.yml"
ZEPHYR_PORT = FIRMWARE_DIR / "src/ad5940/ZephyrPort.c"
BOARD_POWER = FIRMWARE_DIR / "src/board_power.c"
HARDWARE_DOC = FIRMWARE_DIR / "docs/hardware-v2.md"
HARDWARE_README = REPO_ROOT / "hardware/README.md"
FIRMWARE_README = REPO_ROOT / "firmware/README.md"


EXPECTED_OVERLAY_TOKENS = {
    "ad5940 spi sck": r"NRF_PSEL\(SPIM_SCK,\s*0,\s*9\)",
    "ad5940 spi mosi": r"NRF_PSEL\(SPIM_MOSI,\s*0,\s*13\)",
    "ad5940 spi miso": r"NRF_PSEL\(SPIM_MISO,\s*0,\s*19\)",
    "ad5940 cs": r"cs_pin:\s+cs_pin\s*\{\s*gpios\s*=\s*<&gpio0\s+16\s+GPIO_ACTIVE_LOW>",
    "ad5940 reset": r"rst_pin:\s+rst_pin\s*\{\s*gpios\s*=\s*<&gpio0\s+2\s+GPIO_ACTIVE_LOW>",
    "ad5940 interrupt": r"int_pin:\s+int_pin\s*\{\s*gpios\s*=\s*<&gpio0\s+3\s+\(GPIO_PULL_UP\s*\|\s*GPIO_ACTIVE_LOW\)>",
    "pmic i2c scl": r"NRF_PSEL\(TWIM_SCL,\s*0,\s*24\)",
    "pmic i2c sda": r"NRF_PSEL\(TWIM_SDA,\s*0,\s*26\)",
    "pmic address": r"npm1304_pmic:\s+pmic@6b\s*\{[^}]*reg\s*=\s*<0x6b>",
    "status led": r"status_led:\s+status_led\s*\{\s*gpios\s*=\s*<&gpio1\s+10\s+GPIO_ACTIVE_HIGH>",
}

EXPECTED_DOC_TOKENS = [
    "`RESET_AD` | `P0.02`",
    "`AD_INT` | `P0.03`",
    "`AD_SCLK` | `P0.09`",
    "`AD_MOSI` | `P0.13`",
    "`AD_CS` | `P0.16`",
    "`AD_MISO` | `P0.19`",
    "`SCL_nPM` | `P0.24`",
    "`SDA_nPM` | `P0.26`",
    "`INT_nPM` | `P0.28`",
    "`SHPHLD` | `nPM1304 SHPHLD`",
    "`LED` | `P1.10`",
]


def read(path: Path) -> str:
    if not path.exists():
        raise AssertionError(f"Missing expected file: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def assert_overlay(path: Path) -> None:
    text = read(path)
    for label, pattern in EXPECTED_OVERLAY_TOKENS.items():
        if re.search(pattern, text, re.MULTILINE | re.DOTALL) is None:
            raise AssertionError(f"{path.name} hardware mapping mismatch: {label}")


def assert_code_uses_devicetree_nodes() -> None:
    zephyr_port = read(ZEPHYR_PORT)
    board_power = read(BOARD_POWER)
    for token in [
        "DT_NODELABEL(spi2)",
        "DT_NODELABEL(cs_pin)",
        "DT_NODELABEL(rst_pin)",
        "DT_NODELABEL(int_pin)",
    ]:
        if token not in zephyr_port:
            raise AssertionError(f"AD5940 Zephyr port must use devicetree token: {token}")
    for token in [
        "DT_NODELABEL(npm1304_pmic)",
        "DT_NODELABEL(npm1304_charger)",
        "NPM13XX_EVENT_SHIPHOLD_PRESS",
        "NPM13XX_EVENT_SHIPHOLD_RELEASE",
    ]:
        if token not in board_power:
            raise AssertionError(f"Board power code must use devicetree token: {token}")
    for token in [
        "SENSOR_CHAN_GAUGE_VOLTAGE",
        "mv = CLAMP(mv, 0, UINT16_MAX);",
        "pct = CLAMP(pct, 0, 100);",
        "*voltage_mv = (uint16_t)mv;",
        "*percentage = (uint16_t)pct;",
    ]:
        if token not in board_power:
            raise AssertionError(f"Board power battery reading must preserve BLE-safe PMIC payload contract: {token}")


def assert_docs_match_pinout() -> None:
    doc = read(HARDWARE_DOC)
    for token in EXPECTED_DOC_TOKENS:
        if token not in doc:
            raise AssertionError(f"hardware-v2.md is missing pinout entry: {token}")
    hardware_readme = read(HARDWARE_README)
    for token in [
        "PCB v2",
        "nRF5340",
        "nPM1304",
        "biomess_nrf5340/nrf5340/cpuapp",
        "../firmware/nrf5340_zephyr/docs/hardware-v2.md",
        "nRF52832/BQ24074",
    ]:
        if token not in hardware_readme:
            raise AssertionError(f"hardware/README.md must distinguish current PCB v2 from legacy hardware: {token}")
    firmware_readme = read(FIRMWARE_README)
    for token in [
        "biomess_nrf5340/nrf5340/cpuapp",
        "firmware/nrf5340_zephyr/build/merged.hex",
        "nrf5340_zephyr/docs/bring-up.md",
        "nrf5340_zephyr/docs/verification.md",
    ]:
        if token not in firmware_readme:
            raise AssertionError(f"firmware/README.md must describe current BioMess nRF5340 flow: {token}")
    if "seleccionar el board `nrf5340dk/nrf5340/cpuapp`" in firmware_readme:
        raise AssertionError("firmware/README.md must not recommend the nRF5340 DK as the primary BioMess board")
    if "# TODO: Implementar framework de testing" in firmware_readme:
        raise AssertionError("firmware/README.md must describe the implemented nRF5340 verification tools, not a stale testing TODO")


def assert_biomess_board_target() -> None:
    cpuapp = read(BIOMESS_CPUAPP_DTS)
    cpunet = read(BIOMESS_CPUNET_DTS)
    board_yml = read(BIOMESS_BOARD_YML)
    runner = read(FIRMWARE_DIR / "tools/run_verification.py")
    prj_conf = read(FIRMWARE_DIR / "prj.conf")
    sysbuild_conf = read(FIRMWARE_DIR / "sysbuild.conf")
    for label, pattern in EXPECTED_OVERLAY_TOKENS.items():
        if re.search(pattern, cpuapp, re.MULTILINE | re.DOTALL) is None:
            raise AssertionError(f"BioMess board DTS hardware mapping mismatch: {label}")
    if re.search(r"host-int-gpios\s*=\s*<&gpio0\s+28\s+0>", cpuapp, re.MULTILINE | re.DOTALL) is None:
        raise AssertionError("BioMess board DTS must treat nPM1304 GPOIRQ as active-high on nRF P0.28")
    if re.search(r"pmic-int-pin\s*=\s*<0>", cpuapp, re.MULTILINE | re.DOTALL) is None:
        raise AssertionError("BioMess board DTS must route nPM1304 IRQ through PMIC GPIO0")
    for token in [
        "name: biomess_nrf5340",
        "full_name: BioMess nRF5340 PCB",
        "nrf5340",
    ]:
        if token not in board_yml:
            raise AssertionError(f"BioMess board.yml missing token: {token}")
    if "biomess_nrf5340/nrf5340/cpuapp" not in runner:
        raise AssertionError("run_verification.py must default to the BioMess board target")
    if "BOARD_ROOT" not in runner:
        raise AssertionError("run_verification.py must pass BOARD_ROOT for the out-of-tree BioMess board")
    if "NRF_PSEL(UART_RTS, 0, 19)" in cpuapp:
        raise AssertionError("BioMess board DTS must not assign UART RTS to AD_MISO P0.19")
    if "zephyr,bt-hci = &bt_hci_ipc0" not in cpuapp:
        raise AssertionError("BioMess CPUAPP DTS must keep Bluetooth HCI IPC chosen node")
    if "zephyr,bt-hci-ipc = &ipc0" not in cpunet:
        raise AssertionError("BioMess CPUNET DTS must keep Bluetooth HCI IPC chosen node")
    if "CONFIG_SOC_NRF53_CPUNET_ENABLE=y" not in prj_conf:
        raise AssertionError("prj.conf must release the nRF5340 network core for BLE HCI IPC")
    if "SB_CONFIG_NETCORE_HCI_IPC=y" not in sysbuild_conf:
        raise AssertionError("sysbuild.conf must build the HCI IPC network-core image")


def main() -> None:
    assert_overlay(CPUAPP_OVERLAY)
    assert_overlay(CPUAPP_NS_OVERLAY)
    assert_biomess_board_target()
    assert_code_uses_devicetree_nodes()
    assert_docs_match_pinout()
    print("hardware_contract_ok=true")


if __name__ == "__main__":
    main()
