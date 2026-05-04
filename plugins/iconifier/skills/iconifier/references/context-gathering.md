# Context gathering

The skill needs to decide what each subfolder *is about* so the generated icon depicts the right thing. This file is the heuristic for how to do that quickly without dragging the user through twenty questions.

## The signal hierarchy

Pull from these sources in order, stopping as soon as you have a confident one-sentence summary of the folder's purpose:

1. **Top-of-file content of `README.md`, `CLAUDE.md`, or `ABOUT.md`** if present. The first paragraph is usually a direct, prose summary of what the folder is. Read it. Don't chase recursive references.
2. **Project metadata files** — `package.json`'s `description`, `Cargo.toml`'s `description`, `pyproject.toml`'s `description`. These exist precisely to summarize the project.
3. **The folder's name itself**, contextualized by sibling and parent names. A folder named `acme` next to siblings `globex`, `initech` is clearly a client folder; the same name next to `trip-photos`, `recipes` is more ambiguous.
4. **Top-level filenames** — a folder full of `.psd` files is a design folder; a folder full of `.mp4`s is a video folder. A glance is enough.
5. **The user's invocation phrasing** — "iconify my client folders" already tells you the inferred theme. Lean into it.

## When to ask

The only signal that warrants asking the user is *contextual ambiguity that affects the icon choice*. Concretely, ask only when **all** of the following are true:

- After exhausting the hierarchy above, you can't write a one-sentence summary of the folder's purpose with reasonable confidence.
- The folder's name is generic or opaque (`misc`, `temp`, `archive`, `stuff`, a single letter, a date with no context).
- The contents are heterogeneous enough that no file type dominates.

Don't ask just because:
- The folder is private — your guess will still be in the right ballpark.
- The folder is ambiguous *between two reasonable icons* — pick one and let the preview surface the choice. The user can ask for a regen.
- You're worried about getting it wrong — a wrong-but-plausible icon is fine; the preview catches it.

## How to ask

Use `AskUserQuestion` with one question per ambiguous folder, batched in a single tool call. Phrase it as a multiple-choice with 2–3 plausible interpretations plus an "Other" affordance:

> Question: "What's in the folder `~/Downloads/old-stuff/2018-archive`?"
> Options:
>   - "Personal photos / memorabilia"
>   - "Old project files / code"
>   - "Tax documents / paperwork"

The user has invoked a skill called "iconifier" because they want their folders to look nicer with minimal effort. Asking five clarifying questions defeats the purpose. As a rule, batch all clarifications into a single round and never ask about more than ~25% of the target list.

## Context blurb format

The blurb you pass to `compose_folder_icon.py` (as the implicit subject of an emoji/SF-symbol pick) or to `generate_ai_icon.py --context` should be:

- **One short noun phrase** describing the subject — "a coffee bean", "a movie clapperboard", "a stack of receipts".
- **Not** a description of the folder's *purpose* — "a folder for storing my coffee-shop notes" is too meta and trips up gpt-image-1 into rendering a literal folder.
- **Not** the folder name verbatim — `acme-co` doesn't mean anything visual; you might choose "a stylized geometric A" or "an anvil" depending on context.

Examples:

| Folder name        | Context                                 | Blurb                                     |
|--------------------|------------------------------------------|-------------------------------------------|
| `client-acme`      | Sibling client folders, no other clues  | "a stylized geometric letter A"           |
| `2024-receipts`    | Tax-prep parent folder                  | "a stack of paper receipts"               |
| `wedding-photos`   | Personal context                        | "a wedding ring"                          |
| `infra-terraform`  | Code project with `.tf` files           | "a stack of cloud server boxes"           |
| `reading-list`     | Folder of PDFs and `.epub` files        | "an open book"                            |

When the user has given strong direction (e.g. "make them all sci-fi themed"), incorporate that into the blurb directly: "a stylized geometric letter A, sci-fi neon style".
