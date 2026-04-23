---
name: sort-videos
description: This skill should be invoked when the user runs `/sort-videos` (with or without a path argument) or asks to "sort my downloaded videos", "transcribe and categorize videos", "organize my AI Library", "summarize a talk or lecture video", or "reprocess a video". Finds yt-dlp downloads in `~/Downloads`, transcribes them with whisper-cpp, optionally runs OCR on frames, enriches from Instagram oEmbed captions, detects talks/lectures (from length and content) for an extended summary format, exports a tagged MP3 for talks/lectures, renames, moves them into topic folders under `~/Downloads/AI Library/`, and writes a companion `.md` summary. Asks the user when the talk/lecture classification is uncertain. Pass a file path or glob to reprocess a specific video.
user-invocable: true
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

**If arguments were provided** (a file path, glob pattern, or filename):

- Resolve the path. It may be:
  - An absolute path (e.g., `/Users/tal/Downloads/AI Library/Comedy/some-video.mp4`)
  - A relative path from the current working directory
  - A filename to search for in `~/Downloads/` and `~/Downloads/AI Library/` (recursive)
  - A glob pattern (e.g., `*.mp4`, `Comedy/*.webm`)
- The file may already live inside `~/Downloads/AI Library/` — that's fine for re-runs. Process it in place.
- For re-runs of files already in AI Library: the video stays in its current folder unless the user asks to re-categorize. Re-generate the `.md` file alongside it, overwriting any existing one.

**If no arguments were provided** (batch mode):

Find all video files downloaded by yt-dlp in `~/Downloads` (root level) and `~/Downloads/Recents/`. Match any common video extension: `.mp4`, `.webm`, `.mkv`, `.avi`, `.mov`, `.flv`, `.m4v`, `.ts`, `.wmv`. Files follow the yt-dlp naming pattern: `<Platform> - <title> [<id>].<ext>` (e.g., `Instagram - Video by stuartbrazell [DWM02r5EtFq].mp4`). Also match the legacy pattern `Video by*.<ext>` for older downloads. Do NOT include files already inside `~/Downloads/AI Library/`.

For each video found, do the following:

## 1. Transcribe

- Convert the video to 16kHz mono WAV using ffmpeg: `ffmpeg -i "<video>" -ar 16000 -ac 1 -c:a pcm_s16le /tmp/<slug>.wav -y`
- Transcribe with whisper-cpp: `whisper-cli -m /tmp/ggml-base.bin -f /tmp/<slug>.wav --no-timestamps`
- If the whisper model isn't downloaded yet, fetch it: `curl -L -o /tmp/ggml-base.bin "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"`
- If the transcription is blank/silent, skip the video and report it at the end.

## 2. Visual text extraction (per-video opt-in)

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

Based on the transcription content, determine the best topic folder. Reuse existing folders in `~/Downloads/AI Library/` when the content fits. Common categories include but are not limited to:

- Comedy
- Marvel & TV
- Self-Improvement
- Food & Restaurants
- Game Recs
- Tech
- Music
- Sports
- Education
- Children & Parenting

If none of the existing folders fit, create a new descriptively named topic folder.

Videos classified as `talk-or-lecture` in step 4 should prefer the `Education` folder, or a more specific subject folder if one fits (e.g., `Tech`, `Self-Improvement`). Create a dedicated `Talks & Lectures` folder only if the content doesn't fit any existing subject-based folder.

## 6. Rename, move, and create markdown

**For new videos (not yet in AI Library):**

- Rename the video file to include a brief description of the content while keeping the platform, creator name, video ID, and original extension. Format: `<brief-description> - <platform> - <creator name> [<video ID>].<original-ext>` (e.g., `sesame-chicken-recipe - Instagram - Video by louishowardpt [DVs_UEwiIx9].mp4`). For legacy files without a platform prefix, use `Instagram` as the default. Keep the description short (2-5 words, lowercase, hyphenated).
- Create the topic folder under `~/Downloads/AI Library/` if it doesn't exist.
- Move the renamed video file into that folder.

**For re-runs (file already in AI Library):**

- Keep the video in its current location and folder — do not move or rename it unless the user explicitly asks to re-categorize.
- Overwrite the existing `.md` file with fresh content.

**In both cases**, create a matching `.md` file with the same base name. The structure depends on the classification from step 4:

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

## 7. Audio export for talks and lectures

For videos classified as `talk-or-lecture`, also export a tagged MP3 alongside the video and markdown so the talk can be listened to later (e.g., on a phone or in a podcast app). Skip this step for `short-form` videos.

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
  - `title` — the talk title (same as the H1 in the markdown, without the speaker suffix)
  - `artist` / `album_artist` — the speaker's name (fall back to the creator/channel name from the filename if unknown)
  - `album` — the conference, lecture series, podcast, or platform (e.g., `YouTube`, `TED`, `Strange Loop 2024`). Fall back to the platform prefix from the filename.
  - `genre` — `Speech` (use `Podcast` if the source is clearly a podcast episode)
  - `date` — the year, if it can be inferred from the caption or transcription; otherwise omit
  - `comment` — the TL;DR text from the markdown, trimmed to a single line
- If ffmpeg fails (e.g., corrupt audio), log the failure and continue with the rest of the pipeline — the markdown summary is still the primary output.

## 8. Parallel processing

- Convert all videos to WAV in parallel (background ffmpeg jobs).
- Transcribe all videos in parallel (separate bash calls or subagents).
- MP3 exports for talks/lectures can also run in parallel once classification is complete.

## 9. Report

When finished, print a summary table of all videos processed:

| Video | Type | Topic Folder | Outputs | Summary |
|-------|------|-------------|---------|---------|

- `Type` — `short-form` or `talk-or-lecture`
- `Outputs` — indicate `md` for every video, and `md + mp3` for talks/lectures

Also list any videos that were skipped (blank audio, errors, etc.).
