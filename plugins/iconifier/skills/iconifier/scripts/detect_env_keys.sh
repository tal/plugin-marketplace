#!/usr/bin/env bash
# Probe the environment + nearby .env files for image-gen API keys.
# Output is line-based so the calling skill can grep it:
#   OPENAI_API_KEY: yes|no
#   GEMINI_API_KEY: yes|no
#   GOOGLE_API_KEY: yes|no
#   ANTHROPIC_API_KEY: yes|no
#   ai-available: yes|no
#
# .env loading: walk upward from cwd to $HOME, sourcing the first .env
# (and .env.local) we find. We don't merge — closest wins, same as most
# tooling. Sourcing happens in a subshell so we don't pollute the caller.

set -euo pipefail

dir="$PWD"
loaded=""
while [[ "$dir" != "/" && "$dir" != "$HOME/.." ]]; do
  for name in .env .env.local; do
    if [[ -f "$dir/$name" && -z "$loaded" ]]; then
      # set -a auto-exports anything sourced. shellcheck source=/dev/null
      set -a
      # shellcheck disable=SC1090
      source "$dir/$name" 2>/dev/null || true
      set +a
      loaded="$dir/$name"
    fi
  done
  [[ "$dir" == "$HOME" ]] && break
  dir="$(dirname "$dir")"
done

check() {
  local var="$1"
  local val="${!var:-}"
  if [[ -n "$val" ]]; then
    echo "$var: yes"
    return 0
  else
    echo "$var: no"
    return 1
  fi
}

ai_available="no"
check OPENAI_API_KEY     && ai_available="yes" || true
check GEMINI_API_KEY     && ai_available="yes" || true
check GOOGLE_API_KEY     && ai_available="yes" || true
check ANTHROPIC_API_KEY  || true   # noted but not used for image gen

echo "ai-available: $ai_available"
[[ -n "$loaded" ]] && echo "loaded-env: $loaded" || echo "loaded-env: none"
