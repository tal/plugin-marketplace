#!/bin/bash

# Usage: ./get-pr-comments.sh [-v] [-a] [-f] [-o] [pr-number|pr-url|comment-url]
# Example: ./get-pr-comments.sh 12345
# Example: ./get-pr-comments.sh -v 12345
# Example: ./get-pr-comments.sh -a 12345      # Actionable only (compact by default, newest first)
# Example: ./get-pr-comments.sh -af 12345     # Actionable + full mode with diff_hunks
# Example: ./get-pr-comments.sh -ao 12345     # Actionable + oldest first
# Example: ./get-pr-comments.sh https://github.com/tal/repo/pull/113726
# Example: ./get-pr-comments.sh https://github.com/tal/repo/pull/113726#discussion_r2406356483
# If no PR number provided, attempts to use current branch's PR
#
# Flags:
#   -v    Verbose mode - output diagnostic information to stderr
#   -a    Actionable only - filter to unresolved and not outdated threads
#   -f    Full mode - include diff_hunk fields (default is compact without diff_hunks)
#   -o    Oldest-first chronological order (default is newest first)
#
# Environment Variables:
#   OUTPUT_FILE    If set, writes output to this file path in addition to stdout
#
# Auto-fallback for large output:
#   When output exceeds 25KB, automatically writes to temp file at:
#   /tmp/pr-comments-{owner}-{repo}-{pr}.json
#   This bypasses Bash tool output limits when invoked from Claude Code

SPECIFIC_COMMENT_ID=""
VERBOSE=0
ACTIONABLE_ONLY=0
FULL_MODE=0
OLDEST_FIRST=0

# Function to log verbose messages to stderr
log_verbose() {
  if [ "$VERBOSE" -eq 1 ]; then
    echo "[get-pr-comments] $*" >&2
  fi
}

# Function to log errors to stderr
log_error() {
  echo "[ERROR] $*" >&2
}

# Parse flags
while getopts "vafo" opt; do
  case $opt in
    v)
      VERBOSE=1
      log_verbose "Verbose mode enabled"
      ;;
    a)
      ACTIONABLE_ONLY=1
      log_verbose "Actionable-only mode enabled"
      ;;
    f)
      FULL_MODE=1
      log_verbose "Full mode enabled (including diff_hunks)"
      ;;
    o)
      OLDEST_FIRST=1
      log_verbose "Oldest-first chronological mode enabled"
      ;;
    \?)
      log_error "Invalid option: -$OPTARG"
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))

# Validation: Check if gh is installed
if ! command -v gh &> /dev/null; then
  log_error "GitHub CLI (gh) is not installed"
  log_error "Please install it from: https://cli.github.com/"
  echo "[]"
  exit 1
fi

# Validation: Check if jq is installed
if ! command -v jq &> /dev/null; then
  log_error "jq is not installed"
  log_error "Please install it from: https://stedolan.github.io/jq/"
  echo "[]"
  exit 1
fi

# Validation: Check if gh is authenticated
if ! gh auth status &> /dev/null; then
  log_error "GitHub CLI is not authenticated"
  log_error "Please run: gh auth login"
  echo "[]"
  exit 1
fi

log_verbose "Prerequisites validated: gh and jq are installed and configured"

if [ -z "$1" ]; then
  log_verbose "No argument provided, attempting to detect PR from current branch"

  # Check if in a git repository first
  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    log_error "Not in a git repository"
    log_error "Please run this script from within a git repository or provide a PR number/URL"
    echo "[]"
    exit 0
  fi

  CURRENT_BRANCH=$(git branch --show-current)
  log_verbose "Current branch: $CURRENT_BRANCH"

  # Try to get PR number and repo from current branch
  if ! PR_INFO=$(gh pr view --json number,url 2>&1); then
    log_error "No PR number provided and unable to determine PR for current branch: $CURRENT_BRANCH"
    log_error "This could mean:"
    log_error "  - The current branch doesn't have an associated PR"
    log_error "  - You need to create a PR first"
    log_error "  - The PR exists in a fork and gh can't detect it"
    log_error ""
    log_error "Solutions:"
    log_error "  1. Create a PR for branch '$CURRENT_BRANCH'"
    log_error "  2. Provide a PR number or URL as an argument"
    log_error "  3. Check out the branch associated with the PR you want to query"
    log_error ""
    log_error "Usage: $0 [-v] <pr-number|pr-url|comment-url>"
    # Return empty array (valid JSON) for graceful handling
    echo "[]"
    exit 0
  fi
  PR_NUMBER=$(echo "$PR_INFO" | jq -r '.number')
  # Extract repo from URL (e.g., https://github.com/tal/repo/pull/113726)
  REPO=$(echo "$PR_INFO" | jq -r '.url' | sed -E 's|https://github.com/([^/]+/[^/]+)/pull/.*|\1|')
  log_verbose "Detected PR #$PR_NUMBER in repository $REPO"
else
  log_verbose "Argument provided: $1"

  # Check if argument is a GitHub comment URL
  if [[ "$1" =~ ^https://github.com/([^/]+)/([^/]+)/pull/([0-9]+)#discussion_r([0-9]+)$ ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO_NAME="${BASH_REMATCH[2]}"
    PR_NUMBER="${BASH_REMATCH[3]}"
    SPECIFIC_COMMENT_ID="${BASH_REMATCH[4]}"
    REPO="${OWNER}/${REPO_NAME}"
    log_verbose "Parsed as specific comment URL: PR #$PR_NUMBER, comment #$SPECIFIC_COMMENT_ID in $REPO"
  # Check if argument is a regular GitHub PR URL
  elif [[ "$1" =~ ^https://github.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO_NAME="${BASH_REMATCH[2]}"
    PR_NUMBER="${BASH_REMATCH[3]}"
    REPO="${OWNER}/${REPO_NAME}"
    log_verbose "Parsed as PR URL: PR #$PR_NUMBER in $REPO"
  else
    # Treat as PR number
    PR_NUMBER="$1"
    log_verbose "Treating argument as PR number: #$PR_NUMBER"

    # Get repo from git remote
    if ! REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>&1); then
      log_error "Failed to determine repository from current directory"
      log_error "Please run this script from within the git repository or provide a full PR URL"
      log_error "Output: $REPO"
      echo "[]"
      exit 0
    fi
    log_verbose "Determined repository from current directory: $REPO"
  fi
fi

# Extract owner and repo name from REPO variable (if not already set from URL)
if [ -z "$OWNER" ]; then
  OWNER=$(echo "$REPO" | cut -d'/' -f1)
  REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
fi

log_verbose "Fetching review comments for PR #$PR_NUMBER in $OWNER/$REPO_NAME"

# Verify the PR exists and we have access
if ! gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO_NAME" --json number &> /dev/null; then
  log_error "Cannot access PR #$PR_NUMBER in $OWNER/$REPO_NAME"
  log_error "This could mean:"
  log_error "  - The PR doesn't exist"
  log_error "  - You don't have permission to access this repository"
  log_error "  - The repository name is incorrect"
  log_error ""
  log_error "Please verify:"
  log_error "  1. PR #$PR_NUMBER exists in $OWNER/$REPO_NAME"
  log_error "  2. You have access to the repository"
  log_error "  3. You're authenticated with 'gh auth login'"
  echo "[]"
  exit 0
fi

log_verbose "PR exists and is accessible, querying review threads via GraphQL"

# Fetch PR review comments using GraphQL to get resolved and outdated status
# GraphQL provides review threads with isResolved and isOutdated flags
COMMENTS_JSON=$(gh api graphql --paginate -f query="
query(\$cursor: String) {
  repository(owner: \"${OWNER}\", name: \"${REPO_NAME}\") {
    pullRequest(number: ${PR_NUMBER}) {
      reviewThreads(first: 100, after: \$cursor) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          isResolved
          isOutdated
          comments(first: 50) {
            nodes {
              id
              databaseId
              author {
                login
              }
              body
              path
              line
              originalLine
              startLine
              originalStartLine
              diffHunk
              createdAt
              updatedAt
              commit {
                oid
              }
              replyTo {
                databaseId
              }
              url
            }
          }
        }
      }
    }
  }
}" --jq '
  .data.repository.pullRequest.reviewThreads.nodes[] as $thread |
  {
    thread_id: ($thread.comments.nodes[0].databaseId // 0),
    resolved: $thread.isResolved,
    outdated: $thread.isOutdated,
    comments: [
      $thread.comments.nodes[] | {
        comment_id: .databaseId,
        author: .author.login,
        body: .body,
        path: .path,
        line: .line,
        original_line: .originalLine,
        start_line: .startLine,
        original_start_line: .originalStartLine,
        side: "RIGHT",
        diff_hunk: .diffHunk,
        created_at: .createdAt,
        updated_at: .updatedAt,
        commit_id: .commit.oid,
        in_reply_to_id: .replyTo.databaseId,
        html_url: .url
      }
    ]
  }
' 2>&1)

# Check if GraphQL query failed
if [ $? -ne 0 ]; then
  log_error "GraphQL query failed"
  log_error "Output: $COMMENTS_JSON"
  echo "[]"
  exit 1
fi

# Combine into array of threads
THREADS_JSON=$(echo "$COMMENTS_JSON" | jq -s '.')

# Count total threads and comments
TOTAL_THREADS=$(echo "$THREADS_JSON" | jq 'length')
TOTAL_COMMENTS=$(echo "$THREADS_JSON" | jq '[.[].comments | length] | add // 0')
log_verbose "Retrieved $TOTAL_THREADS review threads with $TOTAL_COMMENTS total comments"

if [ "$TOTAL_COMMENTS" -eq 0 ]; then
  log_verbose "No review comments found"
fi

# Filter by comment ID if specified (return only the thread containing that comment)
if [ -n "$SPECIFIC_COMMENT_ID" ]; then
  log_verbose "Filtering to thread containing comment ID: $SPECIFIC_COMMENT_ID"
  THREADS_JSON=$(echo "$THREADS_JSON" | jq --arg comment_id "$SPECIFIC_COMMENT_ID" '
    map(select(.comments[] | .comment_id == ($comment_id | tonumber)))
  ')
  FILTERED_THREADS=$(echo "$THREADS_JSON" | jq 'length')
  log_verbose "After filtering: $FILTERED_THREADS threads"

  if [ "$FILTERED_THREADS" -eq 0 ]; then
    log_error "Comment #$SPECIFIC_COMMENT_ID not found in PR #$PR_NUMBER"
  fi
fi

# Sort threads by the first comment's created_at timestamp (default: newest first)
if [ "$OLDEST_FIRST" -eq 1 ]; then
  log_verbose "Sorting threads chronologically (oldest first)"
  THREADS_JSON=$(echo "$THREADS_JSON" | jq 'sort_by(.comments[0].created_at)')
else
  log_verbose "Sorting threads in reverse chronological order (newest first)"
  THREADS_JSON=$(echo "$THREADS_JSON" | jq 'sort_by(.comments[0].created_at) | reverse')
fi

# Filter to actionable threads only if -a flag is set
if [ "$ACTIONABLE_ONLY" -eq 1 ]; then
  log_verbose "Filtering to actionable threads only (unresolved and not outdated)"
  THREADS_JSON=$(echo "$THREADS_JSON" | jq '[.[] | select(.resolved == false and .outdated == false)]')
  ACTIONABLE_COUNT=$(echo "$THREADS_JSON" | jq 'length')
  log_verbose "Filtered to $ACTIONABLE_COUNT actionable threads"
fi

# Remove diff_hunk fields by default (unless full mode is enabled)
if [ "$FULL_MODE" -eq 0 ]; then
  log_verbose "Removing diff_hunk fields (compact mode by default, use -f for full)"
  THREADS_JSON=$(echo "$THREADS_JSON" | jq '[.[] | .comments = [.comments[] | del(.diff_hunk)]]')
fi

# Write to temp file if output is large or OUTPUT_FILE is set
OUTPUT_SIZE=$(echo "$THREADS_JSON" | wc -c | tr -d ' ')
TEMP_FILE=""

if [ -n "$OUTPUT_FILE" ]; then
  # User specified output file via env var
  TEMP_FILE="$OUTPUT_FILE"
  echo "$THREADS_JSON" > "$TEMP_FILE"
  log_verbose "Wrote output to $TEMP_FILE (user-specified)"
elif [ "$OUTPUT_SIZE" -gt 25000 ]; then
  # Output is large, write to temp file automatically
  TEMP_FILE="/tmp/pr-comments-${OWNER}-${REPO_NAME}-${PR_NUMBER}.json"
  echo "$THREADS_JSON" > "$TEMP_FILE"
  log_verbose "Output size $OUTPUT_SIZE bytes exceeds 25KB, wrote to temp file: $TEMP_FILE"
  echo "[get-pr-comments] Large output detected - wrote to temp file for Claude to read: $TEMP_FILE" >&2
fi

# Always output to stdout for backwards compatibility
echo "$THREADS_JSON"
