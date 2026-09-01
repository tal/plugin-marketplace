# Titles and card pictures

Line numbers from commit `ffef3bc`.

## `title` — resolution order for a folder (`src/scan/catalog.ts:354-365`)

1. manifest `title` (trimmed);
2. else the **intro's** frontmatter `title` — intro = `README.md` / `index.md` (case-insensitive), else
   `<dirname>.md` (`src/scan/group.ts:13`, `:113-120`);
3. else the intro's first non-generic `# H1` — generic = `Video by …`, `Reel from …`, a bare URL,
   `untitled` (`src/scan/frontmatter.ts:286-296`); no H2 promotion for folders;
4. else `prettifyName(dirname)` (`src/util/paths.ts:139-148`).

The root is `AI Library` unless a **root manifest** declares `title` — the root README never renames it.

Where the resolved title shows: card title; page `<h1 class="page-title">` on non-root folder pages;
breadcrumbs; `<title>` as `"<title> · AI Library"`; `/_/api/tree`; the unlock prompt heading
`Unlock <title>`; `/_/unlisted` entries; search folder hits; the app problem page. The header brand link is
always the hard-coded `SITE_NAME` "AI Library".

Interaction with the intro body: `renderLibraryMarkdown(…, node.title)` strips a leading H1 that is generic
**or equal to the resolved title** (case-insensitive, trimmed, inline markup ignored), plus a following
heading equal to the title — one `<h1>` per page. So if the manifest `title` **differs** from the intro's
`# H1`, both render (page title, then the intro's H1). That is documented as accepted, not a bug. Tags still
come from the intro's frontmatter when the manifest sets the title.

Manifest `title` on an app folder shows on the card, crumbs and tree — it is **not** injected into the app's
own HTML `<title>`.

## `preview` — the card picture rule (`catalog.ts:311-334`)

Precedence, first match wins:

| # | Manifest | Card shows |
|---|---|---|
| 1 | `preview: none` | nothing — the 📁 glyph, even when a macOS icon exists (`Previews/Muted`) |
| 2 | `preview: <path>` and `<folder>/<path>` is a regular file whose lowercase extension is image / video / PDF | that file, thumbnailed through the ordinary derive chain (`/_/thumb/<hash>`), **cropped to fill** the card (`fit: cover`), like an item card |
| 2′ | `preview: <path>` but missing / a directory / wrong kind | `warn` (`was not found` / `is not a file` / `is not an image, video or PDF`) and **fall through** to 3 |
| 3 | nothing declared, folder has a macOS custom icon | the icon PNG (`/_/icon/<hash>`), transparency kept, **sized to fit** (`fit: contain`) |
| 4 | nothing | 📁 glyph |

Accepted kinds by extension (`src/util/mime.ts:12-19`): image `jpg jpeg png gif webp heic heif svg avif bmp tif tiff dng`;
video `mp4 m4v mov webm mkv ts avi`; `pdf`. Matching is lowercase (`Cover.JPG` is fine).

Path rules: relative to the declaring folder; no leading `/`; no `..`, `.`, empty segments; **no segment
starting with `.`**; backslashes normalised. A malformed path invalidates the manifest → folder hidden.
`none` is reserved (exact lowercase) and can never name a file called `none`; `None` is a filename.

Caveats:

- The preview file need not be an item — it can live in a sub-directory (`art/hero.png`) or in an app
  folder; it still gets a `MediaFile` and a thumb hash.
- Whether a `file` preview actually renders depends on the derive tool chain: `thumbUrl` returns `null`
  (glyph, no warning) when no installed tool can produce the JPEG. The deployed container ships ffmpeg +
  libheif only, so a **PDF preview is always a glyph** there; SVG/GIF depend on ffmpeg.
- **A locked folder shows no picture at all** — its icon or thumb URL would answer the unlock page into an
  `<img>`, and a `preview:` inside a protected folder is exactly what the password withholds.
  `/_/icon/<hash>` is guarded as its **folder**, `/_/thumb/<hash>` as the file; both carry the folder's
  unlisted headers.
- `/_/api/tree` returns the same `thumb` + `fit` per folder.

## How the macOS icon is found (`src/media/icon.ts:35-42`, `:93-124`)

Tried in order; the first carrier that yields a PNG wins:

| Carrier | What it is |
|---|---|
| `Icon\r/..namedfork/rsrc` (≥ 16 bytes) | the resource fork itself — macOS on APFS/HFS+. Not carried by git |
| `._Icon\r` (≥ 16 bytes) | the AppleDouble sidecar macOS writes when the volume can't hold a fork (exFAT, flattened copies). Survives a clone |
| `.library-icon.png` (must parse as PNG) | **not a fork** — one PNG already lifted out of the icns. The only carrier that reaches the deployed server |

The icns is parsed by byte-slicing (works in the Alpine container); the entry chosen is the smallest that
still covers `THUMB_SIZE`, never upscaled; legacy non-PNG entries (`ic04`/`ic05`, `is32`/`il32`, JPEG-2000)
are skipped. A **bare zero-byte `Icon\r` is not an icon** (`Tech/weird names` fixture). The PNG is extracted
once at boot into `CACHE_DIR/icons/<hash>.png`; a folder whose carrier yields nothing is never registered,
so a card can never point at a URL that 404s.

Why `.library-icon.png` exists: a filename containing `\r` cannot be *opened* over the bee1 CIFS mount
(listed, but `open()` → ENOENT), and `ai-library-mirror.sh` excludes `Icon\r` and `._*` and copies no xattrs
— so the NAS copy holds zero native carriers. `scripts/stage-folder-icons.ts` lifts one PNG per folder under
a CR-free name; it only reads the source icons. Staging and syncing icons is Tal's operation, not an agent's.

## Fixtures for the picture rule

| Folder | Manifest | Proves |
|---|---|---|
| `Previews/Iconified/` | none | icon by default |
| `Previews/Declared/` | `preview: cover.jpg` | declared file beats the icon the folder also has → `/_/thumb`, `cover` |
| `Previews/Nested/` | `preview: art/hero.png` | preview in a sub-directory |
| `Previews/Muted/` | `preview: none` | `none` wins over a real icon → glyph |
| `Previews/Broken/` | `preview: missing.jpg` | missing → warning, falls back to the icon |
| `Previews/Wrong Kind/` | `preview: note.md` | wrong kind → warning, no picture |
| `Previews/Synced/` | none; only `.library-icon.png` | the post-mirror shape |
