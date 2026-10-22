# Target: script

Deploys by running a deploy command the repo already has (e.g.
`scripts/deploy.sh` that tests, rsyncs to a host and restarts containers).
The script owns *how* it ships. This target only runs it from the right
commit, records what happened, and checks the result afterwards.

- **Channels:** none by default. Define them in the block (e.g. `staging`,
  `production`). A channel can override `command` and add `env`.
- **Gate names** for `confirm_before`: `run`, `rollback`.
- **Artifact:** the commit sha the command ran from, plus any lines the
  script prints that name what it built (image ids, digests).
- **Default `version_scheme`:** `git-sha`. The bump is a no-op
  (`release-commit.sh` exit 3) and the tag goes on `HEAD`.

## Required keys

| Key | Example | Notes |
|---|---|---|
| `command` | `scripts/deploy.sh` | Run from the repo root. It can also be set per channel |

Optional:

| Key | Default | Notes |
|---|---|---|
| `env` | none | Map of extra **non-secret** env vars for the command (e.g. `SORTOF_DEPLOY_HOST: bee1`). It can be set per channel. Secrets stay in the environment or the script's own `.env` |
| `command_timeout` | `15m` | How long Ship waits for the command |
| `health_url` (per channel) | none | Polled in Verify. Expects a 2xx |
| `watch_timeout` | `5m` | How long Verify retries `health_url` |

The command also gets `DEPLOY_TARGET`, `DEPLOY_CHANNEL`, `DEPLOY_VERSION` and
`DEPLOY_COMMIT` in its environment, so a script can branch on them if it wants.

```yaml
script:
  command: scripts/deploy.sh
  channels:
    production:
      health_url: https://app.example.com/health
```

## Setup

Used by config mode (SKILL.md §11) to fill the block. All read-only.

| Key | Where to find it |
|---|---|
| `command` | `ls scripts/ bin/` for `deploy*`, `package.json` `scripts.deploy`, `Makefile` `deploy:` target, the README's deploy section. Several candidates → ask |
| `env` | Env vars the script reads with a default (`${FOO:-bar}`). Only add ones the user wants to pin, and never secret-looking ones |
| `health_url` | The README / changelog / reverse-proxy config for the public URL, plus a cheap health route. Probe it once (`curl -s -o /dev/null -w '%{http_code}'`); it must answer 2xx **without** a login. Ask before adding it |

## Doctor

Used by `/deploy doctor` (SKILL.md §12). Read-only. Never runs the command.

1. **Command:** the file exists and is executable (or the `package.json` /
   `Makefile` entry exists) → else ❌.
2. **Syntax:** for a shell script, `bash -n <command>` → else ❌.
3. **Env:** no `env` key looks secret (`token|secret|password|key`) → else ❌.
4. **Health:** `health_url` returns 2xx now → else ⚠️.

## Version bump

None. Use `git-sha` (the default).

Dirty runs are allowed but stay **untagged** (SKILL.md §6): the command runs
against the working tree, so the dirty files ship too. Say so in the plan.

## Preflight

1. **Command exists** (Doctor 1–2). Any ❌ stops the run.
2. **Plan line:** the exact command line with its `env` and `DEPLOY_*` values,
   e.g. `DEPLOY_CHANNEL=production scripts/deploy.sh`.
3. **What it does:** read the script's header comment and put a one-line
   summary of it in the plan, so the confirmation is informed.
4. **Health baseline:** `health_url`'s current status, if set.

## Ship

Gate `run`. From the repo root, with a `command_timeout` timeout (run it in the
background and wait on it if it's longer than the tool's foreground limit):

```bash
DEPLOY_TARGET=<t> DEPLOY_CHANNEL=<c> DEPLOY_VERSION=<v> DEPLOY_COMMIT=$(git rev-parse HEAD) \
  <env pairs> <command> 2>&1 | tee "$TMPDIR/deploy-<t>-<c>.log"
```

Use `${PIPESTATUS[0]}` for the exit code, not `tee`'s. A non-zero exit is a
failed Ship: put the last 30 lines of the log in the changelog.

## Verify

- The command exited 0.
- Scan the log for lines starting with `WARNING`, `REFUSING` or `ERROR`. A
  zero exit with warnings is **shipped**, but every warning line goes into the
  changelog's Pipeline notes, verbatim. They often mean "part of this didn't
  go live yet" (e.g. a busy worker that wasn't restarted).
- `health_url`, if set: 2xx, retried every 10 s up to `watch_timeout`.

## Rollback

Gate `rollback`, always confirm.

1. **Revert forward** (preferred): `git revert` the bad commits, then a
   normal `/deploy`.
2. **Re-run an older tag:** `git worktree add <tmp> <previous builds/<t>/<c>/* tag>`,
   run the command from there, then `git worktree remove <tmp>`. The next
   normal deploy ships `HEAD` again. Only safe for scripts that ship their own
   checkout (rsync, build-from-cwd), not ones that deploy a remote ref.

Record the rollback in a changelog entry. The bad deploy's tag stays.

## Notes / landmines

- The script is a black box: anything it refuses or skips only shows up in
  its output, which is why Verify reads the log instead of trusting the exit code.
- Scripts that rsync the working tree ship untracked files too, unless
  they exclude them. A clean tree is what keeps a tag honest.
- Don't pass secrets through `env`. `check-config.sh` rejects secret-looking
  key names, but a secret under an innocent name would still land in git.
