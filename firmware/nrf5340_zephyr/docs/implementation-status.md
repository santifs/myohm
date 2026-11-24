# BioMess firmware implementation status

Last updated: 2026-06-09.

This document records what is implemented, what is verified locally, and what still requires a physical BioMess/nRF5340 board.

Historical record from the original firmware tree. The Android/iOS apps and the mobile CI jobs mentioned below are not part of this repository.

## Firmware image

- Build target: `biomess_nrf5340/nrf5340/cpuapp` with a BioMess out-of-tree Zephyr board definition.
- Current image path after build: `firmware/nrf5340_zephyr/build/merged.hex`.
- Current image size and SHA256 are build artifacts; inspect them with `make -C firmware/nrf5340_zephyr flash-dry-run` or `tools/flash_firmware.py --dry-run --summary-json /tmp/biomess_flash_dry_run.json`.
- Handoff packages are written under `firmware/nrf5340_zephyr/build/releases/`; use `make firmware-release-info` and `make firmware-release-matches-build` from the repo root to identify and verify the newest package.
- BLE device name: `BioMess`.
- Short command path: `docs/quickstart.md`.
- Current runtime behavior: `docs/current-system-behavior.md`.
- Primary protocol documentation: `docs/ble-protocol.md`.
- Mobile integration notes: `docs/mobile-integration.md`.
- Low-power strategy: `docs/low-power-strategy.md`.
- Requirement-to-evidence audit: `docs/validation-matrix.md`.
- First-board validation guide: `docs/bring-up.md`.
- Failure triage guide: `docs/troubleshooting.md`.

## Implemented firmware paths

| Area | Status | Evidence |
| --- | --- | --- |
| BLE advertising and GATT services | Implemented | `src/ble_service.c`, `docs/ble-protocol.md` |
| Android/iOS command characteristic `0xC000` | Implemented | `src/ble_service.c`, `tools/test_protocol_contract.py` |
| AD5940 sweep streaming | Implemented | `src/ad5940/AD5940Main.c`, `src/ble_service.c`, `tools/test_ad5940_sweep.py`, `tools/analyze_sweep_csv.py` |
| Sweep config read/write | Implemented | `0xC011-0xC017`, clamped points `2..100`, reps `1..10` |
| PMIC battery command | Implemented | `src/board_power.c`, command `0x02`, `tools/test_pmic_battery.py` |
| Power button / ship mode | Implemented | `src/board_power.c`; nPM1304 `SHIPHOLD` press/release events arm a 3 s hold timer, show one long LED pulse when shutdown is armed, and request regulator parent ship mode only after release when USB VBUS is absent |
| nRF/BLE low-power policy | Implemented | `src/main.c`, `src/ble_service.c`, `prj.conf`; fast advertising window falls back to slow advertising, short press restarts fast advertising, connected idle uses slower connection parameters, measurement temporarily requests faster parameters, status LED no longer loops continuously, and `CONFIG_PM_DEVICE_RUNTIME` is enabled |
| Board health command | Implemented | command `0x0A`, `tools/test_board_health.py`, reads PMIC and AD5940 ADIID/CHIPID; ADIID OK is only set for expected `0x4144` |
| LED command | Implemented | command `0x64`, `tools/test_led_command.py` |
| Stored measurement sync | Implemented as RAM ring buffer | commands `0x07/0x08/0x09`, `tools/test_stored_sync.py` |
| Auto mode | Implemented while connected | commands `0x05/0x06`, `tools/test_auto_mode.py` |
| IMU commands | Placeholder | commands return zero-filled quaternions |

## Local verification passed

Run from repo root:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --report /tmp/biomess_runner_build.md
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile --report /tmp/biomess_mobile_runner.md
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py --skip-build --mobile-tests --report /tmp/biomess_mobile_tests_runner.md
make -C firmware/nrf5340_zephyr verify REPORT_DIR=/tmp/biomess_final_verify
```

Current local evidence:

| Check | Current result |
| --- | --- |
| Python tooling preflight | `west_available=true`, `zephyr_sdk_available=true`, `bleak_available=true`, `pyserial_available=true` |
| Offline payload parser | `protocol_payloads_ok=true` |
| Firmware/app BLE contract | `protocol_contract_ok=true` |
| Hardware/devicetree pin contract | `hardware_contract_ok=true` |
| Firmware documentation links | `docs_links_ok=true` |
| Python script syntax | `python_syntax_ok=true`; `test_python_syntax.py` checks all runtime Python tools and release verification compiles the packaged tools |
| BLE contract summary | `ble_contract_ok=true`; prints firmware/Android/iOS UUID and opcode coverage |
| Offline sweep analysis fixture | `sweep_fixture_ok=true`, `sweep_csv_ok=true`; validates CSV analyzer without AD5940 hardware |
| Firmware build | `verification_ok=true`; `build/merged.hex` exists; runner emits Markdown and JSON summaries; `tools/test_build_artifacts.py` checks BioMess board metadata and nRF5340 netcore HCI IPC |
| Offline CI | Implemented: `.github/workflows/firmware-offline-checks.yml` runs `make firmware-ci-offline` for payload, BLE contract, hardware pin contract, docs links, Python syntax, readiness report fixture behavior, board validation report fixture behavior, synthetic release-package verification and sweep fixture analysis without requiring hardware; the same workflow runs Android `:core-ble:testDebugUnitTest` in `mobile-android-tests` on Ubuntu with Java 17 and iOS `swift test` in `mobile-ios-tests` on macOS 15 |
| Firmware handoff package | Implemented: `tools/package_firmware_release.py` writes zip with app-core and network-core images, hashes, manifest, docs, all Python tools and package-local board-check commands; `tools/describe_firmware_release.py` summarizes it; `tools/verify_firmware_release.py` validates entries, hashes, build summary, dependency hints, extracted flasher dry-run and package-local BLE/PMIC/AD5940 script help |
| Release/build consistency | Implemented: `tools/test_release_matches_build.py` verifies the selected release zip contains the current `build/merged.hex` |
| Readiness summary | Implemented: `tools/readiness_report.py` summarizes build/release/debugger/serial/full-board evidence and prints the next concrete command; `tools/test_readiness_report.py` covers handoff-ready, full-board-ready, malformed-release and mismatched-release states |
| Board evidence report | Implemented: `tools/board_validation_report.py` supports `--require-ble-board` for BLE/PMIC/LED/AD5940/stored-sync evidence and `--require-full-board` for the stricter flash+UART+BLE gate |
| Android BLE build | `:core-ble:compileDebugKotlin` exits 0 |
| iOS package build | `swift build` exits 0 |
| Android BLE unit tests | `:core-ble:testDebugUnitTest` exits 0 |
| iOS package tests | `swift test` exits 0 locally on macOS via `run_verification.py --skip-build --mobile-tests`; CI also runs `swift test` in `mobile-ios-tests` |

## Current board status

The current low-power/BLE policy image builds and is packaged, but it has not been flashed in the latest session because `nrfjprog --ids` returned no debugger serial. The latest built image at the time of this update was:

```text
build_artifacts_merged_hex=build/merged.hex
build_artifacts_merged_hex_bytes=498296
build_artifacts_merged_hex_sha256=637f129e81c0facac3508549817cbf73c90a03069f28e6af55fd5906a915f210
release_package=build/releases/biomess-nrf5340-firmware-20260609T171153Z.zip
```

The DK J-Link now detects the external BioMess target through P20, AP protection has been cleared with `nrfjprog --recover`, and the app-core plus network-core images have been programmed and verified on the PCB. After a full recover, program both `build/merged.hex` and `build/merged_CPUNET.hex`; programming only the app core leaves Bluetooth initialization failing.

Example board-programming evidence from the 2026-06-08 bring-up session:

```text
nrfjprog_ids=1050009456
flash_ok=true
hex_size_bytes=484584
hex_sha256=77f4c1126edbddc3adebd80af1cf9c6b10698f6bf5cae1fcf332f35203eaa2cc
```

The app image programmed during that session was:

```text
flash_ok=true
hex_size_bytes=484584
hex_sha256=77f4c1126edbddc3adebd80af1cf9c6b10698f6bf5cae1fcf332f35203eaa2cc
```

The network-core image programmed during that session was `build/merged_CPUNET.hex` with SHA256 `00a162e0cf3c36c32b87ca067d267ec3ce7168445258145afcf6fe593ef6a290`.

The firmware includes a visible status pattern on `led0` (`P1.10`, active high): 1 pulse means BLE and AD5940 initialized, 2 means BLE failed, 3 means AD5940 failed, and 4 means both failed.

Hardware evidence collected from the current image after the 2026-06-08 advertising-restart fix:

```text
advertised_name=BioMess
advertised_name_validation_ok=true
gatt_validation_ok=true
ble_probe_ok=true
health_flags=0x0007
pmic_ok=true
battery_voltage_mv=4150
battery_percentage=94
ad5940_adi_id=0x4144
ad5940_chip_id=0x5502
ad5940_identity_ok=true
sweep_expected_points=240
sweep_received_points=240
sweep_repetitions=5
sweep_points_per_repetition=48
sweep_csv_ok=true
stored_count=1
stored_records_received=1
stored_crc=ok
```

The firmware now restarts connectable advertising from a delayed work item after central disconnect. This was validated by running advertising scan, GATT probe, board health, PMIC battery, LED command, AD5940 sweep and stored sync as separate BLE connections in one runner pass.

UART evidence is still incomplete on this bench setup: `capture_uart.py` selected `/dev/cu.debug-console` and the J-Link USB modem ports were tested manually, but all captured 0 bytes after reset. Treat UART boot-log validation as a wiring/console-routing item for the PCB/debug setup; BLE, PMIC and AD5940 board evidence is available through the BLE tools.

Still limited or intentionally scoped:

- Stored measurements are RAM-backed; stored-sync behavior is verified by protocol tests and available as `tools/test_stored_sync.py`, but data is lost on reset.
- Auto mode runs only while connected and should be exercised with `tools/test_auto_mode.py --duration 60` when no mobile app is connected.
- IMU commands return zero-filled quaternion data until a real IMU path is integrated.

## Hardware verification command

Once `nrfjprog --ids` shows a debugger serial:

```bash
firmware/nrf5340_zephyr/.venv/bin/python firmware/nrf5340_zephyr/tools/run_verification.py \
  --flash \
  --uart \
  --ble \
  --report /tmp/biomess_board_verification.md
```

Add `--include-auto` for the 60-second auto-mode test. If the mobile app is open and connected, stop/disconnect it first so the Mac can connect to the BLE peripheral.

## Known limitations

- Stored measurements are RAM-backed only and are lost on reset.
- Auto mode stops when BLE disconnects.
- IMU commands return zero-filled quaternion data until a real IMU path is integrated.
- The iOS and Android projects still retain legacy package/target namespaces such as `VolumHealth` and `com.volumhealth`. Those identifiers are packaging debt only: BLE-facing class names, advertised name, scan filters, service contract, commands, tests and protocol docs use `BioMess`.
