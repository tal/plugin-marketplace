# Config mode: editing `.config/deploy.yml`

Loaded from SKILL.md §11. It sets up or changes a repo's `.config/deploy.yml`.
Nothing is deployed, tagged or pushed.

```
/deploy config                    show the config, then ask what to change
/deploy config init               create the file for this repo
/deploy config add <target> [<channel> …]
/deploy config <plain words>      e.g. "add a staging channel to fly",
                                  "external should always submit for beta review",
                                  "add a pipeline that ships internal then staging"
```

Plain words work without `config` too, when they're clearly about the file
("set up deploys for this repo", "add Fly to deploy.yml"). An ambiguous
request ("deploy staging") is a deploy, never an edit.

## 1. Load

```bash
"$S/check-config.sh" --format json
```

- `status=missing`: only `init` or `add` make sense. For anything else, say
  there's no file and offer `init`.
- `status=invalid`: show the `errors`. Fixing them is a valid edit; offer it
  first, before the requested change.
- **Show** (bare `/deploy config`, or "what's configured?"): list the targets with
  their channels, pipelines, and every generic key that differs from the §2
  default. Then ask what to change, with AskUserQuestion options such as Add a
  target, Add a channel, Edit a key, Add a pipeline. A plain question stops here.

## 2. Work out the change

| Request | What to do |
|---|---|
| `init` | Look for every shipped target's signals (`*.xcodeproj` → `testflight`, `fly.toml` → `fly`, deploy workflows / PaaS remotes → `push`). Ask which to set up (multi-select), then `add` each |
| `add <target>` | Read `targets/<target>.md`: **Required keys**, the optional table, **Channels**, **Setup**. Fill every required key by following **Setup**, and ask for whatever it can't find. Channels: the ones given, else the target file's **Channels** line, else ask |
| Add or rename a channel | Same **Setup** lookups for the channel's per-channel keys |
| Edit a key | Check the value against the key's table row (enums, formats). Generic keys go top-level unless the user scopes them to a target or channel |
| Add a pipeline | Each step is `target:channel` for a block that exists. Ask for the order |
| Remove a target or channel | Also offer to drop the pipeline steps that name it, and refuse to leave a pipeline that names something missing |
| A target with no `targets/<name>.md` | Write the block from what the user says and what the repo shows (§9's discovery). Its keys can't be checked against a file. Offer to write the target file too |

Rules for the values:

- **Never write secrets.** Write env var **names** (`token_env: FLY_API_TOKEN`)
  and key **paths** (`api_key_dir`) only. If the user pastes a token or key,
  don't write it. Ask which env var holds it.
- **Enums, never booleans.** If a value would be `true`/`false`/`yes`/`no`, use
  the key's enum instead. `dirty` is never a key.
- **Leave defaults out.** Don't write a key whose value equals its default
  (§2, or the target file's optional table) unless the user asks for it.
- Quote values YAML would retype: numeric ids (`app_id: "1234567890"`),
  anything with a leading zero, and words like `on`/`off`/`yes`/`no`.
- Write `$HOME`, not `~`, in paths.
- Pipeline steps: block list (`- fly:staging`) or quoted flow items
  (`["fly:staging"]`). An unquoted `[fly:staging]` breaks Ruby's parser.
- Duplicate keys are silently last-wins in both parsers, and `check-config.sh`
  can't see them. Before adding a key, check the block doesn't already have it.
- `config` is reserved: it can't be a target block or a pipeline name.

Renaming a channel or a target orphans its history: `since-last-tag.sh` and the
promotion checks look for `builds/<target>/<channel>/*` tags, and tags are
immutable. Say so before renaming. The first run under the new name has no
previous release, so What's New covers all history unless the user picks a
base.

## 3. Show, confirm, write

1. Show the change before writing. For a new file, show all of it. For an
   edit, show the changed lines with a few lines of context, as `-`/`+` lines.
2. Ask: **Write this?** → Write / Change something / Cancel.
3. Edit the file **in place**: keep comments, key order, quoting and the flow
   or block style already used. Never round-trip the whole file through a YAML
   library, because that drops comments. A new file starts with a short header
   comment:
   ```yaml
   # Release config for the tal:deploy skill (`/deploy <target> <channel>`).
   # Generic keys and defaults: the deploy skill's SKILL.md §2.
   # Target keys: the deploy skill's targets/<target>.md.
   # No secrets here: env var names and key paths only.
   ```
4. Validate:
   - `"$S/check-config.sh"` must exit 0. Show its warnings.
   - Every target and channel that was touched has all the **Required keys**
     from its target file once block and channel values are merged.
   - If either check fails, fix the edit, or put the file back the way it was
     and report what failed. Never leave an invalid file behind.

## 4. Commit

A changed `deploy.yml` is a dirty tree, and the next `/deploy` would refuse it.
Ask: **Commit** / **Leave uncommitted**.

- Commit: only that file.
  `git add .config/deploy.yml && git commit -m 'chore(deploy): <what changed>' -- .config/deploy.yml`
  Add any commit attribution trailer your harness requires.
- Don't push. The next deploy's push step takes it along.

**During a deploy run** (§4's missing keys, §9's saved block), the edit
follows the same steps 2–3 at the end of the run. Commit it before the run's
final push, as its own commit after the changelog commit.
