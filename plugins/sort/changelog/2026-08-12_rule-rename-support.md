# Rename support for `action: prompt` rules

**Date:** 2026-08-12

Added a `rename:` field to the sort rule schema, and used it to consolidate all Loretta
Mulcare billing paperwork into one folder with normalized filenames.

## Why

The rule schema could route files but never rename them. `route` and `route_sensitive` are
pure moves, and `sort-route-by-prompt` was explicitly read-only ("Don't modify, rename, or
write to the file") with a strict one-line reply contract that had nowhere to put a new name.

That's a real gap for provider paperwork. Portal exports arrive named `stmt_88213.pdf` /
`INV_7781.pdf` — the service date and document type are printed *inside* the PDF and nowhere
in the filename. Routing them correctly still leaves a folder nobody can scan.

## What changed

### `rename:` field (plugin-wide)

New optional rule field, valid **only** with `action: prompt`. It holds a natural-language
naming convention, written the same way as `prompt:` — not a format string:

```yaml
rename: |
  roe <4-digit year>-<2-digit month> <superbill|invoice|receipt>
```

There is deliberately no static-rule equivalent. Filling in a convention requires reading the
document, so a `rename:` on `route`/`route_sensitive` would have nothing to read.

| File | Change |
|---|---|
| `agents/sort-route-by-prompt.md` | New `rename` input; reply format gained an optional `\| rename: <basename>` clause on the same line; new "Renaming" section; the blanket "don't rename" constraint now reads as "you propose, the dispatcher applies" |
| `skills/sort/SKILL.md` | §0.5 passes `rename:` into the agent; new "Applying a `rename:` clause" subsection (parse, sanitize, apply); §5 `Destination` column documents showing the new filename |
| `skills/sort/OVERRIDES.md` | `rename:` in the rule shape, a "Renaming" section with a worked example, validation line |
| `scripts/add-rule.rb` | `--rename=` flag; warns and drops it on non-`prompt` actions |
| `scripts/match-rules.rb` | `--rules-only` / match output now renders `rename→ "…"` so you can see it fires |
| `commands/add-rule.md` | Interactive rename question after the agent-prompt step; `rename` added to the shorthand keys |

### Safety decisions worth remembering

- **The extension is never taken from the agent.** It emits a bare basename; the dispatcher
  reattaches the original extension verbatim, preserving case and multi-part forms (`.tar.gz`).
- **Move and rename are one operation.** Doing them in two steps means a crash mid-run leaves
  a file misfiled under a name no rule matches.
- **Sanitize then fall back, don't fail.** Path separators, control chars, leading dots, and
  >200-byte names get the rename discarded — but the *move still happens*. A rejected rename
  is logged, never silent.
- **Omitting the rename is a valid agent answer.** No date in the document → keep the original
  name. Keeping a filename is recoverable; a confidently wrong date is not.
- **§5 keeps both names.** `File` holds the original, `Destination` shows the new one. Renaming
  is the one action a user can't audit by browsing the destination folder afterward.

## Downloads config: Mulcare billing rule

`~/Downloads/.claude/sort.md` rule 3 — **replaced**, not appended.

The old rule was `(?i)superbill` → `route_sensitive: Medical`, with body prose stating that
plain invoices from the same provider stay in `AI Library/Invoices/`. The new policy puts
superbills, invoices *and* receipts together in `Sensitive/Mulcare Billing/`.

Two things forced the replace-in-place:

1. **Appending would have been shadowed.** First match wins, so a new rule after the superbill
   rule never sees a superbill. Same for anything in `~/.claude/sort.local.md` — that's
   priority 3, below `~/Downloads/.claude/sort.md` at priority 2. Only
   `~/Downloads/.claude/sort.local.md` would have outranked it.
2. **The body prose contradicted the new rule** and is surfaced to classification agents as
   context, so leaving it would have actively fought the rule. Rewritten as "Loretta Mulcare
   billing".

The rationale that got recorded in the prose: the invoices and receipts carry less than the
superbills on their own, but they name the same clinician on the same dates, so filing them
under a general `Invoices/` folder leaks the treatment relationship anyway.

**Regex widened after testing.** The first draft used whole words
(`superbill|invoice|receipt|statement|bill`) and missed `stmt_88213.pdf` — the exact portal-export
shape this was built for. Now also matches `stmt`, `rcpt`, `super_bill`, and `inv[-_]?[0-9]`.
Verified with `match-rules.rb`: all four abbreviations fire, `vacation.pdf` still falls through.

The regex is only a cheap pre-filter to avoid an agent call per PDF — provider identity is
decided by reading the file, and the agent falls through if it's someone else's paperwork.
A Mulcare document whose filename matches none of those words is missed; widen the regex if
that shows up.

**Extended to images.** The rule originally matched `.pdf` only, which missed
`2023-12-01 Mulcare Receipt - $3025.png` — a screenshot of a Zelle confirmation. Now matches
`.pdf .png .jpg .jpeg .heic .webp`, and the regex gained `screen[ _-]?shot|cleanshot`.
Only ~11 screenshots exist in the tree, so the extra agent calls are negligible; the prompt
tells the agent that `fallthrough` is the expected answer for ordinary screenshots.

## Retroactive migration of already-sorted files

The rule only fires on future `/sort` runs, so previously-sorted Mulcare paperwork was
migrated by hand. **26 files** consolidated into `AI Library/Sensitive/Mulcare Billing/`
from `Sensitive/Medical/` (15), `Invoices/` (12) and `Receipts/` (1). Dry run first, then
applied; 0 collisions. `Sensitive/Medical/` is now empty but retained — default document
classification still routes there.

Non-Mulcare files in those folders correctly fell through: DHL `MyBill_*.pdf`, `AWB-*`,
`Laptop Stand order invoice.pdf`, `Order #99N43302`, `vietnamese lunch.pdf`,
`Receipt-2126-7202-7656.pdf`, `Felix and Rory Atlas - SHHK RECEIPT 2.pdf`.

### The date bug this caught — read this before touching the rename spec

The first `rename:` spec said "the document's own service/statement date". That is
**ambiguous and was wrong**, and reading the actual documents proved it. This provider's
dates diverge systematically:

| Document | Filename claims | `Issued:` | Sessions actually in |
|---|---|---|---|
| `Superbill20250801` | 2025-08 | 08/01/2025 | **July 2025** |
| `Invoice20250801` | 2025-08 | 07/31/2025 | **July 2025** |
| `Superbill20251031` | 2025-10 | 11/01/2025 | **October 2025** |
| `Invoice20251101` | 2025-11 | 10/31/2025 | **October 2025** |

- Superbills are issued the **1st of the month after** their sessions.
- Invoices are issued the **last day of the month** they cover.
- So an invoice and superbill covering the *same sessions* have issued dates one day apart
  **across a month boundary** — naming by issued date splits every matched pair into two
  different months, which defeats the entire point of the folder.
- Filename dates are unreliable in a third way: sometimes the issued date
  (`Superbill20250501` → issued 05/01), sometimes the service-period end
  (`Superbill20251031` → issued 11/01). Never trust them.

Tal's call: **name by the month the billed sessions took place.** The spec was rewritten to
say so explicitly and to enumerate every date it must *not* use.

The Zelle receipt is the clearest case. Filename says `2023-12-01`; the payment was sent
**Jan 6 2024**; the memo reads "Invoice 778 superbill 0602"; Invoice 778 covers **November
2023** sessions. Three dates, none agreeing. It filed as `mulcare 2023-11 receipt.png`,
directly beside the `mulcare 2023-11 invoice.pdf` it pays. The rename spec now has an
explicit clause for payment receipts: use the month covered by the invoice the payment
settles, found via the payment memo — not the send date.

### Second pass: ~/Desktop screenshots

Tal pointed at `~/Desktop`, which held 6 screenshots. Five were Zelle payment
confirmations to Jean Loretta Mulcare; the sixth (`Simulator Screenshot - iPhone 17 …`,
a `CurlTest2` chat app) was correctly not billing and was left in place.

| Was | Payments | Memo | Filed as |
|---|---|---|---|
| `CleanShot 2026-05-28…` | $5,000 Apr 19 + $800 May 28 | "March Sessions 1of2" / "march 2 of 2" | `mulcare 2026-03 receipt.png` |
| `CleanShot 2026-05-29…` | $5,000 May 29 | "April Sessions" | `mulcare 2026-04 receipt.png` |
| `CleanShot 2026-06-15…` | $5,000 Jun 9 + $350 Jun 15 | "May sessions 1of2" / "2 of 2" | `mulcare 2026-05 receipt.png` |
| `CleanShot 2026-08-12 …09.13.13` | $5,000 Aug 8 + $800 Aug 9 | "June 1 of 2" / "june 2 of 2" | `mulcare 2026-06 receipt.png` |
| `CleanShot 2026-08-12 …09.12.55` | $4,100 Aug 9 | "july" | `mulcare 2026-07 receipt.png` |

**Every payment memo names the session month explicitly, and every payment lands 1–3
months after it.** Independent confirmation that the session-month convention is right —
naming these by send date would have scattered five receipts across months with no
matching invoice or superbill.

Two of the screenshots capture *two* Zelle payments in one image (the provider splits
larger months into "1 of 2" / "2 of 2"). They stay as one file per session month, since
both payments settle the same month's sessions.

**Scope decision:** the rule lives in `~/Downloads/.claude/sort.md`, so it only fires when
sorting `~/Downloads`. Tal chose to leave scope alone rather than add `~/Desktop` to
`sources:` — adding it would make `/sort` reorganize the entire Desktop, a far bigger
behavior change than catching the occasional receipt. Desktop receipts get pointed at
manually.

### Coverage gap worth chasing

31 files now. `2026-05` has a **receipt but no superbill and no invoice** — $5,350 paid for
May 2026 sessions with no superbill on file to submit for reimbursement. Also missing
entirely: 2025-05, 2025-08, 2025-09. Superbill-without-invoice: 2025-04, 2025-12, 2026-02.
Invoice-without-superbill: 2024-05.

### Duplicates found

Two byte-identical pairs (md5-verified), deleted rather than moved:

- `Invoice20260401-36-xlinsa.pdf` existed in **both** `Sensitive/Medical/` and `Invoices/`
  — a straddle left by the old split superbill/invoice policy.
- `Invoice20250801-267825-4ubb1o.pdf` + its `-1` download-collision twin.

Both would otherwise have collided into `…invoice-2.pdf` with identical content.
