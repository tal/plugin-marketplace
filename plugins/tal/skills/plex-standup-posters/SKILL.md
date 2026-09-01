---
name: plex-standup-posters
description: Use when the user asks to process new YouTube or provider-managed stand-up/comedy-special downloads, fix wide thumbnails in the Plex Standup library, add folder metadata, find portrait posters, create missing comedy-special posters, add poster sidecars, or install and verify stand-up artwork in Plex. Handles the personal synfeld Standup-library workflow from discovery through sourced-or-generated 2:3 artwork and direct Plex selection.
---

# Plex Stand-up Posters

Process newly downloaded YouTube or provider-managed stand-up specials without changing videos, filenames, library agents, or unrelated media.

## Defaults

- Media host: `synfeld`
- Media directory: `/volume1/Media/Standup`
- Plex library title: `Standup`
- Credentials file: `/Users/tal/Projects/darr-manager/.env`
- Required poster output: JPEG, exactly `1000x1500`
- Helper: `${CLAUDE_PLUGIN_ROOT}/skills/plex-standup-posters/scripts/plex-standup-posters.sh`

The helper accepts overrides through `PLEX_MEDIA_HOST`, `PLEX_MEDIA_ROOT`, `PLEX_LIBRARY_TITLE`, `PLEX_SECTION_KEY`, and `PLEX_ENV_FILE`. Never print `PLEX_TOKEN` or place it in a URL; send it only in the `X-Plex-Token` header.

## Workflow

### 1. Discover only the new YouTube downloads

Run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/plex-standup-posters/scripts/plex-standup-posters.sh inventory
```

The command lists top-level video files containing a YouTube-style `[video_id]` that do not have an exact same-basename `.jpg` sidecar. For provider-managed folders (for example, Netflix releases named with an IMDb ID), separately inventory folders containing a video but no `movie.nfo` or poster sidecar. Treat these lists as the scope unless the user names additional files.

Before any writes, inspect the discovered paths and report the count. Preserve filenames exactly, including punctuation, Unicode, and format suffixes such as `.f625`.

### 2. Resolve the real comedian and special title

Use the bracketed video ID with YouTube oEmbed or the official video page. Do not infer the comedian solely from a downloader's filename: a title token can be a special name, as with `Terapy`, rather than the performer.

Record at least:

- YouTube ID
- exact video path
- comedian
- special title
- local poster path

If the title or performer is ambiguous, investigate before creating art. Do not guess.

### Provider-managed folder metadata

For a provider-managed folder, keep the existing folder and video names. Write `movie.nfo` in that folder with the exact title, original title, plot, premiere date, studio/provider, `Comedy` and `Stand-Up Comedy` genres, provider tag where appropriate, TMDB and IMDb unique IDs, director(s), and performer as an actor. XML-escape ampersands and other special characters. A folder-side `movie.nfo` is the durable metadata source even when the legacy Plex YouTube agent does not ingest it automatically; apply the same fields through Plex's item metadata endpoint when necessary, then verify the resulting title/date/summary.

### Add the performer to Plex's cast

Every special should list the person performing it as an actor, with the role left blank (or `Self` in the NFO). After resolving the Plex `ratingKey`, run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/plex-standup-posters/scripts/plex-standup-posters.sh actor \
  RATING_KEY \
  'Performer Name'
```

The helper uses Plex's `actor[0].tag.tag` field and verifies the name appears in the item's `Role` collection. Do this for both YouTube files and provider-managed folders. Do not refresh metadata afterward, because the legacy YouTube agent can erase manually added cast data.

This creates a text cast tag only. It does **not** create a Plex Discover person association (`tagKey`), so it will not necessarily open a performer's filmography. Plex's normal metadata API does not expose a supported cast-linking operation for these legacy-agent items. Do not claim that a person is linked unless the returned `Role` contains a canonical `tagKey` and `thumb`.

If canonical filmography links are required, stop and present the tradeoff before proceeding: migrate the library/items to a Plex metadata provider that supplies canonical cast (which may replace custom metadata), or perform a separately backed-up, Plex-stopped database migration. Never silently change the library agent or edit the live database.

### 3. Source portrait art before generating it

Search current sources in this order:

1. TMDB movie search and poster records
2. The comedian's or distributor's official page
3. Reputable streaming or retail listings
4. General image search

Accept a source only after visually inspecting the actual image. It must:

- be portrait and close enough to 2:3 to crop safely;
- visibly include both the comedian's name and special title;
- be legible at Plex-card size;
- correspond to the exact special, not merely the performer.

Prefer the highest-resolution official image. A landscape YouTube thumbnail is a reference, not a finished Plex poster.

### 4. Generate only the posters that remain missing

Use the available image-generation skill/tool in image-edit mode with the official YouTube thumbnail as the reference. Inspect the reference first. Create one poster per call so each result has an independent prompt and output.

Require:

- a native vertical 2:3 composition, not blurred bars or a naive crop;
- the performer's recognizable likeness and the reference's visual identity;
- exact, prominent comedian and special-title text;
- no YouTube marks, play buttons, watermarks, dates, invented credits, or extra copy.

Copy generated assets into the active workspace and retain their official reference images. Report which posters were sourced and which were generated.

### 5. Normalize and inspect the complete batch

Convert every final poster to a stripped, high-quality `1000x1500` JPEG. A typical ImageMagick command is:

```bash
magick input.jpg -resize '1000x1500^' -gravity center -extent 1000x1500 -strip -quality 92 output.jpg
```

Do not run this blindly when the crop would remove a face, title, border, or meaningful design element. Recompose or extend the source instead. Build a labeled contact sheet and visually inspect the entire batch for spelling, legibility, cropping, duplication, and correct title-to-file mapping.

### 6. Scan once, then install each approved poster

The user's request to “do the same” authorizes poster sidecars and poster selection for the scoped Standup items. It does not authorize renaming videos, changing metadata agents, altering other Plex libraries, or touching non-YouTube media.

Scan only the Standup section:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/plex-standup-posters/scripts/plex-standup-posters.sh scan
```

Then install each poster using the exact remote video path:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/plex-standup-posters/scripts/plex-standup-posters.sh install \
  /absolute/local/poster.jpg \
  '/volume1/Media/Standup/exact video name [youtube_id].webm'
```

The helper validates the poster, writes an exact same-basename `.jpg` beside the video, finds the Plex item by YouTube ID in `Media.Part.file`, uploads the image to `/library/metadata/{ratingKey}/posters`, and confirms that an `upload://posters/...` asset is selected.

Direct upload is intentional: this library uses the legacy `com.plexapp.agents.youtube` agent, which may discover a local sidecar without selecting it. Keep the sidecar for portability and use the upload for reliable current display.

### 7. Verify the result Plex actually serves

Run for every installed item:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/plex-standup-posters/scripts/plex-standup-posters.sh verify \
  '/volume1/Media/Standup/exact video name [youtube_id].webm'
```

Verification must establish all three facts:

- the remote same-basename sidecar exists;
- Plex's selected poster key begins with `upload://posters/`;
- the selected image downloaded from Plex is exactly `1000x1500`.

For a batch, also inspect a contact sheet built from the images downloaded back from Plex. Finish with the processed count, sourced/generated split, sidecar count, Plex verification count, and workspace path containing the final art.

## Failure boundaries

- Stop before installing any mapping that lacks a unique video path, Plex rating key, or exact title; a YouTube ID is required only for YouTube-style files.
- If the Standup library cannot be resolved uniquely, do not scan another section.
- If an upload fails, leave already installed items intact, report the exact failed item, and resume from it after correction.
- If an actor update fails, leave the poster and metadata intact, report the affected rating key, and retry only that cast update.
- Never expose credentials in logs, skill output, generated files, or URLs.
- Do not delete source images, generated originals, videos, or existing artwork.
