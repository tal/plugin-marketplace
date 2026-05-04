# 2026-05-04 — AGENTS.md, README pass, and small bugfixes the pass surfaced

## AGENTS.md as the marketplace's source of truth

- New `AGENTS.md` at the repo root with shared instructions for any agent (Claude Code, Codex, etc.) working in this marketplace.
- `CLAUDE.md` is now a one-line `@AGENTS.md` reference so Claude Code imports the same content.
- AGENTS.md captures three rules that had been implicit:
  - Plugins are dual-runtime by default — every plugin ships both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`, sharing one `skills/` / `commands/` / etc. tree.
  - When you create a new plugin, register it in both marketplace digests (`.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`). Use the same `category` in the digest entry and the per-plugin `interface.category`. Existing categories: Developer Tools, Productivity, Utilities, Automation.
  - Keep READMEs current — root `README.md` lists every plugin with brief descriptions and links to per-plugin READMEs; per-plugin READMEs are the canonical inventory of features, commands, skills, and agents. README staleness is treated like a lint failure.

## Root README "Plugins" section

Replaced the bare `Available plugins: ...` line with a real **Plugins** section that has a one-paragraph description per plugin and a direct link to that plugin's own README.

## Per-plugin READMEs

Spawned six parallel subagents — one per plugin — to inventory each plugin and write or refresh its README based on what's actually in the directory. Final state:

| Plugin              | Status   | Lines |
|---------------------|----------|-------|
| iconifier           | new      | 86    |
| karabiner           | new      | 57    |
| plan-refiner        | new      | 64    |
| smart-notifications | refreshed| 151   |
| sort                | refreshed| 143   |
| tal                 | new      | 80    |

Each README now covers: one-paragraph overview, install snippets for both Claude Code and Codex matching the marketplace conventions, every shipped skill/command/agent with one-line summaries, requirements (OS, dependencies, optional API keys), and a "files of interest" pointer list.

## Bugs the README pass surfaced (fixed in this commit)

- **`tal` plugin manifests had `author: "AI DevX Team"`** despite being Tal's personal plugin. Both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` (including the `interface.developerName`) updated to "Tal Atlas".
- **`tal` plugin description claimed "CI troubleshooting"** but no CI-troubleshooting command or skill ships in the plugin. Both manifest descriptions, `shortDescription`, `longDescription`, and the `defaultPrompt` array tightened to match what's actually shipped (commits, PR feedback, App Store Connect, partial-commit staging).
- **`plan-refiner/commands/create.md`** had `name: plan` in frontmatter — every other command in that plugin uses `name: <filename>`, and the live command surfaces as `/plan-refiner:create`. Fixed to `name: create`.
- **`iconifier` skill**:
  - SKILL.md step 8 invoked `swift set_icon.swift` directly, leaving `apply_icons.py` orphaned. Step 8 now invokes the Python wrapper, which gives a clean `applied N, failed M` summary line.
  - Pillow is a soft dependency of `detect_existing_style.py` (the script returns `"unknown"` for every folder if Pillow is missing) but wasn't documented anywhere. SKILL.md's "0. Bail if not on macOS" section now calls it out so the model can suggest `pip3 install Pillow` if many `unknown` entries show up in detection output.
  - The `.claude-plugin/plugin.json` description led with `\`/iconifier\`` as if a slash command existed; it doesn't (the plugin is skill-only). Reworded to "triggers on any 'give these folders icons' / 'iconify my downloads' request".

## Bugs surfaced but NOT fixed (need user judgment)

- **`plan-refiner/commands/act-on.md`** has no YAML frontmatter at all (every other command does). Functional but inconsistent — would need a `description:` and `argument-hint:` to match.
- **`plan-refiner/skills/plan-refinement/SKILL.md`** references `before-after-api.md` and `before-after-architecture.md` — only `before-after-feature.md` exists. Either add the missing examples or remove the SKILL references.
- **`tal/commands.md`** and **`tal/skills/git/partial-commit/SKILL.md`** both reference a `git-branches` skill (`commands.md` calls it "MANDATORY") that doesn't exist in the plugin. Either add the skill or remove the references.
- **`tal/.orphaned_at`** — small timestamped file at the plugin root, possibly from earlier marketplace tooling. Unexplained but harmless.
- **`sort` plugin had two recent feature commits** (`Add action: prompt rules` and `Sensitive/ subcategories`) that never got changelog entries. The README now reflects them, but no `changelog/YYYY-MM-DD_*.md` entry exists for the work itself.

## Files touched

- New: `AGENTS.md`, `CLAUDE.md`, `plugins/iconifier/README.md`, `plugins/karabiner/README.md`, `plugins/plan-refiner/README.md`, `plugins/tal/README.md`.
- Refreshed: `README.md`, `plugins/smart-notifications/README.md`, `plugins/sort/README.md`.
- Bugfixes: `plugins/tal/.claude-plugin/plugin.json`, `plugins/tal/.codex-plugin/plugin.json`, `plugins/plan-refiner/commands/create.md`, `plugins/iconifier/.claude-plugin/plugin.json`, `plugins/iconifier/skills/iconifier/SKILL.md`.
