---
argument-hint: [type] [scope] [rationale]
description: Quickly commit all changes with a well-formatted commit message
model: sonnet
context: fork
allowed-tools: Bash(git add:*), Bash(git commit:*), Bash(git log:*), TodoWrite, TodoRead
---

# Quick Commit

Be concise. Don't overthink. Act fast.

Arguments: $ARGUMENTS

## Current changes

Status:
!`git status --short`

Diff (unstaged + staged):
!`git diff`
!`git diff --staged`

## Instructions

All change data is above — do NOT run additional git commands to read changes or files.

### Step 1: Determine commit details

Infer type and scope from the diff. If arguments provide type/scope/rationale, use those. Types: feat, fix, refactor, docs, test, chore, style, perf.

**Rationale is required.** Use the first that applies:
- Rationale from arguments
- Rationale obvious from conversation context or the diff itself
- **Otherwise, you MUST ask the user** using AskUserQuestion: "What was the rationale for this change?" with brief context about what changed

### Step 2: Stage and commit (single command)

```bash
git add -A && git commit -m "$(cat <<'EOF'
<type>(<scope>): <short description>

- <what changed>
- <why it changed>

Rationale: <rationale for change>
EOF
)

This commit made by [/tal:git:commit:quick](https://github.com/tal/plugin-marketplace/tree/main/plugins/tal/commands/git/commit/quick.md)" && git log -1 --oneline --stat
```

If the commit fails, STOP and report the error.

### Step 3: Report

Tell the user the commit succeeded and remind them to push when ready. No additional commands needed.
