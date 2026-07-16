#!/bin/zsh
# Name-survival benchmark for the on-device intent parser. Compiles the app's
# REAL search source files together with Benchmark.swift and runs it against the
# live Foundation Model.
#
#   ./bench.sh              # 5 iterations per query (default), ~3–4 min
#   ITERS=8 ./bench.sh      # more iterations for a tighter estimate
#   MAX_SECONDS=900 ./bench.sh
#
# Live per-query progress prints to stderr. A watchdog hard-kills the run after
# MAX_SECONDS (default 600) so a rare model stall can't hang for 29 minutes —
# the on-device model occasionally freezes on a single call.
set -e
HERE="${0:A:h}"
APP="${HERE:h:h}/MiniMusic"
BIN="$HERE/.build/benchmark"
MAX_SECONDS="${MAX_SECONDS:-600}"
mkdir -p "$HERE/.build"

swiftc -O \
  "$APP/Models/SearchCategory.swift" \
  "$APP/Models/SearchIntent.swift" \
  "$APP/Utilities/CatalogueReference.swift" \
  "$APP/Utilities/ClassicalTitle.swift" \
  "$APP/Utilities/SearchQueryParser.swift" \
  "$APP/Utilities/SearchPlanner.swift" \
  "$APP/Utilities/SearchIntentParser.swift" \
  "$HERE/Benchmark.swift" \
  -o "$BIN"

"$BIN" &
run_pid=$!

# Watchdog: kill the run if it exceeds the wall-clock cap.
( sleep "$MAX_SECONDS"
  if kill -0 "$run_pid" 2>/dev/null; then
    print -u2 "\n⏱  watchdog: exceeded ${MAX_SECONDS}s — the model likely stalled. Killing run."
    kill -9 "$run_pid" 2>/dev/null
  fi ) &
watchdog_pid=$!

# Wait for the benchmark; then stop the watchdog so it doesn't linger.
# (|| capture avoids `set -e` aborting when the watchdog kills the run.)
wait "$run_pid" && run_status=0 || run_status=$?
kill "$watchdog_pid" 2>/dev/null
exit $run_status
