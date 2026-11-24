# Myohm licensing

Copyright 2026 Myohm contributors. Licences apply by component, not as a blanket licence for all repository contents.

| Original contribution | Licence | Scope |
| --- | --- | --- |
| Hardware | CERN-OHL-S-2.0 | Original main-board and electrode-strip circuit connections, layout, project configuration, BOM and generated fabrication files in `hardware/mainboard/` and `hardware/electrodes/` |
| Firmware | Apache-2.0 | Original software in `firmware/`, excluding third-party material |
| Web application | Apache-2.0 | Original software in `web/` |
| Scripts | Apache-2.0 | Original software in `tools/` |
| iOS and Android | Apache-2.0 | Original local-only clients in `mobile/`; the experimental companion applications remain in `biomess/mobile/` |
| Bench data | CC-BY-4.0 | Measurements of the impedance test board in `tools/bench/data/` |

Full terms: [CERN-OHL-S-2.0](LICENSES/CERN-OHL-S-2.0.txt), [Apache-2.0](LICENSES/Apache-2.0.txt) and [CC-BY-4.0](LICENSES/CC-BY-4.0.txt). See [hardware scope](hardware/LICENSE.md) and [third-party notices](THIRD_PARTY_NOTICES.md).

All existing third-party notices and licences remain in force. The grant covers only rights held by Myohm contributors. Third-party CAD symbols, footprints and models, including embedded copies, are not relicensed. The maintainer confirmed on 2026-10-14 that permission to redistribute the imported CAD assets had been requested and approved. This permission does not relicense those assets; retain their applicable terms and attribution. ADI reference code retains `LicenseRef-ADI-reference`; Nordic binaries and other dependencies retain their own terms. The complete firmware binary is not wholly Apache-licensed.

Documentation prose, reports, research datasets other than the bench data above, participant data, externally authored figures, name and logo receive no additional grant here. Source availability does not establish data-publication permission or unrestricted redistribution of every component.

Source Location: https://github.com/santifs/myohm.

2026-10-22: the maintainer confirmed that the code of the iOS and Android clients in `mobile/`, including the packages named `com.volumhealth`, belongs to the project authors and is published under Apache-2.0.

2026-10-14: extended CERN-OHL-S-2.0 to original electrode-strip designs and adopted Apache-2.0 for original software on the maintainer's explicit instruction. These local changes do not by themselves create a public release or DOI.
