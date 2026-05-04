# tal

Tal's personal common-helpers plugin — a grab-bag of workflow utilities that ship together because they all show up in the same day-to-day routine. Currently covers git commits (atomic and quick), GitHub PR feedback (fetching review threads, replying inline), App Store Connect tooling (`xcrun altool` and ASC REST API patterns), and partial-file staging.

## Install

Claude Code (from inside the session):

```
/plugin install tal@tal-marketplace
```

Or from the shell with the `claude` CLI:

```
claude plugin install tal@tal-marketplace
```

Codex:

```
codex plugin install tal@tal-marketplace
```

See the [marketplace README](../../README.md) for adding the marketplace itself.

## Commands

### Git

- `/tal:git:commit:atomic` — Group uncommitted changes into multiple focused commits, one per logical feature. Runs an Assessment → Build Commit List → Add and Commit pass, includes related implementation/tests/docs in the same commit, and uses the `git-partial-commit` skill to split mixed-feature files. Optional args: `[feature-name] [rationale]` to scope to a single feature. Reach for it when a working tree has accumulated unrelated changes that should land as separate commits.
- `/tal:git:commit:quick` — Stage everything (`git add -A`) and write one commit with a conventional-commit-formatted message. Runs on `sonnet`, restricts itself to `git add` / `git commit` / `git log` so it doesn't wander, and asks for rationale via AskUserQuestion if not obvious from context. Optional args: `[type] [scope] [rationale]`. Reach for it when all changes belong together and you want a fast commit.

### PRs

- `/tal:pr:address-feedback` — Fetch unresolved, non-outdated review threads on a PR and walk through addressing each one. Auto-detects the PR from the current branch, or accepts `[pr-number | pr-url | comment-url]`. Delegates fetching to the `get-pr-feedback` skill (falling back to its script directly if the skill doesn't auto-activate), builds a TodoWrite plan, and edits files thread-by-thread.

## Skills

- **`get-pr-feedback`** — Fires when the user mentions PR feedback, review comments, "what did reviewers say", or pastes a `#discussion_r…` URL. Wraps `gh api` (GraphQL) in `skills/get-pr-feedback/get-pr-comments.sh` to return review threads as structured JSON with accurate resolved/outdated status — something `gh pr view` can't surface. Supports `-a` (actionable only), `-f` (include `diff_hunk`), `-o` (oldest-first), `-v` (verbose). Auto-spills to `/tmp/pr-comments-…json` when output exceeds 25 KB so large PRs don't get truncated by the Bash tool's 30 KB cap.
- **`pr-thread-reply`** — Fires when the user asks to reply to an inline PR review comment or pastes a comment URL with a reply message. Native `gh pr comment` only posts top-level PR comments; this skill posts threaded replies to inline review comments via `gh api` (`skills/pr-thread-reply/reply-pr-thread.sh`). Accepts a comment URL plus message, or `--comment-id` / `--pr` / `--repo` flags, or runs interactively. Marked `disable-model-invocation: true` — invoke it deliberately, not automatically.
- **`appstore-connect`** — Fires for App Store Connect, `altool`, TestFlight uploads, IPA validation, ASC REST API, JWT generation, asset pack management, etc. Reference-only (no scripts) — covers `xcrun altool` authentication (API key vs. password), the full command table (`--upload-package`, `--validate-app`, `--build-status`, `--list-apps`, `--list-providers`, `--generate-jwt`, `--app-store-text`, asset-pack commands), and ASC REST API workarounds for endpoints altool doesn't expose (TestFlight builds, beta groups, review status). Detailed reference files in `skills/appstore-connect/references/`.
- **`git-partial-commit`** — Fires when the user wants to stage specific lines or hunks rather than whole files (splitting mixed changes into atomic commits). Wraps `git apply --cached` against a user-supplied unified diff via `skills/git/partial-commit/stage-lines.sh`. Used internally by `/tal:git:commit:atomic` to handle files that contain changes for multiple features.

## Requirements

Skills assume the following tools are on `PATH` and authenticated where applicable:

- **`gh`** (GitHub CLI), authenticated via `gh auth login` — required by `get-pr-feedback`, `pr-thread-reply`, and `/tal:pr:address-feedback`.
- **`jq`** — required by `get-pr-feedback` and `pr-thread-reply` for JSON parsing.
- **`git`** — required by `git-partial-commit` and the commit commands.
- **`xcrun altool`** (Xcode command line tools) — required by the `appstore-connect` skill. An ASC API key (`AuthKey_<KEY_ID>.p8`) in one of altool's search paths or referenced via `$API_PRIVATE_KEYS_DIR` / `--p8-file-path` is needed for most subcommands.
- **`curl`** — used in the ASC REST API examples for endpoints altool doesn't expose.

## Files of interest

- `commands/git/commit/atomic.md` — Full three-phase atomic commit instructions, including the partial-staging integration and the conventional-commit message template.
- `commands/git/commit/quick.md` — The fast-path commit command, with the inline `git status` / `git diff` slash-bang context blocks.
- `commands/pr/address-feedback.md` — End-to-end PR-feedback workflow with pre-flight checks and skill-fallback logic.
- `skills/get-pr-feedback/get-pr-comments.sh` — The GraphQL-backed comment-fetching script. Worth reading if you want to consume the JSON output programmatically (or pipe through `jq` filters).
- `skills/pr-thread-reply/reply-pr-thread.sh` — REST-API-based inline-reply poster, with URL parsing and comment-ID extraction.
- `skills/git/partial-commit/stage-lines.sh` — `git apply --cached` wrapper used by `/tal:git:commit:atomic` for splitting mixed-feature files.
- `skills/appstore-connect/references/commands.md` — Complete `xcrun altool` command reference: every flag, every parameter, every command.
- `skills/appstore-connect/references/rest-api-workarounds.md` — JWT-plus-curl recipes for TestFlight builds, beta groups, and other ASC REST API endpoints altool can't reach. Notes the URL-encoded bracket gotcha (`%5B` / `%5D`) for filter parameters.
- `commands.md` — A separate, slightly older command-doc file living alongside the README. Has more verbose write-ups of the two git commit commands (with example output and screenshots) than this README does.

## Layout

```
plugins/tal/
  .claude-plugin/plugin.json    Claude Code manifest
  .codex-plugin/plugin.json     Codex manifest
  commands/
    git/commit/
      atomic.md                 /tal:git:commit:atomic
      quick.md                  /tal:git:commit:quick
    pr/
      address-feedback.md       /tal:pr:address-feedback
  skills/
    get-pr-feedback/            PR review-thread fetcher
    pr-thread-reply/            Inline-comment reply poster
    appstore-connect/           xcrun altool + ASC REST API reference
      references/
    git/partial-commit/         Stage exact lines/hunks via git apply --cached
  commands.md                   Long-form command docs (predates this README)
```
