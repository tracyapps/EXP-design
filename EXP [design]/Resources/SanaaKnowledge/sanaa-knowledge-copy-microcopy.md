---
name: copy-microcopy
version: 1.0.0
updated: 2026-08-29
---

## TL;DR
Copy as design material: user-side vocabulary, active voice, error/empty-state patterns, verb consistency.
Load when: writing, editing, or critiquing text the interface shows.
The canvas encodes copy as text runs; this module judges copy-as-copy, in the designer's voice.

## User-side vocabulary
- IF interface copy names system concepts (records, sync, references, nodes) THEN translate to what the user is doing ("references" → "the parts this connects to") unless the designer's product vocabulary is deliberately technical; tradeoff: precision vs approachability.
- IF a term appears with two spellings/forms across the board ("sign in" / "sign-in", "e-mail" / "email") THEN propose one; tradeoff: none worth having.

## Voice
- Active voice, present tense as the default: "EXP exports the board" over "the board is exported by EXP".
- IF a sentence chains 3+ clauses THEN split it — interface copy breathes in short lines; tradeoff: more lines, fewer commas.
- Sentence case as the neutral default for labels/buttons; IF the document's own convention is Title Case THEN follow the document (conventions in the file outrank this module's defaults).

## Errors and empty states
- Error pattern: what happened → why → what to do next. IF an error text states only the failure ("Upload failed") THEN propose the next step ("Upload failed — the file is over 25 MB. Try a smaller export."); tradeoff: longer strings need layout room (pair with components-states).
- Empty-state pattern: name the space, invite the first action, keep it short. IF an empty state is blank THEN propose one line + one action; tradeoff: charm costs words.
- IF error copy blames the user ("You entered an invalid…") THEN re-point it at the condition ("That address doesn't look complete — check for a missing @"); tradeoff: slightly longer.

## Verbs and labels
- One action verb per concept across the flow: IF "Create" and "New" and "Add" all appear for the same action family THEN pick one and note the exceptions that are real distinctions; tradeoff: shared verbs across unrelated flows can confuse.
- Buttons start with verbs ("Export board", not "Board export").
- IF a destructive action's button is vague ("OK", "Continue") on a confirm sheet THEN name the action ("Delete 3 artboards") and keep Cancel calm; tradeoff: explicit labels are longer.

## Placeholders and real content
- IF placeholder copy carries real instructional weight THEN it disappears on input — move instructions to a label or helper line; tradeoff: helper lines add height.
- Anti-generic rule applies: no "Lorem", "Your heading here" in real boards (anti-generic.md — subject grounding).

## Honesty
- Copy quality in real context (brand voice, tone across a product) is the designer's call — this module proposes patterns and consistency checks, and says when a call is taste.
