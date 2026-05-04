# Style detection

This file is read by the SKILL.md when classifying existing custom folder icons. The goal is to decide which of three generation methods the user has implicitly chosen by setting icons elsewhere in the directory:

- **emoji** — a single emoji glyph composited on the system folder shape
- **sf-symbol** — an SF Symbols glyph composited on the system folder shape
- **ai-illustration** — a full custom illustration that doesn't follow the folder shape

The `scripts/detect_existing_style.py` script handles the mechanical part — extracting current icons via `sips`, classifying them, returning the dominant style and a confidence score. This document is for the cases where the script returns `unknown` or low confidence and the model needs to use judgment.

## Signals beyond the script

When the script's confidence is below ~0.6, look at:

- **Sibling folder names** — names like `🎬 movies`, `📚 books`, `🛠 tools` strongly hint emoji even before you look at the icons. Emoji in the *folder name itself* is a near-certain emoji style intent.
- **Parent folder name & icon** — if the parent has a colorful illustration and the children have nothing, the user's pattern may be "illustrated when it's worth it, plain when it isn't" — defaulting to `none` and asking is reasonable.
- **The presence of a `.iconifier` or `_icons/` folder** — sometimes users keep reference assets nearby. Worth a quick check.
- **Folder content type** — folders full of `.app` bundles or codebases lean SF-symbol/illustration; folders full of personal media lean emoji.

## When to override the detected style

The user can always pass an explicit `--method emoji` (or similar) at invocation time, in which case detection is skipped. Beyond that, the only time the SKILL should override the detected style is when:

1. The detected style is `ai-illustration` but no AI key is available — downgrade per SKILL.md step 3.
2. The detection confidence is < 0.4 *and* the contextual signals (folder names, parent name) point strongly elsewhere — in this case favor the contextual signal and note the override in the user-facing summary.

## SF Symbol starter map

When generating SF Symbol icons, the model picks a symbol name. SF Symbols has thousands of names; here's a starter map covering the common folder archetypes — extend as needed.

| Context cue                         | Suggested SF Symbol         |
|-------------------------------------|-----------------------------|
| code project / repo                 | `chevron.left.forwardslash.chevron.right` |
| documents / writing                 | `doc.text`                  |
| images / photos                     | `photo.on.rectangle`        |
| video / movies                      | `film`                      |
| music / audio                       | `music.note`                |
| book / reading                      | `book.closed`               |
| design / mockups                    | `paintbrush`                |
| client work                         | `briefcase`                 |
| finance / receipts                  | `dollarsign.circle`         |
| travel                              | `airplane`                  |
| home / personal                     | `house`                     |
| ai / experiments                    | `sparkles`                  |
| backups / archives                  | `archivebox`                |
| screenshots                         | `camera.viewfinder`         |
| config / dotfiles                   | `gearshape`                 |
| downloads (generic)                 | `arrow.down.circle`         |
| data / spreadsheets                 | `tablecells`                |

When the context suggests something not in the table, prefer a generic but recognizable symbol over a niche one — `briefcase` for any client work beats `building.columns` for "law-firm-shaped client".

## Emoji selection guidance

Emojis carry cultural baggage and aesthetic weight. A few rules:

- **Single emoji per folder.** Multi-emoji compositions ("📚📖🔖") look messy at small sizes. Pick the single most representative one.
- **Prefer object emojis over face emojis** for folder icons. `🏠` reads better than `🤔` for a folder named "house-stuff".
- **Skin-tone modifiers** rarely make sense for folder icons — strip them.
- **Avoid emojis with culturally-charged meanings unless the context demands it.** E.g. `🇺🇸` is fine for a folder of US-related docs, but `🍑` shouldn't be the default for "fruit-photos".

## AI illustration prompt notes

The default prompt template lives in `scripts/generate_ai_icon.py`. When constructing the `--context` argument:

- Lead with the *subject*, not the abstract concept. "A coffee bean" beats "a folder for coffee-related notes".
- One subject only. Compositions confuse small sizes.
- Mention concrete materials/colors only if the user asked. Otherwise let the prompt template's "vibrant but limited color palette" guidance carry it.
- Avoid words like "icon for" or "logo of" — that nudges the model toward generating a literal icon-with-frame, which fights with the folder shape we composite onto. Just describe the subject.
