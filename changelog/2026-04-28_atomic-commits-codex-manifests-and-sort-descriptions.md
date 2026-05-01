# 2026-04-28 — Atomic commits: Codex manifests, smart-notifications attribution, sort descriptions

Split eight modified files into three atomic commits via `/tal:git:commit:atomic`. The smart-notifications Codex manifest contained two unrelated changes and was staged in two halves using the partial-commit helper.

## Commits created

1. `7f3d3fa chore(codex): Remove version fields from Codex plugin manifests`
   - Removed the unused `"version": "0.1.0"` key from the Codex manifests for: `karabiner`, `plan-refiner`, `smart-notifications`, `sort`, `tal`.
   - Mirrors the convention applied to the Claude manifests in `426eacc`.

2. `8fd24fe chore(smart-notifications): Update author attribution to Tal Atlas`
   - Updated `author.name` (both Claude and Codex manifests) and `interface.developerName` (Codex) from "Mat Brown" to "Tal Atlas".
   - Aligns the displayed author with the existing `me@tal.by` and `tal/plugin-marketplace` fields.

3. `2668a34 docs(sort): Tighten skill descriptions for sort and sort-videos`
   - Condensed the `description` front-matter for `plugins/sort/skills/sort/SKILL.md` and `plugins/sort/skills/sort-videos/SKILL.md`.
   - Trigger keywords preserved; no behavioral change.

## Notes

- `plugins/smart-notifications/.codex-plugin/plugin.json` had mixed changes (version removal + author rename). The version removal hunk was staged via `plugins/tal/skills/git/partial-commit/stage-lines.sh` so it could land with commit 1, leaving the author-rename hunks for commit 2.
- No planning/scratch files were detected or excluded.
- Working tree is clean. Branch is `main`, ahead of `origin/main` by 3 commits — not pushed.
