# iconifier

Generate and apply custom macOS folder icons for a directory's subfolders. Point the skill at a parent folder — `~/Projects`, `~/Downloads`, a clients directory — and it inspects existing custom icons on the peers and parent to infer the house style, gathers a one-line context blurb per subfolder, generates a candidate icon for each, and shows an HTML preview before anything is written. Apply happens through `NSWorkspace.setIcon`, the only path that round-trips cleanly with Finder. macOS only.

## Requirements

- **macOS** (Darwin). The skill exits immediately on non-Darwin systems.
- **Xcode command line tools** for `sips`, `swift`, and `python3`. Install with `xcode-select --install`.
- **Pillow** (`pip3 install Pillow`) — used by `detect_existing_style.py` to classify already-set icons. Without it, existing-style detection falls back to `unknown` and the skill picks a method from context alone.
- **Optional API keys** for the AI-illustration path:
  - `OPENAI_API_KEY` — uses `gpt-image-1`.
  - `GEMINI_API_KEY` or `GOOGLE_API_KEY` — uses `imagen-3`.
  - If none are present, AI generation is skipped automatically and the skill falls back to emoji or SF Symbol — it does not block the run.

## Install

### Claude Code

```
/plugin marketplace add tal/plugin-marketplace
/plugin install iconifier@tal-marketplace
```

There is no `/iconifier` slash command — Claude Code triggers the skill from natural-language requests like *"iconify these folders"*, *"give my project folders matching icons"*, or *"make my Downloads pretty"*.

### Codex

```
codex plugin marketplace add tal/plugin-marketplace
codex plugin install iconifier@tal-marketplace
```

Codex triggers the skill from the same kinds of prompts.

## Skills

| Skill | What it does |
|---|---|
| `iconifier` | The whole pipeline. Detects existing style on peers, gathers context, generates candidates, previews in the browser, applies via Swift/AppKit. |

**Triggering.** The skill activates on requests to iconify, decorate, or "give icons to" a folder of folders. If invoked in a directory of subfolders with no other instruction, the default target is **every immediate subdirectory** — one level only, no recursion, with dotfiles and `node_modules`-style junk skipped. Pass explicit paths or a glob to narrow the target list.

## How it works

1. **Darwin gate.** `darwin_check.sh` confirms `uname -s == Darwin` and that `sips`, `swift`, and `python3` are available. Anything else aborts the run.
2. **Resolve targets.** Either the paths the user passed, or the immediate subdirectories of the working directory.
3. **Detect existing style.** `detect_existing_style.py` reads the current icons on peer folders (and the parent), classifies them as `emoji`, `sf-symbol`, `ai-illustration`, or `none`, and reports a confidence score.
4. **All-already-iconified shortcut.** If every target already has a custom icon, the skill uses `AskUserQuestion` to ask whether to regenerate everything, regenerate specific ones, re-detect and report only, or abort — instead of silently regenerating N proposals only to lock all the checkboxes.
5. **API-key probe.** `detect_env_keys.sh` walks up from `$PWD` to `$HOME`, sources the first `.env` (and `.env.local`) it finds, and reports which image-gen keys are present.
6. **Pick a method.** If a style was detected, every folder in the batch gets that style (consistency reads better in Finder than per-folder cleverness). If no style exists yet, pick from context: emoji for casual/personal, SF Symbol for technical, AI for clearly-named projects when a key is available.
7. **Gather context.** For each folder, build a one-line subject blurb from `README.md` / `CLAUDE.md` / `package.json` / file-type cues / sibling and parent names. Falls back to `AskUserQuestion` only when the folder is genuinely opaque (`misc`, `temp`, etc.).
8. **Generate candidates.** `compose_folder_icon.py` composites an emoji or SF Symbol glyph onto Apple's stock `GenericFolderIcon.icns` (extracted from `CoreTypes.bundle` and cached locally). `generate_ai_icon.py` calls OpenAI or Gemini for the illustration path.
9. **Preview.** `build_preview.py` writes an HTML page with one card per folder showing current icon → proposed icon, the method, and a checkbox. Folders that already have a custom icon get a **disabled checkbox** by default, so the safe action is to leave them alone.
10. **Apply.** Once the user exports the selection JSON, `set_icon.swift` calls `NSWorkspace.shared.setIcon(_:forFile:options:)` for each entry and touches the folder so Finder refreshes.

## Generation methods

| Method | What it produces | Requirements |
|---|---|---|
| `emoji` | A single emoji glyph composited onto the system folder shape. | None beyond Xcode CLT. |
| `sf-symbol` | An SF Symbol glyph (semibold, dark-slate tint) composited onto the folder shape. | macOS 11+, which is implied by Xcode CLT. |
| `ai-illustration` | A 1024×1024 transparent-background glyph from `gpt-image-1` or `imagen-3`, then composited onto the folder shape. | One of `OPENAI_API_KEY` / `GEMINI_API_KEY` / `GOOGLE_API_KEY`. |

The AI path is automatically skipped if no key is detected — the skill downgrades to emoji or SF Symbol based on whether the inferred subject feels casual or technical.

## Configuration

Iconifier is intentionally light on configuration. There is no `iconifier.md` rule file or per-project setting today.

- **Environment variables** — `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY` enable the AI-illustration method. `ANTHROPIC_API_KEY` is detected for completeness but not used (Anthropic doesn't ship an image model).
- **`.env` walk-up** — `detect_env_keys.sh` walks from the working directory up to `$HOME`, sourcing the first `.env` (and `.env.local`) it finds. Closest wins; values are loaded into a subshell so the calling environment is untouched.
- **Style override** — pass an explicit method in the prompt (e.g. *"use emoji"*) and detection is skipped.

## Files of interest

- `skills/iconifier/SKILL.md` — the canonical pipeline description; everything below is referenced from there.
- `skills/iconifier/references/style-detection.md` — heuristics for classifying existing custom icons when the script's confidence is low, plus the SF Symbol starter map and the emoji-selection guidance.
- `skills/iconifier/references/context-gathering.md` — the signal hierarchy for deciding what each folder is about, when to ask the user, and the noun-phrase format for the context blurb passed to the generators.
- `skills/iconifier/scripts/darwin_check.sh` — Darwin gate; verifies `sips`, `swift`, `python3` are present.
- `skills/iconifier/scripts/detect_env_keys.sh` — `.env` walk-up + line-based report of available API keys, ending with `ai-available: yes|no`.
- `skills/iconifier/scripts/detect_existing_style.py` — extracts current icons via `sips`, classifies them with Pillow, returns a JSON report with `dominant_style`, per-folder breakdown, and a confidence score.
- `skills/iconifier/scripts/compose_folder_icon.py` — extracts Apple's `GenericFolderIcon.icns` once, caches it, and composites an emoji / SF Symbol / pre-rendered image onto the lower face of the folder.
- `skills/iconifier/scripts/generate_ai_icon.py` — calls `gpt-image-1` or `imagen-3` with a glyph-not-illustration prompt and writes a 1024×1024 transparent PNG.
- `skills/iconifier/scripts/build_preview.py` — renders the manifest into a self-contained HTML page (data-URI images, no frameworks) with per-card checkboxes and an "Export selection" button.
- `skills/iconifier/scripts/apply_icons.py` — thin wrapper around `set_icon.swift` that prints `iconifier: applied N, failed M`.
- `skills/iconifier/scripts/set_icon.swift` — the actual `NSWorkspace.setIcon` loop; reads the selection JSON, applies each pair, touches the folder so Finder refreshes.
