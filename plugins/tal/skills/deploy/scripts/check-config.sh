#!/usr/bin/env bash

# check-config.sh — load and validate a repo's .config/deploy.yml.
#
# Usage: check-config.sh [--file <path>] [--format kv|json]
#
#   --file <path>   Default: <repo top level>/.config/deploy.yml.
#   --format        kv (default) or json.
#
# Read-only. YAML is parsed by ruby (Psych), else python3 + PyYAML, then
# validated with jq. Checks: top-level keys that are neither generic keys nor
# maps (typos), version_scheme / unpushed_policy enums at any depth, booleans
# anywhere (use string enums), a `dirty` key anywhere, a target block or
# pipeline named `config` or `doctor` (reserved), `channels` shape and duplicates, pipeline
# steps (`target:channel`, known target, known channel), secret-looking keys
# (`*token`, `*secret`, `*password`) and inline `-----BEGIN` key material.
#
# kv output, one key=value per line:
#   file, status (ok|missing|invalid), parser (ruby|python3; absent when missing),
#   target=<name>[ <channel> …]      one per target block, channels in file
#                                    order; no channels declared → name only
#   pipeline=<name> <target:channel> …   one per pipeline
#   error=<message>, warning=<message>   repeated
# json output: {file, status, parser, targets: [{name, channels: [..] | null}],
#   pipelines: {..}, errors: [..], warnings: [..], config: <parsed> | null}
#
# An empty file or a null document is an empty config ({}), which is ok.
#
# Exit: 0 ok (warnings allowed) or file missing | 1 invalid | 2 no YAML parser
#       (or no jq) | 64 usage

set -euo pipefail

usage() {
  echo "usage: check-config.sh [--file <path>] [--format kv|json]" >&2
  exit 64
}

FILE=""
FORMAT=kv
while [ $# -gt 0 ]; do
  case $1 in
    --file) [ $# -ge 2 ] || usage; FILE=$2; shift 2 ;;
    --format) [ $# -ge 2 ] || usage; FORMAT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "check-config: unknown argument: $1" >&2; usage ;;
  esac
done
case $FORMAT in kv|json) ;; *) echo "check-config: --format must be kv or json" >&2; usage ;; esac

if [ -z "$FILE" ]; then
  TOP=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "check-config: not inside a git repository; pass --file" >&2; exit 64; }
  FILE="$TOP/.config/deploy.yml"
fi

command -v jq >/dev/null 2>&1 || { echo "check-config: jq is required" >&2; exit 2; }

emit() {
  # $1 = result JSON (the object described in the header)
  if [ "$FORMAT" = json ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$1" | jq -r '
      def oneline: gsub("[\r\n]+"; " ");
      "file=\(.file)",
      "status=\(.status)",
      (if .parser then "parser=\(.parser)" else empty end),
      (.targets[] | "target=" + ([.name] + (.channels // []) | join(" "))),
      (.pipelines | to_entries[] | "pipeline=" + ([.key] + (.value | map(if type == "string" then . else tojson end)) | join(" "))),
      (.errors[] | "error=" + oneline),
      (.warnings[] | "warning=" + oneline)'
  fi
}

if [ ! -e "$FILE" ]; then
  emit "$(jq -cn --arg file "$FILE" \
    '{file: $file, status: "missing", parser: null, targets: [], pipelines: {}, errors: [], warnings: [], config: null}')"
  exit 0
fi
[ -f "$FILE" ] && [ -r "$FILE" ] || { echo "check-config: not a readable file: $FILE" >&2; exit 64; }

# YAML → JSON. Dates/times become ISO strings, non-string keys become strings,
# non-finite floats become strings, and an empty or null document becomes {}.
RUBY_PARSE='
require "yaml"; require "json"; require "date"; require "time"
def key(k)
  return "null" if k.nil?
  k.is_a?(String) ? k : conv(k).to_s
end
def conv(o)
  case o
  when Hash then o.each_with_object({}) { |(k, v), h| h[key(k)] = conv(v) }
  when Array then o.map { |x| conv(x) }
  when Time then o.strftime("%Y-%m-%dT%H:%M:%S%:z")
  when Date then o.iso8601
  when Float then o.finite? ? o : o.to_s
  else o
  end
end
path = ARGV[0]
src = File.read(path, encoding: "UTF-8")
begin
  data = begin
    YAML.safe_load(src, permitted_classes: [Date, Time], aliases: true, filename: path)
  rescue ArgumentError
    YAML.safe_load(src, [Date, Time], [], true, path)  # Psych < 3.1
  end
rescue Psych::Exception => e
  warn e.message
  exit 3
end
data = {} if data.nil?
puts JSON.generate(conv(data))
'
PYTHON_PARSE='
import datetime, json, math, sys
import yaml
def key(k):
    if k is None: return "null"
    if isinstance(k, bool): return "true" if k else "false"
    return k if isinstance(k, str) else str(conv(k))
def conv(o):
    if isinstance(o, dict): return {key(k): conv(v) for k, v in o.items()}
    if isinstance(o, list): return [conv(x) for x in o]
    if isinstance(o, (datetime.date, datetime.datetime)): return o.isoformat()
    if isinstance(o, float) and not math.isfinite(o): return str(o)
    return o
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = yaml.safe_load(f)
except yaml.YAMLError as e:
    print(str(e), file=sys.stderr)
    sys.exit(3)
print(json.dumps(conv({} if data is None else data)))
'

PARSER=""
if command -v ruby >/dev/null 2>&1 && ruby -ryaml -rjson -e 1 >/dev/null 2>&1; then
  PARSER=ruby
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  PARSER=python3
else
  echo "check-config: no YAML parser; needs ruby (with psych) or python3 with PyYAML" >&2
  exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/check-config.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# The parsers exit 3 on a YAML error; any other failure is the parser itself.
PARSE_RC=0
if [ "$PARSER" = ruby ]; then
  ruby -e "$RUBY_PARSE" "$FILE" >"$TMP/config.json" 2>"$TMP/err" || PARSE_RC=$?
else
  python3 -c "$PYTHON_PARSE" "$FILE" >"$TMP/config.json" 2>"$TMP/err" || PARSE_RC=$?
fi

if [ "$PARSE_RC" -ne 0 ]; then
  MSG=$(tr '\n' ' ' <"$TMP/err" | sed 's/  */ /g; s/ $//')
  if [ "$PARSE_RC" -eq 3 ]; then KIND="YAML parse error"; else KIND="$PARSER failed converting YAML to JSON"; fi
  RESULT=$(jq -cn --arg file "$FILE" --arg parser "$PARSER" --arg msg "$KIND: ${MSG:-unknown error}" \
    '{file: $file, status: "invalid", parser: $parser, targets: [], pipelines: {}, errors: [$msg], warnings: [], config: null}')
else
  RESULT=$(jq -c --arg file "$FILE" --arg parser "$PARSER" '
    def G: "branch", "version_scheme", "tag_pattern", "bump_commit", "bump_trailers",
      "changelog_dir", "changelog_pattern", "changelog_commit", "release_notes_source",
      "unpushed_policy", "confirm_before", "pipelines";
    def fmtpath: reduce .[] as $p (""; if ($p | type) == "number" then . + "[\($p)]" elif . == "" then $p else . + "." + $p end);
    def chan_names: if type == "array" then [.[] | select(type == "string")] elif type == "object" then keys_unsorted else null end;
    def err: {level: "error", msg: .};
    def warn: {level: "warning", msg: .};
    def secretish: ascii_downcase | test("(token|secret|password)$");
    def enum_check($c; $name; $allowed):
      $c | paths as $p | select(($p[-1]) == $name) | getpath($p) as $v
      | select(($v | type) != "boolean")  # already reported as a boolean
      | select(($v | type) != "string" or ($v | IN($allowed[]) | not))
      | "`\($p | fmtpath)` is \($v | tojson); must be one of \($allowed | join(" / "))" | err;

    . as $c
    | if ($c | type) != "object" then
        {file: $file, status: "invalid", parser: $parser, targets: [], pipelines: {}, warnings: [], config: $c,
         errors: ["top level must be a map of keys, got \($c | type)"]}
      else
        ($c | to_entries | map(select(.key | IN(G) | not))) as $nongeneric
        | ($nongeneric | map(select(.value | type == "object"))) as $blocks
        | ($blocks | map(.key)) as $tnames
        | ($blocks | map({key: .key, value: (.value.channels | chan_names)}) | from_entries) as $chans
        | (if ($c.pipelines | type) == "object" then $c.pipelines else {} end) as $pl
        | [
            ($nongeneric[] | select(.value | type != "object")
              | select(.key != "dirty" and (.key | secretish | not))  # reported more specifically below
              | "unknown top-level key `\(.key)` (not a generic key, and not a map so not a target block)" | err),
            ($tnames[] | select(. == "config" or . == "doctor")
              | "target block `\(.)`: the name is reserved for `/deploy \(.)`; rename it" | err),
            ($c | paths(type == "boolean") as $p
              | "boolean at `\($p | fmtpath)`: use a string enum (YAML 1.1 also reads yes/no/on/off as booleans; quote them)" | err),
            enum_check($c; "version_scheme"; ["timestamp-dotted", "semver", "git-sha"]),
            enum_check($c; "unpushed_policy"; ["push", "ask", "refuse"]),
            ($c | paths | select(.[-1] == "dirty")
              | "`\(fmtpath)`: dirty is per-run only (`--dirty`), never a deploy.yml key" | err),
            ($blocks[] | .key as $t | .value | select(has("channels")) | .channels as $ch
              | if ($ch | type) == "array" then
                  ($ch | to_entries[] | select(.value | type != "string")
                    | "`\($t).channels[\(.key)]` must be a channel name, got \(.value | tojson)" | err),
                  ([$ch[] | select(type == "string")] | group_by(.) | map(select(length > 1) | .[0])[]
                    | "duplicate channel `\(.)` in `\($t).channels`" | err)
                elif ($ch | type) == "object" then
                  ($ch | to_entries[] | select(.value | type != "object" and type != "null")
                    | "`\($t).channels.\(.key)` must be a map of overrides (or empty), got \(.value | tojson)" | err)
                else
                  "`\($t).channels` must be a list of names or a map, got \($ch | tojson)" | err
                end),
            (if ($c | has("pipelines")) and ($c.pipelines | type) != "object" then
               "`pipelines` must be a map of name → [target:channel, …], got \($c.pipelines | tojson)" | err
             else empty end),
            ($pl | to_entries[] | .key as $n | .value as $steps
              | (if $n == "config" or $n == "doctor" then "pipeline `\($n)`: the name is reserved for `/deploy \($n)`; rename it" | err else empty end),
                (if ($n | IN($tnames[])) then "pipeline `\($n)` has the same name as a target block" | err else empty end),
                (if ($steps | type) != "array" or ($steps | length) == 0 then
                   "pipeline `\($n)` must be a non-empty list of target:channel steps" | err
                 else
                   $steps[] as $s
                   | if ($s | type) != "string" or ($s | test("^[^:\\s]+:[^:\\s]+$") | not) then
                       "pipeline `\($n)` step \($s | tojson) is not target:channel" | err
                     else
                       ($s | split(":")) as [$t, $ch]
                       | if ($t | IN($tnames[]) | not) then
                           "pipeline `\($n)` step `\($s)`: no target block `\($t)`" | err
                         elif $chans[$t] == null then
                           "pipeline `\($n)` step `\($s)`: `\($t)` declares no channels here, so `\($ch)` must be in targets/\($t).md" | warn
                         elif ($ch | IN($chans[$t][]) | not) then
                           "pipeline `\($n)` step `\($s)`: `\($t)` has no channel `\($ch)` (has: \($chans[$t] | join(", ")))" | err
                         else empty end
                     end
                 end)),
            ($c | paths as $p | select(($p[-1] | type) == "string")
              | select($p[-1] | secretish)
              | "secret-looking key `\($p | fmtpath)`: store the env var name under `\($p[-1])_env` instead, never the value" | err),
            ($c | paths(type == "string") as $p | select($c | getpath($p) | contains("-----BEGIN"))
              | "`\($p | fmtpath)` holds inline key material (-----BEGIN …); reference a key path instead" | err)
          ] as $findings
        | ([$findings[] | select(.level == "error") | .msg]) as $errors
        | {file: $file,
           status: (if ($errors | length) > 0 then "invalid" else "ok" end),
           parser: $parser,
           targets: [$blocks[] | {name: .key, channels: $chans[.key]}],
           pipelines: ($pl | map_values(if type == "array" then . else [] end)),
           errors: $errors,
           warnings: [$findings[] | select(.level == "warning") | .msg],
           config: $c}
      end' "$TMP/config.json")
fi

emit "$RESULT"

N=$(printf '%s\n' "$RESULT" | jq '.errors | length')
if [ "$N" -gt 0 ]; then
  echo "check-config: $N config error(s) in $FILE" >&2
  exit 1
fi
exit 0
