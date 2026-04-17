---
name: karabiner-js-modifications
description: >
  This skill should be used when the user asks to "write Karabiner rules", "create a karabiner
  complex modification", "remap keys on macOS", "edit karabiner.json", "set up keyboard shortcuts
  with Karabiner", "debug a Karabiner rule", or mentions Karabiner-Elements, key_code mappings,
  modifier remapping, or app-specific hotkeys on macOS. Also triggers on any request to remap
  keys or create keyboard shortcuts on macOS beyond what System Settings offers. Guides writing
  Karabiner-Elements complex modification rules in JavaScript (Duktape ES5.1) that generate JSON,
  instead of hand-authoring deeply nested JSON.
---

# Karabiner-Elements: JavaScript Complex Modifications

Since v15.9.6, Karabiner-Elements lets you write complex modification rules in JavaScript that generate JSON, instead of hand-writing deeply nested JSON. The JS is evaluated by a built-in Duktape engine.

## When to use JS vs raw JSON

JS shines when rules have repetitive structure -- cycling through modes, generating per-app overrides, mapping ranges of keys. For a single simple remapping, raw JSON is fine. But once there are 3+ manipulators with similar shapes, JS pays for itself in readability and maintainability.

## How it works

1. Open Karabiner-Elements Settings > Complex Modifications
2. Click **"Add your own rule using JavaScript"**
3. The built-in editor opens with a sample script
4. The JS returns a JSON array of rules. Karabiner evaluates it and applies the result.
5. Save with Cmd+S

CLI alternative: `karabiner_cli --eval-js <path-to-js-file>`

## Duktape / ES5.1 constraints

The JS engine is **Duktape**, which only supports **ES5.1**. This means:

- Use `var`, not `let` or `const`
- Use `function() {}`, not arrow functions `() => {}`
- No template literals -- use string concatenation with `+`
- No destructuring, spread, default params, or `for...of`
- No `Array.from`, `Object.entries`, `Map`, `Set`, `Promise`
- `JSON.stringify` and `JSON.parse` are available
- `Array.prototype.map`, `.filter`, `.forEach`, `.indexOf` work fine

See `references/duktape-es5-constraints.md` for the full list of what's available and what isn't.

## Rule structure

Every JS script must return an array of rule objects. Each rule has a `description` and a `manipulators` array:

```javascript
// The script's return value is the rules array
[
  {
    "description": "My rule",
    "manipulators": [
      {
        "type": "basic",
        "from": { "key_code": "a", "modifiers": { "mandatory": ["control"] } },
        "to": [{ "key_code": "b" }]
      }
    ]
  }
]
```

## Core concepts

### Manipulator fields

| Field | Purpose |
|-------|---------|
| `from` | The key + modifiers to match |
| `to` | Events to emit when the key is pressed |
| `to_if_alone` | Events to emit if the key is pressed and released without other keys |
| `to_if_held_down` | Events to emit if the key is held |
| `to_after_key_up` | Events to emit after the key is released |
| `to_delayed_action` | Events for delayed press/cancel behavior |
| `conditions` | When this manipulator should be active (app, variable, device, etc.) |
| `parameters` | Timing parameters (alone timeout, held threshold, etc.) |

### Modifiers

In the `from.modifiers` object:
- `mandatory`: modifiers that **must** be held (the event won't match without them)
- `optional`: modifiers that **may** be held (won't prevent matching)

Set `"optional": ["any"]` to allow the rule to fire regardless of extra modifiers being held.

Modifier names: `control`, `shift`, `option`, `command`, `caps_lock`, `fn`
Sided variants: `left_control`, `right_control`, `left_shift`, `right_shift`, `left_option`, `right_option`, `left_command`, `right_command`

### Conditions

Conditions control when a manipulator is active:

- **`frontmost_application_if` / `frontmost_application_unless`** -- match by bundle ID regex
- **`variable_if` / `variable_unless`** -- match on internal variables (set via `set_variable`)
- **`device_if` / `device_unless`** -- match by vendor_id / product_id
- **`input_source_if` / `input_source_unless`** -- match by keyboard input source
- **`event_changed_if` / `event_changed_unless`** -- match if keys were recently changed

### Shell commands

Set `"shell_command"` in `to` to run arbitrary commands:
```javascript
{ "shell_command": "open -a 'Ghostty'" }
```

### Variables

Set and check variables to create stateful rules (mode switching, toggles):
```javascript
// Set a variable
{ "set_variable": { "name": "my_mode", "value": 1 } }

// Check a variable in conditions
{ "name": "my_mode", "type": "variable_if", "value": 1 }
```

Unset variables default to `0`.

See `references/key-codes.md` for the full key_code reference and `references/modifiers-and-conditions.md` for detailed condition/modifier docs.

## Patterns

### Pattern 1: App launcher (simple)

Map a hotkey to open an app:

```javascript
[{
  description: "Ctrl+1 to launch VS Code",
  manipulators: [{
    type: "basic",
    from: {
      key_code: "1",
      modifiers: { mandatory: ["control"], optional: ["any"] }
    },
    to: [{ shell_command: "open -a 'Visual Studio Code'" }]
  }]
}]
```

### Pattern 2: Mode cycling with variables

Cycle through modes with a single key, using variables to track state. This is much cleaner in JS than writing N separate manipulators by hand:

```javascript
// Cycle through terminal apps with Ctrl+0, launch the active one with Ctrl+`
var modes = [
  { value: 0, name: "Ghostty", app: "Ghostty" },
  { value: 1, name: "Warp", app: "Warp" },
  { value: 2, name: "cmux", app: "cmux" }
];

var cycleManipulators = modes.map(function(mode, i) {
  var next = modes[(i + 1) % modes.length];
  return {
    type: "basic",
    conditions: [{ name: "terminal_mode", type: "variable_if", value: mode.value }],
    from: { key_code: "0", modifiers: { mandatory: ["control"], optional: ["any"] } },
    to: [
      { set_variable: { name: "terminal_mode", value: next.value } },
      { shell_command: "osascript -e 'display notification \"Terminal: " + next.name + "\" with title \"Terminal Mode Switched\"'" }
    ]
  };
});

var launchManipulators = modes.map(function(mode) {
  return {
    type: "basic",
    conditions: [{ name: "terminal_mode", type: "variable_if", value: mode.value }],
    from: { key_code: "grave_accent_and_tilde", modifiers: { mandatory: ["control"], optional: ["any"] } },
    to: [{ shell_command: "open -a '" + mode.app + "'" }]
  };
});

// Return both rules
[
  { description: "Ctrl+0 to cycle terminal mode", manipulators: cycleManipulators },
  { description: "Ctrl+` to launch active terminal", manipulators: launchManipulators }
]
```

This replaces ~100 lines of JSON with ~25 lines of readable JS.

### Pattern 3: App-specific remapping

Remap keys only in specific apps using bundle ID conditions:

```javascript
var appRemaps = [
  { app: "^com\\.tinyspeck\\.slackmacgap$", from_key: "p", to_key: "k", desc: "Cmd+P to Cmd+K in Slack" },
  { app: "^com\\.apple\\.dt\\.Xcode$", from_key: "p", to_key: "o", to_mods: ["left_command", "left_shift"], desc: "Cmd+P to Cmd+Shift+O in Xcode" }
];

appRemaps.map(function(r) {
  var toMods = r.to_mods || ["left_command"];
  return {
    description: r.desc,
    manipulators: [{
      type: "basic",
      conditions: [{ bundle_identifiers: [r.app], type: "frontmost_application_if" }],
      from: { key_code: r.from_key, modifiers: { mandatory: ["command"] } },
      to: [{ key_code: r.to_key, modifiers: toMods }]
    }]
  };
});
```

### Pattern 4: Dual-role keys

Caps Lock as Escape on tap, Control on hold:

```javascript
[{
  description: "Caps Lock: Escape on tap, Control on hold",
  manipulators: [{
    type: "basic",
    from: { key_code: "caps_lock", modifiers: { optional: ["any"] } },
    to: [{ key_code: "left_control" }],
    to_if_alone: [{ key_code: "escape" }]
  }]
}]
```

### Pattern 5: Function key context switching

Use function keys normally in dev tools, media keys everywhere else:

```javascript
var devApps = [
  "^com\\.microsoft\\.VSCode$",
  "^com\\.jetbrains\\.",
  "^com\\.apple\\.dt\\.Xcode$"
];

var fnKeys = [];
for (var i = 1; i <= 12; i++) {
  fnKeys.push({
    type: "basic",
    conditions: [{ bundle_identifiers: devApps, type: "frontmost_application_unless" }],
    from: { key_code: "f" + i, modifiers: { optional: ["any"] } },
    to: [{ apple_vendor_top_case_key_code: "keyboard_fn" }]
    // Karabiner handles the actual media key mapping
  });
}

[{ description: "Function keys as media keys outside dev apps", manipulators: fnKeys }]
```

## Debugging tips

- **Use EventViewer** (in Karabiner-Elements menu bar) to inspect which key_codes and modifiers are being sent on keypress. This is the single most useful debugging tool.
- **Check the logs** at `/var/log/karabiner/` (core_service, grabber) and `~/.local/share/karabiner/log/` (console_user_server) for errors.
- **Variables start at 0** -- when `variable_if` conditions check for specific values but the variable was never set, the default is `0`. Ensure a manipulator matches `value: 0`.
- **Rule order matters** -- manipulators are evaluated top to bottom within a rule, and rules are evaluated in the order they appear. The first match wins.
- **`osascript` permissions** -- shell commands using `osascript` to send keystrokes need accessibility permissions. Commands like `open -a` don't have this issue.
- **Sleep/wake issues** -- the Karabiner-Core-Service (root daemon) can get stuck after sleep/wake cycles. The in-app "Restart" only restarts user-level processes. If rules stop working, a full system reboot restarts the root daemons too.
- **CLI diagnostic**: `karabiner_cli --list-system-variables` should respond instantly. If it hangs, the core service needs restarting.
