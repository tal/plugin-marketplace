# iconifier

Give a directory of folders custom macOS icons that match each folder's contents — and match each other. Point it at `~/Projects`, `~/Downloads`, a clients folder, or any parent directory, and it figures out what each subfolder is *about*, picks a visual style consistent with whatever icons are already in use, and previews the whole batch before touching anything.

## What it does for you

- **One coherent set of icons across a folder of folders.** If your other projects already use emoji, the new ones get emoji. If they use SF Symbols, the new ones get SF Symbols. If they're AI illustrations, you get AI illustrations. No mixed bag.
- **Each icon reflects the folder's actual contents.** It reads `README.md`, `CLAUDE.md`, `package.json`, file-type cues, and sibling/parent names to figure out what each folder is for, then picks a glyph or generates an illustration that fits.
- **Browser preview before anything is applied.** You see current icon → proposed icon for every folder, with checkboxes. Folders that already have a custom icon are unchecked by default so you don't accidentally clobber them.
- **Safe-by-default selection.** "Apply" only touches the folders you check. Nothing is written to disk until you export the selection.
- **Three generation methods, picked automatically.** Emoji for casual/personal folders, SF Symbol for technical ones, AI illustration when an image-gen API key is available and the folder has a clear subject. You can also force one in the prompt (*"use emoji"*).
- **Sensible defaults when invoked with no args.** Run it in a folder of folders and it targets every immediate subdirectory — one level deep, dotfiles and `node_modules`-style noise skipped.

## Requirements

- **macOS** (Darwin). The skill exits immediately on non-Darwin systems.
- **Xcode command line tools** for `sips`, `swift`, and `python3`. Install with `xcode-select --install`.
- **Pillow** (`pip3 install Pillow`) for classifying existing icons. Without it, style detection falls back to `unknown` and the skill picks a method from context alone.
- **Optional image-gen API key** for the AI-illustration path: `OPENAI_API_KEY` (uses `gpt-image-1`) or `GEMINI_API_KEY` / `GOOGLE_API_KEY` (uses `imagen-3`). If none are present, AI generation is skipped and the skill falls back to emoji or SF Symbol — it does not block the run.

## Install

### Claude Code

From inside Claude Code:

```
/plugin marketplace add tal/plugin-marketplace
/plugin install iconifier@tal-marketplace
```

Or from the shell with the `claude` CLI:

```
claude plugin marketplace add tal/plugin-marketplace
claude plugin install iconifier@tal-marketplace
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
| `iconifier` | The whole pipeline: detect existing style on peers, gather context per folder, generate candidates, preview in the browser, apply on confirmation. |

## Generation methods

| Method | What it produces | Requirements |
|---|---|---|
| `emoji` | A single emoji glyph on the system folder shape. | None beyond Xcode CLT. |
| `sf-symbol` | An SF Symbol glyph (semibold, dark-slate tint) on the folder shape. | macOS 11+. |
| `ai-illustration` | A 1024×1024 transparent-background glyph from `gpt-image-1` or `imagen-3`, composited onto the folder shape. | `OPENAI_API_KEY`, `GEMINI_API_KEY`, or `GOOGLE_API_KEY`. |

## Configuration

Iconifier is intentionally light on configuration — there is no `iconifier.md` rule file today.

- **Style override** — pass an explicit method in the prompt (*"use emoji"*, *"use SF Symbols"*) and detection is skipped.
- **`.env` walk-up** — API keys are auto-loaded from the nearest `.env` / `.env.local` walking up from the working directory to `$HOME`. Closest wins; the calling environment is untouched.
