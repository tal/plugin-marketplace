#!/usr/bin/env bash
# Exit 0 on macOS, exit 1 with a clear message everywhere else.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iconifier: this skill only runs on macOS (uname=$(uname -s)). Aborting." >&2
  exit 1
fi

# Sanity-check the system bits we rely on.
missing=()
command -v sips >/dev/null 2>&1 || missing+=("sips")
command -v swift >/dev/null 2>&1 || missing+=("swift")
command -v python3 >/dev/null 2>&1 || missing+=("python3")

if (( ${#missing[@]} > 0 )); then
  echo "iconifier: missing required tools: ${missing[*]}" >&2
  echo "  Install Xcode command line tools with: xcode-select --install" >&2
  exit 1
fi

exit 0
