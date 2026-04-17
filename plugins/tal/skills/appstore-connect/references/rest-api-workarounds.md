# ASC REST API Workarounds

altool cannot access TestFlight builds, beta testers, review status, or many other App Store Connect features. Use `--generate-jwt` to mint a token, then query the REST API directly with curl.

## Generating a JWT

```bash
TOKEN=$(xcrun altool --generate-jwt --api-key <KEY_ID> --api-issuer <ISSUER_ID> 2>&1 | grep '^ey')
```

The token is valid for ~20 minutes. All REST API calls use:
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
