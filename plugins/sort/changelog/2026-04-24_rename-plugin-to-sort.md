# Rename plugin from `sort-videos` to `sort`

Renamed the plugin directory and marketplace entry so the plugin can host additional sort/process workflows beyond videos.

## Changes

- `plugins/sort-videos/` → `plugins/sort/` (git rename, history preserved)
- `plugin.json` — `name` changed from `sort-videos` to `sort`; description broadened to cover "downloaded media" generally; version field removed to match the current project convention
- `marketplace.json` — plugin entry `name` and `source` updated to `sort` / `./plugins/sort`, description broadened

## Not changed

- The skill is still named `sort-videos` (at `plugins/sort/skills/sort-videos/SKILL.md`), so the `/sort-videos` command and all of its triggering phrases continue to work identically.
- Agent, scripts, and skill content are untouched.
