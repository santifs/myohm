#!/usr/bin/env python3
"""Offline checks for the binary payload formats shared by firmware and apps."""

from __future__ import annotations

import struct
import sys

sys.dont_write_bytecode = True

from biomess_ble import (
    BATTERY_LEVEL,
    CONFIG_CHARACTERISTICS,
    CMD_CONTACT_CHECK,
    CONFIG_SERVICE,
    CONTROL_COMMAND,
    CONTACT_ENTRY_FLAG_HIGH,
    CONTACT_FLAG_ANY_HIGH,
    CONTROL_SERVICE,
    DATA_SERVICE,
    ENV_SERVICE,
    HEALTH_FLAG_AD5940_ADIID_OK,
    HEALTH_FLAG_AD5940_CHIPID_KNOWN,
    HEALTH_FLAG_PMIC_OK,
    IMU_Q_VARIANCE,
    IMU_QUATERNION,
    SERIAL_NUMBER,
    contact_check_payload_size,
    STORED_POINTS_PER_REPETITION,
    STORED_RECORD_SIZE,
    STORED_REPETITIONS,
    crc16_ccitt,
    parse_battery_payload,
    parse_board_health_payload,
    parse_contact_check_payload,
    parse_points,
    parse_stored_measurement,
    validate_gatt_contract,
)


def assert_raises_value_error(fn, *args) -> None:
    try:
        fn(*args)
    except ValueError:
        return
    raise AssertionError(f"{fn.__name__} did not raise ValueError")


def main() -> None:
    payload = struct.pack("<fff", 4000.0, 123.5, -12.25) + struct.pack("<fff", 198000.0, 98.0, 3.5)
    points = parse_points(payload)
    assert len(points) == 2
    assert points[0].frequency == 4000.0
    assert points[0].magnitude == 123.5
    assert points[0].phase == -12.25
    assert points[1].frequency == 198000.0
    battery = struct.pack("<HH", 3890, 65)
    assert parse_battery_payload(battery) == (3890, 65)
    assert_raises_value_error(parse_battery_payload, b"\x00")
    assert_raises_value_error(parse_battery_payload, struct.pack("<HH", 3890, 101))

    health_flags = HEALTH_FLAG_PMIC_OK | HEALTH_FLAG_AD5940_ADIID_OK | HEALTH_FLAG_AD5940_CHIPID_KNOWN
    health = parse_board_health_payload(struct.pack("<HHHHHH", health_flags, 3890, 65, 0x4144, 0x5500, 0))
    assert health.pmic_ok
    assert health.ad5940_adi_id_ok
    assert health.ad5940_chip_id_known
    assert health.battery_voltage_mv == 3890
    assert health.battery_percentage == 65
    assert health.ad5940_adi_id == 0x4144
    assert health.ad5940_chip_id == 0x5500
    assert_raises_value_error(parse_board_health_payload, b"\x00")
    assert_raises_value_error(parse_board_health_payload, struct.pack("<HHHHHH", health_flags, 3890, 101, 0x4144, 0x5500, 0))

    assert CMD_CONTACT_CHECK == 0x0B
    contact = struct.pack("<BBHI", 1, 2, CONTACT_FLAG_ANY_HIGH, 5000)
    contact += struct.pack("<BBHfff", 0, 0, 0, 10000.0, 812.5, -4.0)
    contact += struct.pack("<BBHfff", 1, CONTACT_ENTRY_FLAG_HIGH, 0, 10000.0, 9876.0, -12.5)
    assert contact_check_payload_size(contact[:2]) == len(contact) == 40
    check = parse_contact_check_payload(contact)
    assert check.any_high and check.threshold_ohm == 5000
    assert [entry.pair_name for entry in check.entries] == ["I+/I-", "V+/V-"]
    assert not check.entries[0].high and check.entries[1].high
    assert check.entries[1].magnitude_ohm == 9876.0
    assert_raises_value_error(parse_contact_check_payload, contact[:-1])
    assert_raises_value_error(parse_contact_check_payload, b"\x02" + contact[1:])

    stored = bytearray(STORED_RECORD_SIZE)
    struct.pack_into("<IHHHBB", stored, 0, 123, 1, 2, 60, 77, 5)
    offset = 12
    for rep in range(STORED_REPETITIONS):
        for point in range(STORED_POINTS_PER_REPETITION):
            struct.pack_into("<fff", stored, offset, 4000.0 + point, 100.0 + rep, -1.0)
            offset += 12
    for _ in range(STORED_REPETITIONS):
        struct.pack_into("<ffff", stored, offset, 0.0, 0.0, 0.0, 0.0)
        offset += 16
    struct.pack_into("<H", stored, offset, crc16_ccitt(stored[:-2]))
    record = parse_stored_measurement(bytes(stored))
    assert record.crc16_valid
    assert record.session_id == 1
    assert record.sequence_number == 2
    assert len(record.repetitions) == 5
    assert len(record.repetitions[0]) == 48

    valid_gatt = {
        CONTROL_SERVICE: {
            CONTROL_COMMAND: {"write", "notify"},
            SERIAL_NUMBER: {"read"},
            **{uuid: {"read", "write"} for uuid in CONFIG_CHARACTERISTICS},
        },
        CONFIG_SERVICE: {uuid: {"read", "write"} for uuid in CONFIG_CHARACTERISTICS},
        DATA_SERVICE: {},
        ENV_SERVICE: {
            IMU_QUATERNION: {"read", "notify"},
            BATTERY_LEVEL: {"read", "notify"},
            IMU_Q_VARIANCE: {"read", "notify"},
        },
    }
    assert validate_gatt_contract(valid_gatt) == []
    missing_gatt = {key: value for key, value in valid_gatt.items() if key != DATA_SERVICE}
    assert any("missing service" in failure and DATA_SERVICE in failure for failure in validate_gatt_contract(missing_gatt))
    bad_control = {
        **valid_gatt,
        CONTROL_SERVICE: {**valid_gatt[CONTROL_SERVICE], CONTROL_COMMAND: {"write"}},
    }
    assert any(CONTROL_COMMAND in failure and "notify" in failure for failure in validate_gatt_contract(bad_control))
    print("protocol_payloads_ok=true")


if __name__ == "__main__":
    main()
