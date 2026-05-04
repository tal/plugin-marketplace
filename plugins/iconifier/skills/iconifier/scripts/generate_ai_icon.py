#!/usr/bin/env python3
"""
Generate a folder-icon-suitable illustration via OpenAI gpt-image-1 or
Google imagen-3.

Usage:
    generate_ai_icon.py --context "<blurb>" --provider openai --out <path>
    generate_ai_icon.py --context "<blurb>" --provider gemini --out <path>

The output is a 1024x1024 PNG with a transparent background. The skill
then passes it to compose_folder_icon.py --image to composite onto the
macOS folder shape.

Prompt template:

    A simple flat icon glyph of {context}, centered on a transparent
    background, single subject, soft rounded shapes, no text, no shadows,
    no border, vibrant but limited color palette, style consistent with
    Apple's SF Symbols and macOS folder-icon glyphs.

The glyph-not-illustration framing matters — gpt-image-1 will happily
generate a full Pixar scene if you ask for "an icon of a coffee shop".
We want the equivalent of an SF Symbol but in color: a single recognizable
shape that reads at 16x16 just as well as 512x512.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.request
from pathlib import Path

PROMPT_TEMPLATE = (
    "A simple flat icon glyph of {context}, centered on a transparent "
    "background, single subject, soft rounded shapes, no text, no shadows, "
    "no border, vibrant but limited color palette, style consistent with "
    "Apple's SF Symbols and macOS folder-icon glyphs."
)


def call_openai(prompt: str, out: Path) -> None:
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        raise SystemExit("generate_ai_icon: OPENAI_API_KEY not set")
    req = urllib.request.Request(
        "https://api.openai.com/v1/images/generations",
        data=json.dumps({
            "model": "gpt-image-1",
            "prompt": prompt,
            "size": "1024x1024",
            "background": "transparent",
            "n": 1,
        }).encode(),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read())
    b64 = body["data"][0]["b64_json"]
    out.write_bytes(base64.b64decode(b64))


def call_gemini(prompt: str, out: Path) -> None:
    key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not key:
        raise SystemExit("generate_ai_icon: GEMINI_API_KEY / GOOGLE_API_KEY not set")
    # imagen-3 via the Generative Language API.
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        "imagen-3.0-generate-002:predict?key=" + key
    )
    req = urllib.request.Request(
        url,
        data=json.dumps({
            "instances": [{"prompt": prompt}],
            "parameters": {"sampleCount": 1, "aspectRatio": "1:1"},
        }).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read())
    b64 = body["predictions"][0]["bytesBase64Encoded"]
    out.write_bytes(base64.b64decode(b64))


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--context", required=True)
    p.add_argument("--provider", choices=["openai", "gemini"], required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--extra", default="", help="extra prompt notes from the user")
    args = p.parse_args()

    prompt = PROMPT_TEMPLATE.format(context=args.context.strip())
    if args.extra:
        prompt += " " + args.extra.strip()

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    if args.provider == "openai":
        call_openai(prompt, out)
    else:
        call_gemini(prompt, out)

    print(str(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
