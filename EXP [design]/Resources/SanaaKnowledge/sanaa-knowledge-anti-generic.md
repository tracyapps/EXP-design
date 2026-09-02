---
name: anti-generic
version: 1.0.0
updated: 2026-08-29
---

## TL;DR
How to avoid the generic AI look: the documented model-default clusters, the steering rules, and the self-revision check.
Load when: drawing anything new — variations, completions, directions, or a full board from scratch.

## The slop-tells (blocklist)
Check every proposal against these documented model defaults before showing it:
- Purple/blue gradient heroes; gradient text as identity.
- Centered hero + three equal cards ("the triple").
- Default font stack as the entire identity (system-ui everywhere, no deliberate choice anywhere).
- The model-default clusters named in Anthropic's public frontend-design skill: cream + serif + terracotta; near-black + acid green; broadsheet hairlines everywhere.
- Decorative blobs / mesh gradients with no relation to the subject.
- Icon row + stat row + testimonial row assembled with no real content behind them.
Provenance: Anthropic's public frontend-design skill names these clusters; community catalogs agree. Practice-compiled beyond that.

## Steering rules
- Plan before pixels: pick a token skeleton first (surface / text / accent / status roles, one type pairing, one spacing scale) and state it in one line so the designer can veto it early.
- One signature element: each direction gets exactly one memorable, subject-grounded element (a distinctive table treatment, an unusual header, a custom chart frame) — boldness in one place, restraint everywhere else.
- Subject grounding: reference the actual content — real headings, real labels, real numbers from the document. Lorem and "Your heading here" only when the board is literally empty (and say so).
- Structure is information: layout expresses the content's hierarchy as the file shows it — the thing the designer's own artboard treats as primary gets the most weight. Not a template.
- Translate mood words into tokens: "warm", "technical", "calm" become concrete choices (type category, lightness structure, corner-radius range, gap scale) — read them back before drawing.
- Negative constraints ("no Inter", "no purple gradients") apply when the designer says so or the document implies it; otherwise steer by construction.

## Self-revision (the check)
Before proposing, ask: "would this be the default for ANY brief?" If yes, revise — move one named axis (layout strategy, density, color strategy, or type mood) until at least one deliberate, explainable departure exists. Keep the departure cheap to undo (its own artboard or batch).

## Quality floor (non-negotiable even in experiments)
- Real states: hover/focus/disabled/error get drawn or explicitly named as missing.
- Visible focus: the focus treatment exists in the design itself; "the browser draws it" is implementation-stage — say so.
- Copy as design: real microcopy wherever the subject provides it.

## When conventional IS the answer
If the designer asks for the conventional version (a baseline, a safe corporate pass), deliver it plainly and label it: "the conventional take — included as the baseline." Convention on request is a decision, not a failure.
