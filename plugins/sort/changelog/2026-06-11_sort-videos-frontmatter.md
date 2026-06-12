# sort-videos: YAML frontmatter on companion markdown files

## What changed

The companion `.md` summary that `/sort-videos` writes for every processed video now begins with a YAML frontmatter block instead of jumping straight into the H1.

## Frontmatter fields

| Field | Content |
|-------|---------|
| `source_url` | Original link reconstructed from platform + video ID (Instagram reel URL, YouTube watch URL, TikTok video URL). Omitted when it can't be reconstructed. |
| `platform` | Platform prefix from the filename (`Instagram`, `TikTok`, `Youtube`, …). |
| `creator` | Creator username/handle (no `@`), preferring the oEmbed handle for Instagram. |
| `video_id` | The `[XXX]` ID from the filename, brackets stripped. |
| `type` | `short-form` or `talk-or-lecture` (classification from the talk-detection step). |
| `topic` | The AI Library topic folder the video was filed into. |
| `tags` | 3-7 lowercase hyphenated content keywords, inline-array syntax. |
| `description` | One sentence (≤ 150 chars); also usable as the source for the renamed file's slug. |
| `processing` | Inline array of steps actually performed: `transcript`, `ocr-text`, `ocr-products`, `caption-enrichment`, `mp3-export`. Only lists what really happened; `[]` for skipped videos. |
| `retrieved_sources` | Inline array of URLs actually fetched to augment the summary (oEmbed endpoint, recipe pages, etc.). Successful, content-contributing fetches only — not links merely mentioned in the video. |
| `processed` | `YYYY-MM-DD` processing date; preserved across re-runs. |

## Re-run behavior

Re-processing regenerates the frontmatter along with the body, but keeps the original `processed` date when the existing `.md` has one — full history stays in `_processing-log.md`.

## Files touched

- `plugins/sort/skills/sort-videos/SKILL.md` — frontmatter spec added to step 6; skill description updated.
- `plugins/sort/README.md` — `/sort-videos` row updated to mention the frontmatter.
