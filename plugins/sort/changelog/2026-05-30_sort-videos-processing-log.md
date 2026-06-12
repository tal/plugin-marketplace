# sort-videos: prepend-only processing log

## What changed

Added a prepend-only processing log to the `sort-videos` skill. Every video the skill processes now gets recorded in `<target>/AI Library/_processing-log.md`, newest entry on top.

## Details

- **New script** `scripts/log-video.sh` — reads an entry from stdin and atomically prepends it to the given log file (write to temp, then `mv`). New entries land on top; existing content is preserved untouched.
- **New step 8 ("Append to the processing log")** in `skills/sort-videos/SKILL.md`. Renumbered the former steps 8 and 9 to 9 (Parallel processing) and 10 (Report).
- The log lives at the **root of the AI Library** so it travels with the library. The leading underscore in `_processing-log.md` keeps it out of the topic-folder candidate list used during categorization (step 5's `grep -vE '^(Review|_|\.)'`).
- **Prepend-only semantics:** past entries are never edited or removed. Re-runs add a fresh entry tagged `(reprocess)`; skipped videos are logged too, with the reason — so the log is a complete record of everything the skill has touched.

## Entry format

Each entry captures timestamp, final filename, type (`short-form` / `talk-or-lecture` / `skipped`), topic folder, source platform + video ID, resulting path, and a one-line summary.
