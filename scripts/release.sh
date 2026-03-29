#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────
APP_NAME="Repose"
SCHEME="Repose"
BUNDLE_ID="com.repose.app"
PROJECT="Repose.xcodeproj"

# Set these before running:
DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Fikri Karim}"
NOTARY_PROFILE="${NOTARY_PROFILE:-repose-notary}"
GITHUB_REPO="${GITHUB_REPO:-fikrikarim/repose}"
# ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
APPCAST_DIR="$ROOT_DIR/docs"

VERSION=$(grep 'MARKETING_VERSION' "$ROOT_DIR/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')

echo "==> Building $APP_NAME v$VERSION"
echo ""

# ─── Locate Sparkle tools ────────────────────────────────────────
SPARKLE_TOOLS="$(xcodebuild -project "$ROOT_DIR/$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | grep -m1 BUILD_DIR | awk '{print $3}')/../../SourcePackages/artifacts/sparkle/Sparkle/bin"
if [ ! -d "$SPARKLE_TOOLS" ]; then
    # Fallback: look in DerivedData
    SPARKLE_TOOLS="$(find ~/Library/Developer/Xcode/DerivedData -path "*/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)"
fi
if [ ! -d "$SPARKLE_TOOLS" ]; then
    echo "Error: Cannot find Sparkle tools. Build the project in Xcode first to resolve SPM packages."
    exit 1
fi
echo "    Sparkle tools: $SPARKLE_TOOLS"

# ─── Clean ───────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR" "$APPCAST_DIR"

# ─── Archive ─────────────────────────────────────────────────────
echo "==> Archiving..."
xcodebuild archive \
    -project "$ROOT_DIR/$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -quiet

echo "    Archive created at $ARCHIVE_PATH"

# ─── Export ──────────────────────────────────────────────────────
echo "==> Exporting..."

cat > "$BUILD_DIR/ExportOptions.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR" \
    -quiet

echo "    App exported to $APP_PATH"

# ─── Verify signing ─────────────────────────────────────────────
echo "==> Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH"
echo "    Signature valid"

# ─── Create DMG ──────────────────────────────────────────────────
echo "==> Creating DMG..."

DMG_TEMP="$BUILD_DIR/dmg_temp"
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    -quiet

rm -rf "$DMG_TEMP"
echo "    DMG created at $DMG_PATH"

# ─── Also create a zip (for Sparkle) ─────────────────────────────
echo "==> Creating zip..."
cd "$EXPORT_DIR"
ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"
cd "$ROOT_DIR"
echo "    Zip created at $ZIP_PATH"

# ─── Notarize ────────────────────────────────────────────────────
echo "==> Notarizing DMG..."
echo "    (this may take a few minutes)"

xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# Also notarize the ZIP for Sparkle updates
echo "==> Notarizing ZIP..."
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# ─── Sparkle: Generate appcast ───────────────────────────────────
echo "==> Generating Sparkle appcast..."

# Copy the signed+notarized ZIP to a staging folder for generate_appcast
SPARKLE_STAGING="$BUILD_DIR/sparkle_staging"
mkdir -p "$SPARKLE_STAGING"
cp "$ZIP_PATH" "$SPARKLE_STAGING/"

# generate_appcast reads the EdDSA private key from your Keychain automatically
# and creates/updates appcast.xml in the same folder
"$SPARKLE_TOOLS/generate_appcast" "$SPARKLE_STAGING" \
    --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/v$VERSION/"

# Copy the generated appcast to docs/ for GitHub Pages
cp "$SPARKLE_STAGING/appcast.xml" "$APPCAST_DIR/appcast.xml"
echo "    Appcast generated at $APPCAST_DIR/appcast.xml"

# ─── Commit appcast and push ──────────────────────────────────────
echo "==> Committing updated appcast..."
cd "$ROOT_DIR"
git add docs/appcast.xml
git commit -m "Update appcast for v$VERSION" || true
git push

# ─── Create GitHub Release ────────────────────────────────────────
echo "==> Creating GitHub Release v$VERSION..."
TAG="v$VERSION"

gh release create "$TAG" \
    --repo "$GITHUB_REPO" \
    --title "$APP_NAME $VERSION" \
    --generate-notes \
    "$DMG_PATH#$APP_NAME.dmg" \
    "$ZIP_PATH#$APP_NAME-$VERSION.zip"

echo ""
echo "==> Done!"
echo "    Release: https://github.com/$GITHUB_REPO/releases/tag/$TAG"
echo "    Appcast: https://fikrikarim.github.io/repose/appcast.xml"
