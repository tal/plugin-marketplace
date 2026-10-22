# Target: lambda

Deploys an AWS Lambda function by running the repo's own deploy script (e.g.
`ruby scripts/publish.rb`), which builds the package and calls
`aws lambda update-function-code`. This target doesn't build anything itself.
It runs the script, then checks that Lambda took the new code.

- **Channels:** none by default. One function per channel. Define channels in
  the block (e.g. `production`), each with its own `function` if they differ.
- **Gate names** for `confirm_before`: `upload`, `rollback`.
- **Artifact:** the function's new `CodeSha256`, plus `Version` when the
  script publishes one.
- **Default `version_scheme`:** `git-sha`. The bump is a no-op
  (`release-commit.sh` exit 3) and the tag goes on `HEAD`.

## Required keys

| Key | Example | Notes |
|---|---|---|
| `function` | `spotify-playlist-dev` | Lambda function name. It can also be set per channel |
| `region` | `us-east-1` | AWS region of the function |
| `ship_command` | `ruby scripts/publish.rb` | Run from the repo root. Must exit non-zero on failure |

Optional:

| Key | Default | Notes |
|---|---|---|
| `health_url` (per channel) | none | Function URL or custom domain. Verify expects a 2xx |
| `aws_profile_env` | none | **Name** of an env var holding the AWS profile to use. Never the credentials |
| `watch_timeout` | `2m` | How long Verify retries `health_url` |

```yaml
lambda:
  function: my-fn
  region: us-east-1
  ship_command: ruby scripts/publish.rb
  version_scheme: git-sha
  channels:
    production: { health_url: https://example.com/ }
```

## Setup

Used by config mode (SKILL.md §11) to fill the block. All read-only.

| Key | Where to find it |
|---|---|
| `function`, `region` | Constants in the deploy script (`grep -nE 'FUNCTION|REGION|function-name|--region' scripts/*`), `serverless.yml`, `template.yaml`, or `aws lambda list-functions --region <r>` |
| `ship_command` | The deploy script named in README / AGENTS.md / CLAUDE.md / `package.json` scripts |
| `health_url` | A custom domain in the docs, or `aws lambda get-function-url-config --function-name <f> --region <r>` |

## Doctor

Used by `/deploy doctor` (SKILL.md §12). Read-only.

1. **AWS CLI and creds:** `aws --version`; `aws sts get-caller-identity`. A
   failure → ❌.
2. **Function:** `aws lambda get-function-configuration --function-name <f> --region <r>`
   succeeds → ✅, and report `Runtime`, `Architectures`, `LastUpdateStatus` and
   `LastModified`. `LastUpdateStatus` other than `Successful` → ⚠️.
3. **Ship command:** the script file in `ship_command` exists, and so does its
   interpreter (`ruby`, `bun`, …).
4. **Health:** `health_url` returns 2xx now. A failure → ⚠️.
5. **History:** the newest `builds/lambda/<channel>/*` tag per channel.

## Version bump

None. Use `git-sha` (the default). Dirty runs are allowed: deploy scripts
usually package the working tree, so a dirty deploy ships exactly what's on
disk. SKILL.md's dirty-run rules (untagged, changelog only) apply.

## Preflight

1. `aws sts get-caller-identity` passes. If not, stop and say to refresh creds.
2. Record the current state for rollback and for Verify:
   `aws lambda get-function-configuration --function-name <f> --region <r> --query '{sha:CodeSha256,modified:LastModified,status:LastUpdateStatus}'`.
   Put the current `CodeSha256` in the plan.
3. `LastUpdateStatus` is `InProgress` → stop. Another deploy is running.
4. `health_url` responds now (info only). If it is already down, say so in the plan.

## Ship

Gate `upload`. From the repo root:

```bash
<ship_command>
```

A non-zero exit is a failed deploy. Keep the last ~40 lines of output for the
changelog.

## Verify

- `aws lambda wait function-updated-v2 --function-name <f> --region <r>`.
- `get-function-configuration` again: `LastUpdateStatus` is `Successful`, and
  `CodeSha256` differs from Preflight's. An unchanged sha is only OK when the
  package really is identical. Note it in the changelog, but don't fail.
- `health_url`: `curl -fsS -o /dev/null -w '%{http_code}' <health_url>`
  returns 2xx. Retry every 10 s until `watch_timeout`.
- Artifact = the new `CodeSha256`.

## Rollback

Gate `rollback`, always confirm. The previous `builds/lambda/<channel>/*` tag
names the last good commit.

1. **Redeploy the old commit:** `git worktree add <tmp> <previous tag>`, run
   `ship_command` there, then remove the worktree.
2. If the script publishes versions or aliases, re-point the alias instead:
   `aws lambda update-alias --function-name <f> --name <alias> --function-version <prev>`.

## Notes / landmines

- A deploy script can update the function's **configuration** (memory, layers,
  runtime) as well as its code. Rolling back the code doesn't undo a
  configuration change unless the old script also sets it.
- `update-function-code` returns before the update finishes. Always `wait`
  before trusting `CodeSha256`.
- Lambdas with reserved concurrency 1 serve health checks serially. A slow
  `health_url` can time out while a scheduled run is in progress, so retry
  before failing.
