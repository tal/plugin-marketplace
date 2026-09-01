# `kind: app` — static apps inside the library

An app is a folder whose manifest says `kind: app` with an `app:` block. Line numbers from commit `ffef3bc`.

```yaml
kind: app
title: Counter              # optional; card/crumbs/tree — NOT injected into the app's own <title>
app:
  entry: app/index.html     # required — folder-relative, no leading '/', no '.' or '..' segments
  build: app/src/main.ts    # optional — honoured only if this folder path is in TRUSTED_APPS
```

## Scan (`src/scan/catalog.ts:233-246`, `:371-392`)

- The folder becomes a `FolderNode` with `kind: 'app'`, `app: { entry, build }`, `items: []`, `folders: []`.
- Nothing below it is walked: its files never become items or search documents, and a `.library.yml`
  deeper inside is never read.
- `entry` / `build` existence is checked at scan → warnings `app.entry '<x>' not found`,
  `app.build '<x>' not found`, `app.entry '<x>' is inside a dotfile path and can never be served`.
- `visibility` / `listing` / `title` / `preview` compose with `kind: app` like any folder; every file under
  the app is guarded by the app node's guards.

## Entry serving (`src/routes/apps.ts:43-87`, `src/apps/serve.ts:29-64`)

`GET /<folder slug>` (e.g. `/apps/counter-app`) reads `<folder>/<entry>` and returns it as `text/html`,
`Cache-Control: no-store`, with the **app CSP**. Injections, in order:

1. First thing in `<head>`: `<script>window.LIBRARY = Object.freeze({ root: '<folder path>', apiBase: '/_/api', token })</script>`.
   `token` is an HMAC-sealed `{ scope: folder, sid, exp }`, valid `APP_TOKEN_TTL_SECONDS` (default 6 h).
2. `<base href="/<folder slug>/<entry dir>/">` unless the document already has a `<base>`.
3. The bundle's CSS `<link>` (trusted builds only).
4. The bundle `<script type="module">` before the last `</body>` (trusted builds only).

A `<head>` is synthesised if missing. Entry pages mint a session cookie (for the scoped token).

App CSP (nonce-free on purpose):
`default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self'; font-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'self'`.

Failure pages: entry missing → **500** "This app cannot be shown. app.entry '<x>' could not be read.";
entry in a dot-directory → **500** "… is not a servable path."; trusted build failed → **500** "The app's
build failed: <error>".

## Static files under the app (`apps.ts:89-158`)

Served by real path with **realpath containment** (a symlink leaving the app folder → 404), no directory
listings, dotfiles 404, trailing slashes 308 to the slashless canonical, `.ts` sniffed (MPEG-TS vs
TypeScript). **Open gap:** `app.entry` itself is read without the containment check
(`docs/2026-08-22_remaining-bugs-rescan.md`).

## Scoped API (`src/server.ts:150-183`, `src/routes/api.ts:124-175`)

With `Authorization: Bearer <window.LIBRARY.token>`:

| Endpoint | Behaviour with an app token |
|---|---|
| `/_/api/tree`, `/_/api/item`, `/_/api/search` | clamped to the app subtree; 404 outside it |
| `/_/api/files?dir=` | exists **only** with a token; lists the app's own files with raw and derived-JPEG display URLs |

Because the scan excludes the app's files, these are the app's only way to see its own data.

## Cards

Badge `app`, glyph 🧩, subtitle "app". `title` shows on the card, crumbs and `/_/api/tree`.

## `build` — trusted folders only

- `TRUSTED_APPS` is a comma-separated list of **library-relative folder paths in on-disk spelling**
  (`src/config.ts:52-59`); membership is exact `Set` lookup on `node.path` (`state.ts:366-384`) — case and
  NFC must match the catalog, and it is the path, not the URL slug. Dev: `TRUSTED_APPS=Apps/counter-app`
  (`package.json`); `compose.yaml` leaves it empty.
- **Trusted + `build`:** `Bun.build({ target: 'browser', format: 'esm', minify: false, sourcemap: 'none', naming: '[name].[ext]' })`
  into `CACHE_DIR/apps/<hash>/` with a `manifest.json` `{ scriptFile, cssFile, folder }`.
  `hash = sha1(fingerprint(whole app folder: path|mtime|size of every regular file, minus scanner-ignored
  names, node_modules, dotfiles, and a __build dir) + '|' + relBuild)` — never file contents, so an edit to
  `../shared/util.ts` outside the entry's directory still rebuilds. Reused while the dir exists; built into a
  scratch dir then renamed; superseded outputs for the same folder pruned after a successful rebuild;
  orphans swept on rescan with two "keep" floors. The build entry must stay inside the app folder.
- Served at `<folder>/__build/<scriptFile>` (slug `/apps/counter-app/build/main-js`),
  `Cache-Control: private, max-age=0, must-revalidate`.
- **Untrusted + `build`:** `{ status: 'skipped', reason: 'untrusted' }`, log `warn`
  `app build ignored: folder is not in TRUSTED_APPS — entry served as-is`, no bundle tags injected.
  No `build` at all → `skipped/no-build` either way.
- **Security trade-off, by design** (`src/apps/build.ts:7-10`, plan Part F): bundling code from the library
  tree *executes* it — Bun macros, `bunfig.toml` preloads, and `tsconfig.json` / `package.json` inside the
  folder are honoured. "The decision to execute code must not live in the same tree as the code": the
  allowlist lives in server env, which no sync can touch. Only folders whose contents the owner controls
  belong in `TRUSTED_APPS`. Adding a folder to `TRUSTED_APPS` is a server-config change on bee1, not a
  manifest change.

## Fixtures

- `Apps/counter-app` — `kind: app`, `title: Counter`, `entry: app/index.html`, `build: app/src/main.ts`;
  trusted in dev. Proves: TS build with an inlined import, `window.LIBRARY`, `<base href>`, `__build`
  bundle, a stray `.mp4`+`.md` inside never becomes an item, `.gitignore` 404s, escaping symlinks 404.
- `Apps/static-app` — `kind: app`, `entry: index.html`, no build; served as-is with `LIBRARY` injected.
