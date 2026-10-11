# Integer-`exp` JWT minter for App Store Connect

**Date:** 2026-10-11
**Scope:** `plugins/tal/skills/appstore-connect/` (new `scripts/asc-jwt.py`, references, SKILL.md Quick Example), `plugins/tal/skills/deploy/targets/testflight.md`, `plugins/tal/README.md`

## Why

During the weather-range migration, its 2026-07-11 release log turned up this: `xcrun altool --generate-jwt` emits a **fractional `exp`**, and the ASC REST API rejected that token with `401 NOT_AUTHORIZED`. The build-status poll read every 401 as "build absent", so a 20-minute stall looked like slow processing. Every weather-range release since has used a hand-rolled integer-`exp` token, but the plugin recipes still used `--generate-jwt`.

## What was verified (2026-10-11)

| Token | `exp` | `GET /v1/apps/<id>` | `GET /v1/builds?filter[app]=…` |
|---|---|---|---|
| `altool --generate-jwt` | `1791737477.3232589` (fractional, no `iat`) | 200 | 200 |
| `scripts/asc-jwt.py` | integer, with `iat` | 200 | 200 |

**The July 401 did not reproduce today.** Apple's handling of fractional `exp` has varied, so the minter stays as the default for REST calls. The docs say both things rather than claiming altool tokens always fail.

## What changed

- `scripts/asc-jwt.py`: Python stdlib plus the `openssl` CLI, ES256 with an integer `exp`. The issuer is read from the `AuthKey_<id>.issuer-id` sidecar, and the TTL is capped at Apple's 20 minutes.
- The polling recipe now stops on 401/403 instead of treating them as "not there yet"; only a 404 means "keep waiting".
- `targets/testflight.md` Preflight now mints with `asc-jwt.py` and makes one read-only `GET` that must return 200. It also gained a landmine: zsh treats unquoted `[ ]` in URLs as globs.
- `appstore-connect` is no longer "reference-only (no scripts)", and the README says so.
