# karabiner

Skills for configuring and writing [Karabiner-Elements](https://karabiner-elements.pqrs.org/) complex modification rules on macOS. The bundled skill teaches the agent to author rules in JavaScript (Duktape ES5.1) that generate JSON, instead of hand-writing the deeply nested JSON Karabiner expects. It is aimed at anyone who wants to remap keys, build app-specific hotkeys, set up dual-role keys, or debug rules that aren't firing.

## Requirements

- macOS.
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/) v15.9.6 or newer (the version that introduced the JavaScript-authored complex modifications editor).
- Optional: `karabiner_cli` on `PATH` for the `--eval-js` and `--list-system-variables` debugging flows referenced in the skill.

## Install

Claude Code (from inside the session):

```
/plugin install karabiner@tal-marketplace
```

Or from the shell with the `claude` CLI:

```
claude plugin install karabiner@tal-marketplace
```

Codex:

```
codex plugin install karabiner@tal-marketplace
```

See the root [README](../../README.md) for marketplace setup if you haven't added `tal-marketplace` yet.

## Skills

### `karabiner-js-modifications`

**Triggers** when the user asks to "write Karabiner rules", "create a karabiner complex modification", "remap keys on macOS", "edit karabiner.json", "set up keyboard shortcuts with Karabiner", "debug a Karabiner rule", or otherwise mentions Karabiner-Elements, `key_code` mappings, modifier remapping, or app-specific hotkeys on macOS. It also fires for general "remap keys / make a keyboard shortcut on macOS" requests that go beyond what System Settings supports.

**What it does:** guides the agent through authoring Karabiner complex modifications as JavaScript that returns a rules array, working within the Duktape ES5.1 sandbox. Covers manipulator anatomy (`from`, `to`, `to_if_alone`, `to_if_held_down`, `conditions`, `parameters`), modifier semantics (`mandatory` / `optional` / `any`), the major condition types (`frontmost_application_if`, `variable_if`, `device_if`, `input_source_if`, `event_changed_if`), shell commands, and stateful variables. Includes worked patterns for app launchers, mode cycling with variables, app-specific remaps, dual-role keys (caps lock as escape/control), and function-key context switching, plus a debugging checklist (EventViewer, log paths, sleep/wake recovery).

## Files of interest

- [`skills/js-complex-modifications/SKILL.md`](./skills/js-complex-modifications/SKILL.md) — the skill body itself, including the five worked patterns and the debugging tips section. Useful as a standalone reference even outside the skill harness.
- [`skills/js-complex-modifications/references/duktape-es5-constraints.md`](./skills/js-complex-modifications/references/duktape-es5-constraints.md) — what's available and what isn't in Duktape's ES5.1 runtime: `var` only, no arrow functions, no template literals, no `Map`/`Set`/`Promise`, but `JSON`, common `Array.prototype` methods, and `String.prototype` essentials all work.
- [`skills/js-complex-modifications/references/key-codes.md`](./skills/js-complex-modifications/references/key-codes.md) — full `key_code` reference: letters, numbers, function keys, punctuation, modifiers, arrows, navigation, media, and the Apple-vendor key codes.
- [`skills/js-complex-modifications/references/modifiers-and-conditions.md`](./skills/js-complex-modifications/references/modifiers-and-conditions.md) — deeper coverage of `from.modifiers`, sided modifier variants, and every condition type with example payloads.

## Layout

```
plugins/karabiner/
  .claude-plugin/plugin.json   Claude Code manifest
  .codex-plugin/plugin.json    Codex manifest
  skills/
    js-complex-modifications/
      SKILL.md
      references/
        duktape-es5-constraints.md
        key-codes.md
        modifiers-and-conditions.md
```

No commands, agents, hooks, or scripts ship with this plugin — it is skill-only.
