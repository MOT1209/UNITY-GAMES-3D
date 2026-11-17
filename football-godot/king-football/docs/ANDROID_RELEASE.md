# Android release build (KING FOOTBALL)

Status (2026-11-14): **debug and release APKs were built and signed headless on Linux** with
`tools/export_android.sh` (Godot 4.7.2 Android templates; apksigner / zipalign / adb from Ubuntu's packages;
OpenJDK 21). `aapt dump badging` on the release APK: package `dev.kingfootball.game`, versionName 0.3.0,
minSdk 24, targetSdk 36, arm64-v8a + armeabi-v7a, INTERNET / ACCESS_NETWORK_STATE / ACCESS_WIFI_STATE,
adaptive icons; `apksigner verify` passes (debug key and a throw-away test release key, both outside the
repository). Sizes: debug 72 MB, release 67 MB. **Not done: running it on a phone or emulator** (no device, no
emulator image here) — install with `adb install -r build/android/KINGFootball-release.apk` on a real phone.

Problems the real export found and that are fixed in the project:
* `textures/vram_compression/import_etc2_astc` was off — Godot refuses every Android export without it.
* `gradle_build/min_sdk` / `target_sdk` may only be set together with `use_gradle_build`. Round 3 (2026-11-15) sets
  them explicitly (min 24, target 36) and turns the Gradle build on; `tools/export_android.sh` installs the Android
  build template (`android/`, git-ignored) on first use. **The Gradle export itself was not re-run in this round**
  (no Android SDK in that environment) — run the script once on a machine with the SDK before the next release.
* No network permission: KING CONTROLLER could not open its server on a phone. INTERNET, ACCESS_NETWORK_STATE
  and ACCESS_WIFI_STATE are now requested.
* The project path contains "ß": apksigner (Java) needs a UTF-8 locale (`LC_ALL=C.UTF-8`), set by the script.

## Preset (`export_presets.cfg`, preset "Android")

| Field | Value | Note |
|---|---|---|
| `version/code` | 1 | raise by 1 for every Play Store upload |
| `version/name` | 0.3.0 | shown to players |
| `gradle_build/use_gradle_build` | true | required by Godot for the SDK fields below; template installed by `tools/export_android.sh` |
| `gradle_build/min_sdk` / `target_sdk` | 24 / 36 | Google Play requires target API 36 for new apps and updates since 31 Aug 2026 — **check the current requirement in the Play Console before each release**; checked by `release_readiness_validation`. |
| `permissions/*` | INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE | the KING CONTROLLER server |
| `launcher_icons/*` | `assets/icons/icon_192.png`, `icon_foreground_432.png`, `icon_background_432.png` | generated from `icon.svg` by `tools/build_icons.tscn` (adaptive: logo inside the 66 % safe zone, navy background) |
| `package/signed` | true | signing material comes from the environment, never from the repository |

Play Store uploads need an **AAB**: the Gradle build is already on; set `gradle_build/export_format` to AAB.

## Release keystore (do NOT commit it)

```bash
keytool -genkeypair -v -keystore king_football_release.keystore -alias kingfootball \
        -keyalg RSA -keysize 4096 -validity 10000
```

Keep the file and its passwords outside the repository (`*.keystore`, `*.jks`, `build/` and
`export_credentials.cfg` are in `.gitignore`). Losing the upload key means asking Google for a key reset.
Provide it to the export through Godot's environment variables (work for CI too):

```bash
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/secure/king_football_release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=kingfootball
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD='...'
godot --headless --path . --export-release "Android" build/android/KINGFootball.aab
```

Debug builds use the debug keystore configured in Editor Settings > Export > Android.

## Before uploading

1. `tests/run_all.sh --full` green.
2. Build, install on a mid-range phone, play a full match: target 60 FPS, never below 30 (Settings > Graphics:
   shadows "low" on phones), check the developer overlay (debug builds: F3).
3. Arabic, German and English screenshots on the device (RTL, digits, touch buttons).
