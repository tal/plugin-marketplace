---
name: sort-videos
description: Transcribe, summarize, and categorize downloaded videos — defaults to the folder Claude Code was launched in. Trigger on `/sort-videos`, when the user references a video file (yt-dlp output, Instagram reels, TikTok, YouTube downloads, conference talks, lectures), or asks to "transcribe this video", "summarize this talk", "make notes from this reel", "save this talk for listening later", "what's in this video", or "reprocess a video" — even when they don't say "sort". Transcribes with whisper-cpp, optionally OCRs frames for on-screen text, enriches from Instagram oEmbed captions, detects talks/lectures for an extended summary format, exports a tagged MP3 for talks, renames with a content-derived slug, moves into `<target>/AI Library/<topic>/` (created if absent), and writes a companion `.md` summary with YAML frontmatter (source URL, creator, tags, description). Videos belonging to an **audio-only topic** (default: `Comedy`) skip transcription, OCR, and summarization entirely — they just get a tagged MP3 exported alongside the video. Pass a file path or glob to reprocess a specific video.
user-invocable: true
context: fork
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---

# Sort and Transcribe Downloaded Videos

Arguments passed: `$ARGUMENTS`

## 0. Determine target videos

The **target folder** is wherever the videos live and where the AI Library should be created. Resolution order:

1. If `$ARGUMENTS` is a directory path, that's the target folder (search videos inside it).
2. If `$ARGUMENTS` is a file path or glob, the target folder is the parent of those files.
3. Otherwise, the target folder is the **current working directory** — the folder Claude Code was launched in.

The skill is **location-agnostic**: it works on `~/Downloads`, `~/Desktop`, a project folder, or anywhere else.

**If arguments were provided** (a file path, glob pattern, or filename):

- Resolve the path. It may be:
  - An absolute path
  - A relative path from the current working directory
  - A filename to search for under the target folder (recursive, including `<target>/AI Library/`)
  - A glob pattern (e.g., `*.mp4`, `<topic>/*.webm`)
- The file may already live inside `<target>/AI Library/` — that's fine for re-runs. Process it in place.
- For re-runs of files already in AI Library: the video stays in its current folder unless the user asks to re-categorize. Re-generate the `.md` file alongside it, overwriting any existing one.

**If no arguments were provided** (batch mode):

Find video files at the root of the target folder and in `<target>/Recents/` if it exists. Match any common video extension: `.mp4`, `.webm`, `.mkv`, `.avi`, `.mov`, `.flv`, `.m4v`, `.ts`, `.wmv`. Common yt-dlp naming pattern: `<Platform> - <title> [<id>].<ext>` (e.g., `Instagram - Video by stuartbrazell [DWM02r5EtFq].mp4`). Also match the legacy pattern `Video by*.<ext>` for older downloads. Do NOT include files already inside `<target>/AI Library/`.

Create `<target>/AI Library/` if it doesn't exist before moving anything: `mkdir -p "<target>/AI Library"`.

## 0.5. Load user rules and conventions (optional)

Before processing, check for the same user override files the `/sort` dispatcher reads. This step is **optional and best-effort**: if none of these files exist, skip it entirely and proceed normally. Read **every** file that exists and combine them, in this priority order (highest first):

1. `$PWD/.claude/sort.local.md` — project-local (gitignored)
2. `$PWD/.claude/sort.md` — project-shared (committable)
3. `~/.claude/sort.local.md` — user-global (gitignored)
4. `~/.claude/sort.md` — user-shared

Parse the YAML frontmatter with `yq` if installed, otherwise the bundled `${CLAUDE_PLUGIN_ROOT}/scripts/match-rules.rb --rules-only`, which merges all four files in priority order. The free-form markdown body **below** each file's frontmatter is user context — read it too. For the rule schema and matcher/action lists, see `${CLAUDE_PLUGIN_ROOT}/skills/sort/OVERRIDES.md`.

Apply whatever is relevant to the video pipeline; ignore the rest:

- **`route` / `prompt` rules** whose matcher fires on a video's filename (`ext`, `filename_glob`, `filename_regex`, `mime_type`, `size_*`) pin that video to the rule's destination folder — honor it in place of the step 5 categorization. A `delete` rule (e.g. on a `.torrent`) means skip the video; a `skip` rule leaves the file untouched.
- **Free-form body context and per-topic conventions** inform steps 5 and 6. For example, a user can document how a given topic's notes should be tagged (e.g. a recipe tagging vocabulary), and you apply it when writing that note's frontmatter `tags`.
- **`paprika_sidecar` opt-in (frontmatter key).** If a merged override file sets the top-level frontmatter key `paprika_sidecar: enabled`, the Paprika export sub-step in §6.5 is turned on for recipe notes. It is **off** unless this key is explicitly present and set to `enabled` — never emit sidecars otherwise. Any other value (or absence) means disabled.
- **`audio_only_topics` (frontmatter key).** A list of topic folder names that get an MP3 and no transcript or summary — see §0.6. Unlike `paprika_sidecar` this one has a **non-empty default (`[Comedy]`)**, so a user who wants comedy transcribed like everything else has to set `audio_only_topics: []` explicitly.

User rules and documented conventions take precedence over this skill's defaults. When nothing matches, fall back to the normal flow.

## 0.6. Audio-only topics (no transcription, no summary)

Some topics are for **listening**, not reading. A standup special is the motivating case: a transcript of it is worthless — the timing is the act — and a written summary of jokes actively destroys them. What you actually want is the audio on your phone.

A video whose topic is in the **audio-only set** therefore gets a tagged MP3 and nothing else:

| Step | Audio-only topic |
|---|---|
| §1 transcription (whisper) | **skipped** |
| §2 OCR | **skipped** — don't even ask |
| §3 oEmbed caption enrichment | **skipped** |
| §4 talk/lecture detection | **skipped** — the classification is moot |
| §5 categorization | from the filename, see below |
| §6 rename + move | yes, but slug comes from the title, and **no `.md` is written** |
| §6.5 Paprika sidecar | **skipped** |
| §7 MP3 export | **yes — this is the only output** |
| §8 processing log | yes, with `Type: audio-only` |

The video file itself is **kept** — it is renamed and moved as usual, and the MP3 lands beside it. Never delete the video to save space unless the user explicitly asks.

**Default audio-only set: `Comedy`.**

Override it with the top-level frontmatter key `audio_only_topics` in any of the §0.5 override files (the highest-priority file that sets the key wins, per-key):

```yaml
audio_only_topics: [Comedy, Music, Stand-Up]   # replaces the default set
audio_only_topics: []                          # disables the behavior entirely
```

Matching is case-insensitive against the topic folder name.

### Deciding before you transcribe

Normal categorization (§5) reads the transcript — but an audio-only video never gets one, so the call has to be made from the filename **first**, before any ffmpeg or whisper work:

1. **Pre-classify from the filename, title, and creator alone.** yt-dlp filenames carry plenty of signal: `(Full Comedy Special)`, `(Full Special)`, `Stand-Up`, `Standup`, `Live at the Apollo`, `: A Comedy Special`, a comedy channel or club name, `Netflix Is A Joke`, `Dry Bar Comedy`, and so on.
2. **If that confidently lands in an audio-only topic**, jump straight to §6 → §7 → §8 and stop. Do not convert to WAV. Do not run whisper. That is the entire point of this step: a 42-minute special should cost one ffmpeg pass, not a transcription plus a written summary nobody wants.
3. **If a §0.5 `route` rule pins the video** to a folder that's in the audio-only set, that counts as a confident pre-classification — honor it and skip transcription.
4. **If the filename is genuinely ambiguous**, fall through to the normal flow: transcribe, then categorize in §5. If §5 *then* lands on an audio-only topic, still honor it — export the MP3, skip the `.md`, and discard the transcript. A wasted transcription is acceptable; a wrong topic is not.
5. **Don't ask when the filename is explicit** — `(Full Comedy Special)` is explicit. Only use AskUserQuestion when you can't tell from the filename and don't want to transcribe 40 minutes to find out.

For each video found, do the following:

## 1. Transcribe

**Skip this entire step when §0.6 pre-classified the video into an audio-only topic** — no WAV conversion, no whisper. Go straight to §6.

- Convert the video to 16kHz mono WAV using ffmpeg: `ffmpeg -i "<video>" -ar 16000 -ac 1 -c:a pcm_s16le /tmp/<slug>.wav -y`
- Transcribe with whisper-cpp: `whisper-cli -m /tmp/ggml-base.bin -f /tmp/<slug>.wav --no-timestamps`
- If the whisper model isn't downloaded yet, fetch it: `curl -L -o /tmp/ggml-base.bin "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"`
- If the transcription is blank/silent, skip the video and report it at the end.

## 2. Visual text extraction (per-video opt-in)

**Skip for audio-only topics (§0.6) — and don't ask.** There's no `.md` for the extracted text to land in, so the question would be dead weight.

For each video, use AskUserQuestion to ask the user whether they want to perform OCR on this specific video. Present these options:

- **No, skip OCR** — just use audio transcription
- **Yes, text only** — extract on-screen text (captions, recipes, lists, instructions)
- **Yes, text + product ID** — extract text AND identify products by visual appearance (useful for product recommendations, ingredients shown as images)

If the user says yes to either OCR mode:

1. Extract frames using the bundled script:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/extract-frames.sh" "<video>" "/tmp/<slug>_frames" 2
   ```
   The `2` is the interval in seconds (1 frame every 2 seconds). The script outputs the frames directory path.

2. Launch the `video-ocr` agent with the frames directory and the selected mode (`text-only` or `text-and-products`):
   ```
   Analyze the frames in /tmp/<slug>_frames/ for on-screen content.
   Mode: <text-only|text-and-products>
   ```

3. The agent returns structured markdown. Merge its output into the final `.md` file under an `## On-Screen Text` section (after the transcription content).

4. Clean up frames: `rm -rf /tmp/<slug>_frames/`

## 3. Enrich from source

**For audio-only topics (§0.6), skip the caption fetch** — there's nothing to enrich. You still parse the filename for the platform, creator, and video ID, because §6 and §7 need them for the new name and the MP3 tags.

After transcribing, extract the video ID from the filename (the `[XXX]` part before the extension) and the platform prefix (e.g., `Instagram`, `TikTok`, `Youtube`).

For **Instagram** videos, fetch the post caption via the oEmbed API:

```
curl -s "https://www.instagram.com/api/v1/oembed/?url=https://www.instagram.com/reel/<VIDEO_ID>/" | jq -r '.title'
```

For other platforms, skip the oEmbed step and rely on the transcription.

Use the caption to enrich the markdown in the following cases:

- **Recipes:** If the transcription is about cooking/food, check the caption for a full ingredient list with measurements and detailed instructions. Replace or supplement the transcription-based recipe with the exact quantities from the caption.
- **Lists of items:** If the transcription references a list (e.g., game recommendations, restaurants, products, tips), check the caption for the complete list with details. Include the full list in the markdown rather than relying solely on what was spoken.

If the oEmbed request fails or returns no useful caption, proceed with just the transcription.

## 4. Detect talks and lectures

**Skip for audio-only topics (§0.6).** The distinction only exists to pick a markdown body format, and there is no markdown. Type those videos `audio-only` and move on — a standup special would otherwise trip every talk/lecture signal (long, single speaker, audience laughter and applause) and earn itself an outline and a Key Points section, which is exactly the outcome §0.6 exists to prevent.

Classify each video as either `short-form` or `talk-or-lecture`. Talks/lectures get a more extensive summary in the markdown file (see step 6).

Use two signals — length and content — and combine them:

**Length signal** — get the duration with ffprobe:

```
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "<video>"
```

- `< 5 min`: almost certainly short-form. Classify as `short-form` without asking.
- `5-15 min`: ambiguous. Use content signal to decide; ask if still unsure.
- `> 15 min`: likely a talk/lecture. Use content signal to confirm; ask if content signal disagrees.

**Content signal** — look at the transcription for lecture/talk patterns:

- Sustained monologue by one speaker on a single topic
- Clear structure: introduction → thesis/argument → supporting points → conclusion
- Academic, technical, or conference register (defines terms, cites sources, references slides)
- Q&A segments, moderator intros ("please welcome…"), or audience laughter/applause
- Phrases like "today I'm going to talk about", "in this talk", "the thesis of this lecture", "any questions?"

Strong short-form signals that override length: recipe walkthrough, product haul, skit, vlog, reaction, tutorial < 10 steps, gameplay clip.

**When to ask the user** — if the signals disagree or are weak (e.g., a 12-minute cooking video that happens to be monologue-style, or a 20-minute podcast clip that isn't really a talk), use AskUserQuestion with options:

- **Treat as short-form** — standard summary
- **Treat as talk/lecture** — extended summary with outline, key points, and takeaways

Do NOT ask when the classification is obvious (a 2-minute Instagram reel, or a clearly labeled conference talk from YouTube). Only ask when genuinely uncertain.

## 5. Categorize

Based on the transcription (and OCR / caption enrichment, if collected), determine the best topic folder under `<target>/AI Library/`.

**If a user rule from §0.5 already pins this video to a folder** (a matching `route`/`prompt` rule), use that destination and skip the discovery below.

**If §0.6 already pre-classified this video from its filename**, that's the topic — you have no transcript to reconsider it with. Still run the folder-discovery `ls` below, so you reuse the folder as it is actually spelled on disk (`Comedy`, not a newly invented `Stand-Up`).

**Discover existing folders at runtime — never hardcode topic names.** Each folder builds up its own taxonomy across runs, and a folder list that ships with the skill would be wrong for everyone:

```bash
ls -1 "<target>/AI Library/" 2>/dev/null | grep -vE '^(Review|_|\.)'
```

Use that list as the candidate set. **Reuse an existing folder whenever the content plausibly fits** — that's how the user's taxonomy stays coherent over time, and minor variation ("Productivity" vs. "Self-Improvement") will fragment the library if you're too eager to create new folders.

Only create a new folder when nothing existing fits. Pick a descriptive 1-3 word Title Case name (e.g., `Cooking`, `Woodworking`, `Personal Finance`). Avoid hyper-specific names that won't catch future videos — prefer broad-but-clear topic names.

For videos classified as `talk-or-lecture` in step 4: pick a subject folder when one obviously matches the topic (a tech talk → tech-related folder if the user has one). Otherwise default to a folder named for educational content if one already exists, or fall back to creating one named `Talks & Lectures` only if the user has nothing similar yet.

## 6. Rename, move, and create markdown

**For audio-only topics (§0.6) — rename and move, but write no markdown:**

- Rename and move the video exactly as described below, with one difference: derive the `<brief-description>` slug from the **original title in the filename** instead of from the content, because there is no transcript to derive it from. Strip parenthetical boilerplate (`(Full Comedy Special)`, `(Full Special)`, `(Official)`), drop the creator name where the title just repeats it, and keep it to 2-5 lowercase hyphenated words. `youtube - Emily Catalano ｜ The Introvert (Full Comedy Special) [bt_I3nJmQ3I].webm` → `the-introvert - Youtube - Emily Catalano [bt_I3nJmQ3I].webm`.
- **Write no `.md` file**, and skip §6.5. Go to §7.
- On a re-run, if a `.md` from an earlier transcribing run already sits next to the video, **leave it alone** — deleting notes the user may value is not this skill's call. Note it in the §10 report so they can decide.

**For new videos (not yet in AI Library):**

- Rename the video file to include a brief description of the content while keeping the platform, creator name, video ID, and original extension. Format: `<brief-description> - <platform> - <creator name> [<video ID>].<original-ext>` (e.g., `sesame-chicken-recipe - Instagram - Video by louishowardpt [DVs_UEwiIx9].mp4`). For legacy files without a platform prefix, use `Instagram` as the default. Keep the description short (2-5 words, lowercase, hyphenated).
- Create the topic folder under `<target>/AI Library/` if it doesn't exist.
- Move the renamed video file into that folder.

**For re-runs (file already in AI Library):**

- Keep the video in its current location and folder — do not move or rename it unless the user explicitly asks to re-categorize.
- Overwrite the existing `.md` file with fresh content.

**In both cases**, create a matching `.md` file with the same base name.

**Every `.md` file starts with a YAML frontmatter block** populated from the data gathered in steps 1-5:

```yaml
---
source_url: https://www.instagram.com/reel/<VIDEO_ID>/
platform: Instagram
creator: louishowardpt
video_id: DVs_UEwiIx9
type: short-form
topic: Cooking
tags: [cooking, recipe, sesame-chicken]
description: Quick sesame chicken recipe with a 3-ingredient sauce.
processing: [transcript, ocr-text, caption-enrichment]
retrieved_sources: [https://www.instagram.com/api/v1/oembed/?url=https://www.instagram.com/reel/DVs_UEwiIx9/]
processed: 2026-06-11
---
```

Field rules:

- `source_url` — reconstruct the original link from the platform prefix and video ID in the filename: Instagram → `https://www.instagram.com/reel/<ID>/`, YouTube → `https://www.youtube.com/watch?v=<ID>`, TikTok → `https://www.tiktok.com/@<creator>/video/<ID>`. If the platform or ID is unknown and the link can't be reconstructed, omit the field rather than guessing.
- `platform` — the platform prefix from the filename (`Instagram`, `TikTok`, `Youtube`, …).
- `creator` — the creator's username/handle from the filename (e.g., the `louishowardpt` in `Video by louishowardpt`), without any `@` prefix. For Instagram this is the account username; prefer the handle from the oEmbed response (step 3) if it differs from the filename.
- `video_id` — the `[XXX]` ID from the filename, without brackets. Omit if there is none.
- `type` — the classification from step 4: `short-form` or `talk-or-lecture`.
- `topic` — the topic folder chosen in step 5, exactly as named on disk.
- `tags` — 3-7 lowercase hyphenated keywords derived from the content (transcription, caption, OCR). Specific enough to search on later (`sesame-chicken`, not just `food`), inline-array syntax. **If §0.5 surfaced a tagging convention for this topic** (e.g. a recipe tag vocabulary), follow it — its vocabulary and tag count take precedence over this generic guidance. When updating an existing note, merge new tags into the current `tags` array rather than dropping any.
- `description` — one sentence (≤ 150 chars) summarizing the video. This can double as the source for the renamed file's brief-description slug.
- `processing` — inline array of every processing step actually performed on this video, drawn from: `transcript` (whisper-cpp succeeded), `ocr-text` (step 2, text-only mode), `ocr-products` (step 2, text + product ID mode), `caption-enrichment` (step 3 oEmbed caption was fetched AND used), `mp3-export` (step 7 produced an MP3). List only what really happened — if OCR was declined or the oEmbed call failed, the entry doesn't appear. A skipped/blank-audio video that still gets an `.md` would have `processing: []`.
- `retrieved_sources` — inline array of the URLs of every website/API actually fetched to augment the summary (the step 3 oEmbed endpoint, plus anything else retrieved — a recipe page, a speaker's site, a conference page). List the exact URLs requested, only for fetches that succeeded and contributed content. Omit the field entirely (or use `[]`) when nothing was retrieved. Note this is *fetched* sources, not links merely mentioned in the video — those belong in the body's `## References` section.
- `processed` — today's date, `YYYY-MM-DD`.

On re-runs, regenerate the frontmatter along with the body — but keep the original `processed` date if the existing `.md` has one, since the file's history lives in the processing log (step 8).

**Below the frontmatter**, the body structure depends on the classification from step 4:

**For `short-form` videos:**

  - An H1 title: `# Video by <creator name>`
  - An H2 subtitle summarizing the video topic
  - The transcription, cleaned up and formatted nicely with markdown (lists, bold for names/titles, sections where appropriate)
  - If OCR was performed, an `## On-Screen Text` section with the extracted visual content
  - Extract and highlight key items (game names, restaurant names, tips, people, etc.) rather than dumping raw transcript text.

**For `talk-or-lecture` videos** — write an extended summary that a reader could skim in 2-3 minutes to get most of the value:

  - An H1 title: `# <Talk title> — <Speaker name>` (use the best available title from the caption, transcription intro, or filename)
  - A `## TL;DR` section: 2-4 sentences stating the thesis and the main conclusion
  - A `## Outline` section: a bulleted list of the major sections/topics in order, each with a one-line description
  - A `## Key Points` section: the 5-10 most important arguments, claims, or ideas, each as a short paragraph with context
  - A `## Notable Quotes` section: 2-5 direct quotes worth remembering, with speaker attribution if there are multiple speakers
  - A `## Terms & Concepts` section (if applicable): definitions of jargon, frameworks, or named concepts introduced in the talk
  - A `## References` section (if applicable): books, papers, people, tools, or prior work cited by the speaker
  - A `## Q&A Highlights` section (if a Q&A is present): the most interesting exchanges, summarized
  - A `## Takeaways` section: 3-5 bullets of actionable or memorable conclusions for the viewer
  - If OCR was performed, an `## On-Screen Text` section with the extracted visual content (slide text is especially valuable for talks)

Do not dump the raw transcript in the talk/lecture format — the extended summary replaces it.

## 6.5. Paprika recipe sidecar (optional, opt-in)

**Skip this step entirely unless §0.5 found `paprika_sidecar: enabled` in a merged override file.** It is off by default; only run it when the user has explicitly opted in.

When enabled, and only for notes that are actually recipes (a recipe note has ingredient + instruction content — the kind of thing tagged with meal-type tags like `dinner`/`snack`/`dessert`), emit a Paprika-importable `.paprikarecipe` sidecar next to the `.md` note so the recipe can be one-click imported into Paprika Recipe Manager.

Build a JSON payload from the recipe content you already extracted for the note (steps 1-3), then pipe it to the bundled script:

```bash
echo '<payload JSON>' | python3 "${CLAUDE_PLUGIN_ROOT}/scripts/make_paprikarecipe.py" -
```

Payload fields (only `note_path` is required; omit anything you don't have):

- `note_path` — absolute path to the `.md` note just written. The sidecar is written beside it as `<base>.paprikarecipe`, the uid is derived deterministically from the base name (stable across re-runs — re-importing the same file won't create a second copy under Paprika cloud sync), and categories default to `AI Library` + the meal-type tags from the note's frontmatter.
- `name` — recipe title (Title Case, e.g. `Banana Almond Cookie Dough Bark`), not the filename slug.
- `ingredients` — newline-separated, one item per line; blank lines allowed to separate sub-sections (e.g. `Sauce:` headers).
- `directions` — newline-separated numbered steps (`1. …\n2. …`).
- `description`, `notes`, `source` (creator handle), `source_url`, `prep_time`, `cook_time`, `total_time`, `servings` — fill from the note when known, else omit.
- `is_reconstructed` — set `true` if the full recipe was reconstructed/adapted rather than taken verbatim from the source; this adds a `Reconstructed` category.
- `photo_path` — optional. If omitted, the script auto-extracts the **first frame** of the sibling `.mp4` (via `ffmpeg`) and embeds it as the recipe photo.

The script is pure standard library (no `pip install` needed) and idempotent: re-running preserves the original `created` timestamp and overwrites in place. Report the sidecar in step 10 only when one was written.

## 7. Audio export

Export a tagged MP3 alongside the video so it can be listened to later (e.g., on a phone or in a podcast app). This step runs for:

- **`talk-or-lecture` videos** — the MP3 accompanies the markdown summary.
- **Audio-only topics (§0.6)** — the MP3 *is* the deliverable. If ffmpeg fails here, the video has produced no output at all, so unlike the talk case this is a hard failure: report it loudly in §10 and log it as `skipped` with the reason in §8.

Skip this step for `short-form` videos in a normal (non-audio-only) topic.

- Output path: same folder and base name as the video, with `.mp3` extension (e.g., `<brief-description> - <platform> - <creator name> [<video ID>].mp3`).
- Use ffmpeg to extract and tag in a single pass:

  ```
  ffmpeg -i "<video>" -vn -acodec libmp3lame -b:a 128k \
    -metadata title="<talk title>" \
    -metadata artist="<speaker name>" \
    -metadata album_artist="<speaker name>" \
    -metadata album="<series, conference, or platform>" \
    -metadata genre="Speech" \
    -metadata date="<YYYY if known>" \
    -metadata comment="<one-line TL;DR from the markdown>" \
    -id3v2_version 3 \
    "<output>.mp3" -y
  ```

- Populate the tags from the data already gathered:
  - `title` — the talk title (same as the H1 in the markdown, without the speaker suffix). *Audio-only:* the original title from the filename, cleaned and Title Cased with boilerplate stripped — `The Introvert`.
  - `artist` / `album_artist` — the speaker's name (fall back to the creator/channel name from the filename if unknown). *Audio-only:* the performer from the filename — `Emily Catalano`.
  - `album` — the conference, lecture series, podcast, or platform (e.g., `YouTube`, `TED`, `Strange Loop 2024`). Fall back to the platform prefix from the filename.
  - `genre` — `Speech` (use `Podcast` if the source is clearly a podcast episode). *Audio-only:* use the topic folder name — `Comedy` for a standup special — so it shelves itself sanely in a podcast app or music library.
  - `date` — the year, if it can be inferred from the caption or transcription; otherwise omit
  - `comment` — the TL;DR text from the markdown, trimmed to a single line. *Audio-only:* **omit it.** There is no summary, and manufacturing a one-liner would mean watching the thing — which is the work §0.6 exists to avoid.
- If ffmpeg fails (e.g., corrupt audio) on a `talk-or-lecture`, log the failure and continue with the rest of the pipeline — the markdown summary is still the primary output. On an audio-only topic there is no fallback output, so treat it as a hard failure per the note above.

## 8. Append to the processing log

After a video is fully processed (moved, markdown written, and MP3 exported for talks and audio-only topics), record it in the **prepend-only processing log** that lives at the root of the AI Library:

```
<target>/AI Library/_processing-log.md
```

The log is **prepend-only**: new entries go on top (newest first), and past entries are **never edited or removed** — not even on re-runs. Re-processing a video that's already in the library adds a *new* entry noting it's a reprocess, leaving the original entry intact. The leading underscore keeps the file out of the topic-folder candidate list from step 5.

Build a compact markdown entry, then prepend it with the bundled script (entry text on stdin):

```bash
printf '## %s — %s\n- **Type:** %s\n- **Topic:** %s\n- **Source:** %s\n- **Path:** %s\n- **Summary:** %s\n' \
  "$(date '+%Y-%m-%d %H:%M')" \
  "<final filename>" \
  "<short-form|talk-or-lecture|audio-only>" \
  "<topic folder>" \
  "<platform> [<video ID>]" \
  "AI Library/<topic>/<final filename>" \
  "<one-line summary>" \
| bash "${CLAUDE_PLUGIN_ROOT}/scripts/log-video.sh" "<target>/AI Library/_processing-log.md"
```

For re-runs, append ` (reprocess)` to the `Type` field so the history is self-explanatory. If a video was skipped (blank audio, error), still log it with the reason in `Summary` and `skipped` as the `Type` — the log is a complete record of everything the skill has touched.

For **audio-only** topics (§0.6), the `Type` is `audio-only` and the `Summary` is the one thing you honestly know without a transcript: the original title and performer, e.g. `Standup special "The Introvert" by Emily Catalano — audio exported, not transcribed`. Don't guess at content you never processed.

## 9. Parallel processing

- Convert all videos to WAV in parallel (background ffmpeg jobs).
- Transcribe all videos in parallel (separate bash calls or subagents).
- MP3 exports for talks/lectures can also run in parallel once classification is complete.
- Audio-only videos (§0.6) have no WAV or transcription stage at all, so kick their MP3 exports off immediately, in parallel with everyone else's transcriptions. They finish first and cost the least.

## 10. Report

When finished, print a summary table of all videos processed:

| Video | Type | Topic Folder | Outputs | Summary |
|-------|------|-------------|---------|---------|

- `Type` — `short-form`, `talk-or-lecture`, or `audio-only`
- `Outputs` — `md` for a normal video, `md + mp3` for talks/lectures, and `mp3` for audio-only topics (no `md` by design — say so in the row rather than leaving it looking like a failure)

Also list any videos that were skipped (blank audio, errors, etc.).

When any video took the audio-only path, add one line under the table stating the rule that fired and how to turn it off — e.g. *"Comedy is an audio-only topic, so these were exported as MP3 and not transcribed or summarized. Set `audio_only_topics: []` in `sort.md` to transcribe comedy like everything else."* A user who has forgotten they configured this should not have to wonder why their special has no notes. Mention any pre-existing `.md` files you deliberately left in place, too.
