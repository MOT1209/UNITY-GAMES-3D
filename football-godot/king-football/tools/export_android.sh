#!/usr/bin/env bash
# Builds the Android APKs headless (debug + release) into build/android/.
# Usage: tools/export_android.sh [--public] [path-to-godot]
#   --public  builds the public (Google Play) release with the "release_public" preset: the same game WITHOUT the real
#             club / player data pack (data/packs/real_2025, real names from Transfermarkt), which must not ship before a
#             legal review. The game then starts with the fictional world only.
# Needs: Godot 4.7.2 Android export templates installed, an Android SDK path (build-tools with apksigner
# and zipalign, platform-tools with adb) and a JDK in the Godot editor settings (export/android/*), the debug
# keystore in the editor settings, and for release the GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}
# environment variables (see docs/ANDROID_RELEASE.md). Never commit a keystore.
set -euo pipefail
PUBLIC=0
if [ "${1:-}" = "--public" ]; then PUBLIC=1; shift; fi
GODOT="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/.."
# The project path contains "ß": Java's apksigner needs a UTF-8 locale or it cannot find the APK to sign.
export LC_ALL=C.UTF-8 LANG=C.UTF-8
mkdir -p build/android
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
# The preset sets min/target SDK explicitly, which Godot only accepts with a Gradle build: install the
# Android build template into android/ (git-ignored) when it is missing.
if [ ! -f android/build/build.gradle ]; then
  "$GODOT" --headless --path . --install-android-build-template
fi
if [ "$PUBLIC" = "1" ]; then
  if [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
    echo "the public release needs GODOT_ANDROID_KEYSTORE_RELEASE_PATH (see docs/ANDROID_RELEASE.md)" >&2
    exit 1
  fi
  "$GODOT" --headless --path . --export-release "release_public" build/android/KINGFootball-public.apk
  ls -la build/android
  exit 0
fi
"$GODOT" --headless --path . --export-debug "Android" build/android/KINGFootball-debug.apk
if [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
  "$GODOT" --headless --path . --export-release "Android" build/android/KINGFootball-release.apk
else
  echo "release skipped: GODOT_ANDROID_KEYSTORE_RELEASE_PATH is not set"
fi
ls -la build/android
