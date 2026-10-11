# Add `fly` and `push` targets to the deploy skill

**Date:** 2026-10-11
**Scope:** `plugins/tal/skills/deploy/targets/{fly,push}.md`, deploy `SKILL.md` description, `plugins/tal/README.md`

## What changed

| Target | Ship | Channels | Promotion | Rollback |
|---|---|---|---|---|
| `fly` | `fly deploy -a <app> --remote-only --image-label <version>` | One Fly app per channel (`app` key) | Redeploy the previous channel's image (`--image`) | Redeploy the previous tag's image. `release_command` migrations don't roll back |
| `push` | `git push <remote> <commit>:refs/heads/<ref>` | One remote branch per channel (`ref` key) | Push the exact commit the previous channel got | Revert forward (preferred), or `--force-with-lease` with an explicit sha |

- Both default to `version_scheme: git-sha`, so there's no bump commit and the tag goes on `HEAD`.
- `push` **refuses dirty runs**: a push only ships committed code, so "dirty" would mean shipping something other than what the plan shows.
- `push` Verify modes: `watch: gh-run` (follow the Actions run for the sha), `url` (poll a health URL), or `none` (the changelog says the deploy wasn't verified).
- Policy keys are enums (`build: remote|local`, `push_mode: fast-forward|force-with-lease`, `watch: none|gh-run|url`).

## Verified

- flyctl flags (`--image-label`, `--image`, `--remote-only`, `--wait-timeout`, `--strategy`, `releases --image --json`, `status --json`) checked against the installed `fly v0.4.108` help output.

## Not verified

- Cross-app image reuse for Fly promotion assumes both apps share an org registry. The target says to fall back to a fresh build if the pull fails.
