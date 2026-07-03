#!/bin/zsh
# Inspects what the on-device intent parser does with specific queries. Compiles
# the app's REAL search source files together with Inspect.swift and runs it.
# Pass queries as args, or run with none for a default set.
#
#   ./inspect.sh "brahms piano" "albums by radiohead"
set -e
HERE="${0:A:h}"
APP="${HERE:h:h}/MiniMusic"
BIN="$HERE/.build/inspect"
mkdir -p "$HERE/.build"

swiftc -O \
  "$APP/Models/SearchCategory.swift" \
  "$APP/Models/SearchIntent.swift" \
  "$APP/Utilities/SearchQueryParser.swift" \
  "$APP/Utilities/SearchPlanner.swift" \
  "$APP/Utilities/SearchIntentParser.swift" \
  "$HERE/Inspect.swift" \
  -o "$BIN"

"$BIN" "$@"
