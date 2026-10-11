#!/usr/bin/env bash

# signing-identities.sh — can this Mac sign for a team, and for how long?
#
# Usage: signing-identities.sh [--team <TEAM_ID>] [--kind distribution|development|all]
#                              [--warn-days <n>] [--asc-certs <file>]
#
#   --team       Only identities whose certificate subject OU is this team id.
#                The "(XXXXXXXXXX)" in an identity's name is the person's id,
#                not the team, so it is never used for matching.
#   --kind       distribution (default): Apple Distribution / iPhone Distribution.
#                development: Apple Development / iPhone Developer.
#                all: every code-signing identity.
#   --warn-days  An identity expiring within this many days is `expiring`.
#                Default 30.
#   --asc-certs  A saved ASC response of
#                GET /v1/certificates?fields[certificates]=serialNumber,expirationDate,certificateType,displayName&limit=200
#                Local certs are matched to it by serial number. A revoked
#                cert disappears from that list.
#
# macOS only (`security`, BSD `date`). Read-only: lists keychain identities
# and reads their public certificates. It never creates, imports or deletes
# anything, and never touches private keys.
#
# Identities come from `security find-identity -p codesigning` without `-v`,
# so expired and revoked ones are listed too, deduped by SHA-1.
#
# status: valid | expiring (≤ --warn-days) | expired | revoked |
#         untrusted (any other CSSMERR_* reason from find-identity)
# asc:    listed | missing (not on ASC: revoked or deleted there) |
#         unchecked (no --asc-certs)
# usable = status valid or expiring AND asc not missing. A `missing` identity
# keeps its status but is never counted in usable or picked as best.
#
# Output: team, kind, identities (matching team + kind), usable, best (sha1
# of the usable identity with the latest not_after, or -), best_days_left,
# a `---` line, then TSV with a header row:
#   sha1  status  not_after  days_left  serial  team  asc  name
# not_after is YYYY-MM-DD (UTC). days_left is negative once expired.
#
# Exit: 0 at least one usable | 1 none usable | 3 not macOS, or no
#       `security` / `openssl` (or no `jq` with --asc-certs) | 64 usage

set -euo pipefail

usage() {
  echo "usage: signing-identities.sh [--team <TEAM_ID>] [--kind distribution|development|all] [--warn-days <n>] [--asc-certs <file>]" >&2
  exit 64
}

team=""
kind="distribution"
warn_days=30
asc_file=""

while [ $# -gt 0 ]; do
  case "$1" in
    --team) [ $# -ge 2 ] || usage; team="$2"; shift 2 ;;
    --kind) [ $# -ge 2 ] || usage; kind="$2"; shift 2 ;;
    --warn-days) [ $# -ge 2 ] || usage; warn_days="$2"; shift 2 ;;
    --asc-certs) [ $# -ge 2 ] || usage; asc_file="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "signing-identities: unknown argument: $1" >&2; usage ;;
  esac
done

case "$kind" in
  distribution|development|all) ;;
  *) echo "signing-identities: --kind must be distribution, development or all" >&2; usage ;;
esac
[[ "$warn_days" =~ ^[0-9]+$ ]] || { echo "signing-identities: --warn-days must be a whole number" >&2; usage; }

if [ "$(uname -s)" != "Darwin" ] || ! command -v security >/dev/null 2>&1; then
  echo "signing-identities: macOS only (needs \`security\`)" >&2
  exit 3
fi
command -v openssl >/dev/null 2>&1 || { echo "signing-identities: needs openssl" >&2; exit 3; }

if [ -n "$asc_file" ]; then
  command -v jq >/dev/null 2>&1 || { echo "signing-identities: --asc-certs needs jq" >&2; exit 3; }
  [ -r "$asc_file" ] || { echo "signing-identities: can't read $asc_file" >&2; usage; }
  jq -e '.data | type == "array"' "$asc_file" >/dev/null 2>&1 \
    || { echo "signing-identities: $asc_file is not an ASC /v1/certificates response (.data array)" >&2; usage; }
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/signing-identities.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# Serial numbers on ASC, normalized: uppercase hex, no leading zeros.
asc_serials="$tmp/asc-serials"
: > "$asc_serials"
if [ -n "$asc_file" ]; then
  jq -r '.data[].attributes.serialNumber // empty | ascii_upcase | sub("^0+"; "")' "$asc_file" > "$asc_serials"
fi

# Every certificate in the search list, one PEM file per SHA-1. Only public
# certificates; find-certificate never returns private keys.
security find-certificate -a -Z -p 2>/dev/null | awk -v dir="$tmp" '
  /^SHA-1 hash:/ { h = $3; next }
  /-----BEGIN CERTIFICATE-----/ { if (h != "") { f = dir "/" h ".pem"; p = 1 } }
  p { print > f }
  /-----END CERTIFICATE-----/ { if (p) { close(f) }; p = 0; h = "" }
'

# `<sha1>\t<name>\t<reason or empty>`, first occurrence of each SHA-1 only.
# The "Matching identities" section comes first and carries the reasons.
security find-identity -p codesigning 2>/dev/null | awk '
  /^ *[0-9]+\) [0-9A-F]+ "/ && length($2) == 40 {
    sha = $2
    if (seen[sha]++) next
    line = $0
    start = index(line, "\"")
    rest = substr(line, start + 1)
    end = index(rest, "\"")
    name = substr(rest, 1, end - 1)
    reason = substr(rest, end + 1)
    gsub(/^[ (]+|[ )]+$/, "", reason)
    printf "%s\t%s\t%s\n", sha, name, reason
  }
' > "$tmp/identities"

now=$(date -u +%s)
rows="$tmp/rows"
: > "$rows"
count=0
usable=0
best="-"
best_days="-"
best_epoch=0

while IFS="$(printf '\t')" read -r sha name reason; do
  [ -n "$sha" ] || continue

  case "$kind" in
    distribution)
      case "$name" in "Apple Distribution:"*|"iPhone Distribution:"*) ;; *) continue ;; esac ;;
    development)
      case "$name" in "Apple Development:"*|"iPhone Developer:"*) ;; *) continue ;; esac ;;
  esac

  pem="$tmp/$sha.pem"
  cert_team="-"
  serial="-"
  not_after="-"
  days="-"
  epoch=""
  if [ -s "$pem" ]; then
    info=$(openssl x509 -in "$pem" -noout -enddate -serial -subject -nameopt sep_multiline 2>/dev/null || true)
    ou=$(printf '%s\n' "$info" | sed -n 's/^ *OU=//p' | head -n1)
    [ -n "$ou" ] && cert_team="$ou"
    s=$(printf '%s\n' "$info" | sed -n 's/^serial=//p' | head -n1 | tr 'a-f' 'A-F' | sed 's/^0*//')
    [ -n "$s" ] && serial="$s"
    end=$(printf '%s\n' "$info" | sed -n 's/^notAfter=//p' | head -n1)
    if [ -n "$end" ]; then
      epoch=$(date -j -u -f '%b %d %T %Y %Z' "$end" +%s 2>/dev/null || true)
      if [ -n "$epoch" ]; then
        not_after=$(date -j -u -r "$epoch" +%F)
        diff=$((epoch - now))
        if [ "$diff" -ge 0 ]; then
          days=$((diff / 86400))
        else
          days=$(( -((-diff + 86399) / 86400) ))
        fi
      fi
    fi
  fi

  if [ -n "$team" ] && [ "$cert_team" != "$team" ]; then
    continue
  fi

  case "$reason" in
    "") status="valid" ;;
    *CSSMERR_TP_CERT_EXPIRED*) status="expired" ;;
    *CSSMERR_TP_CERT_REVOKED*) status="revoked" ;;
    *) status="untrusted" ;;
  esac
  if [ "$status" = "valid" ] && [ "$days" != "-" ]; then
    if [ "$days" -lt 0 ]; then
      status="expired"
    elif [ "$days" -le "$warn_days" ]; then
      status="expiring"
    fi
  fi

  asc="unchecked"
  if [ -n "$asc_file" ]; then
    if [ "$serial" != "-" ] && grep -qx "$serial" "$asc_serials"; then
      asc="listed"
    else
      asc="missing"
    fi
  fi

  count=$((count + 1))
  case "$status" in
    valid|expiring)
      if [ "$asc" != "missing" ]; then
        usable=$((usable + 1))
        if [ -n "$epoch" ] && [ "$epoch" -gt "$best_epoch" ]; then
          best_epoch="$epoch"
          best="$sha"
          best_days="$days"
        elif [ "$best" = "-" ]; then
          best="$sha"
        fi
      fi
      ;;
  esac

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$sha" "$status" "$not_after" "$days" "$serial" "$cert_team" "$asc" "$name" >> "$rows"
done < "$tmp/identities"

echo "team=${team:--}"
echo "kind=$kind"
echo "identities=$count"
echo "usable=$usable"
echo "best=$best"
echo "best_days_left=$best_days"
echo "---"
printf 'sha1\tstatus\tnot_after\tdays_left\tserial\tteam\tasc\tname\n'
cat "$rows"

[ "$usable" -gt 0 ]
