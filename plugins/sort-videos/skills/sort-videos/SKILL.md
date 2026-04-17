---
name: sort-videos
description: Find, transcribe, and sort downloaded videos from Downloads into topic folders in AI Library. Pass a file path to reprocess a specific video (e.g., /sort-videos path/to/video.mp4).
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

## 4. Categorize

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

## 5. Rename, move, and create markdown

**For new videos (not yet in AI Library):**

- Rename the video file to include a brief description of the content while keeping the platform, creator name, video ID, and original extension. Format: `<brief-description> - <platform> - <creator name> [<video ID>].<original-ext>` (e.g., `sesame-chicken-recipe - Instagram - Video by louishowardpt [DVs_UEwiIx9].mp4`). For legacy files without a platform prefix, use `Instagram` as the default. Keep the description short (2-5 words, lowercase, hyphenated).
- Create the topic folder under `~/Downloads/AI Library/` if it doesn't exist.
- Move the renamed video file into that folder.

**For re-runs (file already in AI Library):**

- Keep the video in its current location and folder — do not move or rename it unless the user explicitly asks to re-categorize.
- Overwrite the existing `.md` file with fresh content.

**In both cases**, create a matching `.md` file with the same base name, containing:
  - An H1 title: `# Video by <creator name>`
  - An H2 subtitle summarizing the video topic
  - The transcription, cleaned up and formatted nicely with markdown (lists, bold for names/titles, sections where appropriate)
  - If OCR was performed, an `## On-Screen Text` section with the extracted visual content
  - Extract and highlight key items (game names, restaurant names, tips, people, etc.) rather than dumping raw transcript text.

## 6. Parallel processing

- Convert all videos to WAV in parallel (background ffmpeg jobs).
- Transcribe all videos in parallel (separate bash calls or subagents).

## 7. Report

When finished, print a summary table of all videos processed:

| Video | Topic Folder | Summary |
|-------|-------------|---------|

Also list any videos that were skipped (blank audio, errors, etc.).
