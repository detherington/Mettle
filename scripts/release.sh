#!/usr/bin/env bash
# scripts/release.sh <version>
#
# Builds a signed Release app, wraps it in a drag-to-Applications DMG,
# notarizes the DMG against the "Picsy" keychain profile, staples, and
# regenerates appcast.xml so Sparkle can ship it.
#
# Requires:
#   - xcodegen, xcodebuild, xcrun, hdiutil, codesign
#   - Notary keychain profile "Picsy" (xcrun notarytool store-credentials)
#   - Sparkle SPM tools under ~/Library/Developer/Xcode/DerivedData/Mettle-*/
#     (auto-located; override with SPARKLE_TOOLS env var if needed)

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <version>   e.g. $0 1.1"
    exit 1
fi

VERSION="$1"
BUILD_NUMBER="${2:-$VERSION}"
SCHEME="Mettle"
NOTARY_PROFILE="Picsy"
SIGN_ID="Developer ID Application: Darrell Etherington (8B29CDK832)"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="$ROOT/build"
RELEASES_DIR="$ROOT/releases"
APP_PATH="$BUILD_DIR/Build/Products/Release/Mettle.app"
DMG_PATH="$RELEASES_DIR/Mettle-$VERSION.dmg"

mkdir -p "$RELEASES_DIR"

echo "→ Regenerating project (xcodegen)"
xcodegen generate >/dev/null

echo "→ Building Release (v$VERSION, build $BUILD_NUMBER)"
rm -rf "$BUILD_DIR"
xcodebuild \
    -project Mettle.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    clean build | grep -E "error:|warning:|\*\* BUILD" || true

if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ Build did not produce $APP_PATH"
    exit 1
fi

echo "→ Re-signing Sparkle nested binaries with Developer ID"
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR=$(/bin/ls -d "$SPARKLE_FW/Versions"/[A-Z] 2>/dev/null | head -1)
if [[ -z "$SPARKLE_VERSION_DIR" ]]; then
    echo "✗ Could not locate Sparkle version directory under $SPARKLE_FW/Versions"
    exit 1
fi
for target in \
    "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc" \
    "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc" \
    "$SPARKLE_VERSION_DIR/Updater.app" \
    "$SPARKLE_VERSION_DIR/Autoupdate"
do
    [[ -e "$target" ]] || continue
    codesign --force --options=runtime --timestamp \
             --preserve-metadata=entitlements \
             --sign "$SIGN_ID" "$target"
done
codesign --force --options=runtime --timestamp --sign "$SIGN_ID" "$SPARKLE_FW"
codesign --force --options=runtime --timestamp --sign "$SIGN_ID" "$APP_PATH"

echo "→ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "→ Building DMG"
STAGING="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGING/Mettle.app"
ln -s /Applications "$STAGING/Applications"

# Purge stale DMGs for this version so generate_appcast sees only the new one.
rm -f "$DMG_PATH"
# Also purge any legacy .zip for this version.
rm -f "$RELEASES_DIR/Mettle-$VERSION.zip"

hdiutil create \
    -volname "Mettle $VERSION" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING"

echo "→ Signing DMG"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG_PATH"

echo "→ Submitting DMG to notary (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "→ Stapling ticket to DMG"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "✓ Done: $DMG_PATH"

# Default SPARKLE_TOOLS to the Sparkle SPM artifact. Check our local build dir
# first (in case xcodebuild ran with -derivedDataPath), then fall back to the
# user's DerivedData.
if [[ -z "${SPARKLE_TOOLS:-}" ]]; then
    for candidate in \
        "$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle" \
        ~/Library/Developer/Xcode/DerivedData/Mettle-*/SourcePackages/artifacts/sparkle/Sparkle
    do
        if [[ -x "$candidate/bin/generate_appcast" ]]; then
            SPARKLE_TOOLS="$candidate"
            break
        fi
    done
fi

if [[ -n "${SPARKLE_TOOLS:-}" && -x "$SPARKLE_TOOLS/bin/generate_appcast" ]]; then
    echo "→ Generating appcast.xml"
    "$SPARKLE_TOOLS/bin/generate_appcast" "$RELEASES_DIR" \
        --download-url-prefix "https://github.com/detherington/Mettle/releases/download/v$VERSION/" \
        --link "https://github.com/detherington/Mettle"
    cp "$RELEASES_DIR/appcast.xml" "$ROOT/appcast.xml"
    echo "✓ appcast.xml copied to repo root (commit + push it)"
else
    echo "ℹ SPARKLE_TOOLS not set; skipping appcast generation."
fi

echo
echo "Next steps:"
echo "  gh release upload v$VERSION \"$DMG_PATH\" --clobber   # or create fresh"
echo "  git add appcast.xml && git commit -m \"appcast: $VERSION\" && git push"
