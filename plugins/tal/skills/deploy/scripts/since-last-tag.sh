#!/usr/bin/env bash

# since-last-tag.sh — what changed since this target+channel last shipped.
#
# Usage: since-last-tag.sh --target <t> --channel <c> [--tag-pattern <p>]
#                          [--head <rev>] [--include <csv>] [--exclude <csv>]
#                          [--max <n>]
#
#   --tag-pattern  Default builds/{target}/{channel}/{version}
#   --head         Default HEAD. Use the promoted commit when re-pointing an
#                  existing artifact at a new channel.
#   --include      Conventional-commit types that are user-facing.
#                  Default feat,fix,perf
#   --exclude      Types to drop. Default chore,docs,test,ci,build,style,refactor,design
#   --max          Commits to list when there is no usable base. Default 50
#
# Base = the newest tag in the channel's namespace (--sort=-creatordate). The
# diff base is per channel on purpose: external usually lags internal, so an
# external release should list everything since *external* last shipped.
#
# base_status:
#   ancestor   tag commit is an ancestor of head — normal case
#   twin       history was rewritten under the tag; matched a commit in head's
#              history with the same author timestamp + subject and used that
#   unrelated  no twin; fell back to `git merge-base` (base_commit=none if
#              there isn't one, then the last --max commits are listed)
#   none       no tag yet; the last --max commits are listed
#
# Output: base_tag, base_commit, base_status, tag_commit, head, included_count,
# unclassified_count, excluded_count, a `---` line, then TSV lines
# `<included|unclassified>\t<short sha>\t<subject>`. Excluded commits are only
# counted. Merges are skipped.
#
# Exit: 0 ok | 64 usage

set -euo pipefail

usage() {
  echo "usage: since-last-tag.sh --target <t> --channel <c> [--tag-pattern <p>] [--head <rev>] [--include <csv>] [--exclude <csv>] [--max <n>]" >&2
  exit 64
}

TARGET=""
CHANNEL=""
PATTERN="builds/{target}/{channel}/{version}"
HEAD_REV=HEAD
INCLUDE="feat,fix,perf"
EXCLUDE="chore,docs,test,ci,build,style,refactor,design"
MAX=50
while [ $# -gt 0 ]; do
  case $1 in
    --target) [ $# -ge 2 ] || usage; TARGET=$2; shift 2 ;;
    --channel) [ $# -ge 2 ] || usage; CHANNEL=$2; shift 2 ;;
    --tag-pattern) [ $# -ge 2 ] || usage; PATTERN=$2; shift 2 ;;
    --head) [ $# -ge 2 ] || usage; HEAD_REV=$2; shift 2 ;;
    --include) [ $# -ge 2 ] || usage; INCLUDE=$2; shift 2 ;;
    --exclude) [ $# -ge 2 ] || usage; EXCLUDE=$2; shift 2 ;;
    --max) [ $# -ge 2 ] || usage; MAX=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "since-last-tag: unknown argument: $1" >&2; usage ;;
  esac
done
if [ -z "$TARGET" ] || [ -z "$CHANNEL" ]; then usage; fi
case $MAX in ''|*[!0-9]*) usage ;; esac
case $PATTERN in *'{version}'*) ;; *) echo "since-last-tag: --tag-pattern must contain {version}" >&2; exit 64 ;; esac
git rev-parse --git-dir >/dev/null 2>&1 || { echo "since-last-tag: not inside a git repository" >&2; exit 64; }
HEAD_SHA=$(git rev-parse -q --verify "$HEAD_REV^{commit}") || { echo "since-last-tag: unknown --head: $HEAD_REV" >&2; exit 64; }

ere_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/[].(){}*+?^$|[]/\\&/g'; }

# Anchored ERE for this target + channel's tags.
pattern_regex() {
  local p=$1 out=""
  while [ -n "$p" ]; do
    case $p in
      '{target}'*) out="$out$(ere_escape "$TARGET")"; p=${p#'{target}'} ;;
      '{channel}'*) out="$out$(ere_escape "$CHANNEL")"; p=${p#'{channel}'} ;;
      '{version}'*) out="$out.+"; p=${p#'{version}'} ;;
      *) out="$out$(ere_escape "${p:0:1}")"; p=${p:1} ;;
    esac
  done
  printf '^%s$' "$out"
}

BASE_TAG=$(git tag --list --sort=-creatordate | grep -E "$(pattern_regex "$PATTERN")" | head -1 || true)
TAG_COMMIT=none
BASE_COMMIT=none
if [ -z "$BASE_TAG" ]; then
  BASE_TAG=none
  BASE_STATUS=none
else
  TAG_COMMIT=$(git rev-parse "$BASE_TAG^{commit}")
  if git merge-base --is-ancestor "$TAG_COMMIT" "$HEAD_SHA"; then
    BASE_STATUS=ancestor
    BASE_COMMIT=$TAG_COMMIT
  else
    # Rewritten history: look for the tagged commit's twin in head's history.
    TWIN_AT=$(git log -1 --format=%at "$TAG_COMMIT")
    TWIN_SUBJ=$(git log -1 --format=%s "$TAG_COMMIT")
    TWIN=$(git log --format='%H%x09%at%x09%s' "$HEAD_SHA" |
      AT="$TWIN_AT" S="$TWIN_SUBJ" awk -F'\t' '$2 == ENVIRON["AT"] && substr($0, length($1 FS $2 FS) + 1) == ENVIRON["S"] { print $1; exit }')
    if [ -n "$TWIN" ]; then
      BASE_STATUS=twin
      BASE_COMMIT=$TWIN
      echo "since-last-tag: $BASE_TAG points at ${TAG_COMMIT:0:7}, which is not in head's history; using its twin ${TWIN:0:7}" >&2
    else
      BASE_STATUS=unrelated
      BASE_COMMIT=$(git merge-base "$TAG_COMMIT" "$HEAD_SHA" || echo none)
      echo "since-last-tag: $BASE_TAG is not in head's history and has no twin; falling back to merge-base ($BASE_COMMIT)" >&2
    fi
  fi
fi

if [ "$BASE_COMMIT" = none ]; then
  LOG=$(git log --no-merges -n "$MAX" --format='%h%x09%s' "$HEAD_SHA")
else
  LOG=$(git log --no-merges --format='%h%x09%s' "$BASE_COMMIT..$HEAD_SHA")
fi

echo "base_tag=$BASE_TAG"
echo "base_commit=$BASE_COMMIT"
echo "base_status=$BASE_STATUS"
echo "tag_commit=$TAG_COMMIT"
echo "head=$HEAD_SHA"

# Classify `type(scope)!: subject`. Neither-list types and non-conventional
# subjects land in `unclassified` for a human (or the model) to judge.
printf '%s' "$LOG" | INC="$INCLUDE" EXC="$EXCLUDE" awk -F'\t' '
  BEGIN {
    n = split(tolower(ENVIRON["INC"]), a, ","); for (i = 1; i <= n; i++) inc[a[i]] = 1
    n = split(tolower(ENVIRON["EXC"]), a, ","); for (i = 1; i <= n; i++) exc[a[i]] = 1
  }
  NF == 0 { next }
  {
    subj = substr($0, length($1) + 2)
    type = ""
    if (match(subj, /^[A-Za-z]+(\([^)]*\))?!?:/)) {
      type = tolower(subj); sub(/[(!:].*/, "", type)
    }
    if (type != "" && (type in exc)) { excluded++; next }
    kind = (type != "" && (type in inc)) ? "included" : "unclassified"
    if (kind == "included") included++; else unclassified++
    lines[++count] = kind "\t" $1 "\t" subj
  }
  END {
    print "included_count=" included + 0
    print "unclassified_count=" unclassified + 0
    print "excluded_count=" excluded + 0
    print "---"
    for (i = 1; i <= count; i++) print lines[i]
  }'
