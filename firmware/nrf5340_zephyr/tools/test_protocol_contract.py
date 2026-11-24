#!/usr/bin/env python3
"""Static contract checks for the Myohm firmware and web laboratory."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
FIRMWARE_BLE = REPO_ROOT / "firmware/nrf5340_zephyr/src/ble_service.c"


UUIDS = {
    "CONTROL_SERVICE": "0000af00-0000-1000-8000-00805f9b34fb",
    "CONFIG_SERVICE": "0000af01-0000-1000-8000-00805f9b34fb",
    "DATA_SERVICE": "0000af02-0000-1000-8000-00805f9b34fb",
    "ENV_SERVICE": "0000af03-0000-1000-8000-00805f9b34fb",
    "CONTROL_COMMAND": "0000c000-0000-1000-8000-00805f9b34fb",
    "SERIAL_NUMBER": "0000c001-0000-1000-8000-00805f9b34fb",
    "RCAL": "0000c011-0000-1000-8000-00805f9b34fb",
    "SWEEP_ENABLE": "0000c012-0000-1000-8000-00805f9b34fb",
    "SWEEP_START_FREQ": "0000c013-0000-1000-8000-00805f9b34fb",
    "SWEEP_STOP_FREQ": "0000c014-0000-1000-8000-00805f9b34fb",
    "SWEEP_POINTS": "0000c015-0000-1000-8000-00805f9b34fb",
    "NUM_REPETITIONS": "0000c017-0000-1000-8000-00805f9b34fb",
    "EXCITATION_AMPLITUDE": "0000c018-0000-1000-8000-00805f9b34fb",
    "IMU_QUATERNION": "0000c201-0000-1000-8000-00805f9b34fb",
    "BATTERY_LEVEL": "0000c202-0000-1000-8000-00805f9b34fb",
    "IMU_Q_VARIANCE": "0000c203-0000-1000-8000-00805f9b34fb",
}

COMMANDS = {
    "MEASUREMENT": 0x01,
    "BATTERY_MANUAL": 0x02,
    "IMU_SINGLE": 0x03,
    "IMU_STATS": 0x04,
    "START_AUTO_MODE": 0x05,
    "STOP_AUTO_MODE": 0x06,
    "GET_STORED_COUNT": 0x07,
    "GET_STORED_BATCH": 0x08,
    "CLEAR_STORED": 0x09,
    "HEALTH_CHECK": 0x0A,
    "CONTACT_CHECK": 0x0B,
    "LED_BLINK": 100,
}


def read(path: Path) -> str:
    if not path.exists():
        raise AssertionError(f"Missing expected file: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def uuid16(full_uuid: str) -> str:
    return "0x" + full_uuid[:8]


def parse_int_literal(value: str) -> int:
    value = value.strip()
    if value.endswith(".toByte()"):
        value = value[: -len(".toByte()")]
    return int(value, 16 if value.lower().startswith("0x") else 10)


def assert_firmware_commands() -> None:
    text = read(FIRMWARE_BLE)
    found = {
        match.group(1): parse_int_literal(match.group(2))
        for match in re.finditer(r"#define\s+COMMAND_([A-Z0-9_]+)\s+([^\s]+)", text)
    }
    for name, code in COMMANDS.items():
        if found.get(name) != code:
            raise AssertionError(f"Firmware command {name} expected {code}, found {found.get(name)}")


def assert_firmware_sweep_safety() -> None:
    ble = read(FIRMWARE_BLE)
    ad5940 = read(REPO_ROOT / "firmware/nrf5340_zephyr/src/ad5940/AD5940Main.c")

    if "CLAMP(sys_get_le32(buf), 2, AD5940_MAX_SWEEP_POINTS)" not in ble:
        raise AssertionError("Firmware BLE config must clamp sweep points to 2..AD5940_MAX_SWEEP_POINTS")
    if "active.points < 2" not in ad5940:
        raise AssertionError("AD5940_RunSweep must reject fewer than 2 sweep points")
    for token in ["put_le_float(sweep_config.rcal_ohms", "get_le_float(buf)", "put_le_float(point->frequency"]:
        if token not in ble:
            raise AssertionError(f"Firmware BLE float packing helper missing: {token}")
    if "stream->offset > 0 && stream->offset + 12 > limit" not in ble:
        raise AssertionError("Firmware BLE streaming must flush before exceeding the negotiated ATT payload limit")
    if "auto_mode_enabled = false;" not in ble:
        raise AssertionError("Firmware must stop RAM-backed auto mode when the BLE connection drops")
    for token in [
        "static struct k_work_delayable advertising_restart_work",
        "k_work_init_delayable(&advertising_restart_work, advertising_restart_work_handler)",
        "k_work_reschedule(&advertising_restart_work, K_MSEC(250))",
        "static int start_advertising(void)",
        "ret == -EALREADY",
    ]:
        if token not in ble:
            raise AssertionError(f"Firmware must restart advertising robustly after central disconnect: {token}")
    if not re.search(r"static const struct bt_data ad\[\]\s*=\s*\{[^}]*BT_DATA_FLAGS", ble, re.DOTALL):
        raise AssertionError("Firmware primary advertising packet must include BLE flags")
    if not re.search(r"static const struct bt_data ad\[\]\s*=\s*\{[^}]*BT_DATA_NAME_COMPLETE", ble, re.DOTALL):
        raise AssertionError("Firmware primary advertising packet must include the configured device name")
    if "BT_LE_ADV_OPT_CONN | BT_LE_ADV_OPT_USE_IDENTITY" not in ble:
        raise AssertionError("Firmware connectable advertising must use the identity address")
    if re.search(r"static const struct bt_data (ad|sd)\[\]\s*=\s*\{[^}]*BT_DATA_UUID128_ALL", ble, re.DOTALL):
        raise AssertionError("Firmware must keep 128-bit service UUIDs out of legacy advertising payloads")


def assert_firmware_health_check() -> None:
    ble = read(FIRMWARE_BLE)
    ad5940_header = read(REPO_ROOT / "firmware/nrf5340_zephyr/src/ad5940/AD5940Main.h")
    ad5940_main = read(REPO_ROOT / "firmware/nrf5340_zephyr/src/ad5940/AD5940Main.c")
    tools = read(REPO_ROOT / "firmware/nrf5340_zephyr/tools/biomess_ble.py")
    runner = read(REPO_ROOT / "firmware/nrf5340_zephyr/tools/run_verification.py")
    uart_log = read(REPO_ROOT / "firmware/nrf5340_zephyr/tools/test_uart_boot_log.py")

    expectations = [
        ("firmware command handler", ble, "case COMMAND_HEALTH_CHECK:"),
        ("firmware pmic flag", ble, "HEALTH_FLAG_PMIC_OK"),
        ("firmware ad5940 flag", ble, "HEALTH_FLAG_AD5940_ADIID_OK"),
        ("firmware chip flag", ble, "HEALTH_FLAG_AD5940_CHIPID_KNOWN"),
        ("firmware payload size", ble, "uint8_t payload[12]"),
        ("ad5940 identity api", ad5940_header, "int AD5940_ReadIdentity"),
        ("ad5940 adi id read", ad5940_main, "AD5940_GetADIID()"),
        ("ad5940 chip id read", ad5940_main, "AD5940_GetChipID()"),
        ("python health helper", tools, "async def read_board_health"),
        ("python health dataclass", tools, "class BoardHealth"),
        ("python health parser", tools, "def parse_board_health_payload"),
        ("python battery parser", tools, "def parse_battery_payload"),
        ("python health helper parser use", tools, "return parse_board_health_payload(raw)"),
        ("python battery helper parser use", tools, "return parse_battery_payload(bytes(payload))"),
        ("runner health step", runner, "test_board_health.py"),
        ("runner uart boot log step", runner, "test_uart_boot_log.py"),
        ("uart boot log ble marker", uart_log, "BLE advertising as BioMess"),
        ("uart boot log ad5940 marker", uart_log, "AD5940 GPIOs:"),
    ]
    for label, text, token in expectations:
        if token not in text:
            raise AssertionError(f"Health check contract missing: {label}")
    false_positive_pattern = "AD5940_ReadIdentity(&identity) == 0) {\n\t\tflags |= HEALTH_FLAG_AD5940_ADIID_OK;"
    if false_positive_pattern in ble:
        raise AssertionError("Health check must not set ADIID_OK merely because AD5940 identity read returned success")




def assert_web_contract() -> None:
    firmware = read(FIRMWARE_BLE).lower()
    web = read(REPO_ROOT / "web/src/ble/index.ts").lower()
    for name, value in UUIDS.items():
        assert uuid16(value) in firmware, f"Missing firmware UUID {name}"
    web_uuids = re.findall(r'"(0000[0-9a-f]{4}-0000-1000-8000-00805f9b34fb)"', web)
    assert len(web_uuids) == 11, "Review changed web GATT contract"
    for value in web_uuids:
        assert value in UUIDS.values(), f"Unknown web UUID {value}"
    for name, value in {"measurement": 1, "battery_manual": 2, "stop_auto": 6}.items():
        match = re.search(r"const command_" + name + r" = (0x[0-9a-f]+|[0-9]+)", web)
        assert match and int(match[1], 0) == value, name


def main() -> None:
    assert_web_contract()
    assert_firmware_commands()
    assert_firmware_sweep_safety()
    assert_firmware_health_check()
    print("firmware_web_protocol_contract_ok=true")


if __name__ == "__main__":
    main()
