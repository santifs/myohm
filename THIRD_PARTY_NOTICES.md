# Third-party components

This index supplements, and does not replace, dependency licences and upstream NOTICE files. Preserve those files and applicable notices in every distribution.

- **Analog Devices:** `firmware/nrf5340_zephyr/src/ad5940/`, including ADI-noticed ports such as ZephyrPort.c, retains its original terms. Full text: `LICENSES/LicenseRef-ADI-reference.txt`. Provenance: `reports/adi-provenance.json`. Adaptations are identified in `firmware/nrf5340_zephyr/src/ad5940/MODIFICATIONS.md` and in each source header.
- **Nordic:** the inspected NCS 3.3.0 build links SoftDevice Controller and MPSL vendor binaries. Full vendor terms: `LICENSES/LicenseRef-Nordic-5-Clause.txt`; MPSL ARM attribution: `LICENSES/Nordic-MPSL-ATTRIBUTION.txt`. These include Nordic-product restrictions. Use the notices of the exact SDK used for a distributed build.
- **Zephyr:** Apache-2.0, with its own dependency notices. An SDK is not collectively relicensed by the Myohm grant.
- **Web:** React/React DOM MIT, Lucide ISC and other dependencies under their own terms. The dependency lockfile includes development packages under BlueOak, BSD, CC-BY and other licences. Retain notices for the actual distributed bundle. The previous audit of the web copy is not certification of a newer `lab` lockfile.
- **Mobile:** the `mobile/` clients use Apple system frameworks on iOS. On Android they use AndroidX/Jetpack Compose, Material Components, Room, Lifecycle, Navigation, DataStore, Dagger/Hilt, Kotlin standard library and kotlinx libraries (Apache-2.0) and Vico (Apache-2.0); JUnit, Hamcrest and Robolectric are test-only. See `mobile/THIRD_PARTY_NOTICES.md`. Platform SDK terms remain separate.
- **Python:** numerical, plotting and BLE libraries retain their licences.
- **Bench data:** `tools/bench/data` is licensed CC-BY-4.0 (`tools/bench/data/LICENSES/CC-BY-4.0.txt`). PyMuPDF in the editorial environment is AGPL/commercial and is not included or relicensed by this grant.
- **CAD:** see `docs/third-party-cad.csv`. KiCad standard libraries carry their exception; other manufacturers' assets require their own provenance. The maintainer confirmed on 2026-10-14 that permission for the imported CAD files was requested and approved; preserve applicable third-party terms and attribution. Exact source links and approval references remain traceability improvements, not an unconfirmed-permission blocker.

A release-specific transitive inventory and bundled notices must be finalized before binary publication. This index makes no claim that all vendor components are open source.
