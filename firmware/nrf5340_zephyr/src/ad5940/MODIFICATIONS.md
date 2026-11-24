# ADI-derived source modification notice

This directory is an adapted Myohm/BioMess distribution, **not an unmodified
Analog Devices release**. Original notices remain intact. The seven ADI-derived files listed below retain
[the ADI terms](../../../../LICENSES/LicenseRef-ADI-reference.txt), including the
ADI-product restriction; the Apache grant for original Myohm software does not
replace them. Modification notices were added on 2026-10-14 without changing
executable code.

- `ad5940.c`, `ad5940.h`: differ from ad5940lib commit
  `818c54822ad35c57ec277e1503cd45e9dc4e554f`. Differences include register-cache
  lookup, filter/calibration implementations and declarations, chip selection,
  debug configuration and filter clock definitions. This is a comparison baseline,
  **not proof of the original imported revision**; some differences can reflect
  upstream evolution rather than local edits. Historical comparison hashes are
  recorded in `reports/adi-provenance.json` at repository root.
- `AD5940Main.c`, `AD5940Main.h`: adapted application entry points, Zephyr execution,
  sweep configuration, callbacks and measurement buffering; Myohm sets RCAL to the
  schematic's 30-ohm value. Physical validation is still pending.
- `BodyImpedance.c`, `BodyImpedance.h`: adapted BIA configuration and sequencing,
  project sweep limits and BLE integration. Original example headers are retained.
- `ZephyrPort.c`: board-specific Zephyr SPI/GPIO, interrupt and timing port.

On 2026-10-22, executable changes were made to `AD5940Main.c`, `AD5940Main.h` and
`BodyImpedance.c` (configurable excitation amplitude, an exported platform
configuration prototype). The contact check is original Myohm code in
`src/contact_check.c`, outside this directory. These changes are not validated on hardware.

The exact upstream revisions for the example and port files have not been
established. Do not infer authorship of individual changes from this inventory.
Source import hashes are in `docs/import-manifest.json`; subsequent Myohm changes
are recorded in Git. No ADI endorsement or whole-firmware open-source claim is made.
