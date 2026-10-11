# Target: fly

Deploys an app to [Fly.io](https://fly.io) with `flyctl` (`fly`). Each channel
is a separate Fly app (e.g. `myapp-staging`, `myapp`).

- **Channels:** none by default. Define them in the block, in promotion order
  (e.g. `staging`, `prod`), each with its own `app`.
- **Gate names** for `confirm_before`: `deploy`, `rollback`.
- **Artifact:** the deployed image ref (`registry.fly.io/<app>:<label>`) plus
  the Fly release version (`v42`).
- **Default `version_scheme`:** `git-sha`. Nothing in the repo changes, so the
  bump step is a no-op (`release-commit.sh` exit 3) and the tag goes on `HEAD`.

## Required keys

| Key | Example | Notes |
|---|---|---|
| `app` (per channel) | `myapp-staging` | The Fly app name. It overrides `app` in `fly.toml` via `-a` |

Optional:

| Key | Default | Notes |
|---|---|---|
| `config` | `fly.toml` | Path to the Fly config. Can differ per channel |
| `build` | `remote` | `remote` (Fly builders, `--remote-only`) / `local` (`--local-only`, needs Docker) |
| `strategy` | from `fly.toml` | `rolling` / `immediate` / `canary` / `bluegreen` |
| `wait_timeout` | `5m` | Passed to `--wait-timeout` |
| `health_url` (per channel) | none | Polled in Verify. Expects a 2xx |
| `token_env` | `FLY_API_TOKEN` | Env var **name** for a deploy token. Without it, `fly` uses the logged-in session |

```yaml
fly:
  config: fly.toml
  channels:
    staging:
      app: myapp-staging
      health_url: https://myapp-staging.fly.dev/healthz
    prod:
      app: myapp
      health_url: https://myapp.fly.dev/healthz
```

## Setup

Used by config mode (SKILL.md §11) to fill the block. All read-only.

| Key | Where to find it |
|---|---|
| `config` | `ls fly.toml fly.*.toml`. Leave the key out when it's the default `fly.toml`. Per-channel files (`fly.staging.toml`) go on the channel |
| `app` (per channel) | `app = …` in each config, plus the `Name` of each entry in `fly apps list --json`. Suggest channel names from the app names (`myapp-staging` → `staging`, `myapp` → `prod`), and confirm the order, since it's the promotion order |
| `health_url` | A `[[http_service.checks]]` / `[[services.http_checks]]` `path` in the config, on `https://<app>.fly.dev`. Ask before adding it: it must be publicly reachable |
| `build` | `remote` (the default, so leave it out) unless the user wants local Docker builds |
| `token_env` | Leave out (logged-in session). For CI-style deploy tokens, ask for the env var **name** only |

## Doctor

Used by `/deploy doctor` (SKILL.md §12). Read-only.

1. **Tools and auth:** `fly version`. If `token_env` is set and that env var
   is empty → ❌. Otherwise `fly auth whoami` must pass.
2. **Config:** each `config` file exists and passes `fly config validate -c <config>`.
   If its `app = …` differs from the channel's `app`, that's fine, because `-a`
   wins. Say so anyway.
3. **Apps:** `fly status -a <app> --json` works for every channel. Report the
   machine count and the current image. An app with no machines → ⚠️.
4. **Promotion path:** `fly apps list --json` → each channel app's
   `Organization.Slug`. Apps in different orgs → ⚠️: promotion can't re-use
   the image, so every channel builds fresh.
5. **Builds:** `build: local` needs `docker info` to succeed.
6. **Health:** each `health_url` returns 2xx right now. Failing → ⚠️: it might
   be down, or the URL is wrong.
7. **History:** the newest `builds/fly/<channel>/*` tag per channel, and
   whether it matches the image label the app is running now.

## Version bump

None. Use `git-sha` (the default). The image is labelled with the version
(`--image-label <version>`), so the tag, the image and the Fly release all
name the same commit. Dirty runs work the same way and still change nothing.

## Preflight

1. **Auth:** `fly auth whoami`. If `token_env` names a set env var, export it
   as `FLY_API_TOKEN` first. If neither works, stop.
2. **Config:** `fly config validate -c <config>`.
3. **App exists:** `fly status -a <app> --json`. Put the current release
   version and image (`fly releases -a <app> --image --json`, newest entry) in
   the plan as "replacing vN (image …)".
4. **Migrations:** if `fly.toml` has `[deploy] release_command`, say so in the
   plan. It runs once per deploy, before the new machines start.
5. **Promotion check** (any channel after the first). If the previous
   channel's newest `builds/fly/<prev>/*` tag is newer than this channel's
   newest tag, ask: **Promote `<version>` from `<prev>`** (re-use its image)
   or **Build fresh**. Choosing Promote **declares a promotion run**
   (SKILL.md §5). The version and image come from the previous channel's tag
   annotation (`Artifact:` line).

## Ship

New build (gate `deploy`):

```bash
fly deploy -a <app> -c <config> --remote-only \
  --image-label <version> --wait-timeout <wait_timeout> [--strategy <strategy>]
```

Use `--local-only` in place of `--remote-only` when `build: local`. Then record the artifact:

```bash
fly releases -a <app> --image --json | jq '.[0]'
```

This gives the release version and image ref.

Promotion (gate `deploy`): redeploy the already-built image to this channel's app:

```bash
fly deploy -a <app> -c <config> --image <image ref from the previous channel's tag> \
  --wait-timeout <wait_timeout> [--strategy <strategy>]
```

This works when both apps are in the same Fly org, which shares the registry. If
the pull fails, stop and offer **Build fresh** instead.

## Verify

- `fly deploy` exited 0. It already waits for machines to pass health checks
  up to `--wait-timeout`.
- `fly status -a <app> --json`: every machine is `started` and none is still
  on the old image.
- `fly checks list -a <app>`: all checks are passing.
- `health_url`, if set: `curl -fsS -o /dev/null -w '%{http_code}' <url>` returns
  2xx. Retry every 10 s for up to 2 min before calling it failed.
- The newest `fly releases -a <app> --json` entry has status `complete`.

## Rollback

Redeploy the previous image (gate `rollback`, always confirm). The previous
`builds/fly/<channel>/*` tag's `Artifact:` line names it; `fly releases -a <app> --image` lists every release's image too.

```bash
fly deploy -a <app> -c <config> --image <previous image ref> --wait-timeout <wait_timeout>
```

This creates a **new** Fly release that runs the old image. A
`release_command` migration does **not** roll back. Undo schema changes
separately before rolling back code that can't handle them. Record the
rollback in a changelog entry. The bad deploy's tag stays.

## Notes / landmines

- `-a <app>` wins over `app = …` in `fly.toml`. Always pass it, so a staging
  config can never deploy to prod by accident.
- `--remote-only` needs no local Docker. A `--local-only` build pushes the image
  from your machine, which is slow on home uplinks.
- `fly deploy --detach` returns before health checks finish. Don't use it here:
  Verify depends on the wait.
- Secrets live in `fly secrets`, never in `deploy.yml` or `fly.toml`. Setting a
  secret triggers its own restart/release.
- Failing health checks during a rolling deploy leave a mix of old and new
  machines. Verify's "none on the old image" check catches it. Roll back or
  redeploy, and never leave the app split.
