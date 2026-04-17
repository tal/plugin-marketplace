#!/usr/bin/env bash
set -euo pipefail

# Reply to GitHub PR inline comment threads using native gh CLI
# Usage: reply-pr-thread.sh [options] <comment-url-or-comment-id> <message>

VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${YELLOW}[verbose]${NC} $*" >&2
    fi
}

log_error() {
    echo -e "${RED}[error]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

show_usage() {
    cat << EOF
Usage: reply-pr-thread.sh [options] <input> [message]

Reply to a GitHub PR inline comment thread using native gh CLI.

Options:
  --comment-id <id>     Comment database ID to reply to
  --pr <number>         PR number
  --repo <owner/repo>   Repository in owner/repo format
  -v, --verbose         Enable verbose output
  -h, --help           Show this help message

Input Formats:
  1. Comment URL + message (recommended):
     reply-pr-thread.sh "https://github.com/owner/repo/pull/123#discussion_r456" "message"

  2. Comment ID with flags:
     reply-pr-thread.sh --comment-id 456789 --pr 123 --repo owner/repo "message"

  3. Interactive mode:
     reply-pr-thread.sh

Examples:
  # Reply using comment URL
  reply-pr-thread.sh "https://github.com/tal/repo/pull/123#discussion_r456" "Fixed!"

  # Reply using comment ID
  reply-pr-thread.sh --comment-id 456789 --pr 123 --repo tal/repo "Thanks!"

  # Interactive mode
  reply-pr-thread.sh

Note:
  - Comment ID is the numeric ID from the URL (discussion_r<ID>)
  - You can only reply to top-level review comments, not replies to replies
  - Requires 'gh' CLI to be installed and authenticated
EOF
}

# Extract components from GitHub comment URL
# Supported formats:
#   https://github.com/owner/repo/pull/123#discussion_r456789
#   https://github.com/owner/repo/pull/123/files#discussion_r456789
#   https://github.com/owner/repo/pull/123/files#r456789
#   https://github.com/owner/repo/pull/123/changes#r456789
parse_comment_url() {
    local url="$1"

    # Check if it's a GitHub PR comment URL (with optional /files or /changes segment, and #discussion_r or #r)
    if [[ ! "$url" =~ github\.com/.+/pull/[0-9]+(/(files|changes))?#(discussion_)?r[0-9]+ ]]; then
        log_error "Invalid GitHub PR comment URL format"
        log_error "Expected format: https://github.com/owner/repo/pull/123#discussion_r456"
        return 1
    fi

    # Extract owner/repo
    local repo_part
    repo_part=$(echo "$url" | sed -E 's|https?://github\.com/([^/]+/[^/]+)/pull/.*|\1|')

    # Extract PR number (handle optional /files or /changes segment)
    local pr_num
    pr_num=$(echo "$url" | sed -E 's|.*/pull/([0-9]+)(/(files|changes))?#.*|\1|')

    # Extract comment ID (handles both #discussion_r and #r patterns)
    local comment_id
    comment_id=$(echo "$url" | sed -E 's|.*#(discussion_)?r([0-9]+).*|\2|')

    log_verbose "Parsed URL: repo=$repo_part, pr=$pr_num, comment_id=$comment_id"

    echo "$repo_part|$pr_num|$comment_id"
}

# Post reply using GitHub API
post_reply() {
    local repo="$1"
    local pr_number="$2"
    local comment_id="$3"
    local message="$4"

    log_verbose "Posting reply to comment $comment_id on PR #$pr_number in $repo"

    # Use GitHub API to post reply
    # Endpoint: POST /repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies
    local response
    if response=$(gh api \
        -X POST \
        "repos/$repo/pulls/$pr_number/comments/$comment_id/replies" \
        -f body="$message" \
        2>&1); then

        # Extract the HTML URL from response
        local html_url
        html_url=$(echo "$response" | jq -r '.html_url // empty' 2>/dev/null || echo "")

        log_success "Reply posted successfully"
        if [[ -n "$html_url" ]]; then
            echo "URL: $html_url"
        else
            echo "PR: https://github.com/$repo/pull/$pr_number"
        fi
        return 0
    else
        log_error "Failed to post reply"
        log_verbose "API response: $response"

        # Parse error message
        if echo "$response" | grep -qi "not found"; then
            log_error "Comment not found or you don't have access"
            log_error "Note: You can only reply to top-level review comments, not replies to replies"
        elif echo "$response" | grep -qi "unauthorized\|forbidden"; then
            log_error "Authentication failed or insufficient permissions"
            log_error "Run 'gh auth login' to authenticate"
        else
            log_error "Unknown error occurred"
        fi

        return 1
    fi
}

# Main logic
main() {
    local comment_id=""
    local pr_number=""
    local repo=""
    local message=""
    local input_mode="auto"  # auto, url, manual, interactive

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --comment-id)
                comment_id="$2"
                input_mode="manual"
                shift 2
                ;;
            --pr)
                pr_number="$2"
                shift 2
                ;;
            --repo)
                repo="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                # Positional argument
                if [[ -z "$message" ]]; then
                    # First positional could be URL or comment ID or message
                    if [[ "$1" =~ ^https?://github\.com/.*/pull/[0-9]+(/(files|changes))?#(discussion_)?r[0-9]+ ]]; then
                        # It's a comment URL
                        local url="$1"
                        input_mode="url"

                        # Parse and extract components
                        local parsed
                        parsed=$(parse_comment_url "$url")
                        if [[ -z "$parsed" ]]; then
                            exit 1
                        fi

                        repo=$(echo "$parsed" | cut -d'|' -f1)
                        pr_number=$(echo "$parsed" | cut -d'|' -f2)
                        comment_id=$(echo "$parsed" | cut -d'|' -f3)
                    elif [[ "$1" =~ ^[0-9]+$ ]]; then
                        # It's a comment ID
                        comment_id="$1"
                        input_mode="manual"
                    else
                        # Assume it's the message
                        message="$1"
                    fi
                else
                    # Second positional is the message
                    message="$1"
                fi
                shift
                ;;
        esac
    done

    # Check prerequisites
    if ! command -v gh &> /dev/null; then
        log_error "gh CLI is not installed"
        echo "Install it from: https://cli.github.com/" >&2
        exit 1
    fi

    if ! gh auth status &> /dev/null; then
        log_error "gh is not authenticated"
        echo "Run 'gh auth login' to authenticate" >&2
        exit 1
    fi

    # Interactive mode if not enough info
    if [[ -z "$comment_id" && -z "$message" ]]; then
        input_mode="interactive"

        echo "Interactive mode - reply to PR inline comment"
        echo ""

        read -rp "Comment URL or Comment ID: " input

        if [[ "$input" =~ ^https?://github\.com/.*/pull/[0-9]+(/(files|changes))?#(discussion_)?r[0-9]+ ]]; then
            # Parse URL
            local parsed
            parsed=$(parse_comment_url "$input")
            if [[ -z "$parsed" ]]; then
                exit 1
            fi

            repo=$(echo "$parsed" | cut -d'|' -f1)
            pr_number=$(echo "$parsed" | cut -d'|' -f2)
            comment_id=$(echo "$parsed" | cut -d'|' -f3)
        elif [[ "$input" =~ ^[0-9]+$ ]]; then
            comment_id="$input"
            read -rp "PR number: " pr_number
            read -rp "Repository (owner/repo): " repo
        else
            log_error "Invalid input. Expected comment URL or comment ID (number)"
            exit 1
        fi

        echo ""
        read -rp "Reply message: " message
    fi

    # Validate required fields
    if [[ -z "$comment_id" ]]; then
        log_error "Comment ID is required"
        echo "Use --comment-id flag or provide a comment URL" >&2
        exit 1
    fi

    if [[ -z "$pr_number" ]]; then
        log_error "PR number is required"
        echo "Use --pr flag or provide a comment URL" >&2
        exit 1
    fi

    if [[ -z "$repo" ]]; then
        log_error "Repository is required"
        echo "Use --repo flag or provide a comment URL" >&2
        exit 1
    fi

    if [[ -z "$message" ]]; then
        log_error "Reply message is required"
        exit 1
    fi

    # Post the reply
    post_reply "$repo" "$pr_number" "$comment_id" "$message"
}

main "$@"
