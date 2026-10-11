# Target: push

Deploys by `git push`. A push to some remote branch makes something else do the
real deploy: a CI workflow, a PaaS git remote (Dokku, Heroku-style), or a
host that builds on push. This target pushes the right commit to the right ref,
then watches the result.

- **Channels:** none by default. Define them in the block (e.g. `staging`,
  `production`), each with its own `ref`.
- **Gate names** for `confirm_before`: `push-deploy`, `force-push`, `rollback`.
- **Artifact:** the pushed commit sha, plus the CI run URL when `watch: gh-run`.
- **Default `version_scheme`:** `git-sha`. The bump is a no-op
  (`release-commit.sh` exit 3) and the tag goes on `HEAD`.

## Required keys

| Key | Example | Notes |
|---|---|---|
| `remote` | `origin` / `dokku` | Git remote to push to. It can also be set per channel |
| `ref` (per channel) | `production` | Branch on that remote whose update triggers the deploy |

Optional:

| Key | Default | Notes |
|---|---|---|
| `push_mode` | `fast-forward` | `fast-forward` (refuse anything else) / `force-with-lease` (gated by `force-push`) |
| `watch` | `none` | `none` / `gh-run` (follow the GitHub Actions run for the pushed sha) / `url` (poll `health_url`) |
| `workflow` | any | With `watch: gh-run`: workflow file or name to follow, e.g. `deploy.yml` |
| `health_url` (per channel) | none | With `watch: url`. Expects a 2xx |
| `watch_timeout` | `15m` | How long Verify waits before calling it failed |

```yaml
push:
  remote: origin
  watch: gh-run
  workflow: deploy.yml
  channels:
    staging:    { ref: staging }
    production: { ref: production }
```

## Version bump

None. Use `git-sha` (the default). Dirty runs are **refused** by this target:
a push only ever ships committed code, so a "dirty deploy" here would ship
something other than what the plan shows. Say so and stop.

## Preflight

1. **Remote state:** `git fetch <remote> <ref>`, then
   `git rev-parse <remote>/<ref>` (or `git ls-remote <remote> refs/heads/<ref>`
   for remotes that aren't fetched). Missing ref: say "creates `<ref>`" in the plan.
2. **Fast-forward check:**
   `git merge-base --is-ancestor <remote>/<ref> <commit>`. If it isn't an
   ancestor and `push_mode` is `fast-forward`, stop and show the diverging
   commits (`git log --oneline <commit>..<remote>/<ref>`). Under
   `force-with-lease`, put **FORCE** in the plan and list the commits that
   will disappear from `<ref>`.
3. **What changes:** `git log --oneline <remote>/<ref>..<commit>`. Put the
   count in the plan.
4. **Watcher ready:** for `gh-run`, `gh auth status` must pass and `workflow`
   must exist (`gh workflow view <workflow>`).
5. **Same branch as the plumbing push.** If `<remote>/<ref>` is the branch's
   own upstream (e.g. `origin/main` with `ref: main`), the plumbing's push
   step *is* the deploy. Ship pushes nothing extra; it only watches.
6. **Promotion check** (any channel after the first). If the previous
   channel's newest `builds/push/<prev>/*` tag is newer than this channel's,
   ask: **Promote `<sha>` from `<prev>`** (push the exact commit that channel
   got) or **Push `HEAD`**. Promote **declares a promotion run** (SKILL.md §5).

## Ship

Gate `push-deploy`. Add gate `force-push` when the push isn't a fast-forward:

```bash
# fast-forward
git push <remote> <commit>:refs/heads/<ref>
# force-with-lease: only replaces <ref> if it is still the sha Preflight saw
git push --force-with-lease=refs/heads/<ref>:<preflight sha> <remote> <commit>:refs/heads/<ref>
```

`<commit>` is `HEAD` (or the bump commit) for a normal run, and the promoted
commit for a promotion run. Never use a plain `--force`.

## Verify

- `watch: gh-run`:
  ```bash
  RUN=$(gh run list --commit <commit> --workflow <workflow> --limit 1 --json databaseId -q '.[0].databaseId')
  gh run watch "$RUN" --exit-status
  ```
  The run can take a few seconds to appear, so retry `gh run list` every 10 s
  for up to 2 min. A non-zero exit is a failed deploy; link the run URL
  (`gh run view "$RUN" --json url -q .url`) in the changelog.
- `watch: url`: `curl -fsS -o /dev/null -w '%{http_code}' <health_url>` returns
  2xx. Retry every 15 s until `watch_timeout`.
- `watch: none`: the push succeeding is all this target can check. Say in the
  changelog that the deploy itself wasn't verified.
- Always: `git ls-remote <remote> refs/heads/<ref>` now equals `<commit>`.

## Rollback

The previous `builds/push/<channel>/*` tag names the last good commit.
Gate `rollback`, always confirm. Prefer the first option:

1. **Revert forward** (safe when others push to `<ref>`): `git revert` the bad
   commits on the branch, then run a normal deploy. It's a fast-forward, and
   history keeps the record.
2. **Re-point the ref** (deploy-only branches nobody else writes to):
   ```bash
   git push --force-with-lease=refs/heads/<ref>:<current sha> <remote> <previous tag's commit>:refs/heads/<ref>
   ```

## Notes / landmines

- `--force-with-lease` with an explicit expected sha only protects you if the
  sha is the one Preflight saw. A bare `--force-with-lease` trusts whatever
  your last fetch saw, which may be stale.
- Pushing a tag doesn't trigger branch-push workflows, and pushing a branch
  doesn't trigger tag workflows. Make sure `ref` is the trigger the CI
  actually listens to (`on: push: branches: [...]`).
- `gh run list --commit` matches the head sha of the run. Workflows that run on
  a merge or squash commit won't match the pushed sha.
- PaaS git remotes (Dokku, Heroku) often stream the build log in the `git push`
  output and fail the push when the build fails. There, Ship's exit code is
  the deploy result, and `watch: none` is acceptable.
