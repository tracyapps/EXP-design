# Homepage feature image briefs — v2.1

The homepage now uses the selected v2.1 screenshots for its product, component,
accessibility-teaching, and Design Language stories. The import + handoff diagram
remains intentionally illustrative because it communicates the workflow more
clearly than a collection of unrelated export dialogs.

## 1. Component system

**Selected images:**

- `website/public/assets/components-nested-overview.png`
- `website/public/assets/components-editor-detail.png`

**Story to show:** one reusable source can contain another source, while placed
instances choose different states and overrides without becoming disconnected
copies.

The wider image establishes nested structure, states, relationships, and multiple
editor contexts. The smaller foreground detail makes the selected nested source,
state, public properties, and overrides readable without asking one screenshot to
carry the entire story.

The earlier CSS source-to-instance diagram was removed in favor of these real
product views.

## 2. Import + Handoff

**Suggested filename:** `website/public/assets/import-handoff-workflow.png`

**Story to show:** EXP fits between the tools a designer already uses instead of
demanding a closed workflow.

**Suggested composition:**

```text
Figma · XD · PDF · SVG/images  →  EXP [design]  →  PNG/JPEG · PDF/SVG
                                             →  semantic HTML · tokens
                                             →  Handoff Package · local agent
```

This can be a clean diagram rather than a literal screenshot. Keep EXP centered,
make both sides feel equally important, and avoid implying that unsupported
formats round-trip perfectly. “Import” means editable where the fidelity report
says it is; “handoff” means the designer chooses the artifact the next step needs.

**Alt-text draft:** “Figma, Adobe XD, PDF, SVG, and image inputs flowing through
EXP into visual exports, semantic HTML, design tokens, a Handoff Package, and a
local read-only agent.”

## 3. Design Language refresh

**Selected images:**

- `website/public/assets/design-language-panel-v2-1.png`
- `website/public/assets/design-language-css-import.png`

The tall panel shows colors, gradients, complete type styles, categories, recent
items, and list/grid controls in the working interface. The wider settings image
adds the CSS palette-import path. Together they say both “use the system while
you design” and “bring an existing system with you.”

The section copy now describes CSS, EXP JSON, and W3C design-token handoff, but
the image does not need to show every export menu.

## Accessibility image strategy

Keep the existing contrast screenshot and the three text-led “accessible
thinking” points. The new collage uses:

- `website/public/assets/aria-guide-overview.png`
- `website/public/assets/aria-guide-role-detail.png`

The overview proves the broad, plain-language teaching model; the focused Link
role view shows that the guidance continues into use cases, cautions, code, and
common confusion. The more sparsely composed Link-vs-Button screenshot was not
used because the detail view communicates the same distinction more efficiently.

## Homepage product view

`website/public/assets/exp-canvas-workbench-v2-1.png` replaces the older hero
capture. It was chosen over the near-duplicate option because the selected
component and populated Properties, Components, Design Language, and Handoff
panels show more of the v2.1 workflow in a single glance.
