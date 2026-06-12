---
name: sort
description: Sort and organize an accumulating folder of files — defaults to the folder Claude Code was launched in (`~/Downloads`, `~/Desktop`, a project inbox, etc.). Trigger on `/sort`, when the user asks to "sort my downloads", "organize this folder", "clean up the desktop", "tidy this directory", "categorize these files", or complains about piled-up DMGs, zips, PDFs, screenshots, receipts, or installers — even when they don't say "sort". Dispatcher that classifies each item — videos, images (vision + OCR for returns/receipts/memes/screenshots/photos), archives, disk images, app bundles, documents — and routes to `<target>/AI Library/<topic>/`. Videos delegate to `/sort-videos`; documents go through the `documents.md` sub-dispatcher; everything else is handled inline. Auto-deletes installers whose app is already in `/Applications/`; otherwise never deletes without confirmation. User overrides via `sort.md` / `sort.local.md`. Pass a path or glob to process specific items.
user-invocable: true
context: fork
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - Skill
---

# Sort Files in Any Folder

Arguments passed: `$ARGUMENTS`

Dispatcher skill. Scans a target folder, classifies each item by type, and routes it to the right pipeline. Videos delegate to the `/sort-videos` skill (same plugin) via the Skill tool. Other types are handled inline here.

## Target folder resolution

The **target folder** is wherever the user wants sorting to happen. Resolve it in this order:

1. If `$ARGUMENTS` is an absolute or relative path to a directory, that's the target folder.
2. If `$ARGUMENTS` is a file path or glob, the target folder is the parent directory of those files.
3. Otherwise, the target folder is the **current working directory** — the folder Claude Code was launched in (`pwd` in Bash, or the dispatcher's session CWD). This is the common case: the user runs Claude in a folder they want tidied and types `/sort`.
4. If a `sort.md` / `sort.local.md` rule file sets `sources:` (see §0.5), that overrides the default — useful when the user always wants to sort one specific folder regardless of where they launched Claude.

The skill is **location-agnostic by design**. It works equally well on `~/Downloads`, `~/Desktop`, a project folder, a subfolder of Downloads, or anywhere else the user happens to be working.

## Output location

All output lands under `<target>/AI Library/` in topic subfolders. **Create that directory if it doesn't already exist** — `mkdir -p "<target>/AI Library"`.

**Discover existing topic folders at runtime** with `ls -1 "<target>/AI Library/"` and reuse them whenever the content fits — never hardcode topic names. Create a new topic folder only when nothing existing fits. This keeps the skill content-agnostic: each folder builds up its own taxonomy over time (from prior runs in that folder plus anything the user manually creates there), and the dispatcher simply respects whatever's already there. A `~/Downloads/AI Library` and a `~/Desktop/AI Library` can have completely different folder structures, and that's fine — they reflect what each location is used for.

## 0. Determine targets

After resolving the target folder (see "Target folder resolution" above), build the list of items to process:

**If `$ARGUMENTS` was a path or glob to specific files/dirs**, use those directly (absolute, relative from CWD, or glob expansion).

**If no arguments**, scan the target folder at the root level. If `<target>/Recents/` exists, scan it too — yt-dlp users sometimes have one. **Skip anything already inside `<target>/AI Library/`** — those are already sorted, and re-processing them risks renaming files the user has organized by hand.

Capture path, size, extension, and (for directories) whether it's a `.app` bundle. The size and extension feed classification in §1; the `.app` check matters because `.app` bundles are directories, not files, and need different handling than the app-installer disk images and zips that contain them.

## 0.5. Load user rules (before classification)

Users can override per-extension behavior, route specific filename patterns to fixed folders, suppress install prompts for tools they don't need, and tweak top-level settings (`sources`, `sensitive_dir`). The dispatcher reads **every** rule file that exists below and concatenates their `rules:` lists into one combined list, in this priority order:

1. `$PWD/.claude/sort.local.md` — project-local override (gitignored)
2. `$PWD/.claude/sort.md` — project-shared (committable)
3. `~/.claude/sort.local.md` — user-global override (gitignored)
4. `~/.claude/sort.md` — user-shared (could live in a dotfiles repo)

Resolution semantics:
- **For each file in the run**, walk the combined rule list top-to-bottom and take the first rule whose matcher fires. Lower-priority files don't get skipped because a higher-priority file exists — they only get overridden on rules that actually match the same file.
- **For top-level scalars** (`sources`, `sensitive_dir`), the highest-priority file that sets the key wins; the others are ignored for that key.
- **Within a single file**, rules apply in the order they're written — author the more specific patterns above the broader ones.

Each file is markdown with a YAML frontmatter block. Parse with whatever YAML reader is available — `yq` if installed, else use the bundled `${CLAUDE_PLUGIN_ROOT}/scripts/match-rules.rb --rules-only`, which reads all four rule files in priority order and prints the merged rules + top-level scalars (`sources`, `sensitive_dir`) as a structured listing the dispatcher can parse. For the schema, examples, and matcher/action lists, see `${CLAUDE_PLUGIN_ROOT}/skills/sort/OVERRIDES.md`. For interactive rule creation, the user can run `/sort:add-rule`.

Apply rules at every dispatcher decision point:
- Top-level `sources:` overrides the §0 default (current working directory). Use this when you always want to sort one specific folder regardless of where Claude was launched — e.g. a user who always sorts `~/Downloads` would put `sources: [~/Downloads, ~/Downloads/Recents]` in `~/.claude/sort.md`.
- Top-level `sensitive_dir:` overrides the prompt default in `documents.md` §4. Tilde expansion is supported. If unset, the dispatcher defaults to `<target>/AI Library/Sensitive/`.
- Per-file rules can short-circuit §1 classification, replace any pipeline section's routing decision, or skip the §0 tool prompt in `documents.md`.

### `action: prompt` rules

When a winning rule has `action: prompt`, hand the file off to the **`sort-route-by-prompt`** agent (defined in this plugin under `agents/sort-route-by-prompt.md`) instead of running default classification. The agent reads the file, applies the rule's `prompt:` text as its routing instructions, and replies with a single-line decision the dispatcher then executes.

Invoke it via the Agent tool with `subagent_type: "sort-route-by-prompt"`. The agent's contract (inputs, allowed reply forms, constraints) lives in its own definition file — don't restate it here. The dispatcher's job is just to assemble the inputs:

```
prompt: <rule.prompt verbatim>
file:   <absolute path>
target: <run target folder>
topics: <one folder per line, from `ls -1 "<target>/AI Library/"`>
note:   <rule.note if present, else omit>
```

Pass these as a structured block in the Agent invocation's prompt.

Apply the agent's reply the same way you'd apply a static rule of that action:

- `route: <path>` → move the file there (`AI Library/<Topic>/` shorthand resolves under `<target>`; create the folder if missing).
- `route_sensitive` → move to the run's resolved `sensitive_dir/`.
- `route_sensitive: <category>` → move to `<sensitive_dir>/<Category>/` where `<Category>` is the Title-Case form of the agent's category (`credentials → Credentials`, etc.). Create the subfolder if missing. The agent's allowed categories are listed in `agents/sort-route-by-prompt.md`.
- `delete` → delete the file. Report it in §5 with the rule reference.
- `skip` → leave the file alone.
- `fallthrough` → drop back to §1 classification for this file.

If the reply is malformed (more than one line, doesn't match the allowed forms), log a warning and treat as `ask`.

Batch parallelism: if multiple files match `action: prompt` rules, spawn the agents in parallel — they're independent. Show `prompt(<agent decision>)` in the §5 summary's `Action` column so the user can see the agent decided it.

Soft-fail behavior:
- No rule files present → continue with defaults silently.
- Bad YAML in a file → log one line naming the file, skip that file, continue with the others.
- Unknown rule keys → log + skip that single rule, continue.
- No YAML reader available → log one line, skip user rules entirely.

When a rule fires, record its source file and index. Include them in the §5 summary table's `Rule` column so the user can audit which override produced each routing decision.

## 1. Classify by type

Map each item to a type bucket:

| Extension / pattern | Type |
|---|---|
| `.mp4 .webm .mkv .avi .mov .flv .m4v .ts .wmv` | `video` |
| `.jpg .jpeg .png .gif .heic .webp .tiff .bmp .svg` | `image` |
| `.zip .tar .tar.gz .tgz .7z .rar` | `archive` |
| `.dmg .iso` | `disk-image` |
| `.pkg` | `installer` |
| `.app` (directory) | `app-bundle` |
| `.pdf .doc .docx .txt .md .rtf .epub` | `document` |
| `.webloc .url` link file, or pasted text containing an `instagram.com/p/` or `/reel/` URL | `instagram-link` |
| 3+ loose images sharing an Instagram-shortcode stem (`<code>_1.jpg … <code>_5.jpg`) or a folder named after a shortcode | `image-carousel` |
| anything else | `unknown` |

## 2. Dispatch by type

Process each bucket independently. Buckets can run in parallel where they don't share state.

### Videos → delegate to `/sort-videos`

For every `video` item, invoke the `sort-videos` skill via the Skill tool, passing the path as the argument. Do not re-implement transcription, OCR, talk detection, or markdown generation here — sort-videos owns that pipeline end-to-end.

`sort-videos` declares `context: fork` in its frontmatter, so each invocation runs in its own forked subagent. The dispatcher's context only sees the skill's reply, not the transcription / OCR / summary working details. No need to spawn an Agent manually — the fork happens at skill invocation.

If there are many videos, invoke sort-videos once per path (or pass a glob if that fits the user's request).

### Instagram carousels & link files → delegate to `/sort-images`

Two buckets route here, both via the Skill tool to the `sort-images` skill (same plugin):

- **`instagram-link`** — a `.webloc`/`.url` shortcut file or pasted text holding an `instagram.com/p/<shortcode>/` (or `/reel/`) URL. Pass the URL as the argument; `sort-images` downloads the slides with gallery-dl, OCRs them, and files them under `<target>/AI Library/`.
- **`image-carousel`** — a group of already-downloaded slides (a shortcode-named folder, or 3+ loose images sharing a `<shortcode>_N` stem). Pass the folder or glob; `sort-images` OCRs them in place and files them under `<target>/AI Library/`.

Don't re-implement download/OCR/summarization here — `sort-images` owns that pipeline end-to-end and lands its artifacts (the renamed slides plus a companion `.md`) in a topic subfolder of `<target>/AI Library/`, exactly like the other pipelines. Like `/sort-videos`, it declares `context: fork`, so each invocation runs in its own subagent and only the reply returns to the dispatcher.

If gallery-dl turns out to be missing and the user declines installing it, `sort-images` reports the carousel as skipped — surface that in the §5 summary rather than retrying here.

Note: a **single loose image** is not a carousel — it stays in the `image` bucket below. Only grouped slides / Instagram links come here.

### Images

For each image (loose file, or an image extracted from a zip group — see Archives), the goal is to identify *what the image actually is* before routing — filename and EXIF heuristics alone routinely misfile things like return labels, receipts, and shipping artifacts as memes. **Always look at the image content (vision + OCR) before falling back to heuristics.**

**(a) Cheap shortcut — filename-prefix screenshots only.** If the filename starts with `Screen Shot`, `Screenshot`, `CleanShot`, or `Shottr`, route to `<target>/AI Library/Screenshots/` and skip the vision pass. These are unambiguous and high-volume; analyzing them every run is wasteful.

**(b) Vision + OCR analysis for every other image.** For 1–3 loose images, Read each directly — the model is multimodal and can see both visual content and any embedded text in a single Read call. For larger batches, spawn one or more `general-purpose` Agents and pack multiple image paths into each prompt to amortize the per-call overhead (rule of thumb: ~10 images per Agent call, parallel Agents when total count is large). Whichever path you take, the analysis should treat the image as both visual scene + OCR target, and classify it into one of these content categories:

- **Return code / shipping label** — image contains a QR code, barcode-with-tracking-number, RMA card, drop-off receipt, packing slip, or any other logistics artifact (Amazon Return Summary Cards, UPS/USPS/FedEx/DHL labels). Route to `<target>/AI Library/Returns/`. **Any QR code present is sufficient on its own** — QR-code-bearing images are essentially never memes or photos in this workflow.
- **Receipt / invoice scan** — printed receipt or invoice photographed or scanned. Route to `<target>/AI Library/Receipts/`.
- **Screenshot of UI / app / chart** — desktop or mobile UI capture, dashboard, error dialog, code snippet, web page. Route to `<target>/AI Library/Screenshots/` unless the content clearly fits a more specific existing topic (e.g. a finance chart into a finance-related folder).
- **Meme / reaction image** — recognizable meme template, captioned reaction, joke graphic, web-sourced low-res image with no QR/label/receipt content. Route to `<target>/AI Library/Memes/`.
- **Photo / topic-tagged content** — anything else (real-world photo, illustration, diagram). Tag with a topic that matches existing folders under `<target>/AI Library/`, or propose a new 2–3 word Title Case topic if nothing fits. Route to `<target>/AI Library/<Topic>/`.

Suggested prompt / reply format for the Agent:

```
Look at this image at <path>. Use both the visual content and any text visible
in the image (OCR). Classify it into one of these categories: return, receipt,
screenshot, meme, photo, other. If photo or other, also pick a topic that
matches one of these existing folders if possible: <list of folders under
<target>/AI Library/>; if none fit, propose a new 2–3 word Title Case topic.

Reply with JSON: {
  "category": "return|receipt|screenshot|meme|photo|other",
  "topic": "<existing or new topic, only when category is photo or other>",
  "reuse": true|false,
  "ocr_summary": "<one-line description of any visible text — empty string if none>",
  "description": "<one-line summary of what the image is>"
}
```

Always include `ocr_summary` so visible text feeds the routing decision (return-card numbers, "The UPS Store", "Amazon", merchant names on receipts, etc.). For zip-bundled images, see Archives for grouping rules.

**(c) Fallback when no vision is available.** If for some reason no vision-capable tool is reachable (no Agent, no multimodal Read), fall back to the legacy heuristics: meme = no EXIF + dimensions < 1200px on both axes + random/web filename; photo = EXIF camera Make + Model present (`sips -g make -g model "<file>"` or `exiftool`); everything else → `<target>/AI Library/Review/`. Note in the §5 summary which images used this fallback so the user can spot-check.

### Archives (zip, tar.gz, 7z, rar)

Peek at contents — do not extract blindly:

- `.zip`: `unzip -l "<file>"`
- `.tar.gz` / `.tgz`: `tar -tzf "<file>"`
- `.tar`: `tar -tf "<file>"`
- `.7z`: `7z l "<file>"`
- `.rar`: `unrar l "<file>"` (or `7z l` if unrar isn't installed)

Classify the archive from the listing:

- **Contains a `.app` at the top level (or within one subdirectory)** → app installer. Extract into a temp dir (`/tmp/sort-extract-<basename>/`), run the app-bundle pipeline on the extracted `.app`, then:
  - If the extracted app's bundle ID already matches something in `/Applications/` → **delete the original archive** (`.zip`, `.7z`, `.tar.gz`, `.rar`, etc.) and remove the temp extraction. Same auto-delete rule as DMGs.
  - Otherwise move the original archive alongside the app's destination topic folder, and clean up the temp extraction.
- **Mostly images** (≥ 70% of entries have image extensions) → image group. Extract a 1-2 image sample to a temp dir, run topic tagging on the sample (see Images §b) to pick a topic, then extract the whole archive into `<target>/AI Library/<Topic>/<zip-basename>/`. Keep the original archive inside that same folder.
- **Single document** (exactly one entry whose extension is in the document bucket — `.pdf .doc .docx .epub`) → unwrap and treat the inner file as a document. Extract into a temp dir, run that single file through the documents-pipeline subagent (same prompt as the `### Documents` section), and route the extracted file to whatever destination it classifies into. Move the original archive into the same destination folder so nothing is silently discarded — the user can clean up duplicates later. Don't ask.
- **Mixed or unclear** (mix of docs, code, images, etc.) → ask via AskUserQuestion for this specific archive with options: treat as app installer, treat as image group, treat as document archive (extract into `AI Library/Review/<zip-basename>/`), or skip.

### Disk images (.dmg, .iso)

Mount read-only, inspect, then detach:

```
hdiutil attach -nobrowse -readonly "<file>" -mountpoint "/tmp/sort-mount-<basename>"
```

Find `.app` or `.pkg` inside the mount point. Run the app-bundle pipeline (for `.app`) or installer handling (for `.pkg`) on the mounted copy, then decide the fate of the original disk-image file:

- If the app's bundle ID already matches something in `/Applications/` → **delete the `.dmg`/`.iso`** after detaching. Same auto-delete rule as zip installers.
- Otherwise move the `.dmg`/`.iso` into the chosen topic folder (next to where the app would be installed).

Detach before deleting/moving:

```
hdiutil detach "/tmp/sort-mount-<basename>"
```

Always detach on both success and failure (use a trap / cleanup step).

### App bundles (.app)

Read bundle ID and version:

```
defaults read "<path>/Contents/Info.plist" CFBundleIdentifier
defaults read "<path>/Contents/Info.plist" CFBundleShortVersionString
```

Check whether that bundle ID is already installed:

```
mdfind -onlyin /Applications "kMDItemCFBundleIdentifier == '<bundle-id>'"
```

Fall back to matching on `.app` name if `mdfind` returns nothing (Spotlight may be indexing).

- **Already installed in `/Applications/`** — installer/source was a DMG, disk image, or zip:
  - **Delete the installer file** (`.dmg`, `.iso`, `.zip`, etc.). This is the only auto-delete case the user authorized.
  - Report the deletion in the summary.
  - If the app was a loose `.app` bundle in the target folder (not inside an installer), do **not** delete — move it to `<target>/AI Library/Apps/_duplicates/` for manual review instead.
- **Not installed** — move the installer (DMG, zip, or the loose `.app`) to a topic folder. Prefer an existing folder that fits the app's purpose (a DAW → a music-related folder if one exists, a dev tool → a tech-related folder, a game → a games folder, etc.) — discover the user's folders at runtime, don't guess names. If nothing fits, use `<target>/AI Library/Apps/`.

### `.pkg` installers

Treat like a DMG:
- If the installed package already matches an existing app in `/Applications/` (check via `pkgutil --pkgs | grep -i <basename>` and cross-reference receipts), delete the `.pkg`.
- Otherwise move to the same topic folder as an unmounted app would go.
- When uncertain about what a `.pkg` installs, ask via AskUserQuestion.

### Documents → see `documents.md`

For any item in the `document` bucket (`.pdf .doc .docx .txt .md .rtf .epub`), follow the procedure in `${CLAUDE_PLUGIN_ROOT}/skills/sort/documents.md`. Read it on demand — only when the run actually contains documents. That file is a sub-dispatcher: it owns text extraction, vision fallback for scanned PDFs, sensitivity routing, and confidence-based fallthrough to Review/.

The whole `/sort` skill runs forked (`context: fork` in frontmatter), so document classification work — pdftotext extracts, agent calls — already lives in an isolated context relative to the user's parent conversation. No additional forking needed inside the doc path.

Don't re-implement that logic here. The dispatcher's only job for documents is to hand the path off and incorporate the result into the summary table (§5).

### Unknown files

Anything that didn't match a type bucket (`.json`, `.torrent`, `.spk`, `.ipsw`, etc.) is normally moved to `<target>/AI Library/Review/` for manual triage — these don't have a portable inspection method.

**Sensitive-name default**: before routing to Review/, check the basename (case-insensitive) against this regex:

```
(recovery|backup-codes?|\.env|credentials|secret|private-key|api-key|api_key|recovery-kit|\.pem$|\.key$|id_rsa|id_ed25519)
```

If it matches, route to `<sensitive_dir>/Credentials/` (not the top-level `<sensitive_dir>/`) — by construction this regex only matches credential material (recovery keys, dotenv files, SSH/API keys), so the subcategory is already known. Create the `Credentials/` subfolder if missing. This default fires only if no §0.5 user rule already fired for the file (rules always take priority). Users who don't want this default can add a rule with `match: { phase: unknown-sensitive-default } action: skip`.

## 3. Ask when uncertain

When type or topic classification is weak, conflicting, or ambiguous, use AskUserQuestion. Examples:

- An archive whose contents don't cleanly match any of the classification rules
- An image where the vision pass (§Images §b) returns low confidence, an unrecognized category, or no good topic match — or where the heuristic fallback (§c) had to be used and the result feels uncertain
- A `.pkg` whose target app can't be inferred
- A file type not in the extension table (when there's only one or two)

**Batch ambiguous items into a single AskUserQuestion call per run** — interrupting one-by-one across many files trains the user to mash through the prompts and degrades signal. Group the uncertain ones and present them together (e.g., one question with 2-4 files per option, or a multiSelect question for categorizing a list).

Never delete without explicit confirmation, **except** the installer-already-installed case spelled out above. Deletion is the only irreversible action; everything else can be undone by moving files back.

## 4. Parallel processing

- Type classification is cheap — run it serially across all items.
- Dispatch can run in parallel across buckets:
  - Videos delegate to `/sort-videos` which has its own parallel transcription.
  - Images: prefer batching multiple images into a single Agent prompt (see §Images §b) to amortize overhead. Multiple such Agent calls can run in parallel when image counts are high. Single-image runs can use a direct multimodal Read instead of an Agent.
  - Archive peeks (`unzip -l` etc.) run in parallel.
  - DMG mounts run serially (hdiutil is global state).
  - Documents follow `documents.md`, which extracts text in parallel and fires Agent classification in parallel.

## 5. Report

Print a summary table:

| File | Type | Destination | Action | Rule |
|---|---|---|---|---|

- `Type` — `video`, `image`, `image-carousel`, `instagram-link`, `archive`, `disk-image`, `installer`, `app-bundle`, `document`, `unknown`
- `Action` — `moved`, `extracted`, `delegated` (to `/sort-videos` or `/sort-images`), `deleted` (installer-dedup or `action: delete` rule), `mounted+moved`, `classified` / `classified-sensitive(<Category>)` / `review` / `error` (from `documents.md`), `prompt(<agent decision>)` (an `action: prompt` rule fired and the agent's chosen action is in parens), or `skipped`. For images, append `(vision)` when the §Images §b vision/OCR pass produced the routing, or `(fallback)` when §c heuristics were used because no vision tool was reachable — the user wants to spot-check fallback rows. For sensitive items, `<Category>` is one of `Credentials | Identity | Financial | Medical | Legal | Other` and tells the user which subfolder of `<sensitive_dir>/` it landed in.
- `Rule` — when a §0.5 user rule fired, show `<file>:<index>` (e.g. `~/.claude/sort.local.md:1`); blank when defaults applied

Also list:
- Files sent to `AI Library/Review/` for manual triage
- Installers auto-deleted (with the matching `/Applications/` app name)
- Any errors (mount failures, corrupt archives, extraction failures)
