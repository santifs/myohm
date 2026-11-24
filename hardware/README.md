# Myohm hardware

Current PCB v2 candidate: nRF5340 / AD5941 / nPM1304, imported from the `AllInOne-corrected` hardware working tree. This is not the old nRF52832/BQ24074 board.

Open `mainboard/AllInOne.kicad_pro` with KiCad 10.0.3 and standard KiCad 10 footprint/3D libraries installed. Project libraries use `${KIPRJMOD}`. Recovered symbols started from imported definitions; the electrical review records subsequent pin-type corrections. Editable does not mean fully validated. Footprint filters include the assigned KiCad names in addition to imported Altium names; this is metadata migration, not dimensional approval.

Firmware target: `biomess_nrf5340/nrf5340/cpuapp`. [Pinout](../firmware/nrf5340_zephyr/docs/hardware-v2.md), [audit](../docs/hardware-audit.md).

The historical `BOM.csv` is a reference only; use the generated schematic inventory in reports for review. Missing manufacturer part numbers and unknown battery remain release blockers. No production Gerbers are included, because inherited Gerbers predate the corrected board.

Original hardware contributions: **CERN-OHL-S-2.0**, with [scope and third-party exclusions](LICENSE.md).
