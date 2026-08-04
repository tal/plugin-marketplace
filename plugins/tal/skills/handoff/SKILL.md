---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up. Invoke explicitly via /handoff or /tal:handoff — do not auto-invoke.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work.

Create the file with:

```bash
t=$(mktemp "${TMPDIR:-/tmp}/handoff-XXXXXX") && mv "$t" "$t.md" && echo "$t.md"
```

Write to the path that prints (read the file before you write to it).

The rename is required, not decorative: `mktemp` only substitutes `X`s that are *trailing*, and BSD/macOS `mktemp -t` treats its argument as a bare prefix. Both `mktemp -t handoff-XXXXXX.md` and `mktemp .../handoff-XXXXXX.md` produce a file with a literal `XXXXXX` in the name and no `.md` extension.

Report the full path back to the user in your final message so they can find the document later.

Suggest the skills to be used, if any, by the next session.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
