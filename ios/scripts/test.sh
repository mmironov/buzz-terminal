#!/bin/bash
# Run the unit tests. 35 tests across 6 suites; all should pass.
set -euo pipefail
source "$(dirname "$0")/_env.sh"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
  test "$@" 2>&1 | grep -E "✔|✘|Suite .*(passed|failed)|error:|TEST (SUCCEEDED|FAILED)" || true
