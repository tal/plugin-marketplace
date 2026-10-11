# Add `deploy` skill to the `tal` plugin

**Date:** 2026-10-11
**Scope:** `plugins/tal/skills/deploy/` (new), `plugins/tal/README.md`, root `README.md`, both `tal` manifests, `TEMP_deploy-skill-design.md`

## What changed

- New `deploy` skill: generic release plumbing, invoked as `/deploy [target | pipeline | target:channel] [channel] [--dirty]` (`/tal:deploy` always works; `$deploy` in Codex).
  - Reads `<project>/.config/deploy.yml`. Every top-level key that isn't a generic key is a target block, with its own `channels`.
  - Order: resolved plan and a yes → clean-tree / branch / unpushed check → isolated version-bump commit → preflight, ship and verify from `targets/<target>.md` → annotated tag `builds/<target>/<channel>/<version>` → release changelog → push.
- `targets/testflight.md`: the generic parts of weather-range's `testflight` skill, lifted out of it. App-specific values (App ID, key ids, group ids, release gate) belong in weather-range's `deploy.yml`, not here. Generic `altool` / REST mechanics stay in `tal:appstore-connect`.
- Five scripts in `skills/deploy/scripts/`: `verify-clean-tree.sh`, `build-id.sh`, `release-commit.sh`, `since-last-tag.sh`, `tag.sh`.
- READMEs and manifest descriptions now mention deploys.

## Decisions made with the user (2026-10-11)

| Topic | Decision |
|---|---|
| Config path | `.config/deploy.yml`, not `.claude/deploy.yml`, so Codex reads it too |
| Target routing | Positional argument. No target → ask (AskUserQuestion), unless exactly one target block and no pipelines exist |
| Which targets exist | Inferred from the blocks in `deploy.yml`. This **reverses** the brief's "explicit `target:` key, never infer" rule |
| Unknown target | Best-effort run, then offer to save a target file + `deploy.yml` block |
| Channels | Per target block. No channel → ask, unless there's only one |
| Dirty deploys | `--dirty` or plain words. No bump commit, no tag, changelog marked UNTAGGED |
| Ship fails after the bump commit | Keep the commit, no tag, changelog marked FAILED |
| `unpushed_policy` default | `push` |
| Multi-target | Named `pipelines:`. Stop at the first failure |
| Scripts vs model | The bump commit, build id and since-last-tag range are scripts. The changelog filename stays with the model |

## Corrections to the design brief

- **`beta_review_submit: new-train-only` didn't match reality.** Weather-range's 2026-10-06 release log shows the external state stuck at `READY_FOR_BETA_SUBMISSION` on an already-approved train until a submission POST. The values are now `when-needed` / `always` / `never`, and `when-needed` checks the build's actual beta state.
- **The ASC polling recipe in `tal:appstore-connect` is wrong for fresh builds.** It polls by `filter[version]`, which returns nothing while a build is `PROCESSING`. `targets/testflight.md` polls `/v1/builds/<delivery UUID>` instead. `appstore-connect` was left untouched because its `SKILL.md` has an uncommitted user edit; the recipe still needs fixing.
- **`since-last-tag.sh` handles tags orphaned by rewritten history.** Weather-range's `builds/testflight/external/2026.9.26.16.34` points at `d177d90`, which is not on `master`. The script looks for a "twin" commit with the same author time and subject and uses that as the base.
- The target-file contract gained a `Version bump` heading, because the target owns *how* to bump.
- **Preflight and What's New now run before the plan**, not after the bump commit. A skill review caught the problem: Preflight could stop the run, or declare a promotion, only after a bump commit already existed. TestFlight also pushes the notes during Ship, before the changelog step where they were being written.
- **The ASC build-number check takes the tuple maximum over every build**, not the newest upload. A stray older upload with a higher number is exactly the `20260404` landmine.
- The `deploy` description claims TestFlight uploads from repos that have `.config/deploy.yml` over `tal:appstore-connect`. Otherwise an upload could run with no tag and no changelog. It also answers "what's new since the last build" without deploying.
- Archives go to `~/Library/Developer/Xcode/Archives/…` and exports to a temp dir, so build output never dirties the tree that `tag.sh` checks.

## Not done

- Weather-range migration (brief §10 step 4): replace its `testflight` skill with `.config/deploy.yml`. That has to happen in the weather-range repo.
- Supabase and Portainer targets: deferred until something actually deploys there.
