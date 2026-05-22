---
description: Write a handoff document so a fresh agent can pick up the current conversation.
argument-hint: "[what the next session will focus on]"
---

Invoke the `handoff` skill (from this plugin) to write a handoff document for the current conversation.

If `$ARGUMENTS` is non-empty, pass it through as the description of what the next session will focus on so the skill can tailor the doc accordingly.
