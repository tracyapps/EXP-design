---
name: spacing-layout
version: 1.0.0
updated: 2026-08-29
---

## TL;DR
Spacing and layout rhythm as DESCRIPTIVE observation: 4/8pt systems, grid discipline, density consistency.
Load when: layout questions, spacing normalization, alignment rhythm.
STRICTLY DESCRIPTIVE: the document has no spacing tokens and no tool judges spacing — this module observes inventories and suggests directions; it never implies a rule-check or a pass/fail.

## Spacing systems (4/8pt)
- IF gaps and paddings across a board land on an informal scale (multiples of 4 or 8: 4/8/12/16/24/32/40) THEN the rhythm reads deliberate; IF they scatter (9, 13, 17, 22) THEN propose snapping the outliers to the board's own dominant steps; tradeoff: snapping shifts surrounding elements.
- Read the inventory from the file: autoLayout gap, per-side padding, sibling frame deltas. Present it as a measured list ("gaps in use: 8, 12, 14, 16, 24 — 14 appears twice"), never as an error count.
- IF two spacing scales coexist (a tight card scale and an airy section scale) THEN that's a system, not a mess — as long as each is internally consistent.

## Grids & alignment
- IF the artboard defines layout grids THEN content snapping to them is the norm; IF content ignores its own grid THEN propose either honoring it or removing it; tradeoff: free-form layouts lose the grid's shared rhythm.
- IF sibling elements share a column edge except a few THEN the exceptions read as drift — align or offset deliberately (≥ half a column); tradeoff: deliberate offsets need a reason the designer can state.
- IF consistent gutters exist between columns THEN keep them constant per region; mixed gutters inside one region reads as unfinished.

## Density
- Density = content-to-space ratio; IF one section is airy and an equivalent section is cramped THEN propose one density intent per content class (forms tighter, marketing looser); tradeoff: uniform density wastes room where data is dense.
- IF touch/pointer targets shrink to win density THEN target-size questions belong to a11y-foundations/SC 2.5.8 (measured by get_design_facts) — density never justifies shrinking below measured references without the designer's explicit call.

## Vertical rhythm
- IF section spacing follows a pattern (e.g. 40 between sections, 16 inside) THEN keep it; IF section spacing varies more than the content requires THEN propose the dominant pattern; tradeoff: rhythm can flatten intentional emphasis.
- IF whitespace sits only at the bottom of a board (or only at the top) THEN the composition leans — propose balancing or declaring intent.

## Honesty rules
- This module proposes DIRECTIONS with tradeoffs; the designer decides. No spacing rule is a law; conventions (4/8pt) are starting points, not validators.
- When get_design_facts ships, its spacingInventory feeds these observations with real numbers — same descriptive framing, better data.
