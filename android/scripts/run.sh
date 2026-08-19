#!/bin/bash
# Build, install and launch on a device or emulator.
#
#   ./scripts/run.sh                  the BuzzPhone emulator, booting it if needed
#   ./scripts/run.sh -s <serial>      a specific device (see `adb devices`)
#
# The iOS twin is ios/scripts/run.sh. Launch flags (-sbScreen, -sbBackend …)
# arrive here as `am start` extras once the launch overrides land.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"
AVD="${AVD:-BuzzPhone}"
APP_ID="fest.swingbuzz.terminal"
ACTIVITY="$APP_ID/.MainActivity"

# Boot the emulator only if nothing is attached already — plugging in a real
# phone and running this should use the phone.
if [ -z "$("$ADB" devices | sed '1d' | grep -w device || true)" ]; then
  # Braced deliberately: an unbraced expansion followed by a multibyte character
  # takes those bytes into the variable name in a UTF-8 locale, and `set -u` then
  # fails on a variable that is set. See ios/scripts/release.sh.
  echo "No device attached; booting ${AVD}…"
  "$EMULATOR" -avd "$AVD" -no-boot-anim > /dev/null 2>&1 &
fi

"$ADB" wait-for-device
# `adb wait-for-device` returns as soon as adbd answers, which is long before
# the launcher exists. This is the wait that actually matters.
until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  sleep 2
done

./gradlew :app:installDebug "$@"
"$ADB" shell am start -n "$ACTIVITY"
