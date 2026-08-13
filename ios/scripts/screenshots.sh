#!/bin/bash
# Capture every screen to ./screenshots/ using the debug launch overrides.
# Handy for eyeballing a design change across the whole app in one pass.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "$DESTINATION" -derivedDataPath "$DERIVED" build >/dev/null

UDID=$(xcrun simctl list devices available \
  | grep -m1 "$SIM_NAME (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/BuzzTerminal.app"

OUT="$PWD/screenshots"
mkdir -p "$OUT"

shoot() {
  local name=$1; shift
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" ${1+"$@"} >/dev/null
  sleep 1.8
  # `simctl io screenshot` rejects relative paths, hence $OUT being absolute.
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" 2>/dev/null
  echo "  $name"
}

shoot 01-signin
shoot 02-reception-home  -sbScreen reception
shoot 03-scan            -sbScreen reception -sbScanning
shoot 04-assign          -sbScreen assign
shoot 05-participant     -sbScreen participant
shoot 06-topup           -sbScreen topup
shoot 07-receipt         -sbScreen receipt
shoot 08-blocked         -sbScreen blocked
shoot 09-bar-menu        -sbScreen bar
shoot 10-cart            -sbScreen cart
shoot 11-payreview       -sbScreen payreview
shoot 12-payreview-short -sbScreen payreview-short
shoot 13-payreview-blocked -sbScreen payreview-blocked
shoot 14-payreview-unassigned -sbScreen payreview-unassigned
shoot 15-offline         -sbScreen reception -sbOffline
echo "→ ios/screenshots/"
