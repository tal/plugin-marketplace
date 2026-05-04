# 2026-05-04 — Document `claude` CLI install commands in every README

## What changed

Added shell-side `claude plugin marketplace add` / `claude plugin install` invocations alongside the existing in-session `/plugin …` slash commands in every README that documents installation.

Files touched:

- `README.md` (root marketplace README)
- `plugins/iconifier/README.md`
- `plugins/smart-notifications/README.md`
- `plugins/sort/README.md`
- `plugins/tal/README.md`
- `plugins/plan-refiner/README.md`
- `plugins/karabiner/README.md`

## Why

Users who already have `claude` on `PATH` can install plugins without first opening a Claude Code session. The slash-command form was the only documented path; both work, so list both.

## Pattern

Each Claude Code install block now has two snippets:

1. The slash-command form, labeled "from inside the session".
2. The CLI form, labeled "from the shell with the `claude` CLI".

Codex install blocks are unchanged.
