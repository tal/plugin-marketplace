# Target: portainer

Redeploys a Portainer **repository (git) stack**: Portainer pulls the stack's
git ref, re-reads its compose file and runs `docker compose up` (building any
`build:` services) on the stack's endpoint. Each channel is one stack.

- **Channels:** none by default. Define them in the block, in promotion order
  (e.g. `staging`, `production`), each with its own `stack_id`.
- **Gate names** for `confirm_before`: `redeploy`, `rollback`.
- **Artifact:** the stack's `GitConfig.ConfigHash` after the redeploy (the
  commit Portainer deployed) plus the running container image id(s).
- **Default `version_scheme`:** `git-sha`. Nothing in the repo changes, so the
  bump step is a no-op (`release-commit.sh` exit 3) and the tag goes on `HEAD`.

## Required keys

| Key | Example | Notes |
|---|---|---|
| `stack_id` (per channel) | `"37"` | Portainer stack id. Quote it |
| `endpoint_id` | `"2"` | Portainer environment id the stack runs on. Can be set per channel |

Optional:

| Key | Default | Notes |
|---|---|---|
| `host_env` | `PORTAINER_HOST` | Env var **name** holding the base URL (`https://host:9443`) |
| `username_env` | `PORTAINER_USERNAME` | Env var **name** for JWT login |
| `password_env` | `PORTAINER_PASSWORD` | Env var **name** for JWT login |
| `env_file` | none | Path to a `.env` to source for those vars when they aren't already set (e.g. `$HOME/Projects/infra/.env`) |
| `tls` | `verify` | `verify` / `insecure` (`curl -k`, for Portainer's self-signed cert) |
| `pull_image` | `never` | `never` / `always`. `always` sends `pullImage: true`, which also upgrades every floating image tag in the stack |
| `health_url` (per channel) | none | Polled in Verify. Expects a 2xx |
| `watch_timeout` | `10m` | How long Verify waits for the new container and `health_url` |

```yaml
portainer:
  env_file: $HOME/Projects/infra/.env
  tls: insecure
  endpoint_id: "2"
  channels:
    production:
      stack_id: "37"
      health_url: https://app.example.com/healthz
```

## Setup

Used by config mode (SKILL.md §11) to fill the block. All read-only.

| Key | Where to find it |
|---|---|
| `host_env`, `username_env`, `password_env`, `env_file` | `grep -o '^PORTAINER[A-Z_]*' <file>` in the repo's `.env` and in sibling infra repos (never print values). Leave the `*_env` keys out when the names are the defaults |
| `tls` | `curl -fsS $PORTAINER_HOST/api/system/status`. An SSL error that `-k` fixes → `insecure` |
| `stack_id`, `endpoint_id` | `GET /api/stacks` → the entry whose `GitConfig.URL` matches `git remote get-url origin` (https form). Its `Id` and `EndpointId`. Several matches → one channel each, ask for names and order |
| `health_url` | The repo's README / changelog / reverse-proxy config for the public URL, plus a cheap JSON or health route. Ask before adding it |
| `pull_image` | Leave out (`never`) unless the stack uses floating tags the user wants upgraded on every deploy |

Auth for every API call (a login POST, which changes nothing):

```bash
JWT=$(curl $K -fsS -X POST "$HOST/api/auth" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg u "$USER" --arg p "$PASS" '{username:$u,password:$p}')" | jq -r .jwt)
```

`$K` is `-k` when `tls: insecure`. Never echo `$PASS`, `$JWT` or the stack's `Env` values.

## Doctor

Used by `/deploy doctor` (SKILL.md §12). Read-only (GETs plus the login POST).

1. **Credentials:** the three env vars are set (after sourcing `env_file` if
   given) → else ❌. Login returns a JWT → else ❌.
2. **Stack:** `GET /api/stacks/<stack_id>` works, `Type` is 2 (compose),
   `EndpointId` equals `endpoint_id`, and `GitConfig` is non-null (not a
   git stack → ❌, this target can't redeploy it).
3. **Ref:** `GitConfig.ReferenceName` is `refs/heads/<branch>` (the deploy
   branch). Anything else → ❌: a redeploy would ship a different branch.
   `GitConfig.URL` matches `origin` → else ⚠️.
4. **Auto-update:** `AutoUpdate` non-null (polling or webhook) → ⚠️: Portainer
   redeploys on its own, so pushes ship without `/deploy` and tags lag.
5. **Drift:** `GitConfig.ConfigHash` vs the newest `builds/portainer/<channel>/*`
   tag's commit and vs `origin/<branch>`. Report both. Behind `origin` is info.
6. **Pins:** report the stack `Env` **names** whose value looks like a 40-hex
   sha (name only) as info: a pinned dependency won't move on redeploy.
7. **Health:** `health_url` returns 2xx now → else ⚠️.

## Version bump

None. Use `git-sha` (the default). Dirty runs are **refused**: Portainer
deploys what's on the remote ref, so a dirty tree can never be what ships.
Say so and stop.

## Preflight

1. **Auth + stack:** as Doctor 1–3. Any ❌ stops the run.
2. **Remote ref:** Portainer clones `GitConfig.URL` at `GitConfig.ReferenceName`.
   After the plumbing push, `origin/<branch>` must equal the commit to deploy.
   Put "Portainer will deploy `<sha>`" in the plan. If the push step is
   skipped (`ask` → no) and `origin/<branch>` ≠ `HEAD`, stop.
3. **Current state:** put `ConfigHash` (short) and `UpdateDate` in the plan as
   "replacing `<sha>` deployed `<date>`". `ConfigHash` already equal to the
   commit → say "re-deploy of the same commit" (still allowed: it rebuilds).
4. **Pins:** list pinned `Env` names (Doctor 6) in the plan so a stale pin is
   seen before it ships.
5. **Container baseline:** record the current container ids and image ids:
   ```bash
   curl $K -fsS -H "Authorization: Bearer $JWT" -G \
     "$HOST/api/endpoints/<endpoint_id>/docker/containers/json" \
     --data-urlencode 'all=1' \
     --data-urlencode "filters={\"label\":[\"com.docker.compose.project=<stack Name>\"]}" \
     | jq '[.[] | {Id, Image: .ImageID, State, Names}]'
   ```
6. **Promotion check** (any channel after the first): if the previous
   channel's newest tag is newer than this channel's, ask **Promote `<sha>`**
   or **Deploy `HEAD`**. Portainer only deploys a branch head, so Promote
   needs the stacks on different refs; if both use the same ref, say so and
   offer Deploy `HEAD` only.

## Ship

Gate `redeploy`. Send the stack's **current** `Env` back unchanged (the body
replaces it), and keep stored git credentials:

```bash
STACK=$(curl $K -fsS -H "Authorization: Bearer $JWT" "$HOST/api/stacks/<stack_id>")
BODY=$(jq --arg pull "<pull_image>" '{
  env: .Env,
  prune: false,
  pullImage: ($pull == "always"),
  repositoryReferenceName: .GitConfig.ReferenceName,
  repositoryAuthentication: (.GitConfig.Authentication != null),
  stackName: .Name
}' <<<"$STACK")
curl $K -fsS -X PUT -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
  "$HOST/api/stacks/<stack_id>/git/redeploy?endpointId=<endpoint_id>" -d "$BODY" \
  | jq '{Id, Status, ConfigHash: .GitConfig.ConfigHash, UpdateDate}'
```

The call blocks until compose finishes (including the image build), so give it
a long timeout (10 min). A non-2xx response body has Portainer's `message` /
`details`; put them in the changelog.

## Verify

- The redeploy response's `GitConfig.ConfigHash` equals the deployed commit.
- Containers (Preflight 5 query): every container is `running`, and at least
  one has a different `ImageID` than the baseline for a stack with `build:`
  services. Same image ids → **FAILED: not rebuilt** (Portainer reused the
  old image).
- Not restart-looping: `GET .../docker/containers/<id>/json` →
  `.RestartCount` is 0 and `.State.Status` is `running`, checked twice 20 s apart.
- `health_url`, if set: 2xx, retried every 10 s up to `watch_timeout`.
- On failure, grab the last 50 log lines for the changelog:
  `GET .../docker/containers/<id>/logs?stdout=1&stderr=1&tail=50` (the stream
  has 8-byte frame headers; strip them with `LC_ALL=C sed 's/^.\{8\}//'`).

## Rollback

Gate `rollback`, always confirm. Portainer only deploys a branch head, so:

1. **Revert forward** (preferred): `git revert` the bad commits on the branch,
   push, and run a normal `/deploy`.
2. **Temporarily re-point the stack** at the previous tag: redeploy with
   `repositoryReferenceName: refs/tags/<previous builds/portainer/<channel>/* tag>`.
   This changes the stack's tracked ref. Set it back to `refs/heads/<branch>`
   on the next normal deploy, or Doctor 3 fails.

Record the rollback in a changelog entry. The bad deploy's tag stays.

## Notes / landmines

- Portainer 2.42 routes: create is `POST /api/stacks/create/standalone/repository`
  (`composeFile`, not `composeFilePathInRepository`); redeploy is
  `PUT /api/stacks/<id>/git/redeploy?endpointId=<id>`. The old
  `/api/stacks?method=repository` returns 405.
- The redeploy `env` **replaces** the stack's env. Omitting it wipes secrets
  like `GIT_TOKEN`. Always send `.Env` from a fresh GET.
- `pullImage: true` upgrades every floating tag in the stack, not just yours.
- Build args that pin a dependency (a sha in stack `Env`) don't move on
  redeploy. Preflight lists them; change them in Portainer, not here.
- Whether Portainer rebuilds an existing `build:` image on redeploy depends on
  the Portainer/compose version. Verify's image-id check is what catches a
  silent no-rebuild; don't drop it.
- Log streams and `docker/*` proxy routes go through
  `/api/endpoints/<endpoint_id>/docker/…`, not the Docker socket.
