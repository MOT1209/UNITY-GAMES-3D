# Android release build (KING FOOTBALL)

Status: the export preset is **filled in but no APK/AAB has been built on this machine** (no Android SDK,
no device). Everything below is the procedure, not a report of a successful build.

## Preset (`export_presets.cfg`, preset "Android")

| Field | Value | Note |
|---|---|---|
| `version/code` | 1 | raise by 1 for every Play Store upload |
| `version/name` | 0.3.0 | shown to players |
| `gradle_build/min_sdk` | 24 (Android 7.0) | only used when `gradle_build/use_gradle_build=true` |
| `gradle_build/target_sdk` | 35 | Google Play requires new apps/updates to target a recent API level (API 35 since 31 Aug 2025). **Check the current requirement in the Play Console before each release** and raise it if needed. |
| `launcher_icons/*` | `assets/icons/icon_192.png`, `icon_foreground_432.png`, `icon_background_432.png` | generated from `icon.svg` by `tools/build_icons.tscn` (adaptive: logo inside the 66 % safe zone, navy background) |
| `package/signed` | true | signing material comes from the environment, never from the repository |

Play Store uploads need an **AAB**: enable `gradle_build/use_gradle_build`, install the Android build template
(Project > Install Android Build Template) and set `gradle_build/export_format` to AAB.

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
