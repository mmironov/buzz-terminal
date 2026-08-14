#!/bin/bash
# Run the unit tests. 67 tests — 60 in :domain, 7 in :app; all should pass.
#
# `:domain` is plain JVM — no emulator, no device, no Android SDK involved —
# which is the whole reason it is a separate module. `:app` has exactly one test
# class, for the Firestore field names, which are a security contract that
# `:domain` deliberately cannot see. It compiles the app module, so it is the
# slow half of this.
set -euo pipefail
source "$(dirname "$0")/_env.sh"
./gradlew :domain:test :app:testDebugUnitTest "$@"
