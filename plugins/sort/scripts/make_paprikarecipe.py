#!/usr/bin/env python3
"""Write a single Paprika `.paprikarecipe` sidecar next to a recipe note.

Pure standard library — no `paprika-recipes` install required. A
`.paprikarecipe` file is just gzip-compressed JSON in Paprika's schema;
this reproduces that schema (and its sha256 `hash`) faithfully.

Invoked by the sort-videos skill ONLY when the user opts in via
`paprika_sidecar: enabled` in sort.md. Reads a JSON payload (from a file
arg or stdin) describing one recipe and emits `<base>.paprikarecipe`
beside the note.

Payload schema (only `note_path` is required; everything else is optional):
  {
    "note_path":   "/abs/AI Library/Recipes/<base>.md",   # placement + uid seed
    "photo_path":  "/abs/frame.jpg",        # if omitted, first frame of sibling .mp4
    "name":        "Banana Almond Bark",
    "description": "...",
    "ingredients": "2 ripe bananas\n2 cups almond meal",   # newline-separated
    "directions":  "1. Mash bananas.\n2. Stir in almond meal.",
    "notes":       "...",
    "source":      "carlyfowler_",          # creator handle
    "source_url":  "https://www.instagram.com/reel/XXXX/",
    "prep_time": "", "cook_time": "", "total_time": "", "servings": "",
    "categories":  ["AI Library", "Snack"], # if omitted, derived from note tags
    "is_reconstructed": false                # adds "Reconstructed" category
  }

Usage:
  make_paprikarecipe.py payload.json
  cat payload.json | make_paprikarecipe.py -
"""
import base64
import datetime
import gzip
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

# Stable namespace so the same note always yields the same uid (idempotent re-runs,
# and uid-keyed cloud-sync dedup rather than duplicate recipes).
NS = uuid.UUID("6f1b8a4e-0000-4000-8000-000000000000")

MEAL = {"breakfast": "Breakfast", "brunch": "Brunch", "lunch": "Lunch",
        "dinner": "Dinner", "snack": "Snack", "dessert": "Dessert", "side": "Side"}


def frontmatter_tags(md_path: Path):
    if not md_path.exists():
        return []
    txt = md_path.read_text(encoding="utf-8")
    m = re.search(r"^tags:\s*\[(.*)\]\s*$", txt, re.M)
    if not m:
        return []
    return [t.strip().strip("'\"") for t in m.group(1).split(",") if t.strip()]


def derive_categories(note_path: Path, reconstructed: bool):
    cats = ["AI Library"]
    for t in frontmatter_tags(note_path):
        if t in MEAL and MEAL[t] not in cats:
            cats.append(MEAL[t])
    if reconstructed:
        cats.append("Reconstructed")
    return cats


def first_frame_jpeg(mp4: Path):
    """Extract the first frame of a sibling .mp4 to JPEG bytes, or return None."""
    if not mp4.exists() or not shutil.which("ffmpeg"):
        return None
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tf:
        tmp = Path(tf.name)
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(mp4),
             "-vf", "select=eq(n\\,0)", "-frames:v", "1", str(tmp)],
            check=True,
        )
        data = tmp.read_bytes()
        return data or None
    except subprocess.CalledProcessError:
        return None
    finally:
        tmp.unlink(missing_ok=True)


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "-"
    raw = sys.stdin.read() if arg == "-" else Path(arg).read_text(encoding="utf-8")
    p = json.loads(raw)

    note_path = Path(p["note_path"])
    # Strip ONLY the .md extension via string slicing — do not use Path.with_suffix(),
    # which mis-parses base names that contain a dot (e.g. "Video by whatmolly.eats").
    name = note_path.name
    stem = name[:-3] if name.endswith(".md") else name
    out = note_path.parent / (stem + ".paprikarecipe")

    cats = p.get("categories") or derive_categories(note_path, p.get("is_reconstructed", False))

    # Photo: explicit path, else first frame of the sibling video.
    photo_bytes = None
    if p.get("photo_path"):
        pp = Path(p["photo_path"])
        if pp.exists():
            photo_bytes = pp.read_bytes()
    if photo_bytes is None:
        photo_bytes = first_frame_jpeg(note_path.parent / (stem + ".mp4"))

    photo_data = photo_hash = photo_name = ""
    if photo_bytes:
        photo_data = base64.b64encode(photo_bytes).decode("ascii")
        photo_hash = hashlib.sha256(photo_bytes).hexdigest()
        photo_name = re.sub(r"[^A-Za-z0-9._-]", "_", stem)[:60] + ".jpg"

    # Preserve original `created` on re-run so unchanged content yields a stable file.
    created = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    if out.exists():
        try:
            prev = json.loads(gzip.decompress(out.read_bytes()))
            created = prev.get("created", created)
        except Exception:
            pass

    recipe = {
        "categories": cats,
        "cook_time": p.get("cook_time", "") or "",
        "created": created,
        "description": p.get("description", "") or "",
        "difficulty": "",
        "directions": p.get("directions", "") or "",
        "image_url": "",
        "ingredients": p.get("ingredients", "") or "",
        "name": (p.get("name") or stem).strip(),
        "notes": p.get("notes", "") or "",
        "nutritional_info": "",
        "photo": photo_name,
        "photo_hash": photo_hash,
        "photo_large": None,
        "photos": [],
        "photo_data": photo_data if photo_data else None,
        "prep_time": p.get("prep_time", "") or "",
        "rating": 0,
        "servings": p.get("servings", "") or "",
        "source": p.get("source", "") or "",
        "source_url": p.get("source_url", "") or "",
        "total_time": p.get("total_time", "") or "",
        "uid": str(uuid.uuid5(NS, stem)).upper(),
    }
    recipe["hash"] = hashlib.sha256(
        json.dumps(recipe, sort_keys=True).encode("utf-8")
    ).hexdigest()

    out.write_bytes(gzip.compress(json.dumps(recipe).encode("utf-8")))
    print(f"wrote {out.name}  [{','.join(cats)}]  {'photo' if photo_data else 'NO-PHOTO'}")


if __name__ == "__main__":
    main()
