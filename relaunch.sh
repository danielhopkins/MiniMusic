#!/bin/bash
set -eu

APP_NAME="MiniMusic"
# Matches the running executable of any MiniMusic.app, regardless of which
# DerivedData directory it was built into.
EXEC_GLOB="${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

# PIDs of every running MiniMusic instance.
running_pids() {
    pgrep -f "$EXEC_GLOB" 2>/dev/null || true
}

# --- Pick the newest built app -----------------------------------------------
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
    echo "ERROR: No built ${APP_NAME}.app found in DerivedData" >&2
    exit 1
fi

if [ "$(echo "$CANDIDATES" | grep -c .)" -gt 1 ]; then
    echo "NOTE: multiple DerivedData builds found; using the newest:"
    echo "$CANDIDATES" | cut -f2- | sed 's/^/  /'
fi

# --- Kill every running instance, escalating, and refuse to continue if any
#     survive. Piling up duplicate instances is the classic footgun here: the
#     menu-bar icon you click may belong to a stale build while a newer one runs
#     invisibly, so a half-successful kill is worse than a loud failure. --------
attempt=0
while :; do
    pids="$(running_pids)"
    [ -z "$pids" ] && break

    attempt=$((attempt + 1))
    if [ "$attempt" -gt 6 ]; then
        echo "ERROR: could not stop ${APP_NAME}; still running: $(echo $pids | tr '\n' ' ')" >&2
        echo "       Kill by hand and re-run: kill -9 $(echo $pids | tr '\n' ' ')" >&2
        exit 1
    fi

    if [ "$attempt" -eq 1 ]; then
        # First pass: SIGTERM, so the app can persist its queue on the way out.
        echo "Stopping ${APP_NAME} (PIDs: $(echo $pids | tr '\n' ' '))"
        echo "$pids" | xargs kill 2>/dev/null || true
    else
        # It didn't go quietly — escalate to SIGKILL.
        echo "$pids" | xargs kill -9 2>/dev/null || true
    fi
    sleep 0.5
done

# --- Launch exactly the build we selected ------------------------------------
# `-n` opens this specific bundle as a fresh instance rather than letting
# LaunchServices reactivate some other registered copy by bundle ID.
open -n "$APP_PATH"

# --- Verify a single instance came up, from the binary we launched -----------
pids=""
for _ in $(seq 1 15); do
    sleep 0.3
    pids="$(running_pids)"
    [ -n "$pids" ] && break
done

if [ -z "$pids" ]; then
    echo "ERROR: ${APP_NAME} did not start" >&2
    exit 1
fi

count="$(echo "$pids" | grep -c .)"
if [ "$count" -ne 1 ]; then
    echo "ERROR: expected 1 ${APP_NAME} instance, found $count: $(echo $pids | tr '\n' ' ')" >&2
    echo "       A duplicate slipped through — kill all and re-run." >&2
    exit 1
fi

# Confirm the running executable is the build we picked, not a stale copy that
# LaunchServices resurrected from elsewhere.
running_exe="$(ps -o comm= -p "$pids" 2>/dev/null || true)"
case "$running_exe" in
    "$APP_PATH"/*) ;;
    *)
        echo "ERROR: running instance is $running_exe," >&2
        echo "       not the selected build $APP_PATH" >&2
        exit 1
        ;;
esac

echo "Launched: $APP_PATH (PID $pids)"
