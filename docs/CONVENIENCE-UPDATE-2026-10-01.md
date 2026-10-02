# Performance and convenience additions — 2026-10-01

Status: **owner-verified 2026-10-01**. Owner: “excellent. all work great to me.”
The owner explicitly authorizes this bundle in the small v2.6 release.
The owner approved these four additions after accepting FEAT-066/067. They share
one verification gate, now closed. Detailed scenarios below remain a regression
checklist; formal assistive-technology testing is not inferred from acceptance.

## Appearance commands (FEAT-068 / Phase 16c)

| Command | Copy | Paste | Contents |
| --- | --- | --- | --- |
| Effects | ⇧⌘C | ⇧⌘V | Effects, opacity, blending |
| Style | ⌥⌘C | ⌥⌘V | Fill, stroke, corners |
| Style & Effects | ⌥⇧⌘C | ⌥⇧⌘V | Both channels |

Each channel has its own per-window session clipboard. Ordinary Copy/Paste and the
system pasteboard are unchanged. Edit, canvas context menus, and both Layers context
menus expose all three pairs. Copy reads the first selected source in document order
(the paint command skips sources without paint). A Layers row copies that row.

Paint keeps the complete solid/gradient/pattern value, gradient endpoints/stops,
stroke width/alignment/pattern, supported caps/joins/miter/markers, uniform and
per-corner radii. Unsupported properties leave compatible target values alone.
Live text supports solid color/outline only; gradient/pattern paints are not flattened
onto text. Text/font metrics, shape geometry, path points, identity and semantic
metadata stay with the destination. Images/instances accept effects, not vector paint.

Ordinary folders pass paint to compatible nested artwork. An auto-padding folder
receives its background paint/corner treatment, preserving padding/margins/layout.
Effects affect explicitly selected layers, retaining whole-folder compositing.
Menu selection/appearance validation reuses its existing node index rather than
performing a separate document search for every selected icon.
Locked/hidden branches are protected. A single tree pass deduplicates inherited
paint and explicitly selected descendants; each paste creates one undo transaction.
Copied effects receive fresh identities, and an empty stack clears target effects.

## Ruler pointer performance (PERF-005)

The two moving pointer markers now use retained CAShapeLayers in a transparent,
click-through AppKit overlay. Plain pointer movement with rulers enabled no longer
invalidates the artwork. Pen hover and Option measurement still redraw their actual
canvas changes. Static ticks, guide interaction and camera redraws retain their
existing behavior. Markers use the system accent color and have no animation or
accessibility focus stop.

## Save type style (FEAT-034 remaining font surface)

The Type section in Properties has a 28 × 28 pt `plus.circle` button. It invokes the
same canvas action as Type → Save as Type Style, the text context menu, and the
Design Language panel's Save Type Style from Selection command. A native sheet
asks for a name, initially the layer name or readable font/size fallback. Cancel
writes nothing; Save creates one named library entry and one Undo step. The current
shared category model is retained (unfiled category), rather than reviving the
retired candidate/official status model. Typography excludes color and geometry.

Accessible names were checked against [W3C APG Button](https://www.w3.org/WAI/ARIA/apg/patterns/button/)
and the native AX tree exposes both the save button and “Type style name” field.
Native controls own focus/keyboard behavior. Full VoiceOver, Full Keyboard Access,
light/dark and Increase Contrast passes remain owner checks, not implied by this test.

## Notes task lists (FEAT-019)

The Handoff Package orientation Markdown converts bare `[ ]`, `[x]` and `[X]`
notes markers into list items, per [GFM §5.3](https://github.github.com/gfm/#task-list-items-extension-).
Existing task lists, headings and formatting are retained; fenced/indented code
samples are protected. Normalization happens at export, preserving the notes editor's
checkbox styling, Return continuation, and saved plain-string schema.

## Fresh verification

- Debug `xcodebuild`, signing disabled, derived data `/tmp/exp-convenience-build`:
  **BUILD SUCCEEDED**, including the shared-model thumbnail extension.
- `scripts/verify_appearance_style.sh`: paint/effects/combined boundaries, gradient
  geometry, patterns, stroke/corners, path geometry/caps/joins, nested folders,
  hidden/locked branches, padding preservation, text limitations, named type styles,
  800-icon batch and encoded round-trip **PASS**.
- `scripts/verify_ruler_pointer_overlay.sh`: 500 retained marker moves after a real
  initial parent draw, **zero parent artwork redraws**; exact x/y positions,
  click-through, hiding, decorative accessibility and no animation **PASS**.
- `scripts/verify_semantic_html_package.sh`: new checkbox check failed on baseline
  (`bare notes checkbox must export as a GFM task list`), then passed with checked
  states, existing tasks, code samples and unchanged saved notes. Existing semantic
  HTML golden, package/manifest, nested-landmark, mask and CodePen checks **PASS**.
- `scripts/verify_vector_shape_editing.sh`: previous Knife/Unite regression **PASS**.
- `scripts/verify_node_tree_performance.sh`: nested selection, transforms/flips,
  style targets, batched edits and revision/page/scope/state/document invalidation
  **PASS**; final indexed-menu build **BUILD SUCCEEDED**.
- Disposable native `/tmp/EXP Convenience Test.app` and synthetic `.design`:
  all three keyboard pairs, effects clipboard retained after copying different
  text paint, paint-only/effects-only preservation, combined gradient/stroke/corner/
  effects rendering, Layers context labels, Inspector naming sheet, named library
  entry, one-step type-style Undo/Redo and saved geometry/typography **PASS**.
  Test app closed; owner app/documents untouched. Updater disabled only in test app.
- `git diff --check` and backlog ID collision guard **PASS**.

Existing renderer/isolation compiler warnings remain; no unrelated warning cleanup.
This does not claim a measured frame-rate change in the owner's stress document.

## Owner check after rebuilding

- [ ] Rulers on in `stresstest.design`: move the pointer, pan/zoom and drag a guide;
      markers stay aligned and plain movement avoids artwork stalls.
- [ ] Each copy/paste pair does what its table says, including nested icon folders,
      independent clipboards and one-step Undo.
- [ ] Save a named type style from Properties; Cancel and Undo behave naturally;
      saved treatment applies through the existing library workflow.
- [ ] Export artboard notes with checked/unchecked items; orientation Markdown
      renders actual task-list checkboxes in a GFM reader.
- [ ] Shared bundle acceptance. Formal assistive-technology checks stay separate
      if they have not been performed.
