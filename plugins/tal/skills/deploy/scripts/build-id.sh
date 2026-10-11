#!/usr/bin/env bash

# build-id.sh — make the next version / build id for a deploy target.
#
# Usage: build-id.sh --scheme timestamp-dotted|semver|git-sha --target <t>
#                    [--tag-pattern <p>] [--bump patch|minor|major] [--current <v>]
#
#   timestamp-dotted  YYYY.M.D.H.MM (month/day/hour unpadded, minutes padded),
#                     e.g. 2026.10.3.14.08
#   semver            --current, else the highest semver among this target's
#                     tags, bumped by --bump (default patch)
#   git-sha           `git rev-parse --short=12 HEAD`; nothing is compared
#
# Existing versions come from tags matching --tag-pattern (default
# builds/{target}/{channel}/{version}, any channel). For timestamp-dotted and
# semver the new id must be strictly greater than every dotted-numeric one,
# compared as INTEGER TUPLES split on dots. A stray non-dotted build like
# `20260404` tuple-dominates every `2026.M.D...` build and TestFlight then
# treats the dotted builds as "older" — this refuses rather than ship behind it.
#
# Prints key=value: version, previous (<max>|none|-), scheme
# Exit: 0 ok | 1 refused (not greater / no base version) | 64 usage

set -euo pipefail

usage() {
  echo "usage: build-id.sh --scheme timestamp-dotted|semver|git-sha --target <t> [--tag-pattern <p>] [--bump patch|minor|major] [--current <v>]" >&2
  exit 64
}

SCHEME=""
TARGET=""
PATTERN="builds/{target}/{channel}/{version}"
BUMP="patch"
CURRENT=""
while [ $# -gt 0 ]; do
  case $1 in
    --scheme) [ $# -ge 2 ] || usage; SCHEME=$2; shift 2 ;;
    --target) [ $# -ge 2 ] || usage; TARGET=$2; shift 2 ;;
    --tag-pattern) [ $# -ge 2 ] || usage; PATTERN=$2; shift 2 ;;
    --bump) [ $# -ge 2 ] || usage; BUMP=$2; shift 2 ;;
    --current) [ $# -ge 2 ] || usage; CURRENT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "build-id: unknown argument: $1" >&2; usage ;;
  esac
done
[ -n "$TARGET" ] || usage
case $SCHEME in timestamp-dotted|semver|git-sha) ;; *) usage ;; esac
case $BUMP in patch|minor|major) ;; *) usage ;; esac
case $PATTERN in *'{version}'*) ;; *) echo "build-id: --tag-pattern must contain {version}" >&2; exit 64 ;; esac
git rev-parse --git-dir >/dev/null 2>&1 || { echo "build-id: not inside a git repository" >&2; exit 64; }

DOTTED_RE='^[0-9]+(\.[0-9]+)*$'

ere_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/[].(){}*+?^$|[]/\\&/g'; }

# Turn the tag pattern into an anchored ERE whose only group captures {version}.
pattern_regex() {
  local p=$1 out=""
  while [ -n "$p" ]; do
    case $p in
      '{target}'*) out="$out$(ere_escape "$TARGET")"; p=${p#'{target}'} ;;
      '{channel}'*) out="${out}[^/]+"; p=${p#'{channel}'} ;;
      '{version}'*) out="$out(.+)"; p=${p#'{version}'} ;;
      *) out="$out$(ere_escape "${p:0:1}")"; p=${p:1} ;;
    esac
  done
  printf '^%s$' "$out"
}

# tuple_cmp a b → prints -1, 0 or 1. Missing components count as 0.
tuple_cmp() {
  local IFS=.
  local -a a b
  read -r -a a <<<"$1"
  read -r -a b <<<"$2"
  local n=${#a[@]} i x y
  [ ${#b[@]} -gt "$n" ] && n=${#b[@]}
  for ((i = 0; i < n; i++)); do
    x=$((10#${a[i]:-0}))
    y=$((10#${b[i]:-0}))
    if [ "$x" -lt "$y" ]; then echo -1; return; fi
    if [ "$x" -gt "$y" ]; then echo 1; return; fi
  done
  echo 0
}

# Highest dotted-numeric version among this target's tags (leading v stripped).
# Tags are read into a variable first so a git failure aborts under set -e
# instead of silently yielding "no previous version" and skipping the guard.
existing_max() {
  local re tags tag v max=""
  re=$(pattern_regex "$PATTERN")
  tags=$(git tag --list)
  while IFS= read -r tag; do
    [[ $tag =~ $re ]] || continue
    v=${BASH_REMATCH[1]#v}
    [[ $v =~ $DOTTED_RE ]] || continue
    if [ -z "$max" ] || [ "$(tuple_cmp "$v" "$max")" = 1 ]; then max=$v; fi
  done <<<"$tags"
  printf '%s' "$max"
}

if [ "$SCHEME" = git-sha ]; then
  echo "version=$(git rev-parse --short=12 HEAD)"
  echo "previous=-"
  echo "scheme=$SCHEME"
  exit 0
fi

MAX=$(existing_max)

case $SCHEME in
  timestamp-dotted)
    read -r Y M D H MIN <<<"$(date '+%Y %m %d %H %M')"
    VERSION="$Y.$((10#$M)).$((10#$D)).$((10#$H)).$MIN"
    ;;
  semver)
    BASE=${CURRENT#v}
    [ -n "$BASE" ] || BASE=$MAX
    if [ -z "$BASE" ]; then
      echo "build-id: no existing semver tags for target '$TARGET'; pass --current <version>" >&2
      exit 1
    fi
    [[ $BASE =~ $DOTTED_RE ]] || { echo "build-id: current version '$BASE' is not dotted-numeric" >&2; exit 1; }
    IFS=. read -r MAJ MIN_ PAT _ <<<"$BASE"
    MAJ=$((10#${MAJ:-0})); MIN_=$((10#${MIN_:-0})); PAT=$((10#${PAT:-0}))
    case $BUMP in
      major) VERSION="$((MAJ + 1)).0.0" ;;
      minor) VERSION="$MAJ.$((MIN_ + 1)).0" ;;
      patch) VERSION="$MAJ.$MIN_.$((PAT + 1))" ;;
    esac
    ;;
esac

if [ -n "$MAX" ] && [ "$(tuple_cmp "$VERSION" "$MAX")" != 1 ]; then
  echo "build-id: new version $VERSION is not greater than existing $MAX (integer-tuple compare on dots)." >&2
  echo "build-id: a non-dotted or future-dated tag for '$TARGET' outranks it; fix that before shipping." >&2
  exit 1
fi

echo "version=$VERSION"
echo "previous=${MAX:-none}"
echo "scheme=$SCHEME"
