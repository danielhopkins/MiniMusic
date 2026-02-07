#!/bin/bash
#
# release.sh — Build, sign, notarize, and package MiniMusic as a DMG
#
# One-time setup: store notarytool credentials in keychain:
#
#   xcrun notarytool store-credentials "MiniMusic" \
#       --key /path/to/AuthKey_XXXXXXXXXX.p8 \
#       --key-id "XXXXXXXXXX" \
#       --issuer "YOUR_ISSUER_UUID"
#
# Key ID + Issuer UUID from App Store Connect > Users and Access >
# Integrations > App Store Connect API.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MiniMusic"
PROJECT_YML="${SCRIPT_DIR}/project.yml"
BUILD_DIR="${SCRIPT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/release"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
KEYCHAIN_PROFILE="MiniMusic"

cd "$SCRIPT_DIR"

# ── 1. Bump version ─────────────────────────────────────────────────
CURRENT_VERSION=$(grep 'MARKETING_VERSION:' "$PROJECT_YML" | sed 's/.*"\(.*\)"/\1/')
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"
sed -i '' "s/MARKETING_VERSION: \"${CURRENT_VERSION}\"/MARKETING_VERSION: \"${NEW_VERSION}\"/" "$PROJECT_YML"
echo "Version: ${CURRENT_VERSION} → ${NEW_VERSION}"

CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | sed 's/.*"\(.*\)"/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"${CURRENT_BUILD}\"/CURRENT_PROJECT_VERSION: \"${NEW_BUILD}\"/" "$PROJECT_YML"
echo "Build:   ${CURRENT_BUILD} → ${NEW_BUILD}"

# ── 2. Regenerate Xcode project ─────────────────────────────────────
xcodegen generate

# ── 3. Archive ───────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
echo "Archiving..."
xcodebuild archive \
    -project MiniMusic.xcodeproj \
    -scheme MiniMusic \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    | tail -3

echo "Archive complete."

# ── 4. Export ────────────────────────────────────────────────────────
echo "Exporting..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath "$EXPORT_PATH" \
    | tail -3

APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Export failed — ${APP_PATH} not found"
    exit 1
fi
echo "Export complete."

# ── 5. Notarize ──────────────────────────────────────────────────────
echo "Submitting for notarization..."
ZIP_PATH="${BUILD_DIR}/${APP_NAME}-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

rm -f "$ZIP_PATH"
echo "Notarization complete."

# ── 6. Staple the .app ──────────────────────────────────────────────
echo "Stapling .app..."
xcrun stapler staple "$APP_PATH"

# ── 7. Verify ────────────────────────────────────────────────────────
echo "Verifying..."
codesign --verify --deep --strict "$APP_PATH"
spctl --assess --type exec -v "$APP_PATH"
echo "Verification passed."

# ── 8. Create DMG ────────────────────────────────────────────────────
echo "Creating DMG..."
rm -f "$DMG_PATH"

STAGING_DIR="${BUILD_DIR}/dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

# ── 9. Notarize the DMG ──────────────────────────────────────────────
echo "Submitting DMG for notarization..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait
echo "DMG notarization complete."

# ── 10. Staple the DMG ──────────────────────────────────────────────
echo "Stapling DMG..."
xcrun stapler staple "$DMG_PATH"

# ── 11. Summary ──────────────────────────────────────────────────────
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1 | xargs)
echo ""
echo "════════════════════════════════════════"
echo "  ${APP_NAME} ${NEW_VERSION} (${NEW_BUILD})"
echo "  DMG: ${DMG_PATH}"
echo "  Size: ${DMG_SIZE}"
echo "════════════════════════════════════════"
