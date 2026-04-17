# Karabiner-Elements Key Codes Reference

## Letter keys
`a` through `z`

## Number keys
`0` through `9`

## Function keys
`f1` through `f24`

## Punctuation and symbols

| Key | key_code |
|-----|----------|
| `` ` ~ `` | `grave_accent_and_tilde` |
| `- _` | `hyphen` |
| `= +` | `equal_sign` |
| `[ {` | `open_bracket` |
| `] }` | `close_bracket` |
| `\ \|` | `backslash` |
| `; :` | `semicolon` |
| `' "` | `quote` |
| `, <` | `comma` |
| `. >` | `period` |
| `/ ?` | `slash` |

## Modifier keys

| Key | key_code |
|-----|----------|
| Caps Lock | `caps_lock` |
| Left Shift | `left_shift` |
| Right Shift | `right_shift` |
| Left Control | `left_control` |
| Right Control | `right_control` |
| Left Option | `left_option` |
| Right Option | `right_option` |
| Left Command | `left_command` |
| Right Command | `right_command` |
| Fn | `fn` |

## Navigation

| Key | key_code |
|-----|----------|
| Return | `return_or_enter` |
| Escape | `escape` |
| Delete (Backspace) | `delete_or_backspace` |
| Forward Delete | `delete_forward` |
| Tab | `tab` |
| Spacebar | `spacebar` |
| Up Arrow | `up_arrow` |
| Down Arrow | `down_arrow` |
| Left Arrow | `left_arrow` |
| Right Arrow | `right_arrow` |
| Page Up | `page_up` |
| Page Down | `page_down` |
| Home | `home` |
| End | `end` |

## Keypad

| Key | key_code |
|-----|----------|
| Num Lock | `keypad_num_lock` |
| Keypad / | `keypad_slash` |
| Keypad * | `keypad_asterisk` |
| Keypad - | `keypad_hyphen` |
| Keypad + | `keypad_plus` |
| Keypad Enter | `keypad_enter` |
| Keypad . | `keypad_period` |
| Keypad 0-9 | `keypad_0` through `keypad_9` |
| Keypad = | `keypad_equal_sign` |

## Special keys

| Key | key_code |
|-----|----------|
| Print Screen | `print_screen` |
| Scroll Lock | `scroll_lock` |
| Pause | `pause` |
| Insert | `insert` |
| Menu | `application` |

## International keys

| Key | key_code |
|-----|----------|
| International 1 | `international1` |
| International 2 | `international2` |
| International 3 | `international3` |
| Language 1 (Kana) | `lang1` |
| Language 2 (Eisuu) | `lang2` |

## Consumer / media keys (for `to` events)

These use `consumer_key_code` instead of `key_code`:

| Function | consumer_key_code |
|----------|-------------------|
| Volume Up | `volume_increment` |
| Volume Down | `volume_decrement` |
| Mute | `mute` |
| Play/Pause | `play_or_pause` |
| Next Track | `fastforward` |
| Previous Track | `rewind` |
| Brightness Up | `display_brightness_increment` |
| Brightness Down | `display_brightness_decrement` |
| Eject | `eject` |

Example using consumer keys:
```javascript
{ consumer_key_code: "volume_increment" }  // not key_code
```

## Apple vendor keys (for `to` events)

These use `apple_vendor_keyboard_key_code` or `apple_vendor_top_case_key_code`:

| Function | Field | Value |
|----------|-------|-------|
| Mission Control | apple_vendor_keyboard_key_code | `mission_control` |
| Spotlight | apple_vendor_keyboard_key_code | `spotlight` |
| Launchpad | apple_vendor_keyboard_key_code | `launchpad` |
| Fn key | apple_vendor_top_case_key_code | `keyboard_fn` |

## Pointing button (mouse)

Use `pointing_button` instead of `key_code`:

| Button | pointing_button |
|--------|-----------------|
| Left click | `button1` |
| Right click | `button2` |
| Middle click | `button3` |
| Button 4-32 | `button4` through `button32` |
