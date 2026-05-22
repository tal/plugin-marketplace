# og-simplify

The resurrected `/simplify`. Claude Code shipped a bundled `/simplify` slash command that reviewed your changed code for reuse, quality, and efficiency and then **applied the fixes**. In v2.1.147 it was renamed to `/code-review` and the cleanup-and-fix behavior was removed — `/code-review` today is read-only bug reporting. This plugin brings the original auto-fixing behavior back, invoked as `/og-simplify`.

## What it does

Three phases, mirroring the original:

1. **Identify changes** — runs `git diff` (or `git diff HEAD` for staged changes); falls back to recently modified files when there's no diff.
2. **Launch three review agents in parallel** over the full diff:
   - **Code Reuse** — flags newly written code that duplicates existing utilities/helpers and suggests the existing one.
   - **Code Quality** — catches hacky patterns: redundant state, parameter sprawl, copy-paste-with-variation, leaky abstractions, stringly-typed code, unnecessary JSX nesting, deep nested conditionals, and noise comments.
   - **Efficiency** — catches unnecessary work, missed concurrency, hot-path bloat, recurring no-op updates, TOCTOU existence checks, memory leaks, and overly broad operations.
3. **Fix issues** — aggregates all findings and **applies the fixes directly** (skipping false positives), then summarizes what changed.

### Effort argument

Optional: `/og-simplify [low|medium|high|xhigh|max]`. The given effort is passed down so each of the three agents runs at that rigor/depth. An unrecognized value is ignored with a note; no argument runs at the session's current effort.

## Provenance

Recovered **verbatim** from the embedded prompt in the `@anthropic-ai/claude-code@2.1.146` native binary (the last release carrying the cleanup-and-fix behavior). In that build the command was already internally `name: "code-review", aliases: ["simplify"]`.

- Introduced: **v2.1.63** (`Added /simplify and /batch bundled slash commands`)
- Removed/renamed: **v2.1.147** (`Renamed /simplify to /code-review ... The old cleanup-and-fix behavior has been removed`)

## Install

### Claude Code

From inside Claude Code:

```
/plugin marketplace add tal/plugin-marketplace
/plugin install og-simplify@tal-marketplace
```

Or from the shell with the `claude` CLI:

```
claude plugin marketplace add tal/plugin-marketplace
claude plugin install og-simplify@tal-marketplace
```

Invoke it as the `/og-simplify` skill (it also triggers from natural-language requests like *"clean up the code I just changed"* or *"review my diff and fix what you find"*).

### Codex

```
codex plugin marketplace add tal/plugin-marketplace
codex plugin install og-simplify@tal-marketplace
```

## Skills

| Skill | What it does |
|---|---|
| `og-simplify` | The full original `/simplify` pipeline: diff → three parallel review agents (reuse / quality / efficiency) → aggregate and apply fixes. Takes an optional `[low\|medium\|high\|xhigh\|max]` effort argument. |
