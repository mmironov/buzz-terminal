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

echo "Archiving for device, team $DEVELOPMENT_TEAM…"
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
	<string>$([ "$UPLOAD" = yes ] && echo upload || echo export)</string>
</dict>
</plist>
PLIST

echo "Exporting (destination: $([ "$UPLOAD" = yes ] && echo upload || echo export))…"
EXPORT_ARGS=(-exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" -exportPath "$EXPORT_DIR" -allowProvisioningUpdates)

if [ "$UPLOAD" = yes ]; then
  # An App Store Connect API key authenticates the upload without a password or
  # an app-specific password. The .p8 is a credential: keep it outside the repo,
  # and note that the key id and issuer id are not secret but the file is.
  : "${ASC_KEY_ID:?Set ASC_KEY_ID — see docs/distribution.md}"
  : "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID — see docs/distribution.md}"
  : "${ASC_KEY_PATH:?Set ASC_KEY_PATH to the AuthKey_*.p8 file — see docs/distribution.md}"
  [ -f "$ASC_KEY_PATH" ] || { echo "No API key at $ASC_KEY_PATH" >&2; exit 1; }
  EXPORT_ARGS+=(
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
    -authenticationKeyPath "$ASC_KEY_PATH"
  )
fi

xcodebuild "${EXPORT_ARGS[@]}"

echo
if [ "$UPLOAD" = yes ]; then
  echo "✔ Uploaded version $VERSION build $BUILD_NUMBER."
  echo "  It appears in App Store Connect → TestFlight after processing (minutes, not instant)."
  echo "  An external group's first build of a version waits on Beta App Review."
else
  echo "✔ Exported to $EXPORT_DIR"
  echo "  Re-run with --upload to send it, or drag the .ipa into Transporter."
fi
