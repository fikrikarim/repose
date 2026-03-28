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
# ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

VERSION=$(defaults read "$ROOT_DIR/Repose/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")

echo "==> Building $APP_NAME v$VERSION"
echo ""

# ─── Clean ───────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

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

# ─── Also create a zip (for Sparkle / GitHub) ────────────────────
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

echo ""
echo "==> Done! Release artifacts:"
echo "    DMG: $DMG_PATH"
echo "    Zip: $ZIP_PATH"
echo ""
echo "    Upload these to a GitHub Release."
