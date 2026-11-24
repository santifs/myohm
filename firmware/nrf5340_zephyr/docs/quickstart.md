# BioMess nRF5340 quickstart

Use this when you open the repo and need to know the next command without reading every document first.

## 1. No hardware connected

This path proves the firmware/app contract, tooling, documentation links, release packaging and synthetic sweep analysis without a PCB or debugger:

```bash
make firmware-setup
make firmware-ci-offline
make firmware-verify-mobile
make firmware-verify-mobile-tests
make firmware-handoff
```

Healthy signs:

- `protocol_contract_ok=true`
- `hardware_contract_ok=true`
- `docs_links_ok=true`
- `readiness_report_contract_ok=true`
- `sweep_csv_ok=true`
- Android `:core-ble:compileDebugKotlin` and `:core-ble:testDebugUnitTest` exit 0.
- iOS `swift build` and `swift test` exit 0 on macOS.
- GitHub Actions runs Android `:core-ble:testDebugUnitTest` on Ubuntu and iOS `swift test` on macOS 15.
- `release_package_verify_ok=true`
- `release_matches_build_ok=true`
- `readiness_handoff_ready=true`
- `readiness_serial_debug_port_visible=...` and `readiness_next_step=...` explain whether the next blocker is a missing J-Link/nRF debugger or a serial-only USB endpoint.

## 2. Before flashing a board

Do not flash until Nordic tools see a real debugger:

```bash
make firmware-preflight-board
```

Healthy sign:

```text
nrfjprog_ids=<debugger-serial>
```

If `nrfjprog_ids=` is empty but serial ports exist, run:

```bash
make firmware-diagnose
```

A USB serial endpoint is not enough to program the nRF5340. The debugger must be visible to `nrfjprog --ids`.

## 3. Board validation path

For a first board validation with a debugger attached, flash first and let the runner capture UART, advertising, GATT, PMIC, AD5940 sweep and stored-sync evidence:

```bash
make firmware-board-full
make firmware-board-report
```

Healthy final gate:

```text
board_validation_ok=true
```

That gate requires flash, UART capture, UART boot log check, BLE/GATT probe, board health, PMIC battery, LED command, AD5940 sweep, sweep CSV analysis and stored sync evidence. `make firmware-advertising` is the faster passive check to run first when a phone app cannot find the board.

If the board is already flashed and no phone is connected to it, the faster passive advertising check is:

```bash
make firmware-advertising
make firmware-ble
make firmware-ble-board-report
```

If that scan sees other BLE devices but no `BioMess` match, reset/flash the board or disconnect the phone app before running GATT/PMIC/AD5940 checks from the Mac.
`make firmware-ble-board-report` is the objective-level hardware gate for BLE, PMIC, LED, AD5940 sweep and stored-sync evidence when UART boot logs are not routed to the debug USB serial ports.

## 4. Package handoff path

The newest release zip is under:

```text
firmware/nrf5340_zephyr/build/releases/
```

Inspect it before sending or flashing:

```bash
make firmware-handoff
```

If a package already exists and you only want to inspect it, use `make firmware-release-info`, `make firmware-verify-release` and `make firmware-release-matches-build`.

After extracting a package on another machine:

```bash
python3 -m pip install -r tools/requirements.txt
python3 tools/preflight.py --require-board
python3 tools/flash_firmware.py --dry-run --summary-json /tmp/biomess_flash_dry_run.json
python3 tools/flash_firmware.py --log /tmp/biomess_flash.log --summary-json /tmp/biomess_flash.json
python3 tools/ble_probe.py --summary-json /tmp/biomess_gatt_probe.json
python3 tools/test_board_health.py
python3 tools/test_pmic_battery.py
python3 tools/test_ad5940_sweep.py --points 48 --start-hz 4000 --stop-hz 198000 --repetitions 5 --csv /tmp/biomess_sweep.csv
python3 tools/analyze_sweep_csv.py /tmp/biomess_sweep.csv --points 48 --expected-ohms 10000 --magnitude-tolerance-pct 20 --max-abs-phase-deg 15
```

## 5. Where to read next

- [validation-matrix.md](validation-matrix.md): requirement-to-evidence audit.
- [bring-up.md](bring-up.md): full first-board checklist.
- [verification.md](verification.md): detailed command reference and expected output.
- [troubleshooting.md](troubleshooting.md): what to run when a step fails.
- [mobile-integration.md](mobile-integration.md): Android/iOS BLE contract notes.
