#!/bin/bash
# Run the domain unit tests. 36 tests across 5 suites; all should pass.
#
# These are plain JVM tests — no emulator, no device, no Android SDK involved —
# which is the whole reason `:domain` is a separate module.
set -euo pipefail
source "$(dirname "$0")/_env.sh"
./gradlew :domain:test "$@"
