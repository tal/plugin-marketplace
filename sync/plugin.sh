#!/usr/bin/env bash
set -euo pipefail

MARKETPLACE_DIR="$(cd "$(dirname "$0")" && pwd)"
MARKETPLACE_JSON="$MARKETPLACE_DIR/.claude-plugin/marketplace.json"

DEFAULT_SOURCE="../claude-marketplace"

usage() {
  cat <<EOF
Usage: $0 <source-plugin> [dest-name] [source-marketplace]

Sync an entire plugin from another marketplace, optionally renaming it.

  source-plugin        name of the plugin directory in the source
  dest-name            name for the plugin in this marketplace (default: same as source)
  source-marketplace   path to the source marketplace repo (default: $DEFAULT_SOURCE)

The script will:
  - rsync the full plugin directory
  - rename the plugin in .claude-plugin/plugin.json
  - rewrite /old-name: references to /new-name: in .md files
  - register the plugin in this marketplace's catalog if not already present

Examples:
  $0 source-name tal                                # sync source-name as tal from default marketplace
  $0 source-name                                    # keeps the original name
  $0 source-name tal /path/to/other/marketplace     # use a different source
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage

SOURCE_PLUGIN="$1"
DEST_NAME="${2:-$SOURCE_PLUGIN}"
SOURCE_MARKETPLACE="${3:-$DEFAULT_SOURCE}"

# Resolve source path — plugins may be at root level or under plugins/
if [[ -d "$SOURCE_MARKETPLACE/plugins/$SOURCE_PLUGIN" ]]; then
  SOURCE_DIR="$SOURCE_MARKETPLACE/plugins/$SOURCE_PLUGIN"
elif [[ -d "$SOURCE_MARKETPLACE/$SOURCE_PLUGIN" ]]; then
  SOURCE_DIR="$SOURCE_MARKETPLACE/$SOURCE_PLUGIN"
else
  echo "Error: cannot find plugin '$SOURCE_PLUGIN' in '$SOURCE_MARKETPLACE'" >&2
  echo "Looked in:" >&2
  echo "  $SOURCE_MARKETPLACE/plugins/$SOURCE_PLUGIN" >&2
  echo "  $SOURCE_MARKETPLACE/$SOURCE_PLUGIN" >&2
  exit 1
fi

DEST_DIR="$MARKETPLACE_DIR/plugins/$DEST_NAME"

echo "Syncing: $SOURCE_DIR -> $DEST_DIR"
[[ "$SOURCE_PLUGIN" != "$DEST_NAME" ]] && echo "Renaming: $SOURCE_PLUGIN -> $DEST_NAME"

# Step 1: rsync the whole plugin
mkdir -p "$DEST_DIR"
rsync -av --delete "$SOURCE_DIR/" "$DEST_DIR/"

# Step 2: rewrite plugin name in plugin.json
PLUGIN_JSON="$DEST_DIR/.claude-plugin/plugin.json"
if [[ -f "$PLUGIN_JSON" ]] && [[ "$SOURCE_PLUGIN" != "$DEST_NAME" ]]; then
  sed -i '' "s/\"name\": *\"$SOURCE_PLUGIN\"/\"name\": \"$DEST_NAME\"/" "$PLUGIN_JSON"
  echo "Updated plugin.json name -> $DEST_NAME"
fi

# Step 3: rewrite slash-command references in .md files (/old: -> /new:)
if [[ "$SOURCE_PLUGIN" != "$DEST_NAME" ]]; then
  count=0
  while IFS= read -r -d '' file; do
    if grep -q "/$SOURCE_PLUGIN:" "$file" 2>/dev/null; then
      sed -i '' "s|/$SOURCE_PLUGIN:|/$DEST_NAME:|g" "$file"
      count=$((count + 1))
    fi
  done < <(find "$DEST_DIR" -name '*.md' -print0)
  echo "Rewrote /$SOURCE_PLUGIN: -> /$DEST_NAME: in $count file(s)"
fi

# Step 4: register in marketplace.json if not already present
if ! grep -q "\"name\": *\"$DEST_NAME\"" "$MARKETPLACE_JSON" 2>/dev/null; then
  # Read description from plugin.json if available
  DESC=""
  if [[ -f "$PLUGIN_JSON" ]]; then
    DESC=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('description',''))" "$PLUGIN_JSON" 2>/dev/null || true)
  fi

  # Insert into the plugins array using python for reliable JSON manipulation
  python3 -c "
import json, sys

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

entry = {
    'name': sys.argv[2],
    'source': sys.argv[2],
    'description': sys.argv[3] or 'Synced from $SOURCE_PLUGIN',
    'version': '0.1.0'
}
data['plugins'].append(entry)

with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$MARKETPLACE_JSON" "$DEST_NAME" "$DESC"
  echo "Registered '$DEST_NAME' in marketplace.json"
else
  echo "'$DEST_NAME' already in marketplace.json, skipping registration"
fi

echo ""
echo "Done. Files synced:"
find "$DEST_DIR" -type f | sort | sed "s|$MARKETPLACE_DIR/||; s/^/  /"
