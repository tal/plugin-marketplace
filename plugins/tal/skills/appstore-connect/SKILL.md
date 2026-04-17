---
name: appstore-connect
description: This skill should be used when the user asks about "App Store Connect", "altool", "xcrun altool", "upload to App Store", "submit to TestFlight", "validate app archive", "TestFlight builds", "list my apps", "check build status", "app store metadata", "app store text", "asset packs", "ASC API key", "generate JWT for App Store", "App Store Connect REST API", "IPA upload", or needs to interact with Apple's App Store Connect service via the command line. Also applicable when uploading, validating, or checking status of iOS/macOS/visionOS app submissions, or when querying TestFlight build information.
---

# App Store Connect CLI (altool)

`xcrun altool` is Apple's command-line tool for interacting with App Store Connect. It handles app uploads, validation, build status checks, metadata management, and JWT generation for the ASC REST API.

## Authentication

All commands except `--store-password-in-keychain-item` and `--generate-jwt` require authentication.

### API Key (Recommended)

```bash
xcrun altool <command> --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

The tool searches for `AuthKey_<KEY_ID>.p8` in order:
1. `./private_keys`
2. `~/private_keys`
3. `~/.private_keys`
4. `~/.appstoreconnect/private_keys`

Override with `$API_PRIVATE_KEYS_DIR` environment variable or pass explicitly via `--p8-file-path <path>`.

### Username / Password

```bash
xcrun altool <command> -u <apple_id> -p <password>
```

Password supports `@keychain:<item_name>` and `@env:<VAR_NAME>` prefixes. Store credentials with:
```bash
xcrun altool --store-password-in-keychain-item <name> -u <email> -p <password>
```

## Command Quick Reference

| Command | Purpose |
|---|---|
| `--upload-package` | Upload app archive (modern, supports `--wait`) |
| `--upload-app -f` | Upload app archive (legacy) |
| `--validate-app -f` | Validate archive without uploading |
| `--build-status` | Check processing status of a delivery |
| `--list-apps` | List all apps for account |
| `--list-providers` | List provider IDs for multi-team accounts |
| `--generate-jwt` | Mint a JWT for ASC REST API calls |
| `--app-store-text` | Download/upload localized App Store metadata |
| `--beta-app-store-text` | Download/upload TestFlight metadata |
| `--upload-asset-pack` | Upload on-demand resource pack |
| `--list-asset-packs` | List asset packs for an app |
| `--list-asset-pack-versions` | List versions of a specific asset pack |
| `--asset-pack-status` | Check asset pack processing status |
| `--store-password-in-keychain-item` | Save credentials to keychain |

For detailed syntax, flags, and examples for each command, consult **`references/commands.md`**.

## Global Options

- `--output-format {xml | json | normal}` — Structured output (default: `normal`)
- `--show-progress` — Display progress during uploads
- `--verbose` — Enable detailed logging
- `--wait` — Block until processing completes (supported by `--upload-package`, `--build-status`, `--upload-asset-pack`)

## Limitations and Workarounds

altool does **not** expose:
- TestFlight build listings or beta tester management
- App review status or submission management
- In-app purchase configuration
- App analytics or sales data

For these, mint a JWT with `--generate-jwt` and hit the ASC REST API directly with curl. See **`references/rest-api-workarounds.md`** for patterns including TestFlight build queries, with the URL-encoded bracket syntax required for filter parameters.

### Quick Example: Query TestFlight Builds

```bash
TOKEN=$(xcrun altool --generate-jwt --api-key <KEY_ID> --api-issuer <ISSUER_ID> 2>&1 | grep '^ey')
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=<APPLE_ID>&sort=-uploadedDate&limit=5'
```

Note: filter parameters use URL-encoded brackets (`%5B` / `%5D`) because bare `[` `]` cause curl to fail with "bad range" errors.

## Common Workflows

### Upload and Wait

```bash
xcrun altool --upload-package MyApp.ipa \
  -t ios --apple-id <APPLE_ID> --bundle-id <BUNDLE_ID> \
  --bundle-version "42" --bundle-short-version-string "2.0.0" \
  --wait --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

### Validate Before Upload

```bash
xcrun altool --validate-app -f MyApp.ipa \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

### Find Provider ID (Multi-Team Accounts)

```bash
xcrun altool --list-providers --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

Use the returned `--provider-public-id` with `--upload-package`.

### Download and Edit App Store Metadata

```bash
xcrun altool --app-store-text ./metadata --download \
  --apple-id <APPLE_ID> --bundle-short-version-string "2.0.0" -t ios \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
# Edit files in ./metadata/, then:
xcrun altool --app-store-text ./metadata --upload \
  --apple-id <APPLE_ID> --bundle-short-version-string "2.0.0" -t ios \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

### CI/CD Authentication

Write the API key from a CI secret to the expected path:
```bash
mkdir -p ./private_keys
echo "$ASC_API_KEY_CONTENT" > ./private_keys/AuthKey_${ASC_KEY_ID}.p8
xcrun altool --upload-package ... --api-key $ASC_KEY_ID --api-issuer $ASC_ISSUER_ID
```

## Additional Resources

### Reference Files

- **`references/commands.md`** — Complete command reference with all flags, parameters, and usage examples
- **`references/rest-api-workarounds.md`** — JWT + curl patterns for querying TestFlight builds, beta groups, and other ASC REST API endpoints that altool cannot access directly

### Supported Platforms

All platform-specific flags accept: `ios`, `macos`, `appletvos`, `visionos`
