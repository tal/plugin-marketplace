# Tal Plugin Commands

This document describes all available commands in the tal plugin, organized by category.

---

## Git Commands

Git workflow utilities for intelligent commit management.

### `/tal:git:commit:atomic`

**Description:** Create atomic commits by intelligently grouping related changes into separate, focused commits.

**Usage:**
```bash
# Analyze all changes and create atomic commits
/tal:git:commit:atomic

# Only commit changes related to a specific feature
/tal:git:commit:atomic auth feature

# Specify feature and rationale
/tal:git:commit:atomic auth feature Added OAuth support for third-party login
```

**Features:**
- Automatically detects distinct features in your uncommitted changes
- Groups related implementation, tests, and documentation together
- Handles files with mixed changes using `git add -p` for selective staging
- Excludes Claude-generated planning/testing files (unless they're the only changes)
- Generates properly formatted commit messages with:
  - Conventional commit format: `<type>(<scope>): <description>`
  - Bullet points explaining what changed and why
  - Rationale paragraph
- Stops immediately if any git command fails

**Arguments:**
- `[feature-name]` - (Optional) Name of the specific feature to commit
- `[rationale]` - (Optional) Rationale for the change

**Commit Types:**
- `feat` - New features
- `fix` - Bug fixes
- `refactor` - Code restructuring without functionality change
- `docs` - Documentation changes
- `test` - Test additions/modifications
- `chore` - Build, dependencies, generated files
- `style` - Formatting, whitespace
- `perf` - Performance improvements

**Example Output:**
```
feat(auth): Add OAuth2 authentication middleware

- Add OAuth2 provider configuration and client setup
- Implement middleware for token validation and user session creation
- Add error handling for expired and invalid tokens
- Integrate with existing user repository for account lookup

Rationale: Users requested the ability to authenticate using their existing OAuth2 providers (Google, GitHub) instead of creating new credentials. This reduces friction in the onboarding process and improves security by leveraging established identity providers.
```

When the rationale is not clear from context, Claude will ask you to clarify:

![Rationale Question](./commands/git/commit/commit-rationale-question.png)

**See Also:** [commands/git/commit/atomic.md](./commands/git/commit/atomic.md) for detailed implementation instructions

---

### `/tal:git:commit:quick`

**Description:** Quickly commit all changes with a well-formatted commit message. Optimized for speed while maintaining commit message quality.

**Usage:**
```bash
# Interactive mode (will ask for details if needed)
/tal:git:commit:quick

# Specify type and scope
/tal:git:commit:quick feat commands

# Include rationale
/tal:git:commit:quick feat commands Added fast commit workflow
```

**Features:**
- Commits all changes in a single commit (uses `git add -A`)
- Fast analysis using the Haiku model
- Maintains conventional commit format with bullets and rationale
- Stops immediately if any git command fails

**Arguments:**
- `[type]` - (Optional) Commit type (feat, fix, refactor, docs, test, chore, style, perf)
- `[scope]` - (Optional) Component/module affected
- `[rationale]` - (Optional) Rationale for the change

**When to Use:**
- Quick commits where all changes belong together
- Simple updates that don't need atomic grouping
- When speed is prioritized over detailed analysis

**When to Use Atomic Instead:**
- Changes span multiple distinct features
- Need to selectively stage file hunks
- Want detailed feature-by-feature commit history

**Example Output:**
```
feat(commands): Add quick commit command

- Create streamlined commit workflow for fast commits
- Maintain conventional commit message format
- Include automatic change analysis and staging
- Add support for command arguments to skip prompts

Rationale: Users needed a faster alternative to the atomic commit workflow for simple changes where all modifications should go into a single commit. This reduces the overhead of manual file staging while maintaining commit message quality.
```

**See Also:** [commands/git/commit/quick.md](./commands/git/commit/quick.md) for detailed implementation instructions

---

### Skills: `git-branches`

This skill is **MANDATORY** and automatically invoked before any git diff/log commands. It detects the correct base branch in stacked branch workflows.

Detection hierarchy:
1. Graphite (`gt` CLI)
2. Git Machete (`git-machete` CLI)
3. GitHub PR relationships
4. `rebase.updateRefs` configuration
5. Origin HEAD (main/master fallback)

The skill handles common stacked branch patterns.

---

## PR Commands

Fetch and address GitHub pull request review comments.

### Prerequisites

- `gh` (GitHub CLI) must be installed and authenticated
- `jq` must be installed for JSON processing

### `/tal:pr:address-feedback`

**Description:** Address PR feedback from your current branch or a specific PR/comment.

**Usage:**

Address PR feedback from your current branch:
```bash
/tal:pr:address-feedback
```

Or specify a PR number, PR URL, or specific comment URL:
```bash
/tal:pr:address-feedback 12345
/tal:pr:address-feedback https://github.com/tal/repo/pull/12345
/tal:pr:address-feedback https://github.com/tal/repo/pull/12345#discussion_r2406356483
```

**Workflow:**

The command will:
1. Fetch unresolved, non-outdated comments
2. Create a task plan to address each comment
3. Implement the requested changes
4. Run tests and build if needed

### Skills: `get-pr-feedback`

This skill is automatically invoked when needed. It fetches PR comments programmatically and returns structured JSON containing:
- Comment author, body, path, line numbers
- Diff hunks for context
- Resolution status (resolved/outdated)
- HTML URLs for reference
- Thread information for replies

---

## Command Development

To add a new command to this plugin:

1. Create a new `.md` file in the appropriate directory (e.g., `commands/category/new-command.md`)
2. Add frontmatter with `description` and optional `argument-hint`
3. Write the command instructions
4. Update this document with the command documentation
5. Increment the plugin version in `.claude-plugin/plugin.json`

**Template:**
```markdown
---
argument-hint: [optional-arg]
description: Short description of what the command does
---

# Command Name

Detailed instructions for Claude to follow when executing this command...
```

---

## Contributing

Found a bug or have a suggestion? Open an issue.
