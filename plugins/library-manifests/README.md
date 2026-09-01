# library-manifests

Reference plugin for the AI Library server's per-folder `.library.yml` manifests — the one and only
configuration file the server (`~/Projects/ai-library-server`, deployed at `library.tal.by`) reads from the
folder tree. Packaged as a single progressive-disclosure skill.

Ships no commands, agents, or hooks. It is pure knowledge: the skill fires on its own when you are writing,
debugging, or explaining a manifest, and pulls in the deeper reference files only when the task needs them.
Every claim was verified against the server source (commit `ffef3bc`, 2026-08-30) and, for the edge cases,
against live probes on throwaway fixture trees — never the real library.

## Install

```
/plugin install library-manifests@tal-marketplace
```

Codex:

```
codex plugin add library-manifests@tal-marketplace
```

Project-scoped alternatives (what is set up in `~/Downloads`, where the real library lives):

- Claude Code: `claude plugin install library-manifests@tal-marketplace --scope project` run from the
  folder — writes `.claude/settings.json` → `enabledPlugins`.
- Codex: a **copy** of this plugin's skill directory at `.agents/skills/library-manifests` in the folder, so
  Codex discovers it as a project skill without a global plugin install. Codex does not follow symlinks for
  skills (neither a symlinked skill directory nor symlinked contents are discovered — verified 2026-08-30),
  so after editing the skill here, refresh the copy:

  ```
  rsync -a --delete ~/Projects/plugin-marketplace/plugins/library-manifests/skills/library-manifests/ ~/Downloads/.agents/skills/library-manifests/
  ```

## Skill

### `library-manifests`

Triggers on `.library.yml`, "library manifest" / "folder manifest", `library.tal.by`, and any request to
password-protect, hide, unlist, make link-only, retitle, give a cover picture to, or turn into a static app
a folder in the AI Library — plus the debugging questions: why did a folder vanish or 404, why is a
sub-folder still locked / still missing, why did a card lose its picture, why does an app 500.

`SKILL.md` covers, inline:

| Topic | What's there |
|---|---|
| Ten facts | filename, optionality, Ajv + `additionalProperties: false`, the editor `$schema` line (and the dead `$id` trap), YAML 1.2 typing traps, fail-closed, rescan-only reads, dotfile, read-only library, plaintext passwords |
| Keys at a glance | `kind`, `visibility`, `password`, `listing`, `title`, `preview`, `app.entry`, `app.build` — values, defaults, inheritance, effect, relative-path rules |
| Two axes | `visibility` × `listing` composition table; inheritance; narrow-only; widening is ignored + publicly warned; re-keying; only declaring folders are guards; root manifests |
| Access cheat sheet | 303 vs 401 vs 404, unlock flow, cookie, rate limit, no existence oracle, locked folders show no picture, `/_/unlisted` |
| Structural side effects | the gallery rule (existence is enough), `kind: app` excludes content, `hidden` stops the walk |
| Triage table | symptom → most likely cause → how to confirm (log line / page `<details>` / status code) |
| Recipes | every working shape, and the shapes that look like they should work but don't |
| Gotchas checklist | the verified surprises |
| Rules of engagement | who writes manifests (Tal, by hand), fixtures-only in the server repo, `Travel/…` hands-off, never run the mirror, throwaway passwords, no write path ever, rescan after |

### Bundled references

Loaded on demand, not up front:

| File | Read it when |
|---|---|
| `references/keys.md` | You need a key's exact type, pattern, conditional requirement, or the error string a violation produces |
| `references/access-and-listing.md` | Explaining or debugging protected / hidden / unlisted: guard decision order, unlock flow, cookie shape, rate limit, headers, search and tree filtering, `/_/unlisted`, forward-auth bypass, inheritance corner cases |
| `references/apps.md` | Anything `kind: app`: entry serving and injections, CSP, static files, scoped API + token, `TRUSTED_APPS`, build cache key, the security trade-off |
| `references/previews-and-titles.md` | Title resolution order and where titles show; the card-picture precedence including macOS icon carriers and `.library-icon.png` |
| `references/failure-modes.md` | The complete situation → outcome → warning text → HTTP table, plus every verified gotcha |
| `references/fixtures.md` | What each fixture manifest in `fixtures/library/` proves, the fixture passwords, which tests pin what |
| `examples/*.yml` | Copy-ready manifests for every shape, each validated against the server's own `validateManifest` |

## Keeping it current

The skill mirrors the server at a specific commit. When `schema/library.schema.json`, `src/scan/manifest.ts`,
`src/scan/catalog.ts`, or `src/access/guard.ts` change behaviour, update the matching section here and bump
the commit note at the top of `SKILL.md`. Then:

- **Claude Code** caches an installed plugin per `version` (`~/.claude/plugins/cache/tal-marketplace/library-manifests/<version>`)
  and `claude plugin update` reports "already at the latest version" while the number is unchanged — bump
  `version` in both `plugin.json` files, run `claude plugin marketplace update tal-marketplace`, then
  `claude plugin update library-manifests@tal-marketplace --scope project` from `~/Downloads`.
- **Codex** in `~/Downloads` reads the copy — run the `rsync` above.
