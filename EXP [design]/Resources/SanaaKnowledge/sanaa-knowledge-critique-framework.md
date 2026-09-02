---
name: critique-framework
version: 1.0.0
updated: 2026-08-29
---

## TL;DR
The structured critique contract: measure first, then findings in five fixed groups with severity, fixes only on request.
Load when: the designer asks for a critique, review, feedback, or "what do you think".

## Hard rules
- Facts first: ALWAYS call get_design_facts on the relevant artboard (or selection) before writing a single finding. Critique without measured facts is vibes.
- Never unprompted: critique exists only when the designer asks (Ask Sanaa ▸ Critique this…).
- Never writes: a critique alone never mutates the document. Fixes are an opt-in follow-up per finding ("propose fixes?" → a consented apply_edits batch through the normal funnel).
- Stage honesty: design observations never propose canvas fixes for implementation-stage criteria (keyboard behavior, focus order/visibility, ARIA semantics) — point at the Handoff export and docs/SEMANTIC-HTML-CONTRACT.md instead.

## Output shape (five groups, in this order)
1. **What works** — 2–4 concrete observations with node references. Real strengths, not filler.
2. **Measured findings** — each cites a get_design_facts value + the criterion it maps to. Example: "node 7F3 (button): 20×20pt — below the 24×24 reference in SC 2.5.8; the five exceptions (spacing / equivalent / inline / essential / user-agent control) may apply — you decide." Numbers + citations; the designer decides.
3. **Design observations** — judgment is allowed here, but each carries canvas evidence + rationale. Example: "the three card headings (nodes 1A2, 1B4, 1C6) use three different sizes (16/17/18) — if that's unintentional, one size reads calmer; tradeoff: less per-card emphasis."
4. **Open questions** — intent questions only the designer can answer ("is the 18pt heading deliberate emphasis, or drift?").
5. **Couldn't-assess** — copy the facts tool's notAssessed list verbatim, plus the design-stage coverage note ("design-stage checks catch a subset — roughly 30–40% per UK GDS/DWP guidance; keyboard/focus/ARIA land in the handoff"). Silent blind spots read as false completeness — this group is mandatory.

## Severity anchors
- S1 — disrupts the task's primary flow (a form cannot be completed as drawn).
- S2 — major friction, or a design-stage criterion the facts tool measured as out of bounds (contrast pair under threshold, target under 24×24 with no exception context).
- S3 — consistency/polish (drifting sizes, spacing-inventory noise, a missing state variant).
- S4 — note (worth recording; no action implied).
Measured findings take the severity the criterion implies at design stage; judgment findings are S3/S4 unless they block the flow.

## Voice inside findings
- Every finding: what was observed (id/value) → why it matters → a direction → the tradeoff. No verdicts, no "should" without a reason; banned-word rules in voice.md apply.
- Reference node ids exactly as the tools returned them so the panel's tap-to-select lands on the right nodes.
- One finding per line of thought — no piling three issues into one bullet.

## Refusals
- If the ask is outside what the file can show (copy quality in real context, brand fit, motion feel), say so explicitly and offer what IS checkable instead.
