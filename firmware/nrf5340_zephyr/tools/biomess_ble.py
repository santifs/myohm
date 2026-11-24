#!/usr/bin/env python3
"""Shared BLE helpers for the BioMess nRF5340 firmware verification scripts."""

from __future__ import annotations

import asyncio
import csv
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Mapping

try:
    from bleak import BleakClient, BleakScanner
except ImportError:  # pragma: no cover - BLE-only paths raise a helpful error
    BleakClient = None
    BleakScanner = None


REQUIREMENTS = Path(__file__).resolve().parent / "requirements.txt"


def dependency_install_hint() -> str:
    return f"python3 -m pip install -r {REQUIREMENTS}"


CONTROL_SERVICE = "0000af00-0000-1000-8000-00805f9b34fb"
CONFIG_SERVICE = "0000af01-0000-1000-8000-00805f9b34fb"
DATA_SERVICE = "0000af02-0000-1000-8000-00805f9b34fb"
ENV_SERVICE = "0000af03-0000-1000-8000-00805f9b34fb"

CONTROL_COMMAND = "0000c000-0000-1000-8000-00805f9b34fb"
SERIAL_NUMBER = "0000c001-0000-1000-8000-00805f9b34fb"
RCAL = "0000c011-0000-1000-8000-00805f9b34fb"
SWEEP_ENABLE = "0000c012-0000-1000-8000-00805f9b34fb"
SWEEP_START_FREQ = "0000c013-0000-1000-8000-00805f9b34fb"
SWEEP_STOP_FREQ = "0000c014-0000-1000-8000-00805f9b34fb"
SWEEP_POINTS = "0000c015-0000-1000-8000-00805f9b34fb"
NUM_REPETITIONS = "0000c017-0000-1000-8000-00805f9b34fb"
# Optional (firmware with the contact check); not part of REQUIRED_CHARACTERISTICS.
EXCITATION_AMPLITUDE = "0000c018-0000-1000-8000-00805f9b34fb"
IMU_QUATERNION = "0000c201-0000-1000-8000-00805f9b34fb"
BATTERY_LEVEL = "0000c202-0000-1000-8000-00805f9b34fb"
IMU_Q_VARIANCE = "0000c203-0000-1000-8000-00805f9b34fb"

CMD_MEASUREMENT = 0x01
CMD_BATTERY = 0x02
CMD_START_AUTO = 0x05
CMD_STOP_AUTO = 0x06
CMD_STORED_COUNT = 0x07
CMD_STORED_BATCH = 0x08
CMD_CLEAR_STORED = 0x09
CMD_HEALTH_CHECK = 0x0A
CMD_CONTACT_CHECK = 0x0B
CMD_LED_BLINK = 100
HEALTH_FLAG_PMIC_OK = 1 << 0
HEALTH_FLAG_AD5940_ADIID_OK = 1 << 1
HEALTH_FLAG_AD5940_CHIPID_KNOWN = 1 << 2
CONTACT_PAIRS = {0: "I+/I-", 1: "V+/V-", 2: "I+/V+", 3: "I-/V-"}
CONTACT_ENTRY_FLAG_HIGH = 1 << 0
CONTACT_ENTRY_FLAG_INVALID = 1 << 1
CONTACT_ENTRY_FLAG_OPEN = 1 << 2
CONTACT_ENTRY_FLAG_OVERRANGE = 1 << 3
CONTACT_FLAG_ANY_HIGH = 1 << 0
CONTACT_FLAG_ANY_INVALID = 1 << 1
CONTACT_FLAG_AFE_ERROR = 1 << 2
CONTACT_HEADER_SIZE = 8
CONTACT_ENTRY_SIZE = 16
STORED_REPETITIONS = 5
STORED_POINTS_PER_REPETITION = 48
STORED_RECORD_SIZE = 2974
WRITE_ANY = "write-any"
REQUIRED_SERVICES = (CONTROL_SERVICE, CONFIG_SERVICE, DATA_SERVICE, ENV_SERVICE)
CONFIG_CHARACTERISTICS = (
    RCAL,
    SWEEP_ENABLE,
    SWEEP_START_FREQ,
    SWEEP_STOP_FREQ,
    SWEEP_POINTS,
    NUM_REPETITIONS,
)
REQUIRED_CHARACTERISTICS = (
    (CONTROL_SERVICE, CONTROL_COMMAND, (WRITE_ANY, "notify"), "control command"),
    (CONTROL_SERVICE, SERIAL_NUMBER, ("read",), "serial number"),
    *[(CONTROL_SERVICE, uuid, ("read", WRITE_ANY), f"control config {uuid}") for uuid in CONFIG_CHARACTERISTICS],
    *[(CONFIG_SERVICE, uuid, ("read", WRITE_ANY), f"config service {uuid}") for uuid in CONFIG_CHARACTERISTICS],
    (ENV_SERVICE, IMU_QUATERNION, ("read", "notify"), "IMU quaternion"),
    (ENV_SERVICE, BATTERY_LEVEL, ("read", "notify"), "battery level"),
    (ENV_SERVICE, IMU_Q_VARIANCE, ("read", "notify"), "IMU variance"),
)


@dataclass(frozen=True)
class MeasurementPoint:
    frequency: float
    magnitude: float
    phase: float


@dataclass(frozen=True)
class StoredMeasurement:
    timestamp_s: int
    session_id: int
    sequence_number: int
    interval_s: int
    battery_percentage: int
    num_repetitions: int
    repetitions: list[list[MeasurementPoint]]
    quaternions: list[tuple[float, float, float, float]]
    crc16: int
    crc16_valid: bool


@dataclass(frozen=True)
class BoardHealth:
    flags: int
    battery_voltage_mv: int
    battery_percentage: int
    ad5940_adi_id: int
    ad5940_chip_id: int
    reserved: int

    @property
    def pmic_ok(self) -> bool:
        return bool(self.flags & HEALTH_FLAG_PMIC_OK)

    @property
    def ad5940_adi_id_ok(self) -> bool:
        return bool(self.flags & HEALTH_FLAG_AD5940_ADIID_OK)

    @property
    def ad5940_chip_id_known(self) -> bool:
        return bool(self.flags & HEALTH_FLAG_AD5940_CHIPID_KNOWN)


@dataclass(frozen=True)
class ContactEntry:
    pair: int
    flags: int
    frequency_hz: float
    magnitude_ohm: float
    phase_deg: float

    @property
    def pair_name(self) -> str:
        return CONTACT_PAIRS.get(self.pair, f"pair {self.pair}")

    @property
    def high(self) -> bool:
        return bool(self.flags & CONTACT_ENTRY_FLAG_HIGH)


@dataclass(frozen=True)
class ContactCheck:
    version: int
    flags: int
    threshold_ohm: int
    entries: list[ContactEntry]

    @property
    def any_high(self) -> bool:
        return bool(self.flags & CONTACT_FLAG_ANY_HIGH)


async def find_device_advertisement(name_prefix: str = "BioMess", timeout: float = 10.0):
    if BleakScanner is None:
        raise RuntimeError(f"Missing dependency: {dependency_install_hint()}")
    devices = await BleakScanner.discover(timeout=timeout, return_adv=True)
    for device, advertisement in devices.values():
        name = advertisement.local_name or device.name or ""
        if name.upper().startswith(name_prefix.upper()):
            return device, name
    raise RuntimeError(f"No BLE device found with name prefix '{name_prefix}'")


async def find_device(name_prefix: str = "BioMess", timeout: float = 10.0):
    device, _ = await find_device_advertisement(name_prefix=name_prefix, timeout=timeout)
    return device


async def connect(address: str | None, name_prefix: str = "BioMess", timeout: float = 10.0):
    if BleakClient is None:
        raise RuntimeError(f"Missing dependency: {dependency_install_hint()}")
    device = address or await find_device(name_prefix=name_prefix, timeout=timeout)
    return BleakClient(device)


def characteristic_in_service(client: BleakClient, service_uuid: str, characteristic_uuid: str):
    service = client.services.get_service(service_uuid)
    if service is None:
        raise RuntimeError(f"Service not found: {service_uuid}")

    for characteristic in service.characteristics:
        if characteristic.uuid.lower() == characteristic_uuid.lower():
            return characteristic

    raise RuntimeError(f"Characteristic {characteristic_uuid} not found in service {service_uuid}")


def parse_points(payload: bytes) -> list[MeasurementPoint]:
    if len(payload) % 12 != 0:
        raise ValueError(f"Measurement payload has {len(payload)} bytes; expected a multiple of 12")
    return [
        MeasurementPoint(*struct.unpack_from("<fff", payload, offset))
        for offset in range(0, len(payload), 12)
    ]


def parse_battery_payload(payload: bytes) -> tuple[int, int]:
    if len(payload) != 4:
        raise ValueError(f"Battery payload has {len(payload)} bytes; expected 4")
    voltage_mv, percentage = struct.unpack("<HH", payload)
    if percentage > 100:
        raise ValueError(f"Battery percentage out of range: {percentage}")
    return voltage_mv, percentage


def parse_board_health_payload(payload: bytes) -> BoardHealth:
    if len(payload) != 12:
        raise ValueError(f"Board health payload has {len(payload)} bytes; expected 12")
    health = BoardHealth(*struct.unpack("<HHHHHH", payload))
    if health.battery_percentage > 100:
        raise ValueError(f"Board health battery percentage out of range: {health.battery_percentage}")
    return health


def contact_check_payload_size(first_bytes: bytes) -> int:
    """Total payload size announced by the header (needs at least 2 bytes)."""
    if len(first_bytes) < 2:
        raise ValueError("Contact check header needs 2 bytes to know the entry count")
    return CONTACT_HEADER_SIZE + first_bytes[1] * CONTACT_ENTRY_SIZE


def parse_contact_check_payload(payload: bytes) -> ContactCheck:
    if len(payload) < CONTACT_HEADER_SIZE:
        raise ValueError(f"Contact check payload has {len(payload)} bytes; expected at least {CONTACT_HEADER_SIZE}")
    version, count, flags, threshold = struct.unpack_from("<BBHI", payload, 0)
    if version != 1:
        raise ValueError(f"Unsupported contact check payload version {version}")
    expected = contact_check_payload_size(payload)
    if len(payload) != expected:
        raise ValueError(f"Contact check payload has {len(payload)} bytes; expected {expected}")
    entries = []
    for index in range(count):
        pair, entry_flags, _reserved, freq, mag, phase = struct.unpack_from(
            "<BBHfff", payload, CONTACT_HEADER_SIZE + index * CONTACT_ENTRY_SIZE
        )
        entries.append(ContactEntry(pair, entry_flags, freq, mag, phase))
    return ContactCheck(version, flags, threshold, entries)


def crc16_ccitt(payload: bytes) -> int:
    crc = 0xFFFF
    for byte in payload:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def parse_stored_measurement(payload: bytes) -> StoredMeasurement:
    if len(payload) != STORED_RECORD_SIZE:
        raise ValueError(f"Stored measurement has {len(payload)} bytes; expected {STORED_RECORD_SIZE}")

    offset = 0
    timestamp_s, session_id, sequence_number, interval_s, battery_percentage, num_repetitions = struct.unpack_from(
        "<IHHHBB", payload, offset
    )
    offset += 12

    repetitions: list[list[MeasurementPoint]] = []
    for _ in range(STORED_REPETITIONS):
        points = []
        for _ in range(STORED_POINTS_PER_REPETITION):
            points.append(MeasurementPoint(*struct.unpack_from("<fff", payload, offset)))
            offset += 12
        repetitions.append(points)

    quaternions = []
    for _ in range(STORED_REPETITIONS):
        quaternions.append(struct.unpack_from("<ffff", payload, offset))
        offset += 16

    (crc16,) = struct.unpack_from("<H", payload, offset)
    calculated = crc16_ccitt(payload[:-2])
    return StoredMeasurement(
        timestamp_s=timestamp_s,
        session_id=session_id,
        sequence_number=sequence_number,
        interval_s=interval_s,
        battery_percentage=battery_percentage,
        num_repetitions=num_repetitions,
        repetitions=repetitions,
        quaternions=quaternions,
        crc16=crc16,
        crc16_valid=crc16 == calculated,
    )


def write_csv(points: Iterable[MeasurementPoint], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["frequency_hz", "magnitude_ohm", "phase_deg"])
        for point in points:
            writer.writerow([point.frequency, point.magnitude, point.phase])


def normalize_uuid(uuid: str) -> str:
    return uuid.lower()


def service_contract_from_bleak(services) -> dict[str, dict[str, set[str]]]:
    contract: dict[str, dict[str, set[str]]] = {}
    for service in services:
        service_uuid = normalize_uuid(str(service.uuid))
        characteristics: dict[str, set[str]] = {}
        for characteristic in service.characteristics:
            characteristics[normalize_uuid(str(characteristic.uuid))] = {
                str(prop).lower() for prop in characteristic.properties
            }
        contract[service_uuid] = characteristics
    return contract


def has_required_props(actual: set[str], required: tuple[str, ...]) -> bool:
    for prop in required:
        if prop == WRITE_ANY:
            if "write" not in actual and "write-without-response" not in actual:
                return False
        elif prop not in actual:
            return False
    return True


def validate_gatt_contract(services: Mapping[str, Mapping[str, set[str]]]) -> list[str]:
    normalized = {
        normalize_uuid(service_uuid): {
            normalize_uuid(char_uuid): {str(prop).lower() for prop in props}
            for char_uuid, props in characteristics.items()
        }
        for service_uuid, characteristics in services.items()
    }
    failures: list[str] = []
    for service_uuid in REQUIRED_SERVICES:
        if service_uuid not in normalized:
            failures.append(f"missing service {service_uuid}")

    for service_uuid, char_uuid, required_props, label in REQUIRED_CHARACTERISTICS:
        characteristics = normalized.get(service_uuid, {})
        actual_props = characteristics.get(char_uuid)
        if actual_props is None:
            failures.append(f"missing characteristic {label} {char_uuid} in {service_uuid}")
        elif not has_required_props(actual_props, required_props):
            failures.append(
                f"characteristic {label} {char_uuid} props={','.join(sorted(actual_props))} "
                f"missing required {','.join(required_props)}"
            )
    return failures


async def read_config(client: BleakClient) -> dict[str, float | int | bool | str]:
    serial = (await client.read_gatt_char(SERIAL_NUMBER)).decode("utf-8", errors="replace").strip()
    rcal = struct.unpack("<f", await client.read_gatt_char(characteristic_in_service(client, CONFIG_SERVICE, RCAL)))[0]
    sweep_enabled = bool((await client.read_gatt_char(characteristic_in_service(client, CONFIG_SERVICE, SWEEP_ENABLE)))[0])
    start = struct.unpack("<f", await client.read_gatt_char(characteristic_in_service(client, CONFIG_SERVICE, SWEEP_START_FREQ)))[0]
    stop = struct.unpack("<f", await client.read_gatt_char(characteristic_in_service(client, CONFIG_SERVICE, SWEEP_STOP_FREQ)))[0]
    points = struct.unpack("<I", await client.read_gatt_char(characteristic_in_service(client, CONFIG_SERVICE, SWEEP_POINTS)))[0]
    repetitions = (await client.read_gatt_char(characteristic_in_service(client, CONFIG_SERVICE, NUM_REPETITIONS)))[0]
    return {
        "serial": serial,
        "rcal_ohms": rcal,
        "sweep_enabled": sweep_enabled,
        "start_hz": start,
        "stop_hz": stop,
        "points": points,
        "repetitions": repetitions,
    }


async def configure_sweep(
    client: BleakClient,
    points: int | None = None,
    start_hz: float | None = None,
    stop_hz: float | None = None,
    repetitions: int | None = None,
) -> dict[str, float | int | bool | str]:
    if points is not None:
        await client.write_gatt_char(characteristic_in_service(client, CONFIG_SERVICE, SWEEP_POINTS), struct.pack("<I", points), response=True)
    if start_hz is not None:
        await client.write_gatt_char(characteristic_in_service(client, CONFIG_SERVICE, SWEEP_START_FREQ), struct.pack("<f", start_hz), response=True)
    if stop_hz is not None:
        await client.write_gatt_char(characteristic_in_service(client, CONFIG_SERVICE, SWEEP_STOP_FREQ), struct.pack("<f", stop_hz), response=True)
    if repetitions is not None:
        await client.write_gatt_char(characteristic_in_service(client, CONFIG_SERVICE, NUM_REPETITIONS), bytes([repetitions]), response=True)
    return await read_config(client)


async def _collect_control_stream(
    client: BleakClient,
    expected_bytes: int,
    timeout: float,
    start_command,
) -> bytes:
    done = asyncio.Event()
    chunks: list[bytes] = []

    def on_chunk(_, data: bytearray):
        chunks.append(bytes(data))
        if sum(len(chunk) for chunk in chunks) >= expected_bytes:
            done.set()

    await client.start_notify(CONTROL_COMMAND, on_chunk)
    try:
        if start_command is not None:
            await start_command()
        await asyncio.wait_for(done.wait(), timeout=timeout)
    finally:
        await client.stop_notify(CONTROL_COMMAND)

    return b"".join(chunks)[:expected_bytes]


async def run_measurement(client: BleakClient, expected_bytes: int, timeout: float = 45.0) -> bytes:
    async def start():
        await client.write_gatt_char(CONTROL_COMMAND, bytes([CMD_MEASUREMENT]), response=True)

    return await _collect_control_stream(client, expected_bytes, timeout, start)


async def wait_measurement_stream(client: BleakClient, expected_bytes: int, timeout: float = 45.0) -> bytes:
    return await _collect_control_stream(client, expected_bytes, timeout, None)


async def read_battery(client: BleakClient, timeout: float = 5.0) -> tuple[int, int]:
    done = asyncio.Event()
    payload = bytearray()

    def on_battery(_, data: bytearray):
        payload[:] = data
        done.set()

    await client.start_notify(BATTERY_LEVEL, on_battery)
    try:
        await client.write_gatt_char(CONTROL_COMMAND, bytes([CMD_BATTERY]), response=True)
        await asyncio.wait_for(done.wait(), timeout=timeout)
    finally:
        await client.stop_notify(BATTERY_LEVEL)

    try:
        return parse_battery_payload(bytes(payload))
    except ValueError as exc:
        raise RuntimeError(str(exc)) from exc


async def read_board_health(client: BleakClient, timeout: float = 8.0) -> BoardHealth:
    raw = await _collect_control_stream(
        client,
        expected_bytes=12,
        timeout=timeout,
        start_command=lambda: client.write_gatt_char(CONTROL_COMMAND, bytes([CMD_HEALTH_CHECK]), response=True),
    )
    try:
        return parse_board_health_payload(raw)
    except ValueError as exc:
        raise RuntimeError(str(exc)) from exc


async def get_stored_count(client: BleakClient, timeout: float = 5.0) -> int:
    done = asyncio.Event()
    payload = bytearray()

    def on_count(_, data: bytearray):
        payload[:] = data
        done.set()

    await client.start_notify(CONTROL_COMMAND, on_count)
    try:
        await client.write_gatt_char(CONTROL_COMMAND, bytes([CMD_STORED_COUNT]), response=True)
        await asyncio.wait_for(done.wait(), timeout=timeout)
    finally:
        await client.stop_notify(CONTROL_COMMAND)

    if len(payload) < 2:
        raise RuntimeError(f"Unexpected stored count payload length: {len(payload)}")
    return struct.unpack_from("<H", payload)[0]


async def read_stored_batch(
    client: BleakClient,
    offset: int = 0,
    count: int = 1,
    timeout: float = 30.0,
) -> list[StoredMeasurement]:
    expected_bytes = count * STORED_RECORD_SIZE
    done = asyncio.Event()
    chunks: list[bytes] = []

    def on_chunk(_, data: bytearray):
        chunks.append(bytes(data))
        if sum(len(chunk) for chunk in chunks) >= expected_bytes:
            done.set()

    payload = struct.pack("<HB", offset, count)
    await client.start_notify(CONTROL_COMMAND, on_chunk)
    try:
        await client.write_gatt_char(CONTROL_COMMAND, bytes([CMD_STORED_BATCH]) + payload, response=True)
        await asyncio.wait_for(done.wait(), timeout=timeout)
    finally:
        await client.stop_notify(CONTROL_COMMAND)

    raw = b"".join(chunks)[:expected_bytes]
    return [
        parse_stored_measurement(raw[i : i + STORED_RECORD_SIZE])
        for i in range(0, len(raw), STORED_RECORD_SIZE)
    ]


async def clear_stored(client: BleakClient, timeout: float = 5.0) -> int:
    done = asyncio.Event()
    payload = bytearray()

    def on_count(_, data: bytearray):
        payload[:] = data
        done.set()

    await client.start_notify(CONTROL_COMMAND, on_count)
    try:
        await client.write_gatt_char(CONTROL_COMMAND, bytes([CMD_CLEAR_STORED]), response=True)
        await asyncio.wait_for(done.wait(), timeout=timeout)
    finally:
        await client.stop_notify(CONTROL_COMMAND)

    return struct.unpack_from("<H", payload)[0] if len(payload) >= 2 else 0


async def start_auto_mode(client: BleakClient, interval_s: int) -> None:
    await client.write_gatt_char(
        CONTROL_COMMAND,
        bytes([CMD_START_AUTO]) + struct.pack("<H", interval_s),
        response=True,
    )


async def stop_auto_mode(client: BleakClient) -> None:
    await client.write_gatt_char(CONTROL_COMMAND, bytes([CMD_STOP_AUTO]), response=True)
