# Documents (sub-dispatcher, read on demand by sort/SKILL.md)

Loaded with the Read tool only when the current run contains items in the `document` bucket (`.pdf .doc .docx .txt .md .rtf .epub`). Do not pre-load.

This is a small dispatcher: extract classifiable signal from each file, hand it to a single Agent call per file, route by the agent's reply. Folder taxonomy is discovered at runtime — **never hardcode topic names**. This file ships with the plugin and runs against arbitrary user folders.

The parent `/sort` skill declares `context: fork` so this whole pipeline runs in an isolated subagent — pdftotext output, classification agent calls, etc. don't bloat the user's parent conversation. No additional forking is needed inside this file.

## 0. Tool detection and install prompt (once per run)

Run before processing any document. The doc phase relies on these tools:

| Tool | Package | Used for |
|---|---|---|
| `pdftotext` | poppler | PDF → text excerpt |
| `pdftoppm` | poppler (same package) | PDF page 1 → PNG for the vision fallback |
| `pandoc` | pandoc | `.epub` → plaintext (also a `textutil` fallback for `.doc/.docx/.rtf`) |
| `textutil` | macOS built-in | `.doc/.docx/.rtf` → plaintext |

### Probe

```bash
missing=()
command -v pdftotext >/dev/null 2>&1 || missing+=(poppler)
command -v pandoc    >/dev/null 2>&1 || missing+=(pandoc)
```

If `missing` is empty, continue to §1.

### Detect a package manager

```bash
if   command -v brew    >/dev/null 2>&1; then mgr=brew    install_cmd="brew install"
elif command -v apt-get >/dev/null 2>&1; then mgr=apt     install_cmd="sudo apt-get install -y"
elif command -v dnf     >/dev/null 2>&1; then mgr=dnf     install_cmd="sudo dnf install -y"
elif command -v port    >/dev/null 2>&1; then mgr=port    install_cmd="sudo port install"
else mgr=none
fi
```

Package name per manager:

| | brew | apt | dnf | port |
|---|---|---|---|---|
| poppler | `poppler` | `poppler-utils` | `poppler-utils` | `poppler` |
| pandoc | `pandoc` | `pandoc` | `pandoc` | `pandoc` |

### Prompt

If `mgr` is `none`, skip the prompt and go straight to degraded mode (§Degraded). Print the manual install command (e.g. `brew install poppler pandoc`) so the user can install it themselves later.

Otherwise, ask **one** AskUserQuestion combining all missing packages:

```
question: "Document classification needs <missing list>. Install with <install_cmd> now?"
header: "Install tools"
options:
  - "Install now"                    — run install_cmd, then proceed
  - "Skip — degraded mode"           — continue; affected files fall through to Review/
  - "Cancel document processing"     — skip the doc bucket entirely; other buckets still run
```

Don't ask per tool. Don't ask per file. One prompt covers the whole run.

### After "Install now"

Run the install with Bash. After it finishes, re-probe with `command -v` and verify the binaries exist. If verification fails, fall through to degraded mode rather than retrying or asking again. Print one line summarizing what got installed and what didn't.

Never run an installer the user didn't approve in this run, even if a previous run approved it.

### Degraded mode

| Missing | Effect |
|---|---|
| `pdftotext` only | use `pdftoppm` to render page 1 and treat every PDF as scanned (vision agent on every PDF) |
| `pdftoppm` only | use `pdftotext`; PDFs with < 200 chars of text go to Review/ |
| both poppler tools | filename-only routing — send the basename alone to the agent. Most replies will be low-confidence and end up in the run-end batch question (§3 of `SKILL.md`). |
| `pandoc` | `.epub` files go to Review/ |
| `textutil` (only matters off macOS) | `.doc/.docx/.rtf` use `pandoc` if present, else Review/ |

Print one line at the start of the doc phase summarizing what's degraded, e.g. `Doc phase: poppler missing → filename-only mode for PDFs.`

## 1. Discover the folder list (once per run)

The dispatcher passes the **target folder** (`<target>`) into the doc phase — typically the folder Claude Code was launched in, or whatever folder the user is sorting. Discover topic folders inside `<target>/AI Library/`:

```bash
ls -1 "<target>/AI Library/" 2>/dev/null | grep -vE '^(Review|_|\.)'
```

Pass this list to every Agent call as the "reuse if fits" set. Do not supply a default. If `<target>/AI Library/` doesn't exist yet, the list is empty — the agent will propose new folder names.

## 2. Extract signal from each file (parallel across files)

| Type | Command |
|---|---|
| `.pdf` | `pdftotext -l 2 -nopgbrk "$f" -` capped at ~4KB. If output < 200 chars, render page 1: `pdftoppm -f 1 -l 1 -r 100 -png "$f" /tmp/sort-doc-<n>` and tag as a vision input. |
| `.doc .docx .rtf` | `textutil -convert txt -stdout "$f"` → first ~4KB |
| `.txt .md` | `head -c 4096 "$f"` |
| `.epub` | `pandoc -t plain "$f" 2>/dev/null | head -c 4096` |

Always include the basename in the agent input — filename is often the strongest signal, and the only one available when extraction fails.

## 3. Agent call (one per file, parallel)

Use the `general-purpose` subagent. Prompt template:

```
You will classify a document for filing.

Filename: <basename>
Type: <pdf | docx | epub | txt | ...>
Excerpt (first ~4KB, or "[scanned — see attached image]"):
<text>

Existing topic folders the user already uses:
<list from §1>

Tasks:
1. Pick a destination folder. If an existing one fits, set "reuse": true. Otherwise propose
   a new folder name in Title Case (1-3 words). Folder names should describe the kind of
   document (e.g. "Invoices", "Contracts", "Research") — do not invent personal labels.
2. Decide if the document contains personally sensitive content: signed legal contracts,
   medical records, financial statements with account numbers, recovery keys / credentials,
   government IDs, or anything a reasonable person would file away from casual access.
3. Rate your confidence in the topic choice from 0.0 to 1.0.

Reply with JSON only:
{
  "topic": "...",
  "reuse": true | false,
  "sensitive": true | false,
  "confidence": 0.0-1.0,
  "description": "one sentence on what the document is"
}
```

When a vision input is used, attach the rendered PNG and pass `[scanned — see attached image]` as the excerpt.

## 4. Route by reply

- `sensitive: true` → `<sensitive_dir>`. Resolve `<sensitive_dir>` once per run: prefer the value from `~/.claude/sort.local.md` / `sort.md` (§0.5 of `SKILL.md`), otherwise the first sensitive item triggers a single AskUserQuestion offering `<target>/AI Library/Sensitive/` (default), `~/Documents/Sensitive/`, or a custom path. Cache the answer for the rest of the run.
- `confidence < 0.5` → defer. Add the file to the run-end batch AskUserQuestion (same batching rule as `SKILL.md` §3) instead of forcing Review/ immediately.
- Otherwise → `<target>/AI Library/<topic>/`. Create the folder if it doesn't exist.

Never overwrite an existing destination file silently — append a `-2`, `-3`, etc. suffix on collision.

On destination-name collisions, append `-2`, `-3`, etc. — never overwrite silently.

## 5. Fallthroughs

- Both poppler tools missing → filename-only mode: send the basename alone to the agent. Most replies will be low-confidence and end up in the run-end batch AskUserQuestion. That's the intended degradation.
- Agent returns malformed JSON, or the call errors → Review/.
- Empty extract AND no vision tool available → Review/.
- Files outside the document extension table (`.json`, `.torrent`, `.spk`, etc.) are not handled here — they stay in `SKILL.md`'s `unknown` bucket and route to Review/.

## 6. Report contribution

For each document, return one row to the dispatcher's summary with one of these Action values:

- `classified` — moved to a topic folder
- `classified-sensitive` — moved to the sensitive folder
- `review` — fell through to Review/ (extraction failure, low confidence with no batch resolution, malformed reply)
- `error` — tool or agent failure; include a short reason
