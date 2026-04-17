---
name: git-partial-commit
description: This skill should be used when the user asks to "stage specific lines", "partial commit", "stage one hunk", "commit part of a file", "split changes into multiple commits", "stage only some changes", "create atomic commits from mixed changes", or needs to commit a subset of the changes in a file without staging the whole file. Uses `git apply --cached` with a user-supplied unified diff patch to stage exact lines or hunks.
---

# Git Partial Commit

Stage and commit specific lines or hunks from a file without staging the entire file. Useful for creating atomic, focused commits when a file contains multiple unrelated changes.

## How It Works

Use git's patch mechanism to stage specific lines:

1. Generate a unified diff showing the changes in a file
2. Extract the specific hunks or lines to stage
3. Apply those changes to the staging area using `git apply --cached`

## Usage

### Using the Helper Script

Invoke the included helper script to stage specific lines from a file:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/git/partial-commit/stage-lines.sh <file> <patch>
```

**Parameters:**
- `file`: Path to the file (relative or absolute)
- `patch`: A unified diff patch string containing the changes to stage

The script:
1. Validates that the file exists and has changes
2. Applies the provided patch to the staging area
3. Returns success/failure status

### Workflow for Partial Commits

1. **View the changes in a file with context:**
   ```bash
   git diff --unified=<N> <file>
   ```
   Where `<N>` is the number of context lines (default is 3; use larger numbers for more context)

2. **Construct a patch for the lines to stage:**
   A patch follows the unified diff format:
   ```
   diff --git a/foo.txt b/foo.txt
   index abcdef..123456 100644
   --- a/foo.txt
   +++ b/foo.txt
   @@ -10,0 +11,1 @@
   +this is the line to stage
   ```

3. **Stage the specific lines:**
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/git/partial-commit/stage-lines.sh foo.txt "$(cat <<'EOF'
   diff --git a/foo.txt b/foo.txt
   index abcdef..123456 100644
   --- a/foo.txt
   +++ b/foo.txt
   @@ -10,0 +11,1 @@
   +this is the line to stage
   EOF
   )"
   ```

4. **Commit the staged changes:**
   ```bash
   git commit -m "Your commit message"
   ```

### Understanding Unified Diff Format

A unified diff patch consists of:

**Header:**
```
diff --git a/file.txt b/file.txt
index <old-hash>..<new-hash> <mode>
--- a/file.txt
+++ b/file.txt
```

**Hunks:**
Each hunk starts with a hunk header and contains the changes:
```
@@ -<old-start>,<old-count> +<new-start>,<new-count> @@
 context line
-removed line
+added line
 context line
```

- Lines starting with `-` are removed
- Lines starting with `+` are added
- Lines starting with ` ` (space) are context lines
- The hunk header `@@` specifies line numbers

### Tips for Creating Patches

1. **Get the full diff first:**
   ```bash
   git diff --unified=5 file.txt
   ```

2. **Extract the desired hunks:**
   - Copy the header section (diff --git, index, ---, +++)
   - Copy only the hunks (`@@ ... @@`) to stage
   - Include enough context lines for git to locate the changes

3. **Keep proper patch format:**
   - Maintain the exact indentation and spacing
   - Include the required header lines
   - Ensure hunk headers match the line numbers

## Common Use Cases

### Example 1: Stage a single added line

File has multiple changes, but only one should be staged:

```bash
# View the changes
git diff file.txt

# Stage just the line you want
${CLAUDE_PLUGIN_ROOT}/skills/git/partial-commit/stage-lines.sh file.txt "$(cat <<'EOF'
diff --git a/file.txt b/file.txt
index abc123..def456 100644
--- a/file.txt
+++ b/file.txt
@@ -5,0 +6,1 @@
+new feature line
EOF
)"

# Commit
git commit -m "Add new feature"
```

### Example 2: Stage one hunk from multiple hunks

File has changes in multiple places, stage only one section:

```bash
# Get diff with context
git diff --unified=3 file.txt

# Stage only the first hunk
${CLAUDE_PLUGIN_ROOT}/skills/git/partial-commit/stage-lines.sh file.txt "<patch-with-one-hunk>"

# Commit
git commit -m "Fix bug in section A"

# Later, stage and commit the other changes separately
```

### Example 3: Separate bug fix from refactoring

File contains both a bug fix and refactoring:

```bash
# Stage the bug fix lines
${CLAUDE_PLUGIN_ROOT}/skills/git/partial-commit/stage-lines.sh file.txt "<bug-fix-patch>"
git commit -m "fix: Correct null pointer handling"

# Stage the refactoring lines
${CLAUDE_PLUGIN_ROOT}/skills/git/partial-commit/stage-lines.sh file.txt "<refactor-patch>"
git commit -m "refactor: Simplify logic"
```

## Workflow Integration

This skill works well with:
- The `git-branches` skill for determining the base branch
- Standard commit workflows for creating atomic commits
- PR creation workflows for clean commit history

## Error Handling

The script will fail if:
- The file doesn't exist
- The file has no changes
- The patch format is invalid
- The patch doesn't apply to the current state of the file

When the script fails:
- Check the error message for details
- Verify the file path is correct
- Ensure the patch matches the current file state
- Confirm the patch format is valid unified diff

## Notes

- The file must have unstaged changes for the skill to work
- Patches are applied to the staging area only (`--cached` flag)
- The working directory file remains unchanged
- Multiple patches may be staged to the same file before committing
- Run `git diff --cached` to see what's currently staged
- Run `git reset HEAD <file>` to unstage if needed
