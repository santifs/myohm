# Myohm bench measurements

Raw measurements of one Myohm unit on the Analog Devices AD5940 impedance test board (EVAL-AD5940BIOZ, schematic 02-049393 rev. A), acquired with `../ztest.py` in October 2026. `../bench_error_model.py` and `../mismatch_model.py` read them from this directory.

## Layout

| Folder | Strip (voltage-electrode spacing) | Session |
|---|---|---|
| `VV150_2026-10-07/` | 150 mm | 7 October 2026 (earlier session) |
| `VV150/` | 150 mm | 9 October 2026 (reported session) |
| `VV150_r2/` | 150 mm | 9 October 2026, repeat of two configurations |
| `VV100/` | 100 mm | 9 October 2026 |
| `VV75/` | 75 mm | 9 October 2026 |

Each configuration has a CSV and a JSON with the same name:

- `<config>.csv` has the columns `rep, freq_hz, mag_ohm, phase_deg, nom_mag_ohm, nom_phase_deg`, with 3 sweeps of 40 logarithmic points from 4 to 198 kHz. The magnitude and phase are as reported by the device; the nominal values come from the switch settings.
- `<config>.json` holds the metadata: device, strip, timestamp, number of points and repetitions, DIP switches left OFF (connected) per bank, and a free-text note.

Configuration names follow `../ztest.py`:

- `zb<R>` is the load bank (for example `zb100` for 100 Ω and `zb4k99` for 4.99 kΩ), and `zb0` is the shorted bank.
- Suffixes describe the contact impedances: `_c402` for 402 Ω at every contact, `_f1k` for about 1 kΩ at the current electrodes, `_fhi` for 10 kΩ and 4.99 kΩ at the current electrodes, and `_shi` and `_s1M` for 300 kΩ and 1 MΩ at a voltage electrode.
- `_flex` marks a sweep taken while the strip was being bent by hand, and `_1n` and `_10n` mark series RC loads.

The notes are in Spanish.

## Known issues

- **`VV150_2026-10-07/zb100_fhi`** was mounted with banks S4 and S5 swapped by mistake, as recorded in its note: F+ 10 kΩ, F− 402 Ω, S+ 402 Ω and S− 4.99 kΩ. It is therefore a voltage-contact test, not a repeat of `zb100_fhi`.
- **`zb100p200`** is two resistors in series (300 Ω). An older note in the 7 October session says it is in parallel (66.7 Ω); the measured data and the switch logic show it is in series.
- **Load values are nominal.** Tolerances are 0.1 %, except 300 Ω, 510 Ω and 2 kΩ at 1 % and the capacitors at 5–10 %. The resistors were not measured independently, so these files do not constitute a calibrated uncertainty budget.
- **Unit name.** `device` is the BLE name of the unit; `Messi-05` is an internal nickname for this one board.

## License

These data are licensed under CC-BY-4.0 (`LICENSES/CC-BY-4.0.txt`). Please credit the Myohm project when you reuse them.
