# tal

Tal's personal common-helpers plugin — a grab-bag of workflow utilities that ship together because they all show up in the same day-to-day routine. Currently covers simple visual explanations, reference-clarity rewrites, session-focus guardrails, git commits (atomic, quick, and staged-only), GitHub PR feedback (fetching review threads, replying inline), release deploys (`/deploy`, TestFlight first), App Store Connect tooling (`xcrun altool` and ASC REST API patterns), partial-file staging, and Plex stand-up poster sourcing and installation.

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

### Explanations

- `/tal:eli5 <topic>` — Explain a topic for someone with no prior knowledge as an HTML artifact with big pictures and few words.

### Git

- `/tal:git:commit:atomic` — Group uncommitted changes into multiple focused commits, one per logical feature. Runs an Assessment → Build Commit List → Add and Commit pass, includes related implementation/tests/docs in the same commit, and uses the `git-partial-commit` skill to split mixed-feature files. Optional args: `[feature-name] [rationale]` to scope to a single feature. Reach for it when a working tree has accumulated unrelated changes that should land as separate commits.
- `/tal:git:commit:quick` — Stage everything (`git add -A`) and write one commit with a conventional-commit-formatted message. Runs on `sonnet`, restricts itself to `git add` / `git commit` / `git log` so it doesn't wander, and asks for rationale via AskUserQuestion if not obvious from context. Optional args: `[type] [scope] [rationale]`. Reach for it when all changes belong together and you want a fast commit.
- `/tal:git:commit:staged` — Same fast-path workflow as `quick`, but commits **only what's already staged** — it never runs `git add`, leaves unstaged changes untouched, and stops if the index is empty. Runs on `sonnet`, restricts itself to `git commit` / `git log`, and asks for rationale via AskUserQuestion if not obvious from context. Optional args: `[type] [scope] [rationale]`. Reach for it when you've hand-picked your staging area and just want it committed.

All three commit commands set `context: fork` **plus** `background: false`. A forked command defaults to `background: true`, which detaches it into a named background agent — you get "Running in the background as @agent", the command can't prompt you, and any AskUserQuestion for rationale dies. `background: false` keeps the fork synchronous and in the foreground: it still runs in its own context (only the final `<local-command-stdout>` lands in the parent transcript), but it blocks the turn, streams progress inline, and can prompt you. Keep both keys together — dropping `background: false` silently re-backgrounds the command.

### PRs

- `/tal:pr:address-feedback` — Fetch unresolved, non-outdated review threads on a PR and walk through addressing each one. Auto-detects the PR from the current branch, or accepts `[pr-number | pr-url | comment-url]`. Delegates fetching to the `get-pr-feedback` skill (falling back to its script directly if the skill doesn't auto-activate), builds a TodoWrite plan, and edits files thread-by-thread.

### Deploy

- `/tal:deploy [target | pipeline | target:channel] [channel] [--dirty]` (also `/deploy` when nothing else claims the name; `$deploy` in Codex) — the slash form of the `deploy` skill below. `/deploy testflight internal` ships to that target and channel. With no target, it asks which one (or uses the only configured target). With no channel, it asks (or uses the only one).

### Handoff

- `/tal:handoff` (also reachable as `/handoff` when there's no namespace conflict) — Invoke the `handoff` skill to compact the current conversation into a handoff document at a `mktemp -t handoff-XXXXXX.md` path. Optional argument: a one-liner describing the next session's focus. The skill is marked `disable-model-invocation: true`, so it never fires on its own — this command is the only way in.

## Skills

- **`unambiguous`** — Automatically applies when the user asks to clarify a document or passage, eliminate ambiguity, fix unclear pronouns, demonstratives, or antecedents, or disambiguate a sentence. It keeps already-clear references, makes the smallest necessary edits, reports material grammatical ambiguities, and avoids broader copyediting.
- **`stay-on-track`** — Fires when the user says "stay on track," "don't go off track," "stick to the plan," or otherwise asks to require confirmation before deviating from the session's goal. Pins down the stated or inferred goal in one sentence, then for the rest of the conversation stops and asks before starting unrequested work, broadening scope, switching approach, or touching unrelated files — but doesn't gate on in-scope decisions or on work the user directly asks for afterward.
- **`deploy`** — Generic release plumbing driven by a per-repo `.config/deploy.yml`. Every top-level block in that file is a target (`testflight:`, `supabase:`, …) with its own `channels`. Order: show a resolved plan and wait for a yes → clean-tree / branch / unpushed check → isolated version-bump commit → preflight, ship and verify per `targets/<target>.md` → immutable annotated tag `builds/<target>/<channel>/<version>` → release changelog with What's New since that channel's last tag. Dirty trees deploy only with `--dirty` (or saying so), and then get no bump commit and no tag, only an UNTAGGED changelog entry. Named `pipelines:` run several targets in order and stop at the first failure. An unconfigured target gets a best-effort run, then an offer to save it as a new target file. Ships three targets. `targets/fly.md`: `fly deploy` per Fly app (one channel per app), image re-use for promotion, rollback by redeploying the previous image. `targets/push.md`: deploy by `git push <remote> <commit>:<ref>` with a fast-forward check, `--force-with-lease` only behind a gate, and Verify by following the GitHub Actions run or polling a health URL. `targets/testflight.md` (archive → export → release gate → `altool --upload-package` → What's New via `betaBuildLocalizations` → beta-review submit → external group attach, plus promotion of an internal build to external and the CLI release landmines). Deterministic steps are scripts in `skills/deploy/scripts/`: `verify-clean-tree.sh`, `build-id.sh` (version schemes plus the dotted-tuple ordering guard), `release-commit.sh`, `since-last-tag.sh` (handles tags orphaned by rewritten history) and `tag.sh` (refuses dirty trees and existing tags).
- **`get-pr-feedback`** — Fires when the user mentions PR feedback, review comments, "what did reviewers say", or pastes a `#discussion_r…` URL. Wraps `gh api` (GraphQL) in `skills/get-pr-feedback/get-pr-comments.sh` to return review threads as structured JSON with accurate resolved/outdated status — something `gh pr view` can't surface. Supports `-a` (actionable only), `-f` (include `diff_hunk`), `-o` (oldest-first), `-v` (verbose). Auto-spills to `/tmp/pr-comments-…json` when output exceeds 25 KB so large PRs don't get truncated by the Bash tool's 30 KB cap.
- **`pr-thread-reply`** — Fires when the user asks to reply to an inline PR review comment or pastes a comment URL with a reply message. Native `gh pr comment` only posts top-level PR comments; this skill posts threaded replies to inline review comments via `gh api` (`skills/pr-thread-reply/reply-pr-thread.sh`). Accepts a comment URL plus message, or `--comment-id` / `--pr` / `--repo` flags, or runs interactively. Marked `disable-model-invocation: true` — invoke it deliberately, not automatically.
- **`appstore-connect`** — Fires for App Store Connect, `altool`, TestFlight uploads, IPA validation, ASC REST API, JWT generation, asset pack management, etc. Mostly reference, plus `scripts/asc-jwt.py`, which mints an ES256 JWT with an integer `exp` (stdlib Python + `openssl`; `altool --generate-jwt` emits a fractional `exp` the REST API has rejected with 401). Covers `xcrun altool` authentication (API key vs. password), the full command table (`--upload-package`, `--validate-app`, `--build-status`, `--list-apps`, `--list-providers`, `--generate-jwt`, `--app-store-text`, asset-pack commands), and ASC REST API workarounds for endpoints altool doesn't expose (TestFlight builds, beta groups, review status). Detailed reference files in `skills/appstore-connect/references/`.
- **`git-partial-commit`** — Fires when the user wants to stage specific lines or hunks rather than whole files (splitting mixed changes into atomic commits). Wraps `git apply --cached` against a user-supplied unified diff via `skills/git/partial-commit/stage-lines.sh`. Used internally by `/tal:git:commit:atomic` to handle files that contain changes for multiple features.
- **`handoff`** — Compacts the current conversation into a handoff document so a fresh agent can pick up the work. Writes the doc to a `mktemp -t handoff-XXXXXX.md` path, suggests skills the next session should reach for, and references existing artifacts (PRDs, plans, ADRs, issues, commits, diffs) by path/URL rather than restating them. Optional argument: a one-liner describing what the next session will focus on. Marked `disable-model-invocation: true` — invoke explicitly via `/tal:handoff` (or `/handoff`); it will never auto-fire from the description. Adapted from [mattpocock/skills](https://github.com/mattpocock/skills/blob/733d312884b3878a9a9cff693c5886943753a741/skills/in-progress/handoff/SKILL.md).
- **`plex-standup-posters`** — Fires when new YouTube or provider-managed stand-up downloads need Plex-ready artwork, folder metadata, cast tags, or portrait replacements for landscape thumbnails. Inventories videos/folders without matching assets, resolves exact comedian/title metadata, prioritizes official portrait art, generates only missing designs from official thumbnails, normalizes and visually checks `1000x1500` posters, installs sidecars and directly selected Plex uploads, adds the performer as a text actor tag, and verifies the image Plex actually serves. It explicitly distinguishes that text tags are not canonical Plex person links unless `tagKey`/`thumb` are present. Includes `scripts/plex-standup-posters.sh` for YouTube inventory, section-scoped scans, guarded installation, cast updates, and end-to-end verification against the personal `synfeld` setup.

## Requirements

Skills assume the following tools are on `PATH` and authenticated where applicable:

- **`gh`** (GitHub CLI), authenticated via `gh auth login` — required by `get-pr-feedback`, `pr-thread-reply`, and `/tal:pr:address-feedback`.
- **`jq`** — required by `get-pr-feedback` and `pr-thread-reply` for JSON parsing.
- **`git`** — required by `git-partial-commit` and the commit commands.
- **`xcrun altool`** (Xcode command line tools) — required by the `appstore-connect` skill. An ASC API key (`AuthKey_<KEY_ID>.p8`) in one of altool's search paths or referenced via `$API_PRIVATE_KEYS_DIR` / `--p8-file-path` is needed for most subcommands.
- **`git`, `jq`, `curl`, `xcodebuild` / `xcrun altool`** — required by `deploy` (the last two only for the `testflight` target). The `fly` target needs `flyctl`. The `push` target needs `gh` when `watch: gh-run`. The TestFlight target needs an ASC API key; by default it looks in `~/.config/appstoreconnect/private_keys` and exports `API_PRIVATE_KEYS_DIR` itself.
- **`python3` + `openssl`** — required by `appstore-connect`'s `scripts/asc-jwt.py` (and by the `deploy` TestFlight target, which uses it).
- **`curl`** — used in the ASC REST API examples for endpoints altool doesn't expose.
- **`ssh`, `curl`, `jq`, and ImageMagick's `magick`** — required by `plex-standup-posters`. The personal defaults expect SSH host `synfeld`, media under `/volume1/Media/Standup`, and `PLEX_URL` / `PLEX_TOKEN` in `/Users/tal/Projects/darr-manager/.env`; each default has an environment-variable override.

## Files of interest

- `commands/eli5.md` — `/tal:eli5` prompt for producing a simple, visual HTML explanation of a topic.
- `skills/unambiguous/SKILL.md` — Rewrite guidance and trigger metadata for eliminating ambiguous references and grammatical parses while preserving meaning and voice.
- `commands/git/commit/atomic.md` — Full three-phase atomic commit instructions, including the partial-staging integration and the conventional-commit message template.
- `commands/git/commit/quick.md` — The fast-path commit command, with the inline `git status` / `git diff` slash-bang context blocks.
- `commands/git/commit/staged.md` — The staged-only sibling of `quick.md`: identical flow, but no `git add` and only the `git diff --staged` context block.
- `commands/pr/address-feedback.md` — End-to-end PR-feedback workflow with pre-flight checks and skill-fallback logic.
- `skills/get-pr-feedback/get-pr-comments.sh` — The GraphQL-backed comment-fetching script. Worth reading if you want to consume the JSON output programmatically (or pipe through `jq` filters).
- `skills/pr-thread-reply/reply-pr-thread.sh` — REST-API-based inline-reply poster, with URL parsing and comment-ID extraction.
- `skills/git/partial-commit/stage-lines.sh` — `git apply --cached` wrapper used by `/tal:git:commit:atomic` for splitting mixed-feature files.
- `skills/deploy/SKILL.md` — Deploy plumbing: argument grammar, `deploy.yml` generic keys and defaults, the order of operations, dirty / promotion / pipeline / best-effort runs, and the release changelog template.
- `skills/deploy/targets/testflight.md` — The TestFlight target: required keys, version bump, preflight, ship, verify, rollback and landmines.
- `skills/deploy/targets/fly.md` — The Fly.io target (`flyctl`).
- `skills/deploy/targets/push.md` — The deploy-by-`git push` target (CI or PaaS git remotes).
- `skills/deploy/scripts/` — `verify-clean-tree.sh`, `build-id.sh`, `release-commit.sh`, `since-last-tag.sh`, `tag.sh`.
- `skills/appstore-connect/scripts/asc-jwt.py` — Integer-`exp` ASC JWT minter. The issuer defaults to the `AuthKey_<id>.issuer-id` sidecar, and the key dir defaults to `$API_PRIVATE_KEYS_DIR`, then `~/.config/appstoreconnect/private_keys`.
- `skills/appstore-connect/references/commands.md` — Complete `xcrun altool` command reference: every flag, every parameter, every command.
- `skills/appstore-connect/references/rest-api-workarounds.md` — JWT-plus-curl recipes for TestFlight builds, beta groups, and other ASC REST API endpoints altool can't reach. Notes the URL-encoded bracket gotcha (`%5B` / `%5D`) for filter parameters.
- `skills/plex-standup-posters/SKILL.md` — End-to-end sourcing, generation, normalization, installation, and verification policy for new YouTube comedy-special artwork in the Plex Standup library.
- `skills/plex-standup-posters/scripts/plex-standup-posters.sh` — Guarded helper for discovering missing sidecars, scanning only the Standup section, writing exact-basename artwork, selecting uploaded Plex posters, and verifying served dimensions.
- `commands.md` — A separate, slightly older command-doc file living alongside the README. Has more verbose write-ups of the two git commit commands (with example output and screenshots) than this README does.

## Layout

```
plugins/tal/
  .claude-plugin/plugin.json    Claude Code manifest
  .codex-plugin/plugin.json     Codex manifest
  commands/
    eli5.md                     /tal:eli5
    git/commit/
      atomic.md                 /tal:git:commit:atomic
      quick.md                  /tal:git:commit:quick
      staged.md                 /tal:git:commit:staged
    pr/
      address-feedback.md       /tal:pr:address-feedback
    handoff.md                  /tal:handoff (also /handoff)
  skills/
    unambiguous/               Reference-clarity rewriting
    stay-on-track/             Session-focus guardrails, auto-fires on "stay on track"
    get-pr-feedback/            PR review-thread fetcher
    pr-thread-reply/            Inline-comment reply poster
    deploy/                     /deploy release plumbing
      targets/                  One file per destination (testflight, fly, push)
      scripts/                  Clean-tree, build id, bump commit, What's New range, tag
    appstore-connect/           xcrun altool + ASC REST API reference
      references/
      scripts/asc-jwt.py        Integer-exp JWT minter
    git/partial-commit/         Stage exact lines/hunks via git apply --cached
    handoff/                    Conversation handoff document writer
    plex-standup-posters/       Source and install 2:3 Plex stand-up artwork
  commands.md                   Long-form command docs (predates this README)
```
