# sort

Sort and process files in any folder. The `/sort` skill dispatches on file type — videos, images, archives, DMGs, app bundles, documents — and routes each to the right pipeline. Output lands under `<target>/AI Library/`, created automatically if absent.

The skill is **location-agnostic**: by default it sorts the folder Claude Code was launched in, so it works equally well on `~/Downloads`, `~/Desktop`, a project folder, or anywhere else. Pin it to a specific folder via the `sources:` override (see User rules below).

## Install

Claude Code (from inside the session):

```
/plugin install sort@tal-marketplace
```

Or from the shell with the `claude` CLI:

```
claude plugin install sort@tal-marketplace
```

Codex:

```
codex plugin install sort@tal-marketplace
```

See the [marketplace README](../../README.md) for adding the marketplace itself.

## Commands

| Command | What it does |
|---|---|
| `/sort` | Top-level dispatcher. Scans the current working directory (and `<cwd>/Recents/` if it exists), classifies each item, and routes it. Pass a path or glob to limit the run, or to sort a different folder than CWD. |
| `/sort-videos` | Video pipeline. Transcribes with whisper-cpp, OCRs frames when relevant, detects talks/lectures for an extended-summary format, exports a tagged MP3 for talks, renames, moves, and writes a companion `.md` summary. Invoked automatically by `/sort` for video files; can be called directly on a single file. |
| `/sort:add-rule` | Interactive command for adding a rule to your sort config (`sort.md` or `sort.local.md`). |

Both skills run with `context: fork` — they execute in an isolated subagent so per-file working details (transcripts, extracted PDF text, agent classifications) don't bloat the parent conversation.

## Pipelines (inside `/sort`)

- **Videos** → delegated to `/sort-videos`
- **Images** → screenshot/meme/photo detection, then a vision agent for topic tagging
- **Archives** (`.zip`, `.tar.gz`, etc.) → peeked; routed as app installer, image group, or single-document depending on contents
- **Disk images** (`.dmg`, `.iso`) → mounted, app-bundle-ID checked against `/Applications/`; auto-deleted if already installed
- **App bundles** → bundle-ID checked; deleted if already installed, else routed to a topic folder
- **Documents** (`.pdf`, `.docx`, `.epub`, etc.) → see `skills/sort/documents.md`. Text-extracted via `pdftotext`, classified by an agent into existing `AI Library/` folders, with a vision fallback for scanned PDFs and a sensitivity flag for personal documents
- **Unknown** → `AI Library/Review/`, with a default sensitive-name regex that re-routes recovery keys, `.env`, credentials, etc. to `<sensitive_dir>/Credentials/`

Sensitive items land under `<sensitive_dir>/<Category>/` where `<Category>` is one of `Credentials`, `Identity`, `Financial`, `Medical`, `Legal`, or `Other` — chosen by the document classifier or named explicitly in a `route_sensitive` rule. `<sensitive_dir>` defaults to `<target>/AI Library/Sensitive/` and can be overridden via the `sensitive_dir:` top-level setting.

## User rules

`/sort` is content-agnostic out of the box — it ships no hardcoded folder taxonomy. To customize behavior (auto-delete certain extensions, route specific filename patterns, suppress install prompts, override the sensitive-files directory), drop a rule file in any of these locations:

| Priority | Path | Scope | Committable |
|---|---|---|---|
| 1 (highest) | `$PWD/.claude/sort.local.md` | per-project, per-user | no — gitignore it |
| 2 | `$PWD/.claude/sort.md` | per-project, shared | yes |
| 3 | `~/.claude/sort.local.md` | per-user, all projects | no — never commit |
| 4 (lowest) | `~/.claude/sort.md` | per-user, all projects | yes (e.g. in a dotfiles repo) |

Anything ending in `.local.md` should be in your gitignore; the bare `sort.md` files are the committable ones.

To add or update a rule in any of these files, run **`/sort:add-rule`** — an interactive command that prompts for scope (which file), match type, action, and an optional note, then appends the rule. You don't have to hand-edit YAML.

### How resolution works

**Every file that exists is read** — a higher-priority file does not skip the lower-priority ones. Their `rules:` lists are concatenated into one combined list in priority order. For each file in the run, the dispatcher walks that combined list top-to-bottom and applies the **first matching rule**; if no rule matches, it falls through to the default classification pipeline (type table → per-bucket logic).

Priority only matters when more than one rule could match the same file — the higher-priority file's rule wins because it sits earlier in the combined list. A rule in `~/.claude/sort.md` still applies to files no higher-priority rule touched.

For top-level scalars (`sources`, `sensitive_dir`), the highest-priority file that sets the key wins on a per-key basis.

### File format

Markdown with a YAML frontmatter block. The frontmatter holds the structured rules; the body holds prose context the dispatcher can read into agent prompts.

```yaml
---
sensitive_dir: ~/Documents/Sensitive   # optional override of the default

rules:
  # auto-delete torrent and nzb files
  - match: { ext: [.torrent, .nzb] }
    action: delete

  # route shipping waybills to a fixed folder
  - match: { filename_glob: "AWB-*.zip" }
    action: route
    to: AI Library/Shipping/

  # suppress the pandoc install prompt when no .epub files are in the run
  - match: { phase: doc-tools-prompt, missing: [pandoc] }
    action: skip

  # let an agent decide where mixed-content PDFs go
  - match: { ext: [.pdf] }
    action: prompt
    prompt: |
      If it's a receipt or invoice, route to AI Library/Receipts/.
      If it's a tax document, route to AI Library/Taxes/.
      Otherwise fall through.
---

# Free-form notes the dispatcher reads as context for ambiguous classifications
```

Matchers include `ext`, `filename_glob`, `filename_regex`, `mime_type`, `size_gt` / `size_lt`, `phase`, and `all` / `any` for combinations. Actions include `delete`, `route` (with `to:`), `route_sensitive` (optionally with `category:`), `ask`, `skip`, and `prompt` (with a natural-language `prompt:` handed off to the `sort-route-by-prompt` agent). Full schema and validation rules live in `skills/sort/OVERRIDES.md`.

### Authoring and debugging

- `/sort:add-rule` — interactive command that walks you through scope → match → action and appends to the file you pick.
- `scripts/match-rules.rb [-v] [--rules-only] [<file>...]` — show which rules apply to a given file, flagging the winner and any shadowed rules. Useful for catching ordering bugs (a broader rule above a more specific one).
- Every rule that fires shows up in the §5 summary's `Rule` column as `<file>:<index>`, so misfires are auditable post hoc.

## Optional dependencies

| Tool | Used for | Install |
|---|---|---|
| `poppler` (`pdftotext`, `pdftoppm`) | PDF classification + scanned-PDF vision fallback | `brew install poppler` |
| `pandoc` | `.epub` → plaintext | `brew install pandoc` |
| `whisper-cpp` | Video transcription | `brew install whisper-cpp` |
| `yt-dlp` | (Not used by sort itself, but commonly produces the videos `/sort-videos` processes) | `brew install yt-dlp` |

`/sort` soft-fails on missing tools — degrades pipelines per-bucket and reports what's reduced rather than aborting.

## Layout

```
plugins/sort/
  .claude-plugin/plugin.json   Claude Code manifest
  .codex-plugin/plugin.json    Codex manifest
  skills/
    sort/                      top-level dispatcher
      SKILL.md
      documents.md             doc sub-dispatcher (read on demand)
      OVERRIDES.md             rule schema reference
    sort-videos/               video pipeline
  commands/
    add-rule.md                /sort:add-rule
  scripts/
    add-rule.rb                rule-append helper
    match-rules.rb             rule-audit / debug tool
    extract-frames.sh          ffmpeg wrapper for sort-videos OCR
  agents/
    video-ocr.md               OCR subagent for sort-videos
    sort-route-by-prompt.md    routing subagent for action: prompt rules
  changelog/                   per-change notes
```
