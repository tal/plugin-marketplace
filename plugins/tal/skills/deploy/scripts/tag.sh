#!/usr/bin/env bash

# tag.sh — create the annotated ("hard") release tag for a deploy.
#
# Usage: tag.sh --name <tag> --commit <rev> --message-file <path> [--remote <name>]
#
#   --message-file  Annotation body: target, channel, version, artifact id,
#                   What's New. Must not be empty.
#   --remote        Also push this one tag ref there (never --force).
#
# Guarantees, enforced here so they hold even if the caller is confused:
#   - No tag from a dirty working tree (staged, unstaged tracked, or untracked
#     non-ignored changes). Every tag names a real, reproducible commit.
#   - Tags are immutable: an existing tag (local, or on --remote) is never
#     moved, replaced or deleted.
#
# Prints key=value: tag, commit, pushed (<remote>|no|failed)
# Exit: 0 ok | 1 dirty tree | 2 tag already exists | 3 remote check or push
#       failed (a local tag created before a failed push is kept) | 64 usage

set -euo pipefail

usage() {
  echo "usage: tag.sh --name <tag> --commit <rev> --message-file <path> [--remote <name>]" >&2
  exit 64
}

NAME=""
COMMIT=""
MSG_FILE=""
REMOTE=""
while [ $# -gt 0 ]; do
  case $1 in
    --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
    --commit) [ $# -ge 2 ] || usage; COMMIT=$2; shift 2 ;;
    --message-file) [ $# -ge 2 ] || usage; MSG_FILE=$2; shift 2 ;;
    --remote) [ $# -ge 2 ] || usage; REMOTE=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "tag: unknown argument: $1" >&2; usage ;;
  esac
done
if [ -z "$NAME" ] || [ -z "$COMMIT" ] || [ -z "$MSG_FILE" ]; then usage; fi
git rev-parse --git-dir >/dev/null 2>&1 || { echo "tag: not inside a git repository" >&2; exit 64; }
TOP=$(git rev-parse --show-toplevel)

git check-ref-format "refs/tags/$NAME" || { echo "tag: invalid tag name: $NAME" >&2; exit 64; }
SHA=$(git rev-parse -q --verify "$COMMIT^{commit}") || { echo "tag: unknown commit: $COMMIT" >&2; exit 64; }
if [ ! -f "$MSG_FILE" ] || ! grep -q '[^[:space:]]' "$MSG_FILE"; then
  echo "tag: message file is missing or empty: $MSG_FILE" >&2
  exit 64
fi

PORCELAIN=$(git -C "$TOP" status --porcelain=v1 --untracked-files=normal)
if [ -n "$PORCELAIN" ]; then
  echo "tag: refusing — working tree is dirty. No tag without a clean tree:" >&2
  printf '%s\n' "$PORCELAIN" | sed 's/^/  /' >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$NAME" >/dev/null; then
  echo "tag: refusing — $NAME already exists locally (at $(git rev-parse --short "$NAME^{commit}")). Tags are never moved." >&2
  exit 2
fi
if [ -n "$REMOTE" ]; then
  if ! REMOTE_HIT=$(git ls-remote --tags "$REMOTE" "refs/tags/$NAME"); then
    echo "tag: could not reach remote $REMOTE to check for $NAME; nothing created" >&2
    exit 3
  fi
  if [ -n "$REMOTE_HIT" ]; then
    echo "tag: refusing — $NAME already exists on $REMOTE. Tags are never moved." >&2
    exit 2
  fi
fi

git tag -a "$NAME" "$SHA" -F "$MSG_FILE"

PUSHED=no
if [ -n "$REMOTE" ]; then
  if git push --quiet "$REMOTE" "refs/tags/$NAME:refs/tags/$NAME"; then
    PUSHED=$REMOTE
  else
    echo "tag: created $NAME locally but pushing it to $REMOTE failed; retry with: git push $REMOTE refs/tags/$NAME" >&2
    echo "tag=$NAME"
    echo "commit=$SHA"
    echo "pushed=failed"
    exit 3
  fi
fi

echo "tag=$NAME"
echo "commit=$SHA"
echo "pushed=$PUSHED"
