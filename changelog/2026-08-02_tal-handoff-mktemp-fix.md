# 2026-08-02 — Fix `handoff` skill producing unfindable temp files

## Problem

The `tal:handoff` skill instructed agents to save the handoff document to a path from:

```bash
mktemp -t handoff-XXXXXX.md
```

On macOS (BSD `mktemp`) this is doubly broken:

- `-t` treats its argument as a **bare prefix**, not a template — the `XXXXXX` is never substituted
- the random suffix is appended to the *end*, so the file does not end in `.md`

Real output observed: `/var/folders/.../T/handoff-XXXXXX.md.NTDYvSar3c`

Result: a real handoff document written by a past session was effectively unfindable — it did not match `handoff-*.md`, and the user could not locate it.

## Root cause

`mktemp` only substitutes `X`s that are **trailing** in the template. Any suffix after them (`.md`) suppresses substitution entirely. This affects the obvious "fix" too — `mktemp "$TMPDIR/handoff-XXXXXX.md"` fails the same way:

| Form | macOS result |
|---|---|
| `mktemp -t handoff-XXXXXX.md` | `handoff-XXXXXX.md.NTDYvSar3c` ❌ |
| `mktemp "$TMPDIR/handoff-XXXXXX.md"` | `handoff-XXXXXX.md` (literal Xs) ❌ |
| `mktemp -d "$TMPDIR/handoff-XXXXXX"` + fixed filename | `handoff-3lfSLG/handoff.md` ✅ (extra dir) |
| `mktemp "$TMPDIR/handoff-XXXXXX"` + rename | `handoff-mtJjnw.md` ✅ |

## Change

`plugins/tal/skills/handoff/SKILL.md` now specifies the trailing-`X`-plus-rename form, which works on both BSD and GNU `mktemp`:

```bash
t=$(mktemp "${TMPDIR:-/tmp}/handoff-XXXXXX") && mv "$t" "$t.md" && echo "$t.md"
```

Also added:

- an explanatory note so a future agent doesn't "simplify" the rename back out
- an instruction to **report the full path to the user** in the final message — the actual UX failure was that the path was never surfaced, so even a correctly-named file would have been hard to find

## Verification

Both forms executed on macOS 25.5.0 / zsh; outputs recorded in the table above.
