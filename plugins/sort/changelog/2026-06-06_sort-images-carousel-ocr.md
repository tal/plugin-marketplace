# Add `/sort-images` — Instagram carousel OCR pipeline

**Date:** 2026-06-06

## Summary

Added a third processing skill, `/sort-images`, that downloads, OCRs, summarizes, and files **Instagram image carousels** (the multi-slide `/p/<shortcode>/?img_index=N` posts — infographics, recipes, tip lists, step-by-step guides, quote graphics, product roundups). It's the image-carousel sibling of `/sort-videos`: same `context: fork` isolation, same `<target>/AI Library/<topic>/` routing, same shared prepend-only `_processing-log.md`.

## What changed

- **New skill** `skills/sort-images/SKILL.md`:
  - Target resolution accepts a carousel **URL**, a `.webloc`/`.url` **link file**, a **folder** of downloaded slides, a **glob**, or a CWD scan for carousel-shaped image groups.
  - Downloads every slide with **gallery-dl** (`-D` flat dir + `--write-metadata`), auto-installing it via brew/pip on first run if missing, with a `--cookies-from-browser` fallback for login-gated posts.
  - OCRs slides **in order** via the new `carousel-ocr` agent, stitching content that spans slides.
  - Enriches from the post caption (gallery-dl metadata sidecar, oEmbed fallback).
  - Categorizes into an existing `AI Library/` topic folder (discovered at runtime), renames slides with a content-derived slug, groups them in a per-carousel subfolder alongside a companion `.md`, and prepends to the shared processing log.
- **New agent** `agents/carousel-ocr.md`: reads ordered carousel slides and returns one coherent structured markdown document (recipe / list / how-to / quote shapes), dropping IG chrome and dead title/CTA slides.
- **Wired into `/sort`** (`skills/sort/SKILL.md`): added `instagram-link` and `image-carousel` type buckets that delegate to `/sort-images` via the Skill tool; single loose images still go through the existing image pipeline. Updated the §5 report `Type`/`Action` enumerations.
- **Manifests** (`.claude-plugin` + `.codex-plugin`): added `gallery-dl`, `instagram`, `carousel` keywords and extended the description.
- **README**: added the `/sort-images` command row, a pipeline bullet, the gallery-dl optional-dependency row, and layout entries for the new skill/agent plus `log-video.sh`.

## Notes

- `gallery-dl` is the standard tool for Instagram photo carousels (`yt-dlp` only reliably handles reels/videos). The skill installs it on demand and soft-fails (reports the carousel as skipped) if install is declined or the post stays login-gated.
- Artifacts land in `<target>/AI Library/` exactly like the other `/sort` pipelines, per request.
