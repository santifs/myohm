# BioMess BLE protocol

This firmware implements the BioMess protocol used by the Android and iOS apps in this repo. For app-side source paths and integration rules, see `mobile-integration.md`.

## Advertising

- The advertised name is `CONFIG_BT_DEVICE_NAME`. `prj.conf` defaults to `BioMess`, but build overlays can override it. The local `label.conf` sets the name and serial to `Messi-06`; the current build applies it through `EXTRA_CONF_FILE` and its generated `.config` confirms that name. Verify the effective build configuration rather than assuming the default is flashed.
- Current `src/ble_service.c` advertises flags and the complete device name only. Service `0000af00-0000-1000-8000-00805f9b34fb` exists in GATT but is **not included in advertising**. A service-only discovery filter will miss this firmware.
- BioMess Lab accepts the known name prefixes `BioMess` and `Messi-`, plus the service UUID for firmware versions that advertise it. For any new naming scheme, update discovery clients or provide an explicit unfiltered device picker; validate the GATT services after selection.
- A live scan on 2026-09-08 detected `Messi-06` without an advertised service UUID, consistent with the current build.
- Firmware starts fast connectable advertising on boot, after disconnect, and after a short button press when not connected.
- Fast advertising lasts 60 seconds and uses the Bluetooth GAP fast interval 2 range, approximately 100-150 ms.
- If no central connects during the fast window, firmware switches to slower connectable advertising at approximately 1.0-1.2 s.
- Slow advertising does not currently stop by timeout; this preserves reconnect UX at the cost of idle advertising current.
- On connection, firmware requests idle connection parameters: 250-500 ms interval, peripheral latency 4, 6000 ms supervision timeout.
- During measurement command `0x01`, firmware temporarily requests measurement connection parameters: 30-50 ms interval, latency 0, 4000 ms supervision timeout, then returns to idle parameters after the sweep.

Central devices can reject or modify connection-parameter requests. Mobile clients must treat those parameters as power hints, not as a protocol guarantee.

## Services

| Service | UUID | Purpose |
| --- | --- | --- |
| Control | `0000af00-0000-1000-8000-00805f9b34fb` | Commands, streaming notifications, serial number, duplicated config writes for iOS compatibility. |
| Config | `0000af01-0000-1000-8000-00805f9b34fb` | Sweep configuration reads/writes. |
| Data | `0000af02-0000-1000-8000-00805f9b34fb` | Reserved for legacy per-point characteristics. Current apps use streaming on `0xC000`. |
| Environment | `0000af03-0000-1000-8000-00805f9b34fb` | Battery and IMU notifications. |

## Characteristics

| Characteristic | UUID | Properties | Format |
| --- | --- | --- | --- |
| Control command | `0000c000-0000-1000-8000-00805f9b34fb` | Write, Notify | Command writes. Measurement/stored responses as notifications. |
| Serial number | `0000c001-0000-1000-8000-00805f9b34fb` | Read | UTF-8 string. |
| RCAL | `0000c011-0000-1000-8000-00805f9b34fb` | Read, Write | `float32` ohms, little-endian. |
| Sweep enable | `0000c012-0000-1000-8000-00805f9b34fb` | Read, Write | `uint8`, `0` or `1`. |
| Sweep start | `0000c013-0000-1000-8000-00805f9b34fb` | Read, Write | `float32` Hz, little-endian. |
| Sweep stop | `0000c014-0000-1000-8000-00805f9b34fb` | Read, Write | `float32` Hz, little-endian. |
| Sweep points | `0000c015-0000-1000-8000-00805f9b34fb` | Read, Write | `uint32`, little-endian. Firmware clamps to `2..100` because log/linear sweep spacing requires at least two endpoints. |
| Repetitions | `0000c017-0000-1000-8000-00805f9b34fb` | Read, Write | `uint8`. Firmware clamps to `1..10`. |
| Excitation amplitude (optional) | `0000c018-0000-1000-8000-00805f9b34fb` | Read, Write | `uint16` mVpp at the HSDAC, little-endian. Firmware clamps to `50..800`. See [Excitation amplitude](#excitation-amplitude). |
| IMU quaternion | `0000c201-0000-1000-8000-00805f9b34fb` | Read, Notify | Four `float32` values. Currently zero-filled. |
| Battery level | `0000c202-0000-1000-8000-00805f9b34fb` | Read, Notify | `uint16 voltage_mv`, `uint16 percentage`, little-endian. |
| IMU variance | `0000c203-0000-1000-8000-00805f9b34fb` | Read, Notify | Four `float32` values. Currently zero-filled. |

Config characteristics are intentionally present in both Control and Config services because the current iOS code writes some config values through `AF00` and reads them through `AF01`.

`0xC018` was added after the Android, iOS and web clients in this repository were written. It is appended as the last characteristic of `AF00` and `AF01`, so clients that look characteristics up by UUID keep working and simply use the build default. The addition does shift the attribute handles of later services; clients that cache handles across firmware updates must rediscover services (the firmware exposes Service Changed and the GATT database hash). Clients should treat `0xC018` as optional and check for it before writing.

Clients should read `Sweep points` (`0xC015`) after writing configuration and use the returned value to calculate expected stream length. The firmware clamps points to `2..100`; Android and iOS are patched to use the firmware-effective value before waiting for measurement bytes.

## Commands

Write one opcode byte plus optional little-endian payload to `0xC000`.

| Opcode | Name | Payload | Response |
| --- | --- | --- | --- |
| `0x01` | Measurement | none | Streams `points * repetitions * 12` bytes on `0xC000`. |
| `0x02` | Battery manual | none | Notifies `0xC202` with 4-byte battery payload. |
| `0x03` | IMU single | none | Notifies zero quaternion on `0xC201`. |
| `0x04` | IMU stats | none | Notifies zero quaternion on `0xC201`. |
| `0x05` | Start auto mode | `uint16 interval_seconds` | Runs periodic AD5940 sweeps while connected. Firmware clamps interval to `60..3600` seconds. |
| `0x06` | Stop auto mode | none | Stops future auto-mode scheduling. |
| `0x07` | Get stored count | none | Notifies `0xC000` with `uint16 count`. |
| `0x08` | Get stored batch | `uint16 offset`, `uint8 count` | Notifies `count` stored records, fragmented by MTU. |
| `0x09` | Clear stored | none | Clears RAM ring buffer and notifies `uint16 0`. |
| `0x0A` | Health check | none | Notifies a 12-byte PMIC + AD5940 diagnostic payload on `0xC000`. |
| `0x0B` | Contact check | none | Two-wire impedance of four electrode pairs at 10 and 100 kHz. Notifies a 136-byte payload on `0xC000`, fragmented by MTU. See [Contact check payload](#contact-check-payload). |
| `0x64` | LED blink | none | Blinks status LED three times. |

## Health check payload

Command `0x0A` is intended for factory bring-up and quick bench diagnostics before running a full impedance sweep.

| Offset | Type | Meaning |
| --- | --- | --- |
| `0` | `uint16` | Flags: bit 0 PMIC read OK, bit 1 AD5940 ADIID OK, bit 2 AD5940 CHIPID part known. |
| `2` | `uint16` | Battery voltage in mV. |
| `4` | `uint16` | Battery percentage estimate. |
| `6` | `uint16` | AD5940 ADIID register. Expected value: `0x4144`. |
| `8` | `uint16` | AD5940 CHIPID register. Known AD5940 parts report `0x5500..0x5502`. |
| `10` | `uint16` | Reserved, currently `0`. |

## Excitation amplitude

The sweep excitation is set by the HSDAC amplitude (`DacVoltPP`) and the excitation buffer gain of 2, so the voltage at CE0 is twice the configured value. The current into `I+` is limited by the 1 kohm series resistor RL1; with contacts and tissue in series it is lower.

| HSDAC amplitude | Voltage at CE0 | Short-circuit current | Use |
| ---: | ---: | ---: | --- |
| 800 mVpp | 1.6 Vpp | 0.57 mA rms | Build default (`CONFIG_MYOHM_EXCITATION_MVPP=800`). Setting used for all published Myohm data. Outside the +/-607 mV range over which the AD5941 output is specified. |
| 500 mVpp | 1.0 Vpp | 0.35 mA rms | **Recommended for measurements on people.** |

The build default comes from `CONFIG_MYOHM_EXCITATION_MVPP` (range `50..800`). A client can override it by writing `0xC018` before command `0x01` or `0x05`; the value is kept in RAM until reset and applies to manual and auto-mode sweeps. Changing the amplitude changes the signal-to-noise ratio, not the calibration: RTIA is calibrated against RCAL at each frequency independently of `DacVoltPP`. Data acquired at different amplitudes should still be compared with care until this has been checked on the bench. The amplitude is not stored in measurement records.

## Contact check payload

Command `0x0B` checks the electrode contacts before a sweep. For each pair the AD5941 switch matrix connects the excitation buffer (D and P switches) to one electrode pin and the high-speed TIA (N and T switches) to the other, and measures a two-wire impedance at 10 kHz and 100 kHz. An RCAL measurement in the same configuration provides the reference (ratio method). The excitation is fixed at 40 mVpp at the pins (HSDAC gain 0.2, excitation buffer gain 0.25), independent of `0xC018`. With 200 ohm between two electrodes the current is 0.2 mApp (71 uA rms); pairs through RL1 stay below 14 uA rms. The check takes roughly one second, resets the AD5941 and leaves it in hibernate; the next sweep reinitializes it.

| Pair id | Pair | Route on this board | Board series elements subtracted |
| ---: | --- | --- | --- |
| `0` | `I+`/`I-` | CE0 (drive) to AIN1 (TIA) | RL1 1 kohm + 2 x 4.7 uF |
| `1` | `V+`/`V-` | AIN2 (drive) to AIN3 (TIA) | 2 x 4.7 uF |
| `2` | `I+`/`V+` | CE0 (drive) to AIN2 (TIA) | RL1 1 kohm + 2 x 4.7 uF |
| `3` | `I-`/`V-` | AIN3 (drive) to AIN1 (TIA) | 2 x 4.7 uF |

All four pairs are reachable with the AD5941 matrix on this board. Each reported value is the sum of the two contact impedances and the tissue between them, after subtracting RL1 and the coupling capacitors with their nominal values. Pairs `0` and `2` carry the RL1 tolerance (not specified in the BOM; 1 % would be +/-10 ohm).

Header (8 bytes, little-endian):

| Offset | Type | Meaning |
| --- | --- | --- |
| `0` | `uint8` | Payload version, currently `1`. |
| `1` | `uint8` | Entry count `N`, currently `8` (4 pairs x 2 frequencies). Total size is `8 + 16 * N` bytes. |
| `2` | `uint16` | Global flags: bit 0 any entry high, bit 1 any entry invalid or over range, bit 2 AFE error (AD5941 not detected, RCAL reference failed or DFT timeout). |
| `4` | `uint32` | High-contact threshold in ohms (`CONFIG_MYOHM_CONTACT_HIGH_OHMS`, default 3000). |

Entry (16 bytes), ordered by pair and then frequency:

| Offset | Type | Meaning |
| --- | --- | --- |
| `0` | `uint8` | Pair id (table above). |
| `1` | `uint8` | Flags: bit 0 high (`|Z|` above threshold), bit 1 invalid (not measured), bit 2 open (no measurable current, `|Z|` is `+inf`), bit 3 over range (TIA beyond its linear swing, very low impedance, `|Z|` unreliable). |
| `2` | `uint16` | Reserved, `0`. |
| `4` | `float32` | Frequency in Hz (`10000` or `100000`). |
| `8` | `float32` | `|Z|` in ohms, board series elements subtracted. `NaN` when invalid. |
| `12` | `float32` | Phase in degrees. Capacitive loads are expected negative, as in the sweep; the sign has not been verified on hardware. `NaN` when invalid. |

The payload is always `8 + 16 * N` bytes, also on failure (entries then carry the invalid flag). Clients reassemble notifications until they have that length, as for the measurement stream. Contact impedance falls with frequency, so the 10 kHz entries are normally the deciding ones. A high pair implicates one or both of its electrodes; comparing pairs that share an electrode (for example `0` and `2` for `I+`) localizes it.

## Measurement stream

Each measurement point is 12 bytes:

| Offset | Type | Meaning |
| --- | --- | --- |
| `0` | `float32` | Frequency in Hz. |
| `4` | `float32` | Impedance magnitude in ohms. |
| `8` | `float32` | Phase in degrees. |

The firmware sends a raw concatenation of points. BLE notification fragmentation is transport-level only; clients reassemble chunks until they have `points * repetitions * 12` bytes and must not assume any fixed notification chunk size. The firmware caps each notification at the negotiated ATT payload limit (`MTU - 3`) so the stream also works with the default 23-byte ATT MTU.

## Stored measurement sync

The firmware stores completed sweeps in a RAM ring buffer with 4-record capacity. This is useful for validating the mobile sync path before adding flash persistence.

Each record uses the Android/iOS `StoredMeasurement` layout:

| Field | Size | Format |
| --- | ---: | --- |
| Timestamp | 4 | `uint32`, seconds since boot. |
| Session ID | 2 | `uint16`. Incremented when auto mode starts. |
| Sequence number | 2 | `uint16`. |
| Interval | 2 | `uint16`, auto-mode interval or `0` for manual. |
| Battery percentage | 1 | `uint8`. |
| Num repetitions | 1 | `uint8`, actual configured repetitions clamped to 5 for this fixed layout. |
| Points | 2880 | `5 * 48` measurement points, each `float32 frequency`, `float32 magnitude`, `float32 phase`. |
| Quaternions | 80 | `5 * 4` zero-filled `float32` values until IMU hardware is integrated. |
| CRC16 | 2 | CRC16-CCITT over all previous bytes, initial value `0xFFFF`, polynomial `0x1021`. |

Total size: 2974 bytes. If the live sweep is configured with fewer than 5 repetitions or fewer than 48 points, unused slots are zero-filled. If it has more, only the first 5 x 48 points are stored; the live stream still sends the full configured sweep.

## Current limitations

- The contact check (`0x0B`) and the excitation amplitude characteristic (`0xC018`) compile but have not been validated on hardware. Android, iOS and the web client do not use them yet.

- Stored measurements are RAM-backed only; they are lost on reset and capped to the last 4 records.
- Auto mode stops on BLE disconnect because this firmware does not yet persist records to flash.
- IMU commands return zero-filled quaternion data until the IMU driver is integrated.
