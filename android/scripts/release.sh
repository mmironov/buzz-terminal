#!/bin/bash
# Build a signed release APK and, optionally, send it to Firebase App Distribution.
#
#     ./android/scripts/release.sh                          build the signed APK
#     ./android/scripts/release.sh --distribute             …and upload it to testers
#     ./android/scripts/release.sh --distribute --group staff
#     ./android/scripts/release.sh --distribute --testers a@x.fest,b@x.fest
#     ./android/scripts/release.sh --unsigned               compile only, no keystore
#
# Signing needs android/keystore.properties; distribution needs `firebase login`.
# Both are covered in docs/distribution.md.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

DISTRIBUTE=no
UNSIGNED=no
GROUPS=""
TESTERS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --distribute) DISTRIBUTE=yes ;;
    --unsigned) UNSIGNED=yes ;;
    --group) GROUPS="${2:?--group needs a name}"; shift ;;
    --testers) TESTERS="${2:?--testers needs a comma-separated list}"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

KEYSTORE_PROPERTIES="keystore.properties"
APK_DIR="app/build/outputs/apk/release"

# versionCode comes from the commit count (see app/build.gradle.kts), so it is
# worth printing: it is the number a device compares against what it already has.
VERSION_CODE=$(git rev-list --count HEAD)
echo "Version code $VERSION_CODE"

if [ "$UNSIGNED" = yes ]; then
  # Proves the release variant compiles — R8 off, resources, the Firebase wiring —
  # without a keystore. This is what CI and a fresh clone should use.
  echo "Building unsigned…"
  ./gradlew :app:assembleRelease
  echo
  echo "✔ Unsigned APK at $APK_DIR/app-release-unsigned.apk"
  echo "  Android will refuse to install it. Add a keystore and drop --unsigned."
  exit 0
fi

if [ ! -f "$KEYSTORE_PROPERTIES" ]; then
  cat >&2 <<'MSG'

No android/keystore.properties, so there is nothing to sign with.

A release APK has to be signed or no device will install it, and the key must be
the same one every time: Android refuses an update signed by a different key, and
there is no way to re-key an installed app. Create one, once:

    keytool -genkeypair -v \
      -keystore android/swing-buzz-release.jks \
      -alias swing-buzz -keyalg RSA -keysize 4096 -validity 10000

then write android/keystore.properties (gitignored):

    storeFile=swing-buzz-release.jks
    storePassword=…
    keyAlias=swing-buzz
    keyPassword=…

Back up the .jks and its passwords somewhere that is not this laptop. Losing them
means every staff phone has to uninstall before it can take another build.

To check the release variant compiles without any of this:
    ./android/scripts/release.sh --unsigned

MSG
  exit 1
fi

echo "Building signed…"
./gradlew :app:assembleRelease

APK=$(ls "$APK_DIR"/*.apk 2>/dev/null | grep -v unsigned | head -1 || true)
if [ -z "$APK" ]; then
  echo "No signed APK in $APK_DIR — the keystore was present but signing produced nothing." >&2
  exit 1
fi

# Trust nothing about the filename: an APK called app-release.apk is not
# necessarily signed, and an unsigned one fails on the device rather than here,
# by which point it is somebody else's afternoon.
if ! "$JAVA_HOME/bin/jarsigner" -verify "$APK" >/dev/null 2>&1; then
  echo "✗ $APK is not signed. Check android/keystore.properties." >&2
  exit 1
fi

echo
echo "✔ Signed APK at $APK"

if [ "$DISTRIBUTE" != yes ]; then
  echo "  Re-run with --distribute to send it, or install it directly:"
  echo "      adb install -r $APK"
  exit 0
fi

# The app id lives in google-services.json, which is already required for a
# release build to run at all — so there is nothing extra to configure and no
# second place for it to drift out of date.
APP_ID=$(python3 -c "
import json
with open('app/google-services.json') as f:
    data = json.load(f)
for client in data['client']:
    if client['client_info']['android_client_info']['package_name'] == 'fest.swingbuzz.terminal':
        print(client['client_info']['mobilesdk_app_id'])
        break
")
[ -n "$APP_ID" ] || { echo "No app id for fest.swingbuzz.terminal in google-services.json" >&2; exit 1; }

NOTES="$(git log -1 --pretty format:'%s')"$'\n\n'"$(git rev-parse --short HEAD) · version code $VERSION_CODE"

DISTRIBUTE_ARGS=(appdistribution:distribute "$APK" --app "$APP_ID" --release-notes "$NOTES")
[ -n "$GROUPS" ] && DISTRIBUTE_ARGS+=(--groups "$GROUPS")
[ -n "$TESTERS" ] && DISTRIBUTE_ARGS+=(--testers "$TESTERS")

if [ -z "$GROUPS" ] && [ -z "$TESTERS" ]; then
  # Uploading with no audience is legal and does nothing visible — the build sits
  # in the console until somebody assigns it. Say so rather than printing a tick.
  echo "  No --group or --testers: uploading only. Assign it in the console afterwards."
fi

echo "Uploading to Firebase App Distribution…"
firebase "${DISTRIBUTE_ARGS[@]}"

echo
echo "✔ Uploaded version code $VERSION_CODE."
echo "  Testers get an email; the link installs the APK directly."
