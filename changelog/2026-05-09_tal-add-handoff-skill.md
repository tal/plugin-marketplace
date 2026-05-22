# 2026-05-09 — Add `handoff` skill to the `tal` plugin

Added a `handoff` skill under `plugins/tal/skills/handoff/` that compacts the current conversation into a handoff document for a fresh agent to pick up. Adapted verbatim from [mattpocock/skills @ 733d312](https://github.com/mattpocock/skills/blob/733d312884b3878a9a9cff693c5886943753a741/skills/in-progress/handoff/SKILL.md).

The skill writes the doc to a `mktemp -t handoff-XXXXXX.md` path, suggests follow-up skills, and references existing artifacts by path/URL rather than restating them. Accepts an optional argument describing the next session's focus.

Marked the skill `disable-model-invocation: true` so it never auto-fires from its description, and added a thin command at `plugins/tal/commands/handoff.md` (`/tal:handoff`, also reachable as `/handoff` when there's no namespace conflict) that delegates to the skill and forwards `$ARGUMENTS` as the next-session focus.

Updated `plugins/tal/README.md` (Commands + Skills list + Layout tree). No manifest changes — skills and commands auto-discover from their respective directories.
