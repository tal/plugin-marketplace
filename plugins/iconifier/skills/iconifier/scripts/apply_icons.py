#!/usr/bin/env python3
"""
Thin wrapper around set_icon.swift. Mostly here to provide nicer error
messages and to give the SKILL.md one consistent invocation surface.

Usage:
    apply_icons.py <selection.json>

Exits 0 if all entries applied, 1 if any failed. Prints a short summary
to stdout: "iconifier: applied N, failed M".
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
SET_ICON_SWIFT = PLUGIN_ROOT / "scripts" / "set_icon.swift"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: apply_icons.py <selection.json>", file=sys.stderr)
        return 2

    selection_path = Path(sys.argv[1])
    if not selection_path.exists():
        print(f"apply_icons: {selection_path} not found", file=sys.stderr)
        return 2

    proc = subprocess.run(
        ["swift", str(SET_ICON_SWIFT), str(selection_path)],
        capture_output=True, text=True,
    )
    sys.stdout.write(proc.stdout)
    if proc.stderr:
        sys.stderr.write(proc.stderr)

    applied = sum(1 for line in proc.stdout.splitlines() if line.startswith("ok "))
    failed  = sum(1 for line in proc.stdout.splitlines() if line.startswith("err "))
    print(f"iconifier: applied {applied}, failed {failed}")
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
