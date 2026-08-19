#!/bin/bash
# Archive, export and (optionally) upload a TestFlight build.
#
#     ./ios/scripts/release.sh              archive + export the .ipa
#     ./ios/scripts/release.sh --upload     …and send it to App Store Connect
#     ./ios/scripts/release.sh --unsigned   no signing at all, to check the archive
#
# Requires a paid Apple Developer Program membership and, for --upload, an App
# Store Connect API key. See docs/distribution.md.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

UPLOAD=no
UNSIGNED=no
for arg in "$@"; do
  case "$arg" in
    --upload) UPLOAD=yes ;;
    --unsigned) UNSIGNED=yes ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

ARCHIVE="$DERIVED/BuzzTerminal.xcarchive"
EXPORT_DIR="$DERIVED/export"

# Credentials are checked here, before anything is built. They used to be checked
# just before the export, which meant a missing key was discovered after a
# two-minute archive — the wrong end of the build for a typo in a path.
#
# An App Store Connect API key authenticates the upload without a password or an
# app-specific password. The key id and issuer id are identifiers; the .p8 is the
# credential, and belongs outside the repository.
if [ "$UPLOAD" = yes ]; then
  missing=()
  [ -n "${ASC_KEY_ID:-}" ]    || missing+=("ASC_KEY_ID       the 10-character key id, also in the .p8 filename")
  [ -n "${ASC_ISSUER_ID:-}" ] || missing+=("ASC_ISSUER_ID    the account-wide UUID above the key table")
  [ -n "${ASC_KEY_PATH:-}" ]  || missing+=("ASC_KEY_PATH     path to the AuthKey_*.p8 file")
  if [ ${#missing[@]} -gt 0 ]; then
    {
      echo
      echo "Cannot upload — missing credentials:"
      printf '    %s\n' "${missing[@]}"
      echo
      echo "App Store Connect → Users and Access → Integrations → App Store Connect API."
      echo "All three on one line, so the credential path is not left in your environment:"
      echo
      echo "    ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=uuid ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 ./ios/scripts/release.sh --upload"
      echo
      echo "Or drop --upload to just build the .ipa, and send it with Transporter."
      echo "See docs/distribution.md."
      echo
    } >&2
    exit 1
  fi
  if [ ! -f "$ASC_KEY_PATH" ]; then
    echo "No API key file at: $ASC_KEY_PATH" >&2
    echo "  Check the path — a leading ~ only expands if it is unquoted." >&2
    exit 1
  fi
fi

# The build number must increase with every upload or App Store Connect rejects
# the build. Deriving it from the commit count makes that automatic and
# reproducible: the same commit always produces the same number, and the next
# commit always produces a higher one. Nobody has to remember anything.
BUILD_NUMBER=$(git rev-list --count HEAD)
VERSION=$(grep -m1 'MARKETING_VERSION' "$PROJECT/project.pbxproj" | sed -E 's/.*= ([^;]+);.*/\1/')

echo "Version $VERSION, build $BUILD_NUMBER"

if [ "$UNSIGNED" = yes ]; then
  # Proves the archive step itself works — target, resources, asset catalogue,
  # Swift build for a real device — without needing a team or certificates. This
  # is what CI and a pre-membership dry run should use.
  echo "Archiving unsigned (no team, no certificates)…"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
    -archivePath "$ARCHIVE" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    archive
  echo
  echo "✔ Unsigned archive at $ARCHIVE"
  echo "  It cannot be installed or uploaded. Set DEVELOPMENT_TEAM and drop --unsigned for that."
  exit 0
fi

# The team can come from the environment or, more usefully, from the project —
# Xcode writes DEVELOPMENT_TEAM there as soon as you pick a team in Signing &
# Capabilities. Preferring the project means the normal case needs no environment
# variable at all, and the override still exists for a second team.
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  DEVELOPMENT_TEAM=$(grep -m1 'DEVELOPMENT_TEAM' "$PROJECT/project.pbxproj" 2>/dev/null | sed -E 's/.*= ([^;]+);.*/\1/' || true)
fi

if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  cat >&2 <<'MSG'

No DEVELOPMENT_TEAM, in the environment or in the project.

A device build has to be signed, and signing needs the 10-character Team ID from
developer.apple.com → Membership details.

Set it once in Xcode — target → Signing & Capabilities → Team — which writes it
into the project, or pass it per build:

    DEVELOPMENT_TEAM=XXXXXXXXXX ./ios/scripts/release.sh

To check the archive builds without any of this:
    ./ios/scripts/release.sh --unsigned

MSG
  exit 1
fi

# Braces are load-bearing here, not style. An unbraced $VAR immediately followed by
# a multibyte character — the ellipsis below — has those bytes swallowed into the
# variable name in a UTF-8 locale, so `set -u` kills the script with
# "DEVELOPMENT_TEAM…: unbound variable" even though the variable is set. It only
# works in the C locale, which is why it passed every automated run and failed in a
# normal Terminal. Brace any expansion followed by non-ASCII text.
echo "Archiving for device, team ${DEVELOPMENT_TEAM}…"
# -allowProvisioningUpdates lets Xcode create and download the provisioning
# profile rather than requiring one to exist first. It needs to be signed in to
# an account (Xcode → Settings → Accounts) or given an API key.
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -allowProvisioningUpdates \
  archive

OPTIONS="$DERIVED/ExportOptions.plist"
# Written here rather than committed, because it carries the team id.
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>$DEVELOPMENT_TEAM</string>
	<key>uploadSymbols</key>
	<true/>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST

# Two steps, two identities, on purpose.
#
# Signing happens first, authenticated by whoever is signed into Xcode. The API key
# is deliberately NOT passed to exportArchive: doing so makes xcodebuild sign *as
# the key*, and minting the "Apple Distribution" cloud certificate needs the key to
# hold the Admin role. An App Manager key — the right role for shipping builds —
# fails with "Cloud signing permission error / No signing certificate iOS
# Distribution found", which reads like a signing setup problem and is really a
# permissions one.
#
# So: export locally, then hand the finished .ipa to altool. Uploading is all the
# key is asked to do, which App Manager can.
echo "Exporting…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates

IPA="$EXPORT_DIR/BuzzTerminal.ipa"
[ -f "$IPA" ] || { echo "Export produced no .ipa at $IPA" >&2; exit 1; }

echo
if [ "$UPLOAD" != yes ]; then
  echo "✔ Exported to $EXPORT_DIR"
  echo "  Re-run with --upload to send it, or drag the .ipa into Transporter."
  exit 0
fi

echo "Uploading build ${BUILD_NUMBER}…"
# altool locates the key by id, searching a fixed set of directories rather than
# taking a path — API_PRIVATE_KEYS_DIR is how a key kept elsewhere is found.
API_PRIVATE_KEYS_DIR="$(cd "$(dirname "$ASC_KEY_PATH")" && pwd)" \
  xcrun altool --upload-app \
    --file "$IPA" \
    --type ios \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"

echo
echo "✔ Uploaded version $VERSION build ${BUILD_NUMBER}."
echo "  It appears in App Store Connect → TestFlight after processing (minutes, not instant)."
echo "  An external group's first build of a version waits on Beta App Review."
