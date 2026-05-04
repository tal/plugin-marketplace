# iconifier — todo

## Block on the preview UI instead of export-paste-back

Right now the apply flow is: build preview HTML → user clicks **Export selection** (downloads `iconifier-selection.json`) → user pastes the path back into chat → skill runs `apply_icons.py`. Two manual steps for the user, and the agent has to wait on chat input.

Steal plannotator's pattern: replace the static HTML + download with a small local HTTP server that serves the preview and blocks until the UI POSTs a selection back.

### How plannotator does it

`plannotator annotate <file>` (cached at `~/.claude/plugins/cache/plannotator/plannotator/0.15.0/`):

1. CLI starts an HTTP server (`startAnnotateServer`), opens the browser to it.
2. Server exposes a `waitForDecision()` promise that resolves when the UI POSTs the user's decision.
3. CLI awaits that promise, prints the result to stdout, exits.
4. The slash command captures stdout via the `!`bash`` mechanism — no chat round-trip needed.

See `server/index.ts:252-336` (the `annotate` branch) for the shape.

### Proposed change for iconifier

- Rewrite `build_preview.py` (or split into `serve_preview.py`) to use Python's stdlib `http.server`:
  - `GET /` → serves the preview HTML (current template, lightly modified).
  - `POST /submit` → accepts the selection JSON, writes 200, signals the main thread to shut down.
  - `POST /cancel` → user clicked a Cancel button, exits with non-zero.
  - Bind to `127.0.0.1` on a random free port (`socket.bind(("127.0.0.1", 0))` then read the assigned port).
  - Open browser via `webbrowser.open(f"http://127.0.0.1:{port}/")`.
  - Block on a single-shot event; on signal, print the selection JSON to stdout and exit 0.
- Replace the **Export selection** button in the HTML with **Apply selection** that does `fetch("/submit", { method: "POST", body: JSON.stringify({selection}) })` and shows a "applied — close this tab" message on success.
- Update SKILL.md step 7/8 to a single piped invocation:
  ```
  python3 serve_preview.py --manifest manifest.json | python3 apply_icons.py /dev/stdin
  ```
  (or stash to a tmp file and pass the path — `apply_icons.py` already takes a path, less plumbing).

### Edge cases to handle

- **User closes the tab without submitting.** Server should time out after N minutes, or expose a Cancel button that POSTs `/cancel`. Without this, the skill hangs forever.
- **Port already in use / firewall.** Random-port binding handles the first; the second is unlikely on localhost but worth a clear error if `webbrowser.open` fails or the user visits but the server isn't reachable.
- **Multiple concurrent runs.** Each invocation gets its own random port — fine.
- **Preview must work offline.** Already does (no external assets). Keep that.
- **Stop button / agent kill.** Make sure SIGTERM cleanly closes the server so we don't leave a zombie port-bind.

### Out of scope (mention but don't do)

- Replacing the HTML preview with a richer UI (regenerate buttons per card, inline emoji picker, drag-to-reorder). Nice-to-have, not why we'd do this.
- Persisting selections across runs. The whole point is one-shot — keep it that way.

### Why we haven't done this yet

The current export flow works and the round-trip cost is small for a < 30-folder run. But every time we ship a new feature in the preview (e.g. regenerate-with-notes), the export-and-confirm step gets clunkier. Worth doing before the next preview-side feature.

(As of 2026-05-04 the SKILL flow no longer asks the user to paste the path — it just confirms via `AskUserQuestion` and reads from `~/Downloads/iconifier-selection.json`. So the chat round-trip is one yes/no, not a path-paste. The HTTP-server pattern still wins on ergonomics — just less urgently.)
