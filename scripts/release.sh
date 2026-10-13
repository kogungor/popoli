#!/bin/zsh
# Builds, signs, notarizes and publishes a Popoli release from main.
# Installed copies update themselves from the appcast.xml attached to the latest GitHub
# release (SUFeedURL in Info.plist), so nothing has to be committed after a release.
# One-time setup and the branch workflow: docs/releasing.md.
#
#   scripts/release.sh     releases the version in Info.plist (CFBundleShortVersionString)
#
# Release notes: the "## <version>" section of CHANGELOG.md, shown on GitHub and in the update window.
set -euo pipefail
cd "${0:A:h}/.."

VERSION=$(plutil -extract CFBundleShortVersionString raw Info.plist)
TAG="v$VERSION"
NOTARY_PROFILE="${NOTARY_PROFILE:-popoli-notary}"
DIST=dist
ZIP="$DIST/Popoli-$VERSION.zip"
# The disk image stays out of dist/, where generate_appcast would list it as a second update.
DMG="build/Popoli-$VERSION.dmg"

# Releases come from main, exactly as it is on GitHub.
[[ $(git rev-parse --abbrev-ref HEAD) == main ]] || { echo "Releases are made from main: git switch main && git pull"; exit 1 }
[[ -z $(git status --porcelain) ]] || { echo "There are uncommitted changes. Commit or stash them first."; exit 1 }
git fetch -q origin main
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || { echo "Local main is not the same as origin/main. Run git pull."; exit 1 }
[[ -f updates/public-key.txt ]] || { echo "Missing updates/public-key.txt (see docs/releasing.md)."; exit 1 }
HEADING=$(awk -v v="$VERSION" '$1 == "##" && $2 == v { print; exit }' CHANGELOG.md)
[[ -n $HEADING ]] || { echo "CHANGELOG.md has no \"## $VERSION\" section. Write the release notes there on dev first."; exit 1 }
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "$TAG is already released. Bump CFBundleShortVersionString on dev and merge it to main first."
  exit 1
fi

echo "▸ Building $VERSION for release"
RELEASE=1 ./build.sh
codesign --verify --deep --strict build/Popoli.app

echo "▸ Notarizing"
mkdir -p $DIST
# Only this version's archive may be in dist/: generate_appcast lists every archive it finds.
find $DIST -name 'Popoli-*.zip' -delete
ditto -c -k --keepParent build/Popoli.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple build/Popoli.app
rm -f "$ZIP"
ditto -c -k --keepParent build/Popoli.app "$ZIP"

# The notes next to the zip are embedded in the appcast, and the same file is the GitHub release text.
NOTES="$DIST/Popoli-$VERSION.md"
awk -v v="$VERSION" '
  $1 == "##" && $2 == v { found = 1; next }
  found && /^## / { exit }
  found && !started && /^[[:space:]]*$/ { next }
  found { started = 1; print }
' CHANGELOG.md > "$NOTES"

echo "▸ Writing appcast.xml"
# Start from the latest release's appcast so earlier versions stay listed; generate_appcast
# signs the new entry with the private key in your keychain.
rm -f $DIST/appcast.xml
gh release download --pattern appcast.xml --dir $DIST 2>/dev/null || true
vendor/Sparkle/bin/generate_appcast --download-url-prefix "https://github.com/kogungor/popoli/releases/download/$TAG/" \
  --embed-release-notes $DIST

# The zip is for Sparkle updates, the disk image for people downloading Popoli.
echo "▸ Making the disk image"
scripts/make-dmg.sh build/Popoli.app "$DMG"

echo "▸ Publishing $TAG"
gh release create "$TAG" "$DMG" "$ZIP" "$DIST/appcast.xml" --target main --title "Popoli ${HEADING#\#\# }" --notes-file "$NOTES"

echo
echo "Released $TAG. Installed copies will offer it on their next update check."
