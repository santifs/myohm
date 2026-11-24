# Firmware verification

This guide gives a reproducible path for build, flash and board-level checks.
For symptom-based failure triage, see `docs/troubleshooting.md`.

## Build

Recommended portable build through the verification runner:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py
```

From `firmware/nrf5340_zephyr`, the same common operation is:

```bash
make verify
```

CI-safe offline checks that do not require Nordic SDK, BLE hardware or a debugger:

```bash
make ci-offline
```

This is the command used by the `firmware-offline` job in `.github/workflows/firmware-offline-checks.yml`. It checks payload parsing, firmware/app BLE protocol contract, hardware pin contract, documentation links, Python syntax, final board report fixture behavior, synthetic release-package creation/verification, and sweep CSV analysis with a fixture.

The same workflow also has a `mobile-android-tests` job that sets up Java 17 on Ubuntu and runs `./gradlew :core-ble:testDebugUnitTest` from `mobile/android`, plus a `mobile-ios-tests` job on `macos-15` that runs `swift test` from `mobile/ios/VolumHealthAppPackage`.

To run only the synthetic handoff-package check:

```bash
make release-fixture
```

The runner defaults to board `biomess_nrf5340/nrf5340/cpuapp`, west `/opt/nordic/ncs/toolchains/0c0f19d91c/bin/west`, NCS directory `/opt/nordic/ncs/v3.3.0`, and Zephyr SDK `/opt/nordic/ncs/toolchains/0c0f19d91c/opt/zephyr-sdk`. Override those with `--board`, `--west`, `--ncs-dir`, and `--zephyr-sdk` on another machine.

Expected result:

- Build exits with code 0.
- `firmware/nrf5340_zephyr/build/merged.hex` exists.
- `tools/test_build_artifacts.py` confirms the BioMess board target, HCI IPC network-core image, app-core CPUNET release config and merged image metadata.
- Vendor warnings from `src/ad5940/ad5940.c` are expected.

## Flash

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/flash_firmware.py \
  --log /tmp/biomess_flash.log \
  --summary-json /tmp/biomess_flash.json
```

Shortcut from `firmware/nrf5340_zephyr`:

```bash
make flash
```

Open UART at 115200 baud. Boot should print readiness logs and the device should advertise as `BioMess`.

`flash_firmware.py` defaults to `firmware/nrf5340_zephyr/build/merged.hex`, checks the image size and SHA256, requires a debugger from `nrfjprog --ids`, runs `nrfjprog --program ... --chiperase --verify --reset`, and writes auditable text/JSON logs when requested. Use `--package <release.zip>` to flash `firmware/merged.hex` from a verified handoff package.

## Python setup

```bash
python3 firmware/nrf5340_zephyr/tools/setup_python_env.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/preflight.py --require-bleak --require-pyserial
```

The setup script creates `firmware/nrf5340_zephyr/.venv`, upgrades `pip`, and installs `bleak` plus `pyserial` from `tools/requirements.txt`. Use `--recreate` only when the existing venv should be removed and rebuilt; the script refuses to delete a path that does not contain `pyvenv.cfg`.

BLE scripts accept `--address` to skip scanning. Without it they scan for a name starting with `BioMess`. UART capture uses `pyserial`; if `--serial-port` is omitted it tries USB/J-Link/debug-style ports first.

## One-command verification

Local tool/board preflight:

```bash
python3 firmware/nrf5340_zephyr/tools/preflight.py
```

Expected on a machine ready for board bring-up:

- `west_available=true`
- `zephyr_sdk_available=true`
- `nrfjprog_available=true`
- `nrfjprog_ids` contains at least one debugger serial before flashing.
- `bleak_available=true`
- `pyserial_available=true`

After creating the local venv, the same check can be made without relying on global Python packages:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/preflight.py \
  --require-bleak \
  --require-pyserial
```

Before flashing, require a physical nRF debugger explicitly:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/preflight.py --require-board
```

Expected: this exits non-zero until `nrfjprog --ids` prints at least one debugger serial. Do not run `--flash` until this passes. If it prints `serial_debug_port_visible=true` while `nrfjprog_ids=` is empty, the machine sees a serial endpoint but not the J-Link/nRF debug probe needed to program the nRF5340.

If serial ports are present but `nrfjprog_ids=` is empty, run:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/diagnose_debugger.py \
  --summary-json /tmp/biomess_debugger.json
```

Expected when ready to flash:

- `debugger_visible=true`.
- `nrfjprog_ids=` contains at least one serial.
- `/tmp/biomess_debugger.json` records the same debugger/serial distinction for the evidence bundle.

If `serial_debug_port_visible=true` but `debugger_visible=false`, the machine sees a USB serial endpoint but not a Nordic/J-Link debug probe. Check connector choice, probe power/reset state, SEGGER/Nordic tools, and whether another process owns the probe.

Offline checks plus firmware build:

```bash
python3 firmware/nrf5340_zephyr/tools/run_verification.py
```

Expected:

- `protocol_payloads_ok=true`
- `protocol_contract_ok=true`
- `hardware_contract_ok=true`
- `docs_links_ok=true`
- `west build` exits with code 0.
- Final line: `verification_ok=true`

To also compile the mobile BLE clients in the same run:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile
```

Use `--ios` or `--android` to run only one mobile build.
To run the mobile unit test suites that exercise Android BLE parsing/buffering and the iOS package tests:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile-tests
```

This command runs Android `:core-ble:testDebugUnitTest` and iOS `swift test`; run it on macOS for the same iOS package coverage used by CI.

After flashing the board, run BLE/hardware checks:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --ble
```

For the narrow “is the board advertising correctly?” check that does not take a GATT connection:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/scan_advertising.py \
  --summary-json /tmp/biomess_advertising_scan.json
```

Expected: `advertising_scan_ok=true`, at least one match with `local_name=BioMess`, and `advertises_biomess_service=true` for the `AF00` control service. Use this before phone-app testing when a mobile device stays on “searching”.
If the scan sees other BLE devices but no `BioMess` match, verify the board is flashed/running this firmware, reset it, and disconnect any phone app that may already have the peripheral connected.

To build, flash and run BLE/hardware checks in one pass:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --flash --ble
```

Use `--address <ble-address>` to skip scanning and `--include-auto` to include the 60-second auto-mode check.
The runner fails during preflight if `--ble` is used without `bleak`, `--uart` is used without `pyserial`, or `--flash` is used without an nRF debugger visible in `nrfjprog --ids`.
The BLE board sequence runs passive advertising scan, GATT discovery, board health, PMIC battery, LED, AD5940 sweep, and stored sync checks. It writes structured advertising evidence to `biomess_advertising_scan.json` and GATT evidence to `biomess_gatt_probe.json` next to the Markdown report, or to `/tmp` when no report path is provided. Override those paths with `--advertising-summary-json <path>` and `--ble-summary-json <path>`.

To keep auditable logs of a run:

```bash
python3 firmware/nrf5340_zephyr/tools/run_verification.py \
  --flash \
  --uart \
  --ble \
  --report /tmp/biomess_board_verification.md
```

The Markdown report captures each command, exit code and combined stdout/stderr. The runner also writes `/tmp/biomess_board_verification.json` with one object per step (`label`, command, cwd, exit code, duration, pass/fail and output tail). Attach both files to bring-up notes when validating a new PCB or firmware image.

Summarize one or more JSON reports:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/summarize_verification.py \
  /tmp/biomess_board_verification.json
```

Expected: `verification_summary_ok=true`. If any step failed, the script prints the failing step and the last lines of its output, then exits non-zero.

Create a final board validation report from the generated evidence:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/board_validation_report.py \
  --verification-json /tmp/biomess_board_verification.json \
  --release-package firmware/nrf5340_zephyr/build/releases/<package>.zip \
  --require-full-board \
  --output /tmp/biomess_board_validation.md \
  --summary-json /tmp/biomess_board_validation.json
```

Expected after real hardware validation: `board_validation_ok=true`. In `--require-full-board` mode the report requires flash, UART capture, UART boot log parser, passive BLE advertising scan, BLE/GATT probe, board health, PMIC battery, LED command, AD5940 sweep, sweep CSV analysis and stored sync runner steps. The advertising evidence must include `advertising_scan_ok=true`; the BLE/GATT probe evidence must include `advertised_name_validation_ok=true`, `gatt_validation_ok=true` and `ble_probe_ok=true`.
If the JSON came from `run_verification.py --flash --uart --ble`, the `firmware flash` runner step is accepted as flash evidence. The board report also uses the runner's `advertising_summary_json` and `ble_probe_summary_json` paths when present and falls back to stdout markers only for older summaries. Add `--flash-json /tmp/biomess_flash.json` only when flashing was performed separately with `tools/flash_firmware.py` and you want the report to include the standalone flash SHA256/debugger log.

If UART boot logs are not available on the bench setup, use the BLE-board gate after `make firmware-ble`:

```bash
make firmware-ble-board-report
```

That report uses `--require-ble-board` and requires passive advertising, GATT, board health, PMIC battery, LED command, AD5940 sweep, sweep CSV analysis and stored sync evidence, without requiring UART capture.

## Firmware release package

After a successful build, create a handoff zip:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/package_firmware_release.py \
  --report /tmp/biomess_firmware_verification.md \
  --summary-json /tmp/biomess_firmware_verification.json
```

Expected:

- `release_package_ok=true`.
- The zip is created under `firmware/nrf5340_zephyr/build/releases/`.
- The zip contains `firmware/merged.hex`, `manifest.json`, a short `README.md`, optional `verification-report.md`, optional `verification-summary.json`, all package-local Python tools, `tools/requirements.txt`, and the key bring-up/protocol docs.
- `manifest.json` records image size, SHA256, git branch/commit/dirty state, detected `nrfjprog --ids`, the package-local flash command, and the exact full-board verification command.

Summarize the latest package before handoff:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/describe_firmware_release.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/readiness_report.py \
  --summary-json /tmp/biomess_readiness.json
```

Expected before physical board validation: `release_info_ok=true`, `verification_summary_ok=true`, `readiness_report_ok=true`, `readiness_handoff_ready=true`, and `full_board_validation_complete=false`.

After extracting a package on another machine:

```bash
python3 -m pip install -r tools/requirements.txt
python3 tools/flash_firmware.py \
  --hex firmware/merged.hex \
  --log /tmp/biomess_flash.log \
  --summary-json /tmp/biomess_flash.json
```

Validate the package before handoff:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/verify_firmware_release.py \
  firmware/nrf5340_zephyr/build/releases/biomess-nrf5340-firmware-*.zip \
  --require-report \
  --require-summary-json \
  --require-build-summary
```

Expected: `release_package_verify_ok=true`. The verifier checks required docs/tools, duplicate zip entries, `manifest.json`, optional reports, generated BLE contract summary, package-local Python tool syntax, package-local dependency hints, `merged.hex` size/SHA256, and, with `--require-build-summary`, successful `firmware build` plus `firmware build artifacts` steps in the bundled summary. It also extracts the zip into a temporary directory, runs the included flasher in `--dry-run` mode against `firmware/merged.hex`, and checks that the package-local BLE/PMIC/AD5940 scripts respond to `--help`.

To capture UART only:

```bash
python3 firmware/nrf5340_zephyr/tools/capture_uart.py \
  --seconds 20 \
  --output /tmp/biomess_uart.log
python3 firmware/nrf5340_zephyr/tools/test_uart_boot_log.py /tmp/biomess_uart.log
```

Expected boot logs include the AD5940 banner, nPM1304 ready message, BLE advertising as `BioMess`, SPI ready, AD5940 GPIO mapping and the final app-ready line. `run_verification.py --uart` captures the log and then runs this parser automatically.

## Offline payload check

```bash
python3 firmware/nrf5340_zephyr/tools/test_protocol_payloads.py
python3 firmware/nrf5340_zephyr/tools/test_protocol_contract.py
python3 firmware/nrf5340_zephyr/tools/describe_ble_contract.py
python3 firmware/nrf5340_zephyr/tools/test_hardware_contract.py
python3 firmware/nrf5340_zephyr/tools/test_docs_links.py
python3 firmware/nrf5340_zephyr/tools/test_python_syntax.py
python3 firmware/nrf5340_zephyr/tools/test_board_validation_report.py
python3 firmware/nrf5340_zephyr/tools/test_readiness_report.py
python3 firmware/nrf5340_zephyr/tools/generate_sweep_fixture.py --csv /tmp/biomess_sweep_fixture.csv
python3 firmware/nrf5340_zephyr/tools/analyze_sweep_csv.py /tmp/biomess_sweep_fixture.csv --points 48 --expected-ohms 10000 --magnitude-tolerance-pct 2 --max-abs-phase-deg 1
```

Expected:

```text
protocol_payloads_ok=true
protocol_contract_ok=true
ble_contract_ok=true
hardware_contract_ok=true
docs_links_ok=true
python_syntax_ok=true
board_validation_report_contract_ok=true
readiness_report_contract_ok=true
sweep_fixture_ok=true
sweep_csv_ok=true
```

## BLE/GATT discovery

```bash
python3 firmware/nrf5340_zephyr/tools/ble_probe.py \
  --summary-json /tmp/biomess_gatt_probe.json
```

Expected:

- Scans for and connects to the board advertising as `BioMess`.
- Lists services `0000af00`, `0000af01`, `0000af02`, `0000af03`.
- Validates required app-facing GATT characteristics and properties: command `0xC000` has write/notify, duplicated sweep config has read/write in `AF00` and `AF01`, and battery `0xC202` has read/notify.
- Prints `advertised_name_validation_ok=true`.
- Prints `gatt_validation_ok=true`.
- Prints `ble_probe_ok=true`.
- Prints serial, RCAL, sweep start/stop, points and repetitions.
- Writes `/tmp/biomess_gatt_probe.json` with discovered services, characteristics, properties and config values.

Use `--address <ble-address>` with `ble_probe.py` to connect directly when several boards are nearby. In that GATT-only mode the contract is still validated, but `ble_probe.py` cannot validate the advertised name because its scanner result is bypassed. `scan_advertising.py --address <ble-address>` still performs a passive advertising scan and validates the matching address before the final board report accepts advertising evidence.

## Board health check

```bash
python3 firmware/nrf5340_zephyr/tools/test_board_health.py
```

Expected:

- `pmic_ok=true`.
- `battery_voltage_mv` is greater than `0`.
- `ad5940_adi_id=0x4144`.
- `ad5940_chip_id_known=true`.

This is the fastest BLE diagnostic for a flashed board because it checks the nPM1304 and AD5940 SPI identity path without running a full sweep.

## PMIC battery check

```bash
python3 firmware/nrf5340_zephyr/tools/test_pmic_battery.py
```

Expected:

- `battery_voltage_mv` is greater than `0`.
- `battery_percentage` is between `0` and `100`.

The percentage is a conservative LiPo estimate from voltage until a proper fuel-gauge model is added.

## LED write-path check

```bash
python3 firmware/nrf5340_zephyr/tools/test_led_command.py
```

Expected:

- Script prints `led_blink_command_sent=true`.
- Board status LED blinks three times.

## AD5940 sweep check

```bash
python3 firmware/nrf5340_zephyr/tools/test_ad5940_sweep.py \
  --points 48 \
  --start-hz 4000 \
  --stop-hz 198000 \
  --repetitions 5 \
  --csv /tmp/biomess_sweep.csv
```

Expected:

- `expected_bytes=2880` for 48 points and 5 repetitions.
- `received_points=240`.
- CSV contains `frequency_hz,magnitude_ohm,phase_deg`.

The runner automatically analyzes the generated CSV for structure, finite values, positive magnitudes and monotonic frequencies:

```bash
python3 firmware/nrf5340_zephyr/tools/analyze_sweep_csv.py /tmp/biomess_sweep.csv --points 48
```

Use a known resistor or phantom load to judge analog validity. For a purely resistive load, magnitude should be close to the known resistance and phase near zero across the sweep:

```bash
python3 firmware/nrf5340_zephyr/tools/analyze_sweep_csv.py \
  /tmp/biomess_sweep.csv \
  --points 48 \
  --expected-ohms 10000 \
  --magnitude-tolerance-pct 20 \
  --max-abs-phase-deg 15
```

## Stored sync check

After at least one successful sweep:

```bash
python3 firmware/nrf5340_zephyr/tools/test_stored_sync.py --count 1
```

Expected:

- `stored_count` is greater than `0`.
- `stored_records_received=1`.
- The record line ends with `crc:ok`.

To reset the RAM-backed ring buffer:

```bash
python3 firmware/nrf5340_zephyr/tools/test_stored_sync.py --clear
```

If `--offset` is outside the available range, the script skips the batch read instead of waiting for bytes that the firmware will not send.

## Auto-mode check

```bash
python3 firmware/nrf5340_zephyr/tools/test_auto_mode.py --interval 60 --timeout 90
```

Expected:

- The script starts auto mode, waits for one firmware-initiated stream, then stops auto mode.
- `auto_mode_points_received` equals `points * repetitions` from the current BLE config.

## Mobile compatibility checks

Android BLE module:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --android
```

Expected:

- `BUILD SUCCESSFUL`.
- KSP/deprecated BLE API warnings may appear elsewhere in the Android project; they are not BLE protocol failures.
- Android Gradle Plugin requires Java 17 or newer. On macOS, `run_verification.py` uses `/usr/libexec/java_home -v 17+` for the Android step when available.

iOS package:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --ios
```

Expected:

- Build exits with code 0.
- Warnings about unused `try?` results or `await` without async work may appear; they are not BLE protocol failures.

## Current limitations

- Stored measurements are RAM-backed only; they are lost on reset and capped to the last 4 records.
- IMU commands return zero-filled quaternion data.
- Auto-mode intervals are clamped to 60-3600 seconds to match the mobile apps.
- Auto mode stops on BLE disconnect until persistent flash storage is implemented.
