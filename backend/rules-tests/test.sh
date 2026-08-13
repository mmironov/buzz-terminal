#!/bin/bash
# Run the security-rules tests against a throwaway Firestore emulator.
#
#     ./test.sh          (or: npm test)
#
# Nothing here touches the real swing-buzz database. The emulator starts empty,
# loads ../firestore.rules, runs the suite, and is torn down.
set -euo pipefail
cd "$(dirname "$0")"

# The emulator is a Java process. Two macOS wrinkles:
#   * /usr/bin/java always exists as a stub, even with no JDK installed — it just
#     prints "install Java" and exits non-zero. So test that java RUNS, not that
#     it is on PATH; `command -v java` is a trap here.
#   * Homebrew's openjdk is keg-only, deliberately not symlinked onto PATH,
#     because macOS ships those wrappers. So find it rather than asking everyone
#     to edit their shell profile.
java_works() { java -version >/dev/null 2>&1; }

if ! java_works; then
  for candidate in \
    "$(brew --prefix openjdk 2>/dev/null || true)/libexec/openjdk.jdk/Contents/Home" \
    "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home" \
    "/usr/local/opt/openjdk/libexec/openjdk.jdk/Contents/Home" \
    "$(/usr/libexec/java_home 2>/dev/null || true)"; do
    if [ -x "$candidate/bin/java" ]; then
      export JAVA_HOME="$candidate"
      export PATH="$JAVA_HOME/bin:$PATH"
      break
    fi
  done
fi

if ! command -v java >/dev/null 2>&1; then
  cat >&2 <<'MSG'

No Java runtime found, and the Firestore emulator is a Java process.

    brew install openjdk

The Homebrew formula needs no sudo and stays inside the Homebrew prefix. (The
`temurin` cask also works but installs into /Library and asks for your password.)

MSG
  exit 1
fi

if [ ! -d node_modules ]; then
  echo "installing test dependencies…"
  npm install --silent
fi

# firebase.json lives one level up, alongside the rules being tested.
cd ..
exec firebase emulators:exec --only firestore --project swing-buzz \
  'node --test rules-tests/*.test.mjs'
