# deploy: portainer target

- New `plugins/tal/skills/deploy/targets/portainer.md` for Portainer **git repository stacks**. Ship = `PUT /api/stacks/<id>/git/redeploy`, Verify = `ConfigHash` matches the commit + the image id changed + no restart loop + optional `health_url`.
- Written during `/deploy init` for career-dash (stack 37 on bee1), where no shipped target fit: no xcodeproj, no fly.toml, no deploy workflows.
- Landmines recorded: the redeploy `env` replaces the stack env (re-send `.Env`), `pullImage: true` upgrades every floating tag, the 2.42 create route and `composeFile` field, and pinned build-arg shas don't move.
- Unverified: whether Portainer 2.42 rebuilds an existing `build:` image on git redeploy. Verify's image-id comparison is there to catch a silent no-rebuild on the first real run.
