# Recipe tag convention

Applies when a sorted note is a **recipe** — a note with ingredient + instruction content (the same notes that get meal-type tags like `dinner`/`snack`/`dessert` and the optional Paprika sidecar). For non-recipe notes, ignore this file and use the generic `tags` guidance.

Recipe `tags` are **layered**: three kinds of tag coexist in the one inline `tags: [...]` array. The generic "3–7 tags" count does **not** apply to recipe notes — a recipe carries as many tags as the layers below require (typically 6–12).

## 1. Category / descriptor tags (bare, no prefix)

The generic tags you'd pick anyway — meal type, diet, method, cuisine, dish type: `dinner`, `snack`, `dessert`, `high-protein`, `vegan`, `gluten-free`, `air-fryer`, `no-bake`, `one-pan`, `thai`, `korean`, `salad`, `cookies`, `curry`. Lowercase, kebab-case, no prefix.

## 2. `ingredient:` hero tags

Prefix the **hero ingredients** — the 2–5 defining/headline ingredients — with `ingredient:`.

- **Hero, not every ingredient.** Include only what the dish is named for or known for: title ingredients, the signature protein, the signature sauce/flavor base. Exclude garnishes, one-of-several salad/bowl vegetables, and toppings.
- **Skip pantry staples** (salt, pepper, oil, water, sugar, butter, plain flour, onion) **unless the staple is the point of the dish** — e.g. `ingredient:semolina`, `ingredient:cornmeal`, or `ingredient:garlic` for a garlic-forward dish.
- **Per-dish, not global.** The same ingredient can be hero in one dish and a garnish in another — judge from this recipe's body (broccoli is hero in a broccoli salad, a topping in a rice bowl).
- **Keep ingredients distinct.** `ingredient:white-chocolate` ≠ `ingredient:chocolate`; `ingredient:chocolate-chips` is its own thing. Don't collapse them.
- **Kebab-case multi-word ingredients:** `ingredient:peanut-butter`, `ingredient:coconut-milk`, `ingredient:sun-dried-tomatoes`, `ingredient:cream-cheese`.
- **Dish-name / prep compounds stay bare** (they aren't shoppable): `chicken-parm`, `honey-chipotle`, `roasted-broccoli`. But *also* add the clean hero separately (`ingredient:chicken`, `ingredient:broccoli`) so the dish is findable by ingredient.

## 3. `texture:` tags (closed vocabulary)

Prefix **1–3 defining mouthfeel** tags with `texture:`, drawn **ONLY** from this closed, collectively-exhaustive set of 7 — never invent others:

| `texture:` | catches | folds in |
|---|---|---|
| `crispy` | fried/roasted/baked shatter, panko crust, air-fried, crispy rice | *flaky, crackly* |
| `crunchy` | raw veg, nuts, seeds, granola, cornflakes, toasted toppings | — |
| `creamy` | dressings, dips, smooth coating sauces, cheesecake, cottage-cheese blends, ganache, nut-butter fillings | *gooey, melty, luscious* |
| `chewy` | cookies, brownies, bars, dense breads, bagels, protein balls | *fudgy* |
| `fluffy` | pancakes, crepes, cakes, muffins, cinnamon/sweet rolls, focaccia, whipped | *soft, pillowy* |
| `saucy` | curries, gochujang/honey glazes, saucy noodles, marinara-heavy bakes | — |
| `juicy` | tender/succulent protein as a headline trait | — |

- **1–3 per dish** — only the mouthfeel a person would actually notice and crave. Most dishes get 1–2.
- **Every recipe gets at least 1** — the vocab is collectively exhaustive, so something always fits.
- **Minor textures fold** into the nearest bucket (see table) rather than getting their own tag.
- **`juicy` is rare** — reserve it for dishes where tender protein is genuinely the headline, not every chicken dish.

## YAML format (critical)

Write namespaced tags with **NO space after the colon** — `ingredient:chicken`, `texture:crispy`. A space (`ingredient: chicken`) makes flow-YAML parse the entry as a `{key: value}` map and breaks the whole `tags` array. Every tag — bare, `ingredient:`, and `texture:` — lives in the single inline `tags: [...]` array; these are namespaced tag *values*, not new frontmatter keys.

## Worked example

A cornflake-crusted air-fried chicken sandwich tossed in a spicy peanut sauce:

```yaml
tags: [dinner, sandwich, thai, high-protein, ingredient:chicken, ingredient:peanut, texture:crispy, texture:creamy]
```

## Precedence

This is the plugin default for recipe notes. A user tagging convention surfaced from `sort.md` / `sort.local.md` (see the `0.5` load-user-rules step) still takes precedence over this file — if the user documents their own recipe vocabulary or tag count, that wins.
