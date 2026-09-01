# Access and listing semantics

Everything here is enforced by **one Hono middleware above every route** (`src/access/guard.ts`, mounted
in `src/server.ts`) — pages, raw files, `/_/api/*`, `/_/thumb`, `/_/icon`, `/_/search`, app bundles.
Line numbers are from commit `ffef3bc`.

## The decision (`guard.ts:5-14`, `:503-557`)

For the catalogued node a path resolves to, with its `guards` chain (root→self, only folders that
**declared** `protected`):

1. `guards.length === 0` → allow.
2. Principal has `bypass === 'yes'` (forward-auth admin group) → allow.
3. Any guard in the chain is present in `session.unlocked` with expiry > now → allow.
4. Otherwise → `locked`, naming the **last** guard on the chain (the nearest one).
5. Path **not catalogued** (hidden, invalid manifest, nonexistent, dotfile, ignored name): if the nearest
   catalogued ancestor is locked for this principal → answer `locked` for **that** guard, exactly like a
   real child would; else `not-found`.

## `protected`

- **Page family** (everything except `/_/api/*`, `/_/rescan`, `/_/thumb/*`, `/_/file/*`) → **303** to
  `/_/unlock?folder=<guard>&next=<path+query>`. Clean raw-file URLs (`/invoices/invoice-2026-01-pdf`) are
  page family → 303.
- `/_/file/…`, `/_/thumb/…`, `/_/api/…` → **401** JSON `{ error: 'locked', guard }`.
- **Unlock page** `GET /_/unlock?folder=&next=` renders only for folders that themselves declared
  `visibility: protected` (`classifyGuard`, `src/routes/unlock.ts:32-37`). An inherited folder or an
  invented name → 404. `folder=` is matched case-insensitively; empty `folder=` is the root guard;
  `folder=@admin` is the admin guard. Heading: `Unlock <folder title>`. Copy promises "unlocks <title> and
  everything under it for this browser session (about 12 hours)" — "12 hours" is hard-coded copy; the real
  TTL is `SESSION_TTL_HOURS`.
- **`POST /_/unlock`** (form `folder`, `password`, `next`): wrong → 401 re-render "Wrong password."; right →
  `session.unlocked[folder] = now + SESSION_TTL` and **303** to `next` (same-origin path only, else `/`).
  Compare = SHA-256 of both sides + `timingSafeEqual`. Logs only `{ folder, ip }`.
- **Cookie** `lib_session` = `base64url(json).base64url(hmac)`, HttpOnly, SameSite=Lax, Path=/, Secure on
  https, `Max-Age` = furthest unlock expiry or the session TTL. Payload `{ sid, unlocked: { '<folder>': expiryMs }, admin, adminExpires? }`
  — never a password. Expired entries are pruned on read. Multiple unlocks accumulate in one cookie.
- **Scope:** one unlock covers the guard folder and **everything under it** at any depth, sub-folders with
  their own key included (`canOpen` accepts any guard on the chain). Unlocking a child never unlocks the
  parent. Inside a re-keyed child the prompt asks for the **child's** key; the parent's password typed
  there is a 401 — but a session that unlocked the parent is already through.
- **Session minting:** only the unlock prompt and app entry pages mint a fresh cookie; ordinary pages,
  files, APIs and 404s never do.
- **Rate limit** (`src/access/ratelimit.ts`): fixed window per `${ip}|${folder}`, `UNLOCK_RATE_LIMIT`
  (default 10) attempts per `UNLOCK_RATE_WINDOW_SECONDS` (default 300). The 11th attempt → **429** "Too many
  attempts. Try again in a few minutes." — even with the right password. Success resets the bucket. Each
  folder has its own bucket. Behind Caddy, `TRUSTED_PROXIES` must be set or every client shares the
  `unknown` bucket.
- **Bypass:** `FORWARD_AUTH_TRUST=trusted` + `Remote-Groups` containing `FORWARD_AUTH_ADMIN_GROUP` opens
  everything. The admin (`@admin`) unlock does **not** open protected folders.
- **Degraded boot:** a scan that yields zero items while a populated catalog is persisted keeps the old
  catalog but with **empty secrets** — protected folders show locks and cannot be unlocked until a good scan.
- **Locked folders show no card picture** — neither icon nor `preview:`.

## `hidden`

- Never catalogued (`catalog.ts:202-207`); nothing below it is read.
- Under an open ancestor → **404**, byte-identical to a nonexistent path ("Nothing at this address.").
- Under a locked ancestor → answers **locked** for that ancestor's guard, like every real child.
- Never in search, tree, or `/_/unlock?folder=` (404).
- Root `hidden` → empty library + `error` warning.

## No existence oracle (`guard.ts:10-14`)

A visitor without the password cannot tell real names from guesses inside a locked folder: same status,
same body, same `Location` (modulo `next=`), same JSON, same headers. Headers on a locked answer are the
**guard folder's** listing headers, never the probed target's — so an unlisted sub-folder inside a locked
*listed* folder answers with *listed* headers until unlocked. Once unlocked, invented names are honestly 404.

Headers on locked responses: `Location` (303) or JSON 401; `X-Robots-Tag: noindex, nofollow` +
`Referrer-Policy: no-referrer` **iff the guard folder is unlisted**; no `Set-Cookie`;
`Cache-Control: private, no-cache` (the unlock page itself: `no-store`).

## `listing: unlisted`

Enforcement points (`guard.ts:16-27`):

| Where | Behaviour |
|---|---|
| Parent grid, home, `/_/api/tree` | unlisted child folders and items are omitted from `visibleChildren` regardless of unlock state — **unless** the folder being viewed is itself unlisted (you already hold the URL) |
| Global search | `indexCandidates` skips unlisted items and folders and never descends into an unlisted folder from a listed scope; a search scoped **inside** it (`/_/search?in=<folder>`) finds its content. Folder-intro documents and folder title/tag hits obey the same candidate sets |
| Direct link | works: 200 for public+unlisted, the unlock prompt if also protected |
| Headers | on **every** route whose effective target is unlisted — folder page, item page, raw media, thumbs, icons, `/_/api/*`, `/_/search?in=`, `/_/unlock?folder=`, invented paths under it: `X-Robots-Tag: noindex, nofollow` + `Referrer-Policy: no-referrer`. HTML pages add `<meta name="robots" content="noindex, nofollow">` and a footer hint "This page is not listed anywhere … That is obscurity, not protection". Item pages show `Listing: unlisted link-only` |
| Sitemap / feeds / `robots.txt` | none exist in the server; the plan forbids ever naming unlisted paths in a robots file |
| Relisting | impossible — `listed` under an unlisted parent is a widening: ignored + warning; the child still appears **inside** the parent's own page |
| Finding them | `GET /_/unlisted` (requires `ADMIN_PASSWORD`; unlock via `folder=@admin`) lists the **roots** of unlisted subtrees with a lock badge when also protected. It is itself always unlisted and carries the **Rescan now** button |
| Not access control | under an unlisted folder a real name is 200 and a miss is 404 — deliberate. The chooser page for an ambiguous clean path under an unlisted folder carries the same noindex headers |

Composition (from the plan, Part B):

| `visibility` | `listing` | Meaning |
|---|---|---|
| `public` | `listed` | default |
| `public` | `unlisted` | link-only |
| `protected` | `listed` | listed with a lock; prompt on open |
| `protected` | `unlisted` | link-only and password-gated (the `Contracts` fixture) |
| `hidden` | — | implies unlisted |

## Inheritance corner cases (all verified)

| Parent | Child declares | Result |
|---|---|---|
| `protected` | `visibility: public` | child stays protected, `guards: [parent]`, `warn` "would widen inherited 'protected' — ignored"; any `title:` in the same file still applies |
| `protected` | `visibility: protected` + own password | `guards: [parent, child]`; parent key opens child; child key opens only child subtree; prompt inside child asks for child key |
| `protected` | `visibility: hidden` | legal narrowing; child absent; from outside answers like the locked parent |
| `unlisted` | `listing: listed` | stays unlisted + `warn`; still shown inside the parent's page |
| `unlisted` | `visibility: protected` + password | legal: protected **and** unlisted |
| `hidden` | anything | never read |
| root | `visibility: protected` + password | guard `''` on every node; `/` → `/_/unlock?folder=&next=%2F` |
| root | `visibility: hidden` | empty catalog + `error` |
| root | `listing: unlisted` | whole library unlisted |
| root | `title: …` | renames crumbs and `<title>`; header brand unchanged |
