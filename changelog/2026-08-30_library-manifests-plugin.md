# library-manifests plugin

Added `plugins/library-manifests`, a dual-runtime (Claude Code + Codex) reference plugin for the AI Library
server's per-folder `.library.yml` manifests. Pure knowledge — one auto-discovered skill, no commands,
agents, or hooks.

## What the skill contains

- `SKILL.md` — ten facts about the file, a keys-at-a-glance table, the `visibility` × `listing` model with
  inheritance and the narrow-only rule, an access-behaviour cheat sheet, structural side effects (gallery
  rule, `kind: app`, `hidden`), a symptom → cause triage table, recipes, a gotchas checklist, and the rules
  of engagement for who may write manifests and where.
- `references/` — `keys.md` (per-key types, patterns, coupled rules, exact error strings),
  `access-and-listing.md` (guard decision order, unlock flow, cookie, rate limit, no existence oracle,
  unlisted enforcement points, inheritance corner cases), `apps.md` (entry serving, injections, CSP, scoped
  API, `TRUSTED_APPS`, build cache key, security trade-off), `previews-and-titles.md` (title resolution,
  card-picture precedence, macOS icon carriers, `.library-icon.png`), `failure-modes.md` (complete
  situation → outcome → warning → HTTP table plus 25 verified gotchas), `fixtures.md` (every fixture
  manifest and what it proves).
- `examples/` — twelve copy-ready manifests, one per shape, including `does-not-work.yml` for the
  widening attempts the server ignores; all validated against the server's own `validateManifest`.

## How it was built

Compiled from the server source at commit `ffef3bc` (2026-08-30): the JSON Schema, `src/scan/manifest.ts`,
`src/scan/catalog.ts`, `src/access/guard.ts`, the app/render/search modules, the README behaviour tables,
the v2 plan (Parts B/C/F and the recorded plaintext-password trade-off), the still-to-do list, the fixture
generator, and the manifest tests. Edge cases (numeric YAML values, ` #` in passwords, `preview: None`,
`.library.yaml`, empty-manifest gallery flip, public-under-protected, listed-under-unlisted, root
manifests) were pinned with throwaway probe trees — the real library was never touched.

Notable findings surfaced by the research and recorded in the skill: numeric-looking `title`/`password`
values hide the folder; a manifest's mere existence flips a gallery-shaped directory into a category;
widening warnings are rendered publicly on the folder page; only folders that *declared* `protected` are
unlock guards; any library path containing `password` still crashes boot / fails rescan (open bug); the
schema `$id` is a dead URL (missing `/_/`).

## Registration and installs

- Registered in `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`
  (category *Developer Tools*); root `README.md` plugin list updated.
- Installed project-scoped in `~/Downloads` for Claude Code (`--scope project` →
  `~/Downloads/.claude/settings.json`) and for Codex as a plain copy at `~/Downloads/.agents/skills/library-manifests`
  (Codex does not discover symlinked skill directories or symlinked skill contents — tested both; a real
  copy is required, refreshed with `rsync -a --delete` from the plugin's skill directory).
