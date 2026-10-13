#!/bin/zsh
# Builds, signs, notarizes and publishes a Popoli release from main.
# Installed copies update themselves from the appcast.xml attached to the latest GitHub
# release (SUFeedURL in Info.plist), so nothing has to be committed after a release.
# One-time setup and the branch workflow: docs/releasing.md.
#
#   scripts/release.sh     releases the version in Info.plist (CFBundleShortVersionString)
#
# Release notes (optional): write them to dist/Popoli-<version>.md before running.
set -euo pipefail
cd "${0:A:h}/.."

VERSION=$(plutil -extract CFBundleShortVersionString raw Info.plist)
TAG="v$VERSION"
NOTARY_PROFILE="${NOTARY_PROFILE:-popoli-notary}"
DIST=dist
ZIP="$DIST/Popoli-$VERSION.zip"

# Releases come from main, exactly as it is on GitHub.
[[ $(git rev-parse --abbrev-ref HEAD) == main ]] || { echo "Releases are made from main: git switch main && git pull"; exit 1 }
[[ -z $(git status --porcelain) ]] || { echo "There are uncommitted changes. Commit or stash them first."; exit 1 }
git fetch -q origin main
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || { echo "Local main is not the same as origin/main. Run git pull."; exit 1 }
[[ -f updates/public-key.txt ]] || { echo "Missing updates/public-key.txt (see docs/releasing.md)."; exit 1 }
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

echo "▸ Writing appcast.xml"
# Start from the latest release's appcast so earlier versions stay listed; generate_appcast
# signs the new entry with the private key in your keychain.
rm -f $DIST/appcast.xml
gh release download --pattern appcast.xml --dir $DIST 2>/dev/null || true
vendor/Sparkle/bin/generate_appcast --download-url-prefix "https://github.com/kogungor/popoli/releases/download/$TAG/" \
  --embed-release-notes $DIST

echo "▸ Publishing $TAG"
NOTES=(--generate-notes)
[[ -f "$DIST/Popoli-$VERSION.md" ]] && NOTES=(--notes-file "$DIST/Popoli-$VERSION.md")
gh release create "$TAG" "$ZIP" "$DIST/appcast.xml" --target main --title "Popoli $VERSION" "${NOTES[@]}"

echo
echo "Released $TAG. Installed copies will offer it on their next update check."
