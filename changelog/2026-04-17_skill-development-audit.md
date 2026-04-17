# Skill audit via plugin-dev:skill-development (2026-04-17)

Reviewed all 7 skills in the marketplace against skill-development best practices (third-person triggering descriptions with specific phrases, imperative body voice, progressive disclosure). Applied inline fixes.

## Changes per skill

### `plugins/tal/skills/git/partial-commit/SKILL.md`
- Rewrote the frontmatter description from a vague one-liner into a third-person trigger-phrase description ("stage specific lines", "partial commit", "commit part of a file", etc.).
- Removed the redundant "When to Use This Skill" section — the triggers now live in the description.
- Converted remaining second-person copy ("you want to stage", "you'll need to", "you can stage") to imperative/infinitive form.

### `plugins/tal/skills/get-pr-feedback/SKILL.md`
- Description was already good — left alone.
- Converted second-person phrasing throughout the body to imperative ("Use this instead of" → "Prefer this over", "you'll see" → "a message appears", etc.).
- Tidied use-case steps to address Claude as the actor rather than the user.

### `plugins/tal/skills/pr-thread-reply/SKILL.md`
- Description was already good — left alone.
- Converted second-person phrasing to imperative in Why/Usage/Comment-IDs/Troubleshooting sections.

### `plugins/tal/skills/appstore-connect/SKILL.md`
- Minor voice tweak ("See X" → "Consult X") in the limitations/workarounds pointer to `references/rest-api-workarounds.md`.

### `plugins/plan-refiner/skills/plan-refinement/SKILL.md`
- Converted second-person copy ("you want", "you'd prefer", "if user") to imperative/infinitive form across the interview flow, pre-interview checklist, interview pacing, pitfalls, and success-metrics sections.
- No structural trim — body is still on the long side (~2k words) but references/ already carries the detailed patterns/checklist/tradeoff docs, so progressive disclosure is in place.

### `plugins/karabiner/skills/js-complex-modifications/SKILL.md`
- Rewrote the multi-line frontmatter description to match the third-person "This skill should be used when the user asks to …" pattern with specific trigger phrases, while keeping the multi-line YAML form.
- Small voice fixes ("Use `…`" → "Set `…`", "see what key_codes" → "inspect which key_codes", "if your `variable_if`" → "when `variable_if`").

### `plugins/sort-videos/skills/sort-videos/SKILL.md`
- Rewrote the frontmatter description into a third-person trigger description that covers both the slash-style invocation (`/sort-videos`) and natural-language requests ("sort my downloaded videos", "transcribe and categorize videos").
- Body was already imperative — no additional changes.
- `user-invocable: true` preserved; skill remains invocable as a slash-style command.

## Notes / follow-ups not taken

- plan-refinement SKILL.md body is still ~2k words. Further trimming into `references/` is possible but would be a structural refactor beyond this pass.
- sort-videos uses slash-command-style frontmatter (`user-invocable: true`, `$ARGUMENTS`, `allowed-tools`). Kept as a skill per current configuration; converting it into a proper `commands/` entry is a separate decision.
- No skill had obviously broken or missing referenced files — all listed `references/` and `examples/` paths resolve on disk.
