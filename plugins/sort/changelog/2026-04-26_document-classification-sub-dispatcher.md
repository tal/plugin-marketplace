# Document classification sub-dispatcher

Replaced the `/sort` dispatcher's "everything goes to Review/" rule for documents with a real classification path. The new logic lives in a sibling reference file (`documents.md`) loaded on demand by the dispatcher — not a separately-invocable skill. Keeps the top-level `SKILL.md` lean and lets the doc pipeline grow without bloating it.

## Files

- **Added** `plugins/sort/skills/sort/documents.md` — sub-dispatcher: tool detection, runtime folder discovery, text extraction (`pdftotext` / `textutil` / `pandoc`), vision fallback for scanned PDFs (`pdftoppm`), agent classification with the same JSON contract image classification uses, and routing rules for sensitive / low-confidence items.
- **Modified** `plugins/sort/skills/sort/SKILL.md`:
  - Replaced `### Documents and unknown files` with `### Documents → see documents.md` (delegates to the sub-dispatcher) plus a separate `### Unknown files` section that keeps the Review/ fallback for `.json` / `.torrent` / `.spk` etc.
  - §4 parallel-processing list now mentions doc parallelism
  - §5 summary-table Action values now include `classified` / `classified-sensitive` / `review` / `error` from the doc pipeline

## Design choices

- **Not user-invocable.** `documents.md` is a reference file, not a skill — there is no `/sort-docs` command. The dispatcher Reads it on demand only when the run contains documents. Same progressive-disclosure pattern Anthropic recommends for keeping SKILL.md compact.
- **Content agnostic.** The sub-dispatcher discovers folders at runtime via `ls "$HOME/Downloads/AI Library"` and lets the agent propose new folder names; it ships with no hardcoded taxonomy. The same skill should work for any user.
- **Probe-and-prompt for missing tools.** §0 of `documents.md` probes for `pdftotext` / `pdftoppm` / `pandoc` and, if any are missing, detects the available package manager (`brew` / `apt` / `dnf` / `port`) and asks a single AskUserQuestion offering Install / Skip-and-degrade / Cancel-doc-bucket. If no package manager is detected, falls through to degraded mode and prints the manual install command. The degraded-mode behavior is enumerated per missing tool — partial coverage is preserved when only one of poppler's binaries is missing.
- **Sensitivity is a flag, not a hardcoded folder.** The agent returns `sensitive: true|false`. The first sensitive item in a run triggers an AskUserQuestion to choose a sensitive directory (default `~/Downloads/AI Library/Sensitive/`); the answer is cached for the rest of the run.
- **Same JSON contract as image classification** (`topic` / `reuse` / `sensitive` / `confidence` / `description`) so the dispatcher's reporting code is one path.

## Out of scope

- Adding a `/sort-docs` slash command (the user explicitly asked for a non-invocable sub-dispatcher).
- Bundling images and documents into a single shared classifier — input pipelines diverge enough that the gain isn't worth it. The shared piece is the JSON contract, which both paths now use.
- Pre-seeding any topic folders. Discovery is dynamic.
