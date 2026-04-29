---
description: Add a rule to your sort config (sort.md or sort.local.md)
argument-hint: ""
allowed-tools:
  - AskUserQuestion
  - Bash
  - Read
---

# Add a sort rule

Interactive command for appending a rule to one of:

- `~/.claude/sort.md` — user-shared, committable to a dotfiles repo
- `~/.claude/sort.local.md` — user-only, not committed
- `$PWD/.claude/sort.md` — project-shared
- `$PWD/.claude/sort.local.md` — project-only override

The dispatcher reads these in priority order (project local → project shared → user local → user shared) and applies the first matching rule. Schema reference: `${CLAUDE_PLUGIN_ROOT}/skills/sort/OVERRIDES.md`.

## Procedure

Walk the user through a short interactive flow using AskUserQuestion. Don't ask all four questions in one batch — gather the action category first, since later questions depend on it.

### 1. Where to save

Ask which file. Default to `~/.claude/sort.local.md` because most rules are personal and not worth committing.

```
question: "Which config file should this rule go into?"
header: "Scope"
options:
  - "~/.claude/sort.local.md (user, not committed) (Recommended)"
  - "~/.claude/sort.md (user, committable to dotfiles)"
  - "$PWD/.claude/sort.md (project, committed)"
  - "$PWD/.claude/sort.local.md (project, not committed)"
```

If the user picks a project-scoped file and `$PWD/.claude/` doesn't exist, create it.

### 2. What to match

```
question: "What should this rule match?"
header: "Match type"
options:
  - "File extension(s) (e.g. .torrent, .nzb)"
  - "Filename glob (e.g. Invoice-*.pdf)"
  - "Filename regex (e.g. (?i)recovery)"
  - "Dispatcher phase (suppress a prompt or fallthrough)"
```

Then ask a follow-up plain-text question for the value:
- For extensions: comma-separated list. Normalize: lowercase, ensure each has a leading `.`.
- For glob/regex: take the user's literal string.
- For phase: list the supported phases (`doc-tools-prompt`, `archive-ambiguous`, `image-low-confidence`) and any sub-fields (e.g. for `doc-tools-prompt` ask which tools' prompt should be skipped).

### 3. What action

```
question: "What should happen when this rule matches?"
header: "Action"
options:
  - "Delete the file"
  - "Route to a specific folder"
  - "Treat as sensitive (route to sensitive_dir)"
  - "Ask interactively each time"
```

If the user picks Delete, warn that it's irreversible and confirm:

```
question: "Confirm: delete files matching this rule on every /sort run?"
header: "Confirm delete"
options:
  - "Yes, always delete"
  - "No, change to 'ask' instead"
```

If the user picks Route, ask a plain-text follow-up for the destination. Accept `AI Library/<Topic>/` shorthand or absolute/tilde paths.

### 4. Optional note

Ask for a one-line note describing why this rule exists. Skippable.

### 5. Append the rule

Build a YAML inline match expression from the gathered fields and call the helper script:

```bash
ruby "${CLAUDE_PLUGIN_ROOT}/scripts/add-rule.rb" \
  "<file path>" \
  "<match yaml inline>" \
  "<action>" \
  "<to path or empty>" \
  --note="<note or empty>"
```

The script:
- Creates the file with a default template if it doesn't exist
- Parses existing frontmatter, appends the new rule, writes back
- Prints the appended rule to stdout

### 6. Confirm

Show the user:
- The file path that was edited
- The exact YAML block that was appended
- A reminder: "This rule applies on the next `/sort` run."

## Argument shorthand (optional)

If `$ARGUMENTS` is non-empty, parse `key=value` pairs to skip prompts where possible. Supported keys: `file`, `ext`, `glob`, `regex`, `phase`, `action`, `to`, `note`. Anything missing falls back to the interactive flow.

Example:

```
/sort:add-rule ext=.torrent,.nzb action=delete note="auto-delete torrent files"
```
