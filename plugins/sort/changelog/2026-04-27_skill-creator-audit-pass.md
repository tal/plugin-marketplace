---
date: 2026-04-27
title: Skill-creator audit pass on /sort after the vision-first images rewrite
---

# Skill-creator audit pass on /sort

## What changed

Re-ran the `/sort` skill through `skill-creator` after the recent Images-section rewrite (vision + OCR became the default classification path; QR-code-bearing images route to `Returns/`). The audit found six friction points the rewrite introduced or left unresolved. All six were patched in place.

### 1. Description trimmed (~285 → ~165 words)

The previous description listed every conceivable trigger phrasing, which actually dilutes triggering signal. Trimmed to the high-value cues, reorganized for parallel structure, and added `return labels, receipts` to the "things piling up" list so the new image categories show up in the trigger surface area.

### 2. §3 (Ask when uncertain) example fixed

The image example still said "doesn't match screenshot/meme/photo rules AND the vision agent returns a low-confidence topic" — which describes the pre-rewrite heuristic-first flow. Updated to: "the vision pass returns low confidence, an unrecognized category, or no good topic match — or where the heuristic fallback (§c) had to be used and the result feels uncertain". Now consistent with the actual flow.

### 3. §4 (Parallel) reconciled with §(b) batching guidance

§(b) says "batch many images into one Agent call to amortize cost"; §4 said "Images can tag in parallel via multiple Agent calls". These weren't contradictory but were unfocused. Rewrote §4's image bullet to say: batch within a call where possible, parallel calls when image count is large, direct multimodal Read for the single-image case.

### 4. §Images §(b) specifies subagent type and per-call batching size

§(b) said "vision-capable Agent" without specifying which subagent type. `documents.md` §3 uses `general-purpose` — aligned §(b) to do the same. Added a rule of thumb (~10 images per Agent call) and the small-batch shortcut (1–3 images: just Read directly).

### 5. §5 (Report) flags vision vs. fallback

§(c) said "Note in the §5 summary which images used this fallback so the user can spot-check." but §5 itself didn't mention the column. Added: image rows now append `(vision)` or `(fallback)` to the Action so fallback rows are easy to find. Also added the missing `Rule` column to the table header (it was described in the bullets below but absent from the visual table).

### 6. Broken script reference fixed

§0.5 said "the bundled Ruby in `${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.rb`". That script doesn't exist — the actual rule reader is `match-rules.rb --rules-only`, which is documented in OVERRIDES.md. Updated the reference and clarified what the script outputs (merged rules + top-level scalars).

### 7. OVERRIDES.md `to:` shorthand made explicit

Since the rewrite removed the `library_dir` setting and `<target>/AI Library/` is now resolved per-run, the `AI Library/<topic>/` shorthand in `route` actions needed an explicit anchor. Clarified that the shorthand resolves under the current run's `<target>` folder, so the same rule works whether the user is sorting `~/Downloads` or `~/Desktop`.

## Why no eval/iteration cycle

The user explicitly asked for "audit … and update in place and report what changed" — not behavior-change validation. The recent vision-first rewrite is conceptually sound; what needed fixing was internal consistency, dead references, and the description bloat. A full eval cycle (with test cases, baselines, and benchmark comparison) is appropriate when validating a behavior change, not for an internal-consistency cleanup pass.

If you want a real eval cycle later — e.g., compare the vision-first version against the heuristic-first version on a fixed set of test images — that would be a good follow-up to schedule.

## Files touched

- `skills/sort/SKILL.md` — description, §0.5 (script ref), §Images §(b), §3, §4, §5
- `skills/sort/OVERRIDES.md` — `to:` shorthand explanation
