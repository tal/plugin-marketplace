#!/usr/bin/env python3
"""
Build an HTML preview page of proposed folder icons.

Usage:
    build_preview.py --manifest <manifest.json> --out <preview.html>

Manifest schema:
    [
      {
        "folder_path": "/abs/path/to/Subfolder",
        "current_icon_path": "/abs/path/Subfolder/Icon\\r" or null,
        "proposed_icon_path": "/abs/.../proposals/Subfolder.png",
        "method": "emoji" | "sf-symbol" | "ai-illustration",
        "method_detail": "🎬" | "movieclapper" | "<short prompt>",
        "has_existing_custom_icon": bool
      },
      ...
    ]

The page renders one card per entry: folder name, current icon (rendered
as PNG via sips before this script runs, or null), proposed icon, the
method + detail, and a checkbox.

Folders with has_existing_custom_icon == True get a disabled, unchecked
checkbox by default — the user can still manually flip them on, but the
visual default is "don't touch".

The Export button serializes the checked entries to JSON and downloads
it as iconifier-selection.json. We use plain DOM, no frameworks — the
page should work offline and load instantly.
"""

from __future__ import annotations

import argparse
import base64
import html
import json
import subprocess
import tempfile
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
EXTRACT_ICON_SWIFT = PLUGIN_ROOT / "scripts" / "extract_icon.swift"


def png_to_data_uri(path: Path | None) -> str | None:
    if path is None or not path.exists():
        return None
    data = path.read_bytes()
    return "data:image/png;base64," + base64.b64encode(data).decode()


def render_current_icon_to_png(folder: Path) -> Path | None:
    """Render the existing folder icon (if any) to a tmp PNG for display.

    Uses NSWorkspace.shared.icon(forFile:) via the extract_icon.swift
    helper, which works whether the custom icon is stored in an Icon\\r
    file or in the folder's own resource fork (the path third-party
    tools like `fileicon` use). Callers must only invoke this when the
    folder actually has a custom icon — NSWorkspace happily returns
    the stock blue folder for plain folders, which would lie to the
    preview about the current state.
    """
    out = Path(tempfile.mkstemp(prefix="iconifier-current-", suffix=".png")[1])
    proc = subprocess.run(
        ["swift", str(EXTRACT_ICON_SWIFT), str(folder), str(out), "256"],
        capture_output=True,
    )
    if proc.returncode != 0 or not out.exists() or out.stat().st_size == 0:
        return None
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", required=True)
    p.add_argument("--out", required=True)
    p.add_argument(
        "--allow-overwrite",
        action="store_true",
        help=(
            "Don't lock checkboxes for folders that already have a custom icon. "
            "Use when the user explicitly chose 'regenerate all to compare' from "
            "step 2.5 of the skill."
        ),
    )
    args = p.parse_args()

    manifest = json.loads(Path(args.manifest).read_text())

    cards = []
    for entry in manifest:
        folder = Path(entry["folder_path"])
        if entry.get("current_icon_path"):
            current_png = Path(entry["current_icon_path"])
        elif entry.get("has_existing_custom_icon"):
            current_png = render_current_icon_to_png(folder)
        else:
            current_png = None
        cards.append({
            "folder_path": str(folder),
            "folder_name": folder.name,
            "current_icon_uri": png_to_data_uri(current_png),
            "proposed_icon_uri": png_to_data_uri(Path(entry["proposed_icon_path"])),
            "method": entry["method"],
            "method_detail": entry.get("method_detail", ""),
            "has_existing_custom_icon": bool(entry["has_existing_custom_icon"]),
            "proposed_icon_path": entry["proposed_icon_path"],
        })

    html_doc = (
        TEMPLATE
        .replace("__CARDS_JSON__", json.dumps(cards))
        .replace("__ALLOW_OVERWRITE__", "true" if args.allow_overwrite else "false")
    )
    Path(args.out).write_text(html_doc)
    print(args.out)
    return 0


TEMPLATE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>iconifier preview</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 14px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
         margin: 0; padding: 24px; background: Canvas; color: CanvasText; }
  header { display: flex; justify-content: space-between; align-items: center;
           margin-bottom: 16px; gap: 12px; }
  h1 { font-size: 18px; margin: 0; font-weight: 600; }
  .meta { color: GrayText; font-size: 13px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
          gap: 16px; }
  .card { border: 1px solid color-mix(in oklab, CanvasText 15%, transparent);
          border-radius: 12px; padding: 16px; display: flex; flex-direction: column;
          align-items: center; gap: 8px; background: color-mix(in oklab, Canvas 96%, CanvasText 4%); }
  .card.locked { opacity: 0.55; }
  .card.replace { outline: 1px dashed color-mix(in oklab, CanvasText 35%, transparent); }
  .pair { display: flex; gap: 8px; align-items: center; justify-content: center; min-height: 132px; }
  .pair img { width: 110px; height: 110px; image-rendering: -webkit-optimize-contrast; }
  .pair .arrow { color: GrayText; font-size: 18px; }
  .pair .placeholder { width: 110px; height: 110px; border: 1px dashed GrayText; border-radius: 8px;
                       display: flex; align-items: center; justify-content: center;
                       color: GrayText; font-size: 11px; text-align: center; padding: 4px; }
  .name { font-weight: 600; font-size: 13px; word-break: break-word; text-align: center; }
  .method { font-size: 11px; color: GrayText; text-align: center; }
  label.apply { display: flex; align-items: center; gap: 6px; font-size: 13px; }
  .actions { position: sticky; bottom: 0; background: Canvas; padding: 12px 0;
             margin-top: 16px; display: flex; gap: 12px; align-items: center;
             border-top: 1px solid color-mix(in oklab, CanvasText 15%, transparent); }
  button { font: inherit; padding: 8px 14px; border-radius: 8px;
           border: 1px solid color-mix(in oklab, CanvasText 30%, transparent);
           background: color-mix(in oklab, Canvas 90%, CanvasText 10%); color: CanvasText; cursor: pointer; }
  button.primary { background: SystemAccent; color: white; border-color: SystemAccent; }
  .count { color: GrayText; font-size: 13px; }
</style>
</head>
<body>
<header>
  <h1>iconifier — preview</h1>
  <span class="meta">Disabled cards already have a custom icon and won't be touched. Tick to override.</span>
</header>
<div class="grid" id="grid"></div>
<div class="actions">
  <button class="primary" id="export">Export selection</button>
  <button id="select-all">Select all unlocked</button>
  <button id="clear">Clear</button>
  <span class="count" id="count"></span>
</div>
<script>
const cards = __CARDS_JSON__;
const allowOverwrite = __ALLOW_OVERWRITE__;
const grid = document.getElementById("grid");
const countEl = document.getElementById("count");

function renderCard(c, idx) {
  const div = document.createElement("div");
  // "locked" = has an existing icon AND the user didn't opt into overwriting.
  // In that case the checkbox is disabled. Otherwise existing-icon cards
  // are still distinguishable (dimmer) but the user can opt-in per card.
  const locked = c.has_existing_custom_icon && !allowOverwrite;
  div.className = "card" + (locked ? " locked" : (c.has_existing_custom_icon ? " replace" : ""));
  const current = c.current_icon_uri
    ? `<img src="${c.current_icon_uri}" alt="current icon">`
    : `<div class="placeholder">no custom icon</div>`;
  const proposed = c.proposed_icon_uri
    ? `<img src="${c.proposed_icon_uri}" alt="proposed icon">`
    : `<div class="placeholder">generation failed</div>`;
  // Default-checked rules:
  //   no existing icon                                 -> checked
  //   existing icon, allowOverwrite=false (locked)     -> unchecked + disabled
  //   existing icon, allowOverwrite=true  (replace)    -> unchecked + enabled
  const checked = !c.has_existing_custom_icon ? "checked" : "";
  const disabled = locked ? "disabled" : "";
  div.innerHTML = `
    <div class="pair">${current}<span class="arrow">→</span>${proposed}</div>
    <div class="name">${c.folder_name}</div>
    <div class="method">${c.method}${c.method_detail ? ' · ' + c.method_detail : ''}</div>
    <label class="apply">
      <input type="checkbox" data-idx="${idx}" ${checked} ${disabled}>
      ${locked ? "Already iconified" : (c.has_existing_custom_icon ? "Replace" : "Apply")}
    </label>
  `;
  grid.appendChild(div);
}
cards.forEach(renderCard);

function refreshCount() {
  const checked = document.querySelectorAll('input[type=checkbox]:checked').length;
  countEl.textContent = `${checked} of ${cards.length} selected`;
}
grid.addEventListener("change", refreshCount);
refreshCount();

document.getElementById("select-all").onclick = () => {
  document.querySelectorAll('input[type=checkbox]').forEach((cb, i) => {
    // Only flip enabled checkboxes — disabled ones stay locked.
    if (!cb.disabled) cb.checked = true;
  });
  refreshCount();
};
document.getElementById("clear").onclick = () => {
  document.querySelectorAll('input[type=checkbox]').forEach(cb => cb.checked = false);
  refreshCount();
};
document.getElementById("export").onclick = () => {
  const selection = [];
  document.querySelectorAll('input[type=checkbox]:checked').forEach(cb => {
    const c = cards[cb.dataset.idx];
    selection.push({
      folder_path: c.folder_path,
      proposed_icon_path: c.proposed_icon_path,
      method: c.method,
      method_detail: c.method_detail,
    });
  });
  const blob = new Blob([JSON.stringify({selection, exported_at: new Date().toISOString()}, null, 2)],
    {type: "application/json"});
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "iconifier-selection.json";
  document.body.appendChild(a); a.click(); a.remove();
};
</script>
</body>
</html>
"""


if __name__ == "__main__":
    raise SystemExit(main())
