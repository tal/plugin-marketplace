# tal plugin — agent notes

Rules for working on this plugin. The repo-wide rules in the root `AGENTS.md` still apply. `CLAUDE.md` here is a thin pointer at this file.

## New skills are explicit-only by default

Every skill's description is loaded into the context of every session that has the plugin installed, whether or not the skill is used. This plugin is a grab-bag, so that adds up. **Unless the user explicitly says a skill should trigger on its own, make it explicit-only in both runtimes:**

- **Claude Code:** `disable-model-invocation: true` in the `SKILL.md` frontmatter. The description stays out of the model's context, and the skill only runs via `/<name>` or `/tal:<name>`.
- **Codex:** `skills/<name>/agents/openai.yaml` with:
  ```yaml
  policy:
    allow_implicit_invocation: false
  ```
  Codex then leaves the skill out of the model-visible list, and only an explicit `$<name>` runs it.

How to write an explicit-only skill:

- **Description:** write it for a person reading the `/` menu. Say what the skill does in one to three sentences and end with "Invoke explicitly via /<name>". Leave out the trigger-phrase lists ("Use when the user says …"), since no model reads them.
- **Cross-references:** a model can't discover an explicit-only skill, so a pointer to it from another skill goes in that skill's **body** ("tell the user to run `/deploy`"), never in a description.
- **README:** in the plugin README, say the skill is explicit-only.

Skills that auto-trigger on purpose: `get-pr-feedback`, `git-partial-commit`, `plex-standup-posters`, `stay-on-track`, `unambiguous`. Leave them as they are unless the user asks. Explicit-only: `appstore-connect`, `deploy`, `handoff`, `pr-thread-reply`.

Platform-specific skills (Apple-only, one service, one host) are a strong case for explicit-only: their descriptions otherwise load into every unrelated project. To get auto-help in the projects that need it, add a small project-level skill in that repo (`.claude/skills/<name>/SKILL.md`) that points at the slash command.
