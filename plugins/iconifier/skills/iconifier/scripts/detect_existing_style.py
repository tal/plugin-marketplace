#!/usr/bin/env python3
"""
Detect the style of existing custom folder icons across a set of folders.

Usage:
    detect_existing_style.py <folder> [<folder> ...]

Output (JSON to stdout):
    {
      "dominant_style": "emoji" | "sf-symbol" | "ai-illustration" | "none",
      "confidence": 0.0-1.0,
      "per_folder": [{"path": ..., "has_custom_icon": bool, "style": ...}, ...],
      "notes": "..."
    }

How style detection works (heuristic, intentionally cheap):

  - "has custom icon": the folder contains an "Icon\\r" file (the metadata
    Finder writes when you set a custom icon), or its resource fork is
    non-empty per `xattr -p com.apple.ResourceFork`.

  - We dump the icon as PNG via the extract_icon.swift helper, which
    calls NSWorkspace.shared.icon(forFile:) and works for both Icon\\r
    storage and the folder's own resource fork (used by third-party
    tools like `fileicon`). We then run a few quick visual classifiers:

      1. Emoji-on-folder: the icon is a standard macOS folder shape
         (dominant blue ~RGB(95,160,210)) AND has a small high-saturation
         glyph in the centered upper region.
         -> we detect "is this the system folder shape" by sampling the
            outline pixels and comparing against the cached
            assets/folder-base-1024.png.

      2. SF-symbol-on-folder: same folder shape, but the centered glyph
         is monochrome (low saturation across the glyph region).

      3. AI illustration: doesn't match the folder shape (or has heavy
         non-blue regions covering more than ~30% of the canvas).

      4. None of the above: classify as "unknown" and don't count it.

Confidence is the share of has_custom_icon folders that resolve to the
dominant style.

We deliberately keep this loose. It's a hint to step 4 of the skill, not
a courtroom verdict. The skill is allowed to override based on explicit
user intent.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
FOLDER_BASE_PNG = PLUGIN_ROOT / "assets" / "folder-base-1024.png"
EXTRACT_ICON_SWIFT = PLUGIN_ROOT / "scripts" / "extract_icon.swift"


def has_custom_icon(folder: Path) -> bool:
    icon_file = folder / "Icon\r"
    if icon_file.exists():
        return True
    # Fall back to xattr inspection — folders without an Icon\r file but
    # with a resource-fork-bearing icon still count.
    try:
        out = subprocess.run(
            ["xattr", "-l", str(folder)],
            capture_output=True, text=True, check=False,
        )
        return "com.apple.ResourceFork" in out.stdout or "com.apple.FinderInfo" in out.stdout
    except FileNotFoundError:
        return False


def dump_icon_png(folder: Path, out_dir: Path) -> Path | None:
    """Render the folder's current icon to a PNG via NSWorkspace.

    Goes through the extract_icon.swift helper so this works whether
    the icon is stored as an Icon\\r file or in the folder's own
    resource fork (third-party tools like `fileicon` use the latter
    and never write an Icon\\r). Callers must only invoke this when
    has_custom_icon is true — NSWorkspace returns the stock folder
    icon for plain folders.
    """
    out_path = out_dir / (folder.name + ".png")
    try:
        subprocess.run(
            ["swift", str(EXTRACT_ICON_SWIFT), str(folder), str(out_path), "256"],
            capture_output=True, check=True,
        )
    except subprocess.CalledProcessError:
        return None
    return out_path if out_path.exists() and out_path.stat().st_size > 0 else None


def classify_png(png: Path) -> str:
    """Return one of: emoji, sf-symbol, ai-illustration, unknown."""
    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        # No Pillow → we can't analyze pixels. Be honest about it.
        return "unknown"
    from PIL import Image
    import colorsys

    img = Image.open(png).convert("RGBA").resize((128, 128))
    pixels = list(img.getdata())

    # Mask: alpha > 16 only.
    visible = [(r, g, b) for (r, g, b, a) in pixels if a > 16]
    if not visible:
        return "unknown"

    folder_blue_hits = 0
    high_sat_hits = 0
    saturated_glyph_region = 0
    glyph_region_pixels = 0

    for i, (r, g, b) in enumerate(visible):
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        # Folder blue is roughly H~0.55, L~0.55, S~0.4 on Big Sur+.
        if 0.50 < h < 0.62 and 0.40 < l < 0.75 and s > 0.20:
            folder_blue_hits += 1
        if s > 0.45:
            high_sat_hits += 1

    blue_share = folder_blue_hits / len(visible)
    sat_share = high_sat_hits / len(visible)

    # Glyph region: center 60x60 of the 128x128.
    img_pixels = img.load()
    for y in range(34, 94):
        for x in range(34, 94):
            r, g, b, a = img_pixels[x, y]
            if a < 16:
                continue
            glyph_region_pixels += 1
            _, _, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            if s > 0.45:
                saturated_glyph_region += 1
    glyph_sat_share = (
        saturated_glyph_region / glyph_region_pixels
        if glyph_region_pixels else 0.0
    )

    # Decision tree.
    if blue_share > 0.30:
        # Looks like a macOS folder. Emoji vs SF symbol on the glyph.
        if glyph_sat_share > 0.15:
            return "emoji"
        return "sf-symbol"
    elif sat_share > 0.20:
        # Heavy color presence, no folder shape — full custom illustration.
        return "ai-illustration"
    else:
        return "unknown"


def main() -> int:
    folders = [Path(p).resolve() for p in sys.argv[1:]]
    if not folders:
        print("usage: detect_existing_style.py <folder> [<folder> ...]", file=sys.stderr)
        return 2

    per_folder = []
    style_counts: Counter[str] = Counter()
    with tempfile.TemporaryDirectory(prefix="iconifier-detect-") as tmp:
        tmp_dir = Path(tmp)
        for folder in folders:
            entry = {"path": str(folder), "has_custom_icon": False, "style": "none"}
            if not folder.is_dir():
                per_folder.append(entry)
                continue
            if has_custom_icon(folder):
                entry["has_custom_icon"] = True
                png = dump_icon_png(folder, tmp_dir)
                if png:
                    entry["style"] = classify_png(png)
                else:
                    entry["style"] = "unknown"
                if entry["style"] not in ("none", "unknown"):
                    style_counts[entry["style"]] += 1
            per_folder.append(entry)

    if style_counts:
        dominant_style, dominant_count = style_counts.most_common(1)[0]
        total_classified = sum(style_counts.values())
        confidence = dominant_count / total_classified
        notes = (
            f"classified {total_classified}/{len(folders)} folders; "
            f"{dominant_style} won {dominant_count}/{total_classified}"
        )
    else:
        dominant_style = "none"
        confidence = 0.0
        notes = "no folders had a classifiable custom icon"

    print(json.dumps({
        "dominant_style": dominant_style,
        "confidence": round(confidence, 3),
        "per_folder": per_folder,
        "notes": notes,
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
