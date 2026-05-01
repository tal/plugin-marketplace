# Sort matcher: `action: prompt`

Added a new rule action `prompt` to the sort plugin's user-rules system. When a
rule with `action: prompt` matches a file, the dispatcher hands the file off to
the plugin's named `sort-route-by-prompt` agent along with the rule's `prompt:`
text as natural-language routing instructions. The agent decides where the file
goes (`route:`, `route_sensitive`, `delete`, `skip`, or `fallthrough`) and the
dispatcher applies that decision the same way it would a static rule.

This unblocks routing that's too nuanced for static patterns — e.g. "decide if
this PDF is a receipt, invoice, or contract and route accordingly" — without
having to author a separate rule for every category.

Example:

```yaml
- match: { ext: [.pdf] }
  action: prompt
  prompt: |
    If this PDF is a receipt or invoice, route to AI Library/Receipts/.
    If it's a tax document (W-2, 1099, return), route to AI Library/Taxes/.
    Otherwise fall through to default classification.
```

## Files changed

- `plugins/sort/agents/sort-route-by-prompt.md` *(new)* — named agent
  auto-discovered by the plugin. Owns the routing-decision contract: the
  inputs it receives (`prompt`, `file`, `target`, `topics`, `note`), the
  one-line reply forms it must use (`route: <path>` / `route_sensitive` /
  `delete` / `skip` / `fallthrough`), and the read-only/no-deletion-without-
  authorization constraints. Tools: `Read, Bash, Glob, Grep, AskUserQuestion`
  — AskUserQuestion is permitted but constrained to last-resort use (the
  user's prompt explicitly says to ask, OR the file plausibly fits ≥2 of
  the prompt's named buckets and a wrong pick would meaningfully harm the
  user). For routine ambiguity, the agent must reply `fallthrough` instead.
  One question per invocation, max.
- `plugins/sort/skills/sort/OVERRIDES.md` — added `prompt` to the actions table
  (pointing at the named agent), rule-shape block, validation list, and an
  example block.
- `plugins/sort/skills/sort/SKILL.md` — added an "`action: prompt` rules"
  sub-section under §0.5 telling the dispatcher to invoke the named agent
  via `subagent_type: "sort-route-by-prompt"` rather than restating the
  agent's contract; documents only the input-block format and how to apply
  each reply form. Updated §5's `Action` column legend to include
  `prompt(<agent decision>)`.
- `plugins/sort/scripts/match-rules.rb` — `render_action` now displays the
  rule's `prompt:` text (truncated for terminal width) so `--rules-only` and
  per-file output show what an `action: prompt` rule will instruct.
- `plugins/sort/scripts/add-rule.rb` — added `prompt` to `valid_actions`,
  accepted a new `--prompt=<text>` flag, and require it (non-empty) when the
  action is `prompt`. The flag is written to the rule's `prompt:` field.
- `plugins/sort/commands/add-rule.md` — added "Hand to an agent with custom
  instructions" to the action picker, a follow-up question for the prompt text,
  and updated the bash invocation + argument shorthand to include `--prompt`.

## Soft-fail / validation

- Missing or empty `prompt:` on `action: prompt` → rule treated as `ask` and a
  warning logged (parallels the existing missing-`to:`-on-`route` behavior).
- `prompt:` on a non-`prompt` action → ignored.
- Invalid agent reply → log a warning and treat as `ask`.

## Smoke-tested

- `ruby scripts/add-rule.rb` against a temp `sort.md` with
  `action=prompt` + `--prompt=...` writes the expected YAML.
- `ruby scripts/match-rules.rb` against the resulting file shows
  `action=prompt → "<prompt text>"` with the rule marked `✓ winner`.
- `ruby -c` passes on both scripts.
