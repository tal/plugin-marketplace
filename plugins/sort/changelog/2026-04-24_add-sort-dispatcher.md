# Add `/sort` dispatcher skill

Added a top-level `/sort` skill that scans `~/Downloads/`, classifies each item by type, and routes it to the right pipeline. The existing `/sort-videos` skill stays independently invocable; `/sort` delegates to it for video files via the Skill tool.

## Decisions (from interview)

- **Folder layout**: single unified library under `~/Downloads/AI Library/`. Images, apps, archives live as sibling topic folders next to the existing video categories.
- **Topic reuse**: prefer existing categories (`Tech`, `Music`, `Food & Restaurants`, `Game Recs`, etc.). Create new top-level topics only when nothing fits.
- **Archive peek**: always run `unzip -l` / `tar -tzf` / `hdiutil` to read contents before extracting.
- **Zip grouping**: image groups from a zip stay together inside `AI Library/<Topic>/<zip-basename>/`.
- **Image sorting**: obvious types first (screenshots, memes, photos via EXIF), then a vision agent tags the remainder into topic folders.
- **Video routing**: delegate 100% of video files to `/sort-videos`.
- **Uncertainty**: AskUserQuestion is used when classification is weak or ambiguous, batched per run (not one prompt per file).
- **Delete policy**: never delete by default. Single auto-delete exception: installers whose app is already present in `/Applications/` — applies uniformly to `.dmg`/`.iso` disk images, `.pkg` installers, and `.zip`/`.7z`/`.tar.gz`/`.rar` archives that contain a `.app` bundle. Detection: bundle-ID match via `mdfind` against `/Applications/`, with `.app`-name fallback.

## Type pipelines

| Type | Pipeline |
|---|---|
| video | delegate to `/sort-videos` |
| image | obvious-type detection → vision-agent topic tagging |
| archive | peek listing → extract as app installer, image group, or ask |
| disk-image (.dmg/.iso) | `hdiutil attach -nobrowse`, route the `.app` or `.pkg` inside |
| installer (.pkg) | check `/Applications/` for already-installed equivalent |
| app-bundle (.app) | bundle-ID lookup in `/Applications/` → delete installer or move |
| document | move to `AI Library/Review/` for manual triage |
| unknown | move to `AI Library/Review/` |

## Files

- `plugins/sort/skills/sort/SKILL.md` — new dispatcher
- `plugins/sort/.claude-plugin/plugin.json` — broadened description
- `.claude-plugin/marketplace.json` — updated marketplace description
