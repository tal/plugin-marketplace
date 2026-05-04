---
name: iconifier
description: Generate and apply custom macOS folder icons for a directory's subfolders. Use this skill when the user says any variation of "iconify these folders", "give my projects custom icons", "make my Downloads pretty", "this folder of folders is ugly", "add icons to my client folders", or runs `/iconifier`. Also reach for it when the user is staring at a directory of plain blue folders and wants them to look distinct, organized, or branded. The skill inspects existing custom icons on peers and the parent to learn the house style (emoji-on-folder vs SF Symbol vs AI illustration), gathers context from each folder's contents and sibling names, generates a candidate icon per folder, and shows an HTML preview before touching anything. It picks the best generation method available (gpt-image-1 / imagen if an API key is present, otherwise emoji or SF Symbol). macOS only — exits immediately on non-Darwin. If invoked in a directory with subfolders and no other instruction, default target is "every immediate subdirectory".
---

# iconifier

Generates and applies custom folder icons on macOS. The unit of work is "iconify the subfolders of a directory" — a parent folder of project folders, a `~/Downloads`, a clients directory, a `~/Documents/Reading/`. The skill reads existing custom icons on the peers and parent so the new icons match the house style, gathers context from each subfolder's contents, and shows the user a preview before anything is written to the filesystem.

Apple's macOS icon system stores a custom icon in the folder's resource fork via `NSWorkspace.setIcon(_:forFile:options:)`. We use a small Swift helper for that — it's the only thing that reliably round-trips with Finder.

## 0. Bail if not on macOS

Run `bash ${CLAUDE_PLUGIN_ROOT}/skills/iconifier/scripts/darwin_check.sh`. If it exits non-zero, stop immediately and tell the user the skill is macOS-only. Do not attempt any of the steps below — they all rely on Apple frameworks.

**Soft dependency:** style detection (step 2) imports `PIL` (Pillow) for pixel-level classification of existing icons. If Pillow isn't installed, `detect_existing_style.py` returns `"style": "unknown"` for every folder rather than failing — the skill still works, but the consistency-detection signal is degraded. If you notice many `unknown` entries in the detection output and the user cares about matching an existing style, suggest `pip3 install Pillow` and rerun.

## 1. Resolve the target list

The skill operates on a list of folders. Resolve targets in this order:

1. If the user passed explicit paths or a glob, use those.
2. Otherwise, fall back to the immediate subdirectories of the working directory (one level only — do not recurse). Skip dotfiles and `node_modules`-type junk by default.

Stop and ask the user only if the working directory has no subdirectories at all, since the skill has nothing meaningful to do in that case.

## 2. Detect the house style

Before generating anything, look at the existing custom icons on:
- the **peer subfolders** of the target list (the most important signal — the user has already shown what style they like for *these specific* folders)
- the **parent folder** itself (a weaker but still useful signal)

Read `references/style-detection.md` for the classification heuristics. The output of this step is one of:
- `emoji` — an emoji glyph is composited onto a macOS folder shape
- `sf-symbol` — an SF Symbol glyph is composited onto a macOS folder shape
- `ai-illustration` — a generated illustration sits on a folder shape
- `none` — nothing custom exists yet, the skill is starting from scratch

If the user asked for a specific method explicitly (e.g. "use emoji"), honor that and skip detection.

If `none`, you'll pick a method in step 4 based on what's available and what fits the context.

## 2.5. Handle the "everything is already iconified" case

If `detect_existing_style.py` reports that **every** target folder has a custom icon (`has_custom_icon: true` for all entries), don't proceed to generation. Generating N fresh proposals only to lock all their checkboxes in the preview wastes time and, for the AI path, money.

Instead, use `AskUserQuestion` with these options:

- **Regenerate proposals for all of them so I can compare side by side** — proceed to step 3 normally, but after the preview, treat the existing-icon flag as informational rather than a hard lock (set checkboxes to unchecked-but-enabled).
- **Regenerate proposals for specific folders I'll name** — collect the list, narrow the target set to those, then proceed to step 3. Treat them as if they had no custom icon for the rest of the flow.
- **Re-detect style and report only** — run style detection's `notes` and `dominant_style` back to the user, then exit without generating anything.
- **Abort** — say "looks good, nothing to do" and exit.

Default option in the AskUserQuestion list: "Regenerate for specific folders I'll name". That's almost always the right answer — the user ran the skill because something was bothering them about a few specific icons, not because they wanted to redo all of them.

## 3. Detect available image-gen API keys

Run `bash ${CLAUDE_PLUGIN_ROOT}/skills/iconifier/scripts/detect_env_keys.sh` from the working directory. The script:
- sources `.env` (and `.env.local`) if present in cwd or any parent up to `$HOME`
- prints, one per line, which of `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `ANTHROPIC_API_KEY` are populated
- prints `ai-available: yes` or `ai-available: no` on its last line

If `ai-available: no` and the detected style was `ai-illustration`, tell the user that AI generation isn't available here, downgrade to `emoji` or `sf-symbol` (whichever fits the inferred subject matter better — emoji for casual/personal contexts, SF Symbol for technical/utilitarian ones), and continue. Don't block the run on a missing key.

## 4. Pick the generation method per folder

If style detection returned a concrete style, use it for every folder. Consistency matters more than per-folder cleverness — a directory of mixed-style icons looks worse than a directory of slightly-imperfect-but-consistent ones.

If style detection returned `none`, choose for the whole batch (not per-folder):
- if the parent or sibling folder names suggest a casual / personal context (e.g. `~/Downloads`, photo archives, hobbies) → `emoji`
- if they suggest a technical / utilitarian context (codebases, work projects, dotfiles) → `sf-symbol` if AI isn't available, otherwise `ai-illustration`
- if AI is available and the folders are clearly *named projects* (clients, products, distinct apps) → `ai-illustration` (worth the cost — these folders deserve unique icons)

When in doubt, default to `emoji` — it's cheap, fast, and recognizable.

## 5. Gather context per folder

For each target folder, build a short context blurb that will drive the icon choice. Pull from, in order of trust:

1. The folder's own contents — top-level filenames, file types, presence of `README.md` / `CLAUDE.md` / `package.json` / `Cargo.toml`. A glance at the README's first paragraph is usually decisive.
2. The folder's name itself.
3. The names of sibling subfolders (helps disambiguate — "iOS" inside a "platform-tests" parent is different from "iOS" inside a "vacation-photos" parent).
4. The parent folder's name and any `README.md` / `CLAUDE.md` it has.

If after all of that the context for a particular folder is genuinely ambiguous (e.g. a folder named `misc` with five unrelated files), use `AskUserQuestion` to ask the user what that folder is for. Don't ask about every folder — only the ones where you can't confidently name what the icon should depict. Read `references/context-gathering.md` for more on the signal hierarchy and the "ambiguity threshold" — the line between "I can guess" and "I need to ask".

## 6. Generate candidate icons

For each target folder, including ones that already have a custom icon (the user wants to see proposals for everything in the preview, even if they can't be selected):

- **emoji**: pick the most fitting single emoji from the context blurb, then run `python3 ${CLAUDE_PLUGIN_ROOT}/skills/iconifier/scripts/compose_folder_icon.py --emoji <emoji> --out <path>`.
- **sf-symbol**: pick the most fitting SF Symbol name (use the references in `references/style-detection.md` for a starter list), then run the same script with `--sf-symbol <name>`.
- **ai-illustration**: build a tight prompt (see prompt template in `scripts/generate_ai_icon.py`'s docstring) and run `python3 ${CLAUDE_PLUGIN_ROOT}/skills/iconifier/scripts/generate_ai_icon.py --context "<blurb>" --provider <openai|gemini> --out <path>`.

The composer extracts Apple's stock `GenericFolderIcon.icns` from `/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/` on first use and caches it under `${CLAUDE_PLUGIN_ROOT}/skills/iconifier/assets/folder-base-1024.png`. Don't ship a folder PNG in the repo — Apple owns that asset and we use the system copy.

Save all candidate PNGs to a workspace directory — `mktemp -d -t iconifier`. Keep a JSON manifest of `{folder_path, current_icon_path_or_null, proposed_icon_path, method, prompt_or_emoji, has_existing_custom_icon}` next to the PNGs.

## 7. Preview in the browser

Run `python3 ${CLAUDE_PLUGIN_ROOT}/skills/iconifier/scripts/build_preview.py --manifest <manifest.json> --out <preview.html>`, then `open <preview.html>`. If the user picked "regenerate proposals for all of them" in step 2.5, pass `--allow-overwrite` so existing-icon cards render unchecked-but-enabled (labeled "Replace") instead of disabled.

The preview shows a card per folder with: folder name, the current custom icon (if any), the proposed icon, a checkbox to apply, and a small textbox to add notes for a regenerate pass. **Folders that already have a custom icon get a disabled checkbox** — the proposal is shown for completeness but won't be applied unless the user explicitly overrides.

The page has an "Export Selection" button that downloads `iconifier-selection.json` (the list of `{folder_path, proposed_icon_path}` to apply) to the user's default downloads directory.

After running `open` on the preview, prompt the user via `AskUserQuestion` with the question "Done exporting your selection?" and a single option labeled "Yes, exported". Don't list other options — the user will use "Other" or just message back if they want to abort. **Do not** ask them to paste the path; assume the file landed at `~/Downloads/iconifier-selection.json`.

## 8. Apply

When the user confirms they've exported, look for the selection JSON at `~/Downloads/iconifier-selection.json`. If it isn't there, ask the user where it is (some users redirect their downloads folder). Once you have a path, run:

```
python3 ${CLAUDE_PLUGIN_ROOT}/skills/iconifier/scripts/apply_icons.py <selection.json>
```

That's a thin wrapper around the Swift helper at `scripts/set_icon.swift` — it adds a clean `iconifier: applied N, failed M` summary line and uniform error formatting. The Swift helper itself iterates the selection, calls `NSWorkspace.shared.setIcon(_:forFile:options:)` for each pair, prints `ok <path>` / `err <path>: <reason>` per folder, and touches each successful folder to nudge Finder to refresh. Surface the summary line back to the user along with any `err` lines so they can see what didn't apply.

**Delete the selection JSON after applying.** It's a single-use artifact — leaving it in `~/Downloads/` is just clutter, and worse, a stale file from a previous run will silently mislead the next invocation if the user re-runs the skill and forgets to re-export. `rm <selection.json>` after the apply step succeeds, regardless of whether individual folders failed inside the apply.

## A note on regeneration

If the user looks at the preview and asks to regenerate a few cards (e.g. "make the icon for `acme-co` cleaner, less busy"), don't restart from scratch. Reuse the existing manifest, regenerate only the named entries (passing the user's notes as extra prompt context for AI gen, or picking a different emoji / SF Symbol), and rebuild the preview. The state lives in the workspace temp dir.

## Why this shape

A few things worth explaining so you can extend the skill thoughtfully:

- **Consistency-first style detection.** Folder icons live in spatial groups — the user sees them all at once in Finder. A single off-style icon stands out worse than a slightly-wrong-but-consistent one. That's why step 2 picks a method for the whole batch, not per-folder.
- **Don't ship Apple's folder PNG.** Extracting from `CoreTypes.bundle` at runtime keeps us legally clean and means the icon matches the user's current macOS version (the folder shape evolves between releases).
- **AskUserQuestion sparingly.** The user invoked the skill because they didn't want to think about each folder; asking about every one defeats the purpose. Only ask when the folder's purpose is genuinely opaque from the signals.
- **Preview before apply, always.** Setting a folder icon is reversible, but it touches the resource fork and changes what Finder shows. The cost of a preview round-trip is small; the cost of a wrong batch is annoying.
