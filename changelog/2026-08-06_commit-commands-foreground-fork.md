# Commit commands: foreground execution with forked context

**Date:** 2026-08-06
**Scope:** `plugins/tal/commands/git/commit/{atomic,quick,staged}.md`, `plugins/tal/README.md`

## Problem

All three commit commands already carried `context: fork`, so their work stayed out of the
parent transcript. But they were also being detached into background agents — the user saw
`Running in the background as @<name>` instead of live progress, and the mandatory
"ask for rationale via AskUserQuestion" step could never fire, because a background agent
has no one to prompt.

## Root cause

Claude Code 2.1.223 decides foreground vs. background for a forked slash command with:

```js
function UWo(e, t) {
  if (t || Bv() || bn()) return false;  // model-invoked, CLAUDE_CODE_DISABLE_BACKGROUND_TASKS, or non-interactive
  return e.background ?? true;          // <-- forked commands default to BACKGROUND
}
```

`background` defaults to `true` for forked commands. When it resolves truthy the command goes
down `qWo(...)` (detached named agent); when falsy it goes down the synchronous path with
`isAsync: false`, streaming `agent_progress` into the main UI and returning
`<local-command-stdout>` to the parent turn.

So foreground + forked context is not a contradiction — it's `context: fork` + `background: false`.

## Changes

| File | Change |
| --- | --- |
| `commands/git/commit/atomic.md` | Added `background: false` |
| `commands/git/commit/quick.md` | Added `background: false`; added `AskUserQuestion` to `allowed-tools` |
| `commands/git/commit/staged.md` | Added `background: false`; added `AskUserQuestion` to `allowed-tools` |
| `README.md` | Documented the `context: fork` + `background: false` pairing under the Git commands section |

`quick.md` and `staged.md` both instruct "you MUST ask the user using AskUserQuestion" but
their `allowed-tools` allowlists omitted the tool, so the call would have been rejected even
in the foreground. Added it to both.

## Behavior after the change

- Command blocks the turn and streams progress inline instead of detaching.
- `AskUserQuestion` for rationale works.
- Context is still forked: intermediate tool calls and diffs stay in the sub-agent; only the
  final command output lands in the parent conversation.

## Relevant frontmatter fields

Beyond `description` / `model` / `allowed-tools` / `argument-hint`, the command frontmatter
parser also recognizes `context` (`fork` | `inline`, default `inline`), `background`,
`agent`, `effort`, `shell`, `paths`, `hooks`, `user-invocable`, and
`disable-model-invocation`.
