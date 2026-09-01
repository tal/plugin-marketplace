#!/usr/bin/env bash
set -euo pipefail

media_host=${PLEX_MEDIA_HOST:-synfeld}
media_root=${PLEX_MEDIA_ROOT:-/volume1/Media/Standup}
library_title=${PLEX_LIBRARY_TITLE:-Standup}
env_file=${PLEX_ENV_FILE:-/Users/tal/Projects/darr-manager/.env}

usage() {
  printf '%s\n' \
    'Usage:' \
    '  plex-standup-posters.sh inventory' \
    '  plex-standup-posters.sh scan' \
    '  plex-standup-posters.sh install LOCAL_POSTER REMOTE_VIDEO' \
    '  plex-standup-posters.sh verify REMOTE_VIDEO' \
    '  plex-standup-posters.sh actor RATING_KEY ACTOR_NAME'
}

die() {
  printf 'plex-standup-posters: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

remote_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

load_plex_env() {
  [[ -f "$env_file" ]] || die "credentials file not found: $env_file"
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
  [[ -n "${PLEX_URL:-}" && -n "${PLEX_TOKEN:-}" ]] \
    || die 'PLEX_URL and PLEX_TOKEN must be defined in the credentials file'
}

plex_json() {
  curl -fsS \
    -H 'Accept: application/json' \
    -H "X-Plex-Token: $PLEX_TOKEN" \
    "$PLEX_URL$1"
}

resolve_section_key() {
  if [[ -n "${PLEX_SECTION_KEY:-}" ]]; then
    printf '%s\n' "$PLEX_SECTION_KEY"
    return
  fi

  local matches
  matches=$(plex_json '/library/sections' \
    | jq -r --arg title "$library_title" \
      '.MediaContainer.Directory[] | select(.title == $title) | .key')
  [[ $(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ') == 1 ]] \
    || die "could not uniquely resolve Plex library: $library_title"
  printf '%s\n' "$matches"
}

youtube_id_from_path() {
  local path=$1
  local id
  id=$(printf '%s\n' "$path" | sed -nE 's/.*\[([A-Za-z0-9_-]{11})\].*/\1/p')
  [[ -n "$id" ]] || die "video path has no bracketed YouTube ID: $path"
  printf '%s\n' "$id"
}

validate_remote_video() {
  local video=$1
  local quoted_video
  [[ "$video" == "$media_root/"* ]] \
    || die "video is outside configured media root: $video"
  quoted_video=$(remote_quote "$video")
  # The shell-safe path is intentionally expanded into the remote command.
  # shellcheck disable=SC2029
  ssh "$media_host" "test -f $quoted_video" \
    || die "remote video does not exist: $video"
}

rating_key_for_video() {
  local section=$1
  local id=$2
  local keys
  keys=$(plex_json "/library/sections/$section/all" \
    | jq -r --arg needle "[$id]" '
        .MediaContainer.Metadata[]
        | select(any(.Media[]?.Part[]?; (.file // "") | contains($needle)))
        | .ratingKey
      ')
  [[ $(printf '%s\n' "$keys" | sed '/^$/d' | wc -l | tr -d ' ') == 1 ]] \
    || die "could not uniquely resolve Plex item for YouTube ID: $id"
  printf '%s\n' "$keys"
}

inventory() {
  require_command ssh
  local quoted_root
  quoted_root=$(remote_quote "$media_root")
  # The shell-safe media root is intentionally expanded into the remote command.
  # shellcheck disable=SC2029
  ssh "$media_host" "find $quoted_root -maxdepth 1 -type f" \
    | awk '
        BEGIN { IGNORECASE = 1 }
        /\[[A-Za-z0-9_-]{11}\].*\.(mp4|m4v|mkv|webm)$/ {
          videos[++count] = $0
          stem = $0
          sub(/\.[^.]+$/, "", stem)
          expected[count] = stem ".jpg"
          next
        }
        /\.jpg$/ { posters[$0] = 1 }
        END {
          for (i = 1; i <= count; i++) {
            if (!posters[expected[i]]) print videos[i]
          }
        }
      '
}

scan() {
  require_command curl
  require_command jq
  load_plex_env
  local section
  section=$(resolve_section_key)
  curl -fsS \
    -H "X-Plex-Token: $PLEX_TOKEN" \
    "$PLEX_URL/library/sections/$section/refresh" >/dev/null
  printf 'scan-started\tsection=%s\tlibrary=%s\n' "$section" "$library_title"
}

install() {
  [[ $# == 2 ]] || { usage >&2; exit 2; }
  require_command base64
  require_command curl
  require_command jq
  require_command magick
  require_command ssh

  local poster=$1
  local video=$2
  [[ -f "$poster" ]] || die "local poster not found: $poster"
  [[ $(magick identify -format '%wx%h' "$poster") == 1000x1500 ]] \
    || die "poster must be exactly 1000x1500: $poster"
  validate_remote_video "$video"
  load_plex_env

  local id section rating_key sidecar quoted_sidecar status selected
  id=$(youtube_id_from_path "$video")
  section=$(resolve_section_key)
  rating_key=$(rating_key_for_video "$section" "$id")
  sidecar=${video%.*}.jpg
  quoted_sidecar=$(remote_quote "$sidecar")

  # The shell-safe sidecar path is intentionally expanded into the remote command.
  # shellcheck disable=SC2029
  base64 < "$poster" \
    | ssh "$media_host" "base64 -d > $quoted_sidecar; chmod 664 $quoted_sidecar 2>/dev/null || true"

  status=$(curl -sS -o /dev/null -w '%{http_code}' \
    -X POST \
    -H 'Content-Type: image/jpeg' \
    -H "X-Plex-Token: $PLEX_TOKEN" \
    --data-binary "@$poster" \
    "$PLEX_URL/library/metadata/$rating_key/posters")
  [[ "$status" == 200 ]] \
    || die "Plex poster upload failed for ratingKey=$rating_key HTTP=$status"

  selected=$(plex_json "/library/metadata/$rating_key/posters" \
    | jq -r '.MediaContainer.Metadata[] | select(.selected == true) | .ratingKey')
  [[ "$selected" == upload://posters/* ]] \
    || die "uploaded poster is not selected for ratingKey=$rating_key"

  printf 'installed\tyoutube=%s\tratingKey=%s\tsidecar=%s\n' \
    "$id" "$rating_key" "$sidecar"
}

verify() {
  [[ $# == 1 ]] || { usage >&2; exit 2; }
  require_command curl
  require_command jq
  require_command magick
  require_command ssh

  local video=$1
  validate_remote_video "$video"
  load_plex_env

  local id section rating_key sidecar quoted_sidecar posters selected thumb downloaded dimensions
  id=$(youtube_id_from_path "$video")
  section=$(resolve_section_key)
  rating_key=$(rating_key_for_video "$section" "$id")
  sidecar=${video%.*}.jpg
  quoted_sidecar=$(remote_quote "$sidecar")
  # The shell-safe sidecar path is intentionally expanded into the remote command.
  # shellcheck disable=SC2029
  ssh "$media_host" "test -s $quoted_sidecar" \
    || die "sidecar does not exist or is empty: $sidecar"

  posters=$(plex_json "/library/metadata/$rating_key/posters")
  selected=$(jq -r \
    '.MediaContainer.Metadata[] | select(.selected == true) | .ratingKey' \
    <<< "$posters")
  thumb=$(jq -r \
    '.MediaContainer.Metadata[] | select(.selected == true) | .thumb' \
    <<< "$posters")
  [[ "$selected" == upload://posters/* ]] \
    || die "selected Plex poster is not an uploaded asset: $selected"

  downloaded=$(mktemp -t plex-standup-poster-XXXXXX.jpg)
  trap 'rm -f "$downloaded"' RETURN
  curl -fsS \
    -H "X-Plex-Token: $PLEX_TOKEN" \
    "$PLEX_URL$thumb" \
    -o "$downloaded"
  dimensions=$(magick identify -format '%wx%h' "$downloaded")
  [[ "$dimensions" == 1000x1500 ]] \
    || die "selected Plex poster has unexpected dimensions: $dimensions"

  printf 'verified\tyoutube=%s\tratingKey=%s\tdimensions=%s\n' \
    "$id" "$rating_key" "$dimensions"
}

actor() {
  [[ $# == 2 ]] || { usage >&2; exit 2; }
  require_command curl
  local rating_key=$1
  local actor_name=$2
  load_plex_env

  curl -fsS -X PUT -G \
    -H "X-Plex-Token: $PLEX_TOKEN" \
    --data-urlencode "actor[0].tag.tag=$actor_name" \
    --data-urlencode 'actor[0].order=0' \
    "$PLEX_URL/library/metadata/$rating_key" >/dev/null

  local selected
  selected=$(plex_json "/library/metadata/$rating_key" \
    | jq -r --arg actor "$actor_name" \
      '.MediaContainer.Metadata[0].Role[]? | select(.tag == $actor) | .tag' \
    | head -n 1)
  [[ "$selected" == "$actor_name" ]] \
    || die "actor was not added to ratingKey=$rating_key"
  printf 'actor-set\tratingKey=%s\tactor=%s\n' "$rating_key" "$actor_name"
}

case ${1:-} in
  inventory)
    [[ $# == 1 ]] || { usage >&2; exit 2; }
    inventory
    ;;
  scan)
    [[ $# == 1 ]] || { usage >&2; exit 2; }
    scan
    ;;
  install)
    shift
    install "$@"
    ;;
  verify)
    shift
    verify "$@"
    ;;
  actor)
    shift
    actor "$@"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
