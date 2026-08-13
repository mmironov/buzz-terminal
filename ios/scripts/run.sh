#!/bin/bash
# Build, install and launch on the simulator.
#
# Pass debug launch overrides straight through, e.g.
#   ./scripts/run.sh -sbScreen participant
#   ./scripts/run.sh -sbScreen bar -sbOffline
# See BuzzTerminal/App/LaunchOverrides.swift for the full list.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
  build >/dev/null

UDID=$(xcrun simctl list devices available \
  | grep -m1 "$SIM_NAME (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [ -z "$UDID" ]; then echo "No simulator named '$SIM_NAME'" >&2; exit 1; fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator
xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/BuzzTerminal.app"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@"
