---
name: design-principles
version: 1.0.0
updated: 2026-08-29
---

## TL;DR
Core design principles as canvas-checkable observations: hierarchy, visual contrast, alignment, proximity, whitespace, Gestalt grouping.
Load when: critiquing, completing, or composing any artboard.
Rules are observations with tradeoffs — numeric contrast ratios always come from get_design_facts, never from eyeballing.

## Hierarchy
- IF a board's text runs cluster within ±1pt of one size across two roles (heading vs body) THEN hierarchy is unreadable at arm's length — propose separating roles by a full step (e.g. 17/13 rather than 15/14); tradeoff: fewer same-size elements means less even rhythm.
- IF the primary action is the same fill and size as secondary actions THEN the eye lands nowhere first — propose one emphasis lever (weight, fill, or size), not all three; tradeoff: single-lever emphasis is quieter.
- IF every element is bold/large THEN nothing is primary — propose demoting all but one element; tradeoff: the demoted elements read as secondary even where they matter.

## Visual contrast (weight, not WCAG numbers)
- IF two adjacent text blocks differ only by 5–10% opacity THEN the difference reads as unintentional — propose a deliberate step (≥20%) or none; tradeoff: bigger steps are louder.
- IF thin-weight text sits on a mid-tone surface THEN it may visually wash out even when the measured ratio passes — flag as a reading-comfort observation (the measured ratio is still the facts tool's job); tradeoff: heavier weights change the type's character.

## Alignment
- IF sibling elements' left edges differ by <4pt with no intentional offset THEN it reads as drift — propose snapping to the dominant edge; tradeoff: snapping can flatten deliberate rhythm.
- IF mixed alignment appears inside one list/group (some left, some centered) THEN pick one per group; tradeoff: centered text in narrow rows is harder to scan.
- IF optical elements (icons, badges) misalign with text baselines by more than ~2pt THEN propose optical alignment over geometric; tradeoff: optical values look "wrong" in the inspector but right on canvas.

## Proximity & grouping
- IF the gap between items inside a group is larger than the gap between groups THEN grouping inverts — propose gap-inside < gap-between (a 1.5–2× difference reads clearly); tradeoff: tighter groups need more total space.
- IF a heading sits equidistant between two sections THEN ownership is ambiguous — propose pulling it toward the content it names; tradeoff: less symmetric whitespace.

## Whitespace
- IF text blocks run edge-to-edge against fills (<8pt inner padding at body sizes) THEN they feel pinned — propose per-side padding that matches the type scale; tradeoff: padding costs density.
- IF two densities coexist (one section airy, one cramped) without intent THEN propose one density per board or a deliberate transition; tradeoff: uniform density can waste space in data-heavy areas.

## Gestalt (precondition → observed-deviation check)
- Similarity: IF items meant to be equal differ in fill/radius/size THEN they read as different classes — normalize or differentiate on purpose.
- Proximity: IF related label+value pairs are split across a gap larger than unrelated neighbors THEN regroup; tradeoff: may conflict with grid columns.
- Closure/common region: IF a shared background would group items that spacing alone cannot THEN propose a surface or divider; tradeoff: extra fills add visual noise.
- Continuity: IF a row of items breaks a shared edge mid-flow THEN align the flow line or break it clearly.
- Figure/ground: IF a modal/overlay's backing differs from the canvas by <10% lightness THEN layers read as one surface — propose a clearer step; tradeoff: heavier overlays dominate the board.

## Working with the file
- Read get_artboard/get_selection before claiming ANY of these — the check runs on real ids, real frames, real text runs, never on memory of the board.
- Observations reference node ids so the panel's tap-to-select lands; directions name the tradeoff in the same breath.
