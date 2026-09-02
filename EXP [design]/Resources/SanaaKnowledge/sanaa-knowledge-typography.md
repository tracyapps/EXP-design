---
name: typography
version: 1.0.0
updated: 2026-08-29
---

## TL;DR
Type decisions grounded in the document's text runs: scales, measure, leading, tracking, and hierarchy through roles.
Load when: choosing, changing, or critiquing type. The canvas encodes fontName, fontSize, lineHeight (+unit), tracking, align, textCase per run.

## Type scales
- IF body text is N pt THEN a modular scale keeps relationships deliberate (common steps ×1.25 or ×1.333): body → caption below, title above. IF sizes drift off-scale (15.5, 16.2, 17) THEN propose snapping to the document's own dominant steps; tradeoff: snapping loses fine-grained emphasis.
- IF more than ~5 distinct font sizes coexist on one board THEN the scale is dissolving — propose collapsing near-duplicates; tradeoff: fewer sizes, flatter hierarchy (pair with weight/size steps to compensate).

## Measure (line length)
- IF a body text box measures wider than ~75 characters per line at its font size THEN reading comfort drops — propose a narrower box or a multi-column split; tradeoff: narrower measures need vertical space.
- IF body lines run under ~45 characters with ragged edges THEN the rag dominates — propose widening or rebalancing; tradeoff: wider measures trade intimacy for flow.
- Rough points-to-characters: at 16pt, a comfortable measure is ~35em wide; use the box width + fontSize to estimate rather than counting glyphs.

## Leading (line height)
- IF body runs set lineHeight below ~1.4× THEN lines crowd — propose 1.5–1.6× for paragraphs; tradeoff: taller lines lengthen the board.
- Inverse size/leading: IF display sizes keep body-scale leading THEN headlines collide — propose tighter leading as size grows (display ~1.0–1.2×); tradeoff: tight display leading clips ascenders/descenders in some faces — check glyph extremes.
- IF lineHeight unit is px on one run and % on a sibling run THEN scaling behaves differently across the pair — propose one unit convention per role; tradeoff: none worth having.

## Hierarchy through roles
- Assign roles (display / title / body / caption / label) and keep each role consistent in size + weight + case across the board; IF one role appears with two treatments THEN either name it two roles or unify; tradeoff: more roles = more vocabulary to maintain.
- Case is a lever: IF labels and titles share size and weight THEN textCase can separate them without new sizes; tradeoff: all-caps runs need tracking (+2–6%) to breathe.
- Weight carries hierarchy only if the face has real weights — fontName tells you what's installed; IF only regular/bold exist THEN hierarchy must come from size/space/case.

## Grounded in the runs
- TextRun has NO bold flag — large-text judgment (≥14pt bold) comes from fontName heuristics and is labeled heuristic by get_design_facts; don't assert weight from size alone.
- Pair contrast, target size, and spacing questions defer to their modules (a11y-foundations, spacing-layout) — this module judges type-as-type.
