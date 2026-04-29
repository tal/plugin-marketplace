# Location-agnostic: sort any folder, not just `~/Downloads`

The skill no longer assumes `~/Downloads`. The default target folder is now the **current working directory** — wherever Claude Code was launched. `AI Library/` is created inside that folder if it doesn't already exist. The skill works equally well on `~/Downloads`, `~/Desktop`, a project folder, a subfolder of Downloads, or anywhere else.

## Resolution rules (new §0 in both SKILL.md files)

1. If `$ARGUMENTS` is a directory path → that's the target folder.
2. If `$ARGUMENTS` is a file path or glob → target = parent directory.
3. Otherwise → target = current working directory (`pwd`).
4. A `sort.md` / `sort.local.md` `sources:` override beats all of the above — useful when the user wants the skill pinned to a specific folder regardless of CWD (e.g. a user who always sorts `~/Downloads` regardless of where they launch Claude can put `sources: [~/Downloads, ~/Downloads/Recents]` in `~/.claude/sort.md`).

## Ripple changes

Every reference to `~/Downloads/AI Library/` in the active skill files was updated to `<target>/AI Library/`. Folder discovery commands now use the `<target>` variable instead of `$HOME/Downloads`. The "AI Library" directory is `mkdir -p`-ed when first needed.

- `plugins/sort/skills/sort/SKILL.md` — new "Target folder resolution" and "Output location" sections at the top; §0 rewritten; routing destinations throughout (Screenshots, Memes, Apps, Apps/_duplicates, Review, image/archive routes) all changed to `<target>/AI Library/...`; §0.5 `sources:` description updated to explain when to override CWD.
- `plugins/sort/skills/sort-videos/SKILL.md` — same pattern: new target-folder resolution at top of §0, all `~/Downloads/AI Library/` references changed to `<target>/AI Library/`, runtime folder discovery in §5 uses `<target>` instead of `$HOME/Downloads`. Description rewritten to advertise the location-agnostic behavior.
- `plugins/sort/skills/sort/documents.md` — §1 folder discovery uses `<target>/AI Library/`; §4 sensitive default uses `<target>/AI Library/Sensitive/`.
- `plugins/sort/skills/sort/OVERRIDES.md` — `sources` table entry rewritten to describe its role as a CWD-default override; example yaml block has a comment explaining when to set `sources`; `skip` action description no longer specifically mentions `~/Downloads`.
- `plugins/sort/.claude-plugin/plugin.json` — description rewritten to advertise the location-agnostic behavior; keywords expanded (`sort`, `organize`, `desktop`, `documents`, `pdf`, `screenshot`, `ai-library`).
- `plugins/sort/README.md` — opening paragraph rewritten; `/sort` row in the commands table updated to describe CWD-default scanning.

## Migration impact for the user's existing setup

The user's current `~/.claude/sort.local.md` does not set `sources:`, so behavior automatically shifts to the new CWD default. When they launch Claude from `~/Downloads` (their usual working dir based on observed sessions), `/sort` continues to work exactly as before. When they launch Claude from any other folder and run `/sort`, it now sorts that folder instead — the new capability they asked for.

If they want to pin sort to always operate on `~/Downloads` regardless of CWD, add to `~/.claude/sort.md` (committable):

```yaml
sources:
  - ~/Downloads
  - ~/Downloads/Recents
```

## Out of scope

- The seed `~/.claude/sort.local.md` was left untouched (no `sources:` line). The user can decide whether to pin to a specific folder or accept the new CWD-default behavior.
- `match-rules.rb` doesn't reference target folders (it's a rule auditor, not a routing tool) and needed no changes.
- Examples in OVERRIDES.md still use `AI Library/Receipts/`, `AI Library/Invoices/`, etc. as `to:` destinations — these are relative paths the dispatcher resolves to `<target>/AI Library/...` at runtime, which is the correct behavior.
