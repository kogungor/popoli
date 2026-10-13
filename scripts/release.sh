#!/bin/zsh
# Builds, signs, notarizes and publishes a Popoli release, then updates appcast.xml so
# installed copies update themselves (Sparkle). One-time setup: docs/releasing.md.
#
#   scripts/release.sh     releases the version in Info.plist (CFBundleShortVersionString)
#
# Release notes: put them in dist/Popoli-<version>.md before running (optional).
set -euo pipefail
cd "${0:A:h}/.."

VERSION=$(plutil -extract CFBundleShortVersionString raw Info.plist)
TAG="v$VERSION"
NOTARY_PROFILE="${NOTARY_PROFILE:-popoli-notary}"
DIST=dist
ZIP="$DIST/Popoli-$VERSION.zip"

[[ -f updates/public-key.txt ]] || { echo "Missing updates/public-key.txt — see docs/releasing.md"; exit 1 }
gh release view "$TAG" >/dev/null 2>&1 && { echo "$TAG is already released. Bump the version in Info.plist."; exit 1 }

echo "▸ Building $VERSION for release"
RELEASE=1 ./build.sh
codesign --verify --deep --strict build/Popoli.app

echo "▸ Notarizing"
mkdir -p $DIST
rm -f "$ZIP"
ditto -c -k --keepParent build/Popoli.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple build/Popoli.app
rm -f "$ZIP"
ditto -c -k --keepParent build/Popoli.app "$ZIP"

echo "▸ Updating appcast.xml"
# generate_appcast signs the update with the private key in your keychain and keeps the
# entries already in the appcast.
[[ -f appcast.xml ]] && cp appcast.xml $DIST/appcast.xml
vendor/Sparkle/bin/generate_appcast --download-url-prefix "https://github.com/kogungor/popoli/releases/download/$TAG/" \
  --embed-release-notes $DIST
cp $DIST/appcast.xml appcast.xml

echo "▸ Publishing $TAG on GitHub"
NOTES=(--generate-notes)
[[ -f "$DIST/Popoli-$VERSION.md" ]] && NOTES=(--notes-file "$DIST/Popoli-$VERSION.md")
gh release create "$TAG" "$ZIP" --title "Popoli $VERSION" "${NOTES[@]}"

echo
echo "Done. Commit and push appcast.xml so installed copies see the update:"
echo "  git add appcast.xml && git commit -m \"Release $VERSION\" && git push"
