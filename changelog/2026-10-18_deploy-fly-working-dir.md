# deploy: `working_dir` key for the fly target

## Changes
- `targets/fly.md` has a new optional key, `working_dir`: a repo-relative build context passed as `fly deploy <working_dir>`. It defaults to the repo root and can be set per channel.
- The key is now covered in Setup (where to find it), Doctor step 5 (the directory exists and holds the Dockerfile) and Ship (the command, which runs from the repo root).
- Added a landmine: `-c` picks the config file, but the build context is the `WORKING_DIRECTORY` argument. Promotions and rollbacks deploy an `--image`, so they don't need it.

## Learned
- Found by `/deploy doctor fly` in sport-range. That monorepo keeps `coach/fly.toml` and `coach/Dockerfile` and deploys from the repo root.
- `fly deploy --help` (v0.4.108) doesn't say whether `-c` moves the build context. Untested. Passing `working_dir` explicitly avoids depending on it either way.
