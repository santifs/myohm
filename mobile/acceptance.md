# Physical acceptance before a mobile release

Record app commit, OS/phone model, board identifier and firmware commit. Run independently on iOS and Android, starting with a known passive bench load; this checklist does not authorize measurements on people or replace electrical safety validation.

1. Install beside the original experimental app. Confirm both remain installed and have independent storage.
2. Deny Bluetooth permission, retry, then grant it. With Bluetooth off, show a useful error. Scan the current name-only `Messi-` firmware, connect, and verify AF00 discovery and notification subscription.
3. Measure a known resistor using 4–198 kHz, 48 points, 1 repetition. Confirm exactly 48 points and plausible magnitude/phase. Export JSON and CSV and compare every value with the received BLE payload.
4. Repeat with 2 points × 1 repetition, 48 × 5, and 100 × 10. Confirm correct repetition indexing, byte count and retained raw values. Configuration readback must match firmware-effective values. Verify acquisition duration stays within the 120-second client timeout; otherwise adjust timeout from measured timing before release.
5. Reject invalid settings before a write. Interrupt a sweep (disconnect, move out of range, background the app). No partial record may appear. Reconnect and obtain a fresh complete sweep without contamination from a previous stream.
6. Terminate and reopen the app: saved records and exports must match. Rotate Android during configuration and during the export picker. Verify deletion confirmation and that cancelling deletion retains the record.
7. Test local storage/export failure (full storage or unwritable export destination). The app must show the failure, retain the completed sweep for retry/export and never silently label it saved.
8. In airplane mode with Bluetooth enabled, repeat acquisition and open history. Verify no login or network is needed. The OS export picker may offer cloud providers; choosing one is an explicit action outside the app's local store.
9. Confirm foreground-only acquisition and manual export are clearly understood. No automatic acquisition, participant database, cloud sync or fatigue score is promised.

Keep exported bench fixtures and a short signed test record in the release evidence. No participant data belongs in this public repository. Simulator/JVM tests cover decoding and local logic, not radio interoperability.
