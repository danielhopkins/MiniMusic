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

# ── 0. Pre-flight: on-device intent test suite ──────────────────────
# DO NOT ship a release unless the intent test suite has been run and passes.
# The on-device intent parser prompt (SearchIntent / SearchIntentParser) is easy
# to regress — a small wording change can make the model mangle artist names
# (e.g. "brahms" → "braves"). Tools/IntentBench catches this, but it needs live
# Apple Intelligence and is nondeterministic, so it can't run in CI — it must be
# run by hand before shipping. Set SKIP_INTENT_CHECK=1 only if you know why.
if [ "${SKIP_INTENT_CHECK:-0}" != "1" ]; then
    echo "── Release pre-flight ──────────────────────────────────"
    echo "Have you run the intent test suite and confirmed it passes?"
    echo "    ./Tools/IntentBench/bench.sh"
    echo "(needs Apple Intelligence; can't run in CI — see Tools/IntentBench/README.md)"
    read -r -p "Intent suite passing? [y/N] " ans
    if [[ "$ans" != [yY] ]]; then
        echo "Aborting: run ./Tools/IntentBench/bench.sh first (or SKIP_INTENT_CHECK=1 to override)."
        exit 1
    fi
fi

# ── 1. Bump version (CalVer: YY.MMDD.Patch) ─────────────────────────
CURRENT_VERSION=$(grep 'MARKETING_VERSION:' "$PROJECT_YML" | sed 's/.*"\(.*\)"/\1/')
YY=$(date +%y)
# MMDD with no leading zero (e.g. Feb 10 → 210, not 0210)
MMDD=$(date +%-m%d)
DAY_PREFIX="v${YY}.${MMDD}."

# Find highest patch for today from git tags
MAX_PATCH=-1
for tag in $(git tag -l "${DAY_PREFIX}*" 2>/dev/null); do
    P="${tag#${DAY_PREFIX}}"
    if [[ "$P" =~ ^[0-9]+$ ]] && (( P > MAX_PATCH )); then
        MAX_PATCH=$P
    fi
done
NEW_PATCH=$((MAX_PATCH + 1))
NEW_VERSION="${YY}.${MMDD}.${NEW_PATCH}"

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

# ── 11. Tag and create GitHub release ─────────────────────────────────
# Include the regenerated Xcode project (step 2 runs `xcodegen generate`) so
# the working tree isn't left dirty after a release.
git add "$PROJECT_YML" MiniMusic.xcodeproj
git commit -m "Bump version to ${NEW_VERSION} (build ${NEW_BUILD})"
git tag "v${NEW_VERSION}"
git push origin main "v${NEW_VERSION}"
echo "Tagged v${NEW_VERSION}"

echo "Creating GitHub release..."
gh release create "v${NEW_VERSION}" "$DMG_PATH" \
    --title "${APP_NAME} ${NEW_VERSION}" \
    --generate-notes
echo "GitHub release created."

# ── 12. Generate Sparkle appcast and publish to GitHub Pages ─────────
echo "Generating Sparkle appcast..."
APPCAST_DIR="${BUILD_DIR}/appcast"
mkdir -p "$APPCAST_DIR"
cp "$DMG_PATH" "$APPCAST_DIR/"

# Find Sparkle tools — check DerivedData SPM artifacts first, then .build/
SPARKLE_BIN_DIR=$(find ~/Library/Developer/Xcode/DerivedData/MiniMusic-*/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 -type d 2>/dev/null | head -1)
if [ -z "$SPARKLE_BIN_DIR" ]; then
    SPARKLE_BIN_DIR="${SCRIPT_DIR}/.build/artifacts/sparkle/Sparkle/bin"
fi
if [ -z "$SPARKLE_BIN_DIR" ] || [ ! -d "$SPARKLE_BIN_DIR" ]; then
    echo "WARNING: Sparkle bin directory not found — skipping appcast generation"
else
    # Sign the DMG for Sparkle (EdDSA)
    SIGN_OUTPUT=$("$SPARKLE_BIN_DIR/sign_update" "$DMG_PATH")
    echo "$SIGN_OUTPUT"

    # Generate appcast.xml with download URLs pointing to GitHub Releases
    DOWNLOAD_URL_PREFIX="https://github.com/danielhopkins/MiniMusic/releases/download/v${NEW_VERSION}/"
    "$SPARKLE_BIN_DIR/generate_appcast" \
        --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
        "$APPCAST_DIR"

    # Patch in EdDSA signature if generate_appcast didn't include it
    if ! grep -q 'sparkle:edSignature' "${APPCAST_DIR}/appcast.xml"; then
        ED_SIG=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"')
        if [ -n "$ED_SIG" ]; then
            sed -i '' "s|<enclosure |<enclosure ${ED_SIG} |" "${APPCAST_DIR}/appcast.xml"
            echo "Patched EdDSA signature into appcast.xml"
        fi
    fi

    # Publish appcast.xml to gh-pages branch
    GH_PAGES_DIR="${BUILD_DIR}/gh-pages"
    git worktree add "$GH_PAGES_DIR" gh-pages 2>/dev/null || true
    cp "${APPCAST_DIR}/appcast.xml" "$GH_PAGES_DIR/"
    cd "$GH_PAGES_DIR"
    git add appcast.xml
    git commit -m "Update appcast for v${NEW_VERSION}" || echo "No appcast changes to commit"
    git push origin gh-pages
    cd "$SCRIPT_DIR"
    git worktree remove "$GH_PAGES_DIR"
    echo "Appcast published to GitHub Pages."
fi

# ── 13. Summary ──────────────────────────────────────────────────────
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1 | xargs)
RELEASE_URL=$(gh release view "v${NEW_VERSION}" --json url -q .url)
echo ""
echo "════════════════════════════════════════"
echo "  ${APP_NAME} ${NEW_VERSION} (${NEW_BUILD})"
echo "  DMG: ${DMG_PATH}"
echo "  Size: ${DMG_SIZE}"
echo "  Release: ${RELEASE_URL}"
echo "════════════════════════════════════════"
