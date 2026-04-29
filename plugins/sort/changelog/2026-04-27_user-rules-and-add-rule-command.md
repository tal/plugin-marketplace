# User-overridable rules + `/sort:add-rule` command

Added a layered config system that lets users override the dispatcher's per-extension behavior, route specific filename patterns, suppress install prompts for tools they don't use, and tweak top-level settings. Rule files come in committable (`sort.md`) and gitignored (`sort.local.md`) variants at both project and user scope.

## Files

- **Added** `plugins/sort/skills/sort/OVERRIDES.md` — schema reference: file resolution order, top-level keys, matcher list (`ext`, `filename_glob`, `filename_regex`, `mime_type`, `size_gt`/`size_lt`, `phase`, `all`/`any`), action list (`delete`, `route`, `route_sensitive`, `ask`, `skip`), validation behavior, and audit reporting.
- **Added** `plugins/sort/commands/add-rule.md` — interactive `/sort:add-rule` slash command. Walks the user through scope → match → action via AskUserQuestion, confirms before any `delete` rule, then calls the helper script.
- **Added** `plugins/sort/scripts/add-rule.rb` — Ruby helper using stdlib YAML (no extra deps on macOS). Bootstraps the target file with a default template if missing, parses existing frontmatter, appends the new rule, preserves the markdown body. Validates action / route target, soft-fails on bad YAML.
- **Added** `plugins/sort/scripts/match-rules.rb` — debug/audit tool that loads every rule file in priority order and reports which rules match a given file, flagging the winner and any shadowed rules. Supports `-v` (show non-matching rules with reasons) and `--rules-only` (dump merged rule list). Useful for catching ordering bugs before they bite — shadowed rules surface when a broader rule was authored above a more specific one in the same file.
- **Modified** `plugins/sort/skills/sort/SKILL.md`:
  - Added §0.5 "Load user rules" between §0 (Determine targets) and §1 (Classify by type). Documents the four-file resolution order, soft-fail behavior, and audit reporting.
  - §5 summary table gained a `Rule` column showing `<file>:<index>` when a user rule fires.
  - `Action` value list now mentions that `delete` can come from an `action: delete` rule, not just installer dedup.

## File resolution

Rules load in this priority order (first match wins):

1. `$PWD/.claude/sort.local.md` — project-local user override (gitignored)
2. `$PWD/.claude/sort.md` — project-shared (committable)
3. `~/.claude/sort.local.md` — user-global override (gitignored)
4. `~/.claude/sort.md` — user-shared (could live in a dotfiles repo)

The `*.local.md` files should be added to gitignore. The bare `sort.md` files are intended to be checked in.

## Design choices

- **Markdown with YAML frontmatter** rather than pure YAML so the file can hold prose context the dispatcher passes to classification agents for low-confidence cases. Same shape as Claude Code's other plugin-settings files.
- **Stdlib Ruby in the helper** rather than `yq` or PyYAML so the command works on a stock macOS install without any package manager calls. The dispatcher's read path can use `yq` if installed for speed and falls back to a bundled Ruby reader.
- **Phase matchers** for non-file-specific overrides (e.g. suppressing the pandoc install prompt). Without this, users would have no clean way to opt out of dispatcher-level prompts.
- **`route_sensitive` action** keeps the sensitive-folder path in one place (top-level `sensitive_dir`) rather than hardcoded in every rule.
- **Soft-fail across the board** — bad YAML, unknown matcher keys, missing route targets — never abort the run. Worst case the run uses defaults.
- **Audit column in the summary** so a misfiring rule can be spotted without it silently doing the wrong thing.

## Out of scope (for follow-ups)

- Tool-relevance gate in `documents.md` §0 (only prompt for tools needed by the actual file types in this run). The pandoc-skip phase rule is a workaround until that lands.
- A `/sort:edit-rules` command that opens an existing rules file in the user's `$EDITOR`.
- Validation flag in `add-rule.rb` to dry-run a match expression against the current `~/Downloads` contents before saving.
