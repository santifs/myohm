# Myohm mobile apps — 0.4.0

These clients are derived directly from the original BioMess iOS and Android apps, including discovery, acquisition, processing, measurement flows, charts, participants, history and export. They replace the independently rewritten Myohm 0.1/0.2 clients. The original BioMess repository is unchanged.

Changes to the copied apps are limited to Myohm installation identity/branding, removal of football-specific choices, and local operation without login or Supabase. iOS saves through the original SwiftData/local history services; Android retains the original Room database and uses a stable local owner identifier. Cloud status indicators are replaced with local-storage indicators. Device-buffer downloads are retained: these are BLE transfers, not cloud synchronization.

The original internal package/class names remain to minimize changes to working code. The original BLE and processing sources are byte-identical to the BioMess apps. Build/test success does not establish a successful physical measurement with this release. The applications used for historical research must not be described as this newly adapted release.

## iOS

Open `ios/Myohm.xcodeproj`; select your signing team and a physical iPhone. Bundle ID `com.myohm.mobile`, version 0.4.0 (5), iOS 17+. The project is generated from `ios/project.yml` with XcodeGen. Local packages BioMessAppFeature and BioMessCore provide the original implementation; no external Swift package is required.

On the maintainer's Mac, **never launch Simulator**. Build with at most two jobs and test on the connected iPhone.

```sh
xcodebuild -project ios/Myohm.xcodeproj -scheme Myohm -destination 'generic/platform=iOS' -jobs 2 build
```

## Android

Application ID `com.myohm.app`, version 0.4.0 (5). Original Compose/Hilt/Room/Vico architecture and core modules retained. Configure the Android SDK and JDK for Gradle. No INTERNET permission or Supabase/Ktor dependency remains.

```sh
cd android
./gradlew --max-workers=2 :app:assembleDebug :core-ble:testDebugUnitTest :core-processing:testDebugUnitTest
```

## Storage and validation

Update in place; do not uninstall to update. Uninstallation removes local records. Export through the original system sharing flows. The app has no cloud backend; users may explicitly share/export to their chosen destination.

The prior Myohm 0.1/0.2 JSON storage format is not automatically imported into the restored SwiftData/Room history. Updating preserves those app-private files, but they are not displayed in the restored history. The previous implementation is archived locally in the ignored `.previous-implementation/2026-10-15` directory for recovery.

Release acceptance requires a real measurement on each supported phone, then checking the displayed curves, saved history after relaunch and exported point count against the acquisition. Do not initiate participant measurements automatically. Android APK is a development/debug build, not a store release.

Source licence: Apache-2.0; third-party code retains its own licences. See `THIRD_PARTY_NOTICES.md`.

## Laboratory mode (0.4.0)

Measure without creating an athlete or completing questionnaires. On iOS choose **Medir → Laboratorio**; on Android open the **Laboratorio** tab. Configure the sweep, measure, then open the saved capture to view charts and export. Captures save automatically on the device. iOS laboratory captures are also accessible from History. Existing athlete protocols remain available.
