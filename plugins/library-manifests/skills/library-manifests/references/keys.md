# Every key, exactly

Types live in `src/types.ts` (`ManifestDeclared`, `Visibility`, `Listing`, `FolderKind`, `AppConfig`,
`PreviewDeclared`). Validation is `schema/library.schema.json` (Ajv draft-07, `allErrors`, `strictSchema`,
`strictRequired: false`) **plus** a hand-written re-check in `validateManifest()` (`src/scan/manifest.ts`)
so a loosened schema still fails closed. Line numbers are from commit `ffef3bc`.

Common shape rules:

- Top level must be a mapping. A list or scalar → `"/: must be a mapping of keys to values"`.
- `additionalProperties: false` at the top level and inside `app` → `"/: must NOT have additional properties ('<key>')"`.
- Empty file / comment-only file → `{}` → valid, nothing declared.
- Errors name the JSON pointer, keyword and constraint — never the offending value.

## `kind`

| | |
|---|---|
| Type | `string`, enum `collection` \| `app` |
| Absent | `collection` (`catalog.ts:217`) |
| Inherits | no |
| Coupled rule | `kind: app` **requires** `app:`; `app:` **requires** `kind: app` (`schema` allOf, `manifest.ts:130-131`). `kind: collection` + `app:` is invalid. |
| Errors | `/kind: must be equal to one of the allowed values (one of "collection", "app")`; `/app: required when kind is 'app'`; `/app: only allowed when kind is 'app'` |
| Runtime | `app` → folder becomes an app node: not descended into, `items: []`, `folders: []`, entry served at the folder URL (`references/apps.md`). `collection` → ordinary category. The only observable effect of writing `kind: collection` is that the file now exists (gallery rule). |

## `visibility`

| | |
|---|---|
| Type | `string`, enum `public` \| `protected` \| `hidden` — case-sensitive |
| Absent | inherited from the nearest ancestor that sets it; root default `public` (`manifest.ts:250`) |
| Inherits | yes, **narrow-only**, rank `public 0 → protected 1 → hidden 2` (`manifest.ts:247`, `:266-275`) |
| Coupled rule | `protected` requires `password`; `password` requires `protected` |
| Errors | enum message as above; `/password: required when visibility is 'protected'` |
| Runtime | `protected`: the folder is appended to its own `guards` chain (`manifest.ts:271`) → unlock prompt for every path under it. `hidden`: the walker does not descend; the folder never exists in the catalog (`catalog.ts:202-207`). Widening (declared rank < inherited rank) → key ignored + `warn` (`references/access-and-listing.md`). |

## `password`

| | |
|---|---|
| Type | `string`, `minLength: 1`. Must be a YAML **string**: `12345678` is a number, `null`/`~` null → `type` error → **folder hidden**. Quote it. |
| Absent | fine unless `visibility: protected` |
| Inherits | no (each guard has its own) |
| Coupled rule | only allowed when `visibility: protected` (`manifest.ts:127-129`) |
| Errors | `/password: required when visibility is 'protected'`; `/password: must not be empty`; `/password: only allowed when visibility is 'protected'` |
| YAML traps | plain scalar ` #…` is a comment (`password: pw #x` → `pw`); `: ` inside needs quotes; not trimmed; compared byte-exact after SHA-256 + `timingSafeEqual` (`src/access/unlock.ts:9-18`) |
| Runtime | returned by `validateManifest` **separately** from `declared` and stored only in `Secrets.passwords: Map<folderPath, plaintext>` in memory (`types.ts:204-208`, `catalog.ts:208-210`); never on a `FolderNode`, never in `catalog.json`, never in any API/log/cookie/error. Uniqueness across folders is **not** enforced. |

## `listing`

| | |
|---|---|
| Type | `string`, enum `listed` \| `unlisted` |
| Absent | inherited; root default `listed` |
| Inherits | yes, **narrow-only**, rank `listed 0 → unlisted 1` (`manifest.ts:248`, `:277-284`) |
| With `hidden` | silently ignored (no warning); resolved listing is forced to `unlisted` (`manifest.ts:278`, `:285`) |
| Errors | enum message |
| Runtime | `unlisted` → omitted from parent grid, home, `/_/api/tree` and global search regardless of unlock state (except when viewing the unlisted folder itself); `X-Robots-Tag: noindex, nofollow` + `Referrer-Policy: no-referrer` + `<meta name="robots">` on every route under it. Direct links work. Widening → ignored + `warn`. |

## `title`

| | |
|---|---|
| Type | `string`, `minLength: 1`. Trimmed; a whitespace-only value passes the schema and is then silently dropped (`manifest.ts:150-151`). Non-string (`title: 2026`) → hidden. Quote numbers. |
| Absent | resolution falls through: intro frontmatter `title` → intro's first non-generic `# H1` → `prettifyName(dirname)` (`catalog.ts:354-365`) |
| Inherits | no |
| Runtime | shown on the card, the page `<h1>`, breadcrumbs, `<title>` (`"<title> · AI Library"`), `/_/api/tree`, the unlock prompt heading `Unlock <title>`, `/_/unlisted`, search folder hits. Works at the root (renames crumbs/`<title>`; header brand stays "AI Library"). If it differs from the intro's `# H1`, both headings render — accepted behaviour. Tags still come from the intro's frontmatter. Never shown for a hidden folder. |

## `preview`

| | |
|---|---|
| Type | `string`, `minLength: 1`, pattern `^(?!/)(?!.*(^|/)\.).+$` — no leading `/`, **no segment starting with `.`** |
| Code re-check | no leading `/` or `\`; no NUL; no empty / `.` / `..` segments; dot-segments rejected (`manifest.ts:68-87`, `:123-125`); backslashes normalised to `/` |
| Reserved value | `none` (exact, lowercase) → `{ source: 'none' }` → glyph even if a macOS icon exists. `None` is treated as a filename. |
| Absent | the folder's macOS custom icon if it has one, else the 📁 glyph |
| Inherits | no |
| Errors (→ hidden) | `/preview: must match pattern "…"`; `/preview: must not contain empty, '.' or '..' segments`; `/preview: must not contain segments starting with '.' (the walker never serves those)`; `/preview: must be a non-empty string` |
| Warnings (→ fallback, folder stays) | `"<path>: preview '<rel>' was not found — ignored"`, `"… is not a file — ignored"`, `"… is not an image, video or PDF — ignored"` (`catalog.ts:327-346`) |
| Accepted kinds | by lowercase extension (`src/util/mime.ts`): image `jpg jpeg png gif webp heic heif svg avif bmp tif tiff dng`; video `mp4 m4v mov webm mkv ts avi`; `pdf` |
| Runtime | `file` → `/_/thumb/<hash>` derived JPEG, cropped to fill (`fit: cover`); the target need not be an item (may sit in a sub-directory or an app folder). Whether it renders depends on the derive tool chain — in the deployed container a PDF preview is always a glyph. A locked folder shows no picture at all. |

## `app.entry`

| | |
|---|---|
| Required | yes, inside `app` (`app` requires it: `"/app/entry: required non-empty string"`) |
| Type | `string`, `minLength: 1`, pattern `^(?!/)(?!.*(^|/)\.\.?(/|$)).+$` — no leading `/`, no `.`/`..` segments |
| Code re-check | `checkRelativePath(…, 'allowed')` — dot-segments like `.hidden/index.html` **pass** validation but the scan warns `"… is inside a dotfile path and can never be served"` and the route answers **500** |
| Errors (→ hidden) | pattern message; `/app/entry: must not contain empty, '.' or '..' segments`; `/app/entry: must be relative (no leading slash)` |
| Warning (folder stays) | `"<path>: app.entry '<x>' not found"` (`catalog.ts:384-391`) → folder URL answers **500** "This app cannot be shown. app.entry '<x>' could not be read." |
| Runtime | read from `<folder>/<entry>`, served as `text/html`, `Cache-Control: no-store`, app CSP, with `window.LIBRARY`, `<base href>` and (if built) the bundle tags injected. **Not** realpath-contained (open bug); static files under the app are. |

## `app.build`

| | |
|---|---|
| Required | no |
| Type / pattern | same as `entry` |
| Errors (→ hidden) | `/app/build: must be a non-empty string`; same path messages as `entry` |
| Runtime | honoured **only** when the folder's catalog path is in `TRUSTED_APPS` (comma-separated, on-disk spelling, NFC, case — exact `Set` membership on `node.path`, `src/config.ts:52-59`, `state.ts:366-384`). Trusted → `Bun.build` into `CACHE_DIR/apps/<hash>/`, served under `<folder>/__build/`. Untrusted → `{ status: 'skipped', reason: 'untrusted' }`, log `warn` `app build ignored: folder is not in TRUSTED_APPS — entry served as-is`. Missing file when trusted → scan `warn` `app.build '<x>' not found` and the folder URL answers 500 "The app's build failed: …". |

## Inheritance in one place

`resolveAccess(parent, declared, folderPath)` — `src/scan/manifest.ts:261-288`, called per folder with the
parent's resolved `{ visibility, listing, guards }`.

- Only `visibility` and `listing` inherit. `kind`, `title`, `preview`, `app`, `password` never do.
- Declared value applies iff `rank(declared) >= rank(inherited)`. Equal is allowed and meaningful for
  `protected` (re-key: folder appends **itself** to `guards`).
- Wider → ignored, `warn` `"<path>: <key> '<declared>' would widen inherited '<inherited>' — ignored"`.
  Not an error; the folder is scanned normally; other keys apply. Warning lands in `catalog.warnings`,
  the node's own `warnings[]`, the boot/rescan log, and a public `<details>` block on the folder page
  (`src/render/grid.ts:54-57`).
- `hidden` → caller stops descending. `listing` beside it is ignored silently and resolves to `unlisted`.
- Root (`parent === null`): `public` / `listed` / `guards: []`. `(root)` is the label in warnings.
- Resolved on every node and item: `visibility` (`'public' | 'protected'` — hidden nodes don't exist),
  `listing`, `guards` (root→self). Items copy their folder's values.
