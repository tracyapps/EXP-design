# EXP [design] v2.3

## A faster, calmer everyday canvas.

EXP [design] 2.3 is a broad workflow release: fewer missed clicks, selection
geometry that agrees with what you see, workspaces that return to the right
screens, faster font discovery, direct gradient editing, real line-end controls,
and an Inspector that is easier to read and harder to misclick.

This release grew through seven owner-tested waves. The completed interaction,
workspace, type, gradient, line, accessibility, and interface work ships now;
the remaining lower-priority vector/effect queue is deliberately deferred to
2.4 rather than holding back the verified improvements.

### Canvas interaction and selection

- The canvas accepts the first click after focus moves to it.
- Option-drag duplication no longer depends on unforgiving key/mouse timing.
- Gradient stops, path points, and handles have more reliable hit targets, and
  keyboard tool switching no longer loses common shortcuts.
- Shift constrains new shapes and frames to a square from the start.
- Selection and transform boxes use visible ink bounds, including outside
  strokes, while resize math still writes the underlying geometry correctly.
- Nested and transformed group selections keep their resize/rotate handles.
- A dedicated Snap to whole pixels preference prevents fractional resize drift.
- Point selections share the same transform-box behavior as object selections.
- Artboard-bound snapping includes the artboard walls with a subtle default
  pull, while preserving deliberate movement past a boundary.

### Workspaces built for real monitors

- Save, name, update, rename, delete, and switch complete workspace presets.
- Presets restore panel positions, sizes, contents, collapse state, workspace
  mode, and multi-monitor placement; missing displays clamp every window back
  onto an available screen.
- Workspace mode stays consistent across every open document window.
- Place panel groups side by side, pause at the insertion indicator to glue
  them, move the connected group together, and pop them apart explicitly.
- Connected panels preserve their independent positions and heights instead of
  being merged into one oversized window.

### Font discovery and text memory

- The font picker is now a taller, active-display-aware browser instead of a
  short fixed menu.
- Search one previewed font list and filter it through an optional icon rail:
  All Fonts, Fonts Used in this document, Recent, and macOS font categories.
- Filters are mutually exclusive, so two active facets cannot silently filter
  every font away. Counts, empty states, hover names, keyboard traversal, and
  VoiceOver state/result announcements are included.
- Recent fonts persist across sessions; Fonts Used is derived from the current
  document, reusable sources, overrides, and saved type styles.
- New point text and text boxes remember the last concrete font, size, and color
  used while typing or editing, across documents and relaunches.
- Line-height values convert cleanly between units and arrow-key stepping follows
  the selected unit.

### Lines and gradients on the object

- Lines and open paths now have whole-stroke Flat, Round, or Square caps plus
  independent start/end arrow markers.
- Arrow bases sit on the authored endpoint and their points project outward;
  the same geometry is used by the canvas, raster/PDF export, SVG export, and
  SVG re-import.
- Linear gradients expose on-canvas endpoints and stops. Add a stop anywhere on
  the gradient line—even over empty canvas—without changing the visible color.
- Drag stops and endpoints directly; edit a stop's color and position from the
  existing color popover; copy/paste stops at the pointer; or save a stop color
  directly to the Design Language.
- Canvas and Inspector share the selected stop. Changing the Inspector angle
  rotates explicit gradient endpoints around their midpoint while preserving
  the gradient's physical length.

### A clearer, more accessible Inspector

- Choose Compact, Standard, or Large interface type in Settings; the preference
  applies to docked panels, floating trays, source windows, and Settings.
- Dropdowns use one measured high-contrast boundary treatment in light and dark
  appearances, including Increase Contrast.
- Horizontal and Vertical flip actions are named and visible in the transform
  hierarchy. Align-to and Distribute remain spatially separated.
- Text case is an exclusive, arrow-key-operable icon control with independent
  accessible names and a non-color-only selected state.
- Effect rows can collapse to one line while retaining enable, effect type, a
  live settings summary, and the actions menu. Duplicate and destructive Remove
  are separated and available through Inspector, context, and Edit-menu routes.
- Tooltips now support hover and keyboard focus, remain hoverable, dismiss with
  Escape, yield immediately when the pointer reaches another control, and offer
  Full, Standard, or Minimal visible detail. Holding Option temporarily reveals
  the full explanation without changing accessible names or hints.
- The committed accessibility control audit records official pattern sources,
  accessible names, tooltip copy, and measured contrast receipts.

### Text, Layers, effects, and performance fixes

- Multi-selection dragging in Layers moves the whole selection and restores it
  in one undo. New groups stay at the intended stack position, and locked layers
  offer an explicit unlock action.
- Entering a canvas text node selects its existing contents for quick replacement
  while a subsequent click still places a precise caret.
- Spread values that cannot yet preview on arbitrary silhouettes remain visible
  and continue to round-trip instead of being silently discarded.
- Idle raster content no longer repeatedly flips between sharp and blurry states.
- Existing export, import, component, Handoff Package, canvas-page, and local
  read-only agent workflows remain intact.

### Honest interoperability notes

- Browser rendering is the SVG conformance target. macOS Quick Look/Preview and
  some versions of Illustrator or Affinity may interpret nested transforms and
  SVG markers differently even when the file renders correctly in a browser.
- Placed SVG `stroke-dasharray` fidelity is a separately tracked import bug and
  is not represented as fixed in this release.
- Arbitrary-silhouette shadow spread, direct-select whole-object movement, mixed
  Create Outlines, live-text outlines, Pencil, balanced handles, and the remaining
  Add-to-Design-Language entry points are deferred to 2.4.

EXP [design] 2.3 is build 14 and requires macOS 26.2 or later.
