---
date: 2026-04-27
title: Vision + OCR analysis for image classification (and QR-code → return routing)
---

# Vision + OCR analysis for image classification

## What changed

Restructured the **Images** section in `skills/sort/SKILL.md` so vision/OCR analysis runs on every image by default, instead of being a topic-tagging step that fires only after coarse filename/EXIF heuristics decide what kind of image it is.

New flow:

1. **(a) Cheap shortcut.** Only filename-prefix screenshots (`Screen Shot`, `Screenshot`, `CleanShot`, `Shottr`) skip the vision pass — they're unambiguous and high-volume. Everything else gets looked at.
2. **(b) Vision + OCR for every other image.** Either Read the image directly (multimodal model) or launch a vision-capable Agent in batches. The classifier returns one of: `return`, `receipt`, `screenshot`, `meme`, `photo`, `other`, plus an `ocr_summary` and a topic when applicable. Routing destinations:
   - `return` → `<target>/AI Library/Returns/` (QR codes, RMA cards, drop-off receipts, shipping labels)
   - `receipt` → `<target>/AI Library/Receipts/`
   - `screenshot` → `<target>/AI Library/Screenshots/`
   - `meme` → `<target>/AI Library/Memes/`
   - `photo` / `other` → topic-tagged folder (existing or newly proposed)
3. **(c) Heuristic fallback.** Only fires when no vision tool is reachable; uses the legacy EXIF/dimension/filename rules and routes anything ambiguous to `Review/`. The §5 summary flags which images came through this path.

QR-code presence alone is treated as sufficient evidence of a return artifact — those images are essentially never memes or photos in this workflow.

## Why

A dry run misrouted `309304100009.JPEG` (an Amazon Return Summary Card with a UPS Store QR code) to `Memes/`. The user pointed out two things:

1. Any image with a QR code is always a return code in their workflow.
2. More fundamentally: the dispatcher should *look at the image content* — both visually and via OCR — to determine what it is, rather than guessing from filename/EXIF and only doing vision as a topic-tagging afterthought. Reading the actual image content surfaces returns, receipts, scanned documents, and miscategorized memes that the cheap heuristics will reliably misfile.

This change makes "look first, route second" the default for images.

## Notes

- The skill's variable was renamed from `<library_dir>` to `<target>/AI Library/` in the same edit cycle (folder-agnostic refactor), so all destination paths reference the new form.
- The Returns/ and Receipts/ folders may not exist in the user's library yet; the skill creates topic folders on first use, so the first sorted return code or receipt will create them.
- Cost note: vision-on-every-image is more expensive than pure heuristics. Mitigated by (i) the filename-prefix screenshot shortcut and (ii) batching multiple images into a single Agent call in §(b). If image volume becomes a problem, a future optimization could re-introduce a `zbarimg`-only fast path for QR detection before the Agent call.
