---
name: sort-images
description: Download, OCR, summarize, and categorize Instagram image carousels (and other multi-image posts) — defaults to the folder Claude Code was launched in. Trigger on `/sort-images`, when the user pastes an Instagram post/carousel link (e.g. `instagram.com/p/<shortcode>/?img_index=1`), references a `.webloc`/`.url` shortcut to one, or asks to "OCR this carousel", "save this Instagram post", "pull the text out of these slides", "summarize this infographic carousel", or "what does this carousel say" — even when they don't say "sort". Downloads every slide with gallery-dl, reads each slide in order via a vision OCR agent, enriches from the post caption, renames with a content-derived slug, moves the images into `<target>/AI Library/<topic>/`, and writes a companion `.md` summary. Pass a URL, a folder of already-downloaded slides, or a glob to (re)process a specific carousel.
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

# Sort and OCR Instagram Image Carousels

Arguments passed: `$ARGUMENTS`

This skill handles **image carousels** — the multi-slide Instagram posts you scroll through sideways (`/p/<shortcode>/?img_index=N`). These are usually infographics, recipes, tip lists, step-by-step guides, quote graphics, or product roundups where the value lives in the *text printed on the slides*, not in audio. Sibling to `/sort-videos`, which owns the audio/video pipeline — if the target is a video (reel), hand it to `/sort-videos` instead.

## 0. Determine the target carousel

The **target folder** is where the downloaded slides and the AI Library should live. Resolution order:

1. If `$ARGUMENTS` is (or contains) an **Instagram URL** — `https://www.instagram.com/p/<shortcode>/…`, `/reel/<shortcode>/`, or a shortened share link — that's a *download job*. The target folder is the current working directory (where Claude was launched), and slides get downloaded into it (see §1).
2. If `$ARGUMENTS` is a **`.webloc` / `.url` / `.html` link file** pointing at an Instagram post, read the URL out of it and treat it as case 1. The target folder is the parent of that link file.
   - `.webloc`: `plutil -extract URL raw "<file>"` (or grep the `<string>` inside).
   - `.url`: grep the `URL=` line.
3. If `$ARGUMENTS` is a **directory** of already-downloaded slides, that's the carousel — OCR it in place (skip §1 download). The target folder is its parent.
4. If `$ARGUMENTS` is a **file path or glob** of image files (e.g. `IG-carousel/*.jpg`), those are the slides. The target folder is their parent.
5. Otherwise (no arguments), scan the current working directory for **carousel-shaped image groups**: 3+ images sharing a common stem that looks like an Instagram download (e.g. `<shortcode>_1.jpg … <shortcode>_5.jpg`, or a folder named after a shortcode). Each such group is one carousel. Single loose images are NOT carousels — leave those to `/sort`'s image pipeline.

The skill is **location-agnostic**: it works on `~/Downloads`, `~/Desktop`, a project folder, or anywhere else. Create `<target>/AI Library/` if it doesn't exist before moving anything: `mkdir -p "<target>/AI Library"`.

**Re-runs:** if the slides already live inside `<target>/AI Library/`, OCR them in place and regenerate the `.md` alongside them — don't move or rename unless the user asks to re-categorize.

## 1. Download the carousel (URL jobs only)

Skip this whole section when the target is already a local folder/glob of slides (§0 cases 3–4).

Extract the **shortcode** from the URL — the path segment after `/p/` or `/reel/` (e.g. `https://www.instagram.com/p/DYa5IUEmn-n/?img_index=1` → `DYa5IUEmn-n`). Use it as the working `<slug>` until a content-derived slug is chosen in §5.

Download every slide with **gallery-dl**, which understands Instagram carousels and grabs all slides plus metadata in one call:

```bash
gallery-dl -D "/tmp/<shortcode>_carousel" --write-metadata \
  "https://www.instagram.com/p/<shortcode>/"
```

- `-D` flattens everything into one directory instead of gallery-dl's default nested `gallery-dl/instagram/<user>/` tree.
- `--write-metadata` writes a `.json` sidecar per slide; the post caption lives there under `.description` (used in §3).

**If gallery-dl is missing**, install it before downloading:

```bash
brew install gallery-dl   # preferred on macOS
# or, if Homebrew isn't available:
python3 -m pip install --user --upgrade gallery-dl
```

If the install fails or the user declines, fall back to asking them (AskUserQuestion): install gallery-dl, point the skill at an already-downloaded folder of slides instead, or skip this carousel.

**If the download fails because the post is private / login-gated** (gallery-dl prints an auth/`401`/`HttpError` message), retry once using the user's browser cookies:

```bash
gallery-dl -D "/tmp/<shortcode>_carousel" --write-metadata \
  --cookies-from-browser firefox \
  "https://www.instagram.com/p/<shortcode>/"
```

Try `firefox`, then `chrome`, then `safari` (whichever the user is logged into Instagram on). If it still fails, report the carousel as skipped with the reason and move on — don't block the rest of the run.

After download, the slides are the image files in `/tmp/<shortcode>_carousel/` sorted by filename (gallery-dl numbers them in carousel order). If gallery-dl pulled a **video** instead of images (the post was actually a reel), stop and tell the user to run `/sort-videos` on it instead.

## 2. OCR the slides

Carousels carry their meaning in printed text and on-slide imagery, so OCR is the core step (not opt-in like it is for videos).

1. Collect the slide image paths in carousel order (numeric sort of the filenames). Ignore the `.json` metadata sidecars here.
2. Launch the **`carousel-ocr`** agent (defined in this plugin under `agents/carousel-ocr.md`) with the ordered list of slide paths:

   ```
   Read these carousel slides IN ORDER and extract their content:
   /tmp/<shortcode>_carousel/01.jpg
   /tmp/<shortcode>_carousel/02.jpg
   ...
   ```

   The agent reads each slide (the model is multimodal — it sees both the imagery and any printed text), preserves slide order, stitches multi-slide content (a recipe split across slides, a numbered list continued on the next slide) into one coherent structure, and returns structured markdown.
3. The agent's markdown becomes the body of the `.md` file (see §5).

For a small carousel (≤10 slides) you may read the slides directly with multimodal Read instead of spawning the agent, but the agent keeps the OCR working details out of the parent context — prefer it for anything larger or when batching multiple carousels.

## 3. Enrich from the caption

The on-slide text is the primary source, but the **post caption** often contains the full list, recipe with exact quantities, source links, or creator handles that the slides abbreviate.

Prefer the caption gallery-dl already saved:

```bash
jq -r '.description // empty' "/tmp/<shortcode>_carousel/"*.json | head -1
```

If no metadata sidecar exists (e.g. a local-folder run), fall back to the oEmbed endpoint:

```bash
curl -s "https://www.instagram.com/api/v1/oembed/?url=https://www.instagram.com/p/<shortcode>/" | jq -r '.title'
```

Use the caption to fill gaps the same way `/sort-videos` does:

- **Recipes / lists:** if the slides reference a list (ingredients, steps, product names, books, tips) and the caption spells it out more completely, use the caption's full version with exact details.
- **Attribution / links:** pull creator handles, source URLs, and credits from the caption into the markdown.

If no useful caption is available, proceed with just the OCR.

## 4. Categorize

From the OCR (and caption), pick the best topic folder under `<target>/AI Library/`.

**Discover existing folders at runtime — never hardcode topic names:**

```bash
ls -1 "<target>/AI Library/" 2>/dev/null | grep -vE '^(Review|_|\.)'
```

Reuse an existing folder whenever the content plausibly fits — that keeps the user's taxonomy coherent and avoids fragmenting it ("Productivity" vs. "Self-Improvement"). Only create a new folder when nothing fits; pick a descriptive 1–3 word Title Case name (e.g. `Cooking`, `Personal Finance`, `Fitness`). Carousels often map cleanly onto the same topic folders the user's videos already use.

## 5. Rename, move, and write the markdown

**For new carousels (not yet in AI Library):**

- Choose a short content-derived slug (2–5 words, lowercase, hyphenated) from the carousel's subject — e.g. `high-protein-breakfasts`, `git-rebase-cheatsheet`.
- Create a folder for the slides so the carousel stays grouped: `<target>/AI Library/<Topic>/<slug> - Instagram [<shortcode>]/`.
- Rename each slide to `<slug> - <NN>.<ext>` (zero-padded, carousel order preserved) and move them into that folder. Discard the `.json` metadata sidecars after the caption is extracted (§3).
- Write the companion `.md` as `<slug> - Instagram [<shortcode>].md` **inside that same folder**.

**For re-runs (slides already in AI Library):**

- Leave the slides where they are; just overwrite the `.md` with fresh content.

The `.md` structure:

- An H1 title: `# <Carousel subject>` (best title from OCR / caption / shortcode)
- An H2 subtitle: one line summarizing what the carousel is about
- A `## Summary` section: 2–4 sentences capturing the takeaway, so the carousel can be understood without opening the images
- The structured OCR body from §2 — the slide-by-slide content, cleaned up and formatted with markdown (numbered steps, ingredient lists, bold for names/titles). Stitch content that spans slides; don't label every slide narratively ("Slide 1 says…") unless the slides are genuinely independent items.
- A `## Source` section: the post URL (`https://www.instagram.com/p/<shortcode>/`), creator handle, and any source links pulled from the caption.

Highlight the useful extracted items (recipe quantities, the full list, the steps, handles, prices) rather than dumping raw per-slide text.

## 6. Append to the processing log

After a carousel is fully processed, record it in the **prepend-only processing log** shared with `/sort-videos` at the root of the AI Library:

```
<target>/AI Library/_processing-log.md
```

The log is **prepend-only**: new entries go on top (newest first); past entries are never edited or removed, even on re-runs (a reprocess adds a *new* entry). Build a compact entry and prepend it with the bundled script (entry text on stdin):

```bash
printf '## %s — %s\n- **Type:** %s\n- **Topic:** %s\n- **Source:** %s\n- **Path:** %s\n- **Summary:** %s\n' \
  "$(date '+%Y-%m-%d %H:%M')" \
  "<slug> - Instagram [<shortcode>]" \
  "carousel" \
  "<topic folder>" \
  "Instagram [<shortcode>]" \
  "AI Library/<Topic>/<slug> - Instagram [<shortcode>]/" \
  "<one-line summary>" \
| bash "${CLAUDE_PLUGIN_ROOT}/scripts/log-video.sh" "<target>/AI Library/_processing-log.md"
```

For re-runs, append ` (reprocess)` to the `Type` field. If a carousel was skipped (download failed, login-gated, blank slides), still log it with `skipped` as the `Type` and the reason in `Summary` — the log is a complete record of everything the skill touched.

## 7. Parallel processing

When several carousels are in the run, process them in parallel where they don't share state:

- Download each carousel (`gallery-dl`) in parallel — independent network jobs.
- Run one `carousel-ocr` agent per carousel; multiple agents can run concurrently.
- Caption extraction and markdown writing follow per carousel.

## 8. Report

Print a summary table of all carousels processed:

| Carousel | Slides | Topic Folder | Outputs | Summary |
|---|---|---|---|---|

- `Slides` — number of slides OCR'd
- `Outputs` — `md` for every carousel (slides live alongside it in the topic subfolder)

Also list any carousels skipped (download failed, login-gated, blank/no text), with the reason.
