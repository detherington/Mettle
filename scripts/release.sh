#!/usr/bin/env bash
# scripts/release.sh <version>
#
# Builds a signed Release build, notarizes it against the "PIcsy" keychain
# profile, staples, and zips the result into releases/Mettle-<version>.zip.
# Then (optionally) regenerates appcast.xml if the Sparkle tools are present.
#
# Requires:
#   - xcodegen, xcodebuild, ditto, xcrun, zip
#   - Notary keychain profile named "PIcsy" (xcrun notarytool store-credentials)
#   - Sparkle tools at $SPARKLE_TOOLS (contains bin/generate_appcast). If unset,
#     this script skips appcast generation and you can run it manually.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <version>   e.g. $0 1.1"
    exit 1
fi

VERSION="$1"
BUILD_NUMBER="${2:-$VERSION}"
SCHEME="Mettle"
NOTARY_PROFILE="PIcsy"
BUNDLE_ID="com.darrelletherington.Mettle"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="$ROOT/build"
RELEASES_DIR="$ROOT/releases"
APP_PATH="$BUILD_DIR/Build/Products/Release/Mettle.app"
ZIP_PATH="$RELEASES_DIR/Mettle-$VERSION.zip"

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

echo "→ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "→ Zipping for notarization"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "→ Submitting to notary (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "→ Stapling ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "→ Re-zipping stapled app"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "✓ Done: $ZIP_PATH"

# Default SPARKLE_TOOLS to the Sparkle SPM artifact inside DerivedData if present.
if [[ -z "${SPARKLE_TOOLS:-}" ]]; then
    CANDIDATE=$(/bin/ls -d ~/Library/Developer/Xcode/DerivedData/Mettle-*/SourcePackages/artifacts/sparkle/Sparkle 2>/dev/null | head -1)
    if [[ -n "$CANDIDATE" ]]; then
        SPARKLE_TOOLS="$CANDIDATE"
    fi
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
    echo "  Set SPARKLE_TOOLS to the Sparkle-X.Y.Z extracted directory to enable."
fi

echo
echo "Next steps:"
echo "  gh release create v$VERSION \"$ZIP_PATH\" --title \"$VERSION\" --notes \"...\""
echo "  git add appcast.xml && git commit -m \"appcast: $VERSION\" && git push"
