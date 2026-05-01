# Sort overrides — schema and examples

`/sort` reads optional user-provided rule files before classifying anything. This file documents the schema. The dispatcher itself is in `SKILL.md` §0.5.

## Files and resolution order

Rules are loaded from up to four files. **Every file that exists is read** — a higher-priority file does not skip the lower-priority ones. Their `rules:` lists are concatenated into one combined list, in this priority order:

| Priority | Path | Scope | Committable? |
|---|---|---|---|
| 1 (highest) | `$PWD/.claude/sort.local.md` | per-project, per-user | no — gitignore |
| 2 | `$PWD/.claude/sort.md` | per-project, shared | yes |
| 3 | `~/.claude/sort.local.md` | per-user, all projects | no — never commit |
| 4 (lowest) | `~/.claude/sort.md` | per-user, all projects | yes (e.g. dotfiles repo) |

Resolution semantics for each file in the run:

1. Walk the combined rule list **top-to-bottom**.
2. The **first** rule whose matcher fires for this file wins; the dispatcher applies its action and stops looking.
3. If no rule matches, fall through to default classification (the type table in `SKILL.md` §1 and the per-bucket pipelines).

Priority only matters when multiple rules could match the same file — the higher-priority file's rule wins because it sits earlier in the combined list. A rule in `~/.claude/sort.md` still applies to files that no higher-priority rule touched.

Within a single file, rules apply in the order written. **Author specific patterns above broader ones** — e.g. put `Invoice-*.pdf → Invoices/` above a generic `*.pdf → Documents/`.

For **top-level scalars** (`sources`, `sensitive_dir`), the highest-priority file that sets the key wins on a per-key basis. Setting `sensitive_dir` in `~/.claude/sort.local.md` overrides the value from `~/.claude/sort.md` but doesn't affect `sources` if only `sort.md` sets that.

Convention: anything ending in `.local.md` is **never** committed. Add `.claude/*.local.md` to your project's `.gitignore`. The shared `sort.md` files at either scope are intended to be checked in.

To add rules interactively without hand-editing YAML, run `/sort:add-rule`.

## File format

Each file is markdown with a YAML frontmatter block. The frontmatter holds the structured rules; the markdown body holds prose context the dispatcher can pass into agent prompts for low-confidence classifications.

```yaml
---
# Optional top-level settings
# `sources` overrides the default (CWD where Claude was launched). Set this only
# if you want to pin sort runs to one specific folder regardless of CWD:
sources:
  - ~/Downloads
  - ~/Downloads/Recents
sensitive_dir: ~/Documents/Sensitive

# Ordered list of rules. First match wins.
rules:
  - match: { ext: [.torrent, .nzb] }
    action: delete
    note: "Pointers, not content"

  - match: { filename_glob: "Receipt-*.pdf" }
    action: route
    to: AI Library/Receipts/

  - match: { filename_regex: "(?i)(recovery|backup-codes|\\.env)" }
    action: route_sensitive
---

# Free-form notes the dispatcher will read into agent context

Anything below the closing `---` is loose markdown, surfaced to classification agents as
"user context" so they can make better topic choices for ambiguous documents.
```

## Top-level keys

| Key | Type | Effect |
|---|---|---|
| `sources` | list of paths | Replaces the default scan target (the current working directory the user launched Claude in, plus `<cwd>/Recents/` if it exists). Common use: pin the skill to always sort `~/Downloads` regardless of where Claude was launched. Tilde expansion supported. |
| `sensitive_dir` | path | Pre-answers the "where to file sensitive items?" prompt in `documents.md` §4. Tilde expansion supported. |
| `rules` | list of rule objects | See below. Concatenated across files in priority order. |

## Rule shape

Every rule has a `match` block and an `action`. Optional `to` (for `action: route`), `prompt` (for `action: prompt`), and `note` (free text, shown in the §5 summary).

```yaml
- match: { <matcher>: <value>, ... }
  action: <delete | route | route_sensitive | ask | skip | prompt>
  to: <path>          # only with action: route
  prompt: <string>    # only with action: prompt
  note: <string>      # optional, surfaces in summary
```

### Matchers

| Matcher | Value | Notes |
|---|---|---|
| `ext` | string or list of strings | Leading `.` required (`.torrent` not `torrent`). Lowercased before compare. |
| `filename_glob` | shell-glob string | Matched against basename only. `*.pdf`, `Invoice-*.pdf`. |
| `filename_regex` | regex string | Matched against basename. POSIX extended. Use `(?i)` for case-insensitive. |
| `mime_type` | string | From `file --mime-type`. |
| `size_gt` / `size_lt` | size string | Accepts `100MB`, `2GB`, `500K`, etc. |
| `phase` | dispatcher decision-point name | See "Phases" below. |
| `all` / `any` | list of matchers | Combine matchers with AND / OR. |

`all` example:

```yaml
- match:
    all:
      - ext: [.pdf]
      - filename_regex: "(?i)invoice"
  action: route
  to: AI Library/Invoices/
```

### Phases

Phase matchers fire at named dispatcher decision points instead of per file. Used to opt out of prompts and suppress fallthrough behavior.

| Phase | Fires when | Match sub-fields |
|---|---|---|
| `doc-tools-prompt` | `documents.md` §0 detects missing tools | `missing: [poppler, pandoc]` — only fires if all listed tools are missing |
| `archive-ambiguous` | An archive doesn't fit the "app installer", "image group", or "single document" rules | none |
| `image-low-confidence` | The image vision agent returns low confidence | none |
| `unknown-sensitive-default` | The unknown-bucket sensitive-name regex would route a file to `sensitive_dir` | none — `action: skip` here disables the default |

Example — silence the pandoc install prompt when no `.epub` files are in the run:

```yaml
- match: { phase: doc-tools-prompt, missing: [pandoc] }
  action: skip
```

### Actions

| Action | Effect |
|---|---|
| `delete` | Remove the file. Always reported in the §5 summary with the rule reference. Use sparingly — delete is irreversible. |
| `route` | Move to `to:`. Path can be absolute (`/some/abs/path`), tilde-expanded (`~/Archive`), or `AI Library/<topic>/` shorthand which resolves under the current run's `<target>` folder (so the same shorthand works whether the user is sorting `~/Downloads` or `~/Desktop`). Folder is created if missing. |
| `route_sensitive` | Move to `sensitive_dir`. Cleaner than hardcoding the path in every sensitive rule. |
| `ask` | Force AskUserQuestion for this file even if the dispatcher would have auto-classified it. |
| `skip` | Leave the file alone. Useful when something arrives in the target folder that isn't yours to sort, or to silence a prompt phase. |
| `prompt` | Hand the file to the plugin's `sort-route-by-prompt` agent (see `agents/sort-route-by-prompt.md`) with the rule's `prompt:` text as natural-language routing instructions. The agent sees the file (Read/vision for images and docs), the existing topic folders under `<target>/AI Library/`, and the rule's prompt; it replies with a destination path or a `skip`/`delete`/`fallthrough` decision. Use when the routing logic is too nuanced for static patterns (e.g. "decide if this PDF is a receipt, invoice, or contract and route accordingly"). |

Example — let an agent decide where mixed-content PDFs go:

```yaml
- match: { ext: [.pdf] }
  action: prompt
  prompt: |
    Look at this PDF. If it's a receipt or invoice, route to AI Library/Receipts/.
    If it's a tax document (W-2, 1099, return), route to AI Library/Taxes/.
    If it's a contract or legal document, route to AI Library/Legal/.
    Otherwise fall through to default classification.
```

The agent's allowed responses are: `route: <path>`, `route_sensitive`, `delete`, `skip`, or `fallthrough` (let the default pipeline handle it). The dispatcher applies that decision the same way it would a static rule.

## Validation

The dispatcher soft-fails on bad config:

- File with bad YAML frontmatter → one warning line naming the file, skip that file.
- Rule with unknown matcher or action key → one warning line with the rule index, skip that rule.
- `to:` path on a non-`route` action → ignored.
- `prompt:` on a non-`prompt` action → ignored.
- Missing `to:` on `action: route` → rule treated as `ask` and a warning logged.
- Missing or empty `prompt:` on `action: prompt` → rule treated as `ask` and a warning logged.

The run never aborts because of a misconfigured rule. Defaults take over.

## Auditing rule firings

Every rule that fires shows up in the §5 summary's `Rule` column as `<file>:<index>` (1-based). For example, the third rule in `~/.claude/sort.local.md` shows as `~/.claude/sort.local.md:3`. If a file got moved by default behavior with no rule involved, the column is blank.

## Debugging rules with `match-rules.rb`

To check what rules apply to a given file before running `/sort`:

```bash
ruby ${CLAUDE_PLUGIN_ROOT}/scripts/match-rules.rb [-v] [--rules-only] [<file>...]
```

Defaults:
- Loads every rule file the dispatcher would load, in priority order.
- For each input file, prints **all** rules that match — the first one is flagged `✓ winner` (the rule the dispatcher would actually apply); subsequent matches are flagged `✓ shadow` (matched but suppressed by an earlier rule).
- Files with no matches print "no rule matched — falls through to default classification".

Flags:
- `-v` / `--verbose`: also print every rule that did NOT match, with a reason (`ext .dat ∉ [".pdf"]`, `glob "Invoice-*.pdf" did not match "random.dat"`, etc.). Useful for figuring out why a rule you wrote isn't firing.
- `--rules-only`: print the merged rule list and top-level scalars without matching against any file. Useful to confirm priority order across multiple config files.

Shadowed rules are usually a sign that ordering is wrong — a more specific pattern got authored after a broader one. Move the specific rule earlier in the same file, or to a higher-priority file.
