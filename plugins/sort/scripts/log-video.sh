#!/usr/bin/env bash
# Prepend an entry to the sort-videos processing log (newest entry first).
# The log is prepend-only: new entries go on top, past entries are never
# edited or removed. Entry markdown is read from stdin.
# Usage: cat entry.md | log-video.sh <log-path>

set -euo pipefail

LOG="$1"
ENTRY="$(cat)"
TMP="$(mktemp)"

{
  printf '%s\n\n' "$ENTRY"
  [ -f "$LOG" ] && cat "$LOG"
} > "$TMP"

mv "$TMP" "$LOG"
echo "$LOG"
