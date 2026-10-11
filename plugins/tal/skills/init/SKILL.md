---
name: init
description: Detects which tal skills fit the current project (deploy, App Store Connect, GitHub PR replies) and writes a managed block into its AGENTS.md telling agents which command to suggest for which request. Re-run to refresh. Invoke explicitly via /tal:init (`$init` in Codex).
argument-hint: "[remove]"
disable-model-invocation: true
---

# Init: point a project at its tal commands

Most tal skills are explicit-only, so no agent knows they exist unless someone
says so. This writes that "someone says so" into the project's `AGENTS.md`:
a short, managed block that maps requests ("ship a TestFlight build") to the
command to suggest (`/deploy testflight external`). It costs context only in
projects where the skills apply.

`$S` below means `${CLAUDE_PLUGIN_ROOT}/skills/init/scripts`.

```
/tal:init          detect, propose the block, confirm, write
/tal:init remove   delete the block (and nothing else)
```

Never invokes another skill, deploys, or edits anything outside the files in
step 5.

## 1. Detect

```bash
"$S/detect.sh"
```

It prints `key=value` signals (header of `detect.sh` lists them all). Stop and
ask before going on when:

- `git=none`: say this isn't a repo and confirm `root` is the project. A
  folder of projects (many `xcode=` hits in different subfolders) is never
  the target; tell the user to run it inside one project.
- `init_block=broken`: only one marker exists. Show where, and ask whether to
  rebuild the block from that marker or stop.
- `deploy_config=invalid`: say `/deploy config` can fix it. Deploy then
  applies in its "not configured" form, whatever the other signals.

## 2. Match the catalog

A skill applies when its signal is present. Only explicit-only, project-scoped
skills are listed; auto-triggering skills (`get-pr-feedback`,
`git-partial-commit`, …) and project-agnostic ones (`handoff`, `eli5`, the
commit commands) never get a pointer.

| Skill | Applies when | Rows to write |
|---|---|---|
| `deploy` (configured) | `deploy_config=ok` with ≥ 1 `deploy_target` | One row per target: its requests → `/deploy <target> <channel>` for each channel. One row per pipeline → `/deploy <pipeline>`. Plus a doctor row and a config row |
| `deploy` (not configured) | no config, and any of `xcode`, `fly_toml`, `deploy_workflow`, `paas_remote` | One row: setting up deploys / releasing → `/deploy config init` |
| `appstore-connect` | any `xcode` | One row: App Store Connect work → `/appstore-connect` |
| `pr-thread-reply` + `/tal:pr:address-feedback` | any `github_remote` | Two rows: replying to an inline review comment, and working through a PR's review feedback |

Ask which to include: one AskUserQuestion, `multiSelect: true`, an option per
applicable skill with its signal as the description (e.g. "deploy:
`.config/deploy.yml` has testflight internal, external"). If nothing applies,
say so and stop (offer `remove` when `init_block=present`).

When a `project_skill` already points at the same command (e.g. a
`.claude/skills/testflight/SKILL.md` that says `/deploy`), mention it. Keep
both; don't edit it.

## 3. Write the rows

Each row is *when the user asks to …* → *suggest*. Phrase the left column as
the requests people actually make in this project, using its names: the real
channel names, the app's name, the Fly app names. Keep it to what tells an
agent "this one", not a list of synonyms.

| Skill | Request phrasing to start from | Suggest |
|---|---|---|
| deploy, testflight target | ship / release / push a build to TestFlight `<channel>`, promote internal to external | `/deploy testflight <channel>` |
| deploy, fly target | deploy / release / promote to `<channel>`, roll back `<channel>` | `/deploy fly <channel>` |
| deploy, push target | deploy / release `<channel>` | `/deploy push <channel>` |
| deploy, other targets | deploy / release `<target>` `<channel>` | `/deploy <target> <channel>` |
| deploy, pipeline | ship everything / run the `<name>` release | `/deploy <name>` |
| deploy doctor | will a deploy work, are the certs / keys / beta groups OK | `/deploy doctor` |
| deploy config | change deploy settings, add a channel or target | `/deploy config` |
| deploy, not configured | set up deploys, release this | `/deploy config init`, then `/deploy <target> <channel>` |
| appstore-connect | App Store Connect: build or review status, beta groups, testers, altool, ASC API / JWT, signing identities | `/appstore-connect` |
| pr-thread-reply | reply to an inline PR review comment | `/tal:pr-thread-reply <comment-url> <message>` |
| address-feedback | work through / address a PR's review feedback | `/tal:pr:address-feedback [pr]` |

Codex forms go in brackets after the Claude form: `$deploy`,
`$appstore-connect`, `$pr-thread-reply`. `/tal:pr:address-feedback` is a
Claude Code command with no Codex form; say "(Claude Code only)".

When both the testflight deploy row and appstore-connect apply, the
appstore-connect row says uploads go through `/deploy`, not altool by hand.

No `|` inside a table cell: write each command separately.

## 4. Build the block

Exactly this shape, markers included. Re-runs replace everything between the
markers.

```markdown
<!-- tal:init:start — written by /tal:init; re-run it to update. Edits inside are replaced. -->
## tal plugin commands

These come from the `tal` plugin and are explicit-only: an agent can't start
them itself. When a request matches a row, suggest the command (Codex form in
brackets) before doing the work by hand. Do it by hand only if the user says to.

| When the user asks to… | Suggest |
|---|---|
| … | … |
<!-- tal:init:end -->
```

## 5. Show, confirm, write

Files:

- **`AGENTS.md`:** `init_block=present` → replace from the start marker line
  through the end marker line. `missing` → append the block at the end, after
  one blank line. `agents_md=missing` → create the file with a `# <project>`
  heading (the repo folder name), one blank line, then the block.
- **`CLAUDE.md`** (so Claude Code reads AGENTS.md):
  - `imports-agents` → leave it alone.
  - `present` → add `@AGENTS.md` as the first line, followed by a blank line.
  - `missing` → create it containing only `@AGENTS.md`.

Steps:

0. Before writing, note whether `git diff --quiet -- AGENTS.md CLAUDE.md`
   passes. Step 6 needs to know if those files already had uncommitted
   changes.
1. Show the change: the whole block for a new one, `-`/`+` lines against the
   old block on a re-run, and the CLAUDE.md line if it changes. If the new
   block equals the old one, say "already up to date" and stop.
2. Ask: **Write this?** → Write / Change something / Cancel.
3. Edit in place. Never touch anything outside the markers in `AGENTS.md`, or
   anything but that one line in `CLAUDE.md`.
4. Re-run `"$S/detect.sh"`: `init_block=present`, and `claude_md=imports-agents`.

`/tal:init remove`: show the block, confirm, delete the marker lines and
everything between them (plus one adjacent blank line). Leave `CLAUDE.md`
alone, and leave a now-empty `AGENTS.md` in place unless the user says to
delete it.

## 6. Commit

Ask: **Commit** / **Leave uncommitted**.

- If step 5.0 found uncommitted changes in either file, say so: the commit
  would take them along. Make Leave uncommitted the first option.
- Commit only those files:
  `git add AGENTS.md CLAUDE.md && git commit -m 'docs(agents): Point at tal commands' -- AGENTS.md CLAUDE.md`
  (only the files that exist). Add any commit attribution trailer your
  harness requires.
- Don't push.
