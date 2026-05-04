# 2026-05-04 — iconifier: render icons set via xattr

## Problem

Running `/iconifier` on a directory whose subfolders had been manually
iconified by a third-party tool (e.g. `fileicon`) produced a preview
where every "current" cell showed the "no custom icon" placeholder,
even though the cards were correctly labeled "Replace" (i.e. detection
already knew there was an existing icon there).

Root cause: both `build_preview.py` and `detect_existing_style.py`
rendered the existing icon by running `sips` against the folder's
`Icon\r` file. Tools like `fileicon` write the icon directly into the
folder's own resource fork via xattr and never create an `Icon\r`
file, so the render path returned `None` and the preview fell back to
the placeholder.

`has_custom_icon` already worked for both storage shapes — only the
render path was broken.

## Fix

- New `scripts/extract_icon.swift` — small helper that calls
  `NSWorkspace.shared.icon(forFile:)` and writes a PNG. Works for
  both Icon\r-style and resource-fork-on-folder-style storage,
  because NSWorkspace doesn't care which one Finder is using.
- `build_preview.py` now calls the Swift helper instead of `sips`
  on `Icon\r`. Render is gated on `has_existing_custom_icon` so we
  don't paint stock blue folders into the "current" column for plain
  folders (NSWorkspace would happily return one).
- `detect_existing_style.py`'s `dump_icon_png` switched to the same
  helper so style classification works for xattr-only icons too.
  Previously those returned `unknown`.

## Verification

End-to-end smoke test:
- Apply an emoji icon to folder A via `apply_icons.py` → it stores
  via `Icon\r`. `extract_icon.swift` returns the composited icon.
- Plain folder B with no icon → `extract_icon.swift` would return the
  stock blue folder, but `build_preview.py` skips it because
  `has_existing_custom_icon: false`. The preview shows null.
- Both paths surface in `build_preview.py` output: 1 data-URI cell,
  1 null cell, matching expectations.
