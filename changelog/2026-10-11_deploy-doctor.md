# Deploy: `/deploy doctor` readiness check

`/deploy doctor [target[:channel]]` checks whether every configured target could
deploy right now, without deploying. It runs only GET requests and doesn't build,
tag, commit, edit or create anything.

## Added

- **SKILL.md §12:**
  - **Config:** `check-config.sh` checks the file.
  - **Repo:** tools, the `branch` and its upstream, the tree state (reported as
    info), and `changelog_dir`.
  - **Keys:** each target's keys after merging block and channel values. A
    missing required key or a bad enum is ❌; an unknown key is ⚠️.
  - **The target's own checks:** its `## Doctor` section.
  - **Report:** a ✅ / ⚠️ / ❌ table, then a verdict per `target:channel`:
    `ready`, `ready-with-warnings` or `blocked`.
  - **Fixes:** key fixes go through `/deploy config`. Anything outside the repo is
    explained but never done.
  - **Reserved name:** `doctor`, now rejected as a target or pipeline name by
    `check-config.sh`.
- **A `## Doctor` section in every target file:**
  - **testflight:** project, scheme, bundle id and team match. `VERSIONING_SYSTEM`
    and the export options are checked. The API key file mode is checked, and the
    key must get a 200 with a matching `bundleId`. Each beta group's id and
    internal/external kind must match. Then distribution certificates, provisioning
    profiles (manual signing only), the release gate, and tags against the highest
    build on ASC.
  - **fly:** auth and `token_env`, `fly config validate`, each app exists, whether
    the apps share an org (needed for promotion), Docker for local builds,
    `health_url`, and tags against the running image.
  - **push:** the remote and each ref, the fast-forward state, `gh` auth, and
    whether the workflow triggers on `ref`. Also the newest CI run, and whether
    the ref still points at the last tag.
- **`appstore-connect/scripts/signing-identities.sh`:** lists this Mac's code-signing
  identities for a team and kind, read-only.
  - `status` is one of `valid`, `expiring`, `expired`, `revoked` or `untrusted`.
  - With `--asc-certs`, it also matches each cert against a saved `/v1/certificates`
    response by serial number, so a cert revoked on Apple's side shows as missing.
  - It prints a `usable` count and the `best` identity.
  - macOS only, bash 3.2-safe.

## Corrected

- **TestFlight Preflight step 4 was wrong.** It said that with no local Apple
  Distribution identity, `-allowProvisioningUpdates` would mint a new distribution
  certificate. This Mac has no distribution identity at all (only Apple
  Development), yet weather-range ships. Its release logs say it uses
  **cloud-managed distribution signing** through the API key. Preflight and Doctor
  now treat "no local identity + automatic signing" as cloud-managed signing (✅,
  needs an Admin-role key), and only manual signing requires a local identity.
- **The skill description had grown to 1,393 chars**, past the Agent Skills
  1,024-char limit, after the config and doctor triggers were added. It's now
  968 chars.

## Learned

- `security find-identity -p codesigning` without `-v` prints every identity twice,
  once under "Matching identities" (with the CSSMERR reason) and again under
  "Valid identities only". Expired identities carry `CSSMERR_TP_CERT_EXPIRED`.
- The `(XXXXXXXXXX)` in an identity's name is the person's id, not the team. The
  team is only in the certificate subject's OU.
- Cloud-managed certificates show up in neither `/v1/certificates` nor the keychain.
  The account lists one `IOS_DISTRIBUTION` cert (expires 2027-02-13) whose private
  key isn't on this Mac.

## Verified

- Every TestFlight doctor check ran read-only against weather-range:
  - export `method` is `app-store-connect` and `teamID` matches
  - the key file mode is `600`
  - `Automatic` signing with `apple-generic` versioning
  - the app GET returned a matching `bundleId`
  - all 3 beta groups exist, with the kinds `deploy.yml` gives them
  - the release gate is executable
  - no usable local distribution identity, so cloud-managed signing

  The verdict would be `ready`.
- `signing-identities.sh` was run on this Mac's real keychain and with ASC fixture
  files.
- The fly and push doctor checks haven't been run against a real app yet.

## Follow-up: explicit-only

- **`deploy` only runs when invoked explicitly.** It's set to
  `disable-model-invocation: true` for Claude, and
  `agents/openai.yaml` sets `policy.allow_implicit_invocation: false` for Codex.
  Its 968-char trigger description stayed in every session's context. It's now a
  short description meant for people reading the `/` menu.
- **`appstore-connect` points at `/deploy` in its body** for TestFlight uploads from
  repos with `deploy.yml`. That steer used to live in deploy's description, which
  the model no longer sees.
- **New `plugins/tal/AGENTS.md`** (with a `CLAUDE.md` pointer): new tal skills are
  explicit-only in both runtimes unless the user says otherwise. It lists which
  skills auto-trigger on purpose today. The root `AGENTS.md` points at
  per-plugin agent notes.
- **`appstore-connect` is explicit-only too** (`disable-model-invocation: true` plus
  `agents/openai.yaml`). It's Apple-only, so its ~700-char description was
  loading into every non-Apple session. Its description is now a short summary
  for the `/` menu. The deploy TestFlight target still reads its scripts and
  references by path, so `/deploy` is unaffected. The tal `AGENTS.md` now
  recommends a project-level pointer skill in each Apple repo for anyone who
  wants auto-help there.
