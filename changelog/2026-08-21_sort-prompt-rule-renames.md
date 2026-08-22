# Add content-derived renaming to sort prompt rules

**Date:** 2026-08-21

## What changed

- Added an optional `rename:` convention to agent-backed `action: prompt` rules.
- Extended the routing agent's one-line response format with an optional proposed basename.
- Documented sanitization, extension preservation, collision handling, and fallback behavior in the dispatcher instructions.
- Added `--rename=` support to the rule-creation helper and surfaced conventions in rule-debug output.
- Updated `/sort:add-rule`, the rule schema reference, and the plugin README for the new user-facing option.

## Why

Portal exports and similar documents often have opaque filenames while the useful date and document type exist only in their contents. Prompt-rule renaming lets the same agent that reads and routes a file propose a consistent filename without weakening the existing no-overwrite and recoverable-fallback guarantees.

See `plugins/sort/changelog/2026-08-12_rule-rename-support.md` for the detailed design notes and motivating migration.
