#!/usr/bin/env bash
# Builds the Android APKs headless (debug + release) into build/android/.
# Usage: tools/export_android.sh [path-to-godot]
# Needs: Godot 4.7.2 Android export templates installed, an Android SDK path (build-tools with apksigner
# and zipalign, platform-tools with adb) and a JDK in the Godot editor settings (export/android/*), the debug
# keystore in the editor settings, and for release the GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}
# environment variables (see docs/ANDROID_RELEASE.md). Never commit a keystore.
set -euo pipefail
GODOT="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/.."
# The project path contains "ß": Java's apksigner needs a UTF-8 locale or it cannot find the APK to sign.
export LC_ALL=C.UTF-8 LANG=C.UTF-8
mkdir -p build/android
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT" --headless --path . --export-debug "Android" build/android/KINGFootball-debug.apk
if [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
  "$GODOT" --headless --path . --export-release "Android" build/android/KINGFootball-release.apk
else
  echo "release skipped: GODOT_ANDROID_KEYSTORE_RELEASE_PATH is not set"
fi
ls -la build/android
