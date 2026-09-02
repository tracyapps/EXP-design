---
name: bulk-adjustments
version: 1.0.0
updated: 2026-08-31
---

## TL;DR
Compact / spacious variants of existing screens: measured deltas on the document's own spacing rhythm, applied to a duplicate — never the original — with proximity invariants and content floors held.
Load when: "compact version", "a version with more space", "make these tighter/airier", any density-variant ask across one or more artboards.

## Variants never mutate the original
- IF a compact or spacious variant is asked for THEN duplicate each artboard (`duplicateArtboard`, `besideOriginal`) and adjust only the copy; the original stays as-is and the designer keeps both. Tradeoff: two boards to keep in sync — later edits to the original do not flow into the variant.
- IF the designer says "these screens" THEN enumerate the exact artboards by name/id and confirm the list before editing. Tradeoff: one extra round vs. adjusting a screen that was never meant.
- Consent for any write is the host app's own flow; this module proposes, it never authorizes a write.

## Density = measured deltas, not ad-hoc squeezing
- There are no spacing tokens — derive steps from measured values only. IF get_design_facts is live THEN read `spacingInventory` (autoLayout gaps, per-side paddings, sibling deltas); ELSE read the same values from `get_artboard`/`get_node`.
- Derive a dominant step per relationship class and SHOW the arithmetic: "within-row gaps cluster at 16 → 12", "between-section gaps cluster at 40 → 24".
- IF compact THEN move each relationship class down roughly one dominant step: within-group 16→12, between-section 40→24, row heights −4 only where content allows. IF spacious THEN up one step (16→24, 40→48). Tradeoff: uniform stepping can flatten intentional emphasis — offer to hold any gap the designer names as deliberate.
- Keep every delta on the document's own 4/8pt logic — snap to its dominant steps, never a foreign scale. Tradeoff: an off-rhythm original passes its oddness through; flag outliers (9, 14, 22) instead of silently normalizing.
- IF the ask names the variant's vertical extent ("compact height", "fits in X") THEN set the duplicate's frame height to the target — or let it hug content — and verify nothing clips; name any region whose floors block the target rather than cropping it. Tradeoff: a fixed target can end the pass early; say so rather than shaving floors.

## Proximity invariants (what "not broken" means)
- IF scaling down THEN take the bigger absolute cuts from between-group gaps — that is where the height savings live — while holding the grouping signal: after the pass every between-group gap stays ≥ ~2× the within-group gaps it separates. Tradeoff: compressing between-group down to within-group scale erases grouping; the ~2× floor is the guardrail.
- Container padding stays proportional to its content — cards shrink from the inside (padding first, then gaps), never by clipping children. Tradeoff: inside-out shrinking changes card heights; clipping hides content.
- Dividers and hairlines persist — they carry the grouping signal when gaps shrink. Tradeoff: at spacious settings they can read as noise; removing them is a separate ask, not part of this pass.
- Headers/footers keep their hierarchy ratio to body — compress their surrounding space by the same class logic, not harder than body. Tradeoff: compressing header margins more aggressively than body inverts emphasis.

## Content floors (numbers from a11y-foundations)
- Interactive targets never go below 24×24 CSS px per SC 2.5.8 (five exceptions apply, designer's call); 44×44 is the SC 2.5.5 AAA reference; platform conventions run 44–48pt (commonly cited; re-verify per platform). Measure before and after: "smallest button 32×32 → 32×32". Tradeoff: honoring floors can block the last compaction step in a control-dense region — say so rather than shaving.
- Multi-line body keeps line-height ≥~1.4 (pack floor; SC 1.4.12's 1.5× is the user-override stress value, not an authored minimum). Single-line labels can compress. Tradeoff: tighter leading risks overflow when copy wraps differently.
- Font sizes unchanged by default — density comes from space, not type shrinkage. IF the designer asks for smaller type THEN that is an explicit separate pass (typography module), floors re-checked after. Tradeoff: fixed type limits how compact rows get; silent type shrinkage trades legibility for density without a designer call.
- Images scale or crop proportionally, never squash; icons keep their size relationship to text. Tradeoff: proportional media sets the minimum row height in media rows.

## Non-breaking guarantees
- No horizontal grid or column-count changes; no content edits; reading order and hierarchy preserved. Tradeoff: some density could be won by reflowing columns — that is a redesign; decline it here and offer it as a separate direction.
- Contrast relationships unchanged. IF any color-adjacent change happens anyway THEN recommend re-reading get_design_facts `colorPairs` on the variant before it ships.
- Reply manifest-first: a grouped change list (what moved, by how much, per relationship class) before or alongside the edits — never a silent batch. End it with an opening: "swap any of these, or tell me which gap to hold."
- IF any "all clean" summary is given THEN carry voice.md's coverage caveat — design-stage checks catch a subset of issues.

## Scope discipline
- Touch only what the ask covers; list every changed node grouped by relationship class in the manifest.
- Anything that cannot adjust within the rules is NAMED with its reason ("row 9E3 cannot compress below its label wrap height") — never silently skipped. Tradeoff: a longer manifest vs. a receipt the designer can audit.

## Forward-compat
- When `normalizeSpacing` / `restyleNodes` ship (v2.5 candidates), each pass becomes one batch op with a dry-run receipt. The discipline does not change: deltas from measured steps, floors checked before apply, manifest-first reply. Tradeoff: one-batch convenience can tempt skipping the derivation — the derivation IS the recipe.

## Worked example — dashboard asked for "compact + spacious"
Measured: within-row gaps 16 (×9), between-section gaps 40 (×4), card padding 12/16, row height 56, buttons 32×32, body 14px/1.5 multi-line.
Step table:
- within-group gaps: 16 → 12 (compact) / 24 (spacious)
- between-section gaps: 40 → 24 / 48
- card padding: 12/16 → 8/12 / 16/24
- row height: 56 → 52 / 64 (allowed: label + value are single-line)
Floors check: buttons 32×32 unchanged (≥24×24 per SC 2.5.8, this set); line-height 1.5 unchanged (≥~1.4); type sizes unchanged; images keep aspect.
Manifest shape:
    Compact — duplicate of "Dashboard", beside original
    · within-group gaps 16→12 — 9 nodes (3A1, 3A2, 4B1 …)
    · between-section gaps 40→24 — 4 nodes (2C1, 5A1, 6D1, 7B1)
    · card padding 12/16→8/12 — 6 cards
    · row height 56→52 — 8 rows
    · unchanged: buttons, type, line-height, images, dividers
    · could not compress: chart legend 8F2 — labels wrap at 52
Spacious manifest mirrors it with upward deltas; designer picks, both stay.
