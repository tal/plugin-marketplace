# spotify-web-api

Reference plugin for working against Spotify's Web API — OAuth, endpoints, scopes, quota modes, and rate limiting — packaged as a single progressive-disclosure skill.

Ships no commands, agents, or hooks. It is pure knowledge: the skill fires on its own when you're touching the Spotify API, and pulls in the deeper reference files only when the task actually needs them.

## Install

```
/plugin install spotify-web-api@tal-marketplace
```

Codex:

```
codex plugin install spotify-web-api@tal-marketplace
```

## Skill

### `spotify-web-api`

Triggers on mentions of "Spotify API", "Spotify Web API", Spotify authentication / OAuth / access tokens, getting playlists, controlling playback, search, rate limits, scopes, or any request to talk to Spotify programmatically over REST.

`SKILL.md` covers, inline:

| Topic | What's there |
|---|---|
| Overview | Base URL, JSON format, bearer auth, rolling 30-second rate window |
| Authentication | Authorization Code, Authorization Code + PKCE, Client Credentials; redirect-URI rules (no `localhost` — use `127.0.0.1`/`[::1]`) |
| Token management | Access-token refresh, the 6-month refresh-token lifetime, `invalid_grant` handling, refresh-token rotation |
| Endpoint map | Albums, artists, tracks, playlists, search, player, users, library, shows, audiobooks, browse, genres, markets |
| Scopes | Scope families and how to pick a minimal set |
| Pagination | Offset-based vs the cursor-based endpoints (`/me/player/recently-played`, `GET /me/following?type=artist`) |
| Errors | Status-code table, error body shape, `QUOTA_EXCEEDED` vs burst 429s |
| Quota modes | Full development-mode constraint table, what extended quota mode does and doesn't restore, why restricted endpoints 404 rather than 403 |
| Common operations | Search modifiers, multi-get vs per-ID fetch, playlist `/items` (and the deprecated `/tracks` predecessor) |
| URIs and IDs | URI / ID / open.spotify.com URL forms |
| Usage policies | Spotify's terms on storage, attribution, streaming, and model training |

### Bundled references

Loaded on demand, not up front:

| File | Read it when |
|---|---|
| `references/endpoints-complete.md` | You need an endpoint's exact path, method, params, response shape, or required scope — also the authoritative per-endpoint quota-mode availability matrix |
| `references/authentication-flows.md` | Implementing or debugging OAuth: Authorization Code, PKCE, Client Credentials, refresh and storage |
| `references/scopes-complete.md` | Choosing a minimal scope set, dealing with partner-only `soa-*` scopes, or diagnosing a 403 |

### Bundled examples

| File | What it is |
|---|---|
| `examples/curl-examples.sh` | Common operations as runnable curl calls |
| `examples/auth-flow.md` | A working Express + TypeScript implementation of the Authorization Code flow |

## Prerequisites

None for the guidance itself. To actually call the API you need a Spotify Developer Dashboard app (client ID + secret), and note that **development mode** is where nearly every app lives: 5 allowlisted users, the owner account must have Premium, no batch multi-ID endpoints, no browse endpoints, and `/search` capped at `limit=10`. Extended quota mode is organization-only. The skill designs against the development-mode limits by default.
