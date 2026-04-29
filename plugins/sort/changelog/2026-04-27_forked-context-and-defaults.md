# Forked-context frontmatter + two pipeline defaults

Two changes to how `/sort` runs, plus two pipeline defaults caught by the latest dry-run audit.

## `context: fork` on both skill frontmatters

Added `context: fork` to the YAML frontmatter of both skills:

- `plugins/sort/skills/sort/SKILL.md`
- `plugins/sort/skills/sort-videos/SKILL.md`

Both `/sort` and `/sort-videos` now run in their own isolated subagent when invoked. The user's parent conversation no longer accumulates per-file working details — pdftotext output, `mdfind` queries, video transcripts, OCR chatter — only the skill's reply lands in the parent context. When `/sort` calls `/sort-videos` via the Skill tool, the call enters its own forked subagent automatically; no manual Agent tool wiring required.

This was also the right place to express the isolation, rather than ad-hoc Agent-tool fan-out inside SKILL.md prose. The frontmatter is the canonical signal to the harness.

`SKILL.md` and `documents.md` were updated to mention this in passing (e.g. "the parent /sort skill declares `context: fork`, so this whole pipeline runs in an isolated subagent — no additional forking needed inside") so future contributors don't try to re-add Agent calls per file.

## Single-document archive rule (`SKILL.md` §2 Archives)

Archives that contain exactly one document file (`.pdf .doc .docx .epub`) are now unwrapped and routed as that document, instead of falling into the "Mixed or unclear" → AskUserQuestion path. The original archive is moved alongside the extracted document so nothing is silently discarded.

Surfaced by the dry run on `AWB-9672714855.zip` (a single shipping waybill PDF inside a zip), which previously fell to AskUserQuestion. Now it routes to wherever the inner PDF classifies (likely `Receipts/`).

## Sensitive-name default for the unknown bucket (`SKILL.md` §2 Unknown files)

Before routing to `Review/`, the unknown bucket now checks the basename against:

```
(?i)(recovery|backup-codes?|\.env|credentials|secret|private-key|api-key|api_key|recovery-kit)
```

Matches go to the resolved `sensitive_dir` instead of the manual-triage pile. Only fires when no §0.5 user rule matched the file (rules always take priority). Users who don't want this default can disable it with a rule on phase `unknown-sensitive-default`.

Surfaced by the dry run on `reflect-recovery-kit-talby.json`, which would otherwise sit unguarded in `Review/`.

## Files

- **Modified** `plugins/sort/skills/sort/SKILL.md`:
  - Frontmatter: added `context: fork`
  - `### Archives` → new "Single document" rule between "Mostly images" and "Mixed or unclear"
  - `### Unknown files` → sensitive-name regex default, with override path via the `unknown-sensitive-default` phase
  - Brief notes added in the Videos and Documents sections explaining that the fork happens via frontmatter
- **Modified** `plugins/sort/skills/sort-videos/SKILL.md`:
  - Frontmatter: added `context: fork`
- **Modified** `plugins/sort/skills/sort/documents.md`:
  - Header now mentions the parent skill is forked; no per-file forking needed inside this file
- **Modified** `plugins/sort/skills/sort/OVERRIDES.md`:
  - New phase `unknown-sensitive-default` documented; archive phase note updated to mention the single-doc rule

## Out of scope (still)

- Tool-relevance gate in dispatcher (only prompt for tools needed by the actual file types in this run); the pandoc-skip phase rule remains a workaround.
- A `/sort:edit-rules` command for opening rule files in `$EDITOR`.
- Validation flag in `add-rule.rb` to dry-run a match expression against `~/Downloads` before saving.
