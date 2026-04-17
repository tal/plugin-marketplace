---
name: get-pr-feedback
description: This skill should be used when the user asks to "get PR feedback", "fetch review comments", "show PR comments", "what did reviewers say", "check PR reviews", "address PR feedback", "retrieve PR feedback", or mentions PR review analysis, comment threads, or reviewer feedback. Also invoke when the user provides a GitHub PR comment URL (e.g., https://github.com/org/repo/pull/123#discussion_r456) to fetch that specific comment thread. Provides comprehensive structured access to PR review comments with full conversation context, author information, and thread resolution status.
---

# Get PR Feedback

Fetch PR review comments from GitHub as structured threads with conversation context.

## Flags Quick Reference

- **`-a`** : Show only actionable threads (unresolved + not outdated) - **recommended for most use cases**
- **`-f`** : Full mode with diff_hunk fields (default: compact without diff_hunks)
- **`-o`** : Sort oldest-first (default: newest-first for most relevant feedback)
- **`-v`** : Verbose diagnostic output to stderr

## Why Use This Skill

Provides structured access to PR review comment threads with accurate resolution and outdated status that is not easily available through basic `gh pr view` commands. It:

- Fetches ALL review comment threads with full conversation context
- Tracks resolved/outdated status (requires GraphQL API)
- Organizes comments into threads for easy navigation
- Returns structured JSON for programmatic filtering
- Auto-detects PR from current branch or accepts explicit PR/comment URLs

**Prefer this over**:
- `gh pr view --comments` (doesn't show threaded conversations or resolution status)
- `gh api` calls (requires manual GraphQL query construction)
- Manual web browsing (not automatable)

## Quick Start

**Most common usage** (auto-detect PR from current branch, compact by default):
```bash
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh
```

**Actionable threads only** (recommended - filters to unresolved + not outdated):
```bash
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh -a
```

**Full mode with diff_hunks** (opt-in to include code context, increases output by 70%):
```bash
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh -af
```

**Combined flags example** (actionable + full mode + oldest-first):
```bash
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh -afo 12345
```

**Specific PR**:
```bash
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh 12345
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh https://github.com/owner/repo/pull/123
```

**Filter manually with jq** (if not using -a flag):
```bash
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh | \
  jq '[.[] | select(.resolved == false and .outdated == false)]'
```

## Usage

Input formats accepted:

- **No argument**: Auto-detects PR from the current git branch
- **PR number**: Fetches comments for a specific PR number (e.g., `12345`)
- **PR URL**: Full GitHub PR URL (e.g., `https://github.com/owner/repo/pull/123`)
- **Comment URL**: Fetches only the thread containing a specific comment (e.g., `https://github.com/owner/repo/pull/123#discussion_r123456`)

**Flags:**
- **-v**: Enables verbose mode for diagnostic output to stderr
- **-a**: Filters to actionable threads only (unresolved AND not outdated). Recommended for large PRs
- **-f**: Full mode — includes diff_hunk fields (70% larger output). diff_hunks are excluded by default since the file contents are readable directly
- **-o**: Oldest-first chronological order (default is newest-first for most relevant feedback)

## Output Structure

Returns an **array of review threads** (sorted newest first by default, use -o for oldest first):

```json
[
  {
    "thread_id": 123,
    "resolved": false,
    "outdated": false,
    "comments": [
      {
        "comment_id": 123,
        "author": "username",
        "body": "comment text",
        "path": "file/path.js",
        "line": 42,
        "original_line": 40,
        "html_url": "https://...",
        "in_reply_to_id": null,
        "created_at": "2025-01-01T00:00:00Z",
        "updated_at": "2025-01-01T00:00:00Z",
        "commit_id": "abc123"
      }
    ]
  }
]
```

**Key fields:**
- `resolved`/`outdated` - Thread-level status (applies to entire thread)
- `.comments[0]` - Original comment that started the thread
- `.comments[1:]` - Replies in the conversation
- `path`, `line`, `original_line` - File location context for each comment
- `diff_hunk` - Code context (only included with `-f` flag, excluded by default)

**Default behavior:**
- Sorted newest first (use `-o` for oldest first)
- Compact mode (no `diff_hunk` fields, use `-f` to include them)

## Common Use Cases

### 1. Address All Unresolved PR Feedback

When the user asks "address the PR feedback":
1. Fetch actionable threads: pass `-a` to get only unresolved, non-outdated threads
2. For each thread, read the referenced file at the specified `path` and `line`
3. Make necessary changes to address the comment
4. Push changes and reply to the comment thread

**Recommended command**: `${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh -a`

### 2. Understand Reviewer Concerns

When the user asks "what did reviewers say about X":
1. Fetch review threads
2. Filter by file path or search comment bodies for keywords
3. Summarize the concerns and suggestions
4. Provide context from the code being discussed

### 3. Resume Work After Context Loss

When returning to a PR after time away:
1. Fetch actionable threads with `-a` to see what needs attention
2. Threads are sorted newest first, so the most recent feedback appears at the top
3. Review the full conversation in each thread (original comment + replies)
4. Address comments starting with the most recent ones

### 4. Analyze Specific Comment Thread

When the user provides a comment URL like `https://github.com/org/repo/pull/123#discussion_r456`:
1. Fetch only that specific thread
2. Read the full conversation context
3. Understand what was already discussed
4. Address the comment with full awareness of the thread history

## Advanced Usage

### Filtering

Use the `-a` flag for actionable threads, or filter manually with jq:

```bash
# Actionable threads (unresolved + not outdated) - built-in with -a flag
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh -a

# Or filter manually with jq
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh | \
  jq '[.[] | select(.resolved == false and .outdated == false)]'

# By author
jq '[.[] | select(.comments[].author == "username")]'

# By file
jq '[.[] | select(.comments[0].path | contains("filename"))]'

# Count comments in actionable threads
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh -a | \
  jq '[.[].comments | length] | add'
```

### Performance Optimization

For large PRs with many comments:
- Pass `-a` to filter actionable threads (reduces output size)
- Compact mode is default (no diff_hunks), keeping output small
- Add `-f` only when inline code context is needed (increases output by 70%)
- **Automatic fallback**: If output exceeds 25KB, the script writes to a temp file automatically
  - Look for: `[get-pr-comments] Large output detected - wrote to temp file for Claude to read: /tmp/pr-comments-{owner}-{repo}-{pr}.json`
  - Read this path with the Read tool to access the full data without truncation
  - This bypasses the Bash tool's 30KB limit entirely

## Troubleshooting

**Enable verbose mode** (`-v` flag) for diagnostic output on stderr:
- Which PR and repository are queried
- Argument parsing details
- Total threads/comments retrieved

**Common issues:**
- **"No PR found"**: Not in git repo, or branch has no PR. Provide explicit PR number/URL.
- **"Cannot access PR"**: Check `gh auth status` and repository permissions.
- **Empty array but comments exist**:
  - With `-a` flag: All threads are resolved or outdated (expected behavior)
  - Without `-a`: Use `-v` to verify correct PR is queried
- **Output seems truncated**: Use `-a` flag to filter first, or ensure PR has <100 threads (GraphQL pagination limit)
- **Missing tools**: Install `gh` (https://cli.github.com/) and `jq`, then run `gh auth login`.

## Notes

- Requires `gh` (GitHub CLI) and `jq` installed and authenticated
- Uses GitHub GraphQL API for accurate `resolved`/`outdated` status
- Returns inline review comments only (not general PR comments)
- Returns empty array `[]` on error with messages to stderr
- **Automatic large output handling**:
  - When output exceeds 25KB, the script automatically writes to a temp file at `/tmp/pr-comments-{owner}-{repo}-{pr}.json`
  - A message appears on stderr: `[get-pr-comments] Large output detected - wrote to temp file for Claude to read: {path}`
  - **Important for skills**: When this message appears, read the temp file path with the Read tool instead of parsing stdout
  - This bypasses the Bash tool's 30KB output limit and allows full data access
- Default behavior optimized for performance:
  - Compact mode (no diff_hunks) reduces output size by 70%
  - Newest-first sorting shows most relevant feedback at the top
  - Use `-a` flag for actionable threads to minimize output on large PRs
