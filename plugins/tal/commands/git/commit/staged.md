---
argument-hint: [type] [scope] [rationale]
description: Quickly commit only staged changes with a well-formatted commit message
model: sonnet
context: fork
allowed-tools: Bash(git commit:*), Bash(git log:*), TodoWrite, TodoRead
---

# Staged Commit

Be concise. Don't overthink. Act fast.

Arguments: $ARGUMENTS

## Current changes

Status:
!`git status --short`

Diff (staged only):
!`git diff --staged`

## Instructions

All change data is above — do NOT run additional git commands to read changes or files. Only the staged diff is being committed; ignore unstaged changes entirely and do NOT stage anything new.

**If the staged diff is empty, STOP** and tell the user nothing is staged — suggest `/tal:git:commit:quick` if they want to commit everything.

### Step 1: Determine commit details

Infer type and scope from the staged diff. If arguments provide type/scope/rationale, use those. Types: feat, fix, refactor, docs, test, chore, style, perf.

**Rationale is required.** Use the first that applies:
- Rationale from arguments
- Rationale obvious from conversation context or the diff itself
- **Otherwise, you MUST ask the user** using AskUserQuestion: "What was the rationale for this change?" with brief context about what changed

### Step 2: Commit (single command, no staging)

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <short description>

- <what changed>
- <why it changed>

Rationale: <rationale for change>
EOF
)

This commit made by [/tal:git:commit:staged](https://github.com/tal/plugin-marketplace/tree/main/plugins/tal/commands/git/commit/staged.md)" && git log -1 --oneline --stat
```

If the commit fails, STOP and report the error.

### Step 3: Report

Tell the user the commit succeeded, mention any unstaged changes left behind, and remind them to push when ready. No additional commands needed.
