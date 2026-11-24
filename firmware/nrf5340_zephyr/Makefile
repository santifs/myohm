PYTHON ?= python3
PY ?= .venv/bin/python
export PYTHONDONTWRITEBYTECODE := 1
BOARD ?= biomess_nrf5340/nrf5340/cpuapp
REPORT_DIR ?= /tmp
BOARD_REPORT ?= $(REPORT_DIR)/biomess_board_verification.md
BOARD_JSON ?= $(REPORT_DIR)/biomess_board_verification.json
BLE_REPORT ?= $(REPORT_DIR)/biomess_ble_board.md
BLE_JSON ?= $(REPORT_DIR)/biomess_ble_board.json
FLASH_LOG ?= $(REPORT_DIR)/biomess_flash.log
FLASH_JSON ?= $(REPORT_DIR)/biomess_flash.json
BOARD_VALIDATION ?= $(REPORT_DIR)/biomess_board_validation.md
BOARD_VALIDATION_JSON ?= $(REPORT_DIR)/biomess_board_validation.json
BLE_BOARD_VALIDATION ?= $(REPORT_DIR)/biomess_ble_board_validation.md
BLE_BOARD_VALIDATION_JSON ?= $(REPORT_DIR)/biomess_ble_board_validation.json
RELEASE_PACKAGE ?= $(shell ls -t build/releases/biomess-nrf5340-firmware-*.zip 2>/dev/null | head -1)

.PHONY: help setup preflight preflight-board diagnose readiness verify verify-offline verify-mobile verify-mobile-tests ci-offline flash flash-dry-run advertising ble board-full package handoff release-fixture release-info verify-release release-matches-build ble-board-report board-report syntax docs-links protocol-contract hardware-contract payloads

help:
	@echo "BioMess nRF5340 firmware commands"
	@echo ""
	@echo "  make setup             Create/update .venv with BLE/UART dependencies"
	@echo "  make preflight         Check west, SDK, nrfjprog, Python deps and serial ports"
	@echo "  make preflight-board   Require an nRF/J-Link debugger before flashing"
	@echo "  make diagnose          Explain debugger vs serial-port visibility"
	@echo "  make readiness         Summarize build/release/debugger/board evidence state"
	@echo "  make verify            Offline checks plus firmware build for $(BOARD)"
	@echo "  make verify-offline    Offline checks only, no firmware build"
	@echo "  make verify-mobile     Android/iOS BLE compatibility builds"
	@echo "  make verify-mobile-tests Android/iOS BLE compatibility tests"
	@echo "  make ci-offline        CI-safe offline contracts/docs/scripts check"
	@echo "  make flash             Program build/merged.hex and write flash log/JSON"
	@echo "  make flash-dry-run     Show exact flash command and image SHA256 without programming"
	@echo "  make advertising       Passive BLE advertising scan, no GATT connection"
	@echo "  make ble               Run BLE/GATT, PMIC, AD5940 sweep and stored-sync checks"
	@echo "  make board-full        Flash, capture UART, run BLE checks and write report/JSON"
	@echo "  make package           Build verification report and create release zip"
	@echo "  make handoff           Package, verify release/build match and print readiness"
	@echo "  make release-fixture   Build and verify a synthetic release zip without hardware"
	@echo "  make release-info      Describe latest release zip or RELEASE_PACKAGE=<zip>"
	@echo "  make verify-release    Verify latest release zip or RELEASE_PACKAGE=<zip>"
	@echo "  make release-matches-build Compare latest release zip against build/merged.hex"
	@echo "  make ble-board-report  Build board evidence report from BLE/PMIC/AD5940 checks"
	@echo "  make board-report      Build strict final board evidence report"

setup:
	$(PYTHON) tools/setup_python_env.py

preflight:
	$(PY) tools/preflight.py --require-bleak --require-pyserial

preflight-board:
	$(PY) tools/preflight.py --require-board

diagnose:
	$(PY) tools/diagnose_debugger.py

readiness:
	$(PY) tools/readiness_report.py --summary-json $(REPORT_DIR)/biomess_readiness.json

verify:
	$(PY) tools/run_verification.py --board $(BOARD) --report $(REPORT_DIR)/biomess_firmware_verification.md

verify-offline:
	$(PY) tools/run_verification.py --skip-build --report $(REPORT_DIR)/biomess_offline_verification.md

verify-mobile:
	$(PY) tools/run_verification.py --skip-build --mobile --report $(REPORT_DIR)/biomess_mobile_verification.md

verify-mobile-tests:
	$(PY) tools/run_verification.py --skip-build --mobile-tests --report $(REPORT_DIR)/biomess_mobile_tests_verification.md

ci-offline:
	$(PYTHON) tools/run_verification.py --skip-build --report $(REPORT_DIR)/biomess_ci_offline.md
	$(PYTHON) tools/summarize_verification.py $(REPORT_DIR)/biomess_ci_offline.json

flash:
	$(PY) tools/flash_firmware.py --log $(FLASH_LOG) --summary-json $(FLASH_JSON)

flash-dry-run:
	$(PY) tools/flash_firmware.py --dry-run --log $(FLASH_LOG) --summary-json $(FLASH_JSON)

advertising:
	$(PY) tools/scan_advertising.py --summary-json $(REPORT_DIR)/biomess_advertising_scan.json

ble:
	$(PY) tools/run_verification.py --skip-build --ble --report $(BLE_REPORT)

board-full:
	$(PY) tools/run_verification.py --flash --uart --ble --report $(BOARD_REPORT)

package:
	$(PY) tools/run_verification.py --board $(BOARD) --report $(REPORT_DIR)/biomess_firmware_verification.md
	$(PY) tools/package_firmware_release.py --report $(REPORT_DIR)/biomess_firmware_verification.md --summary-json $(REPORT_DIR)/biomess_firmware_verification.json

handoff:
	$(MAKE) package
	$(MAKE) verify-release
	$(MAKE) release-matches-build
	$(MAKE) release-info
	$(MAKE) readiness

release-fixture:
	$(PYTHON) tools/test_release_package_fixture.py

release-info:
	$(PY) tools/describe_firmware_release.py $(RELEASE_PACKAGE)

verify-release:
	@test -n "$(RELEASE_PACKAGE)" || (echo "No release package found; run make package or pass RELEASE_PACKAGE=<zip>" && exit 1)
	$(PY) tools/verify_firmware_release.py $(RELEASE_PACKAGE) --require-report --require-summary-json --require-build-summary

release-matches-build:
	@test -n "$(RELEASE_PACKAGE)" || (echo "No release package found; run make package or pass RELEASE_PACKAGE=<zip>" && exit 1)
	$(PY) tools/test_release_matches_build.py --release-package $(RELEASE_PACKAGE)

ble-board-report:
	@test -n "$(RELEASE_PACKAGE)" || (echo "No release package found; run make package or pass RELEASE_PACKAGE=<zip>" && exit 1)
	$(PY) tools/board_validation_report.py --verification-json $(BLE_JSON) --release-package $(RELEASE_PACKAGE) --require-ble-board --output $(BLE_BOARD_VALIDATION) --summary-json $(BLE_BOARD_VALIDATION_JSON)

board-report:
	@test -n "$(RELEASE_PACKAGE)" || (echo "No release package found; run make package or pass RELEASE_PACKAGE=<zip>" && exit 1)
	$(PY) tools/board_validation_report.py --flash-json $(FLASH_JSON) --verification-json $(BOARD_JSON) --release-package $(RELEASE_PACKAGE) --require-full-board --output $(BOARD_VALIDATION) --summary-json $(BOARD_VALIDATION_JSON)

syntax:
	$(PY) tools/test_python_syntax.py

docs-links:
	$(PY) tools/test_docs_links.py

protocol-contract:
	$(PY) tools/test_protocol_contract.py

hardware-contract:
	$(PY) tools/test_hardware_contract.py

payloads:
	$(PY) tools/test_protocol_payloads.py
