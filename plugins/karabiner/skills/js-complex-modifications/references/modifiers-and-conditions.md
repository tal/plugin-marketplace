# Modifiers and Conditions Reference

## Modifiers

### In `from.modifiers`

```javascript
from: {
  key_code: "a",
  modifiers: {
    mandatory: ["control", "shift"],  // MUST be held
    optional: ["any"]                 // MAY be held without preventing match
  }
}
```

**Modifier names for `mandatory` and `optional`:**

| Name | Matches |
|------|---------|
| `control` | left_control or right_control |
| `shift` | left_shift or right_shift |
| `option` | left_option or right_option |
| `command` | left_command or right_command |
| `caps_lock` | caps_lock |
| `fn` | fn |
| `any` | any modifier (only valid in `optional`) |
| `left_control` | left_control only |
| `right_control` | right_control only |
| `left_shift` | left_shift only |
| `right_shift` | right_shift only |
| `left_option` | left_option only |
| `right_option` | right_option only |
| `left_command` | left_command only |
| `right_command` | right_command only |

**Common pattern:** Use `"optional": ["any"]` on most rules so they still fire if the user happens to have extra modifiers held.

### In `to` events

When emitting keys in `to`, specify modifiers directly:

```javascript
to: [{
  key_code: "v",
  modifiers: ["left_command", "left_option", "left_shift"]
}]
```

In `to`, always use the sided variants (`left_command`, not `command`).

---

## Conditions

Conditions go in the `conditions` array on a manipulator. Multiple conditions are AND-ed together.

### frontmost_application_if / frontmost_application_unless

Match based on the currently focused app's bundle identifier (regex):

```javascript
{
  type: "frontmost_application_if",
  bundle_identifiers: [
    "^com\\.microsoft\\.VSCode$",
    "^com\\.jetbrains\\."
  ]
}
```

The `bundle_identifiers` array is OR-ed (matches if any pattern matches).

**Finding bundle IDs:** Use Karabiner's EventViewer > Frontmost Application tab, or run:
```bash
osascript -e 'id of app "AppName"'
```

Common bundle IDs:
| App | Bundle ID |
|-----|-----------|
| VS Code | `com.microsoft.VSCode` |
| Xcode | `com.apple.dt.Xcode` |
| Terminal | `com.apple.Terminal` |
| iTerm2 | `com.googlecode.iterm2` |
| Ghostty | `com.mitchellh.ghostty` |
| Warp | `dev.warp.Warp-Stable` |
| Slack | `com.tinyspeck.slackmacgap` |
| Safari | `com.apple.Safari` |
| Chrome | `com.google.Chrome` |
| Firefox | `org.mozilla.firefox` |
| Finder | `com.apple.finder` |

### variable_if / variable_unless

Match on internal variables set by `set_variable`:

```javascript
// Condition
{ name: "my_mode", type: "variable_if", value: 1 }

// Setting the variable (in a `to` event)
{ set_variable: { name: "my_mode", value: 1 } }
```

- Variables default to `0` when unset
- Variable values can be numbers, booleans, or strings
- Variables persist until changed or Karabiner restarts

### device_if / device_unless

Match by physical device:

```javascript
{
  type: "device_if",
  identifiers: [{
    vendor_id: 1452,
    product_id: 832
  }]
}
```

Find device IDs via `karabiner_cli --list-connected-devices` or EventViewer > Devices tab.

Useful for rules that should only apply to specific keyboards (e.g., external keyboard vs built-in).

### input_source_if / input_source_unless

Match by keyboard input source (language/layout):

```javascript
{
  type: "input_source_if",
  input_sources: [{
    language: "en"
  }]
}
```

Can match on `language`, `input_source_id`, or `input_mode_id`.

### event_changed_if / event_changed_unless

Match if a key event was recently modified by another rule:

```javascript
{ type: "event_changed_if", value: true }
```

Useful for creating rules that only apply when another remapping has already fired.

---

## Combining conditions

Multiple conditions are AND-ed:

```javascript
manipulators: [{
  type: "basic",
  conditions: [
    { type: "frontmost_application_if", bundle_identifiers: ["^com\\.apple\\.Terminal$"] },
    { type: "variable_if", name: "vim_mode", value: 1 }
  ],
  from: { key_code: "h" },
  to: [{ key_code: "left_arrow" }]
}]
```

This fires only when Terminal is focused AND `vim_mode` is 1.

To achieve OR logic, create separate manipulators for each condition.
