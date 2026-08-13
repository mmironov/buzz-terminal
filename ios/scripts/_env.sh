#!/bin/bash
# Shared setup. Sourced by the other scripts.
#
# `xcode-select` on this Mac points at the Command Line Tools rather than Xcode,
# which makes xcodebuild refuse to run. Setting DEVELOPER_DIR overrides that for
# the current process without needing sudo. Once you have run
#   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# this becomes a harmless no-op.
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

PROJECT="BuzzTerminal.xcodeproj"
SCHEME="BuzzTerminal"
BUNDLE_ID="fest.swingbuzz.BuzzTerminal"
SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
DESTINATION="platform=iOS Simulator,name=$SIM_NAME"
DERIVED="${DERIVED:-build/DerivedData}"

cd "$(dirname "$0")/.."
