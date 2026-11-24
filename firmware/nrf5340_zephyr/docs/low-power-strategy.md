# BioMess low-power strategy

Last updated: 2026-06-09.

This document describes the current power behavior of the BioMess nRF5340 firmware and the intended product-level low-power model. The main point is that "low power" exists at three different layers and they are not interchangeable:

- nPM1304 PMIC: system power states, battery charger and regulators.
- nRF5340: MCU and BLE runtime power states.
- AD5940: analog front-end measurement power mode and hibernate.

## User-facing behavior today

Current firmware behavior:

1. A short press on `SHPHLD/RESET` wakes the device from nPM1304 Ship/Hibernate mode. The configured wake press time is `ship-to-active-time-ms = <96>`, so this is effectively a normal short button press.
2. On boot, the nRF5340 starts a fast BLE advertising window as `BioMess`, initializes the nPM1304 interface, initializes the AD5940 SPI/GPIO port, blinks the status LED once with the boot status, then leaves the LED off.
3. The mobile app connects over BLE and sends measurement command `0x01`.
4. If no central connects during the fast window, advertising remains connectable but falls back to a slower interval.
5. While connected but idle, firmware requests slower BLE connection parameters. During measurement, it temporarily requests faster parameters before running the sweep and returns to idle parameters afterwards.
6. The AD5940 wakes, runs the sweep, streams points over BLE, and returns to AD5940 hibernate after the measurement flow.
7. A short press while the firmware is running restarts the fast advertising window if the device is not connected.
8. Holding the button for 3 seconds while the firmware is running shows one long LED pulse and then leaves the LED off. On release, firmware asks the nPM1304 to enter Ship mode, but only if USB VBUS is absent.
9. Connecting USB/VBUS can wake or keep the PMIC active. Ship entry is intentionally blocked while VBUS is present.

There is no implemented "screen-off style standby" in which the nRF5340 remains in a deep MCU sleep and periodically wakes itself. There is also no implemented nPM1304 Hibernate timer flow for scheduled autonomous wakeups.

## nPM1304 layer

The nPM1304 owns whole-board power states. It is connected to the nRF5340 through:

- I2C1 at address `0x6b`.
- `SCL_nPM = P0.24`.
- `SDA_nPM = P0.26`.
- PMIC interrupt output GPIO0 to nRF `P0.28`.
- Button on the PMIC `SHPHLD/RESET` path. It is not read as a direct nRF GPIO in firmware.

In devicetree:

```dts
npm1304_pmic: pmic@6b {
    compatible = "nordic,npm1304";
    reg = <0x6b>;
    host-int-gpios = <&gpio0 28 0>;
    pmic-int-pin = <0>;
    ship-to-active-time-ms = <96>;
    long-press-reset = "one-button";
};
```

Ship mode:

- Entered by host firmware calling `regulator_parent_ship_mode(npm1304_regulators)`.
- In our firmware this happens after `SHPHLD` has been held for 3 seconds and then released. Release is not required to trigger the long-press feedback, but it is required before cutting power so the held button cannot immediately wake the PMIC again.
- The nRF5340 is not "hibernating itself" here; it asks the PMIC to remove system power. After that, the nRF is off.
- Exit is handled by the PMIC when `SHPHLD` is held low for the configured `ship-to-active-time-ms`, or by USB/VBUS.

Hibernate mode:

- nPM1304 Hibernate is effectively Ship mode with the PMIC low-power timer running as an extra wake source.
- We do not currently use nPM1304 Hibernate mode.
- To use it in the future, firmware would need to configure the nPM1304 timer and write the PMIC hibernate task instead of ship mode.

Long-press reset:

- `long-press-reset = "one-button"` leaves the PMIC hardware long-press reset path enabled.
- This is separate from our 3 second application shutdown policy.
- If the user holds the button long enough for the PMIC reset threshold, the PMIC can power-cycle the system regardless of our firmware policy.

## nRF5340 layer

The nRF5340 now uses a first-pass low-power runtime policy:

- Internal nRF regulator mode is set to DCDC for main and radio rails.
- Bluetooth advertising starts in a fast connectable window for 60 seconds, then switches to a slower connectable interval of roughly 1.0-1.2 s.
- A short button press restarts the fast advertising window.
- Connected idle requests 250-500 ms BLE connection interval with peripheral latency 4.
- Measurement requests 30-50 ms BLE connection interval with latency 0, then returns to idle parameters after the sweep.
- The firmware no longer runs a continuous status LED loop; the LED blinks once at boot status and can still be blinked by the debug BLE command.
- `CONFIG_PM_DEVICE` and `CONFIG_PM_DEVICE_RUNTIME` are enabled in `prj.conf`.
- The network core runs HCI IPC for BLE.

This means the current "on" state is an interactive BLE-ready state with lower idle cost, not a deep PMIC-off standby. The command thread blocks on a message queue when idle, and the main thread sleeps forever after boot initialization, so Zephyr can enter idle whenever BLE and driver work permit it.

Remaining nRF-level steps for a real battery product:

1. Measure current in each implemented state and tune BLE intervals from evidence.
2. Decide whether slow advertising should eventually stop after a longer timeout, requiring a short button press to reconnect.
3. Consider disabling UART/logging in production battery builds after bring-up is complete.
4. Consider a firmware standby mode that keeps PMIC regulators on but lets the nRF idle even more aggressively.

This is separate from Ship mode. Ship mode gives the lowest storage/off current but the nRF cannot run BLE or scheduled measurements while in ship mode.

## Nordic guidance and samples

Nordic's examples point to a staged policy rather than a single universal "sleep mode":

1. Keep normal connected operation in System ON idle. In Zephyr/NCS, the CPU can sleep whenever all threads are blocked, while BLE, RTC, GPIO, and other interrupts wake the system as needed.
2. Make BLE policy explicit and measurable. Nordic's Bluetooth power profiling sample exposes advertising duration, advertising interval, connection interval, peripheral latency, notification size, and notification interval as the main variables to tune.
3. Use System OFF or PMIC Ship for actual off/storage states. These are reset/wakeup states, not a transparent BLE standby; the BLE link is gone and the application boots again on wake.
4. Disable visible indicators and unused features in battery builds. The Nordic sample has a Kconfig option to disable LEDs for power profiling, and the nRF5340 board config enables `CONFIG_PM_DEVICE` and `CONFIG_PM_DEVICE_RUNTIME`.
5. Use the nPM13xx one-button pattern for products with `SHPHLD/RESET`. The Nordic sample measures `SHPHLD` press duration from PMIC events, rejects ship entry while VBUS is present, and calls `regulator_parent_ship_mode()` for long press shutdown.

Relevant local NCS references in this install:

- `/opt/nordic/ncs/v3.3.0/nrf/samples/bluetooth/peripheral_power_profiling`
- `/opt/nordic/ncs/v3.3.0/nrf/samples/pmic/native/npm13xx_one_button`
- `/opt/nordic/ncs/v3.3.0/nrf/samples/bluetooth/subrating`
- `/opt/nordic/ncs/v3.3.0/zephyr/samples/boards/nordic/system_off`

For BioMess, this argues against sending the device into nPM Hibernate between series if the user expects immediate reconnect. Hibernate with a timer is useful for scheduled autonomous wakeups, but it creates the same user-experience problem seen on the previous nRF52832 design: if the only wake source is time, the user must wait. The better first product behavior is:

1. Short press or boot starts a fast reconnect window.
2. If nobody connects, advertising falls back to a slower interval.
3. If the phone is connected but idle, use slower connection parameters and no LED loop.
4. When the app starts a measurement, temporarily request faster BLE connection parameters, run the sweep, stream the data, then return to idle parameters.
5. A 3 second held press lights the LED; releasing after that enters nPM1304 Ship mode when VBUS is absent.

## AD5940 layer

The AD5940 has two distinct concepts that are easy to confuse:

1. AFE power mode for measurement quality/current:
   - Current firmware uses `AFEPWR_LP`.
   - System and ADC clocks are configured for the low-power path: 16 MHz HFOSC and 800 kSPS ADC.
   - This was selected because the RC fixture showed sane resistance and the phase behavior looked acceptable; it also matches the legacy direction better than the high-power setup.

2. AD5940 hibernate/sleep:
   - The measurement sequence calls `AD5940_EnterSleepS()` after each sequence.
   - The ISR locks sleep while reading FIFO, then unlocks and calls `AD5940_EnterSleepS()` again.
   - After a complete sweep, the firmware calls `AD5940_ShutDownS()`, which turns off the low-power loop and puts the AFE into hibernate.
   - SPI chip-select assertion includes a wake delay because AD5940 register access wakes it from hibernate.

So the AD5940 is already treated as mostly asleep outside active measurement work. This does not put the nRF5340 or the PMIC into low power; it only reduces the analog front-end power.

## Practical states

| State | Who owns it | Current behavior | User action |
| --- | --- | --- | --- |
| Off/storage | nPM1304 Ship mode | Implemented through 3 s hold plus release if VBUS is absent | Hold button until the long LED pulse ends, then release; short press or USB turns it on |
| On/ready | nRF5340 + nPM1304 active | Fast BLE advertising for 60 s, then slower connectable advertising; LED off after boot blink; AD5940 mostly hibernated | Open app and connect; short press restarts fast advertising |
| Measuring | nRF5340 + AD5940 active | App sends `0x01`; BLE requests faster connection parameters; AD5940 runs 5 x 48 points and streams over BLE | Start measurement in app |
| Between measurements while app connected | nRF5340 active, AD5940 hibernated | BLE remains connected with idle connection parameters; AD5940 sleeps | Start another measurement or disconnect |
| Auto-mode | nRF5340 active timer, AD5940 periodic | Firmware repeats measurement every configured interval while enabled | App sends start/stop auto-mode |
| Scheduled wake from off | nPM1304 Hibernate timer | Not implemented | Future feature |
| nRF deep standby with BLE policy | nRF5340 PM | Not implemented | Future feature |

## Recommended product strategy

For the current hardware and firmware maturity, use this model:

1. Product "off" is nPM1304 Ship mode. Holding the button for 3 seconds arms shutdown, releasing sends the PMIC to ship, and a later short press wakes it.
2. Product "on" is BLE-ready. Keep advertising initially so the app can find the device.
3. The AD5940 should remain hibernated except during measurements. This is already implemented.
4. LED and BLE advertising/connection policy are now implemented as the first nRF low-power layer.
5. `CONFIG_PM_DEVICE` and runtime PM are enabled; measure the resulting current and confirm BLE reconnection behavior on hardware.
6. Add nPM1304 Hibernate timer only if the product needs scheduled measurements while apparently "off". For normal manual use, Ship mode is simpler and lower power.

## Open validation items

- Measure current in Ship mode on battery, with USB disconnected.
- Measure current while advertising with LED enabled and disabled.
- Measure current while connected but idle.
- Measure current during one full 5 x 48 sweep.
- Confirm the PMIC `SHPHLD/RESET` and GPIO0 interrupt timing on hardware with a logic analyzer before freezing production behavior.
- Decide whether PMIC hardware long-press reset should remain `one-button` or be changed to `two-button`/`disabled` for production.
