# Hardware licence notice

Copyright © 2026 Myohm contributors.
SPDX-License-Identifier: CERN-OHL-S-2.0

The original Myohm circuit connections, PCB layout, project configuration and
bill-of-materials contributions in `mainboard/` and `electrodes/`, including original generated fabrication files, are licensed under the
CERN Open Hardware Licence Version 2 — Strongly Reciprocal, version 2.0.
The complete, unmodified terms are in [CERN-OHL-S-2.0.txt](../LICENSES/CERN-OHL-S-2.0.txt).

You may use, modify and redistribute the covered source and make and distribute
products under those terms. The source and products are provided without warranty
as specified in section 6 of the licence. No endorsement by CERN is implied.

Third-party symbols, footprints and models, including embedded copies, retain
original rights and terms. `library/`, `3D/`, and the `.pretty` directories are
not collectively relicensed by this notice. See [the repository scope](../LICENSE.md)
and [provenance review](../docs/licensing.md). The grant does not assert that
unresolved third-party material qualifies as an Available Component under the licence.

## Source and modification record

Source repository: https://github.com/santifs/myohm.

- 2026-09-17: imported corrected design, recovered local libraries, made paths
  portable, replaced inherited board logo, tightened minimum track rule.
- 2026-09-20: corrected electrical pin roles and three contradictory NC markers;
  connectivity and board copper unchanged in that revision.
- 2026-09-28: licensed original hardware under CERN-OHL-S-2.0; added these
  notices without changing electrical design or relicensing third-party material.

Detailed changes and source hashes are retained in Git,
[the import manifest](../docs/import-manifest.json) and
[the electrical review](../docs/electrical-review.md).

- 2026-10-14: extended this grant to original electrode-strip designs and their variants; third-party exclusions remain unchanged.
