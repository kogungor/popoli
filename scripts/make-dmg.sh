#!/bin/zsh
# Packs a notarized Popoli.app into a disk image with an Applications link, then signs,
# notarizes and staples the image. scripts/release.sh runs it for every release.
#
#   scripts/make-dmg.sh <Popoli.app> <output.dmg>
set -euo pipefail

APP="${1:?usage: scripts/make-dmg.sh <Popoli.app> <output.dmg>}"
DMG="${2:?usage: scripts/make-dmg.sh <Popoli.app> <output.dmg>}"
NOTARY_PROFILE="${NOTARY_PROFILE:-popoli-notary}"

# The image is signed with the same Developer ID as the app.
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' | head -1)
[[ -n $IDENTITY ]] || { echo "$APP is not signed with a Developer ID."; exit 1 }

STAGE=$(mktemp -d)
trap 'rm -rf "${STAGE:?}"' EXIT
ditto "$APP" "$STAGE/Popoli.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname Popoli -srcfolder "$STAGE" -format ULMO "$DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
