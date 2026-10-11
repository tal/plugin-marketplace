---
name: deploy
description: Deploy or release the current repo with `/deploy [target] [channel]` (`$deploy` in Codex), driven by the repo's `.config/deploy.yml`. Checks the tree is clean, makes an isolated version-bump commit, ships through a per-destination target file (TestFlight, Fly.io, or a deploy-by-`git push` branch), creates an immutable annotated tag `builds/<target>/<channel>/<version>`, and writes a release changelog with What's New since that channel's last tag. Use when the user wants to actually deploy, release or ship this repo, e.g. "deploy this", "ship it to TestFlight", "upload a build of this app", "push a TestFlight build", "promote the internal build to external", "deploy to staging / prod", "fly deploy", "push to production", "cut a release", "tag the release". Also answers "what's new since the last build" without deploying. For a TestFlight upload from a repo with `.config/deploy.yml`, use this skill instead of `tal:appstore-connect`, which remains the reference for raw altool / REST mechanics. Not for general questions about deploy tooling or CI.
argument-hint: "[target | pipeline | target:channel] [channel] [--dirty]"
---

# Deploy

Generic release plumbing. Everything about a particular destination lives in
`targets/<target>.md`. This file never learns how a destination works: if a
step here starts to need a target-specific `if`, move it into the target file.

`$S` below means `${CLAUDE_PLUGIN_ROOT}/skills/deploy/scripts`. Scripts print
`key=value` lines on stdout and explain refusals on stderr.

**Read-only questions** ("what's new since the last build?", "what did
external last get?"): resolve the target and channel (§3), run
`since-last-tag.sh` (§5) and answer. Don't plan, bump or deploy.

## 1. Parse the request

Arguments: `$ARGUMENTS`

```
/deploy [<target> | <pipeline> | <target>:<channel>] [<channel>] [--dirty] [--<key> <value>]
```

- Plain words work the same way: "deploy testflight internal even though it's dirty".
- `--<key> <value>` overrides one `deploy.yml` key for this run only, e.g. `--unpushed_policy refuse`.
- `--dirty`, or plainly saying to deploy anyway on a dirty tree, is the **only**
  way to allow a dirty tree. It is never a `deploy.yml` key and never carries
  over to the next run.

## 2. Load the config

Read `$(git rev-parse --show-toplevel)/.config/deploy.yml`. A missing file is
fine; then no targets are configured.

Generic keys. All are optional, and the defaults live here, not in the file:

| Key | Default | Meaning |
|---|---|---|
| `branch` | the remote's default branch (`git symbolic-ref --short refs/remotes/origin/HEAD`, minus `origin/`) | Deploys must come from this branch |
| `version_scheme` | `timestamp-dotted` | `timestamp-dotted` (`YYYY.M.D.H.MM`) / `semver` / `git-sha` |
| `tag_pattern` | `builds/{target}/{channel}/{version}` | Annotated tag name |
| `bump_commit` | `chore(build): ship {version} [{channel}]` | Bump commit subject |
| `bump_trailers` | `["Deploy-Target: {target}", "Deploy-Channel: {channel}"]` | Bump commit trailers (greppable) |
| `changelog_dir` | `changelog/` | Where release logs go |
| `changelog_pattern` | `{date}_{target}-release-{version}.md` | `{date}` = `YYYY-MM-DD` |
| `changelog_commit` | `docs: log {target} release {version} ({channel})` | Changelog commit subject |
| `release_notes_source` | `{include: [feat, fix, perf], exclude: [chore, docs, test, ci, build, style, refactor, design]}` | Conventional-commit types that count as user-facing |
| `unpushed_policy` | `push` | `push` / `ask` / `refuse` |
| `confirm_before` | `[]` | Extra gates by step name. Generic steps: `push`, `bump-commit`, `ship`, `tag`. Targets name their own (e.g. `upload`) |
| `pipelines` | none | `name: [target:channel, …]`, see §8 |

**Every other top-level key is a target block.** The key is the target name,
and having a block is what makes a target configured. A target block holds:

- `channels`: a list (`[internal, external]`) or a map
  (`staging: {project_ref: …}`), in promotion order. Map values merge over the
  block for that channel. No `channels` means the channels in the target
  file's **Channels** line (e.g. `internal`, `external`); a target with neither
  has one channel named `default`. The same applies to a target file with no block.
- Overrides of any generic key (e.g. a block-level `version_scheme`).
- The target's own keys, as listed under **Required keys** in its target file.

Secrets never go in the file: env var **names** and key **paths** only.

Config errors (stop and name the problem): a pipeline with the same name as a
target block; a pipeline step that doesn't name a target block and one of its
channels. Pipelines never run best-effort targets (§9).

Minimal file:

```yaml
testflight:
  app_id: "1234567890"
  # …the rest of the Required keys from targets/testflight.md
  channels:
    internal:
      beta_groups: [{name: App Store Connect Users, id: <uuid>, kind: internal}]
    external:
      beta_groups: [{name: Public Beta, id: <uuid>, kind: external}]
```

## 3. Resolve target and channel

First word, checked in this order:

1. A pipeline name → pipeline run (§8).
2. A target block → that target. `<target>:<channel>` sets both.
3. A `targets/<name>.md` with no block → that target. Its required keys will be
   missing, so ask for them (§4).
4. A word that is a channel in exactly one target block (e.g. `/deploy internal`
   when only `testflight` has an `internal` channel) → that target and channel.
5. Anything else → **best-effort target** (§9).

No target given: with exactly one target block and no pipelines, use it.
Otherwise ask with AskUserQuestion. The options are the target blocks plus
pipelines (or, with no `deploy.yml`, the shipped `targets/*.md`), and "Other"
covers anything past four.

Channel: if given, it must be one of the target's channels, or stop and list
them. If not given: one channel → use it; several → ask with the target's
channels as options.

No AskUserQuestion tool (e.g. Codex): ask the same question in plain text and wait.

## 4. Load the target file

Read `targets/<target>.md` from this skill's directory. Every target file has
the same headings: **Required keys, Version bump, Preflight, Ship, Verify,
Rollback, Notes / landmines**.

Check every required key against the merged block + channel values. If one is
missing, stop and ask. Never silently default. Offer to write the answers into
`.config/deploy.yml` at the end of the run.

## 5. Resolve the plan, then confirm

Everything in this section is read-only. It decides the whole run before
anything changes.

1. **Repo state:** `"$S/verify-clean-tree.sh" --branch <branch>`
2. **Target Preflight:** run the target file's **Preflight** checks now. They
   can stop the run, add lines to the plan (e.g. certificate headroom), or
   **declare a promotion run** (below).
3. **Version.** New builds:
   `"$S/build-id.sh" --scheme <version_scheme> --target <target> --tag-pattern '<tag_pattern>'`.
   For a promotion run, the version is the promoted artifact's version.
4. **What's New.**
   `"$S/since-last-tag.sh" --target <target> --channel <channel> --tag-pattern '<tag_pattern>' --include <csv> --exclude <csv>`.
   Add `--head <commit>` for a promotion run. Write the notes now (§7) and show
   them in the plan. That exact text is reused unchanged by Ship (if the target
   pushes notes), the tag and the changelog.

Stop before planning when:

- `branch_status` is `mismatch` or `detached` (exit 2). Say which branch is needed.
- `tree=dirty` (exit 1) and the run isn't `--dirty`. List the `dirty_file`
  lines (raw porcelain, status code included) and say to commit them or re-run
  with `--dirty`.
- `ahead > 0` and `unpushed_policy` is `refuse`. With `upstream=none`, `ahead`
  and `behind` are `-`: say so in the plan, and push later with `git push -u origin <branch>`.
- `build-id.sh` refuses (exit 1). For ordered schemes (`timestamp-dotted`,
  `semver`), a new version must sort above every earlier one, and stderr
  explains why. Two `timestamp-dotted` runs in the same minute collide, so wait
  a minute and re-run. `git-sha` has no ordering check.
- The target's Preflight says to stop.

Then echo the resolved plan:

```
Deploy   testflight → internal            (targets/testflight.md)
Repo     weather-range @ master a1b2c3d
Tree     clean                            ← or: DIRTY, 3 files. UNTAGGED deploy, no bump commit
Push     2 unpushed commits → push first (unpushed_policy: push)
Behind   0
Version  2026.10.11.14.05  (timestamp-dotted; previous 2026.10.6.14.11)
Since    builds/testflight/internal/2026.10.3.14.08: 3 user-facing, 1 unclassified
Steps    push → bump commit → ship → verify → tag builds/testflight/internal/2026.10.11.14.05 → changelog → push
Gates    upload
Preflight  signing identity present; ASC newest build 2026.10.6.14.11

What's New
- <the notes, exactly as they will ship>
```

Ask with AskUserQuestion: **Deploy as planned?** → Deploy / Cancel. This
confirmation is always required, even on a clean run. Nothing in §6 runs
before it.

## 6. Run

The steps run in this order. A `confirm_before` gate is a yes/no question asked
right before the step it names.

1. **Push** (`push`): if `ahead > 0`, then `git push` under `push`, ask under `ask`.
2. **Version bump** (`bump-commit`). Promotion runs skip this step. Dirty
   runs apply the version but skip `release-commit.sh` (below). Otherwise,
   apply the version as the target's **Version bump** section says, then:
   ```bash
   "$S/release-commit.sh" --target <t> --channel <c> --version <v> \
     --subject '<bump_commit>' --trailer '<trailer 1>' --trailer '<trailer 2>' \
     [--expect '<glob from the target file>' …]
   ```
   Exit 3 (`status=nothing-to-commit`) is fine: this target or scheme changed
   no files (e.g. `git-sha`), and the commit to tag is `HEAD`. Exit 1 means the
   change wasn't an isolated bump: `unexpected=` lines name files outside the
   `--expect` globs, or something was already staged. Stop and report. Add any
   commit attribution trailer your harness requires as one more `--trailer`.
3. **Ship → Verify** (`ship`, plus the target's own gate names): follow the
   target file. Record the **artifact** (build id, image digest, migration
   list). It goes into the tag and the changelog.
   - **If Ship or Verify fails**, skip the tag and go straight to steps 5–6
     with the changelog marked **FAILED** and the error. Keep the bump commit
     and never revert it: the next run bumps again, so a version number is
     never reused.
   - A state the target's Verify calls **pending** (e.g. waiting for beta
     review) counts as shipped: tag it, and record the pending state in the
     changelog Status.
4. **Tag** (`tag`), on clean runs only. Write the annotation to a temp file:
   ```
   <version> → <target> <channel>
   Artifact: <artifact id(s)>
   Commit: <sha>  Tree: clean

   What's New:
   <notes>
   ```
   ```bash
   "$S/tag.sh" --name <rendered tag_pattern> --commit <bump commit or HEAD> \
     --message-file <file> --remote origin
   ```
   If `tag.sh` refuses (exit 1 dirty tree, exit 2 tag already exists), stop and
   report. Never work around it: no moving, deleting or force-pushing tags, and
   no moving `latest`-style pointer tags. Exit 3 (`pushed=failed`) means the
   local tag exists but the push failed. Keep the tag and retry the push
   command `tag.sh` printed.
5. **Changelog** (§7). Commit only that file:
   `git add <file> && git commit -m '<changelog_commit>' -- <file>`.
6. **Push** the branch: `push` → `git push`; otherwise ask.

### Dirty runs (`--dirty`)

- The plan says `Tree: DIRTY, N files` and that the deploy is **untagged**.
  It needs the same confirmation as any other run.
- Before touching anything, capture `git rev-parse HEAD` and `git diff --stat`.
- **No bump commit.** Only `release-commit.sh` is skipped. The version still
  comes from `build-id.sh` and is still applied the way the target's Version
  bump section says, so the build carries it. Commit nothing. After Verify (or
  on failure), `git restore` every file the bump changed that was clean before
  the run, and leave files that already had edits alone.
- **No tag.** `tag.sh` is not called.
- The changelog entry is marked **UNTAGGED: dirty tree** and records the
  starting `HEAD` sha and the `git diff --stat`. It is the only trail a dirty
  deploy leaves.

### Promotion runs

When the target's Preflight declares that this run re-points an artifact that
was already built (e.g. TestFlight internal → external). The version and What's
New are already computed for it in §5:

- Skip the version bump and the build.
- The version is that artifact's version.
- Tag the commit the artifact was built from (`git rev-list -n1 <earlier tag>`).
- What's New was computed in §5 with `--head <that commit>`.

## 7. Release changelog

Path: `<changelog_dir>/<changelog_pattern>`. Never overwrite an existing file;
append `-2`, `-3`, … instead.

```markdown
# <target> release <version> (<channel>)

| Field | Value |
|---|---|
| Version | <version> (plus a marketing version if the target has one) |
| Channel | <channel> (<groups / environment / stack>) |
| Artifact | <artifact ids> |
| Bump commit / tag | <sha> / <tag>, or "none (UNTAGGED: dirty tree)" |
| Previous <channel> release | <version from the base tag, or none> |
| Status | shipped / shipped (pending: <state>) / FAILED: <error> / UNTAGGED: dirty tree |

## What's New
<the notes>

## Pipeline notes
- Surprises, workarounds, anything the next run should know.
```

Dirty runs add a `## Dirty tree` section with the starting `HEAD` sha and the
`git diff --stat`.

**What's New** is written in §5, before the plan, from `since-last-tag.sh`. Keep the `included` commits,
judge each `unclassified` one (keep only what users will notice), and rewrite
each kept commit as one plain sentence about what the user will notice, not
the implementation. If `base_status` is `twin` or `unrelated`, say so in
Pipeline notes: history was rewritten under the old tag. The old tag stays
where it is. The What's New text must be **identical** in the tag annotation,
in the destination (when the target pushes notes) and in the changelog.

## 8. Pipelines

`/deploy <pipeline>` runs each `target:channel` step in order, each as a full
deploy with its own bump, tag and changelog.

- One plan covering every step, and one confirmation.
- Commits made by earlier steps don't count as "unpushed" for later steps.
- `--dirty` applies to every step.
- Stop at the first failure. Report which steps ran and which didn't.

## 9. Best-effort targets

When a target has no block and no `targets/<name>.md`:

- The plan says `Target <name>: no target file, best effort`.
- Work out Preflight / Ship / Verify from the repo (scripts, CI config,
  Dockerfiles, README) and the tool's own docs. Ask for missing values. Put the
  exact commands in the plan before confirming, and gate every irreversible
  command individually.
- The plumbing is unchanged: clean-tree check, bump (usually exit 3), tag, changelog.
- After the run, ask whether to save what worked:
  - a new `targets/<name>.md`, with the headings from §4, written to the plugin
    **source** (`~/Projects/plugin-marketplace/plugins/tal/skills/deploy/targets/`;
    ask where it is if that path doesn't exist). Never write into the installed
    plugin cache.
  - a `<name>:` block in this repo's `.config/deploy.yml`.

## 10. Rules

- Tags are immutable. Never move, delete or force-push one, and don't add a
  moving `latest` tag.
- No tag without a clean tree. `tag.sh` enforces this itself.
- `--dirty` is per-run only and never goes into `deploy.yml`.
- Policy keys are string enums, never booleans.
- Rollback is the target's **Rollback** section. The previous
  `builds/<target>/<channel>/*` tag is the index of what to go back to.
- Show the plan before any action, and put gates in front of irreversible steps.
