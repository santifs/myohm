# Contributing to Myohm

Original hardware contributions use CERN-OHL-S-2.0; original firmware, web, native clients and tools use Apache-2.0. Third-party material keeps its own terms. See LICENSE.md. Submitting a contribution is not a copyright assignment; identify any third-party material and its licence.

## Ground rules

- The mainboard source of truth is `hardware/mainboard/AllInOne.kicad_pro` (KiCad 10.0.3). Read `docs/hardware-audit.md` before changing power, electrodes, pinout or libraries.
- Myohm is a research/teaching candidate, not physically qualified. Do not turn simulated or static checks into claims of hardware safety, BLE connectivity or manufacturing approval. Record whether evidence is static, simulated, bench-tested or measured on the physical device.
- The battery is unqualified and R7 is fixed. Do not enable charging or BUCK1 without resolving the documented hardware requirements.
- Preserve BLE wire compatibility. Do not change UUIDs or packet formats as a branding change, and do not assume the board advertises Myohm or a service UUID.
- Do not commit measurement data from people, credentials, local labels, historic PCB variants, experimental participant-management apps, build outputs, backups or fabrication files from a different revision.
- Keep project-local libraries portable (no machine-specific paths) and retain attribution and licences of third-party materials.
- Do not represent the platform as a certified medical device or release manufacturing files before the engineering gate is closed.

## Checks

Keep changes scoped and reviewable: describe the problem, source revision, design rationale and validation evidence.

```sh
python3 tools/check_repository.py
python3 tools/verify_firmware_offline.py
cd web && npm test && npm run build   # web changes; also check the visible flow for UI changes
python3 tools/check_hardware.py      # CAD changes; requires KiCad 10
```

ERC currently fails. Do not hide existing failures; resolve each item with evidence. New exclusions require a written component-level explanation.
