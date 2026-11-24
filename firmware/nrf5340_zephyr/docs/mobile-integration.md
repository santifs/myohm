# Android/iOS BLE integration notes

This firmware is built for the Android and iOS clients already present in this repo. Use this document when changing the BLE firmware, touching mobile BLE code, or debugging an app/firmware mismatch.

## Source map

| Concern | Android | iOS | Firmware |
| --- | --- | --- | --- |
| UUID constants | `mobile/android/core-ble/src/main/kotlin/com/volumhealth/core/ble/BioMessBleUuids.kt` | `mobile/ios/VolumHealthAppPackage/Sources/VolumHealthAppFeature/BLE/BioMessBLEManager.swift` | `firmware/nrf5340_zephyr/src/ble_service.c` |
| Command opcodes | `mobile/android/core-ble/src/main/kotlin/com/volumhealth/core/ble/BioMessCommand.kt` | `BioMessBLEManager.swift`, `BioMessCommands` enum | `COMMAND_*` defines in `ble_service.c` |
| Live measurement reassembly | `BioMessBleManager.kt` | `BioMessBLEManager.swift` | notifications on `0xC000` |
| Stored measurement parser | `mobile/android/core-model/src/main/kotlin/com/volumhealth/core/model/StoredMeasurement.kt` | `Sources/VolumHealthAppFeature/Models/StoredMeasurement.swift` | RAM ring buffer in `ble_service.c` |
| Protocol contract check | `firmware/nrf5340_zephyr/tools/test_protocol_contract.py` | same | same |

Run this after any firmware/mobile protocol change:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile-tests
```

## Discovery and connection

The firmware advertises:

- Device name: `BioMess`
- Primary service: `0000af00-0000-1000-8000-00805f9b34fb`

The current apps accept advertisements by name prefix (`BioMess`) or by the advertised control service `AF00`. This avoids depending on whether the OS exposes the scan-response local name before the service UUID. If apps cannot find the board, first prove advertisement with:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/ble_probe.py
```

## Measurement flow

The mobile clients must use the streaming path, not legacy per-point reads:

1. Subscribe to `0xC000` notifications.
2. Optionally write config characteristics `0xC011-0xC017`.
3. Read back `0xC015` sweep points after writing config.
4. Read `0xC017` repetitions.
5. Write command `0x01` to `0xC000`.
6. Reassemble notifications until `points * repetitions * 12` bytes arrive.
7. Parse each point as little-endian `float32 frequency_hz`, `float32 magnitude_ohm`, `float32 phase_deg`.

The firmware clamps sweep points to `2..100` and repetitions to `1..10`, so clients must use the firmware-effective values, not the requested values. Android and iOS in this repo already do this; the contract test checks for the relevant code paths.

## Config write compatibility

Config characteristics are exposed in both services:

- Control service `AF00`
- Config service `AF01`

This is intentional. Some iOS paths write configuration through `AF00`, while other reads use `AF01`. Do not remove the duplicated characteristics unless the mobile code is migrated and `test_protocol_contract.py` is updated.

All floats and integers in BLE payloads are little-endian. iOS must use explicit byte helpers rather than aligned raw loads from `Data`; the contract test rejects `withUnsafeBytes` in the touched BLE parsing paths.

## Commands used by apps and scripts

| Opcode | Use |
| --- | --- |
| `0x01` | Start live AD5940 sweep stream. |
| `0x02` | Manual battery read. |
| `0x03` | IMU single placeholder. |
| `0x04` | IMU stats placeholder. |
| `0x05` | Start auto mode. |
| `0x06` | Stop auto mode. |
| `0x07` | Get stored measurement count. |
| `0x08` | Get stored measurement batch. |
| `0x09` | Clear stored measurements. |
| `0x0A` | Board health diagnostic for scripts/factory bring-up. |
| `0x64` | LED blink diagnostic. |

The mobile apps do not need to call `0x0A`, but keeping the opcode in mobile enums prevents future command drift and makes factory/debug builds straightforward.

## Stored sync flow

The firmware stores completed sweeps in a RAM ring buffer with the same fixed layout used by Android/iOS:

- Record size: 2974 bytes.
- Repetitions in stored layout: 5.
- Points per repetition in stored layout: 48.
- CRC16-CCITT over the record excluding the final CRC field.

Client flow:

1. Subscribe to `0xC000`.
2. Write `0x07`; expect `uint16 count`.
3. Write `0x08 + uint16 offset + uint8 count`.
4. Reassemble `count * 2974` bytes from `0xC000`.
5. Parse records and validate CRC.

Stored sync is RAM-backed only for now. It is useful to validate the mobile sync path, but records are lost on reset and auto mode stops on BLE disconnect.

## App-facing verification

Use scripts first, then apps:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/ble_probe.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/test_board_health.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/test_ad5940_sweep.py --points 48 --repetitions 5 --csv /tmp/biomess_sweep.csv
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/test_stored_sync.py --count 1
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile-tests
```

If these pass and a mobile app still fails, inspect app-side state, notification subscription timing, BLE cache/pairing state and device selection before changing firmware.

## Change checklist

Before changing UUIDs, opcodes, stream layout, stored layout or endian handling:

1. Update firmware and both mobile clients together.
2. Update `docs/ble-protocol.md`.
3. Update `tools/biomess_ble.py` helpers.
4. Update `tools/test_protocol_contract.py`.
5. Run:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile-tests
```
