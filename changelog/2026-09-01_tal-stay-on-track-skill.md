# Add `stay-on-track` skill

**Date:** 2026-09-01
**Scope:** `plugins/tal/skills/stay-on-track/SKILL.md`, plugin and marketplace READMEs

## What changed

Added a `stay-on-track` skill to the `tal` plugin. It fires automatically when the user says "stay on track," "don't go off track," "stick to the plan," or otherwise asks to require confirmation before deviating from the session's goal. Once triggered, it pins down the session's stated or inferred goal in one sentence and, for the rest of the conversation, requires stopping and asking before starting unrequested work, broadening scope, switching approach, or touching unrelated files — without gating on in-scope decisions or on work the user directly asks for afterward.

## Why a skill, not a command

The user initially asked for a "command," but plugin commands in this repo are purely manual (`/tal:whatever`) — nothing about a command file makes it auto-fire on a spoken phrase. Auto-invocation on phrasing is what skill `description` frontmatter is for (same mechanism as the existing `unambiguous` skill), so this shipped as a skill instead. Confirmed the mechanism choice with the user via AskUserQuestion before building.
