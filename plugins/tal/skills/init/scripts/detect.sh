#!/usr/bin/env bash

# detect.sh — list the signals /tal:init uses to decide which tal skills apply
# to a project. Read-only.
#
# Usage: detect.sh [--dir <path>]
#
#   --dir <path>   Default: the git top level, else the current directory.
#
# kv output, one key=value per line:
#   root=<path>
#   git=repo|none
#   xcode=<relative path>                   *.xcodeproj / *.xcworkspace, depth ≤ 2
#   fly_toml=<relative path>                fly.toml / fly.*.toml, depth ≤ 2
#   github_remote=<name> <url>
#   paas_remote=<name> <url>                dokku / heroku remotes
#   deploy_workflow=<relative path>         .github/workflows/*.yml(yaml) that run on
#                                           push and mention deploy / release / environment
#   deploy_config=ok|missing|invalid|unreadable
#   deploy_target=<name>[ <channel> …]      from check-config.sh, when deploy_config=ok
#   deploy_pipeline=<name> <target:channel> …
#   agents_md=present|missing
#   claude_md=imports-agents|present|missing   imports-agents: has an `@AGENTS.md` line
#   init_block=present|missing|broken       the <!-- tal:init:start/end --> markers in
#                                           AGENTS.md; broken = only one of the two
#   project_skill=<relative path>           .claude/skills/*/SKILL.md (may overlap)
#
# Exit: 0 | 64 usage

set -euo pipefail

usage() {
  echo "usage: detect.sh [--dir <path>]" >&2
  exit 64
}

DIR=""
while [ $# -gt 0 ]; do
  case $1 in
    --dir) [ $# -ge 2 ] || usage; DIR=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "detect: unknown argument: $1" >&2; usage ;;
  esac
done

if [ -z "$DIR" ]; then
  DIR=$(git rev-parse --show-toplevel 2>/dev/null) || DIR=$PWD
fi
[ -d "$DIR" ] || { echo "detect: not a directory: $DIR" >&2; exit 64; }
ROOT=$(cd "$DIR" && pwd -P)
HERE=$(cd "$(dirname "$0")" && pwd -P)
CHECK_CONFIG="$HERE/../../deploy/scripts/check-config.sh"

echo "root=$ROOT"

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "git=repo"
  GIT=repo
else
  echo "git=none"
  GIT=none
fi

# Shallow searches only, skipping build output and vendored trees.
shallow_find() {
  # $@ = find name predicates
  (cd "$ROOT" && find . -maxdepth 2 \
    \( -name .git -o -name node_modules -o -name Pods -o -name build -o -name .build \
       -o -name DerivedData -o -name vendor -o -name Carthage \) -prune -o \
    \( "$@" \) -print 2>/dev/null) | sed 's|^\./||' | sort
}

# Workspaces inside an .xcodeproj or a .playground are Xcode's own; skip them.
shallow_find -name '*.xcodeproj' -o -name '*.xcworkspace' \
  | grep -Ev '\.(xcodeproj|playground)/' | sed 's/^/xcode=/' || true
shallow_find -name 'fly.toml' -o -name 'fly.*.toml' | sed 's/^/fly_toml=/' || true

if [ "$GIT" = repo ]; then
  git -C "$ROOT" remote -v 2>/dev/null | awk '$3 == "(fetch)" { print $1, $2 }' \
    | while read -r name url; do
        case $url in
          *github.com[:/]*) echo "github_remote=$name $url" ;;
        esac
        case "$name $url" in
          dokku\ *|heroku\ *|*heroku.com*|*dokku@*) echo "paas_remote=$name $url" ;;
        esac
      done
fi

if [ -d "$ROOT/.github/workflows" ]; then
  for wf in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml; do
    [ -f "$wf" ] || continue
    grep -Eq '^[[:space:]]*push:|^on:[[:space:]]*\[?.*push' "$wf" || continue
    grep -Eiq 'deploy|release|environment:' "$wf" || continue
    echo "deploy_workflow=${wf#"$ROOT"/}"
  done
fi

if [ ! -f "$ROOT/.config/deploy.yml" ]; then
  echo "deploy_config=missing"
elif [ ! -x "$CHECK_CONFIG" ]; then
  echo "deploy_config=unreadable"
else
  set +e
  OUT=$("$CHECK_CONFIG" --file "$ROOT/.config/deploy.yml" 2>/dev/null)
  RC=$?
  set -e
  case $RC in
    0)
      echo "deploy_config=ok"
      printf '%s\n' "$OUT" | sed -n 's/^target=/deploy_target=/p; s/^pipeline=/deploy_pipeline=/p'
      ;;
    1) echo "deploy_config=invalid" ;;
    *) echo "deploy_config=unreadable" ;;
  esac
fi

if [ -f "$ROOT/AGENTS.md" ]; then
  echo "agents_md=present"
  START=$(grep -c '<!-- tal:init:start' "$ROOT/AGENTS.md" || true)
  END=$(grep -c '<!-- tal:init:end' "$ROOT/AGENTS.md" || true)
  if [ "$START" = 1 ] && [ "$END" = 1 ]; then
    echo "init_block=present"
  elif [ "$START" = 0 ] && [ "$END" = 0 ]; then
    echo "init_block=missing"
  else
    echo "init_block=broken"
  fi
else
  echo "agents_md=missing"
  echo "init_block=missing"
fi

if [ ! -f "$ROOT/CLAUDE.md" ]; then
  echo "claude_md=missing"
elif grep -Eq '^[[:space:]]*@(\./)?AGENTS\.md[[:space:]]*$' "$ROOT/CLAUDE.md"; then
  echo "claude_md=imports-agents"
else
  echo "claude_md=present"
fi

for s in "$ROOT"/.claude/skills/*/SKILL.md; do
  [ -f "$s" ] && echo "project_skill=${s#"$ROOT"/}"
done

exit 0
