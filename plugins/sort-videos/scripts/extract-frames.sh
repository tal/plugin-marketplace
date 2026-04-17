#!/usr/bin/env bash
# Extract frames from a video at a given interval
# Usage: extract-frames.sh <video-path> <output-dir> [interval]
# interval: seconds between frames (default: 2)

set -euo pipefail

VIDEO="$1"
OUTPUT_DIR="$2"
INTERVAL="${3:-2}"

if [ ! -f "$VIDEO" ]; then
  echo "Error: Video file not found: $VIDEO" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

ffmpeg -i "$VIDEO" -vf "fps=1/${INTERVAL}" "$OUTPUT_DIR/%04d.png" -y 2>/dev/null

COUNT=$(ls -1 "$OUTPUT_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "$OUTPUT_DIR"
echo "Extracted $COUNT frames at 1 frame every ${INTERVAL}s"
