# Mobile third-party notices

Myohm application sources are derived from the BioMess project; on 2026-10-22 the maintainer confirmed that this code, including the `com.volumhealth` packages, belongs to the project authors and is licensed under Apache-2.0. Existing headers and licence files are retained. Third-party components retain their respective licences; this notice does not relicense them.

- iOS uses Apple frameworks under the applicable platform terms, plus local BioMessAppFeature/BioMessCore packages. No Supabase or external Swift package is linked.
- Android retains the original AndroidX/Jetpack Compose, Material Components, Room, Lifecycle, Navigation, DataStore, Dagger/Hilt, Kotlin standard library, kotlinx.coroutines, kotlinx.datetime and serialization dependencies (Apache-2.0), and Vico 1.13.1 (Apache-2.0). Exact direct versions are in `android/gradle/libs.versions.toml` and module build files; Gradle resolves transitive versions.
- Build tools include Gradle (Apache-2.0), Android Gradle Plugin (Apache-2.0), Kotlin Gradle Plugin (Apache-2.0), and XcodeGen (MIT, external tool). Wrapper scripts retain upstream headers.
- Test dependencies include JUnit 4 (EPL-1.0), Hamcrest (BSD-3-Clause), Robolectric (MIT), and AndroidX test libraries (Apache-2.0); these test libraries are not application runtime dependencies.

The repository `LICENSES/Apache-2.0.txt` supplies the Apache licence. Preserve all embedded upstream notices when distributing artifacts. A complete release-specific transitive licence inventory remains a release packaging check. Supabase and Ktor dependencies have been removed.
