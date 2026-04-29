# Skill-creator review pass

Ran both `/sort` and `/sort-videos` through the skill-creator best-practice checklist (description quality / triggering coverage, structure, content-agnosticism, "why over MUST" writing style). All edits applied directly to the SKILL.md files in place.

## Description rewrites — broader triggers, slight push factor

Per the skill-creator guide ("Claude has a tendency to undertrigger skills … make the descriptions a little bit pushy"), both descriptions were rewritten to:

- Lead with what the skill does, not "this skill should be invoked"
- List many more concrete trigger phrases (casual phrasings, implied messiness, cases where the user references a video/file without saying "sort")
- Include explicit "Make sure to use this skill whenever the user mentions … even if they don't explicitly say `sort`" language
- Mention the supporting infrastructure (sub-dispatchers, rule files) so the trigger surface covers users asking about overrides too

Length: `sort` description grew from ~700 chars to ~1280; `sort-videos` from ~860 to ~1430. Above the skill-creator's "~100 words" guideline, but the guide explicitly allows going longer for skills with broad trigger surfaces, and these are dispatcher skills with many natural-language entry points.

## Content-agnostic enforcement (distribution-friendly)

Two places hardcoded the user's personal folder taxonomy and have been replaced with runtime discovery:

- `sort/SKILL.md` line ~24: removed the parenthetical list `Comedy, Tech, Food & Restaurants, Self-Improvement, Game Recs, Education, Music, Sports, Children & Parenting, Marvel & TV` — now instructs `ls -1 "$HOME/Downloads/AI Library/"` at runtime, with a paragraph explaining why (each user has their own taxonomy, hardcoded folder names would be wrong for everyone shipping the plugin).
- `sort-videos/SKILL.md` §5 "Categorize": replaced the "Common categories include but are not limited to" list of 10 personal folder names with the same runtime-discovery pattern that `documents.md` already uses. Added a paragraph on **why** reuse beats new-folder-creation (the user's taxonomy stays coherent across runs; minor naming variation fragments the library).

This was the user's stated "content-agnostic for distribution" principle, applied consistently across both skills. The SKILL files no longer leak personal folder choices.

## Writing-style tightening

Following the skill-creator's "explain the why" principle:

- `sort/SKILL.md` §0: added a short note on why we skip `~/Downloads/AI Library/` (re-processing risks renaming files the user organized by hand) and why we capture the `.app` flag separately (`.app` bundles are directories, not files, and need different handling than the disk images and zips that contain them).
- `sort/SKILL.md` §3 "Ask when uncertain": added a one-line rationale for batching prompts (interrupting one-by-one trains the user to mash through prompts and degrades signal) and for the deletion exception (deletion is the only irreversible action; everything else can be undone).

No "ALWAYS" / "NEVER" all-caps yelling was introduced.

## Structure and progressive disclosure

Both SKILL.md files comfortably under 500 lines (sort: 237, sort-videos: 223). Documents flow into the dedicated sub-dispatcher (`documents.md`, 162 lines) and the rules schema reference (`OVERRIDES.md`, 166 lines) — exactly the three-level progressive disclosure pattern the skill-creator describes (metadata → SKILL.md body → bundled references).

## Out of scope

Did **not** run the formal eval-loop with subagents from the skill-creator. The user has already iterated heavily on these skills through the conversation, and a real eval would mean either running `/sort` against the user's actual `~/Downloads/` (which would move and delete files) or building synthetic test fixtures (significant work for marginal value at this stage). If formal triggering accuracy benchmarks are wanted later, the skill-creator's `run_loop.py` description-optimization tool (separate from the eval loop) can target the YAML descriptions specifically without needing fixtures.

## Files

- **Modified** `plugins/sort/skills/sort/SKILL.md` — frontmatter description rewrite; line 24 hardcoded folder list removed; §0 and §3 "why" tightening
- **Modified** `plugins/sort/skills/sort-videos/SKILL.md` — frontmatter description rewrite; §5 hardcoded category list replaced with runtime discovery + reuse-vs-new-folder rationale
