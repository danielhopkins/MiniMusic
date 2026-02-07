#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MiniMusic"
PROJECT_YML="${SCRIPT_DIR}/project.yml"
INSTALL_DIR="/Applications"

# Bump patch version in project.yml
CURRENT_VERSION=$(grep 'MARKETING_VERSION:' "$PROJECT_YML" | sed 's/.*"\(.*\)"/\1/')
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"
sed -i '' "s/MARKETING_VERSION: \"${CURRENT_VERSION}\"/MARKETING_VERSION: \"${NEW_VERSION}\"/" "$PROJECT_YML"
echo "Version: ${CURRENT_VERSION} → ${NEW_VERSION}"

# Bump build number
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | sed 's/.*"\(.*\)"/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"${CURRENT_BUILD}\"/CURRENT_PROJECT_VERSION: \"${NEW_BUILD}\"/" "$PROJECT_YML"
echo "Build: ${CURRENT_BUILD} → ${NEW_BUILD}"

# Regenerate Xcode project
cd "$SCRIPT_DIR"
xcodegen generate

# Build
xcodebuild -project MiniMusic.xcodeproj -scheme MiniMusic -destination 'platform=macOS' build | tail -3

APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData/${APP_NAME}-*/Build/Products/Debug/${APP_NAME}.app -maxdepth 0 2>/dev/null | head -1)"

if [ -z "$APP_PATH" ]; then
    echo "ERROR: No built ${APP_NAME}.app found in DerivedData"
    exit 1
fi

# Kill all running instances
PIDS=$(pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo "$PIDS" | xargs kill -9
    sleep 0.5
fi

# Install
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "$APP_PATH" "${INSTALL_DIR}/"
echo "Installed ${APP_NAME} ${NEW_VERSION} (${NEW_BUILD}) to ${INSTALL_DIR}"

# Launch
open "${INSTALL_DIR}/${APP_NAME}.app"
echo "Launched ${APP_NAME}"
