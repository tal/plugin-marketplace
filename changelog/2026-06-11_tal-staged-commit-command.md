# Add `/tal:git:commit:staged` command

## What changed

- Added `plugins/tal/commands/git/commit/staged.md` — a new command parallel to `/tal:git:commit:quick` that commits **only the changes already in the staging area**.
  - Same fast-path flow as `quick`: infer type/scope from the diff, require a rationale (asking via AskUserQuestion if not obvious), commit with the conventional-commit template, report.
  - Key differences: never runs `git add` (it's not even in `allowed-tools`), only shows `git diff --staged` as context, and stops early with a pointer to `/tal:git:commit:quick` if nothing is staged.
- Updated `plugins/tal/README.md` (intro, Commands, Files of interest, Layout) and `plugins/tal/commands.md` with the new command.
- Updated the `description` in `plugins/tal/.claude-plugin/plugin.json` to mention staged-only commits.

## Why

The quick command stages everything with `git add -A`, which is wrong when you've hand-picked your staging area (e.g. via `git add -p` or the `git-partial-commit` skill) and just want that exact index committed without dragging in unstaged work.
