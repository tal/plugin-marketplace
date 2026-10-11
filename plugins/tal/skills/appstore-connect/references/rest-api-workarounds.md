# ASC REST API Workarounds

altool cannot access TestFlight builds, beta testers, review status, or many other App Store Connect features. Mint a JWT, then query the REST API directly with curl.

## Generating a JWT

Prefer the bundled minter, which signs an ES256 token with an **integer** `exp`:

```bash
TOKEN=$("${CLAUDE_PLUGIN_ROOT}/skills/appstore-connect/scripts/asc-jwt.py" --key-id <KEY_ID>)
# --issuer defaults to the AuthKey_<KEY_ID>.issuer-id sidecar
# --key-dir defaults to $API_PRIVATE_KEYS_DIR, then ~/.config/appstoreconnect/private_keys
```

`xcrun altool --generate-jwt` emits a **fractional** `exp` (e.g. `1791737477.3232589`) and no `iat`. On 2026-07-11 the REST API rejected such a token with `401 NOT_AUTHORIZED` mid-release, while altool's own upload path kept working (weather-range release log). On 2026-10-11 the same kind of token was accepted again on `GET /v1/apps` and `GET /v1/builds`. Apple's behavior has varied, so don't rely on it for REST calls. The altool form still works as a fallback:

```bash
TOKEN=$(xcrun altool --generate-jwt --api-key <KEY_ID> --api-issuer <ISSUER_ID> 2>&1 | grep '^ey')
```

The token is valid for up to 20 minutes. All REST API calls use:
```bash
curl -s -H "Authorization: Bearer $TOKEN" '<URL>'
```

## URL Encoding for Filter Parameters

The ASC REST API uses bracket syntax for filters: `filter[field]=value`. Bare brackets cause curl to fail with a "bad range" error. Always URL-encode them:

| Character | Encoded |
|---|---|
| `[` | `%5B` |
| `]` | `%5D` |

Example: `filter[app]=123` becomes `filter%5Bapp%5D=123`

## Common Queries

### List TestFlight Builds

```bash
TOKEN=$(xcrun altool --generate-jwt --api-key <KEY_ID> --api-issuer <ISSUER_ID> 2>&1 | grep '^ey')
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=<APPLE_ID>&sort=-uploadedDate&limit=10'
```

Parse with python3:
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=<APPLE_ID>&sort=-uploadedDate&limit=5' \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
for b in d['data']:
    a = b['attributes']
    print(f\"{a['version']}  uploaded={a['uploadedDate']}  state={a['processingState']}\")
"
```

Or with jq:
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=<APPLE_ID>&sort=-uploadedDate&limit=5' \
  | jq -r '.data[] | "\(.attributes.version)  uploaded=\(.attributes.uploadedDate)  state=\(.attributes.processingState)"'
```

### Filter Builds by Version String

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=<APPLE_ID>&filter%5Bversion%5D=<BUILD_NUMBER>'
```

### Filter Builds by Processing State

Valid states: `PROCESSING`, `FAILED`, `INVALID`, `VALID`

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=<APPLE_ID>&filter%5BprocessingState%5D=VALID&sort=-uploadedDate&limit=5'
```

### Get Pre-Release Versions (TestFlight Versions)

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/preReleaseVersions?filter%5Bapp%5D=<APPLE_ID>&sort=-version&limit=5'
```

### Get Beta App Review Submission Status

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions?filter%5Bbuild%5D=<BUILD_ID>'
```

The `BUILD_ID` is the `id` field from the builds response, not the version string.

### List Beta Groups

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/betaGroups?filter%5Bapp%5D=<APPLE_ID>'
```

### List Beta Testers

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/betaTesters?filter%5Bapps%5D=<APPLE_ID>&limit=50'
```

### Attach a Build to a Beta Group

After `--upload-package` succeeds, the build needs a few seconds to a few minutes to appear in `/v1/builds`. Once it does, attach it to an **external** beta group with:

```bash
curl -s -w "\n%{http_code}" -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.appstoreconnect.apple.com/v1/betaGroups/<GROUP_ID>/relationships/builds" \
  -d "{\"data\":[{\"type\":\"builds\",\"id\":\"<BUILD_ID>\"}]}"
```

Success returns HTTP 204 with empty body. Reverse direction (`/v1/builds/<id>/relationships/betaGroups`) accepts CREATE/DELETE but **not GET** — there is no way to query "what groups is this build in?" directly. To verify, list the group's builds:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/betaGroups/<GROUP_ID>/builds?sort=-uploadedDate&limit=3'
```

#### Internal groups reject per-build attachment

Internal beta groups (`isInternalGroup: true`) cannot be assigned to specific builds — every valid build is automatically distributed to members based on their App Store Connect role. Attempting to POST returns:

```
422 ENTITY_UNPROCESSABLE
"Cannot add internal group to a build."
```

Filter internal groups out before iterating, or treat 422 with that title as a no-op:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/betaGroups?filter%5Bapp%5D=<APPLE_ID>' \
  | jq '.data[] | select(.attributes.isInternalGroup == false) | {id: .id, name: .attributes.name}'
```

#### External groups still need beta review to distribute

Attaching a build to an external group takes effect immediately on the relationship side, but Apple won't actually push the build to testers until the build's `betaAppReviewSubmission` is approved. Check status with:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions?filter%5Bbuild%5D=<BUILD_ID>'
```

### Polling for a Just-Uploaded Build

`--upload-package` returns a `Delivery UUID` immediately. That UUID **is** the ASC build id. Processing takes anywhere from ~30 s to ~30 min.

**Don't poll with `filter[version]`.** The list endpoint returns nothing while the build is `PROCESSING`, so a version-filter poll looks empty until processing finishes (seen on weather-range 2026.10.6.14.11). Poll the build directly by its id. A 404 for the first few seconds just means "not there yet". A **401/403 is an auth failure, not an absent build**. Stop on it: a poll that treats every non-200 as "keep waiting" looks like a 20-minute stall. The JWT expires after ~20 min, so re-mint inside the loop:

```bash
mint_token() {
  "${CLAUDE_PLUGIN_ROOT}/skills/appstore-connect/scripts/asc-jwt.py" --key-id "$KEY_ID" --issuer "$ISSUER"
}

BUILD_ID="$DELIVERY_UUID"
STATE=""
for i in $(seq 1 90); do
  TOKEN=$(mint_token)
  RESP=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $TOKEN" \
    "https://api.appstoreconnect.apple.com/v1/builds/$BUILD_ID?fields%5Bbuilds%5D=processingState")
  CODE=$(printf '%s' "$RESP" | tail -n1)
  case "$CODE" in
    200) STATE=$(printf '%s' "$RESP" | sed '$d' | jq -r '.data.attributes.processingState') ;;
    404) STATE="" ;;
    *) echo "HTTP $CODE: $(printf '%s' "$RESP" | sed '$d')" >&2; break ;;
  esac
  case "$STATE" in
    VALID) break ;;
    FAILED|INVALID) echo "processing $STATE" >&2; break ;;
  esac
  sleep 30
done
```

## Selecting Fields

Reduce response size by specifying only the fields needed:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=<APPLE_ID>&fields%5Bbuilds%5D=version,uploadedDate,processingState,minOsVersion&sort=-uploadedDate&limit=5'
```

## Pagination

The API returns paginated results. Follow `links.next` for additional pages:

```bash
RESPONSE=$(curl -s -H "Authorization: Bearer $TOKEN" '<URL>&limit=50')
NEXT=$(echo "$RESPONSE" | jq -r '.links.next // empty')
# Continue fetching with $NEXT until empty
```

## API Base URL

All endpoints use: `https://api.appstoreconnect.apple.com/v1/`

Full API documentation: https://developer.apple.com/documentation/appstoreconnectapi

## Common Pitfalls

### Don't name a bash array `GROUPS`

`GROUPS` is a built-in read-only bash array containing the current user's Unix group IDs. Assignments to it are silently ignored (no error even under `set -u`), so a script like:

```bash
GROUPS=(
  "uuid-1|Group One"
  "uuid-2|Group Two"
)
echo "${#GROUPS[@]}"   # prints 15 (or whatever, your group count), not 2
```

…will iterate over numeric Unix group IDs (`20`, `12`, `61`, …) and produce confusing 404s on the API. Use any other name (`BETA_GROUPS`, `GROUP_LIST`, etc.).

### Filter brackets must be URL-encoded

Bare `filter[app]=…` makes curl fail with `bad range`. Always `filter%5Bapp%5D=…`.
