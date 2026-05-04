# Plugin marketplace — agent notes

Shared instructions for any agent (Claude Code, Codex, or anything else) working in this repo. `CLAUDE.md` is a thin pointer at this file; keep all real content here.

## Plugins are dual-runtime by default

Unless a specific plugin says otherwise in its README or manifest, **assume every plugin in `plugins/` is meant to run on both Claude Code and Codex**. Concretely that means:

- Each plugin ships both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`. The Codex manifest carries the additional `interface` block (`displayName`, `shortDescription` ≤60 chars, `longDescription` ≤150 chars, `category`, `defaultPrompt`, `brandColor`, `capabilities`).
- Both manifests reference the same `skills/`, `commands/`, `agents/`, `scripts/` directories — no per-runtime forks of the actual content.
- Scripts and skill bodies use `${CLAUDE_PLUGIN_ROOT}` to resolve plugin-relative paths. That's the established convention even for Codex-targeted plugins; both runtimes resolve it.
- If a plugin is genuinely single-runtime, say so explicitly in its README and skip the other manifest.

## When you create a new plugin, register it in the marketplace digests

A plugin only shows up under `/plugin` (Claude) or the Codex marketplace UI if it's registered in the matching digest. After scaffolding `plugins/<new-plugin>/`, add an entry to **both** of:

- `.claude-plugin/marketplace.json` — `{ "name", "source": "./plugins/<new-plugin>", "description" }`. Description is a single sentence shown in the marketplace listing (existing entries run 33–164 chars).
- `.agents/plugins/marketplace.json` — `{ "name", "source": { "source": "local", "path": "./plugins/<new-plugin>" }, "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" }, "category" }`.

Use the same `category` in both the digest entry and the per-plugin `.codex-plugin/plugin.json`'s `interface.category`. The categories already in use across the marketplace are **Developer Tools**, **Productivity**, **Utilities**, **Automation** — pick one rather than inventing a new bucket unless none fits.

## Keep READMEs in sync with reality

Two layers, both kept current:

- **Root `README.md`** — has a section listing every plugin in `plugins/` with a one-paragraph description and a link to that plugin's own README (e.g. `[iconifier](./plugins/iconifier/README.md)`). When a plugin is added, removed, or its purpose materially changes, update this section in the same change.
- **Per-plugin `plugins/<name>/README.md`** — describes what the plugin does, lists every user-facing feature, command (`/<name>`, `/<name>:<sub>`), skill, and agent that ships with it, plus any prerequisites (API keys, OS requirements, system tools). When a command, skill, or agent is added/removed/renamed inside a plugin, update its README in the same change. The description in the plugin's manifests can drift away from the README's body — that's fine — but the README should always be a complete, accurate inventory.

Treat README staleness like a code lint failure: if you ship a change that introduces or removes a user-visible surface and you didn't touch the matching README, the change isn't done.

## Other recurring rules

- After a significant change anywhere in the repo, drop a markdown file in `changelog/` named `YYYY-MM-DD_descriptive-name.md`.
- Description lengths in `.codex-plugin/plugin.json`: **`shortDescription` ≤ 60 chars, `longDescription` ≤ 150 chars**. Codex errors on overflow rather than truncating silently. The top-level `description` field tracks the existing range of ~100–145 chars.
