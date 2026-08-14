#!/bin/bash
# Compile everything, without installing or running anything.
set -euo pipefail
source "$(dirname "$0")/_env.sh"
./gradlew :app:assembleDebug "$@"
