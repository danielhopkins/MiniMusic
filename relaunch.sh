#!/bin/bash
set -e

APP_NAME="MiniMusic"
APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData/${APP_NAME}-*/Build/Products/Debug/${APP_NAME}.app -maxdepth 0 2>/dev/null | head -1)"

if [ -z "$APP_PATH" ]; then
    echo "ERROR: No built ${APP_NAME}.app found in DerivedData"
    exit 1
fi

# Kill all running instances
PIDS=$(pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo "$PIDS" | xargs kill -9
    echo "Killed PIDs: $PIDS"
    sleep 0.5
fi

# Verify dead
if pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then
    echo "ERROR: Failed to kill ${APP_NAME}"
    exit 1
fi

# Launch
open "$APP_PATH"
echo "Launched: $APP_PATH"
