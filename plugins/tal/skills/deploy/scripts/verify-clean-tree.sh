#!/usr/bin/env bash

# verify-clean-tree.sh — is this checkout fit to deploy from?
#
# Usage: verify-clean-tree.sh [--branch <name>] [--no-fetch]
#
#   --branch <name>   Branch deploys must come from. Omit to accept any branch.
#   --no-fetch        Don't `git fetch` the upstream before counting ahead/behind.
#
# Read-only apart from the fetch. Prints key=value lines on stdout:
#   head, branch, expected_branch, branch_status (ok|mismatch|detached),
#   tree (clean|dirty), dirty_files, one dirty_file=<porcelain line> per entry,
#   upstream (<ref>|none), ahead, behind (N, or - with no upstream),
#   fetch (ok|failed|skipped)
#
# "Dirty" = any staged change, unstaged tracked change, or untracked file that
# isn't gitignored.
#
# Exit: 0 clean and on branch | 1 dirty | 2 wrong branch or detached HEAD
#       (wins over 1) | 64 usage

set -euo pipefail

usage() {
  echo "usage: verify-clean-tree.sh [--branch <name>] [--no-fetch]" >&2
  exit 64
}

EXPECTED=""
FETCH=1
while [ $# -gt 0 ]; do
  case $1 in
    --branch) [ $# -ge 2 ] || usage; EXPECTED=$2; shift 2 ;;
    --no-fetch) FETCH=0; shift ;;
    -h|--help) usage ;;
    *) echo "verify-clean-tree: unknown argument: $1" >&2; usage ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "verify-clean-tree: not inside a git repository" >&2; exit 64; }
TOP=$(git rev-parse --show-toplevel)

HEAD_SHA=$(git rev-parse -q --verify HEAD || echo none)

if BRANCH=$(git symbolic-ref -q --short HEAD); then
  if [ -n "$EXPECTED" ] && [ "$BRANCH" != "$EXPECTED" ]; then
    BRANCH_STATUS=mismatch
  else
    BRANCH_STATUS=ok
  fi
else
  BRANCH=HEAD
  BRANCH_STATUS=detached
fi

# Upstream + fetch. Fetch failure (offline, auth) is reported, not fatal.
UPSTREAM=none
FETCH_STATUS=skipped
AHEAD=-
BEHIND=-
if [ "$BRANCH" != HEAD ] && UPSTREAM=$(git rev-parse -q --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null); then
  if [ "$FETCH" -eq 1 ]; then
    REMOTE=$(git config "branch.$BRANCH.remote" || echo origin)
    if git fetch --quiet "$REMOTE" >/dev/null 2>&1; then
      FETCH_STATUS=ok
    else
      FETCH_STATUS=failed
      echo "verify-clean-tree: git fetch $REMOTE failed; ahead/behind are from the last fetch" >&2
    fi
  fi
  # left = behind (upstream-only commits), right = ahead (local-only commits)
  COUNTS=$(git rev-list --left-right --count "$UPSTREAM...HEAD")
  BEHIND=${COUNTS%%[[:space:]]*}
  AHEAD=${COUNTS##*[[:space:]]}
else
  UPSTREAM=none
fi

PORCELAIN=$(git -C "$TOP" status --porcelain=v1 --untracked-files=normal)
if [ -n "$PORCELAIN" ]; then
  TREE=dirty
  DIRTY_COUNT=$(printf '%s\n' "$PORCELAIN" | wc -l | tr -d ' ')
else
  TREE=clean
  DIRTY_COUNT=0
fi

echo "head=$HEAD_SHA"
echo "branch=$BRANCH"
echo "expected_branch=${EXPECTED:--}"
echo "branch_status=$BRANCH_STATUS"
echo "tree=$TREE"
echo "dirty_files=$DIRTY_COUNT"
if [ -n "$PORCELAIN" ]; then
  printf '%s\n' "$PORCELAIN" | while IFS= read -r line; do echo "dirty_file=$line"; done
fi
echo "upstream=$UPSTREAM"
echo "ahead=$AHEAD"
echo "behind=$BEHIND"
echo "fetch=$FETCH_STATUS"

if [ "$BRANCH_STATUS" != ok ]; then exit 2; fi
if [ "$TREE" = dirty ]; then exit 1; fi
exit 0
