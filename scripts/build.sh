#!/bin/bash
# Build the app for the simulator.
set -euo pipefail
source "$(dirname "$0")/_env.sh"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
  build "$@"
