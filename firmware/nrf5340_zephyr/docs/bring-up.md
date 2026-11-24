# BioMess nRF5340 bring-up checklist

Use this checklist when preparing a new board or when handing the repo to someone who has not worked on the firmware before. If you only need the shortest command path first, start with `docs/quickstart.md`.

For the current pass/fail matrix, see `docs/implementation-status.md`.
For failure triage during any step, see `docs/troubleshooting.md`.

## 1. Know what this firmware does

- Target hardware: BioMess PCB v2 with nRF5340, AD5940 and nPM1304.
- Current Zephyr build target: `biomess_nrf5340/nrf5340/cpuapp`.
- BLE name: `BioMess`.
- Mobile clients: Android `mobile/android/core-ble` and iOS `mobile/ios/VolumHealthAppPackage`.
- Main implemented paths: BLE command/control, AD5940 sweep streaming, nPM1304 battery read, LED command, RAM-backed stored sync and connected-only auto mode.

## 2. Prepare Python tools

```bash
python3 firmware/nrf5340_zephyr/tools/setup_python_env.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/preflight.py --require-bleak --require-pyserial
```

The same common flows are available as Make shortcuts:

```bash
cd firmware/nrf5340_zephyr
make help
make setup
make preflight
```

Expected:

- `bleak_available=true`
- `pyserial_available=true`
- `preflight_ok=true`

## 3. Check offline contracts before flashing

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --report /tmp/biomess_offline_verification.md
```

Expected:

- `protocol_payloads_ok=true`
- `protocol_contract_ok=true`
- `ble_contract_ok=true`
- `hardware_contract_ok=true`
- `python_syntax_ok=true`
- `sweep_fixture_ok=true`
- `sweep_csv_ok=true`
- `verification_ok=true`

These checks catch BLE UUID/opcode drift, payload layout drift, Python syntax errors, devicetree pinout drift and sweep CSV analyzer regressions before hardware is involved.
The same command also writes `/tmp/biomess_offline_verification.json`, a machine-readable step summary that is useful when comparing boards or CI runs.

To include mobile compatibility builds in the same report:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py \
  --skip-build \
  --mobile \
  --report /tmp/biomess_offline_mobile_verification.md
```

## 4. Build firmware

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py
```

Expected:

- Build exits with code 0.
- `firmware/nrf5340_zephyr/build/merged.hex` exists.

The runner defaults to `biomess_nrf5340/nrf5340/cpuapp`. Use `--board <zephyr-board>`, `--west`, `--ncs-dir`, or `--zephyr-sdk` if the Nordic install paths differ.

Optional handoff package after the build-backed verification run:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/package_firmware_release.py \
  --report /tmp/biomess_firmware_verification.md \
  --summary-json /tmp/biomess_firmware_verification.json
```

This creates a zip under `firmware/nrf5340_zephyr/build/releases/` with `merged.hex`, SHA256, git metadata, all package-local Python tools, `tools/requirements.txt`, and the docs needed by whoever flashes the next board.
Verify it with `tools/verify_firmware_release.py --require-report --require-summary-json --require-build-summary` before sending it to another machine.

## 5. Confirm a debugger before flashing

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/preflight.py --require-board
```

Expected:

- `nrfjprog_ids=` contains at least one serial number.

Do not run `--flash` until this passes. If it fails, check USB cable, power, J-Link driver, board power state and whether another tool owns the debugger.

If a `/dev/cu.usbmodem*` or `/dev/ttyACM*` port is visible but `nrfjprog_ids=` is empty, run:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/diagnose_debugger.py
```

That diagnostic separates “serial/UART endpoint visible” from “J-Link/debugger visible to Nordic tools” and prints the next checks to make before flashing.

## 6. Flash and capture boot logs

For a focused programming step, flash the already-built `merged.hex` and keep a log/JSON record:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/flash_firmware.py \
  --log /tmp/biomess_flash.log \
  --summary-json /tmp/biomess_flash.json
```

To program exactly what was sent in a handoff package, use the release zip instead:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/flash_firmware.py \
  --package firmware/nrf5340_zephyr/build/releases/<package>.zip \
  --log /tmp/biomess_flash_package.log \
  --summary-json /tmp/biomess_flash_package.json
```

If the package has been extracted on another machine, run the included tool from inside the extracted package:

```bash
python3 tools/flash_firmware.py \
  --hex firmware/merged.hex \
  --log /tmp/biomess_flash.log \
  --summary-json /tmp/biomess_flash.json
```

Expected:

- `flash_ok=true`
- The log records image path, image size, SHA256, debugger IDs and exact command.
- The JSON summary records the same data for handoff or CI artifacts.

Then run the combined flash/UART validation flow when you want the boot log parsed automatically:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py \
  --flash \
  --uart \
  --uart-seconds 20 \
  --report /tmp/biomess_flash_uart.md
```

Expected UART signs:

- `nPM1304 PMIC ready` or a clear PMIC warning.
- `BLE advertising as BioMess`.
- `SPI device ready`.
- `AD5940 GPIOs:` with CS/RST/INT pins.
- `Ready. Connect with the BioMess app and send BLE command 0x01.`

`run_verification.py --uart` runs `test_uart_boot_log.py` after capture, so these markers become a pass/fail gate in the report.

## 7. Probe BLE/GATT

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/ble_probe.py
```

Expected:

- Connects to `BioMess`.
- Shows services `AF00`, `AF01`, `AF02`, `AF03`.
- Prints `gatt_validation_ok=true`.
- Prints `ble_probe_ok=true`.
- Reads serial, RCAL, start/stop frequency, points and repetitions.

Use `--address <ble-address>` on all BLE scripts if scanning finds multiple devices. Add `--summary-json /tmp/biomess_gatt_probe.json` when you want a machine-readable list of discovered services, characteristics, properties and config values for the final evidence bundle.

## 8. Run board-level checks

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py \
  --ble \
  --report /tmp/biomess_ble_board.md
```

This runs:

- BLE/GATT probe.
- Board health command for PMIC battery data and AD5940 identity.
- PMIC battery command.
- LED command.
- AD5940 sweep command.
- Stored sync command.

Add `--include-auto` only when you want the 60-second auto-mode check.

When flash, UART and BLE validation have all been run, create the final evidence report:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/board_validation_report.py \
  --verification-json /tmp/biomess_board_verification.json \
  --release-package firmware/nrf5340_zephyr/build/releases/<package>.zip \
  --require-full-board \
  --output /tmp/biomess_board_validation.md \
  --summary-json /tmp/biomess_board_validation.json
```

Expected: `board_validation_ok=true`.
`--flash-json` is optional here when `--verification-json` came from `run_verification.py --flash ...`; the report accepts the runner's `firmware flash` step as flash evidence. Add `--flash-json /tmp/biomess_flash.json` when flashing was done separately with `tools/flash_firmware.py` and you want the report to include the standalone SHA256/debugger log.

## 9. Validate analog quality

For AD5940 accuracy, connect a known resistor or phantom load and run:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/test_ad5940_sweep.py \
  --points 48 \
  --start-hz 4000 \
  --stop-hz 198000 \
  --repetitions 5 \
  --csv /tmp/biomess_sweep.csv
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/analyze_sweep_csv.py \
  /tmp/biomess_sweep.csv \
  --points 48 \
  --expected-ohms 10000 \
  --magnitude-tolerance-pct 20 \
  --max-abs-phase-deg 15
```

Expected for a purely resistive load:

- CSV has 240 rows for 48 points x 5 repetitions.
- Magnitude is close to the known resistance across the sweep.
- Phase is near zero degrees.

## 10. Check mobile apps

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile-tests
```

Expected:

- iOS package build exits with code 0.
- Android `:core-ble:compileDebugKotlin` exits with code 0.
- iOS `swift test` exits with code 0.
- Android `:core-ble:testDebugUnitTest` exits with code 0.

For isolated app checks, use `--ios` or `--android`. Android requires Java 17 or newer; on macOS the runner selects `/usr/libexec/java_home -v 17+` for that step when available. Then use the apps to scan for `BioMess`, connect and start a measurement. The apps reassemble `0xC000` notification chunks until they receive `points * repetitions * 12` bytes.

## Known limitations

- Stored measurements are RAM-backed only and are lost on reset.
- Auto mode stops on BLE disconnect.
- IMU commands return zero-filled quaternions until a real IMU path is integrated.
- Physical validation still requires a visible nRF/J-Link debugger and the BioMess PCB.
