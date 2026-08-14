#!/bin/bash
# Create the release signing key, once, and wire the build to it.
#
#     ./android/scripts/keystore.sh
#
# Exists because `keytool` is not on this Mac's PATH — there is no system JDK at
# all. Android Studio ships one, and _env.sh already knows where. Running keytool
# by hand gives "Unable to locate a Java Runtime", which is a PATH problem
# wearing the costume of a missing install.
#
# Writes android/swing-buzz-release.jks and android/keystore.properties, both
# gitignored. Refuses to touch either if it already exists: overwriting the
# keystore of an app that is already on phones is unrecoverable — see
# docs/distribution.md.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

KEYSTORE="swing-buzz-release.jks"
PROPERTIES="keystore.properties"
ALIAS="swing-buzz"

if [ -f "$KEYSTORE" ] || [ -f "$PROPERTIES" ]; then
  cat >&2 <<MSG

Refusing to overwrite an existing key.

  $( [ -f "$KEYSTORE" ]   && echo "android/$KEYSTORE exists" )
  $( [ -f "$PROPERTIES" ] && echo "android/$PROPERTIES exists" )

If the app has ever been installed from a build signed with that key, replacing
it means every phone must uninstall before it can take another update — Android
refuses an update signed by a different key, and there is no way to re-key an
installed app.

If you are certain it was never distributed, delete the file(s) and run again.

MSG
  exit 1
fi

if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/keytool" ]; then
  echo "No keytool. Install Android Studio, or set JAVA_HOME to a JDK." >&2
  exit 1
fi

cat <<'MSG'
Creating the release signing key.

This key identifies the app for the rest of its life. Back up both the .jks file
and this password somewhere that is not this laptop — losing them means every
staff phone has to uninstall before it can take another build.

MSG

# Read twice and compare, because a typo here surfaces much later as a signing
# failure with nothing to point at.
read -rsp "Password for the keystore: " SB_KEYSTORE_PASSWORD; echo
read -rsp "Again: " CONFIRM; echo
[ -n "$SB_KEYSTORE_PASSWORD" ] || { echo "Empty password." >&2; exit 1; }
[ "$SB_KEYSTORE_PASSWORD" = "$CONFIRM" ] || { echo "They do not match." >&2; exit 1; }
[ ${#SB_KEYSTORE_PASSWORD} -ge 6 ] || { echo "keytool requires at least 6 characters." >&2; exit 1; }
unset CONFIRM
export SB_KEYSTORE_PASSWORD

# `-storepass:env` rather than `-storepass`: an argument would be visible to
# anyone running `ps` while this executes.
#
# 10000 days is ~27 years. A key that expires mid-festival cannot sign an update,
# and the number costs nothing.
#
# The distinguished name is not a claim anyone verifies — this certificate is
# self-signed and only ever compared against itself — so it is filled in rather
# than prompted for.
"$JAVA_HOME/bin/keytool" -genkeypair -v \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass:env SB_KEYSTORE_PASSWORD \
  -keypass:env SB_KEYSTORE_PASSWORD \
  -dname "CN=Swing Buzz Staff Terminal, O=Swing Buzz Festival"

# One password for both, deliberately: a separate key password is a second thing
# to lose for a keystore that holds exactly one key.
umask 077
cat > "$PROPERTIES" <<PROPS
# Gitignored. Passwords in plain text — this file is the reason.
storeFile=$KEYSTORE
storePassword=$SB_KEYSTORE_PASSWORD
keyAlias=$ALIAS
keyPassword=$SB_KEYSTORE_PASSWORD
PROPS
chmod 600 "$PROPERTIES"

echo
echo "✔ android/$KEYSTORE and android/$PROPERTIES"
"$JAVA_HOME/bin/keytool" -list -keystore "$KEYSTORE" -storepass:env SB_KEYSTORE_PASSWORD \
  | sed -n '/Your keystore contains/,$p'

cat <<'MSG'

Both are gitignored. Back up the .jks and the password now, before you forget.

Next:
    ./android/scripts/release.sh                       build a signed APK
    ./android/scripts/release.sh --distribute --group staff
MSG
