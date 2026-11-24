# BioMess nRF5340 validation matrix

This matrix maps the requested firmware scope to the implementation, the evidence that can be collected without hardware, and the evidence still required from a physical BioMess PCB.

Use it as the fastest audit checklist before handing a firmware image to someone else.

## Current image and release

These values are generated artifacts and change whenever the firmware is rebuilt. Do not trust a hardcoded hash in documentation; inspect the current workspace with:

```bash
make firmware-readiness
make -C firmware/nrf5340_zephyr flash-dry-run
make firmware-release-info
```

| Item | Source of truth |
| --- | --- |
| Board target | `biomess_nrf5340/nrf5340/cpuapp` |
| Image path | `firmware/nrf5340_zephyr/build/merged.hex` |
| Image size and SHA256 | `make -C firmware/nrf5340_zephyr flash-dry-run` or `tools/flash_firmware.py --dry-run --summary-json /tmp/biomess_flash_dry_run.json` |
| BLE name | `BioMess` |
| Latest handoff package | `make firmware-release-info` |

## Requirement matrix

| Requirement | Implementation | Offline evidence | Physical-board evidence | Status |
| --- | --- | --- | --- | --- |
| nRF5340 firmware for BioMess PCB v2 | Out-of-tree Zephyr board in `boards/biomess/biomess_nrf5340`; app core plus HCI IPC network core | `tools/test_build_artifacts.py`, `tools/test_hardware_contract.py`, `make firmware-ci-offline` | `tools/run_verification.py --flash --uart --ble` | Implemented; board validation pending |
| BLE compatible with Android and iOS apps | `src/ble_service.c`; Android `BioMessBleUuids.kt`/`BioMessCommand.kt`/`BioMessBleManager.kt`; iOS `BioMessBLEManager.swift` | `tools/test_protocol_contract.py`, `tools/describe_ble_contract.py`, Android/iOS build and tests | Apps scan/connect to `BioMess`; `tools/scan_advertising.py` prints `advertising_scan_ok=true`; `tools/ble_probe.py` prints `gatt_validation_ok=true` | Implemented; live app/device validation pending |
| App-facing GATT shape | Services `AF00`, `AF01`, `AF02`, `AF03`; command `0xC000`; config `0xC011-0xC017`; battery `0xC202` | `tools/test_protocol_payloads.py` validates reusable GATT contract logic | `tools/ble_probe.py --summary-json /tmp/biomess_gatt_probe.json` | Implemented; live BLE validation pending |
| AD5940 sweep command | Command `0x01` in `src/ble_service.c`; AD5940 sequencing in `src/ad5940/AD5940Main.c` | Payload parser and contract tests; synthetic sweep fixture and analyzer | `tools/test_ad5940_sweep.py --points 48 --csv /tmp/biomess_sweep.csv` | Implemented; analog hardware validation pending |
| Sweep CSV and analog sanity check | `tools/analyze_sweep_csv.py` validates frequency/magnitude/phase columns and optional resistor tolerance | `tools/generate_sweep_fixture.py` plus `tools/analyze_sweep_csv.py --expected-ohms 10000` | Known resistor/phantom load analyzed with `--expected-ohms`, magnitude tolerance and phase limit | Implemented; real load validation pending |
| PMIC/nPM1304 check | `src/board_power.c`; battery command `0x02`; health command `0x0A` | `tools/test_pmic_battery.py --help`, payload parser checks voltage/percentage bounds | `tools/test_pmic_battery.py`; health prints `pmic_ok=true` | Implemented; I2C/PMIC board validation pending |
| AD5940 identity check | Health command reads ADIID/CHIPID; ADIID OK only when ADIID is `0x4144` | `tools/test_board_health.py --help`; `tools/test_protocol_contract.py` guards against false ADIID OK | `tools/test_board_health.py` prints ADIID `0x4144` and known CHIPID | Implemented; SPI/reset/CS board validation pending |
| LED command | Command `0x64` toggles LED path | `tools/test_led_command.py --help`, protocol contract checks opcode | `tools/test_led_command.py`; visual LED blink on PCB | Implemented; board validation pending |
| Stored measurement sync | RAM ring buffer; commands `0x07`, `0x08`, `0x09`; 2974-byte record layout | `tools/test_protocol_payloads.py`, Android/iOS stored record parsers, `tools/test_stored_sync.py --help` | Successful sweep followed by `tools/test_stored_sync.py --count 1` with valid CRC | Implemented as RAM-only |
| Auto mode | Commands `0x05`, `0x06`; connected-only periodic measurement stream | Contract tests and `tools/test_auto_mode.py --help` | `tools/test_auto_mode.py --interval 60 --timeout 90` | Implemented; optional board validation pending |
| UART boot evidence | Firmware logs PMIC, BLE, SPI and AD5940 GPIO readiness | `tools/test_uart_boot_log.py` checks required markers against captured text | `tools/capture_uart.py`, then `tools/test_uart_boot_log.py /tmp/biomess_uart.log` | Implemented; board validation pending |
| Handoff package | `tools/package_firmware_release.py` packages image, manifest, docs and package-local tools | `tools/verify_firmware_release.py`, `tools/test_release_matches_build.py`, `tools/test_release_package_fixture.py` | Package-local `tools/flash_firmware.py`, then package-local BLE/PMIC/AD5940 checks | Implemented |
| Readiness summary | `tools/readiness_report.py` combines build, release, debugger and full-board evidence state | `tools/test_readiness_report.py`, `make firmware-readiness`; optional `--require-handoff` gate | Same command shows `board_ready_to_flash=true` when `nrfjprog --ids` detects a debugger | Implemented |
| BLE board validation report | `tools/board_validation_report.py --require-ble-board` combines runner, release, advertising, GATT, PMIC, LED, AD5940 sweep and stored-sync evidence | `tools/test_board_validation_report.py` fixture covers BLE-board behavior | `make firmware-ble`, then `make firmware-ble-board-report` prints `board_validation_ok=true` | Implemented; validated on PCB |
| Strict full-board validation report | `tools/board_validation_report.py --require-full-board` combines flash, runner, release, UART, advertising, GATT and sweep evidence | `tools/test_board_validation_report.py` fixture covers strict full-board behavior | `tools/board_validation_report.py --require-full-board ...` prints `board_validation_ok=true` | Implemented; UART evidence depends on bench console routing |

## Required command sets

Run these from the repo root before handing off a firmware image:

```bash
make firmware-ci-offline
make firmware-verify-mobile
make firmware-verify-mobile-tests
make firmware-package
make firmware-verify-release
make firmware-release-matches-build
```

Run these only when a real debugger is visible in `nrfjprog --ids`:

```bash
make firmware-preflight-board
make firmware-board-full
make firmware-board-report
```

## Completion gate

The repository is not fully board-validated until the final report says:

```text
board_validation_ok=true
```

In `--require-full-board` mode, that means the evidence includes firmware flash, UART capture, UART boot log check, passive BLE advertising scan, BLE/GATT probe, board health, PMIC battery, LED command, AD5940 sweep, sweep CSV analysis and stored sync.
