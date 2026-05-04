#!/usr/bin/env python3
"""
Composite an emoji or SF Symbol glyph onto Apple's stock macOS folder icon.

Usage:
    compose_folder_icon.py --emoji <emoji> --out <path>
    compose_folder_icon.py --sf-symbol <name> --out <path>
    compose_folder_icon.py --image <path>     --out <path>   # for AI gen output

The script extracts /System/Library/CoreServices/CoreTypes.bundle's
GenericFolderIcon.icns to a cached PNG on first run, then composites the
glyph in the lower-front face of the folder (centered, ~50% width).

We deliberately render a single 1024x1024 PNG. The Swift apply step
re-renders to all the sizes NSWorkspace expects.

Why we don't ship a folder PNG: Apple's GenericFolderIcon shape evolves
between OS releases (Big Sur, Sonoma, Sequoia), and shipping our own
copy would lock the user's icons to whatever shape we baked in. Reading
the system copy means the icons match the host's current OS aesthetic.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
ASSETS = PLUGIN_ROOT / "assets"
FOLDER_BASE_PNG = ASSETS / "folder-base-1024.png"
SYSTEM_FOLDER_ICNS = Path(
    "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericFolderIcon.icns"
)


def ensure_folder_base() -> Path:
    """Cache a 1024x1024 PNG of the system folder icon."""
    if FOLDER_BASE_PNG.exists() and FOLDER_BASE_PNG.stat().st_size > 0:
        return FOLDER_BASE_PNG
    if not SYSTEM_FOLDER_ICNS.exists():
        raise SystemExit(
            f"compose_folder_icon: system folder icns not found at {SYSTEM_FOLDER_ICNS}; "
            "is this macOS?"
        )
    ASSETS.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="iconifier-base-") as tmp:
        tmp_dir = Path(tmp)
        # `iconutil -c iconset` extracts all the sizes; we pick the largest.
        iconset_dir = tmp_dir / "GenericFolderIcon.iconset"
        subprocess.run(
            ["iconutil", "-c", "iconset", str(SYSTEM_FOLDER_ICNS),
             "-o", str(iconset_dir)],
            check=True, capture_output=True,
        )
        # Prefer 1024x1024 — fall back to whatever's largest.
        candidates = sorted(iconset_dir.glob("*.png"), key=lambda p: p.stat().st_size, reverse=True)
        if not candidates:
            raise SystemExit("compose_folder_icon: iconutil produced no PNGs")
        chosen = candidates[0]
        # Normalize to 1024x1024 with sips so downstream math is simple.
        subprocess.run(
            ["sips", "-z", "1024", "1024", str(chosen),
             "--out", str(FOLDER_BASE_PNG)],
            check=True, capture_output=True,
        )
    return FOLDER_BASE_PNG


def render_emoji_png(emoji: str, size: int = 512) -> Path:
    """Render a single emoji to a transparent PNG via Core Image / Cocoa.

    We shell out to a tiny Swift snippet because Pillow can't render
    color emoji on macOS reliably without the user installing a font.
    """
    swift = f'''
    import AppKit
    let s = "{emoji}"
    let size = CGFloat({size})
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size * 0.78)
    ]
    let attr = NSAttributedString(string: s, attributes: attrs)
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    NSColor.clear.set()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
    let ts = attr.size()
    attr.draw(at: NSPoint(x: (size - ts.width) / 2, y: (size - ts.height) / 2 - size * 0.05))
    img.unlockFocus()
    let tiff = img.tiffRepresentation!
    let bmp = NSBitmapImageRep(data: tiff)!
    let png = bmp.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    '''
    out = Path(tempfile.mkstemp(prefix="iconifier-emoji-", suffix=".png")[1])
    subprocess.run(["swift", "-", str(out)], input=swift, text=True, check=True)
    return out


def render_sf_symbol_png(name: str, size: int = 512) -> Path:
    """Render an SF Symbol to a transparent PNG.

    We default to a hierarchical (semi-tinted) rendering with a dark slate
    color so the glyph sits cleanly on the blue folder. SF Symbols requires
    macOS 11+ which we already require for everything else.
    """
    swift = f'''
    import AppKit
    let name = "{name}"
    let size = CGFloat({size})
    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.7, weight: .semibold)
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else {{
        FileHandle.standardError.write("compose_folder_icon: SF Symbol \\\"\\(name)\\\" not found\\n".data(using: .utf8)!)
        exit(2)
    }}
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    NSColor.clear.set()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
    let s = sym.size
    let origin = NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2)
    NSColor(calibratedRed: 0.18, green: 0.32, blue: 0.55, alpha: 0.92).set()
    sym.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    img.unlockFocus()
    let tiff = img.tiffRepresentation!
    let bmp = NSBitmapImageRep(data: tiff)!
    let png = bmp.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    '''
    out = Path(tempfile.mkstemp(prefix="iconifier-sfsym-", suffix=".png")[1])
    proc = subprocess.run(
        ["swift", "-", str(out)],
        input=swift, text=True, check=False,
        capture_output=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        raise SystemExit(proc.returncode)
    return out


def composite(base_png: Path, glyph_png: Path, out: Path) -> None:
    """Composite glyph onto the lower-front face of the folder.

    The folder front face on Big Sur+ occupies roughly the lower 70% of
    the canvas, centered. Drawing the glyph at 50% width, slightly low
    of center reads correctly at every Finder size from 16x16 to 512x512.
    """
    swift = f'''
    import AppKit
    let basePath = CommandLine.arguments[1]
    let glyphPath = CommandLine.arguments[2]
    let outPath  = CommandLine.arguments[3]

    guard let base  = NSImage(contentsOfFile: basePath),
          let glyph = NSImage(contentsOfFile: glyphPath) else {{
        FileHandle.standardError.write("composite: failed to load images\\n".data(using: .utf8)!)
        exit(2)
    }}
    let size = base.size
    let canvas = NSImage(size: size)
    canvas.lockFocus()
    base.draw(in: NSRect(origin: .zero, size: size))
    let gw = size.width  * 0.52
    let gh = size.height * 0.52
    let gx = (size.width  - gw) / 2
    let gy = (size.height - gh) / 2 - size.height * 0.06
    glyph.draw(in: NSRect(x: gx, y: gy, width: gw, height: gh))
    canvas.unlockFocus()
    let tiff = canvas.tiffRepresentation!
    let bmp  = NSBitmapImageRep(data: tiff)!
    let png  = bmp.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: outPath))
    '''
    subprocess.run(
        ["swift", "-", str(base_png), str(glyph_png), str(out)],
        input=swift, text=True, check=True,
    )


def main() -> int:
    p = argparse.ArgumentParser()
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--emoji")
    src.add_argument("--sf-symbol")
    src.add_argument("--image", help="pre-rendered glyph PNG (e.g. AI gen output)")
    p.add_argument("--out", required=True)
    args = p.parse_args()

    base = ensure_folder_base()

    if args.emoji:
        glyph = render_emoji_png(args.emoji)
        cleanup = glyph
    elif args.sf_symbol:
        glyph = render_sf_symbol_png(args.sf_symbol)
        cleanup = glyph
    else:
        glyph = Path(args.image)
        cleanup = None

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    composite(base, glyph, out)
    if cleanup is not None:
        try:
            cleanup.unlink()
        except OSError:
            pass
    print(str(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
