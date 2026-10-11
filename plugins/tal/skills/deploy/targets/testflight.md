# Target: testflight

Ships an iOS build to TestFlight. Generic `altool`, JWT and REST mechanics live
in the `tal:appstore-connect` skill (`references/rest-api-workarounds.md` covers
JWT minting, URL-encoded filters and group attachment). This file adds only the
release flow and its landmines.

- **Channels:** `internal`, `external`, in promotion order.
- **Gate names** for `confirm_before`: `upload`, `beta-submit`, `external-attach`.
- **Artifact:** the ASC build id. It is the same UUID as the `Delivery UUID` that
  `--upload-package` prints.

## Required keys

| Key | Example | Notes |
|---|---|---|
| `app_id` | `"1234567890"` | Numeric Apple ID of the app (quote it) |
| `bundle_id` | `com.example.app` | |
| `team_id` | `ABCDE12345` | |
| `api_key_id` | `ABC123DEF4` | ASC API key id |
| `project` or `workspace` | `App.xcodeproj` | Use whichever exists: `-project <project>` or `-workspace <workspace>` below |
| `scheme` | `App` | |
| `export_options` | `ExportOptions-AppStore.plist` | `method` = `app-store-connect` |
| `beta_groups` (per channel) | `[{name, id, kind}]` | `kind`: `internal` / `external` |

Optional:

| Key | Default | Notes |
|---|---|---|
| `api_issuer_id` | from the `AuthKey_<api_key_id>.issuer-id` sidecar in `api_key_dir` | If there's no sidecar either, stop and ask |
| `api_key_dir` | `$HOME/.config/appstoreconnect/private_keys` | Written with `$HOME` (`~` doesn't expand inside the quotes below) |
| `release_gate` | none | Repo command run with the IPA path as its last argument. Non-zero = don't ship |
| `expected_bundles` | none | Paths inside `Payload/<App>.app` that must exist (e.g. `Watch/App_watch.app`) |
| `beta_review_submit` | `when-needed` | `when-needed` / `always` / `never` (see Ship step 7) |
| `whats_new_locale` | `en-US` | |
| `version_scheme` | `timestamp-dotted` | `timestamp-dotted` or `semver`. Refuse `git-sha`: CFBundleVersion must be dotted integers. See the first landmine |

```yaml
testflight:
  app_id: "1234567890"
  bundle_id: com.example.app
  team_id: ABCDE12345
  api_key_id: ABC123DEF4
  api_issuer_id: 00000000-0000-0000-0000-000000000000
  project: App.xcodeproj
  scheme: App
  export_options: ExportOptions-AppStore.plist
  release_gate: scripts/verify-release-ipa.sh
  channels:
    internal:
      beta_groups:
        - {name: App Store Connect Users, id: <uuid>, kind: internal}
    external:
      beta_groups:
        - {name: Public Beta, id: <uuid>, kind: external}
```

## Version bump

- `xcrun agvtool new-version -all <version>`. This needs
  `VERSIONING_SYSTEM = apple-generic`; otherwise set `CURRENT_PROJECT_VERSION`
  in `project.pbxproj`. It touches the `Info.plist`s and `project.pbxproj`, so
  pass `--expect '*Info.plist' --expect '*.pbxproj'` to `release-commit.sh`.
- Never change the marketing version here. Read it with
  `xcodebuild -showBuildSettings -scheme <scheme> | awk '/ MARKETING_VERSION /{print $3; exit}'`.
- Dirty runs use the same command and commit nothing. The plumbing restores the files afterward.

## Preflight

1. `export API_PRIVATE_KEYS_DIR="<api_key_dir>"`, because altool doesn't search
   `~/.config/…`. Check that `AuthKey_<api_key_id>.p8` exists.
2. Mint a JWT with an integer `exp` and make one read-only call with it:
   ```bash
   TOKEN=$("${CLAUDE_PLUGIN_ROOT}/skills/appstore-connect/scripts/asc-jwt.py" \
     --key-id <api_key_id> --issuer <api_issuer_id> --key-dir "<api_key_dir>")
   curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" \
     "https://api.appstoreconnect.apple.com/v1/apps/<app_id>?fields%5Bapps%5D=name"   # expect 200
   ```
   Anything but 200 is a key problem; stop. Re-mint every ~15 min during the
   run. Every REST call below uses this `$TOKEN`, and any 401/403 is an error,
   never "not there yet".
3. **The new build number must tuple-sort above every build on ASC**, not
   just above our tags. Don't trust "newest uploaded": a stray older upload
   can have the highest number. Fetch
   `GET /v1/builds?filter[app]=<app_id>&fields[builds]=version&limit=200`
   (with `curl -g` or `%5B`/`%5D`), follow `links.next`, and take the maximum
   `attributes.version` comparing as integer tuples split on dots. Stop if the
   new number isn't greater. Put the maximum in the plan.
4. Signing: `security find-identity -p codesigning`. Omit `-v`, which hides
   expired identities. With no local Apple Distribution identity,
   `-allowProvisioningUpdates` will **mint a new distribution certificate**.
   Apple caps how many you can hold, so check `GET /v1/certificates` for
   headroom and say so in the plan.
5. **Promotion check (external only).** If the newest `builds/testflight/internal/*`
   tag is newer than the newest external one, ask: **Promote internal
   `<version>`** or **Ship a new build**. Choosing Promote **declares a
   promotion run** (SKILL.md §5): skip step 3 above, and use that version.

## Ship

### New build

1. **Archive** outside the repo, so the tree stays clean for `tag.sh` and the
   archive shows up in Organizer. Use `-workspace <workspace>` in place of
   `-project` when the block sets `workspace`:
   ```bash
   ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%F)/<scheme> <version>.xcarchive"
   xcodebuild archive -project <project> -scheme <scheme> -configuration Release \
     -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
     -authenticationKeyPath "<api_key_dir>/AuthKey_<api_key_id>.p8" \
     -authenticationKeyID <api_key_id> -authenticationKeyIssuerID <api_issuer_id>
   plutil -p "$ARCHIVE/Info.plist" | grep -q ApplicationProperties   # missing → two top-level apps, stop
   ```
2. **Export** with the system `PATH` (Homebrew rsync breaks it) and API-key auth:
   ```bash
   EXPORT="$(mktemp -d)/export"
   env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath "$ARCHIVE" \
     -exportOptionsPlist <export_options> -exportPath "$EXPORT" -allowProvisioningUpdates \
     -authenticationKeyPath "<api_key_dir>/AuthKey_<api_key_id>.p8" \
     -authenticationKeyID <api_key_id> -authenticationKeyIssuerID <api_issuer_id>
   IPA=$(ls "$EXPORT"/*.ipa)
   ```
3. **Release gate.** This is the only working pre-flight, since `--validate-app`
   fails on nested watch apps.
   - Exactly **one** top-level app: `unzip -l "$IPA" | grep -cE ' Payload/[^/]+\.app/$'` must print `1`.
   - Every `expected_bundles` path exists under `Payload/<App>.app/`.
   - `<release_gate> "$IPA"` exits 0.
4. **Upload** (gate `upload`):
   ```bash
   xcrun altool --upload-package "$IPA" -t ios --apple-id <app_id> --bundle-id <bundle_id> \
     --bundle-version <version> --bundle-short-version-string <marketing version> \
     --api-key <api_key_id> --api-issuer <api_issuer_id>
   ```
   Record the `Delivery UUID`. It is the artifact and the ASC build id.
5. **Wait for processing.** Poll `GET /v1/builds/<id>` until
   `processingState=VALID`, re-minting the JWT every ~15 min. Don't poll
   `filter[version]`, which returns nothing while the build is `PROCESSING`.
6. **What's New.** `$NOTES` is the What's New text from the plan, unchanged
   (it also goes into the tag and the changelog).
   There is at most one localization per (build, locale): POST to create,
   PATCH to update.
   ```bash
   LOC_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
     "https://api.appstoreconnect.apple.com/v1/builds/$BUILD_ID/betaBuildLocalizations" \
     | jq -r --arg l "<whats_new_locale>" '.data[] | select(.attributes.locale==$l) | .id')
   if [ -z "$LOC_ID" ]; then
     curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
       -d "$(jq -n --arg w "$NOTES" --arg b "$BUILD_ID" --arg l "<whats_new_locale>" \
         '{data:{type:"betaBuildLocalizations",attributes:{locale:$l,whatsNew:$w},relationships:{build:{data:{type:"builds",id:$b}}}}}')" \
       https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations
   else
     curl -s -X PATCH -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
       -d "$(jq -n --arg w "$NOTES" --arg i "$LOC_ID" \
         '{data:{type:"betaBuildLocalizations",id:$i,attributes:{whatsNew:$w}}}')" \
       "https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations/$LOC_ID"
   fi
   ```
   `whatsNew` is limited to 4000 characters.
7. **Beta review submit** (gate `beta-submit`). `altool` only uploads: a build
   sitting at `READY_FOR_BETA_SUBMISSION` is shown to **no** tester, internal or
   external. Read `GET /v1/builds/<id>/buildBetaDetail`, then:
   - `when-needed`:
     - external: submit if `externalBuildState=READY_FOR_BETA_SUBMISSION`.
     - internal: submit only if `internalBuildState` hasn't reached
       `IN_BETA_TESTING` within 10 minutes after `VALID` (poll every 30 s).
       That's the new-version-train case; on an approved train, internal
       builds go live with no submit.
   - `always`: submit unless the build already has a submission.
   - `never`: skip.
   ```bash
   curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d "{\"data\":{\"type\":\"betaAppReviewSubmissions\",\"relationships\":{\"build\":{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}}}}}" \
     https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions
   ```
8. **External only: attach** (gate `external-attach`). Attach the build to every
   `kind: external` group with `POST /v1/betaGroups/<id>/relationships/builds`
   (recipe in `tal:appstore-connect`). Skip `kind: internal` groups: they
   auto-attach, and a per-build attach returns 422.
9. **External only: tag internal too** (clean runs only). A new build shipped
   to `external` reaches internal testers as well. Right after the plumbing's
   tag step, also run
   `tag.sh` for `builds/testflight/internal/<version>` on the same commit.
   Otherwise the next internal What's New re-lists everything in this build
   (weather-range's 2026.10.6.14.11 shipped to both groups but got only an
   external tag).

### Promotion (external, from an existing internal build)

Skip steps 1–5. The build id is the `Artifact:` line of the internal tag's
annotation (older tags say `ASC build id:`). Recompute What's New against
`builds/testflight/external/*` with `--head <internal tag's commit>`, so it
covers everything since external testers last got a build. PATCH it onto the
build (step 6); this replaces the internal notes on that build. Then run steps
7 and 8. The tag is `builds/testflight/external/<version>`, on the internal
tag's commit.

## Verify

- `processingState=VALID`.
- `buildBetaDetail`: internal → `internalBuildState=IN_BETA_TESTING`; external →
  `externalBuildState` is `IN_BETA_TESTING` or `BETA_APPROVED`.
  `WAITING_FOR_BETA_REVIEW` / `IN_BETA_REVIEW` count as **pending**, not failed:
  report them and note them in the changelog.
- `betaBuildLocalizations` carries the exact What's New text.
- External: every external group lists the build
  (`GET /v1/betaGroups/<id>/builds?sort=-uploadedDate&limit=3`).

## Rollback

TestFlight can't delete or un-upload a build. Instead, **expire** the bad one
(irreversible; always confirm first):

```bash
curl -s -X PATCH -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\",\"attributes\":{\"expired\":true}}}" \
  "https://api.appstoreconnect.apple.com/v1/builds/$BUILD_ID"
```

Testers fall back to the newest unexpired build, which the previous
`builds/testflight/<channel>/*` tag names. A fix ships as a new build with a
new number; never reuse one. The bad build's tag stays (tags are immutable).
Log the expiry in a changelog entry.

## Notes / landmines

- **Build numbers compare as integer tuples split on dots.** Never upload a
  non-dotted number: `20260404` outranks every `2026.M.D…` build, so TestFlight
  silently stops offering newer builds. `build-id.sh` and Preflight step 3 guard
  against this.
- **Opaque `409 STATE_ERROR.VALIDATION_ERROR` on upload → count the top-level
  `.app`s in the IPA first.** A watch target with `SKIP_INSTALL = NO` ships twice,
  once nested and once at the top level. Fix it with `SKIP_INSTALL = YES`. The tells:
  the archive lacks `ApplicationProperties` and lands under Organizer "Other Items";
  export fails with `exportOptionsPlist error for key "method" expected one {}`.
  Retrying a 409 is safe because nothing gets created.
- **Still a 409 with one app?** Read the real errors altool hides by running
  `swinfo` yourself:
  `…/Xcode.app/Contents/SharedFrameworks/ContentDelivery.framework/Resources/swinfo -f "$IPA" --platform ios -o /tmp/asset-desc.plist --plistFormat xml -temporary /tmp`,
  then print its `product-errors`. altool's own log is in
  `~/Library/Logs/ContentDelivery/com.apple.itunes.altool/`; grep it for `status code: 409`.
- **Unsigned SwiftPM resource bundles** (`product-errors` osstatus -67062): sign
  `*.bundle` directories inside the archived `.app`, deepest first, before export:
  `find "$APP" -name '*.bundle' -type d | awk '{print gsub(/\//,"/"), $0}' | sort -rn | cut -d' ' -f2- | while IFS= read -r b; do codesign --force --sign "$IDENT" "$b"; done`.
  This is only safe while those bundles contain no Mach-O.
- `exportArchive Copy failed` → Homebrew rsync is on `PATH`. Always export
  under `env PATH=/usr/bin:/bin:/usr/sbin:/sbin`.
- `No signing certificate "iOS Distribution" found` → you're missing
  `-allowProvisioningUpdates` plus the API-key auth flags.
- `Failed to load AuthKey file. (-43)` → `API_PRIVATE_KEYS_DIR` isn't set.
- Use `--upload-package`, never `--upload-app`. With a nested watch app,
  `--upload-app` fails `Cannot determine the platform`.
- `curl` URLs containing `[ ]` need `-g`, or curl says "bad range in URL". Unquoted, zsh also treats them as globs. Use `%5B`/`%5D` inside quotes.
- `altool --generate-jwt` tokens have a fractional `exp`. The REST API rejected one with 401 on 2026-07-11 and silently stalled a poll. Use `asc-jwt.py` (Preflight step 2).
- Don't route uploads through Transporter.app 1.4. It can't package Xcode 26 IPAs.
- Legacy history: older tags used `ASC build id:` in the annotation, and older bump
  commits used a `TestFlight-Channel:` trailer (set `bump_trailers` to keep it).
  The lightweight `builds/iosbeta/*` tags are retired; don't add to them.
