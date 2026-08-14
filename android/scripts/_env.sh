#!/bin/bash
# Shared setup. Sourced by the other scripts.
#
# There is no JDK on this Mac's PATH — `java -version` fails outright. Android
# Studio ships its own (JetBrains Runtime 21), which is the one Studio itself
# builds with, so pointing JAVA_HOME at it means the command line and the IDE
# agree. Set JAVA_HOME yourself and this leaves it alone.
if [ -z "${JAVA_HOME:-}" ]; then
  STUDIO_JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  if [ -d "$STUDIO_JBR" ]; then
    export JAVA_HOME="$STUDIO_JBR"
  fi
fi

# The SDK is where Studio puts it; local.properties is not committed, so this is
# what makes a fresh clone build without opening the IDE first.
if [ -z "${ANDROID_HOME:-}" ] && [ -d "$HOME/Library/Android/sdk" ]; then
  export ANDROID_HOME="$HOME/Library/Android/sdk"
fi

cd "$(dirname "$0")/.."
