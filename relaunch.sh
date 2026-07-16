#!/bin/bash
set -e

APP_NAME="MiniMusic"

# Regenerating the project mints a fresh DerivedData directory without retiring
# the old one, so several can match the glob at once. Pick by the executable's
# build time — the oldest is a stale build that predates today's source.
CANDIDATES="$(
    for app in ~/Library/Developer/Xcode/DerivedData/${APP_NAME}-*/Build/Products/Debug/${APP_NAME}.app; do
        exe="$app/Contents/MacOS/${APP_NAME}"
        [ -x "$exe" ] && printf '%s\t%s\n' "$(stat -f %m "$exe")" "$app"
    done | sort -rn
)"
APP_PATH="$(echo "$CANDIDATES" | head -1 | cut -f2-)"

if [ -z "$APP_PATH" ]; then
    echo "ERROR: No built ${APP_NAME}.app found in DerivedData"
    exit 1
fi

if [ "$(echo "$CANDIDATES" | wc -l)" -gt 1 ]; then
    echo "NOTE: multiple DerivedData builds found; using the newest:"
    echo "$CANDIDATES" | cut -f2- | sed 's/^/  /'
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
