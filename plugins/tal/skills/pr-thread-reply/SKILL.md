---
name: pr-thread-reply
description: This skill should be used when the user asks to "reply to PR thread", "reply to PR comment", "respond to inline comment", "respond to review comment", "comment on review", "answer PR feedback", "post reply to PR discussion", or provides a GitHub PR inline comment URL (e.g., https://github.com/org/repo/pull/123#discussion_r456) and wants to reply to it. Allows posting replies to inline review comment threads on GitHub PRs using native gh CLI.
disable-model-invocation: true
---

# Reply to PR Review Thread

Post a reply to an inline review comment thread on a GitHub pull request.

## Prerequisites

- `gh` (GitHub CLI) installed and authenticated
- `jq` for JSON parsing

No extensions required - uses native `gh api` commands.

## Why Use This Skill

Native GitHub CLI (`gh pr comment`) only supports general PR comments, not inline review comments. This skill uses the GitHub REST API via `gh api` to reply to specific inline review threads with proper threading support.

**Prefer this over**:
- `gh pr comment` (doesn't support inline comment replies)
- Manual `gh api` calls (this skill handles URL parsing and error handling)
- Manual web browsing (not automatable)

## Quick Start

**Reply using comment URL** (most common - extracts thread ID automatically):
```bash
${CLAUDE_PLUGIN_ROOT}/skills/pr-thread-reply/reply-pr-thread.sh \
  "https://github.com/tal/repo/pull/123517#discussion_r2721565974" \
  "Thanks, fixed in the latest commit!"
```

**Reply using comment ID directly**:
```bash
${CLAUDE_PLUGIN_ROOT}/skills/pr-thread-reply/reply-pr-thread.sh \
  --comment-id 456789 \
  --pr 12345 \
  --repo owner/repo \
  "Your reply message here"
```

**Interactive mode** (prompts for inputs):
```bash
${CLAUDE_PLUGIN_ROOT}/skills/pr-thread-reply/reply-pr-thread.sh
```

## Usage

Multiple input formats accepted for flexibility:

### Option 1: Comment URL (Recommended)
Provide the full GitHub PR comment URL and the reply message:
```bash
reply-pr-thread.sh "<comment-url>" "<reply-message>"
```

Example:
```bash
reply-pr-thread.sh \
  "https://github.com/tal/repo/pull/123517#discussion_r2721565974" \
  "Good catch! I've updated the error handling."
```

### Option 2: Comment ID with Flags
Provide comment ID and other details explicitly:
```bash
reply-pr-thread.sh \
  --comment-id <comment-id> \
  --pr <pr-number> \
  --repo <owner/repo> \
  "<reply-message>"
```

Example:
```bash
reply-pr-thread.sh \
  --comment-id 456789 \
  --pr 12345 \
  --repo tal/repo \
  "Fixed as suggested, thanks!"
```

### Option 3: Interactive Mode
Run without arguments to be prompted:
```bash
reply-pr-thread.sh
```

### Flags

- `--comment-id <id>`: The comment database ID to reply to (numeric)
- `--pr <number>`: The PR number
- `--repo <owner/repo>`: The repository in owner/repo format
- `-v, --verbose`: Enable verbose output for debugging

## Getting Comment IDs

Comment IDs are extracted automatically from comment URLs, but they can also be obtained manually:

**From the URL**:
The comment ID is the numeric part after `#discussion_r` in the URL:
```
https://github.com/owner/repo/pull/123#discussion_r456789
                                                    ^^^^^^ <- comment ID is 456789
```

**Using get-pr-feedback skill**:
```bash
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh -a
```
The output lists comment URLs which contain the comment IDs.

## Output

On success, the skill outputs:
```
✓ Reply posted successfully to thread PRRT_...
URL: https://github.com/owner/repo/pull/123#discussion_r456
```

On error, diagnostic information is printed to stderr.

## Common Use Cases

### 1. Reply to Specific Comment After Code Changes

After addressing a reviewer's inline comment:
1. Get the comment URL from GitHub or from the user
2. Reply with what changed:
```bash
reply-pr-thread.sh \
  "https://github.com/tal/repo/pull/123#discussion_r456" \
  "Fixed in commit abc123 - now using error wrapping as suggested"
```

### 2. Acknowledge Feedback

Quick acknowledgment of a comment:
```bash
reply-pr-thread.sh \
  "https://github.com/tal/repo/pull/123#discussion_r456" \
  "Good point, will address this in a follow-up PR"
```

### 3. Batch Reply to Multiple Comments

After addressing multiple review comments:
1. Use `get-pr-feedback` to list all unresolved threads
2. For each addressed thread, post a reply explaining the changes
3. Helps reviewers track what's been fixed

### 4. Discussion on Implementation Approach

When a comment starts a technical discussion:
```bash
reply-pr-thread.sh \
  "https://github.com/tal/repo/pull/123#discussion_r456" \
  "I considered that approach but went with X because Y. Happy to discuss alternatives if you have concerns."
```

## Integration with get-pr-feedback

This skill pairs well with the `get-pr-feedback` skill:

```bash
# 1. Get all actionable feedback
${CLAUDE_PLUGIN_ROOT}/skills/get-pr-feedback/get-pr-comments.sh -a

# 2. Make code changes to address comments

# 3. Reply to each thread explaining what you did
${CLAUDE_PLUGIN_ROOT}/skills/pr-thread-reply/reply-pr-thread.sh \
  "https://github.com/.../discussion_r123" \
  "Fixed in commit abc123"
```

## Troubleshooting

**Authentication error:**
```
Error: gh is not authenticated
```
Run `gh auth login` to authenticate.

**Comment not found:**
```
Error: Comment not found or you don't have access
```
- Verify the comment ID is correct
- Confirm write access to the repository
- Note: Only top-level review comments accept replies — replies to replies are not supported

**Comment URL not recognized:**
The URL must contain `#discussion_r` followed by a number. Example:
`https://github.com/owner/repo/pull/123#discussion_r456789`

**gh CLI not installed:**
```
Error: gh CLI is not installed
```
Install from: https://cli.github.com/

## Notes

- Requires `gh` CLI installed and authenticated
- Uses native GitHub REST API via `gh api` (no extensions needed)
- Replies are posted immediately and cannot be edited via this tool
- Comment IDs are numeric database IDs extracted from the URL
- The skill extracts comment IDs from URLs automatically
- Supports multi-line messages (quote them properly in bash)
- Can only reply to top-level review comments, not replies to replies
