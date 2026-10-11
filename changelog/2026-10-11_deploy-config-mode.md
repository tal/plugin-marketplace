# Deploy: `/deploy config` edits `deploy.yml`

The `deploy` skill can now set up and edit a repo's `.config/deploy.yml` itself,
instead of the user hand-writing it. Chosen over a separate skill, so there's one
entry point and the config rules live next to the plumbing that reads them.

## Added

- **`/deploy config [init | add <target> [channel…] | <plain words>]`** (SKILL.md §11,
  `references/config-mode.md`):
  - **Flow:** show the config → work out the change → show it as a diff and confirm →
    edit in place, keeping comments → validate → offer a commit of only that file.
  - **Never deploys:** config mode doesn't tag or push.
  - **Reserved name:** `config` can't be used as a target or a pipeline name.
- **A `## Setup` section in every target file**, saying where each key can be found
  without changing anything:
  - **testflight:** `xcodebuild -list -json` and `-showBuildSettings -json`, the ASC
    `/v1/apps?filter[bundleId]` and `/v1/betaGroups` endpoints, and the key directory.
  - **fly:** `fly.toml` and `fly apps list --json`.
  - **push:** `git remote`, and the deploy workflows' `on: push: branches`.
  - **Deploy runs use it too:** when a run finds a required key missing (§4), it
    looks the value up first, then asks.
- **`scripts/check-config.sh [--file] [--format kv|json]`:** parses YAML with
  `ruby` (Psych), falling back to `python3` + PyYAML, then validates it with jq. It
  checks for:
  - typo'd top-level keys and the `version_scheme` / `unpushed_policy` enums
  - booleans anywhere, `dirty` keys, and `config` used as a name
  - the shape of `channels` and duplicate channels
  - pipeline steps that name a missing target or channel
  - secret-looking keys and inline `-----BEGIN` key material

  §2 now loads the config with it, so these errors stop a deploy before it plans.
  Exit codes: 0 for ok or a missing file, 1 for an invalid file, 2 when no YAML
  parser is available, 64 for a usage error.

## Learned

- **Ruby's Psych rejects unquoted `target:channel` items in a flow list.**
  `release: [fly:staging]` fails, but PyYAML accepts it. The §2 example now quotes
  the steps, and config mode writes block lists or quoted items.
- **Duplicate YAML keys are silently last-wins in both parsers**, so the validator
  can't catch them. Config mode checks for an existing key before adding one.
- `xcodebuild -list -json` includes the schemes of SPM packages (weather-range lists
  22), so Setup suggests the scheme named after the project, or the app target's.
- The JSON output of `fly apps list` uses `Name`, with a capital N.
- Commands containing a pipe can't go inside markdown tables: escaping the pipe as
  `\|` would get copied into the shell. Those commands sit below the tables instead.

## Verified

- `check-config.sh` was run on weather-range's real file (ok) and on fixtures for
  every error. Both the ruby and python3 parsers were tested, under `/bin/bash` 3.2.
- Config mode itself hasn't been run end to end on a repo yet.
