# deploy: portainer Verify waits for compose to finish

## Changes
- `targets/portainer.md` Ship: dropped the claim that the redeploy PUT blocks until compose finishes. A 200 can come back with `Status: 3` and the new `ConfigHash` while the old containers are still running.
- Verify: new first step. Poll every 10 s up to `watch_timeout` until the stack has `Status: 1` and, for stacks with `build:` services, container ids that aren't in the Preflight baseline. Only then run the image-id, restart and health checks.
- Notes / landmines: recorded the `Status: 3` behavior and where it was seen.

## Learned
- The old Ship text was wrong. In two career-dash releases (`5c466b99bf2f` on 2026-10-18, `3904cb405bcf` on 2026-10-21), checking right after the PUT saw the baseline container and image ids, which looks exactly like **FAILED: not rebuilt**. The rebuilt containers showed up a few seconds to ~30 s later, and the stack moved from `Status: 3` to `Status: 1`.
- `Status: 3` = "deploying" was worked out by watching it happen. It isn't confirmed in Portainer's docs.
- Stacks without `build:` services may keep their container ids, so the new-ids condition only applies to build stacks. Otherwise the wait would always run the full timeout.
