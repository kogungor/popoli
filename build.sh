#!/bin/zsh
# Builds build/Popoli.app with swiftc (no Xcode project needed).
#   ./build.sh          build
#   ./build.sh run      build and launch
#   ./build.sh install  build, copy to ~/Applications and launch
# RELEASE=1 signs for distribution (Developer ID, hardened runtime); see scripts/release.sh.
set -euo pipefail
cd "${0:A:h}"

APP=build/Popoli.app
APPEX="$APP/Contents/PlugIns/PopoliFinder.appex"
RELEASE="${RELEASE:-0}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# macOS ties the Accessibility permission to the signing certificate (ad-hoc signatures change
# with every build). Development builds therefore use the same Developer ID as releases when
# there is one, so a build and an installed release share one permission; otherwise the first
# Apple Development identity, so the permission at least survives rebuilds.
# POPOLI_SIGN_IDENTITY overrides either.
DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')
if [[ $RELEASE == 1 ]]; then
  DEFAULT_IDENTITY=$DEVELOPER_ID
  SIGN_OPTIONS=(--options runtime --timestamp)
else
  DEFAULT_IDENTITY=${DEVELOPER_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}
  SIGN_OPTIONS=()
fi
IDENTITY="${POPOLI_SIGN_IDENTITY:-$DEFAULT_IDENTITY}"
sign() { codesign --force --sign "${IDENTITY:--}" "${SIGN_OPTIONS[@]}" "$@" >/dev/null; }

# Sparkle (automatic updates), downloaded once and checked against its known checksum.
SPARKLE_VERSION=2.10.0
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
SPARKLE=vendor/Sparkle
if [[ ! -d $SPARKLE/Sparkle.framework ]]; then
  echo "Downloading Sparkle $SPARKLE_VERSION…"
  mkdir -p vendor/download
  curl -fsSL -o vendor/download/Sparkle.tar.xz \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "$SPARKLE_SHA256  vendor/download/Sparkle.tar.xz" | shasum -a 256 -c - >/dev/null
  rm -rf $SPARKLE && mkdir -p $SPARKLE && tar -xJf vendor/download/Sparkle.tar.xz -C $SPARKLE
fi

# The app is updated in place instead of being deleted, so the Finder extension inside
# it survives: Finder does not reload a replaced extension until Finder restarts.
swiftc -O -parse-as-library -swift-version 5 \
  -target arm64-apple-macos26.0 \
  -module-name Popoli \
  -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  Sources/*.swift \
  -o build/Popoli.bin
mv build/Popoli.bin "$APP/Contents/MacOS/Popoli"
cp Info.plist "$APP/Contents/Info.plist"
rm -rf "$APP/Contents/Resources/Extensions"
cp -R Extensions "$APP/Contents/Resources/Extensions"
# A new build number every time, so macOS prefers this build over older copies.
plutil -replace CFBundleVersion -string "$(date +%s)" "$APP/Contents/Info.plist"
# The public half of the update signing key (see scripts/release.sh); without it the
# build has no updater.
if [[ -f updates/public-key.txt ]]; then
  plutil -replace SUPublicEDKey -string "$(tr -d '[:space:]' < updates/public-key.txt)" "$APP/Contents/Info.plist"
fi

# App icon, made from Assets/popoli.png whenever the logo changes.
ICNS=build/AppIcon.icns
if [[ ! -f $ICNS || Assets/popoli.png -nt $ICNS || Assets/make-icon.swift -nt $ICNS ]]; then
  rm -rf build/AppIcon.iconset
  swift Assets/make-icon.swift Assets/popoli.png build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o $ICNS
fi
cp $ICNS "$APP/Contents/Resources/AppIcon.icns"

# Sparkle is copied and signed (inside out) only when it or the signing setup changes.
SPARKLE_STAMP=build/.sparkle-stamp
SPARKLE_HASH="$SPARKLE_VERSION|$IDENTITY|$RELEASE"
if [[ ! -d "$APP/Contents/Frameworks/Sparkle.framework" || "$(cat $SPARKLE_STAMP 2>/dev/null)" != "$SPARKLE_HASH" ]]; then
  rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
  ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
  FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  sign "$FW/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
  sign "$FW/Autoupdate"
  sign "$FW/Updater.app"
  sign "$APP/Contents/Frameworks/Sparkle.framework"
  echo "$SPARKLE_HASH" > $SPARKLE_STAMP
fi

# Finder Sync extension (right-click menu): rebuilt only when its own files or the signing
# setup change.
FINDER_STAMP=build/.finder-extension-stamp
APP_VERSION=$(plutil -extract CFBundleShortVersionString raw Info.plist)
FINDER_HASH="$(cat FinderExtension/* | shasum | cut -c1-40)|$IDENTITY|$RELEASE|$APP_VERSION"
FINDER_CHANGED=0
# Stamps written by older versions of this script held only the hash.
if [[ $RELEASE == 0 && "$(cat "$FINDER_STAMP" 2>/dev/null)" == "${FINDER_HASH%%|*}" ]]; then
  echo "$FINDER_HASH" > "$FINDER_STAMP"
fi
if [[ ! -x "$APPEX/Contents/MacOS/PopoliFinder" || "$(cat "$FINDER_STAMP" 2>/dev/null)" != "$FINDER_HASH" ]]; then
  rm -rf "$APPEX"
  mkdir -p "$APPEX/Contents/MacOS"
  swiftc -O -parse-as-library -swift-version 5 -application-extension \
    -target arm64-apple-macos26.0 \
    -module-name PopoliFinder \
    FinderExtension/*.swift \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$APPEX/Contents/MacOS/PopoliFinder"
  cp FinderExtension/Info.plist "$APPEX/Contents/Info.plist"
  # The extension carries the app's version.
  plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APPEX/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$(date +%s)" "$APPEX/Contents/Info.plist"
  # The extension must be sandboxed.
  sign --entitlements FinderExtension/FinderMenu.entitlements "$APPEX"
  echo "$FINDER_HASH" > "$FINDER_STAMP"
  FINDER_CHANGED=1
fi

# Signing the app does not re-sign what is inside it (Sparkle, the extension).
sign --entitlements Popoli.entitlements "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc}$([[ $RELEASE == 1 ]] && echo ', release'))"

# Quits a running Popoli and waits until it is gone; opening the app while the old
# process is still exiting makes `open` fail with error -600.
quit_running() {
  pkill -x Popoli 2>/dev/null || return 0
  for _ in {1..50}; do
    pgrep -x Popoli >/dev/null || return 0
    sleep 0.1
  done
  pkill -9 -x Popoli 2>/dev/null || true
}

# After the extension itself changed, it has to be registered again and Finder restarted.
finder_extension_changed() {
  [[ $FINDER_CHANGED == 1 ]] || return 0
  pluginkit -a "${1:A}/Contents/PlugIns/PopoliFinder.appex" 2>/dev/null || true
  echo "The Finder extension changed. Restart Finder once to load it:  killall Finder"
}

case "${1:-}" in
  run)
    quit_running
    finder_extension_changed "$APP"
    open "$APP"
    ;;
  install)
    quit_running
    mkdir -p ~/Applications
    rm -rf ~/Applications/Popoli.app
    cp -R "$APP" ~/Applications/Popoli.app
    FINDER_CHANGED=1
    finder_extension_changed ~/Applications/Popoli.app
    open ~/Applications/Popoli.app
    echo "Installed to ~/Applications/Popoli.app"
    ;;
esac
