# altool Command Reference

Complete reference for all `xcrun altool` commands.

## Upload Commands

### --upload-package (Recommended)

Upload an app archive to App Store Connect.

```bash
xcrun altool --upload-package <file> \
  -t <platform> \
  --apple-id <APPLE_ID> \
  --bundle-id <BUNDLE_ID> \
  --bundle-version <CFBundleVersion> \
  --bundle-short-version-string <CFBundleShortVersionString> \
  --provider-public-id <PROVIDER_ID> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

**Parameters:**
- `-t, --platform` — `ios`, `macos`, `appletvos`, or `visionos`
- `--apple-id` — The Apple ID of the app (numeric, from App Store Connect)
- `--bundle-id` — The CFBundleIdentifier
- `--bundle-version` — The CFBundleVersion string
- `--bundle-short-version-string` — The marketing version (e.g. "2.0.0")
- `--provider-public-id` — Required when account belongs to multiple teams. Alternatives: `--team-id`, `--asc-public-id`
- `--wait` — Block until processing completes, then return build status

Returns a delivery ID on success, usable with `--build-status`.

### --upload-app (Legacy)

```bash
xcrun altool --upload-app -f <filepath> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

Legacy upload method. Prefer `--upload-package` for new integrations.

## Validation

### --validate-app

Validate an app archive against App Store requirements without uploading.

```bash
xcrun altool --validate-app -f <filepath> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

Run before uploading to catch issues early (icon requirements, entitlements, provisioning).

## Build Status

### --build-status

Check the processing status of a submitted build.

**By delivery ID** (returned from `--upload-package`):
```bash
xcrun altool --build-status --delivery-id <DELIVERY_ID> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

**By app + version** (for legacy uploads or when delivery ID unavailable):
```bash
xcrun altool --build-status \
  --apple-id <APPLE_ID> \
  --bundle-version <CFBundleVersion> \
  --bundle-short-version-string <version> \
  --platform <platform> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

Add `--wait` to poll until processing finishes.

## App and Provider Listing

### --list-apps

List all apps associated with the authenticated account.

```bash
xcrun altool --list-apps --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

**Filters:**
- `--filter-apple-id <id>`
- `--filter-bundle-id <id>`
- `--filter-name <name>`
- `--filter-sku <sku>`
- `--filter-platform {ios | macos | appletvos | visionos}`

For multi-team accounts, add `--provider-public-id <id>` to scope results.

### --list-providers

List provider IDs and team info for the authenticated account.

```bash
xcrun altool --list-providers --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

Use `--legacy` for the older output format. The returned provider public ID or team ID is needed for `--upload-package` on multi-team accounts.

## JWT Generation

### --generate-jwt

Generate a signed JWT token for use with the App Store Connect REST API.

```bash
xcrun altool --generate-jwt --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

Output includes a preamble line (`Running altool at path ...`) followed by the JWT string. Extract with:
```bash
TOKEN=$(xcrun altool --generate-jwt --api-key <KEY_ID> --api-issuer <ISSUER_ID> 2>&1 | grep '^ey')
```

The token is valid for 20 minutes. Use it with `Authorization: Bearer $TOKEN` for ASC REST API calls.

Additional options:
- `--auth-string <string>` — Pass the private key content directly
- `--p8-file-path <path>` — Explicit path to the `.p8` key file

## App Store Text (Metadata)

### --app-store-text

Download or upload localized App Store metadata: description, keywords, promotional text, what's new, support URL, marketing URL.

**Download:**
```bash
xcrun altool --app-store-text ./metadata --download \
  --apple-id <APPLE_ID> \
  --bundle-short-version-string "2.0.0" \
  -t ios \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

Creates a folder with per-locale files and a README.md with editing instructions.

**Upload:**
```bash
xcrun altool --app-store-text ./metadata --upload \
  --apple-id <APPLE_ID> \
  --bundle-short-version-string "2.0.0" \
  -t ios \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

### --beta-app-store-text

Same as `--app-store-text` but for TestFlight beta metadata. Same flags apply.

```bash
xcrun altool --beta-app-store-text ./beta-metadata --download \
  --apple-id <APPLE_ID> \
  --bundle-short-version-string "2.0.0" \
  -t ios \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

## Asset Pack Management

For apps using on-demand resources (ODR).

### --upload-asset-pack

```bash
xcrun altool --upload-asset-pack <filepath.aar> \
  --apple-id <APPLE_ID> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

Add `--wait` to block until status is READY, FAILED, or NULL.

### --asset-pack-status

Check processing status by version ID:
```bash
xcrun altool --asset-pack-status --asset-pack-version-id <UUID> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

Or by app + pack identifier + version:
```bash
xcrun altool --asset-pack-status \
  --apple-id <APPLE_ID> \
  --asset-pack-identifier <identifier> \
  --version <version> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

### --list-asset-packs

```bash
xcrun altool --list-asset-packs --apple-id <APPLE_ID> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

### --list-asset-pack-versions

```bash
xcrun altool --list-asset-pack-versions \
  --apple-id <APPLE_ID> \
  --asset-pack-identifier <identifier> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

## Credential Storage

### --store-password-in-keychain-item

Store App Store Connect credentials in the macOS keychain for use with `-p @keychain:<name>`.

```bash
xcrun altool --store-password-in-keychain-item <item_name> \
  -u <apple_id_email> -p <password>
```

Options:
- `--keychain <filename>` — Store in a specific keychain file
- `--sync` — Sync via iCloud Keychain (cannot combine with `--keychain`)

After storing, authenticate with:
```bash
xcrun altool <command> -p @keychain:<item_name>
```

The username is inferred from the keychain item, so `-u` can be omitted.

## Authentication Reference

### API Key Method

| Flag | Description |
|---|---|
| `--api-key <key_id>` | Key ID from App Store Connect |
| `--api-issuer <issuer_id>` | Issuer ID (UUID, shown at top of API keys page) |
| `--p8-file-path <path>` | Explicit path to `.p8` key file |
| `--auth-string <string>` | Raw private key content (between BEGIN/END lines) |
| `--api-key-subject user` | Required for individual JWT keys not prefixed `ApiKey_` |

### Username/Password Method

| Flag | Description |
|---|---|
| `-u, --username <email>` | Apple ID email |
| `-p, --password <password>` | Password, `@keychain:<name>`, or `@env:<VAR>` |

## Global Options

| Flag | Description |
|---|---|
| `--output-format {xml\|json\|normal}` | Output format (default: `normal`) |
| `--show-progress` | Display progress during operations |
| `--verbose` | Enable detailed logging |
| `--wait` | Block until processing completes |
| `--use-old-altool` | Fall back to legacy altool |
