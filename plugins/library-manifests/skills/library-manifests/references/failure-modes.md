# Failure modes — situation → outcome → warning → HTTP

"Fail closed" (`src/scan/catalog.ts:4-5`): an invalid manifest hides the folder rather than serving it
open. Warning strings are exact as of commit `ffef3bc`; `<path>` is the folder's library-relative path
(`(root)` for the root). No warning ever contains the offending **value**.

| Situation | Scan outcome | Warning | HTTP for the path |
|---|---|---|---|
| Invalid YAML — parse error, duplicate key (`DUPLICATE_KEY`), second document (`MULTIPLE_DOCS`), unresolved alias | folder + subtree **hidden** | `error` — `"<path>: invalid .library.yml — folder treated as hidden: YAML: YAMLParseError <CODE> at line L, column C"` (class + code + position only; the parser message would echo the token) | 404 for folder, items, files — or the locked ancestor's answer |
| Schema violation — wrong type (`title: 2026`, `password: 12345678`, `password: null`), mis-cased or unknown enum value (`Protected`, `banana`), empty string | hidden | `error` — `"… treated as hidden: /visibility: must be equal to one of the allowed values (one of "public", "protected", "hidden")"`, `"/title: must be string"`, `"/password: must NOT have fewer than 1 characters"` | 404 / locked-ancestor answer |
| Unknown or mis-cased key (top level or inside `app`) | hidden | `error` — `"/: must NOT have additional properties ('Visibility')"` | 404 |
| Document is a list or scalar | hidden | `error` — `"/: must be a mapping of keys to values"` | 404 |
| Manifest unreadable (EACCES etc.; ENOENT/ENOTDIR = absent, fine) | hidden | `error` — `"cannot read .library.yml: <code>"` | 404 |
| `password` without `visibility: protected` | hidden | `error` — `"/password: only allowed when visibility is 'protected'"` | 404 |
| `visibility: protected` without `password`, or empty password | hidden | `error` — `"/password: required when visibility is 'protected'"` / `"/password: must not be empty"` | 404 |
| `kind: app` without `app:` / `app:` without `kind: app` | hidden | `error` — `"/app: required when kind is 'app'"` / `"/app: only allowed when kind is 'app'"` | 404 |
| `app.entry` missing from the `app` block | hidden | `error` — `"/app/entry: required non-empty string"` | 404 |
| `app.entry` / `app.build` malformed (`/x`, `../x`, `./x`, `a//b`) | hidden | `error` — pattern message + `"must not contain empty, '.' or '..' segments"` / `"must be relative (no leading slash)"` | 404 |
| `app.entry` well-formed but missing on disk | **valid**, app node exists | `warn` — `"<path>: app.entry '<x>' not found"` | folder URL → **500** "This app cannot be shown. app.entry '<x>' could not be read." |
| `app.entry` inside a dot-directory (`.hidden/index.html`) | valid | `warn` — `"<path>: app.entry '<x>' is inside a dotfile path and can never be served"` | **500** "… is not a servable path." |
| `app.build` missing/broken, folder **in** `TRUSTED_APPS` | valid; build `failed` | log `warn` `app build failed`; scan `warn` `"<path>: app.build '<x>' not found"` when absent | folder URL → **500** "The app's build failed: <error>" |
| `app.build` present, folder **not** in `TRUSTED_APPS` | valid; build `skipped/untrusted` | log `warn` `app build ignored: folder is not in TRUSTED_APPS — entry served as-is` | 200, entry without bundle |
| `preview` malformed (leading `/`, `..`, `./`, any `.`-segment, `a//b`, trailing `/`) | hidden | `error` — `"/preview: must match pattern …"` / `"/preview: must not contain segments starting with '.' (the walker never serves those)"` | 404 |
| `preview` points at a missing file | valid | `warn` — `"<path>: preview '<rel>' was not found — ignored"` → falls through to macOS icon → glyph | 200, card without that picture |
| `preview` points at a directory | valid | `warn` — `"<path>: preview '<rel>' is not a file — ignored"` | 200 |
| `preview` points at a non image/video/PDF (`.md`, `.txt`) | valid | `warn` — `"<path>: preview '<rel>' is not an image, video or PDF — ignored"` | 200 |
| `preview: None` (capitalised) | valid | treated as a filename → `was not found` warning → fallback | 200 |
| Widening (`public` under `protected`, `listed` under `unlisted`) | scanned normally with the inherited value | `warn` — `"<path>: visibility 'public' would widen inherited 'protected' — ignored"` / `"<path>: listing 'listed' would widen inherited 'unlisted' — ignored"` — logged **and** rendered in a public `<details>` on the folder page | served per inherited rules |
| `listing:` beside `visibility: hidden` | folder hidden (by design) | none — silently ignored | 404 |
| Root manifest `visibility: hidden` | **empty catalog** | `error` — `"(root): .library.yml declares 'visibility: hidden' — the whole library is hidden, nothing will be served"` | everything 404 |
| Any folder **or file name** anywhere in the library containing `password` (any case) | scan succeeds, then `serializeCatalog` **throws** `refusing to serialize catalog: key '<name>' at catalog.folders looks like a password` (`catalog.ts:423-445`) | — | boot: `boot failed` → `process.exit(1)`; rescan: **500** `{error:'rescan-failed'}`, previous catalog kept. Documented open bug (`docs/2026-08-22_remaining-bugs-rescan.md`). |
| Scan returns zero items while a populated catalog is persisted | previous catalog kept, **secrets empty** | log `warn` | protected folders show locks but **cannot be unlocked** until a good scan |

Extra effect of an `error`-level warning: app bundles under that path are sheltered from cache eviction
(`build.ts:168-179`, `state.ts:558-567`).

## Verified gotchas (all checked against source or a live probe on a temp library)

1. Numeric-looking `title` / `password` (and `null`) → hidden folder. Quote them.
2. ` #` in a plain-scalar password starts a YAML comment. Quote it.
3. `preview: none` is case-sensitive.
4. `.library.yaml` is ignored (folder treated as manifest-free, **not** invalid). `.LIBRARY.YML` works only on
   case-insensitive volumes (macOS APFS default, the bee1 CIFS mount).
5. A path containing `password` crashes boot / fails rescan (open bug).
6. The mere existence of a manifest — empty included — turns a gallery-shaped directory into a category.
7. Malformed `preview` / `app.entry` path → hidden; missing target → warning (preview) or 500 (app).
8. Widening is loud, harmless, and **public**; preview/app warnings include the declared relative path.
9. Root manifest `title` renames crumbs and `<title>`; the header brand is hard-coded "AI Library".
10. `listing` beside `hidden` is ignored silently — no warning at all.
11. Only a folder that itself **declared** `protected` is a guard; `/_/unlock?folder=<inherited>` → 404.
12. An unlock covers sub-folders with their own key; the reverse never. Search and the tree show an
    Archive-only session its content while the parent stays locked.
13. Locked answers wear the **guard's** listing headers, not the target's.
14. Clean raw-file URLs under a lock **303** to the unlock page; `/_/file/…` and `/_/thumb/…` answer **401** JSON.
15. No sitemap, no `robots.txt`, no file watcher. Manifests are re-read only at boot and `POST /_/rescan`.
16. `app.entry` symlink escape is unchecked (open bug); static files under the app are realpath-contained.
17. A top-level folder literally named `@admin` collides with the virtual admin guard (open bug).
18. `TRUSTED_APPS` matches the catalog path exactly (on-disk spelling, NFC, case), not the slug URL.
19. The unlock page copy hard-codes "about 12 hours" regardless of `SESSION_TTL_HOURS`.
20. Degraded boot = protected folders un-unlockable (secrets empty) though the kept catalog still shows locks.
21. `declared` (the manifest's own keys minus `password`) is serialised into `catalog.json`; `manifest` on a
    node is `'absent' | 'valid'` in practice — `'invalid'` nodes never exist.
22. Manifests below an app root, inside gallery-collapsed directories, or anywhere under a hidden folder
    are never read.
23. `loadManifest` opens the file by path (`Bun.file`), which follows symlinks — the walker's no-symlink rule
    covers directory entries, not the manifest open itself (noted from reading; untested).
24. The schema `$id` is a dead URL (`/schema/library.json`, no `/_/`); the served route and the editor
    comment must use `/_/schema/library.json`.
25. Docs vs source drift to be aware of: `README.md:92` describes the old gallery rule (the conservative
    one in `group.ts` is current); the plan promises signed, expiring media URLs while clean raw paths are
    served unsigned (only `/_/thumb`/`/_/icon` hashes are HMACs); the plan says "every generated file starts
    with the language-server line" but nothing generates manifests.
