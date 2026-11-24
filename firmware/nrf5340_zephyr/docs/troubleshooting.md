# BioMess firmware troubleshooting

Use this guide when a build, flash, BLE check, PMIC check, AD5940 check or sweep validation fails. Each symptom points to the fastest script to run next and the likely hardware/software boundary.
When using `run_verification.py --report ...`, check the sibling `.json` file for the exact failing step and exit code. Use `tools/summarize_verification.py <summary.json>` for a compact pass/fail readout.

## Quick triage

| Symptom | Run first | Healthy sign | If it fails |
| --- | --- | --- | --- |
| `west flash` cannot start | `tools/preflight.py --require-board` | `nrfjprog_ids=<serial>` | If `serial_debug_port_visible=true` but `nrfjprog_ids=` is empty, the OS sees serial/UART but not the J-Link/nRF debugger. Run `tools/diagnose_debugger.py`; check debug USB/J-Link probe, board power/reset and whether another tool owns the probe. |
| Serial port exists but no debugger ID | `tools/diagnose_debugger.py` | `debugger_visible=true` | A UART/CDC device is visible but Nordic tools do not see a J-Link/nRF debugger. Use the debug connector/probe, not just a USB serial endpoint. |
| Board boots but logs look incomplete | `tools/capture_uart.py`, then `tools/test_uart_boot_log.py` | `boot_log_ok=true` | Missing marker tells which init stage failed: PMIC, BLE advertising, SPI, AD5940 GPIO setup or app-ready. |
| Phone app stays on searching | `tools/scan_advertising.py --summary-json /tmp/biomess_advertising_scan.json` | `advertising_scan_ok=true`, `local_name=BioMess`, `advertises_biomess_service=true` | If this fails, debug advertising/flash/reset. If this passes, the firmware is advertising and the next boundary is app scan filters, Bluetooth permission/cache, or an existing central connection. |
| BLE scan cannot find board or GATT shape is wrong | `tools/ble_probe.py --summary-json /tmp/biomess_gatt_probe.json` | Services `AF00`, `AF01`, `AF02`, `AF03`; `gatt_validation_ok=true`; `ble_probe_ok=true` | Confirm the firmware was flashed, logs say `BLE advertising as BioMess`, phone/laptop BLE is on, no other client is holding the connection, and the app-facing characteristics still have the required read/write/notify properties. |
| Board responds over BLE but health fails | `tools/test_board_health.py` | `pmic_ok=true`, `ad5940_adi_id=0x4144`, `ad5940_chip_id_known=true` | Use the failed flag to separate PMIC/I2C from AD5940/SPI/reset/CS wiring. |
| Battery command fails | `tools/test_pmic_battery.py` | Voltage > 0 mV, percentage 0..100 | Check nPM1304 I2C pins, PMIC node readiness, charger/gauge driver and power path. |
| AD5940 sweep times out | `tools/test_board_health.py`, then `tools/test_ad5940_sweep.py` | Health passes before sweep; sweep receives expected point count | Check AD5940 INT pin, CS/RST/SPI pins, phantom/load connection, and whether sweep config is valid. |
| Sweep CSV exists but values look wrong | `tools/analyze_sweep_csv.py` | `sweep_csv_ok=true` | Use `--expected-ohms`, tolerance and phase limit with a known resistor or phantom load. |
| Stored sync returns no records | `tools/test_stored_sync.py --count 1` | `stored_count>0`, CRC `ok` | Run one successful sweep first; stored records are RAM-backed and lost on reset. |
| Mobile app waits forever for a measurement | `tools/test_protocol_contract.py`, then `tools/test_ad5940_sweep.py` | Contract passes and sweep bytes equal `points * repetitions * 12` | Ensure the app reads firmware-effective sweep points after config writes; Android/iOS code in this repo is patched for that. |
| Handoff zip cannot be trusted | `tools/verify_firmware_release.py <zip>` | `release_package_verify_ok=true` plus `release_package_flasher_dry_run_ok=true` | Rebuild/repackage; the verifier checks docs, tools, manifest, `merged.hex` SHA256, package-local dependency hints, flasher dry-run after extraction and BLE/PMIC/AD5940 script `--help`. |
| Verification report is too long to inspect | `tools/summarize_verification.py <summary.json>` | `verification_summary_ok=true` | The failing step output tail points to the next script or hardware check. |
| Final board evidence is incomplete | `tools/board_validation_report.py --require-full-board ...` | `board_validation_ok=true` | Add the missing flash, UART, BLE, PMIC, AD5940 sweep or stored-sync artifact called out in the report. |

## Recommended order on a new board

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/preflight.py --require-board
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --flash --uart --report /tmp/biomess_flash_uart.md
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --ble --report /tmp/biomess_ble_board.md
```

If `--require-board` fails, stop and run:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/diagnose_debugger.py \
  --summary-json /tmp/biomess_debugger.json
```

## Debugger visible vs serial visible

A `/dev/cu.usbmodem*`, `/dev/ttyACM*` or similar path proves that the OS sees a USB serial endpoint. It does not prove that Nordic tools can program the nRF5340. Flashing requires `nrfjprog --ids` to print a debugger serial.

Healthy debugger output:

```text
nrfjprog_ids=1050123456
debugger_visible=true
```

Current failing pattern seen on this machine:

```text
nrfjprog_ids=
debugger_visible=false
serial_debug_port_visible=true
serial_port_4_manufacturer=LG Electronics Inc.
serial_port_4_product=USB Controls
```

That is not a J-Link/nRF debugger for `west flash`.

## BLE command-level checks

Use these checks after the board is flashed and advertising:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/ble_probe.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/scan_advertising.py \
  --summary-json /tmp/biomess_advertising_scan.json
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/test_board_health.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/test_pmic_battery.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/test_led_command.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/test_ad5940_sweep.py --points 48 --repetitions 5 --csv /tmp/biomess_sweep.csv
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/analyze_sweep_csv.py /tmp/biomess_sweep.csv --points 48
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/test_stored_sync.py --count 1
```

All BLE scripts accept `--address <ble-address>` to skip scanning when multiple devices advertise nearby.

## Analog validation

For a purely resistive load, run:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/analyze_sweep_csv.py \
  /tmp/biomess_sweep.csv \
  --points 48 \
  --expected-ohms 10000 \
  --magnitude-tolerance-pct 20 \
  --max-abs-phase-deg 15
```

Adjust `--expected-ohms` and tolerances to the actual resistor or phantom. A structure-only CSV check can pass while analog quality is still poor; the expected-ohms check is what catches gross gain/phase issues.

## When to trust the mobile apps

Treat the mobile apps as protocol consumers, not as first-line hardware diagnostics. First prove the firmware with:

```text
ble_probe.py
test_board_health.py
test_ad5940_sweep.py
analyze_sweep_csv.py
test_stored_sync.py
```

Then validate Android/iOS. If a script succeeds but an app fails, inspect app state, pairing/cache behavior and notification subscription timing before changing firmware. For app-side source paths and protocol rules, see `mobile-integration.md`.
