# Sort: tighter sensitivity criteria + `Sensitive/` subcategories

The `/sort` skill was over-flagging documents as sensitive — its old prompt said
"anything a reasonable person would file away from casual access", which swept
in plain receipts, travel itineraries, signed-but-public letters, and most
personal PDFs. Everything landed in one undifferentiated `Sensitive/` pile,
which made the pile useless and also made users hesitant to actually open it.

This change does both: tightens the criteria the LLM uses to decide, and splits
the destination into category subfolders.

## What changed

### Sensitivity is now an enum, not a boolean

The agent in `documents.md` §3 used to return `sensitive: true | false`. It now
returns:

```
sensitive: "no" | "credentials" | "identity" | "financial" | "medical" | "legal" | "other"
```

`no` is the default. The other six are the canonical subcategories. This swap
also fits the global preference for enums over booleans.

### Tighter criteria, with concrete include/exclude lists

The §3 prompt now lists what *does* count as each category (concrete identifier,
credential, account-number, or signed-binding-contract material) and what
*doesn't*: receipts without full card numbers, travel itineraries, meeting
notes, ebooks, manuals, blog posts, journal articles, recipes, marketing PDFs,
blank tax forms, public records. The agent is told to be conservative because
over-flagging dilutes the signal.

### Sensitive items now route into a subfolder

`documents.md` §4 now writes to `<sensitive_dir>/<Category>/` instead of bare
`<sensitive_dir>/`. The category is the Title-Case form of the enum value:
`Credentials`, `Identity`, `Financial`, `Medical`, `Legal`, `Other`. The
subfolder is created if it doesn't exist.

The `<sensitive_dir>` resolution itself is unchanged — it still comes from
user rules' `sensitive_dir:` setting, or the first-sensitive-item AskUserQuestion
default.

### Unknown-bucket credential-name regex routes into Credentials/

The fallback regex in `SKILL.md` §Unknown files (`recovery|backup-codes|.env|
credentials|...`) used to route to bare `<sensitive_dir>/`. It now routes to
`<sensitive_dir>/Credentials/` since the regex by construction only matches
credential filenames. Added `\.pem$`, `\.key$`, `id_rsa`, `id_ed25519` to the
regex to cover SSH keys.

### `route_sensitive` rules can now name a subcategory

`action: route_sensitive` accepts an optional `category:` field. The dispatcher
routes the file to `<sensitive_dir>/<Category>/` when set, or top-level
`<sensitive_dir>/` when absent. Canonical category names are documented in
OVERRIDES.md; non-canonical values pass through with a warning so users can
also create their own subfolders if they want.

### `sort-route-by-prompt` agent gained a categorized reply

The agent's allowed reply forms now include `route_sensitive: <category>` in
addition to bare `route_sensitive`. Same canonical category list, same
last-resort guidance about over-flagging.

## Where the classification lives

For the record (this came up in the implementation): the sensitivity decision
is **entirely LLM-driven**, never Ruby-driven. The Ruby scripts only do static
matching (extension, filename glob/regex, mime type, size). The judgment about
"is this file sensitive, and which category" happens in three places, all
LLM-based:

1. `documents.md` §3 — the per-document classifier (the main path).
2. `agents/sort-route-by-prompt.md` — when `action: prompt` rules fire.
3. `SKILL.md` §Unknown files — credential-filename regex (the only non-LLM
   path, but it's a *filename* match and only routes credential-named files,
   so the subcategory is hardcoded as `Credentials/` rather than guessed).

When a user writes `category: credentials` directly in their `sort.md`, that's
the user's own classification — Ruby just records it.

## Files changed

- `plugins/sort/skills/sort/documents.md` — rewrote §3's sensitivity criteria
  with concrete include/exclude lists; changed reply schema to the enum;
  updated §4 routing to use `<sensitive_dir>/<Category>/`; updated §6
  `Action` value to `classified-sensitive(<Category>)`.
- `plugins/sort/skills/sort/SKILL.md` — credential-name regex now routes to
  `<sensitive_dir>/Credentials/`; added `.pem`, `.key`, SSH key filenames
  to the regex; §5 Action legend updated to `classified-sensitive(<Category>)`
  with the canonical category list; `action: prompt` reply documentation
  extended with `route_sensitive: <category>`.
- `plugins/sort/skills/sort/OVERRIDES.md` — `route_sensitive` action gained
  optional `category:` field, documented in actions table, rule shape, and
  validation list; example block updated.
- `plugins/sort/agents/sort-route-by-prompt.md` — allowed reply forms now
  include `route_sensitive: <category>`, with a canonical category list and
  guidance to be conservative.
- `plugins/sort/scripts/add-rule.rb` — accepts `--category=<name>`, validates
  against canonical list (warns on non-canonical, ignores when paired with
  non-`route_sensitive` actions), writes the field to the rule.
- `plugins/sort/scripts/match-rules.rb` — `render_action` now displays the
  category as `[<category>]` in `--rules-only` and per-file output.
- `plugins/sort/commands/add-rule.md` — interactive flow asks for the
  subcategory after picking "Treat as sensitive"; example bash invocation
  and `key=value` shorthand both accept `category`.

## Migration

Existing user rules with `action: route_sensitive` (no `category:`) keep
working unchanged — they continue to land in top-level `<sensitive_dir>/`.
Users can re-run `/sort:add-rule` to add categorized rules going forward, or
edit their `sort.md` by hand to add `category:` to existing rules.

Existing files already in `<sensitive_dir>/` from prior runs are not
automatically reorganized into subfolders. Subfolder routing only applies to
new sort runs.

## Smoke-tested

- `add-rule.rb` accepts canonical and non-canonical categories with the
  correct warning behavior.
- `add-rule.rb` ignores `--category` when paired with non-`route_sensitive`
  actions, with the correct warning.
- `match-rules.rb` renders `route_sensitive [credentials]` for categorized
  rules and `route_sensitive` for uncategorized ones.
- `ruby -c` passes on both scripts.
