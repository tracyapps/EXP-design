---
name: color
version: 1.0.0
updated: 2026-08-29
---

## TL;DR
Palette work on the document's own tokens: semantic roles, harmony starting points, and dark-mode adaptation.
Load when: choosing, changing, or critiquing colors — with a11y-foundations for anything contrast-related.
Numeric contrast is get_design_facts' job; this module never estimates a ratio in prose.

## Start from the document
- IF the document has Design Language color tokens THEN new colors derive from them first (tint/shade/de-saturate a token) before inventing new values — read get_tokens; tradeoff: derivation keeps cohesion but caps range.
- IF a proposed color duplicates an existing token within a hair (near-identical hex) THEN reuse the token instead of adding a near-duplicate; tradeoff: fewer, stronger tokens.
- No fill↔token links exist in the file — matching is by value; say so when proposing "apply the token" so the designer knows it's a value copy, not a live binding.

## Semantic roles
- Every board needs the roles covered: surface/backing, primary text, secondary text, accent/action, status (positive/negative/warning). IF a role is missing or doubled THEN propose mapping it to one token; tradeoff: more roles = more flexibility, less cohesion.
- IF one accent appears in 5+ unrelated roles (links, badges, fills, strokes) THEN it stops signalling "action" — propose reserving it or adding a supporting hue; tradeoff: a second accent splits attention.
- IF status colors rely on hue alone (red vs green at the same lightness) THEN pair hue with an icon/text difference; tradeoff: slightly busier states.

## Harmony starting points (starting points, not laws)
- Analogous (neighbors on the wheel) for calm surfaces; complementary for one accent against a neutral field; split-complementary when one accent needs a support act.
- IF a harmony rule fights the document's existing palette THEN the palette usually wins — harmonies are recipes for new sets, not corrections to a working set.
- Prefer lightness-first composition: settle the lightness structure (background → surface → text steps) before choosing hues; hue drifts are easier to fix than lightness chaos.

## Dark-mode adaptation
- IF the designer asks for a dark variant THEN re-map semantics rather than inverting: surfaces go dark (highest elevation lightest), text goes near-white (not pure), accents usually lighten/desaturate to hold contrast on dark.
- IF a brand accent is dark-tuned THEN brighten it a step for dark surfaces and let get_design_facts re-measure the pair; tradeoff: the accent reads slightly different across modes — that's normal.
- IF elevation matters THEN encode it in lightness steps (dark surfaces rise toward lighter grays), not in shadows alone.
- Re-check every text/surface pair after remapping — dark-mode pairs are new pairs, not the old ones.

## Working with measured facts
- Contrast questions belong to get_design_facts (pairs come back with WCAG citations and a notAssessed list). IF the pair involves a gradient, alpha, or image fill THEN the result is an estimate or unassessable — say that, don't eyeball.
- Propose direction, not verdicts: "this pair measures 3.9:1 against the 4.5:1 reference in SC 1.4.3 for 16px text — want a darker ink from the same hue, or a lighter surface?" Both options, one tradeoff line.
