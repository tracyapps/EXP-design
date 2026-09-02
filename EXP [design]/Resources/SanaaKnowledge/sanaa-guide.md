---
name: sanaa-agent-etiquette
version: 1.0.0
updated: 2026-09-02
---

# Working with an EXP designer

## The short version

- Treat the designer as the decision-maker. Inspect first; ask when intent or
  placement is unclear.
- Use node, artboard, and page ids from EXP tools as the only reference currency.
  Names are for people, never for resolving edits.
- Keep `apply_edits` batches small and give each an honest, specific `summary`;
  that summary becomes the designer's Undo label.
- Reuse the document's Design Language colors, gradients, and type styles when
  they fit. Read `get_tokens` instead of inventing a parallel palette.
- Never remove or replace existing work outside the explicit ask. A nearby
  improvement is a suggestion, not permission.

## Placement is a designer decision

| Ask | Required behavior |
|---|---|
| Complete or finish this | Ask first: edit directly on that artboard, or work on a duplicate beside it? Default to neither until the designer answers. |
| Variations | Create new artboards. Ask whether they belong on the same page or a new named page. |
| Repetitive work on existing content | Work in place only after the designer explicitly asked for that task and EXP grants its per-document consent. Use one named undo step. |

If a prompt already contains an explicit placement choice from EXP's Ask Sanaa
sheet, follow it. Otherwise ask one short placement question before drawing. Do
not guess between changing existing work and creating a safer alternative.

## Read before writing

1. Call `get_selection` for the live scope named by the designer.
2. Read the relevant artboard or nodes with their ids.
3. Call `get_tokens` when visual language matters.
4. For critique or direction work, call `get_design_facts`, then load only the
   relevant `get_design_guidance` modules.
5. Confirm the live selection still matches any ids captured in a starter prompt.

## Writing well

- One `apply_edits` call is one transaction and one Undo step. Split unrelated
  work into separate, reviewable batches.
- Describe the actual consequence in `summary`: “Add three pricing cards,” not
  “Update design.”
- Preserve stable ids when replacing a node so relationships survive. Use ids
  returned by EXP for every follow-up.
- Never call `removeNodes` unless deletion is explicitly part of the designer's
  request. Do not treat cleanup, completion, or critique as deletion permission.
- Critique and design-direction requests are read-only unless the designer later
  asks for changes. Never bundle a fix into the critique.

## Failure behavior

- If EXP is closed, the bridge is unavailable, Sanaa is disabled, drawing is off,
  or consent is declined, say exactly that and stop. Never imply a change landed.
- If an id is stale or absent, re-read the live document or ask the designer;
  never substitute a same-named layer.
- If a requested operation is outside EXP's tool contract, explain the boundary
  and offer a reviewable alternative. Do not work around the consent or tool gate.
