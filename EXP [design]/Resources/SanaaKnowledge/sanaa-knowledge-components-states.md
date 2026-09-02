---
name: components-states
version: 1.0.0
updated: 2026-08-29
---

## TL;DR
State completeness and form patterns — the highest-value observation a design-stage assistant can make.
Load when: the board contains interactive components, forms, flows, or the designer asks "is this ready".

## State completeness (the core check)
Interactive components imply a state family: default, hover, focus, active/pressed, disabled, error (for inputs), plus flow states: empty, loading, success.
- IF component X appears on N artboards but no focus or disabled variant of it exists anywhere in the document THEN say so as coverage, not accusation: "X appears 6 times across these boards; I don't see a focus or disabled variant anywhere in the file — want me to sketch them on a scratch artboard?" Tradeoff: states add boards to maintain.
- IF a variant exists in one component family but not a parallel family THEN ask whether that's intent ("buttons have a disabled state; menu items don't — intentional?").
- IF focus state is missing entirely THEN flag it as the one states-gap that also affects handoff (focus visibility maps to SC 2.4.13/2.4.11 in the export — see a11y-foundations for the stage split).
- Component instances matter: read instances via get_node (scope componentSource) — IF variants exist in the source but an instance overrides its way out of the system THEN note the override; tradeoff: overrides are sometimes the point.

## Interactive classification (honesty)
- The file has no stored "isControl" flag — interactivity is inferred from semantics (ARIA roles), naming, and component family. Label heuristic classifications as heuristics in findings.

## Form patterns
- IF an input lacks a visible label (placeholder-only) THEN propose a persistent label; tradeoff: labels cost vertical space, placeholders cost recall.
- IF error states exist THEN the error copy pattern matters (see copy-microcopy): what happened + what to do next; IF error styling relies on color alone THEN add an icon/text difference.
- IF required fields are marked only by absence of "optional" THEN flip the convention ("Optional" tags read calmer); tradeoff: designer's convention may be set by their design system.
- IF a multi-step flow appears THEN check each step for the family: same input widths, same button placement, same back/forward affordance; IF step N diverges THEN ask if it's intentional emphasis.

## Flow states
- IF a data-driven board has a populated state only THEN propose sketching empty + loading on a scratch page: empty (what the user sees first) and loading (what they see while it fills); tradeoff: two more boards, dramatically fewer surprises in build.
- IF destructive actions have no confirm/undo affordance drawn THEN note it — the undo story is a design decision, not an implementation detail.

## Working the file
- Run the check per component family across the document (list_artboards → targeted get_artboard), and report coverage as a map ("button: default ✓ hover ✓ focus ✗ disabled ✗") — the designer sees the gaps at a glance, and every ✗ is an offer, not a verdict.
