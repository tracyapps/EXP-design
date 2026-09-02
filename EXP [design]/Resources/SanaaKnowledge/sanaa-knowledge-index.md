---
name: index
version: 2.0.0
updated: 2026-08-31
---

## TL;DR
Map of EXP's bundled design knowledge pack (v2.0.0). Read this first; load other modules only when a task needs them.
Read a module with resources/read: `exp://sanaa/knowledge/<module>` — styles live at `exp://sanaa/knowledge/styles/<name>`.

## When to load what
| Task | Load |
|---|---|
| Critique / review / feedback | critique-framework → a11y-foundations → design-principles |
| Accessibility, compliance, 508/ADA/WCAG | a11y-foundations (always first) |
| Color, palettes, dark mode | color (with a11y-foundations) |
| Type, scales, hierarchy | typography |
| Spacing, grids, layout rhythm | spacing-layout |
| Forms, interactive components, missing states | components-states |
| Interface copy | copy-microcopy |
| Variations, options, directions, "stuck" | directions → anti-generic → style-profile (for document-grounded style) → styles/<name> (if a style was named) |
| Drawing anything new | anti-generic (before composing) |
| Build repeated structures: tables, row sets, card lists, form groups, chips, placeholder data | procedural-tasks → anti-generic |
| Bulk changes: compact/spacious variants, batch spacing or sizing across nodes | bulk-adjustments (with spacing-layout) |
| Fix accessibility in the canvas: contrast, target size, focus treatment | a11y-foundations → a11y-applied |
| Match the document's own look, or answer style-memory / "remember this" questions honestly | style-profile → styles/<name> (if the designer names a style) |
| Anything you write | voice (standing rules) |

## Modules
- **design-principles** — hierarchy, contrast, alignment, proximity, whitespace, Gestalt as canvas checks
- **color** — palette work on the document's own tokens: semantic roles, harmony starting points, dark-mode adaptation
- **typography** — scales, measure, leading, hierarchy through type roles
- **spacing-layout** — 4/8pt systems, grids, density (descriptive only — the document has no spacing tokens)
- **components-states** — state completeness and form patterns
- **copy-microcopy** — copy as design material
- **anti-generic** — model-default blocklist + steering rules
- **critique-framework** — the critique contract
- **directions (v2.0.0)** — genuinely distinct directions using nine genome axes, explicit from→to diffs, and a sibling-divergence check
- **procedural-tasks** — deterministic builds: measure→derive→replicate, repeated structures, placeholder data
- **bulk-adjustments** — density variants and batch edits that preserve structural invariants
- **a11y-applied** — applied remediation: contrast, target size, role, and focus workflows (companion to a11y-foundations)
- **style-profile** — honest no-memory boundaries and document/session style grounding; includes a clearly labeled future profile contract
- **voice** — Sanaa's language rules (standing)
- **a11y-foundations** — standards map + claim rules (facts verified 2026-08-29)
- **styles/** — swiss-international, minimal, editorial, neo-brutalist, glassmorphic, claymorphic, corporate-safe, playful

## Notes
- get_design_facts (measured contrast pairs, text/target sizes, spacing inventory) arrives with FEAT-055 in this release. Until it ships, ground measured statements in explicit document reads (get_artboard / get_node) — never estimates.
- Every rule in this pack is an observation with a tradeoff — the designer decides. Nothing here creates a write path: canvas changes only ever happen through apply_edits with the designer's consent (SANAA-PLAN §4/§6).
- Pack maintenance: version and per-module `updated` dates live in each file's frontmatter; the pack changelog ships alongside the modules.
