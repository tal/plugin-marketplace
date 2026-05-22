# Add `og-simplify` plugin — the resurrected `/simplify`

**Date:** 2026-05-22

## What

Added a new dual-runtime plugin `plugins/og-simplify/` that restores Claude
Code's removed `/simplify` cleanup-and-fix behavior, invoked as `/og-simplify`.

## Why

Claude Code's bundled `/simplify` slash command was renamed to `/code-review`
in v2.1.147 and its old **cleanup-and-fix** behavior (which actually applied
fixes) was removed — `/code-review` today is read-only bug reporting. This
plugin brings the original auto-fixing pipeline back.

## How it was recovered

The skill prompt was extracted **verbatim** from the embedded prompt in the
`@anthropic-ai/claude-code@2.1.146` native binary (the last release carrying the
cleanup-and-fix behavior, before v2.1.147 removed it):

1. `npm pack @anthropic-ai/claude-code@2.1.146` → confirmed the npm package is a
   thin stub that downloads a per-platform native binary.
2. Downloaded `@anthropic-ai/claude-code-darwin-arm64@2.1.146` (~201 MB binary).
3. `strings` + grep located the skill embedded as a JS template literal —
   internally `name: "code-review", aliases: ["simplify"]`,
   `argumentHint: "[low|medium|high|xhigh|max]"`. The prompt body launches three
   parallel agents (Code Reuse / Code Quality / Efficiency) then applies fixes.

Changelog references:
- Introduced: **v2.1.63** (`Added /simplify and /batch bundled slash commands`)
- Removed/renamed: **v2.1.147** (`Renamed /simplify to /code-review ... The old
  cleanup-and-fix behavior has been removed`)

## Files

Created:
- `plugins/og-simplify/.claude-plugin/plugin.json`
- `plugins/og-simplify/.codex-plugin/plugin.json` (with the Codex `interface` block; category **Developer Tools**)
- `plugins/og-simplify/skills/og-simplify/SKILL.md` (verbatim recovered prompt; effort argument preserved)
- `plugins/og-simplify/README.md`

Edited:
- `.claude-plugin/marketplace.json` — registered the plugin (Claude digest)
- `.agents/plugins/marketplace.json` — registered the plugin (Codex digest)
- root `README.md` — added to the plugin list

## Notes

- The skill body references no plugin-relative files, so no `${CLAUDE_PLUGIN_ROOT}` substitutions were needed.
- Named `og-simplify` (rather than `simplify`) to avoid colliding with the
  upstream `/code-review` and with a personal `~/.claude/skills/simplify/` copy.
