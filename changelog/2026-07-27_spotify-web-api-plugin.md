# 2026-07-27 - Add spotify-web-api Plugin

Extracted the `spotify-web-api` skill out of the `spotify-playlist` repo (`.claude/skills/spotify-web-api/`) and packaged it as a marketplace plugin, so it's installable anywhere instead of living inside one project.

## Files added

| Path | Role |
|---|---|
| `plugins/spotify-web-api/.claude-plugin/plugin.json` | Claude manifest |
| `plugins/spotify-web-api/.codex-plugin/plugin.json` | Codex manifest with `interface` block |
| `plugins/spotify-web-api/README.md` | Full skill/reference/example inventory |
| `plugins/spotify-web-api/skills/spotify-web-api/SKILL.md` | Entry point (moved verbatim) |
| `plugins/spotify-web-api/skills/spotify-web-api/references/{authentication-flows,endpoints-complete,scopes-complete}.md` | On-demand references (moved verbatim) |
| `plugins/spotify-web-api/skills/spotify-web-api/examples/{auth-flow.md,curl-examples.sh}` | Runnable examples (moved verbatim) |

Skill content was moved byte-for-byte — no edits to `SKILL.md`, the references, or the examples.

## Files changed

- `.claude-plugin/marketplace.json` — registered `spotify-web-api`
- `.agents/plugins/marketplace.json` — registered `spotify-web-api` under category **Developer Tools** (matching `interface.category`)
- `README.md` — added the plugin to the `## Plugins` list

## Manifest details

| Field | Value | Limit |
|---|---|---|
| `description` | 126 chars | ~100–145 |
| `interface.shortDescription` | 59 chars | ≤ 60 |
| `interface.longDescription` | 130 chars | ≤ 150 |
| `interface.category` | Developer Tools | existing bucket |
| `interface.brandColor` | `#1DB954` | Spotify green |

Skill-only plugin — no commands, agents, hooks, or scripts, so no `${CLAUDE_PLUGIN_ROOT}` paths to resolve.

## Downstream change in `spotify-playlist`

- Deleted `.claude/skills/spotify-web-api/` (6 tracked files)
- Added `.claude/settings.json` with `enabledPlugins: { "spotify-web-api@tal-marketplace": true }` so the repo pulls the skill from the marketplace instead of vendoring it
