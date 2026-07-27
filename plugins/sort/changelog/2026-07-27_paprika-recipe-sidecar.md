# sort-videos: Paprika recipe sidecar export (opt-in)

## What changed

`/sort-videos` can now write a Paprika-importable `.paprikarecipe` sidecar next to a recipe note's `.md` file, so a processed recipe reel/video can be one-click imported into Paprika Recipe Manager. The feature is off by default and only activates when a user explicitly opts in.

## New: §0.5 user rules and conventions

Added a new step to `SKILL.md` that ports the same override-loading pattern already used by the `/sort` dispatcher and `documents.md` sub-dispatcher into the video pipeline:

- Reads and merges `$PWD/.claude/sort.local.md`, `$PWD/.claude/sort.md`, `~/.claude/sort.local.md`, `~/.claude/sort.md` in priority order (same files, same precedence as elsewhere in the plugin).
- `route` / `prompt` rules that match a video's filename now pin it to a destination folder (or skip/delete it), same as other sort pipelines.
- Free-form body context (e.g. a documented per-topic tagging vocabulary) now informs the `tags` frontmatter field written in step 6.
- The top-level frontmatter key `paprika_sidecar: enabled` turns the new §6.5 sidecar export on. Any other value, or the key's absence, leaves it off.

## New: §6.5 Paprika recipe sidecar

When enabled and the note is a recipe (ingredient + instruction content, meal-type tags), the skill builds a JSON payload from the already-extracted recipe content and pipes it to `scripts/make_paprikarecipe.py`, which writes `<base>.paprikarecipe` beside the `.md` note.

- Pure standard library — no `pip install` needed.
- Idempotent: re-running preserves the original `created` timestamp and overwrites in place.
- The `uid` is derived deterministically from the note's base filename, so re-imports don't create duplicate recipes under Paprika's cloud sync.
- If no `photo_path` is supplied, the script auto-extracts the first frame of the sibling `.mp4` via `ffmpeg` and embeds it as the recipe photo.
- Categories default to `AI Library` plus any meal-type tags (`breakfast`, `brunch`, `lunch`, `dinner`, `snack`, `dessert`, `side`) found in the note's frontmatter; `is_reconstructed: true` adds a `Reconstructed` category.

## Files touched

- `plugins/sort/skills/sort-videos/SKILL.md` — added §0.5 (user rules/conventions) and §6.5 (Paprika sidecar), plus cross-references from steps 5 and 6.
- `plugins/sort/scripts/make_paprikarecipe.py` — new script; builds and writes the `.paprikarecipe` sidecar.
- `plugins/sort/README.md` — `/sort-videos` row now mentions the opt-in sidecar; `scripts/` layout list includes the new script.
