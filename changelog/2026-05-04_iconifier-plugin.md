# 2026-05-04 — iconifier plugin

Added a new macOS-only plugin at `plugins/iconifier/` with a single skill, also named `iconifier`, that generates and applies custom folder icons for a directory's subfolders.

## What it does

Invoked on a directory of subfolders (defaults to immediate children of cwd if no args), the skill:

1. Bails immediately if `uname -s` ≠ `Darwin`. Also requires `sips`, `swift`, `python3` (Xcode CLT).
2. Reads existing custom icons on the peer subfolders and parent to detect the house style — `emoji`, `sf-symbol`, `ai-illustration`, or `none` — so new icons match what the user has already chosen for that directory.
3. Detects available image-gen API keys (`OPENAI_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`) from the current environment and any `.env` / `.env.local` walking up to `$HOME`. If no key is present, falls back to emoji or SF Symbol and continues.
4. Per folder, gathers context from README/CLAUDE.md, project metadata, folder name, sibling and parent names. Uses `AskUserQuestion` only when a folder is genuinely ambiguous (opaque name + heterogeneous contents), batched into a single round.
5. Generates a candidate icon for every subfolder including ones that already have a custom icon (so the preview shows the full set).
6. Builds an HTML preview, opens it in the browser. Cards for already-iconified folders have disabled checkboxes by default; the user exports a JSON selection.
7. Applies via a Swift helper that calls `NSWorkspace.shared.setIcon(_:forFile:options:)`.

## Layout

```
plugins/iconifier/
├── .claude-plugin/plugin.json
├── .codex-plugin/plugin.json
└── skills/iconifier/
    ├── SKILL.md
    ├── assets/                  (folder-base-1024.png cached on first run)
    ├── evals/evals.json
    ├── references/
    │   ├── context-gathering.md
    │   └── style-detection.md
    └── scripts/
        ├── apply_icons.py
        ├── build_preview.py
        ├── compose_folder_icon.py
        ├── darwin_check.sh
        ├── detect_env_keys.sh
        ├── detect_existing_style.py
        ├── generate_ai_icon.py
        └── set_icon.swift
```

## Notable decisions

- **System folder PNG is extracted at runtime, not shipped.** `compose_folder_icon.py` runs `iconutil -c iconset` on `/System/Library/CoreServices/CoreTypes.bundle/.../GenericFolderIcon.icns` on first use, normalizes the largest size to 1024×1024 via `sips`, and caches it under `skills/iconifier/assets/`. This keeps us off Apple's owned art and means icons match the user's macOS version.
- **Apply uses native AppKit, not `fileicon` or AppleScript.** A short Swift script reads the selection JSON and calls `NSWorkspace.shared.setIcon` per entry. No external dependency, and survives Finder permission prompts better than `osascript`.
- **Style consistency wins over per-folder cleverness.** Step 4 in the SKILL picks one generation method for the whole batch instead of mixing — a directory of mixed-style icons reads worse than one of slightly-imperfect-but-consistent ones.
- **Three-level progressive disclosure.** SKILL.md is ~150 lines; deeper guidance lives in `references/style-detection.md` and `references/context-gathering.md` which are loaded only when the model needs them.
- **Dual runtime — Claude Code + Codex.** Both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` ship in the plugin root, sharing the same `skills/` directory. The Codex manifest adds the `interface` block (`displayName`, `shortDescription`, `longDescription`, `category=Customization`, `defaultPrompt` examples, `brandColor=#3B82F6`). Both manifests carry `"platforms": ["darwin"]` so non-macOS runtimes can hide the plugin without invoking it. Scripts continue to reference `${CLAUDE_PLUGIN_ROOT}` — the established convention across this marketplace's dual-runtime plugins.
- **Early branch when every folder is already iconified.** Step 2.5 in SKILL.md detects the all-iconified case after style detection and asks the user whether to regenerate all to compare, regenerate specific named folders, re-detect-and-report, or abort — instead of burning generation cost on proposals that would all be locked off in the preview. `build_preview.py --allow-overwrite` flips existing-icon cards from disabled to enabled-but-unchecked-with-"Replace"-label for the compare-all path.

## Marketplace registration

Added entries for `iconifier` to both marketplace digests so the plugin is discoverable via `/plugin`:

- `.claude-plugin/marketplace.json` — added entry pointing at `./plugins/iconifier` with a single-line description.
- `.agents/plugins/marketplace.json` — added the codex digest entry with `category: "Utilities"`, matching the marketplace's existing categories (Developer Tools, Productivity, Utilities, Automation). Also brought the `.codex-plugin/plugin.json` interface category in line — was "Customization", now "Utilities" to match the digest.

## Eval scaffold

`evals/evals.json` has three test prompts covering: (1) all-fresh code projects with no AI key, (2) mixed dir with some folders already iconified in emoji style, (3) a directory containing one genuinely-ambiguous folder where the skill should ask the user. The skill-creator workflow will run these as the next step.
