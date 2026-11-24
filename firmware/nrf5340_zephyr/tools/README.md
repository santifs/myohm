# BioMess firmware verification tools

Create a local Python environment for BLE/UART checks:

```bash
python3 firmware/nrf5340_zephyr/tools/setup_python_env.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/preflight.py --require-bleak --require-pyserial
```

Direct `pip install -r firmware/nrf5340_zephyr/tools/requirements.txt` also works, but the venv keeps `bleak` and `pyserial` out of the global Python install.

From `firmware/nrf5340_zephyr`, `make help` prints the common command shortcuts. The Make targets are wrappers around the scripts below, so use the scripts directly when you need uncommon flags.

Scripts:

| Script | Purpose |
| --- | --- |
| `setup_python_env.py` | Create/update `firmware/nrf5340_zephyr/.venv` and install BLE/UART dependencies. |
| `preflight.py` | Check local west/nrfjprog, Python BLE/UART dependencies, debugger IDs and serial ports. |
| `diagnose_debugger.py` | Diagnose the common case where a serial port is visible but `nrfjprog --ids` is empty. |
| `readiness_report.py` | Summarize build/release/debugger/serial/full-board evidence, report `release_error` for incomplete packages and print the next concrete command to run. |
| `flash_firmware.py` | Flash a specific `merged.hex` or release zip with SHA256, debugger checks, log output and optional JSON summary. |
| `run_verification.py` | Main runner for offline checks, build, optional mobile builds, optional flash and optional BLE board checks; writes Markdown, step JSON and BLE probe JSON summaries. |
| `summarize_verification.py` | Read one or more runner JSON summaries and fail if any step failed. |
| `board_validation_report.py` | Combine runner, release, UART and sweep artifacts into BLE-board or strict full-board validation Markdown/JSON reports. |
| `test_build_artifacts.py` | Validate generated `build/` metadata: BioMess board target, netcore HCI IPC, devicetree and `merged.hex`. |
| `package_firmware_release.py` | Package `merged.hex`, manifest, hashes, verification report, handoff docs and package-local flash/verify tools into a zip. |
| `describe_firmware_release.py` | Summarize the latest or selected release zip: board, hash, verification summary and missing full-board checks. |
| `verify_firmware_release.py` | Verify a handoff zip contains required docs/tools, matches manifest size/SHA256, and that package-local flash/BLE/PMIC/AD5940 helpers start after extraction. |
| `test_release_matches_build.py` | Compare a release zip against the current `build/merged.hex` so stale handoff packages are caught. |
| `capture_uart.py` | Capture boot/runtime UART logs at 115200 baud for bring-up reports. |
| `test_uart_boot_log.py` | Validate captured UART boot logs for PMIC, BLE, SPI and AD5940 GPIO markers. |
| `scan_advertising.py` | Passive BLE scan that validates the `BioMess` local name and advertised `AF00` service without opening a GATT connection. |
| `ble_probe.py` | Scan/connect, require the `BioMess` advertised name, validate the app GATT contract (`AF00-AF03`, `0xC000`, config and battery characteristics), read config and optionally write JSON evidence. |
| `describe_ble_contract.py` | Summarize the firmware/Android/iOS UUID and command contract as console, JSON or Markdown output. |
| `test_board_health.py` | Send health command and validate PMIC plus AD5940 ADIID/CHIPID. |
| `test_pmic_battery.py` | Send battery command and validate nPM1304 payload. |
| `test_led_command.py` | Send LED blink command to verify command writes. |
| `test_ad5940_sweep.py` | Configure and run a BLE-streamed AD5940 sweep, then save CSV. |
| `generate_sweep_fixture.py` | Generate a deterministic resistor-like sweep CSV for offline analyzer checks and examples. |
| `analyze_sweep_csv.py` | Validate sweep CSV structure and optionally compare magnitude/phase to a known resistor. |
| `test_stored_sync.py` | Read/clear RAM-backed stored measurements and validate CRC16. |
| `test_auto_mode.py` | Start auto mode and wait for one firmware-initiated measurement stream. |
| `test_protocol_payloads.py` | Offline parser check for measurement, battery and stored-record payload formats. |
| `test_protocol_contract.py` | Offline contract check for UUIDs/opcodes shared by firmware, Android and iOS. |
| `test_hardware_contract.py` | Offline contract check for AD5940, nPM1304, LED and button devicetree pin mapping. |
| `test_docs_links.py` | Offline check for local Markdown links in firmware docs and READMEs. |
| `test_python_syntax.py` | Syntax-check Python tools without writing `__pycache__` into the repo. |
| `test_board_validation_report.py` | Offline fixture for strict final board validation report behavior. |
| `test_readiness_report.py` | Offline fixture for handoff-ready, full-board-ready, malformed-release and mismatched-release readiness states. |
| `test_release_package_fixture.py` | Create a synthetic handoff zip and verify package-local flash/BLE/PMIC/AD5940 tooling without Nordic SDK or hardware. |

All BLE scripts accept `--address` and `--name-prefix`.
`run_verification.py --ble` requires `bleak`, `--uart` requires `pyserial`, and `--flash` requires a debugger listed by `nrfjprog --ids`.
Check that explicitly with `firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/preflight.py --require-board` before flashing.
Use `run_verification.py --board`, `--west`, `--ncs-dir`, and `--zephyr-sdk` when the Zephyr board target or Nordic install paths differ from this machine.
For symptom-based failure triage, see `firmware/nrf5340_zephyr/docs/troubleshooting.md`.

Typical flows:

```bash
# Inspect local tools and visible board interfaces.
python3 firmware/nrf5340_zephyr/tools/preflight.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/diagnose_debugger.py \
  --summary-json /tmp/biomess_debugger.json
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/readiness_report.py \
  --summary-json /tmp/biomess_readiness.json
cd firmware/nrf5340_zephyr && make help

# Program the built image and keep an auditable log.
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/flash_firmware.py \
  --log /tmp/biomess_flash.log \
  --summary-json /tmp/biomess_flash.json
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/flash_firmware.py \
  --package firmware/nrf5340_zephyr/build/releases/biomess-nrf5340-firmware-20260605T000000Z.zip \
  --log /tmp/biomess_flash_package.log \
  --summary-json /tmp/biomess_flash_package.json
# After extracting a release package:
python3 tools/flash_firmware.py --log /tmp/biomess_flash.log --summary-json /tmp/biomess_flash.json

# Offline contract/payload checks plus firmware build.
python3 firmware/nrf5340_zephyr/tools/run_verification.py
python3 firmware/nrf5340_zephyr/tools/run_verification.py --report /tmp/biomess_firmware_verification.md
cd firmware/nrf5340_zephyr && make ci-offline
cd firmware/nrf5340_zephyr && make release-fixture
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/summarize_verification.py /tmp/biomess_firmware_verification.json
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile --report /tmp/biomess_mobile_verification.md
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/package_firmware_release.py \
  --report /tmp/biomess_firmware_verification.md \
  --summary-json /tmp/biomess_firmware_verification.json
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/describe_firmware_release.py
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/verify_firmware_release.py \
  firmware/nrf5340_zephyr/build/releases/biomess-nrf5340-firmware-*.zip \
  --require-report \
  --require-summary-json \
  --require-build-summary
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/test_release_matches_build.py

# After flashing or with --flash, run BLE checks against the board.
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/ble_probe.py \
  --summary-json /tmp/biomess_gatt_probe.json
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/scan_advertising.py \
  --summary-json /tmp/biomess_advertising_scan.json
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --ble
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --flash --ble
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --flash --ble --report /tmp/biomess_board_verification.md
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --flash --uart --ble --report /tmp/biomess_board_verification.md
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/board_validation_report.py \
  --verification-json /tmp/biomess_board_verification.json \
  --release-package firmware/nrf5340_zephyr/build/releases/biomess-nrf5340-firmware-20260605T000000Z.zip \
  --require-full-board \
  --output /tmp/biomess_board_validation.md \
  --summary-json /tmp/biomess_board_validation.json
```

`run_verification.py --ble` writes `biomess_advertising_scan.json` and `biomess_gatt_probe.json` next to `--report`, or under `/tmp` when no report path is passed. Override those with `--advertising-summary-json <path>` and `--ble-summary-json <path>`.

When the verification JSON was produced by `run_verification.py --flash --uart --ble`, the `firmware flash` step is enough flash evidence for `--require-full-board`. Pass `--flash-json` only for a separate `tools/flash_firmware.py` log.

When UART is not routed to the available serial ports, validate the BLE/PMIC/AD5940 surface independently:

```bash
make firmware-ble
make firmware-ble-board-report
```

Analog sanity check with a known resistor after a sweep:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/generate_sweep_fixture.py \
  --csv /tmp/biomess_sweep_fixture.csv \
  --points 48 \
  --repetitions 5 \
  --ohms 10000
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/analyze_sweep_csv.py \
  /tmp/biomess_sweep_fixture.csv \
  --points 48 \
  --expected-ohms 10000 \
  --magnitude-tolerance-pct 20 \
  --max-abs-phase-deg 15
```
