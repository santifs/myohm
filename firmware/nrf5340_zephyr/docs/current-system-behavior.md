# BioMess current system behavior

Last updated: 2026-06-09.

This document describes how the BioMess nRF5340 firmware behaves today, from power-on to BLE measurement. It is intended as the first reference before changing runtime behavior, power management, BLE protocol timing, button behavior, or AD5940 measurement flow.

## System overview

The current firmware is a Zephyr/nRF Connect SDK application for the BioMess PCB v2:

- MCU: nRF5340 application core plus HCI IPC network core.
- PMIC: nPM1304 on I2C1, address `0x6b`.
- AFE: AD5940 over SPIM2 plus manual chip select and GPIO interrupt.
- Mobile transport: BLE peripheral named `BioMess`.
- Main build target: `biomess_nrf5340/nrf5340/cpuapp`.
- Runtime protocol: GATT services `AF00..AF03`, command/stream characteristic `0xC000`.

At a high level:

1. nPM1304 powers the board and owns the real off/storage state.
2. nRF5340 owns BLE, command handling, status LED, nPM1304 host control, and AD5940 orchestration.
3. AD5940 wakes only for register access and measurement sweeps, then returns to sleep/hibernate.

## Boot flow

On reset or PMIC wake:

1. `main.c` waits 3 seconds to give the UART console a chance to attach.
2. The status LED on `P1.10` is configured as an active-high output.
3. `board_power_init()` initializes nPM1304 access, registers PMIC event callbacks, and reads initial VBUS state.
4. `ble_service_init()` initializes Bluetooth, GATT services, command queues, stored-record RAM, and starts fast connectable advertising as `BioMess`.
5. `AD5940_MCUResourceInit()` configures SPI, manual CS, AD5940 reset and interrupt GPIO.
6. `main.c` registers the power-button callback used to restart fast advertising on short press.
7. The status LED blinks once with the boot status pattern, then the main thread sleeps forever.

Boot LED pattern:

| Pulses | Meaning |
| ---: | --- |
| 1 | BLE and AD5940 initialized |
| 2 | BLE failed, AD5940 initialized |
| 3 | BLE initialized, AD5940 failed |
| 4 | BLE and AD5940 failed |

There is no continuous heartbeat LED anymore. This is intentional for power consumption. The LED can still be blinked through BLE command `0x64` for diagnostics.

## BLE lifecycle

Advertising data:

- Device name: `BioMess`.
- Primary advertised service: `0000af00-0000-1000-8000-00805f9b34fb`.
- Mobile apps accept either the `BioMess` name prefix or the `AF00` service.

Advertising policy:

1. On boot, after disconnect, or after a short button press, firmware starts fast connectable advertising.
2. Fast advertising lasts 60 seconds.
3. If no central connects, firmware switches to slower connectable advertising.
4. Slow advertising remains connectable; the product does not currently stop advertising after a long timeout.
5. If a central is already connected, advertising restart requests are ignored.

Current advertising intervals:

| Mode | Interval units | Approximate interval |
| --- | ---: | ---: |
| Fast | Bluetooth GAP fast interval 2 | 100-150 ms |
| Slow | `1600..1920` units | 1000-1200 ms |

Connection policy:

| State | Requested interval | Latency | Supervision timeout |
| --- | ---: | ---: | ---: |
| Connected idle | 250-500 ms | 4 | 6000 ms |
| Measurement/streaming | 30-50 ms | 0 | 4000 ms |

The phone is allowed to accept, reject, or modify requested connection parameters. The firmware logs failures and keeps running. The app protocol must therefore not assume that every request is accepted; it should rely on notifications and protocol framing, not on a fixed connection interval.

On disconnect:

- `current_conn` is released.
- RAM-backed auto mode is stopped.
- Slow-advertising timer is cancelled.
- Fast advertising is scheduled after 250 ms.

## Measurement flow

The app starts a measurement by writing command `0x01` to characteristic `0xC000`.

Firmware behavior:

1. Rejects concurrent measurements with `-EBUSY`.
2. Copies the active sweep config under mutex.
3. Clears the RAM stored-record builder.
4. Requests measurement BLE connection parameters.
5. Waits 350 ms if the request was accepted locally, giving the link time to settle.
6. Calls `AD5940_RunSweep()`.
7. Streams each point through notifications on `0xC000`.
8. Flushes any remaining notification bytes.
9. Requests idle BLE connection parameters.
10. Saves a RAM-backed stored record if the sweep succeeded.

Each live point is 12 bytes:

| Offset | Type | Meaning |
| ---: | --- | --- |
| 0 | `float32` little-endian | Frequency in Hz |
| 4 | `float32` little-endian | Impedance magnitude in ohms |
| 8 | `float32` little-endian | Phase in degrees |

The firmware chunks notifications according to the negotiated ATT MTU (`MTU - 3`) and never assumes a fixed notification size. Mobile clients must reassemble until they have `points * repetitions * 12` bytes.

Default measurement configuration is the AD5940 default sweep config:

- Rcal: 30 ohms.
- Start frequency: 4 kHz.
- Stop frequency: 198 kHz.
- Points: 48.
- Repetitions: 5.
- AFE mode: low power.
- AD5940 system/ADC clock path: 16 MHz / 800 kSPS.

## AD5940 behavior

AD5940 runtime behavior is intentionally measurement-driven:

1. SPI, CS, reset and interrupt are initialized at boot.
2. `AD5940_RunSweep()` reinitializes platform and BIA configuration before a sweep.
3. The sweep sequence wakes the AFE, reads FIFO data on interrupts, processes DFT output, and streams processed points.
4. During the ISR path, sleep is locked while FIFO is read and unlocked afterwards.
5. After each sequence/ISR path, the code calls `AD5940_EnterSleepS()`.
6. After a complete sweep, the code calls `AD5940_ShutDownS()` so the AFE returns to hibernate.

Important AD5940 implementation details:

- Chip select is manual GPIO, not Zephyr-managed `cs-gpios`.
- `AD5940_CsClr()` includes wake delays because SPI access can wake the AD5940 from hibernate.
- The AD5940 library expects multiple SPI transactions inside one CS assertion; automatic CS would break register access.
- Negative resistance in earlier testing was caused by config/calibration mismatch, not by BLE framing.

## nPM1304 and button behavior

The nPM1304 is connected to nRF5340 through:

| Signal | nRF pin | Meaning |
| --- | --- | --- |
| `SCL_nPM` | `P0.24` | I2C1 SCL |
| `SDA_nPM` | `P0.26` | I2C1 SDA |
| `INT_nPM` | `P0.28` | nPM1304 GPIO0 interrupt into nRF5340 |
| `SHPHLD` | `nPM1304 SHPHLD` | Physical power button input to the PMIC |

PMIC devicetree settings:

```dts
host-int-gpios = <&gpio0 28 0>;
pmic-int-pin = <0>;
ship-to-active-time-ms = <96>;
long-press-reset = "one-button";
```

Runtime button behavior:

| User action | Firmware/PMIC result |
| --- | --- |
| Short press while off/in Ship | PMIC wakes the board |
| Short press while firmware is running and not connected | Firmware restarts fast BLE advertising |
| Short press while connected | Advertising restart is ignored because BLE is already connected |
| Hold for 3 s while VBUS is absent | One long LED pulse indicates shutdown is armed; release asks nPM1304 regulators to enter Ship mode |
| Hold for 3 s while VBUS is present | One long LED pulse indicates shutdown is armed, but release cannot enter Ship while USB/VBUS is present |
| PMIC hardware long press reset threshold | PMIC can power-cycle according to `long-press-reset = "one-button"` |

Ship mode is the product off/storage state. The nRF is not sleeping in this state; it is powered off by the PMIC. BLE is not active, and wake is a fresh boot.

nPM1304 Hibernate timer is not implemented. It should only be added for scheduled autonomous wakeups, not for normal between-series user flow, because timer-only wake creates poor UX if the user wants immediate reconnect.

## Power states

| State | Owner | Current behavior | Exit |
| --- | --- | --- | --- |
| Ship/off | nPM1304 | PMIC removes system power after a 3 s hold plus release if no VBUS is present | Short button press or USB/VBUS |
| Boot | nRF5340 + nPM1304 | Initialize PMIC, BLE, AD5940 resources; blink LED status once | Automatic |
| Ready fast | nRF5340 BLE | Connectable advertising at 100-150 ms for 60 s | App connects, timeout to slow, or 3 s press to Ship |
| Ready slow | nRF5340 BLE | Connectable advertising at 1.0-1.2 s | App connects, short press restarts fast, or 3 s press to Ship |
| Connected idle | nRF5340 BLE | BLE connected, requested interval 250-500 ms with latency 4; AD5940 hibernated | Measurement command, disconnect, or 3 s press to Ship |
| Measuring | nRF5340 + AD5940 | Requested interval 30-50 ms; AD5940 runs sweep; data streams on `0xC000` | Sweep complete returns to connected idle |
| Auto mode | nRF5340 + AD5940 | Periodic sweep while BLE remains connected | Stop command or disconnect |

`CONFIG_PM_DEVICE` and `CONFIG_PM_DEVICE_RUNTIME` are enabled for the app core. This lets Zephyr place idle-capable devices in lower-power states when drivers support it. This is not the same thing as PMIC Ship mode.

## Stored measurements and auto mode

Stored sync is currently a RAM ring buffer:

- Capacity: 4 records.
- Record size: 2974 bytes.
- Layout: fixed Android/iOS `StoredMeasurement` layout.
- Records are lost on reset, Ship, firmware crash, or power loss.

Manual and auto sweeps both save completed records in this RAM buffer. Auto mode:

- Starts with command `0x05`.
- Stops with command `0x06`.
- Uses interval payload clamped to `60..3600` seconds, default 300 seconds.
- Stops automatically on BLE disconnect.

This is deliberate until flash persistence is designed. Do not rely on current stored sync for offline use.

## Diagnostics and verification

Useful BLE commands:

| Command | Purpose |
| --- | --- |
| `0x02` | Battery voltage/percentage via nPM1304 |
| `0x0A` | Board health: PMIC + AD5940 identity |
| `0x64` | Blink status LED three times |
| `0x07/0x08/0x09` | Stored count, stored batch, clear stored records |

Expected health values:

- PMIC flag set when battery read succeeds.
- AD5940 ADIID expected: `0x4144`.
- AD5940 CHIPID known range: `0x5500..0x5502`.

Build and offline verification:

```bash
make -C firmware/nrf5340_zephyr verify
```

Flash and full board verification when a debugger is visible:

```bash
make -C firmware/nrf5340_zephyr flash
make -C firmware/nrf5340_zephyr ble
```

If `nrfjprog --ids` is empty, flashing cannot proceed even if USB serial ports are visible.

## Current implementation constraints

- BLE service UUIDs and payload formats are shared with Android/iOS tests; change them only with mobile updates.
- Config characteristics are duplicated in Control and Config services for iOS compatibility.
- Live sweep streaming uses raw concatenated points; no per-sweep header is currently sent.
- Stored records are fixed to 5 x 48 points even if live sweep configuration changes; unused slots are zero-filled and excess live points are not stored.
- UART boot-log capture is still unreliable on the current bench setup; BLE health/sweep checks are stronger evidence today.
- Network core image must be programmed together with the app image after recover. Programming only app core can leave BLE initialization failing.
- The current firmware keeps slow advertising active indefinitely. This preserves reconnect UX but still consumes battery.

## Future items to keep in mind

Prioritize future work from measurement evidence, not intuition:

1. Measure current in Ship/off, fast advertising, slow advertising, connected idle, measurement, and auto mode.
2. Decide whether slow advertising should stop after a longer timeout and require short press for reconnect.
3. Add a production build profile with UART/logging reduced or disabled after bring-up.
4. Add flash-backed stored measurements before relying on auto mode through disconnects or power cycles.
5. Validate iOS acceptance of idle and measurement connection-parameter requests with real devices.
6. Revisit BLE subrating only after confirming iOS support and benefit; it is not a first-line dependency.
7. Add nPM1304 Hibernate timer only for scheduled autonomous measurements, not normal manual use.
8. Confirm the final `SHPHLD/RESET` and nPM1304 GPIO0 interrupt timing before freezing production button behavior.
9. Decide whether `long-press-reset = "one-button"` should remain enabled for production or be changed to a safer reset policy.
10. Add IMU integration or remove/rename placeholder IMU commands before product release if they remain unused.
11. Build a current-consumption validation report and store it next to board validation evidence.
