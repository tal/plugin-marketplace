#!/usr/bin/env bash

# release-commit.sh — make the isolated version-bump commit for a deploy.
#
# Usage: release-commit.sh --target <t> --channel <c> --version <v>
#                          [--subject <template>] [--trailer <template>]...
#                          [--expect <glob>]...
#
#   --subject   Default: chore(build): ship {version} [{channel}]
#   --trailer   Repeatable. Default (when none given):
#               Deploy-Target: {target} / Deploy-Channel: {channel}
#   --expect    Repeatable shell glob (`*` crosses `/`). When given, every
#               changed file must match one, or nothing is committed.
#
# Precondition (the caller's job): the tree was clean before the target bumped
# the version, so the only tracked modifications are the bump. Stages them with
# `git add -u` — untracked files are never committed, only counted.
#
# Prints key=value: status, commit, one file=<path> per committed file, untracked
# Exit: 0 committed | 1 refused | 3 nothing to commit (no bump commit needed) | 64 usage

set -euo pipefail

usage() {
  echo "usage: release-commit.sh --target <t> --channel <c> --version <v> [--subject <tpl>] [--trailer <tpl>]... [--expect <glob>]..." >&2
  exit 64
}

TARGET=""
CHANNEL=""
VERSION=""
SUBJECT='chore(build): ship {version} [{channel}]'
TRAILERS=()
EXPECTS=()
while [ $# -gt 0 ]; do
  case $1 in
    --target) [ $# -ge 2 ] || usage; TARGET=$2; shift 2 ;;
    --channel) [ $# -ge 2 ] || usage; CHANNEL=$2; shift 2 ;;
    --version) [ $# -ge 2 ] || usage; VERSION=$2; shift 2 ;;
    --subject) [ $# -ge 2 ] || usage; SUBJECT=$2; shift 2 ;;
    --trailer) [ $# -ge 2 ] || usage; TRAILERS+=("$2"); shift 2 ;;
    --expect) [ $# -ge 2 ] || usage; EXPECTS+=("$2"); shift 2 ;;
    -h|--help) usage ;;
    *) echo "release-commit: unknown argument: $1" >&2; usage ;;
  esac
done
if [ -z "$TARGET" ] || [ -z "$CHANNEL" ] || [ -z "$VERSION" ]; then usage; fi
git rev-parse --git-dir >/dev/null 2>&1 || { echo "release-commit: not inside a git repository" >&2; exit 64; }
TOP=$(git rev-parse --show-toplevel)
[ ${#TRAILERS[@]} -gt 0 ] || TRAILERS=('Deploy-Target: {target}' 'Deploy-Channel: {channel}')

# Replace {target} {channel} {version}. Prefix/suffix splitting rather than
# ${s//…/…} so `&` and `\` in values survive bash 5.2's patsub_replacement.
render() {
  local s=$1 out key val
  for key in target channel version; do
    case $key in target) val=$TARGET ;; channel) val=$CHANNEL ;; version) val=$VERSION ;; esac
    out=""
    while :; do
      case $s in
        *"{$key}"*) out="$out${s%%"{$key}"*}$val"; s=${s#*"{$key}"} ;;
        *) out="$out$s"; break ;;
      esac
    done
    s=$out
  done
  printf '%s' "$s"
}

# Anything already staged that `git add -u` would not produce (new, copied or
# renamed paths) means someone else's work is in the index. Don't sweep it in.
PRESTAGED=$(git -C "$TOP" diff --cached --name-only --diff-filter=ACR)
if [ -n "$PRESTAGED" ]; then
  echo "release-commit: refusing — new files are already staged, so this would not be an isolated bump commit:" >&2
  printf '%s\n' "$PRESTAGED" | sed 's/^/  /' >&2
  echo "status=refused"
  exit 1
fi

git -C "$TOP" add -u
CHANGED=$(git -C "$TOP" diff --cached --name-only)
UNTRACKED=$(git -C "$TOP" ls-files --others --exclude-standard | wc -l | tr -d ' ')

if [ -z "$CHANGED" ]; then
  echo "status=nothing-to-commit"
  echo "untracked=$UNTRACKED"
  exit 3
fi

if [ ${#EXPECTS[@]} -gt 0 ]; then
  UNEXPECTED=""
  while IFS= read -r f; do
    hit=0
    for g in "${EXPECTS[@]}"; do
      # shellcheck disable=SC2254 # $g is deliberately a glob
      case $f in $g) hit=1; break ;; esac
    done
    [ "$hit" -eq 1 ] || UNEXPECTED="$UNEXPECTED$f"$'\n'
  done <<<"$CHANGED"
  if [ -n "$UNEXPECTED" ]; then
    git -C "$TOP" reset -q
    echo "release-commit: refusing — these changed files match no --expect glob (index reset, worktree untouched):" >&2
    printf '%s' "$UNEXPECTED" | sed 's/^/  /' >&2
    echo "status=refused"
    printf '%s' "$UNEXPECTED" | sed 's/^/unexpected=/'
    exit 1
  fi
fi

{
  render "$SUBJECT"
  printf '\n\n'
  for t in "${TRAILERS[@]}"; do render "$t"; printf '\n'; done
} | git -C "$TOP" commit -q -F -

echo "status=committed"
echo "commit=$(git -C "$TOP" rev-parse HEAD)"
printf '%s\n' "$CHANGED" | sed 's/^/file=/'
echo "untracked=$UNTRACKED"
