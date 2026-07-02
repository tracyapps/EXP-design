# UX Design Tool — Project Roadmap & Progress Log

A native macOS design application built around an actual UX workflow,
not feature-count parity with Figma/XD. Guiding principle: **the tool
should get out of the way.**

---

## How we work together

See **WORKING-AGREEMENT.md** in this folder for the collaboration rules
(who runs the compiler, how sessions resume, how this file stays the memory).
Short version: Claude writes code, the user runs it in Xcode and reports back;
this file is the source of truth and the Progress Log is updated every session.

---

## The v1 scope (locked)

A fast native canvas with:

1. Pan / zoom / artboards — buttery smooth, this is the whole thesis
2. Shapes + text + layers
3. **Source/instance components** — the one heavy subsystem; built the
   *simple* way (double-click opens source in its own editing context;
   each instance carries per-layer visibility + a small bounded set of
   overrides). Terminology: **"source,"** never "master."
4. Export to PNG / PDF / SVG
5. **Structured artboard notes** — interaction notes, "assumptions,"
   "test this first" — with a handoff export. This is the point-of-view
   feature that makes it *your* tool.

Explicitly NOT in v1: prototyping/interactions, auto-layout/constraints,
plugins, multiplayer, advanced typography.

---

## Architecture decisions

- **Language/UI:** Swift + SwiftUI for app chrome (panels, inspectors,
  menus) because declarative UI suits how you think. AppKit/Core Graphics
  (and likely Core Animation / Metal-backed layers) for the canvas itself,
  where SwiftUI isn't the right tool for high-performance custom drawing.
- **Rendering:** Use Apple's own frameworks (Core Graphics / Core Animation,
  Metal where needed). Do NOT build a renderer from scratch.
- **Document model is the foundation.** An instance is a *reference* to a
  source + overrides, never a copy. This must exist from the first lines of
  code — retrofitting it later is a project-killing rewrite. Everything
  else hangs off this model.
- **Export dividend:** PNG and PDF come nearly free from the native drawing
  system. SVG requires walking the document model and emitting markup
  ourselves (you know SVG by hand, so we can make this output genuinely good).
- **Appearance:** use Apple *semantic* system colors everywhere (e.g.
  `.underPageBackgroundColor`, `.windowBackgroundColor`, `.labelColor`) so the
  whole app follows system light/dark automatically. Deliberate exception: the
  **artboard stays white regardless of app theme** — you're designing a screen,
  not theming the tool. Don't "fix" this later by accident.
- **Editor layout, not navigation layout:** the side panels are persistent
  inspectors, NOT a navigation hierarchy. Use `HSplitView` (resizable panes),
  not `NavigationSplitView` (which is built for Mail/Notes-style navigation and
  fights an editor UI). Confirmed via research before building the shell.
- **FLOATING/DETACHABLE PANELS — founding principle (scaffolding-sensitive).**
  The end goal is Photoshop/Illustrator-style independent palettes, not
  edge-locked panels. User runs multiple monitors (incl. a vertical 27") and
  wants to push 90% of panels onto other screens, open many at once side-by-side
  (e.g. Layers + Components together, no forced tabs), and expand the canvas to
  fill a 30" display. Tools strip stays fixed on the left of the main screen;
  everything else is free-floating.
  - Full version is **v2**, BUT the decision is locked now because it changes
    how the window is built. The cheap-now / brutal-later rule applies.
  - **The key architectural move:** every panel is written as a fully
    self-contained `View` that reads/writes **shared app state** and makes NO
    assumption about *where* it's hosted. Then the same panel code can be
    docked-in-main-window (v1, good for single-screen/laptop) OR popped into its
    own floating macOS panel-window on any monitor (v2). macOS already handles
    multi-monitor window placement, so once a palette is its own window, it
    "just works."
  - This is why we introduce a shared **app-state object** early (Phase 1/2)
    instead of scattering `@State` in the window — required for portable panels
    AND needed by the component system anyway.

### Cost map (why the timeline is what it is)
- *Cheap* (sit on the canvas): shapes, alignment/snapping/guides, keyboard
  control, color handling, grids/spacing, export options, opinionated defaults.
- *Expensive* (own subsystem): components/instances ✅ (in v1, simple version),
  auto-layout, prototyping, advanced text, plugins, multiplayer (all deferred).

---

## Build phases (the actual sequence)

### Phase 0 — Project skeleton & first runnable window ✅ DONE
- [x] Xcode project created, runs an empty window
- [x] Basic app structure / folder layout agreed (Model / Canvas / UI groups)
- [x] Confirm Swift/Xcode versions: **Xcode 26.3, Swift 6.2.x, macOS 26 SDK**
- [x] Three-pane editor shell built (HSplitView: LeftPanel · CanvasView · RightPanel)
      with toolbar toggles and a placeholder artboard. Runs correctly.
- App name: **EXP [design]** ("exp"). Location: ~/Dropbox/work/custom-work-tools/apps/
  NOTE: Dropbox + Xcode build folders can occasionally conflict; if weird build
  errors appear, suspect Dropbox syncing build/DerivedData first.

### Phase 1 — The canvas (the make-or-break piece) ✅ DONE
- [x] Introduce shared app-state object (foundation for portable panels + components)
- [x] A canvas view that renders (AppKit-backed)
- [x] Pan (space-drag / trackpad) and zoom, smooth
- [x] Artboards: create, position, render — New Artboard button (⇧⌘N), drag to
      move, arrow-key nudge (Shift = 10pt), drawn crisp in view space at any zoom
- [x] Coordinate system / hit-testing groundwork — doc↔view transform both ways,
      artboard hit-testing, click-to-select with accent halo, Tab cycles
      selection, Delete removes (NB: this is artboard-level; per-layer
      hit-testing/selection still belongs to Phase 3)

### Phase 2 — The document model ✅ DONE
- [x] Core data structures: Document → Artboards → Layers → Nodes
      (`Model/Document.swift`, value types, Codable, UI-free)
- [x] Reference-based design so instances can point at sources later
      (`ComponentSource` + `.instance(ComponentInstance)` carrying `sourceID` +
      bounded overrides + per-layer visibility — references, never copies)
- [x] Save / open a file format that opens *instantly* — native **DocumentGroup
      + ReferenceFileDocument** (`Model/ExpDocument.swift`), pretty-printed JSON
      `.exp`. Undo-aware `setModel` funnel powers ⌘Z AND marks the doc dirty so
      Save works. Sandbox set to `user-selected files: readwrite`. Finder file
      association needs the one-time `Info.plist` build-setting step (see log).

### Phase 3 — Primitives & layers
- [x] Rectangle, ellipse, line/path, text — rectangle, ellipse, text, and
      **straight line** all done. Line: L tool, drag to draw, 2 endpoint handles
      to edit, stroke color + width in the Inspector, hit-tested by distance to
      the segment. (Full **pen/bézier path** editing is deferred to its own later
      subsystem — out of v1 primitives scope.)
- [x] Selection, move, resize — click-select topmost shape, drag to move,
      8-handle resize, arrow-nudge, delete; one undo step per gesture
- [~] Layers panel: order, visibility, lock, folders/groups — **panel built**
      (`UI/LayersPanel.swift`): grouped by owning artboard + Wall, front-of-stack
      at top, eye/lock toggles, double-click rename, drag-reorder (mapped to
      global z-order), two-way selection sync with the canvas. Multi-select:
      click = replace, **Shift-click = range**, **Option/⌘-click = toggle**
      (anchor in AppState, shared with canvas clicks). **Group/ungroup done**
      (⌘G / ⇧⌘G + context menu; groups render/move/clip as a unit, children stored
      group-local). Still to do: nested-row display of group children in the
      panel, and group box-resize.

### Phase 4 — Source/instance components ✅ DONE
- [x] Define a "source" from selected layers — **Create Component** (⌘K +
      context menu): wraps selection into a `ComponentSource` (root group,
      children source-local) and replaces it with an `.instance` node.
- [x] Place instances that reference the source — instances render by resolving
      the source (recursive draw at the instance origin); duplicate/copy-paste
      makes more true instances (clone keeps `sourceID`).
- [x] Double-click instance → edit source in its own context → return, instances
      update — the source-editor window now **really edits**. The canvas is
      scope-parameterized (`.document` vs `.source(id)`); the editor window hosts
      a live `CanvasView(scope:.source)` + its own ToolsStrip + own AppState, and
      shares the document's undo manager (window delegate vends it) so ⌘Z works
      and Save sees the change. Edits to a source update every instance live.
      Polish still pending: an Inspector inside the source window (stroke/font/
      color editing there), and auto-growing the source bounds.
- [x] **Detach Component** (⇧⌘K + right-click) — convert an instance back into
      independent layers (fresh copies of the source's children at the instance's
      position; source left intact for other instances; hidden layers carry over).
- [x] Per-instance layer/folder visibility toggles (the InDesign behavior) —
      expand an instance in the Layers panel to see its source layers, each with
      an eye toggle that's a TRUE per-instance override (`layerVisibility`): it can
      show a source-hidden layer or hide a source-visible one, independent of the
      source; matching the source default drops the override so it inherits again.
      Honored live in render + on detach. (Top-level source layers for now.)
- [x] Bounded overrides (text/color swaps) — per-instance text + fill overrides
      (`InstanceOverride`). Select an instance → Inspector "Overrides" section
      lists the source's text layers (editable text fields) and fillable layers
      (color pickers); each has a reset-to-source button. Applied live in render
      and baked in on detach. (Top-level source layers; nested + stroke later.)

### Phase 5 — Export ✅ DONE
_`Export/ExportRenderer.swift` (rendering) + `Export/ExportPanels.swift` (the
panels). File ▸ Export Selected Artboard… (⇧⌘E) → NSSavePanel with a **Format
popup** (PNG/PDF/SVG); File ▸ Export All Artboards… → folder picker with a
**Format popup (PNG/PDF/SVG/All)** plus a **"Combine PDF pages into one file"**
checkbox. Renders in artboard-local coords._
- [x] PNG export — rasterized from the vector PDF at @2x (crisp; not upscaled)
- [x] PDF export — drawn via a flipped offscreen NSView (vector, correct text)
- [x] SVG export (custom emitter) — straight from the model (SVG is y-down like
      us); rect/ellipse/line/path(bezier)/text/group/instance(+overrides+visibility)
- [x] Format picker accessory in both panels; updates the save panel live
- [x] Multi-page PDF — one page per artboard, merged via PDFKit (`Artboards.pdf`)
- [x] **Export Selected Artboard(s)** handles multiple boards: 1 board → save
      panel; 2+ → folder + format + combine-PDF (shares the all-artboards panel)
- [ ] (later) PNG scale chooser, transparent-bg option

### Phase 5.5 — Artboard improvements ✅ DONE
- [x] **Size presets** — New Artboard is now a split menu (Phone/Tablet/Desktop/
      Web/Square/Story/Slide/A4/Letter); primary click = default. `ArtboardPreset`
      list in MainWindow, easy to extend.
- [x] **Artboard resizing** — 8 resize handles on the lone selected board; Shift =
      proportional. Resizing changes the frame only; the wall rule re-derives
      ownership (shapes don't scale — matches frame-resize expectations).
- [x] **Multi-select artboards** — `AppState.selectedArtboardIDs` (Set);
      `selectedArtboardID` kept as a single-select compatibility wrapper.
      Shift-click a board's label to add/remove; all selected boards draw the
      accent outline; Inspector shows "N artboards selected".
- [x] **Move multiple boards** — dragging any selected board's label moves the
      whole set + every shape each owns (Shift = axis-lock). Arrow-nudge + Delete
      also act on all selected boards.
- [x] **Option-drag duplicates** boards + all their contents (new ids; one undo
      step), then drags the copies — mirrors shape option-drag.
- [x] **Rename artboards** — Inspector name field, double-click the label for an
      inline editor, and right-click ▸ Rename.
- [x] **Marquee = boards when fully enclosed** — a lasso that completely surrounds
      one+ artboards selects the boards; partial drags still select items.
- [x] **Rearrange mode** — with 2+ boards selected, dragging anywhere inside a
      selected board moves the whole set + contents (not the shape under cursor).
- [x] **Copy/paste artboards** (⌘C/⌘V + context menu) — pastes boards + contents.
- [x] **Artboard-aware shape paste** — pasting shapes lands on the focused board
      at the same position relative to it, or centered if it won't fit.

### Phase 6 — Structured notes & handoff ✅ DONE
- [x] Notes attached per artboard (NOT an artboard themselves) — `Artboard.notes`
      (backward-compatible decoder); travels with the board on move/dup/delete.
- [x] Notes UI: SwiftUI `ArtboardNotesOverlay` aligned to the canvas camera — a
      toggle button left of each board's name (muted when empty, accent when it
      has content; no badge), opening a resizable, auto-growing, editable panel
      that expands down-and-to-the-left (off the board). Keyboard + VoiceOver.
- [x] Handoff export "Include notes" — PDF only (single + multi-page); adds a
      Letter "Notes — <board>" page after each board with notes (PPT-style).
- [x] Notes editor is a real multi-line `NSTextView` (`NotesEditor`/`NotesTextView`):
      Return = line break, Tab/Shift-Tab = indent/outdent (4 spaces), bullet lines
      ("•/-/\*") auto-continue (empty bullet ends the list), indentation carries to
      the next line. Plain-text storage → Markdown-ready. Panel size persists per
      board across close/open (`AppState.notesPanelSize`).
- [ ] (later) **Markdown** rendering + styling (headings, bold/italic, highlight);
      batch notes undo (currently per-keystroke like the other text fields)

#### Phase 6 design spec (agreed Session 25)
- **Model:** notes are a property *on* `Artboard` (e.g. `notes: String` or a small
  `ArtboardNotes` struct — likely rich-ish text later, plain string first). They
  are NOT nodes and NOT artboards, so they never appear on the wall, in Layers, or
  in shape hit-testing. Because they live on the artboard, they **move, duplicate,
  and delete with it for free** (artboard duplication already deep-copies the
  struct; multi-move carries it).
- **Affordance:** a small **menu / "more" button to the LEFT of the artboard name
  label**. Clicking it toggles a notes panel that **expands down-and-to-the-left**
  (so it never overlaps the artboard itself). The same button collapses it again.
- **Button state:** subtly differentiated when notes exist vs empty — like the
  difference between a primary and a muted/disabled button. **Not** a badge or
  notification dot; just "slightly more prominent" to signal there's content.
- **Panel sizing:** manually resizable, AND auto-grows to at least the height of
  its text content (never clips the note).
- **Export:** when exporting a board that has notes, offer an **"include notes"**
  option (conceptually like PowerPoint exporting slides with speaker notes) —
  rides on the PDF/handoff path. Plain export stays note-free.
- **A11y/ethics tie-in:** this is the point-of-view feature (fight thoughtless
  handoff). Keyboard-operable toggle + VoiceOver label on the notes button.

---

## Polish roadmap (Phases 7+) — planned Session 30

The owner's polish list, organized by value/effort. Within-phase order is
flexible; the two **BIG** phases (15, 16) and explicitly **lower-priority** items
(blend modes, grid auto-lines, images) are deferred to the end on purpose. Each
phase is independently shippable.

### Phase 7 — Inspector & input polish ✅ DONE
- [x] **Universal numeric stepping** (`NumericStepping` modifier in MainWindow):
      ↑/↓ = ±1, ⇧ = ±10, ⌥ = ±0.1, **hold accelerates** (step grows every 5 key
      repeats). Applied to X/Y/W/H (`DimField`), corner radius, stroke widths,
      font size, and the zoom %.
- [x] **Rename element in the Inspector** — inline "Layer" name field above the
      dimensions (`nodeNameBinding` → setModel "Rename Layer"); the Layers panel
      reads the same model, so it stays in sync.
- [x] **Zoom cluster** (RightPanel): editable % field (with stepping), preset menu
      (Fit, Actual 100 %, 25/50/100/200/400 %), a log-scaled slider, and ± buttons.
      Shortcuts in the View menu: ⌘+ in, ⌘- out, ⌘0 Actual, ⌘1 Fit. Zoom keeps the
      viewport center fixed (`AppState.zoomTo`, fed by `viewportSize` from layout).
- [ ] (later) "Fill" preset; zoom-to-selection

### Phase 8 — Color system & gradients
**Build 1 ✅ DONE (Session 32) — custom picker + formats + OKLCH + artboard bg**
- [x] **Inline color popover** at each swatch (`ColorWell` + `ColorPopover` in
      `Color/`): saturation–brightness field, hue + alpha sliders, screen
      **eyedropper** (`NSColorSampler`). Replaces the macOS `ColorPicker` everywhere
      (Inspector fill/stroke/text/path + instance fill overrides).
- [x] **Multi-format readout + copy/paste**: a format selector (HEX / RGB / HSL /
      LCH / OKLCH) with one editable, copyable code field; typing a valid code in
      any space sets the color. `ColorMath` does the conversions/parsers.
- [x] **OKLCH (+ LCH) authoring** — convert to sRGB (gamut-clamped) on input; model
      stays sRGB `RGBAColor` on disk.
- [x] **Artboard background color** — `Artboard.background` (backward-compatible
      decoder, default white); rendered on canvas + PNG/PDF/SVG export; Inspector
      "Background" well.
**Build 2 ✅ DONE (Session 35) — gradients**
- [x] **`Paint` type** (`.solid | .gradient`) replaces the `RGBAColor` fill on
      rectangle/ellipse/path + `Artboard.background`. Backward-compatible: a solid
      encodes as a bare `RGBAColor` (old files load unchanged); gradients add a
      tagged object. `GradientFill` = kind (linear/radial) + multi-stop + angle.
- [x] **Rendering** via shared `PaintRender` (CoreGraphics) — identical on canvas
      and in PNG/PDF export. **SVG** emits `<linearGradient>`/`<radialGradient>`
      defs in objectBoundingBox units (one def fits any element size).
- [x] **Gradient editor** (`PaintWell` + `PaintEditor`): Solid / Linear / Radial
      segmented; a stop bar (drag to add/move, select to recolor, delete; min 2),
      stop color + position, and an angle control for linear. Wired into shape +
      path fills and the artboard background well.
- [x] **Gradient as a component fill override** (Session 36) — `InstanceOverride
      .Value.fill` is now `Paint`; the override well is a `PaintWell`. Legacy
      solid overrides decode unchanged.
- [ ] (later) **gradient text fill** (text stays solid for now); **on-canvas
      gradient handles**

### Phase 8.5 — Rotation ✅ DONE (Session 36)
- [x] **`Node.rotation`** (degrees, clockwise about center; defaulted → old files
      load). Rendered on canvas + PNG/PDF export (CTM rotate) and SVG
      (`<g transform="rotate(...)">`).
- [x] **Interactions**: hit-testing inverse-rotates the cursor; selection box +
      handles + a **rotate knob** draw on the rotated shape; dragging the knob sets
      the angle (Shift = snap 15°); **resize while rotated** keeps the opposite
      corner pinned in world space (resize in local space + world-anchor
      correction). Inspector **R°** field with stepping.
- [ ] (later) rotate handle for paths/lines/groups (today: box shapes get the
      knob; everything rotates via the R field); rotated-bounds marquee

### Phase 9 — Typography ✅ DONE (Session 39)
- [x] **Typeface picker with live preview** — `TextContent.fontName` (PostScript
      face; empty = system, backward-compatible). Inspector menu lists families
      each rendered IN their own face, plus a weight/style Picker for the family.
      `UI/Typography.swift` (`FontCatalog` + `resolvedFont`/`measuredSize`/
      `familyName`). Font threads through canvas draw, inline editor, text
      measuring, PNG/PDF export, and SVG (`font-family` + bold/italic).
- [ ] (later) custom/embedded **font import** beyond installed system fonts;
      font search field for long lists

### Phase 9.5 — Rich text (multi-style) — IN PROGRESS
_Owner chose to go straight to full rich text. Staged across builds._
**Build 1 ✅ DONE (Session 40) — foundation + B/I/U**
- [x] `TextContent` is now **styled runs** (`[TextRun]` = string + face + size +
      color + underline) + paragraph props (align/lineHeight/tracking/box).
      Backward-compatible decode (old single-style → one run).
- [x] NSAttributedString **bridge** (`Typography.swift`): build for draw/measure/
      edit, rebuild runs from the edited attributed string. Threaded through canvas
      render, the **rich** on-canvas editor (`isRichText`), measuring, PNG/PDF, and
      SVG (`<tspan>` per run).
- [x] **Bold / Italic / Underline** — Format menu (⌘B/⌘I/⌘U) + inspector buttons;
      apply to the **selection while editing**, else the whole node.
- [x] Removed the inspector text field (item 1); typeface/size/color now apply to
      the whole node and show **"Multiple"** when runs differ.
**Build 2 ✅ (mostly) DONE (Session 43) — paragraph + type settings**
- [x] **Line vs paragraph** box — explicit **Auto/Text-box** toggle in the
      inspector; **drag-to-create** a fixed box with the text tool (click = auto);
      auto hugs, fixed keeps its size and wraps. Resizing a box makes it fixed.
- [x] **Cropped-text indicator** — red "+" badge at the box's bottom-right when a
      fixed box has more text than fits (`draw(in:)` clips to the box).
- [x] **Alignment** (L/C/R) + **line height** + **letter spacing** in the type area
      (model already in the paragraph style; wired controls).
- [x] **Selection font-size** in the inspector (size field drives the selection
      while editing via the Session-42 style channel; "Multiple" shown).
- [x] **Zoom-stable text** — text now lays out at TRUE size and the *drawing* is
      scaled (CTM), so wrapping/line-height no longer "hop" between zoom levels.
- [x] **Case transforms** (as-written / UPPER / lower / Sentence / Title) — Session 51.
      Non-destructive (CSS `text-transform`): stored runs untouched, applied at
      display/measure/export via `TextContent.displayStrings()` +
      `attributedString(applyCase:)`. The inline editor uses `applyCase: false` so you
      always edit the original characters. Inspector "Case" picker.
- [x] **Convert text → shapes** (glyph outlines → path nodes) — Session 53, refined
      Session 54. Core Text (`CTFramesetter`/`CTFontCreatePathForGlyph`) outlines the
      laid-out, case-applied text into **one path node per glyph**, each sized to its
      TIGHT ink box (no ascender/descender padding) and stored on a new
      `PathShape.contours` (multi-subpath, even-odd fill so counters punch through).
      The letters are **auto-grouped** (group frame = tight union, children relative —
      matches `group()`), so each letter is independently selectable and **Ungroup
      splits them into individual letter shapes**. Single glyph → a lone path node.
      Layer named per character; transform / opacity / effects carry over. Renders +
      exports (PNG/PDF/SVG, nonzero winding). Right-click "Convert to Outlines" +
      Format ▸ ⇧⌘O. Point editing is contour-aware (Session 55) — the Edit-Points tool
      shows and drags anchors/handles on **every** contour of a glyph (inner counter
      of an 'o', all pieces of a complex face). _Underline strokes aren't outlined._

> **⚠️ KNOWN BUG (unsolved across multiple AI agents, incl. this one) —
> "selection style lost on direct click-out."** When you change a text run's
> size/color/weight from the Inspector and then click straight off the text box
> **without first collapsing the selection**, the change is dropped on commit.
> Workaround: click once in the text to deselect (collapse the selection) while the
> box is still active, *then* click out — the change sticks. Attempted fixes
> (Sessions 46–50): deferred apply, `editorSelectedRange` to survive focus loss,
> and a fully synchronous `app.applyTextStyle` hook replacing the async channel.
> None fully resolved it; the commit still reads an editor state that doesn't
> reflect the change in the click-out-while-selected path. **Needs a fresh root-cause
> pass** (suspect: the `NSTextView` first-responder/selection lifecycle vs. when
> `commitTextEditing` snapshots `attributedString()`; possibly instrument with logging
> of `editorSelectedRange`, `firstResponder`, and the committed runs to see exactly
> what's read).

### Phase 10 — Effects
- [x] **Layer opacity** (Session 51) — `Node.opacity` (0…1, default 1, hardened
      decoder that also back-fills `rotation`). Rendered as a grouped transparency
      layer on canvas + PNG/PDF (`beginTransparencyLayer` + `setAlpha`) and SVG
      (`opacity` on the element/group). Inspector 0–100% field next to R°.
      **Number-key shortcuts** (Session 51): canvas focused + shapes selected + not
      editing text → 1–9 = 10–90%, 0 = 100%, applied to all selected nodes as one
      undo step (`setOpacityOnSelection` in `keyDown`).
- [x] **Drop shadow** + **inner shadow** (Session 52) — `Node.effects: [Effect]`
      (CSS box-shadow geometry: color, dx, dy, blur, spread, enable toggle). Shared
      `EffectsRender` (Color/) + `Silhouette` helper, used by canvas + export. Drop
      shadow stamps the shape silhouette (or, for text/lines/open-paths/groups, the
      node's own painted content) into a shadowed transparency layer; inner shadow
      clips to the shape and casts inward. Rendered on canvas, PNG/PDF, and SVG
      (`<filter>` with feGaussianBlur/feOffset/feMorphology-for-spread/feFlood +
      feMerge; drops under source, inners over). Inspector "Effects" section: add
      menu (Drop/Inner), per-effect enable / type / color / X / Y / Blur / Spread,
      remove. _Spread is exact for rect/ellipse; ignored for arbitrary closed paths._
- [ ] (lower priority) **Blend modes** — the CSS `mix-blend-mode` subset
      (multiply / screen / overlay / darken / lighten / …).

### Phase 11 — Layout, alignment & guides
- [x] **Align & distribute** (Session 56) — edges/centers (L/C/R, T/M/B) + distribute
      horizontal/vertical spacing (equal gaps, extremes pinned, needs 3+). Illustrator-
      style **Align-to** toggle (`AppState.alignTarget` = Selection | Artboard); aligning
      to the artboard works on a single item too (center one thing on a board). Logic in
      `CanvasNSView` (`align(_:)` / `distribute(horizontal:)`, one undo step). Reachable
      three ways: Inspector row (icon buttons + Align-to picker, shown for selections),
      Arrange menu, and menu validation gates them (2+ to align, 3+ to distribute).
- [x] **Spacing measurements on ⌥-hover** (Session 57) — hold ⌥ with a selection and
      hover: red measure lines + point labels show the H/V gaps to the shape under the
      cursor, or the four distances to the artboard edges when hovering empty space.
      Live in `CanvasNSView.draw` (`drawMeasurements`), gated on `optionHeld` (tracked
      in `mouseMoved`/`flagsChanged`) and a non-drag state.
- [x] **Rulers + guides** (Session 58) — Photoshop-style rulers (top + left strips,
      document-coord ticks with zoom-aware nice steps + a pointer marker). Guides live
      in `Document.guides` (persisted, backward-compatible). Drag from the top ruler =
      horizontal guide, left ruler = vertical; drag a guide to move, drop on a ruler to
      delete (each one undo step). Cyan lines, drawn under selection chrome. Snapping:
      dragging a node snaps its edges/centers to guides + the owning artboard's
      edges/center (⌘ skips). View menu: Show/Hide Rulers (⌘R), Show/Hide Guides (⌘;),
      Lock Guides (⌥⌘;), Clear Guides. _Rulers/guides are document-scope only for now._
- [x] **Grid overlays** (Session 59) — two kinds. (1) Uniform square grid (Photoshop-
      style, global, session pref in AppState: `showGrid`/`gridSize`/`gridSubdivisions`)
      with minor + major lines aligned to the doc origin; settings in the no-selection
      Inspector; toggle ⌘'. (2) Per-artboard **layout grids** (`Artboard.layoutGrids`,
      persisted): columns / rows (count, gutter, margin) + baseline (spacing), each with
      color + visibility, edited in the artboard Inspector's "Layout Grids" section,
      drawn clipped to the board. **Snap to grid** (`snapToGrid`, toggle ⇧⌘') extends
      `snapNodeOffset` to the uniform grid's minor lines and layout column/row/baseline
      edges (⌘ still disables). Completes Phase 11.

### Phase 12 — Command coverage & menus (cross-cutting)
- [x] **Full menu bar** (Session 60) — File (+Export), Edit (Undo/Redo + Cut/Copy/
      Paste/Delete/Select All from system, + Duplicate ⌘D / Deselect All ⇧⌘A),
      **Object** (Group/Ungroup, Components, Convert to Path), **Type** (B/I/U,
      Convert to Outlines), **Arrange** (z-order + 6 align + 2 distribute), **View**
      (zoom, selection bounds, rulers/guides/grid/snap). Align/distribute also added to
      the right-click "Align & Distribute" submenu (2+). `selectAll(_:)`/
      `deselectAllAction(_:)` added + validated. Every action is reachable keyboard
      (where conventional) + menu + (contextual) right-click, gated by
      `validateMenuItem`. **This is now a standing convention — see CLAUDE.md
      "Command-coverage rule"; every new feature wires all surfaces in one change.**
- [ ] (ongoing) Re-audit for gaps as features land; add shortcuts/checkmark state for
      toggles (rulers/guides/grid/bounds) and align where conventional.

### Phase 13 — Workspace & dockable panels (Photoshop-style) — LARGE
_Panels are already state-driven, so this is layout/hosting work, not a UI
rewrite. Built in sub-phases._

**Architecture decision (Session 75) — two distinct WORKSPACE MODES, not one
hybrid.** `AppState.workspaceMode`:
- **Single Window (DEFAULT):** the compact editor. Panels are their OWN stacked,
  headed sections (NO combined tabs by default). Contextual: whole panels hide
  when not applicable to the current tool/selection (e.g. Components hidden until
  a component exists), and Properties sub-sections show only when relevant.
- **Multi-Window (later):** the Photoshop-style mode. Panels become **separate
  NSWindows** that can move to another monitor, with **tab grouping**. Panels
  stay VISIBLE here even when not applicable — just **de-emphasized** (lower
  priority look) — rather than disappearing.
- **Visual unity (hard requirement):** the single-window panel **heading bar**
  and the multi-window **tab bar** are the SAME component (`PanelTab` styling).
  Multi-window adds affordances on top: grab/drag markings, active-tab highlight.
  The tab/grouping code from 13a is KEPT (parked for multi-window), not rolled back.
- Mode switch lives in the top-right system line. Earlier "in-window floating
  first" note (Session 74) is superseded: real separate windows are the goal for
  multi-window mode.

- **13a — Dock foundation (model + render)** ✓ Session 74
  - [x] Data model: `PanelID` (layers/properties/color/components, + reserved
        slots), `PanelGroup` (tabs + active + collapsed), `DockColumn`,
        `Workspace(.default)`; `AppState.workspace` + mutation helpers.
  - [x] `DockColumnView` / `PanelGroupView`: **tabbed groups**, **collapse /
        expand** (Photoshop "minimize"), flexible height split, column-width
        resize (via the HSplitView). MainWindow renders both docks from the model.
  - [x] **Components panel** (live list of `model.sources`, opens source editor;
        auto-populates as components are created) + **Color** reserved placeholder.
- **13a.1 — Single-window polish** ✓ Session 75
  - [x] **Sane default widths** — docks start at 264 (left) / 300 (right) so panel
        content no longer starts clipped; owner needn't widen every launch. (True
        persistence of a custom width still comes in 13d.)
  - [x] **Collapse direction fixed** — new explicit-height model packs groups from
        the TOP; a collapsed group is exactly its header tall and the freed space
        goes to the EXPANDED groups, so headers stay put (no flinging to the bottom).
  - [x] **Animate collapse/expand** (easeInOut 0.2s; content stays mounted +
        clipped so it slides). Respects Reduce Motion → instant. (Resize drag is
        intentionally NOT animated — it tracks the cursor.)
  - [x] **Removed panels' internal header titles** in the dock (Layers/Inspector);
        the group heading is now the only title. Source-editor window keeps its own
        (showsTitle/showsZoom flags, default true).
  - [x] **Group resize** — draggable divider between two expanded groups (weights).
  - [x] **Default ungrouped** — `Workspace.default` is one panel per group (no
        combined tabs); tabs reserved for multi-window mode.
  - [x] **Reorder** (drag a panel heading to a new position) ✓ Session 77 —
        drag/drop on headings reorders within a column AND moves a panel across
        to the other column (insertion line + dragged section dims). Reuses the
        Layers-panel drop-delegate pattern (`AppState.moveGroup`).
- **13a.2 — Workspace mode scaffold** ✓ Session 75 (partial)
  - [x] `AppState.workspaceMode` (single / multiWindow) + top-right mode switch.
  - [x] Contextual **whole-panel** hide in single mode (`isApplicable`): Components
        hidden until a component exists; Color reserved/hidden. Multi mode shows all.
  - [ ] Wire the multi-window mode to actually do something (see 13c).
- **13b — Rearrange**
  - [ ] **Reorder** panel sections within a column (single-window) — drag the
        heading to a new slot.
  - [ ] Multi-window: drag a tab to reorder / move between groups / drop to make a
        new group (drop-zone highlights, grab markings, active highlight).
  - [x] **Panels menu** (show / hide Layers / Properties / Components, toggle
        left/right dock ⌘\ / ⌥⌘\, Reset Panel Layout) ✓ Session 77. (Used a
        dedicated "Panels" menu rather than the native Window menu — clearer for
        this app; canvas @objc actions + `AppState.togglePanel`/`resetWorkspace`.)
- **13c — Multi-window mode (separate NSWindows; the multi-monitor payoff):**
  _Owner's primary motivation: spread panels across a second monitor to see
  everything at once. Single-window stays DEFAULT; this is the other mode._
  - [x] Switching to Multi-Window **floats panels into separate NSWindows** ✓
        Session 78 — `PanelWindowManager` hosts each layout panel
        (`panelContent` + shared AppState + document; undo via window delegate),
        staggered placement; the main window hides its docks (canvas fills);
        windows close on switch-back or when the document window closes. Shared
        AppState = the floating Properties window tracks the main canvas selection
        live; edits undo on the document stack.
  - [ ] Live open/close when toggling a SINGLE panel in multi mode (currently the
        window set syncs on MODE switch only).
  - [ ] In multi-window, panels stay visible but **de-emphasized** when not
        applicable (instead of hiding). Tab grouping in floating windows.
  - [~] Window snapping + grouped move (Session 80) — SUPERSEDED by the tray model
        (Session 82). The separate-window snapping was choppy (syncing N windows
        every drag tick); replaced by combining panels into one **tray** window.
  - [x] **Tray model** ✓ Session 82 — a tray is ONE window holding a vertical
        stack of panels with a grab bar (drag the bar = move the whole unit,
        smooth + native). `AppState.trays` ([PanelTray], persisted) is the
        arrangement; `PanelWindowManager` maps trays → windows (open/close on
        change, frame recorded back on move). Full-screen/zoom button removed.
  - [x] **Merge / reorder / collapse / tear-out** ✓ Session 82 — drag a panel's
        **header** onto a tray to merge/reorder (horizontal insertion line);
        **click a header** to collapse/expand its body (Adobe-style); a header
        **pop-out button** tears the panel into its own tray. Cross-window via
        SwiftUI drag-and-drop; the dragged panel id is shared through
        `AppState.trayDraggingPanel`.
  - [ ] DEFERRED: (a) **side-by-side docking** within one tray (multi-column /
        vertical insertion line) — panels currently stack vertically only;
        (b) pure **drag-the-header-OUT** tear gesture (today tear-out is the
        pop-out button — drop-outside isn't catchable via SwiftUI DnD);
        (c) header-click collapse in the single-window dock (still uses the
        chevron there).
- **13d — Workspaces**
  - [x] **Persist** the layout between launches ✓ Session 79 — panel arrangement
        (order/column), collapse state, group weights, **column widths**, the
        **workspace mode**, and dock visibility are saved to UserDefaults
        (`exp.workspaceLayout.v1`) and restored on launch (multi-window re-floats
        its panels). It's a workspace preference, not document data.
  - [ ] Save / name / switch multiple **named** workspace presets (e.g. "Laptop",
        "Dual-monitor"); a picker in the mode/workspace control.
- **App settings / preferences** panel (owns toggles like selection-bounds; home
  for saved views). Tools strip stays pinned left; canvas fills freed space.
  → STARTED Session 123: a full-window Settings screen (sidebar + detail,
  `SettingsWindow.swift`) reachable via ⌘, exists and owns the app-wide DEFAULTS
  for smart-guides, selection-bounds, snap, and grid size/subdivisions, plus a
  restore-layout toggle and a Design-Tokens placeholder pane. Per-window View-menu
  toggles still override per session; the screen is built to scale (one enum case
  + one view per new options group).

### Phase 14 — Images (low priority)
- [ ] Place / embed **raster images** as an image node type; render + export.

### Phase 15 — Auto-layout / padding (BIG — later)
- [ ] **Content-driven padding + spacing** for a group: inter-element gaps + edge
      padding that **reflow** as content changes (the button pattern — text/icon
      group with a gap and T/B + L/R padding; editing "Button" → "Buy" shrinks the
      background, "Learn more about us" stretches it). Likely a layout-container
      node with rules.

### Phase 16 — Vector & masking power tools (BIG — later)
- [x] **convert type to shapes** (text → editable paths) — done in Session 53 (see
      Phase 9.5). `PathShape.contours` (multi-subpath, even-odd) is the foundation
      future boolean ops / masks can reuse.
- [ ] **Outline stroke** (expand stroke → fill path).

#### 16a — Shape mask (requested) — IMPLEMENTED Session 120
DONE: a mask is a `.group` flagged `isMask`; its children marked `isMaskShape`
form the clip (additive union of their silhouettes), the rest are masked content.
Reusing `.group` (instead of a new `NodeContent` case) means enter-to-edit,
drag-in, layers, copy/paste, instances all work unchanged. Model: `Node.isMask` +
`Node.isMaskShape` (Codable, default false). Render: `drawNodeContent` `.group`
case clips content to the mask union and draws the mask-shape outline (dashed
accent) while the mask/its descendants are selected; raster export mirrors it.
Create: "Mask with Top Shape" (Object menu ⌃⌘M + right-click + validate) wraps the
selection, topmost = mask shape; "Release Mask" reverts to a plain group. Editing:
double-click to enter, select/move/resize/point-edit the mask shape or content;
dragging a layer in via Layers adds it as content (reuses drag-into-group).
Rotated/flipped mask shapes clip correctly (Session 120 follow-up): each node's
own rotation/flip is baked into the clip path about its center and composed with
ancestor transforms, on canvas AND in raster export.
DEFERRALS (flagged): SVG export doesn't emit `<clipPath>` yet (raster/PDF do);
no Layers-panel badge marking which child is the mask shape (the on-canvas dashed
outline is the cue for now).

ORIGINAL PLAN (kept for reference):
- **Model**: a new `.mask` container `NodeContent` (or reuse `.group` + a
  `maskShapeID`): holds `maskChildren: [Node]` (the shape(s) acting as the mask,
  a group = merged/additive) + `content: [Node]` (the masked elements). Both
  editable; nothing is baked.
- **Render**: build the mask path from `maskChildren` (union of their silhouettes,
  even-odd/additive), `ctx.clip` to it, draw the content, restore. Mirrors how
  `nodeSilhouette` already builds shape paths.
- **Create**: select the top shape + the elements under it → "Mask with Top Shape"
  (Object menu + right-click) wraps them into a `.mask` node.
- **Edit like a component**: double-click to enter; the mask shapes + content are
  live-editable (move/resize/points), live on canvas — reuse the group enter/exit
  + the component inline-edit patterns.
- **Drag-in**: dragging a layer onto the mask node adds it to `content` — reuse the
  Layers drag-into-group machinery (`mutateNested` + drop delegate).
- Command coverage: action + Object/right-click + validate + Layers row affordance.

#### 16b — Pathfinder / boolean ops (FUTURE; requested)
- [ ] **Subtract / cut-out** first (the donut/`o` counter case), then unite /
      intersect / exclude. Operate on `PathShape.contours` with even-odd or a real
      CG boolean (`CGPath` flatten + combine). Output one editable path. Destructive
      by default (with undo); keep originals via a copy if needed.

#### 16c — Copy / paste styles (FUTURE; requested)
- [ ] **Copy Style / Paste Style** (⌥⌘C / ⌥⌘V) — carry fill, stroke, corner,
      opacity, blend, effects (and auto-padding background) from one layer to
      compatible targets. A small `Style` payload + apply-to-each-selected.

### Phase 16.5 — Background blur effect (requested; needs an offscreen render pass)
- [x] **Background blur** — a stackable `Effect.Kind.backgroundBlur` (reuses the
      effect list UI, amount = `blur`), blurring whatever is BEHIND the node within
      its silhouette. ARCHITECTURE NOTE: the live canvas draws straight to the
      window context, so there's no backdrop to sample. Real impl = render the
      artboard CONTENT into an **offscreen bitmap** each frame (so a blur node can
      `makeImage()` the accumulated backdrop, `CIGaussianBlur` it, clip to the
      silhouette, composite), then blit + draw chrome. Same offscreen technique in
      `ExportRenderer`. This is why it's a focused build, not a quick add — a
      half-done version that mishandles the flipped bitmap would corrupt the canvas.
- [ ] **FUTURE IMPROVEMENT — live (gesture-time) blur.** Today blur is deferred
      during pan/zoom and "catches up" on settle (see Session 119 log), because the
      CPU Core Graphics canvas can't do a full-scene readback + Core Image per frame
      at 60fps. To make it truly live: move the canvas (or at least the blur
      compositing) onto a GPU/layer-backed surface — `CALayer` backdrop filter /
      `NSVisualEffectView`, or a Metal `CIContext` drawing to a `CAMetalLayer` so
      the blur stays on-GPU with no CPU `makeImage` roundtrip. Big, own-phase job.
- [ ] **FUTURE — background blur in `ExportRenderer`** (canvas-only right now).

---

### Phase 17 — Design-system rollout (apply the finalized visual language)

The visual language is now **finalized and exported** to `design/EXP [design]
Design System/` — token files (`tokens/colors.css`, `typography.css`,
`spacing.css`, `glass.css`), a React UI-kit recreation of every chrome component,
guideline cards, the SF font files, and the dark three-pane "north star"
screenshot. It is the concrete implementation of `docs/VISUAL-HANDOFF.md`, every
value pinned. **The CSS/JSON is the source of truth for values; this phase ports
it into the SwiftUI chrome.**

**Why this is a phase, not a quick reskin.** The chrome today rides on raw system
semantics — `.primary` / `.secondary` / `Color.accentColor` / `.separatorColor`
and `.bar` / `.regularMaterial` (~87 scattered calls across `MainWindow`,
`ToolsStrip`, `LayersPanel`, `PanelDock`, `PanelWindow`, `SettingsWindow`). That
follows light/dark and the user accent for free, but carries **none** of the
brand's specifics: the `#181819` purple-tinted base + neutral ramp, the
opacity-tiered text hierarchy (100 / 62 / 42 / 28 %), the named surfaces, the two
core glass thicknesses + modal, SF Compact for layer names / dense labels, the
small-and-varied radii (4·5·6·7·8·12), and lime as identity-only spice. **There is
no central token layer in Swift.** Build that seam first; everything else hangs
off it (mirrors the "introduce shared state early" move from Phase 1).

**Decisions locked (this session):**
- **Materials = native Liquid Glass first.** Use the real macOS 26 Liquid Glass
  APIs for docked chrome (panels, inspector, tools rail, popovers). Fall back to
  `NSVisualEffectView` / SwiftUI `Material` **only** where glass sits directly on
  the hand-drawn Core Graphics canvas (rulers, notes overlay, on-canvas chrome) —
  no backdrop there to sample, per `VISUAL-HANDOFF.md`. Reduce-Transparency swaps
  to the opaque `--surface-*-solid` plates.
- **First pass scope = token foundation + core *docked* chrome only.** Tools
  strip, left dock, inspector, layer rows, section headers, fields/controls.
  Floating **trays**, the thick-glass **component-editor modal**, popovers, and
  canvas-overlay chrome are explicitly deferred to **17e+** (below).
- **Full light + dark parity at every step.** Build/tune in dark (the design
  home) but wire both token sets from the start and verify light per component —
  no light-mode debt against the "faithful mirror" commitment.

**Hard constraints carried in:** keep using Apple *semantic* behavior where it
already buys correctness (system accent tracking, the canvas-stays-its-own-thing
rule — `--canvas-*` tokens are isolated, change sparingly). Accessibility is a
gate, not polish: Reduce Transparency, Increase Contrast, Reduce Motion, full
keyboard + VoiceOver must all still hold after the reskin. Lowercase house copy /
UPPERCASE panel titles unchanged. Fonts: SF Pro / SF Compact are **system fonts**
on every target Mac — reference them natively, do **not** bundle the `design/.../
fonts/*.otf` (Apple license; they exist in the export only for the web kit).

#### 17a — Swift token layer (the seam) — DO FIRST
- [x] New `UI/DesignTokens.swift` (member of the app target; **add to the
      EXPThumbnail target too if any shared/rendered code references it** — see
      CLAUDE.md gotcha). Port the CSS verbatim:
  - [x] **Color** — `enum EXPColor` (or `Color`/`NSColor` extension) resolving the
        neutral ramp `n0...n900`, surfaces, row states, text tiers, accent set,
        semantics, hairlines/borders, and the isolated `canvas*` set. Each token is
        **appearance-resolving** via a dynamic `NSColor(name:dynamicProvider:)` so a
        single token serves light + dark (mirrors `.exp-dark` / light scopes). Dark
        values from `colors.css` `:root,.exp-dark`; light from the `@media`/`.exp-light`
        block. Opacity-tiered text via alpha, not new hues.
        - [ ] **App accent override (consider early — touches the token seam).**
          The `accent*` tokens must NOT hardcode `Color.accentColor`; route them
          through an app setting `accentOverride: NSColor?` (nil = follow the macOS
          system accent, the DEFAULT — like System Settings). When set, every
          `accent` / `accent-hover` / `accent-press` / `accent-subtle*` derives from
          the override (hover/press/subtle computed, not stored). Selection, active
          tool, focus rings, primary buttons, segmented-on all follow it for free
          because they read the token. UI lives in Settings (17i). Build the hook in
          17a so the reskin never bakes a raw accent in.
  - [x] **Type** — `EXPType`/`Font` roles matching `typography.css`: docName (15 light),
        panelTitle (13 regular, UPPERCASE +0.06em tracking), section (11 ultralight),
        artboard (12 medium), layer (12 light, **SF Compact**), label (12 light),
        numeric (12 regular, tabular). Helpers return `Font`/`NSFont` with the right
        family (SF Pro Text / Display / **Compact** / Mono) + weight.
  - [x] **Spacing / radii / stroke / layout** — constants from `spacing.css`
        (space 2–32, panel-pad-h 12, row-gap 6, section-gap 8/+4; radii drop4 field5
        row/card/tool6 control7 button8 panel12 pill; strokes hairline1 selection1.5
        dropline2 focus2; metrics dock 264/332, tools 44, ruler 20, control-h 24/30,
        hit-target 28).
  - [x] **Motion** — `ease-standard` / `ease-emphasis` curves + durations
        (fast120 / base180 / slow260); a `reduceMotion`-aware animation helper.
- [x] **Proof step:** restyle **one** control (a button) and **one** surface (a
      panel section header) onto tokens, in both appearances, and eyeball against
      the matching UI-kit card / north-star before mass adoption. (Cheap insurance
      the token resolution + SF Compact actually render as intended.)

#### 17b — Materials: the glass primitives
- [x] A reusable `glass(.thin|.medium|.thick)` surface modifier: native Liquid
      Glass + tint (`--glass-tint-*`), lit top rim (`--border-glass`), sheen, and
      the layered elevation shadows (`shadow-1/2/panel/popover/modal/drag` from
      `glass.css`). Reduce-Transparency → opaque `surface-*-solid`.
- [x] Map thicknesses to roles per the readme: **thin** = tools rail / toolbars,
      **medium** = the default dock panel, **thick** = modals (lands in 17f).
- [ ] Verify against `guidelines/glass-thicknesses.html` + `elevation.html`.

#### 17c — Core chrome reskin (first pass) — onto 17a/17b
- [x] **Tools strip** (`ToolsStrip.swift`, 44 wide, thin glass): tokenize the
      active/hover/idle states (`accent-subtle` active, `row-hover` hover), 15pt
      SF Symbols at token tint, tool radius 6. **Also re-orders the strip and adds
      three tools** (see below) — note the new tools are FUNCTIONAL work
      (`Tool` enum + behavior + full command-coverage), not just chrome, so they may
      be split out if the reskin should ship first.
  - [x] **New tool order / grouping** (`toolGroups`): `[pan, select, node]` ·
        `[rectangle, ellipse, polygon, line, pen]` · `[text, image, component]`.
        (Pen moves up into the shapes group; two spacers as shown.)
  - [ ] **DEFINITIVE SF Symbols (owner-supplied Session 142 — no guesswork):**
        pan `hand.point.up.left.fill` · select `pointer.arrow` · point-select
        `beziercurve` · rectangle `rectangle` · ellipse `circle` · polygon
        `triangleshape` · line `line.diagonal` · pen `point.topleft.down.to.point.bottomright.curvepath.fill`
        · text `character.textbox` · image `photo.fill` · component
        `square.on.square.squareshape.controlhandles`. The EXISTING tools' symbols
        are already updated in `Tool.symbolName` (Session 142); pan/image/component
        land when those tools are built.
  - [x] **(ADD) `pan` / hand tool** — a dedicated Adobe-style hand tool that ONLY
        pans the canvas (never selects/moves). Distinct from today's space-drag /
        trackpad pan (which stays). `Tool.pan`, SF `hand.raised` (filled when
        active), H shortcut (and hold-space still temporarily pans within any tool).
        Cursor = open/closed hand.
  - [x] **(ADD) `image` tool** — opens an `NSOpenPanel` (multi-select) to import
        image(s) onto the canvas. **Depends on Phase 14** (raster image node type +
        render + export), which isn't built yet — pull a minimal image node forward
        or gate this tool on it. SF `photo`.
  - [x] **(ADD) `component` tool** — creates an EMPTY `ComponentSource` and opens
        the source-editor window to author it from scratch / paste into it (the
        inverse of today's ⌘K which wraps a selection). SF `square.on.square` /
        component glyph. Reuses the Phase-4 source-editor window + scope.
  - [x] Command-coverage for each new tool (canvas @objc + menu + shortcut +
        validate + the strip button), per the standing rule.
- [~] **Left dock + panel headers** (`PanelDock.swift` / `PanelHub.swift`): medium
      glass plate, UPPERCASE panel-title role, section headers (11 ultralight),
      panel-pad-h 12, section-gap, panel radius 12.
  - [x] Headers→toolbar tint, tabs→UPPERCASE + accent-subtle, dividers/drop-line/
        component rows tokenized (Session 137). **DEFERRED (on-device visual step):**
        the dock COLUMN native-`expGlass(.medium)` + making the sidebar `List`
        transparent so the glass shows — these fight each other and need live
        iteration; column bg is the `surfaceWindow` token for now.
- [x] **Layer rows** (`LayersPanel.swift`): 28-tall rows, **SF Compact** layer
      name (12 light; active layer 12 medium), eye/lock at token tints, row
      hover/active/selected fills, drop-into radius 4 / dropline 2 accent. Match
      `components/structure/LayerRow.*` + `structure.card.html`.
- [x] **Inspector fields & controls** (`MainWindow.swift` right pane): numeric /
      text fields (radius 5, field surfaces + focus, inset hairline), section
      labels, segmented (align-to, paint kind), buttons. Match `components/inputs/*`
      + `controls/*`.
- [ ] **Window chrome**: window bg `surface-window` (`#181819` in dark), titlebar
      treatment, default 1500×950 / min 900×600 (already set — verify).
- [ ] **Lime, sparingly**: only the `[design]` wordmark mark + (later) a single
      live-status dot / focus glow. Never a fill or button. Blue owns interaction.

#### 17d — A11y + appearance verification (gate for the first pass)
- [ ] Toggle System Settings: light <-> dark, **Increase Contrast**, **Reduce
      Transparency** (glass → solid plates), **Reduce Motion** (curves → instant) —
      chrome stays correct and legible in all.
- [ ] Full keyboard path + VoiceOver labels intact on every restyled control.
- [ ] Contrast check text tiers on their surfaces (primary/secondary/tertiary on
      panel + field) to WCAG AA for body, both appearances.
- [ ] Side-by-side the running app vs. `ui_kits/exp-editor/index.html` and the
      north-star screenshot; log deltas.

#### 17e+ — Deferred to later passes (parked, not dropped)
- [ ] **17e — Floating trays** (`PanelWindow.swift` / tray model) onto the same
      glass + token system (de-emphasized-when-inapplicable look from Phase 13c).
- [ ] **17f — Thick-glass component-editor modal** (`SourceEditorWindow.swift`) —
      the "north star" floating editor; thick glass + `shadow-modal`.
- [x] **17g — Popovers / menus** (color popover, paint editor tokenized Session 148;
        split menus + popover containers use native macOS Liquid Glass chrome) onto
      `surface-popover` + `shadow-popover`.
- [ ] **17h — Canvas-overlay chrome** (rulers, guides labels, notes overlay,
      measurement lines): the **NSVisualEffectView/Material fallback** path — glass
      that can't use the native API because it sits on the CG canvas. Keep
      `--canvas-*` tokens isolated; this is the one place to be careful.
- [ ] **17i — Settings "Design Tokens" pane** (`SettingsWindow.swift` already has
      the placeholder) — surface the live token values for reference.

#### 17 — Owner design callouts (captured Session 133, from the redesign screenshots)
These refine the reskin specifics; fold each into the sub-phase noted.
- [x] **Layer-row order flipped (→ 17c).** The **lock toggle now sits on the RIGHT**
      edge of the row (was left). Row L→R: disclosure chevron · eye · type-glyph ·
      name (SF Compact) · …flex… · lock (right). Open padlock = unlocked, solid =
      locked; locked rows dim the name to `text-tertiary`.
- [x] **Active-layer treatment (→ 17c).** The selected layer row gets a **thicker
      accent border on its LEFT edge** (a ~1.5–2px accent bar) plus the
      `row-selected` fill — distinct from plain hover. One clear "this is active".
- [x] **Active-artboard treatment (→ 17c / canvas group header).** The active
      artboard's highlight is a **hairline accent line moved to the FARThest-left
      edge** of its layers group (a thin vertical accent rule), marking which board
      is active without a heavy fill. Inactive boards ("Non active artboard
      example") show no rule. NB this is the Layers-panel group header; keep it in
      sync with the on-canvas active-board cue.
- [ ] **Glass unity across ALL windows (→ 17b cross-cutting; gates 17e/17f).** The
      glass surfaces, tints, rim, sheen and elevation must read **identically**
      across single-window chrome, the multi-window floating trays, AND the
      source-component editor window — same `glass()` primitive + tokens everywhere,
      so moving between them never feels jarring. Don't let any window grow its own
      one-off material. Verify all three side-by-side as part of 17d.
- [x] **App accent override (→ 17a hook + 17i UI).** Settings "Design" option to
      override the app accent (default = follow macOS system accent, exactly like
      System Settings). See the 17a accent-override sub-bullet for the token wiring.

**Acceptance (whole phase):** zero raw chrome color/font literals left in the
restyled files (all via `DesignTokens`); the running app in dark reads as the
north-star screenshot; light is a faithful mirror; every macOS accessibility +
appearance setting honored; no regression in keyboard/VoiceOver. Update CLAUDE.md
"Current status" (it still says Phase 0) as part of closing this phase.

### Phase 4.5 — Shape styling + vector paths (pulled in before export)
- [x] Stroke color + width on rectangle/ellipse (model + render + Inspector;
      `strokeWidth == 0` = none; backward-compatible decoders so older files open)
- [x] Corner radius UI for rectangle
- [x] Fill color pickers for rectangle/ellipse (ColorPicker ⇄ RGBAColor)
- [x] **Pen tool** (P) — click = corner anchor, click-drag = symmetric bezier in
      one motion, click the first anchor = close; Return/Esc/tool-switch finishes;
      open path strokes, closed path fills. One undo step per path.
- [x] Editable **Path** node + point editing — the **Edit Points** tool (A,
      direct-selection) drags anchors (handles follow) and bezier handles;
      **Convert to Path** (right-click) for rect/ellipse/line.
- [x] Path stroke/fill + closed toggle in the Inspector
- [x] Pen adds a point to an existing shape/path (Pen over existing geometry shows
      a "+" cursor; converts basic shapes to a path first); right-click an anchor →
      Make Curved / Make Corner; selection draws the path outline (no square box);
      View ▸ Toggle Selection Bounds (⇧⌘B) hides the box for shapes too.
- [ ] (later) remove anchor points; line stroke in overrides; nested-source
      overrides; a real Settings panel to own the bounds toggle

### Future phase — more styling (post-v1)
_Folded into the Polish roadmap above: gradients/advanced picker → Phase 8,
font import → Phase 9, shadows → Phase 10._

### Later (post-v1, only once the above is solid)
- [ ] Whatever the cheap-bucket friction-fixers turn out to be in real use
- [ ] Reconsider any expensive subsystem only if daily use demands it

### Refinement backlog (small polish, revisit when convenient)
- [ ] **Nested-selection edge cases** — drilling into groups (Session 61) supports
      select / move / delete / inspector edits / point-editing for nested children, but
      two paths still assume top-level: resize/rotate **handles** are hidden for nested
      items (move-only), and inline **text editing** of a nested text node isn't
      positioned yet (double-click only drills/selects it). Revisit when needed.
- [ ] **Align/distribute on nested selections** — still operate on top-level
      `currentNodes` only (Session 62 made duplicate/copy/cut/paste/delete/order
      nested-aware; align would need absolute-frame math + recursive write-back).
- [ ] **Inspector "Align" row layout** — the Align-to dropdown sits too close to the
      distribute buttons; owner mis-clicked distribute when reaching for the dropdown.
      Separate/regroup them (and revisit overall panel layout) in the panels phase.
- [x] Layers-panel **Shift-click range** clunkiness + drag-reorder "dead spots"
      over the row text — RESOLVED in Session 17 by switching to native
      `List(selection:)` + native drag-reorder and moving Rename to the row's
      context menu (no custom tap gestures to fight the drag). Trade: row
      multi-select toggle is now ⌘-click (macOS-native) rather than Option;
      rename is right-click → Rename (no longer double-click). Say the word if
      you want Option-toggle / double-click rename back (would need the custom
      gesture layer again, or an AppKit NSOutlineView-backed list).
- [x] Layer-reorder keyboard shortcuts (Session 17): ⌘[ send backward, ⌘] bring
      forward, ⇧⌘[ send to back, ⇧⌘] bring to front — all wired (+ Bring Forward /
      Send Backward added to the context menu). Drag-reorder feel improved by the
      native-List switch the same session.
- [ ] Source-editor window: confirm horizontal pan parity with the main canvas;
      if two-finger horizontal scroll still doesn't pan there, investigate the
      NSHostingController scroll-event path (owner reported vertical-only feel).

---

## Accessibility & ethics commitments (non-negotiable, baked in from day 1)
- Full keyboard operability of the app's own UI
- Respect ALL macOS system accessibility & appearance settings: reduce motion,
  increase contrast, AND light/dark mode (via semantic colors — see Architecture)
- VoiceOver-sensible labels on app controls
- "Source" not "master"; inclusive language throughout
- The handoff/notes feature itself exists to fight thoughtless dev handoff —
  ethics as a feature, not an afterthought

---

## Progress Log
_Newest entry on top. Update every session._

- **2026-07-02 — Session 160 (website multi-monitor callout):**
  Added a new public-site feature callout for **Multi-window mode**, using the
  supplied multi-monitor mockup as a website asset
  (`website/public/assets/exp-multi-monitor-workspace.png`). The section sits
  between the product story and existing feature tabs, with copy focused on
  letting the canvas and panels spread across real monitor setups instead of
  replacing any current content. **Verified:** `npm run build` passes; Playwright
  desktop/mobile layout checks confirm the image loads at native size and there
  is no horizontal overflow.

- **2026-06-30 — Session 157 (In-app feedback reporter — FEAT-003):**
  Built `UI/Feedback.swift`: Help ▸ **Send Feedback** (⇧⌘/) opens a native sheet (dogfoods
  EXPSegmented Bug/Idea + `.exp` field + `.exp` buttons). Auto-captures PII-free CONTEXT
  (app+build version, macOS, current tool, selection counts, doc stats: artboards/nodes/
  components — via a recursive node count) and, on submit, opens a **prefilled GitHub New
  Issue** (labels + title + markdown body incl. context) when `FeedbackConfig.githubRepo` is
  set, else the website; ALWAYS copies the report to the clipboard as a fallback.
  • Wiring: `AppState.showingFeedback` flag · `@objc sendFeedbackAction` on CanvasNSView ·
  Help `CommandGroup(replacing: .help)` · `.sheet` in MainWindow. `validateMenuItem` default
  = enabled. Brace-balanced.
  • `FeedbackConfig.githubRepo` is nil for now (→ website); set it once the repo exists
  (BACKLOG INFRA-002). Added **INFRA-001** (one-command approve → ROADMAP → roadmap.json →
  website sync; needs the site's stack confirmed) to the backlog.

- **2026-07-01 — Session 159 (website email signup + field guide copy):**
  Wired the public website tester form to a simple Vercel Function at
  `api/signup.js`. The function validates email, includes a honeypot field,
  and sends a notification email through Resend's REST API using
  `RESEND_API_KEY`, `SIGNUP_TO_EMAIL`, and optional `SIGNUP_FROM_EMAIL` env vars
  (no database yet; honest first version). Updated the tester form UX with
  submit/success/error states and changed the Field Guide section to "coming
  soon" copy. `website/DEPLOYMENT.md` now documents the Resend/Vercel env setup.
  **Verified:** website build passes; API route validation handles invalid email,
  honeypot, and wrong method; Playwright smoke with mocked `/api/signup` confirms
  the form success state, coming-soon copy, no runtime errors, and no horizontal
  overflow.

- **2026-07-01 — Session 158 (website auto-sync + Vercel root deploy):**
  Wired the website to auto-sync from project memory. Added
  `website/scripts/sync-content.mjs`, which reads `docs/ROADMAP.md` +
  `docs/BACKLOG.md` and generates `website/src/generated/siteContent.json`
  before every `npm run dev` / `npm run build`. The React roadmap section now
  imports that generated content, showing synced roadmap cards, latest progress,
  and open backlog queue items. The generated JSON is ignored to avoid timestamp
  churn. Added root `vercel.json` so Vercel can deploy from the repo root while
  building `website/`, which avoids the subdirectory-root limitation where
  `website/` cannot read `../docs`. Added `website/DEPLOYMENT.md` with exact
  Vercel settings and daily workflow. **Verified:** `npm run build` passes;
  Playwright smoke confirms generated content appears, tabs still update, no
  runtime errors, and no horizontal overflow.

- **2026-07-01 — Session 157 (EXP website prototype):**
  Added a separate React + Vite `website/` package as a living public home for
  EXP [design], using the existing design-system tokens/assets and the current
  app screenshot. The site is a dark, Apple-adjacent scroll story with a glass
  nav, product hero, interactive feature tabs (native canvas / source components /
  structured notes), expandable field-guide rows, a roadmap section that is
  written around `docs/ROADMAP.md` as the future source of truth, and a tester
  interest/download placeholder. Captured the generated concept at
  `website/docs/exp-website-concept.png` and verification renders at
  `website/docs/render-desktop.png` + `website/docs/render-mobile.png`.
  **Web build passes** (`npm run build`), Playwright smoke verified no console
  errors, no horizontal overflow, tabs update, guide rows expand, and the tester
  field accepts input. Deferred: real Markdown ingestion from ROADMAP/BACKLOG,
  real signup/download wiring, and deployment/hosting decision.

- **2026-06-30 — Session 156 (v1 milestone + project infrastructure):**
  Phase 17 (design-system rollout) is effectively COMPLETE — marked a solid v1. Set up the
  process scaffolding for ongoing work + friend testing:
  • **docs/BACKLOG.md** — structured, agent-ingestible bug/feature/perf tracker (entry schema
  + "how agents use this"). Seeded: BUG-001 fractional-measurements-shown-as-whole (cause:
  `.fractionLength(0)` on every numeric field + `Int()` on canvas labels; model stores
  fractional), FEAT-001 color saved/recent/palettes (doc-linked + import/export), FEAT-002
  color-mode picker, FEAT-003 in-app bug reporter (agent-ingestible), PERF-001 large-file perf.
  • **docs/ARCHITECTURE.md** — one-read map (model → document/undo → AppState → canvas render
  pipeline → components → design system → command-coverage → two targets → export) + a
  "where do I put a new X?" table.
  • **.github/ISSUE_TEMPLATE/** — bug + feature YAML issue forms (fields mirror BACKLOG.md) +
  config, ready for a GitHub repo. Recommended distribution path: Apple Developer Program →
  TestFlight for friends + GitHub Issues for intake; in-app reporter (FEAT-003) pre-fills.

- **2026-06-30 — Session 155 (Controls compile confirmed + auto-contrast accent text):**
  • **Build:** the Session-154 controls now COMPILE (owner fixed the ButtonStyle access-level
  issue — `makeBody` returns `Body` explicitly and `Body` is `internal`, since a `private`
  result type on a non-private method is an error). The whole 17c control set (fields,
  segmented, buttons, icon toggles) builds.
  • **Auto-contrast accent foreground:** new `EXPColor.accentForeground` / `onColor(_:)` —
  computes WCAG relative luminance of the resolved accent and returns near-black on a LIGHT
  accent, white on a DARK one, so text on a solid accent fill stays legible for ANY accent
  override. Wired into `EXPButtonStyle` (primary) + `EXPSegmented` (selected segment).
  Threshold 0.6 (tunable). `accentOn` (raw white) kept for cases that always want white.

- **2026-06-30 — Session 154 (Inspector: EXPSegmented + EXPButton — controls complete):**
  New `UI/Controls.swift` with two design-system controls:
  • **`EXPSegmented<Value>`** — the accent-fill pill toggle (inset `surface-field` groove,
  selected segment = accent fill / on-accent medium text, idle = light `text-secondary`).
  Replaced ALL 5 native `.pickerStyle(.segmented)` in the inspector: auto-layout direction
  (icons), Gap/Space-Between, cross-align (Top/Center/Bottom), Align-to (Selection/Artboard),
  and text Auto-width/Text-box. Generic over the existing enum/Bool bindings — each keeps
  its own binding + tags.
  • **`EXPButtonStyle`** (`.exp(.primary/.secondary/.ghost)`) — accent primary / neutral-glass
  secondary / borderless ghost, radius 8, medium weight, press-shrink, hover in a nested Body
  view (ButtonStyle can't hold @State). Applied to the two real standalone buttons (Settings:
  Reset Workspace Layout, Reset to system accent). Inspector "Add …" actions stay native
  Menus by design.
  All brace-balanced. **17c inspector fields & controls: COMPLETE** (fields S149, section
  labels S146, icon toggles S153, segmented + buttons S154).

- **2026-06-30 — Session 153 (Inspector icon buttons → brand toggle):**
  New `InspectorIconButton` (accent-subtle active, soft hover wash, `radiusTool`, accent
  glyph / textSecondary idle) replaces the `.buttonStyle(.bordered)` + manual accent-fill in
  the three inspector helpers — `alignOpButton` (align/distribute), `alignButton` (text
  align), `styleButton` (B/I/U). One consistent brand toggle across the align row, the text
  controls, and distribute. Brace-balanced.
  REMAINING inspector controls (next piece): the 5 native `.pickerStyle(.segmented)` toggles
  (design wants a custom accent-fill `EXPSegmented` — a real component build, each Picker has
  its own binding/options) and a primary/secondary `EXPButton` for the Add/Reset actions.

- **2026-06-30 — Session 152 (Design tooltips on the tools rail):**
  Built `.expTooltip(label:shortcut:)` in GlassSurface.swift matching the design-system
  `Tooltip`: a translucent popover (surface-popover + lit rim + popover shadow) with the
  label and a monospaced KEYCAP badge for the shortcut, shown to the right of the trigger
  after a ~0.45s hover delay. Replaced the tool buttons' native `.help` with it (kept the
  accessibilityLabel for VoiceOver). Added `.zIndex(1)` to the tools strip so the bubble
  draws over the canvas.
  ⚠ RISK to verify on build: the bubble renders to the RIGHT of the rail, over the AppKit
  `CanvasView` (NSViewRepresentable), which can OCCLUDE SwiftUI overlays. The zIndex may or
  may not be enough. If it's hidden behind the canvas, the robust fix is a native tooltip
  (NSPopover / child NSWindow) — a bigger lift, flagged rather than done blind.

- **2026-06-30 — Session 151 (Fix: heading "Edited" flag never updated):**
  `WindowChrome` read `window.isDocumentEdited` via KVO, but that key isn't reliably
  KVO-observable — it caught the launch value and never updated, so "Edited" never showed.
  Added a `NSWindow.didUpdateNotification` observer (fires around edits/saves) that re-reads
  the window state; made `update(from:)` change-guarded so the chatty signal doesn't thrash
  @Observable; marked `WindowChrome` `@unchecked Sendable` so the @Sendable notification block
  compiles. Name/extension KVO (title/representedURL) unchanged. Brace-balanced.

- **2026-06-30 — Session 150 (Tool panel: pan / image / component + reorder):**
  Added the three new tools + the new groupings. Functional, brace-balanced; needs a build.
  • **Tool enum** (`AppState`): `.pan` / `.image` / `.component` with the owner's definitive
  SF Symbols, labels, shortcuts (pan=H; image=⇧⌘P; component=none).
  • **Groups** (`ToolsStrip`): `[pan, select, node]` · `[rectangle, ellipse, polygon, line,
  pen]` · `[text, image, component]`. Mode tools set `app.tool`; the two ACTION tools
  (image, component) fire their canvas action via the responder chain and leave the tool
  as-is. Tooltip omits the `()` when a tool has no shortcut.
  • **pan** = the hand tool: reuses the existing space-drag path (`dragMode = .hand` when
  `app.tool == .pan`); open/closed-hand cursor; H selects it. • **image** triggers the
  existing `placeImageAction` (image node type already existed). • **component** →
  new `newEmptyComponentAction` on `CanvasNSView`: makes an EMPTY `ComponentSource` +
  opens its source editor (vs. ⌘K which wraps a selection). Added to the Object menu;
  `validateMenuItem` default = enabled. `desiredCursor` gained the new cases.
  • DEFERRED (owner's "if capacity"): the CUSTOM styled tooltips w/ keycap shortcut badge —
  native `.help` still shows label+shortcut; the designed hover tooltip wants live iteration
  (hover timing/positioning) so it's a focused next step. Also opt-3 Figma drag-to-create
  artboard still pending.

- **2026-06-30 — Session 149 (Inspector field chrome — flat token TextField):**
  Checked the design-system `TextField.jsx`: the field is a CUSTOM flat control (surface-field
  fill, border-strong hairline, radius 5, 12pt, accent focus ring) — the "system metric" note
  only meant the radius. Built `EXPFieldStyle: TextFieldStyle` (in DesignTokens.swift) matching
  it and swapped **all 33** `.textFieldStyle(.roundedBorder)` → `.textFieldStyle(.exp)` across
  MainWindow (28), PaintEditor (2), PanelDock / LayersPanel / ColorPopover (1 each). Every
  inspector/zoom/rename/color field is now the flat brand field, uniform 24pt height.
  Brace-balanced. CAVEAT: focus shows via the text cursor, not yet the accent RING — the ring
  needs per-field @FocusState, a later enhancement. Segmented controls + inspector buttons
  still use system styling (next inspector polish if wanted).

- **2026-06-30 — Session 148 (17g — color popover + paint/gradient editor tokenized):**
  `Color/ColorPopover.swift` + `Color/PaintEditor.swift` (both app-target-only, so tokens are
  safe) onto DesignTokens: `.secondary` labels → token text; `.secondary`-opacity swatch/bar
  strokes → `borderSoft`; `Color.accentColor` (selected gradient stop) → `EXPColor.accent`;
  corner radii 4/5/6 → `radiusDrop`/`radiusField`/`radiusRow`. 19 swaps, brace-balanced.
  Popover CONTAINERS + split/preset menus keep the native macOS popover chrome (Liquid Glass
  on 26), so nothing to override there. 17g done.

- **2026-06-30 — Session 147 (Accent override UI — feature complete):**
  Added the accent-override control to Settings ▸ Design Tokens (the 17a token hook was
  already live). New "Accent" group in `DesignTokensSettingsPane`: a **Follow system accent**
  toggle (on by default) + a `ColorPicker` and "Reset to system accent" when overridden.
  Writes `AppPreferences.accentOverride` ("#RRGGBB"; ""=follow system) — the exact key
  `EXPColor.resolvedAccentNS()` reads, so selection / active tool / focus rings / primary
  buttons all track it. Color↔hex via `NSColor(Color)` + `EXPColor.hexColor`. Brace-balanced.
  NOTE: applies as windows redraw (next render), not instantly across open windows — a live
  push (bump an @Observable on the UserDefaults change) can be added if the delay is annoying.

- **2026-06-30 — Session 146 (Inspector token sweep — section headers + text colours):**
  Safe, mechanical tokenization of the Properties inspector (`MainWindow.swift`), no layout
  risk:
  • **18 section headers** (Type/Fill/Stroke/Align/Grid/Layout Grids/Effects/Overrides/…)
  `.font(.caption).foregroundStyle(.secondary)` → `.expSectionLabel()` — now UPPERCASE, 11pt
  ultralight, tracked, matching the LAYERS/PROPERTIES panel titles.
  • **42** remaining `.foregroundStyle(.secondary)` field labels + **2** `.tertiary` → token
  text tiers; **3** `Color.accentColor` → `EXPColor.accent` (now honour the accent override).
  Brace/paren-balanced. REMAINING inspector polish (deferred, higher-touch): the numeric/
  text FIELD chrome (`DimField` + 25 `.roundedBorder` → token field surface/radius/focus) and
  the `.callout`/`.caption2` FONT roles — left for a focused pass since they change metrics.

- **2026-06-30 — Session 145 (Heading polish: centered doc name + one-bar layout + New-Artboard opt 1):**
  Heading refined per owner feedback (glass heading from S144 confirmed working):
  • **Doc name** now shows in the heading again, CENTERED, via a `WindowChrome` @Observable
  that KVO-observes the NSWindow's `title` / `representedURL` / `isDocumentEdited` (streamed
  by an extended `WindowConfigurator` + a tiny `WindowTrackingView`). Name in primary; the
  **extension shown at 30% opacity**; **Edited** flag moved UNDERNEATH in the accent colour.
  • **One-bar feel:** all clusters TOP-aligned to the stoplight line — stoplights (left),
  New-Artboard (just right of them), centered name, system controls (right); heading height
  trimmed to 44 (tunable). Name layer is non-interactive so window-drag passes through.
  • **New-Artboard button = opt 1** (recommended: least disruptive — it was already in the
  heading; just repositioned left of the controls, now icon-only split button). opt 3 (Figma
  drag-to-create tool) noted as the better long-term UX, to bundle with the pan/image/
  component tool-additions phase.
  Brace/paren-balanced; needs a build. Watch: (1) confirm the doc name/extension/Edited read
  correctly from the window (KVO on those keys); (2) fine-tune heading height / top-padding
  so the three clusters sit exactly on the stoplight line.

- **2026-06-30 — Session 144 (Real fixes: floating-window + custom main-window glass heading):**
  Screenshot showed NOTHING rendering — diagnosed two real bugs:
  • **Floating windows:** content didn't extend under the titlebar (styleMask lacked
  `.fullSizeContentView`), so the glass + gradient started BELOW the stoplight bar →
  that strip was transparent. Added `.fullSizeContentView`; the behind-window glass +
  top gradient now reach the very top.
  • **Main window heading:** the grey bar was the native opaque `.toolbar` above the
  content — canvas never went under it, nothing to blur. **Restructured** MainWindow:
  removed the native toolbar; body is now `VStack { headingBar; HStack{tools|canvas|docks} }`.
  New `headingBar` = behind-window `WindowGlassBackground` + `expTopEdge`, hosting the
  New-Artboard menu + `TopSystemControls` (moved out of the toolbar), 72pt leading clear
  for the stoplights. New `WindowConfigurator` (NSViewRepresentable) sets the window
  transparent-titlebar + `.fullSizeContentView` + **isOpaque=false** so the heading's
  behind-window glass shows. Canvas fills opaquely (`underPageBackgroundColor`), so the
  desktop won't bleed through it.
  • Gradient also fixed to SOLID-top→clear (was dark-on-dark, invisible).
  Brace/paren-balanced; **needs a build + careful check.** Watch-items: (1) the New-
  Artboard menu + zoom/dock/mode controls now live in the heading; ⇧⌘N still bound.
  (2) Window is now non-opaque — if the tools rail or any chrome gap looks see-through
  to the desktop, give that surface an opaque backing. (3) Document title isn't shown in
  the heading yet (titleVisibility hidden) — can add it back if wanted.

- **2026-06-30 — Session 143 (Correction: gradient was invisible + main heading never glassed):**
  Owner couldn't see the gradient/glass. Two real mistakes from Session 142, now corrected/
  clarified:
  • **Gradient was invisible** — it used `surfaceToolbar` (dark translucent) over already-dark
  chrome. Fixed `TopEdgeGradient` to a SOLID `surfacePanelSolid` top fading to clear, so on
  the FLOATING (glass) windows the top now reads as a solid header melting into glass.
  • **Main window heading was mis-targeted** — Session 142 put `.expTopEdge()` on the
  `DockColumnView`s, which are OPAQUE (`surfaceWindow`), so a gradient there is ~invisible;
  and the main window's actual heading is the **native macOS titlebar + `.toolbar`** (no
  custom window config — confirmed by grep), which never got any custom glass. So the main
  window heading currently has only whatever system Liquid Glass the native toolbar provides.
  • TO MATCH the floating panels' glass heading, the main window needs `.windowStyle(
  .hiddenTitleBar)` + a CUSTOM heading bar (move the New-Artboard menu + `TopSystemControls`
  out of the native toolbar into a SwiftUI strip with `WindowGlassBackground` + `expTopEdge`).
  That's a focused structural change — flagged, not yet done (awaiting owner go-ahead).

- **2026-06-30 — Session 142 (Top-edge gradient on all windows + definitive tool symbols):**
  • **Top-edge gradient:** new `TopEdgeGradient` + `.expTopEdge()` in GlassSurface.swift —
  a subtle gradient that's more opaque at the very top, fading to clear, so a grab bar /
  panel top reads solid over glass (the floating grab bar was nearly transparent after
  the glass change). Applied to the floating **tray windows** and the docked **DockColumn**
  panels. NOT applied over the canvas (left untouched, by design). One-line height/tint
  knobs in `TopEdgeGradient`.
  • **Tool symbols (owner-supplied, definitive):** updated `Tool.symbolName` — select
  `pointer.arrow`, polygon `triangleshape`, pen `…curvepath.fill`, text `character.textbox`
  (node/rectangle/ellipse/line unchanged). Recorded the FULL list incl. the not-yet-built
  pan `hand.point.up.left.fill` / image `photo.fill` / component
  `square.on.square.squareshape.controlhandles` in the 17c tools section so there's no
  guesswork when those tools are added.
  Brace-balanced; needs a build.

- **2026-06-30 — Session 141 (Floating-panel glass: thinner-when-inactive, not darker):**
  Owner: the floating panels' glass looked great while active but **darkened when the
  window went inactive** (backwards) and read too thick. Root cause: the tray windows
  leaned on a system material that follows key-state (vibrant→muted on resign-key).
  • New `WindowGlassBackground(active:)` in GlassSurface.swift — real BEHIND-window blur
  (`NSVisualEffectView .sidebar`, `state = .active` so it NEVER auto-dims). Active vs
  inactive is expressed purely as a heavier-vs-lighter brand TINT, so inactive reads
  THINNER/lighter, never darker. Reduce-Transparency → opaque plate.
  • `PanelWindow.TrayWindowView` reads `\.controlActiveState`; `active = (state == .key)`
  so the glass thins the moment the panel isn't the focused window (matches the felt
  behaviour). Tray windows set `isOpaque = false` + clear bg so behind-window glass shows.
  Applies to ALL tray windows uniformly (consistent panel behaviour).
  • Made `LayersPanel` transparent (`.scrollContentBackground(.hidden)` + clear root) so
  the window glass actually shows THROUGH the panel body, not just the header — and in
  docked mode it simply shows the dock column's `surfaceWindow` (no regression).
  • Tint knobs are one line in `WindowGlassBackground` if it still reads heavy/light.
  Brace-balanced; needs a build. (Other panels — Components/Properties — get the same
  window glass + thinning; their content-transparency can follow if wanted.)

- **2026-06-30 — Session 140 (Quick token sweep: trays, source editor, notes, settings):**
  Low-risk colour/type token swaps across four more chrome surfaces (materials/glass
  for the canvas-overlay + tray windows are still the deferred 17e/17h pieces). All
  brace-balanced; needs a build.
  • **PanelWindow** (floating trays): tray bg → `surfaceWindow`; grab bar + section
  header `.bar` → `surfaceToolbar` (matches the dock headers — unified); insertion line
  → token accent + dropline width; grab glyph → textTertiary.
  • **SourceEditorWindow** (component editor, 17f): title → `expDocName`; backdrop-swatch
  stroke → accent/borderStrong + token widths; View label + subtitle → token type/colour.
  • **ArtboardNotesOverlay** (17h colours): notes toggle fill/stroke/foreground + the
  notes panel fill/stroke onto tokens (accentSubtle, surfaceRaised, hairline, radii).
  • **SettingsWindow** (17i): pane titles → `expDocName`; type-metrics diagram label →
  textSecondary, its plate → `surfaceField`.

- **2026-06-30 — Session 139 (Layers row engine rewrite: exact layout spec + click-to-select):**
  Per the owner's per-row spec + the selection bug, rebuilt the row engine in
  `LayersPanel.swift`. **Structural change — needs a build + click-test.**
  • **Dropped native `DisclosureGroup` + `List(selection:)`** (their built-in indent and
  click-handling were exactly what pushed the accent rule off the edge and blocked
  name clicks). `LayerOutlineRow` is now a manual `VStack` with a custom chevron and
  `depth`-based indent; selection is fully manual via a row tap → modifier-aware
  `selectNested` (handles plain / ⌘-toggle / ⇧-range for every row).
  • **Row layout = the spec, L→R:** [hairline artboard-rule slot — accent only when the
  section is active] · [xxs active-layer slot — accent only when selected] · depth
  indent · [chevron block: xxs · chevron · xxs, FIXED width so leaf rows align] · eye ·
  xxs · type glyph (now smaller) · xxs · name · flex · lock · space.sm. The two accent
  slots are element 1+2 of every row, pinned far-left regardless of depth; flush
  `VStack(spacing:0)` makes them read as one continuous line down the active group.
  • **Selection fixed:** single click ANYWHERE on the row selects (name only claims the
  count:2 gesture, so a single tap falls through to the row's select); double-click the
  name renames. Added a row-selected background fill + hover. Eye/lock stay `.fill`/11pt.
  • InstanceLayerRow gained `depth` + indent + matched icon sizes. Removed the now-dead
  `NestedTapSelect` + `selection` binding. Brace-balanced; init arg orders verified.
  • ⚠ Build-test watch-list: (1) if the rule still isn't flush far-left, the remaining
  culprit is `.listStyle(.sidebar)`'s leading gutter → switch that List to `.plain`;
  (2) confirm chevron expand/collapse, drag-reorder, and ⌘/⇧ multi-select still behave;
  (3) layers-panel Delete key may need focus now that native selection is gone (canvas
  Delete unaffected).

- **2026-06-30 — Session 138 (17c bug-fixes: layer-row icons + active-artboard rule):**
  Against the north-star screenshot, fixed four row bugs to lock the pattern:
  • **Icons → `.fill` variants** — eye `eye.fill`/`eye.slash.fill`, lock `lock.fill`/
  `lock.open.fill` (was outline; this also guarantees the hidden state shows a slashed
  eye, not a greyed open eye). • **Icon size** 12→**11** (eye + lock; they read too big).
  • InstanceLayerRow eye matched.
  • **Active-artboard rule** rebuilt: was a per-row leading overlay inside an 8pt row
  inset, so it sat indented and broke between rows. Now ONE continuous line drawn once
  per top-level row spanning the whole group (incl. expanded children); rows are
  full-bleed (`listRowInsets` leading/trailing = 0) with the gutters moved into the row
  content, so the rule sits at the panel's far-left and never jogs/gaps. Nested rows
  skip it (ancestor draws it). Refactored `LayerOutlineRow.body` → `content` + a body
  overlay. Selected-row thick bar unchanged.
  • ⚠ CAVEAT to check on build: `.listStyle(.sidebar)` may still reserve a small leading
  gutter for disclosure chevrons; if the rule isn't perfectly flush-left, the next lever
  is `.listStyle(.plain)` (changes section-header look) or a small negative leading
  offset. Brace-balanced.

- **2026-06-30 — Session 137 (Phase 17c — core chrome reskin, left side):**
  Reskinned the editor's left side onto DesignTokens + `expGlass`. Self-contained,
  brace-balanced; **needs a build + look** (and the native `.glassEffect` confirm from
  17b applies to the tools rail).
  • **ToolsStrip** — thin liquid-glass rail (`expGlass(.thin)`), tokenized active/
  hover/idle (accent-subtle / rowHover, accent / textSecondary), 15pt glyphs, tool
  radius 6, medium (not semibold) active weight. (Tool reorder + new pan/image/
  component tools still pending — functional work.)
  • **LayersPanel** — the Session-133 callouts: **lock moved to the RIGHT** edge;
  selected row gets a **thick (3pt) accent bar** on the left; the active-artboard rule
  is tokenized (1.5pt accent, far-left); names render in **SF Compact** (medium when
  active), locked rows dim to text-tertiary; eye/type/drop-line/drop-into all token.
  InstanceLayerRow tokenized to match.
  • **PanelDock** — header strip → `surfaceToolbar` tint; tabs → UPPERCASE titles +
  accent-subtle active state; chevron/divider/drop-line/Components empty-state +
  ComponentRow tokenized. **Deferred (flagged):** the dock COLUMN native glass + a
  transparent sidebar `List` — they conflict and need live iteration; column is the
  `surfaceWindow` token for now.
  • Remaining 17c: **Inspector fields/controls** (`MainWindow.swift`, ~2400 lines — the
  next big chunk), **window chrome**, and the lime `[design]` mark. Checkpointing here
  so the left-side reskin can be built/verified before the inspector pass.

- **2026-06-30 — Session 136 (Phase 17b — the `expGlass` surface primitive):**
  Built `UI/GlassSurface.swift` — the one liquid-glass modifier the whole reskin
  composes, so panels/trays/popovers/modals share ONE material (the unified-glass
  callout). `.expGlass(_ thickness:style:cornerRadius:tint:interactive:)` with:
  • **.liquid** backend = native macOS-26 **Liquid Glass** (`.glassEffect(.regular
  .tint(…).interactive(…), in:)`) — DEFAULT for docked chrome (deploy target is 26.2,
  so no availability guard). • **.material** backend = `NSVisualEffectView` (real
  backdrop blur, `.withinWindow`) for canvas-overlay glass (wired in 17h). • **Reduce
  Transparency** → opaque token plate, no blur, automatically.
  • Per-thickness tint (`EXPGlass.tint`), a fading lit top **rim** (brighter under
  Increase Contrast), a top-down **sheen** (stronger in light, per glass.css), and
  **elevation** shadow (thin/medium/thick → soft/panel/modal, softened in light).
  • Convenience roles `expToolbarGlass` / `expPanelGlass` / `expPopoverGlass` /
  `expModalGlass` map the readme's thickness→surface table. DEBUG `#Preview`s show all
  three thicknesses over a busy gradient in light + dark.
  • 17b adds ONLY the primitive; ToolsStrip/PanelDock/PanelWindow stay on `.background
  (.bar)` until 17c rewires them. Brace/paren-balanced; token refs resolve. **Needs a
  build** — the one thing to confirm is the native `.glassEffect`/`Glass` API spelling
  (best recall of the 26 SDK; isolated to the `.liquid` branch if it needs a tweak).
  Next: **17c** — reskin the core docked chrome onto tokens + `expGlass`.

- **2026-06-30 — Session 135 (Font bundling — SF Compact for cross-Mac consistency):**
  Bundled the condensed voice so layer names look identical on every Mac. Decided
  (owner): bundle **SF Compact only** (SF Pro / SF Mono are the universal system
  fonts — referenced via `.system`, NOT bundled); owner **may distribute later**, so
  the embed is kept clean + flagged.
  • Copied 5 weights — **SF Compact Display** Ultralight/Light/Regular/Medium/Semibold
  (~31MB) — into `EXP [design]/Resources/Fonts/`. Synchronized-folder default makes
  them **app-target only** (EXPThumbnail only re-includes the listed shared files), so
  the extension isn't bloated.
  • `UI/FontRegistration.swift` — `EXPFonts.registerBundledFonts()` registers them
  PROCESS-scoped via CTFontManager, idempotent, looked up by name (resilient to how the
  build flattens resources). Called from `EXP__design_App.init()` before any view
  renders, so `EXPType.hasSFCompact()` sees the family on first use.
  • `EXPType.layerFont` is the single switch-point; updated its notes (no longer
  'verify availability' — it's bundled). Added `Resources/Fonts/LICENSE-NOTE.md`:
  Apple's SF license restricts redistribution, so **before public distribution** either
  confirm a license path or swap to an SIL-OFL condensed face (one-function change).
  • SF Pro / SF Mono intentionally NOT bundled (universal + cleaner license). Brace-
  balanced; **needs an Xcode build** — confirm layer names render condensed and the
  Light/Medium weights select. Phase 17a + font bundling COMPLETE → next is 17b
  (the `glass()` surface modifier).

- **2026-06-30 — Session 134 (Phase 17a — DesignTokens.swift, the seam):**
  Built the Swift token layer that the whole reskin hangs off — `UI/DesignTokens.swift`
  (334 lines, chrome-only → app target; the synchronized-folder project auto-includes
  it, and it stays OUT of EXPThumbnail since nothing shared references it). Ported the
  CSS verbatim:
  • **`EXPColor`** — neutral ramp n0–n900, surfaces, row states, opacity-tiered text
  (100/62/42/28), borders, semantics, brand, and the isolated `EXPColor.Canvas` set.
  Each token is an **appearance-resolving** dynamic NSColor (light/dark in one token,
  the Swift analogue of `.exp-dark`/light); SwiftUI reads `Color`, AppKit reads the
  `…NS` variants. Sendable-safe (only CGFloat tuples cross into the @Sendable provider).
  • **Accent override hook** — `resolvedAccentNS()` returns the app override if set,
  else `controlAccentColor` (default = follow macOS, like System Settings). Added the
  `AppPreferences.accentOverride` key ("#RRGGBB"; absent = system). hover/press derived,
  subtle = accent @ fixed low alpha. Settings UI comes in 17i.
  • **`EXPType`/`Font`** roles incl. **SF Compact** layer font with a runtime
  availability check + system fallback; `expPanelTitle`/`expSectionLabel` View modifiers
  carry UPPERCASE + tracking. **`EXPMetric`** (spacing/radii/stroke/layout) and
  **`EXPMotion`** (curves/durations, reduce-motion aware). **`EXPGlass`** token VALUES
  parked for 17b (tints/blur/saturate/shadows).
  • **Proof:** `UI/DesignTokensProof.swift` (DEBUG-only, wired nowhere) — a button,
  panel/section headers, text tiers, SF-Compact layer rows w/ active-layer accent bar,
  segmented + switch, with light & dark `#Preview`s.
  Brace/paren-balanced; all cross-refs resolve. **Needs an Xcode build + a look at the
  two previews** — verify (1) SF Compact actually renders condensed on the owner's Mac,
  (2) the accent token tracks the system accent. Next: 17b (the `glass()` modifier).

- **2026-06-29 — Session 133 (Plan: Phase 17 — design-system rollout):**
  The owner added the finalized design-system export under `design/EXP [design]
  Design System/` (token CSS + JSON, a React UI-kit recreation of every chrome
  component, guideline cards, SF fonts, and the dark three-pane "north star"
  screenshot — the concrete build of `docs/VISUAL-HANDOFF.md`). Surveyed it against
  the live app: chrome rides on raw system semantics (~87 `.primary`/`.secondary`/
  `Color.accentColor`/`.separatorColor`/`.bar` calls across `MainWindow`,
  `ToolsStrip`, `LayersPanel`, `PanelDock`, `PanelWindow`, `SettingsWindow`) with
  **no central token layer in Swift**, so it carries none of the brand specifics
  (#181819 purple base, opacity-tiered text, named surfaces, glass thicknesses, SF
  Compact, the 4·5·6·7·8·12 radii, lime-as-spice).
  • Wrote **Phase 17** above. Owner decisions: native macOS 26 **Liquid Glass
  first** (NSVisualEffectView fallback only for canvas-overlay glass); first pass =
  **token foundation + core docked chrome** (tools strip, left dock, inspector,
  layer rows, headers, fields), with trays/modal/popovers/canvas-overlay deferred to
  17e+; **full light+dark parity every step**. Sub-phases 17a (DesignTokens.swift —
  the seam, do first) → 17b (glass primitives) → 17c (reskin) → 17d (a11y/appearance
  gate). No code yet — next session starts at 17a.

  • **Owner refinements (same session):** added an **app accent override**
  (Settings "Design" option, default = follow macOS accent) — wired as a token-seam
  hook in 17a so the reskin never bakes a raw accent. Captured four redesign
  callouts in a new "17 — Owner design callouts" block: layer-row **lock moved to
  the right**; **active-layer** thick left accent bar; **active-artboard** hairline
  accent rule on the far-left edge; and **glass unity** across single/multi-window +
  source-editor windows. Expanded the 17c tools strip: new order `[pan, select,
  node]·[rectangle, ellipse, polygon, line, pen]·[text, image, component]` plus three
  NEW tools — **pan/hand**, **image** (NSOpenPanel import; depends on Phase 14 image
  node), **component** (creates an empty source + opens the editor). Those three are
  functional work, not just reskin. Still no code — work begins next session.

- **2026-06-28 — Session 132 (Fix: handles + inspector W/H for a multi-selection inside a group):**
  The selection-transform subsystem (canvas) and the inspector's multi-selection
  dimensions were both **top-level-only**, so selecting several nested layers showed
  no resize/rotate box and 0×0 in the inspector.
  • Generalized both to nested nodes by lifting each selected node's frame into
  DOCUMENT space (folding in `nodeOffset`), running the existing `SelectionTransform`
  math, then converting the result back to parent-local on write. Valid whenever the
  ancestor chain is unrotated — the same restriction the single-node handles already
  use; rotated-ancestor selections stay move-only.
  • Canvas: `selectionTopLevelIDs/Nodes` → `selectionTransformIDs` +
  `selectionTransformNodesDoc`; baseline now snapshots doc-space + a per-id offset map;
  resize/rotate apply subtracts the offset before `updateNode`. New `hasSelectedAncestor`
  excludes a node whose group is also selected (prevents double-transform).
  • Inspector (`MainWindow`): `multiSelectionBounds` now unions doc-space nested nodes;
  the multi X/Y/W/H move + scale commits recurse via `mutateNestedNode` with the same
  doc↔local conversion. Added scope-aware `scopedNodeOffset` / `scopedAncestorRotation`
  / `scopedIsTopLevel` / `scopedOffset(of:in:)` helpers.
  Touched: `Canvas/CanvasView.swift`, `UI/MainWindow.swift`. Single nested-node
  selection already worked (single-node handle path) and is unchanged. Needs a
  build + on-device check.

- **2026-06-28 — Session 131 (Fix: multi-select inside a group in the Layers panel):**
  Nested DisclosureGroup rows are hand-rolled (they don't participate in
  `List(selection:)`), so they went through `NestedTapSelect`, which *always*
  replaced the selection — you couldn't ⌘/⇧-click to multi-select within a group.
  • New `selectNested(_:)` reads `NSEvent.modifierFlags`: **⌘ toggles** the row,
  **⇧ range-selects** from `AppState.selectionAnchorID` across a new
  `visibleSelectableIDs` flat order (respects collapsed sections + expanded groups),
  plain click replaces. Plumbed down as `onNestedSelect` through `LayerOutlineRow`.
  • Repurposed the previously write-only `selectionAnchorID` as the range anchor.
  KNOWN MINOR GAP: native top-level List clicks don't set the anchor, so a
  top-level→nested ⇧-range can use a stale anchor; within-group selection (the
  reported bug) works. Touched: `UI/LayersPanel.swift`. Needs a build + on-device check.

- **2026-06-28 — Session 130 (Copy / Paste Layer Style):**
  Added a "layer style" copy/paste — carries a layer's **effects + blend mode +
  opacity** (appearance only; geometry, fill, and content are untouched) onto one
  or many other layers.
  • Model: new `LayerStyle` struct + `Node.layerStyle` / `Node.applyLayerStyle(_:)`
  in `Document.swift` (shared-target-safe; pasted effects get fresh ids). The copied
  style lives on `AppState.copiedLayerStyle` (session-only, shared by canvas + panel).
  • Full command coverage: `@objc copyLayerStyle:` / `pasteLayerStyle:` on
  `CanvasNSView` (single source of truth, one undo step via `commitNodes`); Edit-menu
  **Copy Style ⇧⌘C / Paste Style ⇧⌘V**; canvas right-click items; Layers-panel
  right-click items (reimplemented locally like Delete so they work regardless of
  focus); `validateMenuItem` cases (Paste Style disabled until a style is copied).
  Works in both document and component-source scope.
  Touched: `Model/Document.swift`, `Model/AppState.swift`, `Canvas/CanvasView.swift`,
  `UI/LayersPanel.swift`, `EXP__design_App.swift`. No Inspector control added —
  copy/paste has no adjustable parameters (the rule's condition), but an Effects-panel
  affordance is an easy optional follow-up. Needs a build + on-device check.

- **2026-06-27 — Session 129 (Component bounds = resizable SVG-style viewBox):**
  Pivoted the component source bounds from the auto-hug box (Session 128) to a
  stable, user-resizable viewBox — "its own little artboard."
  • `ComponentSource` gained a viewBox `origin` (+ `bounds`), backward-compatible
  Codable (old size-only files decode origin = .zero). Box no longer auto-hugs:
  `commitNodes` stops rewriting `size`, and the editor draws `source.bounds` (stable)
  so elements can be moved/centered within it.
  • **Resize handles** on the source box (8-handle, ⇧ = proportional), reusing the
  artboard machinery: new `hitTestSourceHandle`, `DragMode.resizeSource`,
  mouseDown/Dragged/Up + cursor wiring; edits `source.origin/size` in one undo step.
  • **Instances render the viewBox** (SVG semantics): `resolvedChildren` positions
  content relative to `source.origin`, `resolvedSize` returns the viewBox size, and
  the instance draw path clips to the box so out-of-bounds content is cropped in
  placements (the source editor itself draws unclipped for editing). Freshly created
  components are unchanged visually (viewBox == content at creation).
  Touched: `Model/Document.swift`, `Canvas/CanvasView.swift`. KNOWN TRADE-OFF: a
  fixed viewBox no longer auto-grows an auto-layout button when an instance's label
  override gets longer — revisit with an optional per-source "hug contents" toggle if
  needed. Needs a build + on-device check.

- **2026-06-27 — Session 128 (Source bounds hug content + nested instance layers):**
  • **Source-editor bounds box now hugs the live content.** It was drawn at a fixed
  origin with the stale stored `size`, so it could sit off-centre and never followed
  the elements. New `sourceContentRect()` (union of the source's children) drives the
  drawn page, the initial fit/centering, and the ⌥-spacing measures; `commitNodes`
  keeps `ComponentSource.size` in sync so the Components panel stays honest. Moving
  elements now moves the box with them; ⌘1 (Zoom to Fit) re-centres.
  • **Instance layer list expands nested groups.** A component made from a group only
  showed the group as one row, so you couldn't toggle the layers inside it per
  instance. `InstanceLayerRow` is now recursive (disclosure per nested group), and
  `toggleInstanceLayer` resolves a nested layer's source default via a tree search
  (`nodeInTree`). The model + renderer already supported nested per-instance
  visibility (`applyingOverrides` recurses) — this was the missing UI.
  Touched: `Canvas/CanvasView.swift`, `UI/LayersPanel.swift`. (Document.swift
  untouched — no EXPThumbnail target risk.) Needs a build + on-device check.

- **2026-06-27 — Session 127 (Component naming + name sync):**
  • **Create Component names itself after the selection.** When exactly one (named)
  layer is selected — typically a group the user just named — `createComponent` uses
  that name for the source + instance instead of "Component N" (multi-shape
  selections still get the auto number).
  • **Component name is now one source of truth.** A component instance displays its
  SOURCE name everywhere — Layers panel (`displayName`), Inspector
  (`nodeNameBinding`), and the Components panel all read `ComponentSource.name`.
  Renaming an instance from the Layers panel or Inspector edits the source (one undo
  step, "Rename Component"), so all three panels stay in lockstep. Sets up treating
  instance rows specially in the Layers panel later (e.g. optional per-instance name
  overrides that fall back to the component name).
  Touched: `Canvas/CanvasView.swift`, `UI/LayersPanel.swift`, `UI/MainWindow.swift`.
  Needs a build + on-device check.

- **2026-06-27 — Session 126 (Source-window backdrop view setting):**
  Added a Photoshop-style canvas-shade control to the component source editor so
  white (or black) artwork stays visible while editing. New `AppState.CanvasBackdrop`
  enum (Light / Grey / Dark, grayscale `white` value + SwiftUI `color`), persisted
  via `AppPreferences.sourceBackdrop` (seeded in `applyAppPreferenceDefaults`, live-
  synced in `reloadSyncedPrefs`). The source canvas shades the component "page"
  (`drawSourceBounds`) with the chosen value — NOT the surrounding pasteboard, which
  stays the neutral system shade so the bounds still read as a page — with a
  luminance-aware hairline. The control is a labelled "View" swatch row (radio-style)
  in the source-window header; it's explicitly view-only and never touches the
  element's own background. Canvas redraw tracks it via a new read in `updateNSView`.
  Touched: `Model/AppState.swift`, `UI/SettingsWindow.swift`, `Canvas/CanvasView.swift`,
  `UI/SourceEditorWindow.swift`. Needs a build + on-device check.

- **2026-06-27 — Session 125 (Lock/unlock commands, Layers-panel delete, source-window fix):**
  Three testing-feedback fixes.
  • **Lock / Unlock with full command coverage.** New `lockSelection:` /
  `unlockSelection:` `@objc` actions on `CanvasNSView` (`setLockOnSelection`,
  recurses into groups, one undo step, multi-selection). Wired the conventional
  five ways: Object-menu items with **⌘L** (lock) / **⇧⌘L** (unlock), a contextual
  right-click pair (shows Lock when anything's unlocked, Unlock when locked via the
  new `anySelected(_:)` helper), `validateMenuItem` cases, and an Inspector lock
  toggle in the Layer header (`toggleLockSelected`, scoped so it works in the
  source-editor window too). The per-row toggle in the Layers panel already existed.
  • **Delete from the Layers panel.** Previously delete only worked when shapes were
  selected on the canvas — the panel's List swallowed the key. Added
  `.onDeleteCommand` (Delete key) plus a destructive **Delete** in each row's
  right-click menu; both route to a new `deleteLayers(_:)` (recursive `removeIDs`,
  reflow, one undo step). Right-clicking a row that isn't in the selection deletes
  just that row (`selectionOrRow`); otherwise the whole selection.
  • **Source-editor window layering.** The component editor's middle canvas
  overdrew the header and left panel (it sat under the right panel only). Cause: the
  AppKit canvas lived in a plain `HStack`, which doesn't clip the representable's
  NSView. Restructured `SourceEditorView` to mirror the main window — `ToolsStrip`
  pinned outside an `HSplitView { Layers · Canvas · Inspector }`; split panes clip
  their contents, so the canvas stays in its pane (and the panes are now resizable).
  Touched: `Canvas/CanvasView.swift`, `EXP__design_App.swift`, `UI/MainWindow.swift`,
  `UI/LayersPanel.swift`, `UI/SourceEditorWindow.swift`. Needs a build + on-device
  check (compiled by the Xcode agent / owner).

- **2026-06-26 — Session 124 (Canvas performance: many layers/artboards):**
  Diagnosed lag on a large stress file (`allsortsofthings.design`). Root causes:
  the canvas redrew the ENTIRE scene every frame (pan/zoom included) with (1) no
  viewport culling — every node + artboard drawn regardless of being off-screen;
  (2) `owningArtboard(of:)` called per node = O(nodes × artboards) per frame; and
  (3) component instances re-resolved (`resolvedChildren` → override apply +
  `AutoLayoutEngine.reflowed`) on every single draw, uncached.
  Fixes (3 changes, behaviour-preserving):
  • **Viewport culling** in `renderCanvas` — artboards and leaf nodes whose
  (margin-expanded) view rect doesn't intersect `bounds` are skipped; owned nodes
  are additionally culled when their artboard is off-screen (exact, since they're
  clip-bound to it). Culled leaves also skip the `owningArtboard` scan, cutting the
  quadratic loop down to on-screen + container nodes. New helpers `isLeafContent`,
  `nodeCullMargin` (covers stroke/shadow/rotation reach), `strokeReach`.
  • **Cross-redraw instance cache** — `ExpDocument` gained `resolveGeneration`
  (bumped in `model`'s `didSet`, so it catches in-place drag mutations too). The
  canvas caches `resolvedChildren` by the top-level instance node's id, valid for
  one generation. Pan/zoom don't touch the model, so the cache survives them; any
  edit invalidates it. Nested instances (shared source-layer ids) fall through
  uncached to avoid key collisions.
  • **`AutoLayoutEngine.reflowed` fast path** — returns the input unchanged when no
  node in the tree carries auto-layout/auto-padding (the common case), avoiding a
  full tree rebuild on every commit/resolve.
  Touched: `Canvas/CanvasView.swift`, `Model/ExpDocument.swift`,
  `Model/AutoLayoutEngine.swift`. Needs a build + on-device check against the
  stress file; watch for any leaf wrongly culled at extreme zoom (margin math).
  • **Follow-up — smart-guide cost during wall drags:** `snapNodeOffset` rebuilt
  alignment candidates from EVERY node in the document on each mouse-move
  (`collectCandidates(currentNodes)`), so dragging on the wall with many items
  stalled while snapping against far-distant elements. Now element smart guides only
  run when the dragged selection is over an artboard, and candidates are limited to
  nodes intersecting that board. Loose-on-the-wall drags get no element guides (ruler
  guides + uniform grid still apply). Artboard-edge / grid snapping unchanged.
  • **Testing Mode (perf instrumentation):** added `AppState.testingMode` (session
  state, OFF by default, not persisted) and **View ▸ Testing Mode (⌃⌘T)** with a
  checkmark via `validateMenuItem`. When on, a tiny `PerfMeter` (appended to
  `CanvasView.swift`, no new project file) logs ONE console line ~2×/sec: frame
  time, snap time, nodes total→drawn, boards drawn, instance-cache hit/miss, snap
  candidate count. Hot loops are guarded on `perf.enabled`, so it's near-zero cost
  when off. Use it to find what's still stalling before committing to the bigger
  dirty-rect / layer-backed redraw rewrite. Touched: `Model/AppState.swift`,
  `Canvas/CanvasView.swift`, `EXP__design_App.swift`.

- **2026-06-26 — Session 125 (Disable background blur + log triage):**
  Perf logs from two stress docs showed the real hog: **background blur**. Any node
  with a background-blur effect forces `draw()` down the offscreen path — render the
  WHOLE scene into a bitmap, `makeImage()` it, run a Core Image gaussian per blur
  node — EVERY frame. Result: 30–50ms frames with only ~50 nodes drawn, escalating
  to 3,000–23,000ms frames and `Surface 16000–19000 px too large` failures at high
  zoom. **Disabled background blur** behind `CanvasNSView.backgroundBlurEnabled =
  false`: `documentHasBackgroundBlur` now returns false (so the offscreen pass never
  runs) and the per-node blur block (incl. its `makeImage()`) is gated off. Drop /
  inner shadows unchanged. Removed "Background Blur" from the effects ▸ add menu and
  the kind picker (`UI/MainWindow.swift`); a blur effect saved in an old file just
  doesn't render. To revisit: flip the one flag back on after reworking the blur to
  a clipped, region-only pass (no full-scene readback). Touched:
  `Canvas/CanvasView.swift`, `UI/MainWindow.swift`.
  Still open from the same log (NOT yet fixed): ~90× "Publishing changes from within
  view updates is not allowed" — a SwiftUI feedback loop (an @Observable mutated
  during a view update) that can trigger extra redraws; needs a runtime repro to
  pinpoint. The DetachedSignatures / networkd / ViewBridge / file-provider
  "hasn't been synced" lines are benign macOS sandbox + Dropbox/iCloud noise, not
  app bugs. Re-measure frame times now that blur is gone before deciding whether the
  dirty-rect / layer-backed redraw rewrite is still needed.

- **2026-06-26 — Session 126 (Fix launch hang: shadow convolution blowup):**
  After the blur disable the app "wouldn't run" — really it HUNG on the first frame
  reopening a doc saved at high zoom (~25×), then got SIGTERM'd. Debugger was parked
  in a gaussian convolution kernel (`conv4_8_A`) with `Surface ~19000px too large`.
  Cause: drop/inner shadows use `setShadow(blur: e.blur * zoom)` with NO ceiling, and
  the transparency layer they draw into is sized by the current clip — an artboard
  clip at 25× is ~19000px. So one shadowed node demanded a multi-thousand-pixel
  gaussian over a ~19000px surface → hang. Same blowup class as background blur, but
  zoom-driven. Fixes: (1) `EffectsRender.maxShadowBlurPx = 200` clamps shadow blur in
  device space (drop + inner); (2) `renderCanvas` now `ctx.clip(to: visible)` before
  the artboard clip, so NO transparency layer (shadow / opacity / blend) can allocate
  a surface bigger than the viewport — invisible to the user, but caps the worst case.
  Touched: `Color/EffectsRender.swift`, `Canvas/CanvasView.swift`. Note: the source
  (component) editor canvas doesn't yet apply the viewport clip — same risk if zoomed
  extremely far there; revisit if it surfaces.

- **2026-06-26 — Session 123 (Settings screen + active-artboard highlight):**
  • NEW full-window **Settings** (`SettingsWindow.swift`): a sidebar + detail
  scaffold (General / Canvas / Design Tokens / About) wired as the standard
  SwiftUI `Settings` scene, so ⌘, and the app-menu "Settings…" item come for free.
  Deliberately a real screen, not menu items, so it scales — add one
  `SettingsPane` case + one view per future options group. App-wide prefs are
  UserDefaults-backed via a shared `AppPreferences` key table (Settings can't
  reach a per-window `AppState`, so everything routes through defaults).
  • `AppState.init` now seeds smart-guides, selection-bounds, snap, and grid
  size/subdivisions from those defaults *only when the key exists*, so anyone who
  never opens Settings behaves exactly as before. `loadLayout()` honours a new
  restore-layout opt-out; `AppState.clearSavedLayout()` backs the General reset
  button. The five Settings-exposed toggles (smart-guides, selection-bounds, snap,
  grid size/subdivisions) are now LIVE two-way synced: a per-window View-menu/canvas
  change writes the default (property `didSet`), and a UserDefaults observer in
  `AppState` pulls Settings/other-window changes back into the open window — a
  re-entry guard (`applyingExternalPrefs`) breaks the loop. `showGrid` stays
  per-window display state (not in Settings).
  • Design Tokens pane is an honest "coming soon" placeholder (no dead controls)
  — the future home for the token system.
  • Layers: the section for the **active artboard** (the board owning the current
  selection, or a directly-selected board) now stands out — its name is tinted +
  semibold and a thin accent border runs down the section's leading edge (header +
  every row, incl. nested). Isolated in a `LayersActiveStyle` constant set so it
  folds into design tokens later. Source-editor scope never highlights. VoiceOver
  announces the active board's header as "…, active artboard".
  • Type-token groundwork: NEW `Model/TextMetrics.swift` — `FontMetrics` (Core Text
  ascent/descent/leading/cap/x-height) + `TextBoxTrim` insets math for leading-trim
  (cap-height→baseline optical box vs the font line box) + `inkBounds`. The
  Settings ▸ Design Tokens pane now hosts a real text-box-trim default (radio,
  `exp.pref.textBoxTrim`) with a metric-accurate Canvas schematic drawn FROM that
  helper. No app text rendering trims yet — this is the home for the math, ready
  for the token system.
  • Files: +`UI/SettingsWindow.swift`, +`Model/TextMetrics.swift`; edits to `EXP__design_App.swift` (Settings
  scene), `Model/AppState.swift` (defaults + reset), `UI/LayersPanel.swift`
  (active-section styling). New file is app-target only (no EXPThumbnail concern).

- **2026-06-25 — Session 122 (nudge + layers expand/collapse-all):**
  • Arrow-key nudge now works for a node INSIDE a group: `nudgeSelection` recursed
  via `mutateNested` (was top-level-only, same blind-spot as the earlier opacity
  bug) and rotates the doc-space delta into the node's local space for rotated
  ancestors (matches the move drag). Inspector X/Y already worked.
  • Layers •••: added an options menu in the Layers panel header (always present,
  even when docked) with Expand All / Collapse All (open/close every group +
  section). Also added View ▸ Expand All Layers / Collapse All Layers, wired through
  a new `AppState.layersExpandAll` closure hook the document panel registers
  (mirrors `applyTextStyle`); @objc `expandAllLayersAction:` / `collapseAllLayersAction:`
  + validateMenuItem (enabled only while the panel hook is live). Menu has room to
  grow with more layer options later.
  • TODO (needs more testing): residual layer-SELECTION weirdness the owner noticed —
  may be specific to an artboard carried through many edits, not a general bug.
  Revisit with fresh repro; likely folded into the deferred custom layers-list
  rebuild (see Session 121).

- **2026-06-25 — Session 121 (Layers follow-up + deferred rebuild):** Fixed
  rename-commit: the Layers rename field now commits on focus loss
  (`.onChange(of: nameFocused)` → `commit()`), so clicking another layer saves the
  edit instead of leaving it stuck in edit mode (Esc still cancels via
  `onExitCommand`, no double-commit). DECISION: the remaining Layers issues — the
  click-to-highlight DELAY and the residual "sometimes multiple lines" / vertical
  alignment drift — are structural to SwiftUI `List` + per-row `.onDrag` (the drag
  makes the system delay every tap to disambiguate; `List` owns its row spacing so
  the drop line/heights keep fighting us). The agreed SOLID FIX is to rebuild the
  layer rows on a plain `ScrollView` + `VStack` we fully control (instant selection,
  one drop line rendered in the real gap, exact row heights, manual multi-select
  shift-range/⌘-toggle, drag-into-group, instance sub-rows). DEFERRED to the
  visual-polish pass — the owner will tackle it once design tokens are ready (so the
  rebuild can bake in the final spacing/typography at the same time). Also deferred
  to that pass: smoother section collapse animation.

- **2026-06-25 — Session 121 (Layers panel fixes, batch 2 of bug list):**
  (7) Collapsible sections: each artboard / Wall section is now `Section(isExpanded:)`
  with per-section state (`collapsedSections`), so the header chevron collapses it.
  (8) Auto-reveal: `.onChange(of: app.selectedNodeIDs)` opens a selected layer's
  ancestor groups (`ancestorGroupIDs`) and un-collapses its owning section, so a
  layer selected on the canvas is findable in the panel. (Scroll-into-view noted as
  a future add — needs a ScrollViewReader around the List.)
  (9+10) Drop line + reorder reliability: rows are now a FIXED height (28) and flush
  (`listRowInsets` zeroed top/bottom, `listRowSeparator(.hidden)`), so the
  before/after insertion lines coincide into ONE line per gap (was two, separated by
  the row gap) and the drop thresholds are stable (the measured `rowHeight` jittered).
  Double-click-to-rename kept. If reorder still feels off after testing, next step is
  neighbour-aware drop mapping or a custom scroll/stack list.

- **2026-06-25 — Session 121 (canvas interaction fixes, batch 1 of bug list):**
  (1) Line shift-constrain: drawing a line or dragging an endpoint with Shift snaps
  to 45° increments (incl. horizontal/vertical) via `constrainLineEndpoint`
  (`.drawLine` / `.lineEndpoint` drags). Whole-line move already axis-locked.
  (2) Nested resize: a single node selected inside an UNrotated group now shows the
  8-handle box + rotate knob and resizes. `hitTestHandle`/`rotateKnobPoint` dropped
  the top-level-only guard (now `isTopLevelNode || ancestorRotation==0`) and use the
  absolute frame via `nodeOffset`; the `.resize` drag converts the cursor into the
  node's parent-local space by subtracting `nodeOffset`. Nested LINES also fixed:
  `hitTestLineEndpoint` + the `.lineEndpoint` setup now use a chain-aware
  `lineEndpointsResolvedDoc`, and `setLine` converts doc→parent-local via
  `docToParentLocal`, so nested line endpoints draw + drag correctly. (Nodes under a
  ROTATED group stay move-only — flagged.)
  (3) Text-in-group edit gating: a nested text now needs an extra step — first
  double-click selects/drills (so it's draggable), a further double-click (when
  already selected) opens the editor. Top-level text unchanged (double-click edits).
  (4) Esc exits text edit: added `textView(_:doCommandBy:)` handling
  `cancelOperation:` → `commitTextEditing()`, which keeps the node selected + movable
  and restores canvas first responder.
  (5) Opacity number-shortcut now reaches a layer inside a group
  (`setOpacityOnSelection` recurses via `mutateNested`).
  (6) Line inspector W/H: new `lineSizeBinding` scales the line's endpoints (they're
  frame-local, so setting `frame.size` alone did nothing); inspector branches to it
  for `.line`.
  NEEDS VISUAL CHECK (can't compile here), especially nested resize math + the
  text double-click gating feel. Layers-panel items (7–10) are the next batch.

- **2026-06-25 — Session 120 (eyedropper `i`):** Added the eyedropper shortcut.
  Two entry points, both via `NSColorSampler` (the system screen loupe):
  (1) On the canvas, `i` (no modifiers, handled in `keyDown` like the V/A/R/… tool
  letters, so it never hijacks a focused text field) → `eyedropToSelection()`
  samples a screen color and applies it to the selection: fill for
  rect/ellipse/polygon/path, stroke for a line (its fill-equivalent), text color
  for text, auto-padding background for a group; one undo step. Also exposed as
  `eyedropperAction:` (@objc) in the Object menu (no key-equivalent — the canvas
  key owns `i`) + right-click ("Eyedropper (Pick Fill)") + validateMenuItem.
  (2) In the color popover (`ColorPopover`, used for both solid fill and the
  selected gradient stop), a local `NSEvent` keyDown monitor active while the
  popover is open makes plain `i` fire the existing `sampleScreen()` even when the
  hex/value field has focus — safe to swallow there since a color code
  (hex/rgb/hsl/lch/oklch) never contains `i`. ⌘/⌃/⌥+i are left alone.

- **2026-06-25 — Session 120 (shape masking — Phase 16a):** Non-destructive,
  editable shape masks. Chose to model a mask as a `.group` with two new Node
  bools (`isMask` on the container, `isMaskShape` on the clip child) rather than a
  new `NodeContent` case — this reuses ALL group machinery (enter-to-edit, Layers
  drag-into-group for adding content, copy/paste, instances, auto-layout passthrough
  since mask groups have no autoLayout) and keeps the NodeContent switch surface
  small (less Xcode-agent stub risk). Render (`CanvasView.drawNodeContent` `.group`):
  when `isMask`, build a `CGMutablePath` = union of `isMaskShape` children's
  silhouettes (`appendSilhouette` recurses; a group mask child = merged descendants),
  `ctx.clip`, draw the non-mask content; mask shapes draw no fill. `drawMaskOutline`
  shows a dashed accent boundary while the mask or a descendant is selected
  (`maskEditingActive`). Raster/PDF export mirrors the clip (`appendExportSilhouette`).
  Create: `maskWithTopShape()` mirrors `group()` — topmost selected = mask shape;
  `releaseMask()` reverts to a plain group; `selectionHasMask()` for validation.
  Command coverage: @objc actions, Object menu (⌃⌘M + Release Mask), right-click
  (Mask with Top Shape / Release Mask), validateMenuItem cases. No new files, so no
  EXPThumbnail target change. NEEDS A VISUAL CHECK (can't compile here): confirm the
  clip aligns, the dashed outline shows when editing, and drag-in adds content.
  DEFERRED: SVG `<clipPath>` export, a Layers mask badge.
  FOLLOW-UP (same session): rotated/flipped mask shapes now clip correctly.
  `appendSilhouette` / `appendExportSilhouette` bake each node's own rotation/flip
  (CGAffineTransform about its center) into the clip path and compose it with
  ancestor transforms (`base`), mirroring the `drawNode`/`drawExportNode` CTM. The
  mask group's own rotation needs no handling — it's the active CTM when the clip
  is applied.

- **2026-06-25 — Session 119 (background blur effect):** Implemented the
  stackable `Effect.Kind.backgroundBlur`. Model: added the case to `Effect.Kind`.
  Canvas: `draw(_:)` now splits into a cheap window path and, ONLY when a blur node
  exists (`documentHasBackgroundBlur` scans the tree), an offscreen-bitmap path
  (`bitmapImageRepForCachingDisplay` → `renderCanvas(into:)` → `rep.draw`) so a blur
  node can sample its accumulated backdrop. In `drawNode` (guarded to unrotated,
  unflipped nodes), `ctx.makeImage()` grabs the backdrop, `drawBackgroundBlur`
  CIGaussianBlur's it (`sigma = amount · zoom · backingScale`) and composites it
  clipped to the node silhouette; one composite per enabled blur effect (stackable).
  Safe fallback: nil `makeImage()` → no-op, common path unchanged. Inspector: "Bg
  Blur" in the add menu + picker, single Amount field, default 8. NOT yet in
  `ExportRenderer` (canvas-only for now — flagged for a follow-up).
  FIX (same session): first cut rendered the offscreen pass into an UN-flipped
  `NSGraphicsContext(bitmapImageRep:)`, which disagreed with the flipped view —
  `NSString.draw` honors `isFlipped`, so text/artboard-name came out upside down +
  the sampled backdrop was vertically mirrored. Now the offscreen pass uses a
  cached `CGContext` wrapped in `NSGraphicsContext(cgContext:flipped:true)` with a
  CTM matching `docToView`, so text + geometry render identically to on-screen;
  the result is blitted upright with the image-node idiom. The backing bitmap is
  cached and only reallocated when the pixel size changes (was allocating a
  multi-MB `bitmapImageRepForCachingDisplay` every frame → choppy pan/zoom).
  PERF (same session): blur was Gaussian-ing the WHOLE window per blur node every
  frame. Now `drawBackgroundBlur` renders only the node's region (+ blur-radius
  margin) via `createCGImage(from: region)`, so Core Image computes a small rect
  instead of the full canvas. Still one full-window `makeImage` per blur node (the
  backdrop readback) — fine for a few nodes; revisit if many stacked blurs.
  PERF 2 (same session): full backdrop blur on a CPU Core Graphics canvas is
  inherently too heavy for 60fps live pan/zoom (per-frame full-scene `makeImage`
  readback + Core Image roundtrip). Added "blur catches up" deferral:
  `suppressBlurDuringInteraction()` (called from `scrollWheel`, `zoom(by:anchor:)`,
  hand-drag pan) sets `blurSuppressed`, so `draw(_:)` takes the cheap direct path
  during the gesture; a 0.12s settle timer clears it and forces one final blurred
  redraw. Real fix for buttery live blur would be a GPU/layer-backed canvas — out
  of scope for now. KNOWN: backdrop shows un-blurred mid-gesture, snaps to blurred
  on settle (acceptable, standard behavior).

- **2026-06-24 — Session 118 (flip: selection outline trace matches too):**
  Cleaned up Session 117's leftover: the selection box's path OUTLINE trace now
  mirrors with the flip. Wrapped just the `bezierPath` stroke in `drawNodeSelection`
  in a flip CTM about the frame centre (inside the existing rotation block, so it's
  flip-then-rotate like the renderer). Box/handles untouched (symmetric).

- **2026-06-24 — Session 117 (path-point editing is flip-aware):**
  Resolved Session 116's limitation: anchors now track a flipped path. Made the
  node-local ↔ view conversions apply the flip (a mirror within the frame about its
  centre, BEFORE rotation — matching the renderer): `nodeLocalToView` mirrors the
  local point, `viewToNodeLocal` un-mirrors it. Since drawing the anchors/handles
  (`drawPathPoints`), hit-testing (`hitTestPathPoint`), pen hover/remove
  (`penHover`), and dragging (`pathPointDrag`/`pathPointGroupDrag`) all funnel
  through those two functions, every point operation now lines up with the flipped
  shape. Also un-flipped `addPenPoint`'s direct local calc so an added anchor lands
  under the cursor on a flipped path.
  MINOR remaining: the selection-box's faint path OUTLINE trace still draws unflipped
  (the anchors/handles/box are correct); cosmetic, separate CTM, left for later.

- **2026-06-24 — Session 116 (add-point on complex shapes + flip + resize-flip):**
  • **Add-point** had the same multi-contour gap as remove: it only searched/inserted
    into `ps.points` (first contour). `addPenPoint` now finds the nearest segment
    across EVERY contour (`editContours`, `contourClosed`) and inserts into the right
    one via `writeEditContours`.
  • **Flip Horizontal / Vertical**: new `flipH`/`flipV` flags on `Node`, applied at
    draw time about the frame centre (like rotation) so it works uniformly for
    images, text, paths, and groups — rendered on canvas + raster/PDF + SVG export
    (`scale(±1)` / `transform`). Actions `flipHorizontalAction`/`flipVerticalAction`
    toggle each selected node; wired into the **Arrange** menu, right-click, and
    `validateMenuItem`.
  • **Resize-past-flip**: dragging a handle PAST the opposite edge now mirrors the
    object (un-rotated case). The `.resize` drag captures `resizeFlipBaseline` at
    start and XORs a per-axis "crossed the anchor" test into the flip flags.
  LIMITATION: editing path points (node tool) on a FLIPPED path shows anchors in
  unflipped positions (flip is a render transform, not baked into geometry) — fine
  for the common image/shape flip; bake-on-flip for paths is a later refinement.

- **2026-06-24 — Session 115 (remove-point on complex shapes + closer zoom):**
  • **Remove-point now works on multi-contour paths** (outlined text, SVG subpaths —
    the "more complex shapes" where it silently did nothing). `penHover` was gated to
    `!isMultiContour`; it now scans EVERY contour via `ps.editContours` and returns a
    `PointAddress(contour, index)`. `removePenPoint` takes that address, removes from
    the right contour via `writeEditContours`, drops a contour that falls below 2
    points, and collapses the whole node only when nothing usable remains.
  • **Closer zoom**: max zoom 64× → **256×** (6400% → 25600%) for pixel/anchor work.

- **2026-06-24 — Session 114 (pen tool: visible anchors + Adobe-style deselect):**
  Builds on Session 113's `penHover` scoping fix.
  • **Anchors visible under the pen tool**: when the pen is active but NOT mid-draw,
    the SELECTED path's anchors and the path UNDER THE CURSOR now draw their points
    (in the canvas draw block, guarded by `app.tool == .pen, penNodeID == nil`), and
    `mouseMoved` now redraws under the pen so the hovered vector's anchors light up
    live. The owner couldn't see where points were to add/remove — the hit-tests were
    fine (Session 113), just invisible.
  • **Node-tool deselect like Adobe**: clicking the path BODY (no drag) DESELECTS the
    points instead of requiring a click outside the whole bounding box. New
    `pointGroupFromBody` flag (set true in `nodeToolMouseDown` step 2, false on an
    anchor grab); mouseUp's `.pathPointGroup` case does `setSelectedPoints([])` when
    `!didEdit && pointGroupFromBody`. Dragging the body still moves the selection;
    empty-space click still deselects.
  REMAINING: confirm add/remove on rotated / deeply-nested paths now that anchors are
  visible; if still off, trace `penHover → hitPath → addPenPoint/removePenPoint`.

- **2026-06-24 — Session 113 (fix: pen-tool "+"/"−" cursor stuck on, add-point broken):**
  Owner reported, right after Session 111's pen delete-point feature: "add point
  is not working, and the add point cursor seems to be on all the time." Root
  cause: `hitTestPenRemovablePoint` (added in Session 111) scanned **every**
  single-contour path's **every** anchor across the whole document on every
  cursor move/click, with no z-order or locality awareness — unlike every other
  hit-test in the file (`hitPath`/`nodeHit`), which always stops at the topmost
  node actually under the cursor. On any document with more than a couple of
  detailed paths, anchors belonging to shapes elsewhere on the canvas could
  fall within the fixed 12pt `handleGrab` radius of the cursor almost anywhere,
  so the "−" remove-check (checked first) or the pre-existing "+" add-check
  would key off the wrong, unrelated node — intercepting clicks that should
  have added a point to whatever was actually under the cursor, and making one
  of the two badge cursors read as "always on."
  Fixed by replacing `hitTestPenRemovablePoint`'s flat whole-document scan with
  a new `penHover(atViewPoint:)` that reuses `hitPath(atDoc:).last` — the exact
  same topmost-hit scoping every other tool already relies on — and only checks
  *that* node's anchors for a `handleGrab` match. `hitPath`'s segment-distance
  test already catches thin/unfilled open paths (an anchor is always
  distance-0 from its own segment), so the original worry that motivated the
  flat scan didn't hold up. `desiredCursor`'s `.pen` case and `penMouseDown`'s
  inactive-session branch both now call `penHover` once and branch on
  `removableIndex`/`leafID` instead of running two separate, differently-scoped
  hit-tests.
  Not yet built/run in Xcode — next session should confirm: pen tool over a
  busy canvas (multiple paths) only shows "+"/"−" when actually hovering the
  relevant shape/anchor, and clicking a shape's body away from any anchor adds
  a point to *that* shape again.

- **2026-06-24 — Session 112 (fix: outlined-text bounding box goes stale once points move outside it):**
  Owner reported that after dragging an outlined-text path's points outside its
  original box, (a) the box itself never grew to match, and (b) grabbing the
  shape's body to drag the whole point-selection as a group stopped working.
  Same root cause for both: `normalizePath()` (CanvasView.swift) deliberately
  early-returned for multi-contour (outlined-text) paths, leaving `node.frame`
  stale after an edit. `nodeHit`'s multi-contour fast-path is
  `frame.contains(docPoint)` — a stale, too-small frame means clicks on points
  now outside it no longer register as "on the shape," which is exactly what
  `nodeToolMouseDown`'s case 2 (grab-body-to-drag-selection) depends on.
  Fixed by generalizing `normalizePath` to rebase **every** contour (via
  `ps.editContours` / `writeEditContours`, not just `ps.points`), with the new
  bbox computed from anchors **and** control handles, not anchors alone — a
  bezier curve never leaves the convex hull of its anchor+handle points, so
  this guarantees the recomputed frame always encloses the actual curve.
  Re-checked the original worry behind the old skip (re-framing "would clip
  the glyph's curves"): confirmed via `drawDocument`/`drawNode` that nothing
  clips a path to its own `node.frame` — only artboards clip — so a frame that
  grows or shrinks here can't visually clip anything. No behavior change for
  ordinary single-contour paths (same anchor-rebasing math, now also
  considering handles, which only makes that box more accurate).
  Not yet built/run in Xcode — next session should confirm: Edit Points on an
  outlined-text glyph, drag a point outside the original box, confirm the box
  grows to match and the shape can still be grabbed by its body to drag the
  whole selection.

- **2026-06-24 — Session 111 (feature: delete points, not just whole elements):**
  Two related point-deletion gaps, both in `CanvasView.swift`:
  1. **Node tool (Edit Points):** pressing Delete with points selected used to
     delete the entire element. Added `deleteSelectedPoints()` — removes only
     the selected `PointAddress`es from the edited path's `editContours`
     (mirrors `rotateSelectedPoints`'s selection source/commit pattern), drops
     any contour that's emptied out (e.g. a fully-deleted hole in an outlined
     glyph), writes back via `ps.writeEditContours(cs)`, commits, clears the
     point selection. `deleteSelection()` now checks
     `app.tool == .node && !selectedPointAddresses.isEmpty` first and routes
     there instead of the whole-node path — so the Delete key, Edit menu, and
     right-click menu all pick this up for free with no separate dispatch.
  2. **Pen tool:** added a true "remove point" mode, mirroring the existing
     "add point" affordance. `hitTestPenRemovablePoint` finds an anchor
     directly under the cursor (any single-contour path, top-most first,
     including inside groups) when no pen session is active. The hover cursor
     now shows a "−" badge over a hit anchor (checked *before* the existing
     "+"/`.dragCopy` body-hover check, so a point sitting on its own path's
     fill still reads as removable), and clicking calls `removePenPoint`,
     which deletes just that anchor — or, if the path collapses below 2
     points, removes the whole node via `removeNested` (correct for paths
     nested in a group), same convention `finishPen` already uses for a lone
     pen click. Scoped to single-contour paths only for this pass — outlined-
     text/compound paths aren't pen-editable yet, matching the existing
     "add point" feature's scope.
     **Placeholder cursor:** AppKit has no stock "minus badge" cursor and no
     formal artwork has been supplied for one, so `removePointCursor` draws a
     small black-fill/white-halo minus badge over the system arrow in code
     (`CanvasView.swift`, near `desiredCursor`). This matches the project's
     black+white cursor styling but is NOT designer artwork — swap it for a
     real `NSCursor(image:hotSpot:)` per docs/DESIGN-ASSETS.md §5/§9 (vector
     art + explicit hotspot, dropped in `design-assets/cursors/`) whenever
     that's wanted.
  Not yet built/run in Xcode — next session should confirm: Edit Points →
  select a few points → Delete only removes those; Pen tool → hover an
  existing anchor (shows "−"), click removes it; clicking a point until <2
  remain removes the whole path, matching a lone pen click's behavior.

- **2026-06-24 — Session 110 (fix: V-tool resize not scaling multi-contour paths):**
  Owner reported the regular resize handles (V/select tool) were "just resizing
  the bounding box" instead of the actual vector. Root cause: in
  `CanvasNSView`'s `.resize` drag handler (CanvasView.swift), the live-drag
  path-scaling code only scaled `PathShape.points`. That's correct for simple
  pen-drawn single-contour paths, but multi-contour paths — outlined text
  (Convert to Outlines) and any compound/boolean shape — render from
  `PathShape.contours` via `renderContours` (which prefers `contours` over
  `points` when present, see `Document.swift`). So for those shapes the frame
  resized but the rendered geometry didn't move at all. Fixed by scaling both
  `ps.points` and, when present, every sub-array of `ps.contours`, using the
  same per-point scale closure — matching the pattern `SelectionTransform.
  scaleInternal` already used correctly for multi-node/group resize and the
  Inspector's numeric W/H fields (which were unaffected by this bug; only the
  live canvas-handle drag path was broken). One-line-of-reasoning fix, no new
  state or API surface.
  Not yet built/run in Xcode — next session should confirm by resizing an
  outlined-text shape and a compound path via the corner handles.

- **2026-06-24 — Session 109 (Edit Points: multi-point selection, marquee, group-drag, selection rotation):**
  Owner reported the node/Edit-Points tool had regressed (selected points no
  longer highlighted, marquee no longer multi-selected) and asked for two new
  abilities (grab-anywhere-in-selection to move it; rotate the selection about
  its own center). Investigation showed multi-point selection never existed in
  this codebase — only single-anchor drag and uniform anchor rendering did — so
  this was new functionality, not a revert. Built as one coherent system across
  three files:
  • **AppState.swift** — new "Point-selection channel," mirroring the existing
    `applyTextStyle` pattern: `selectedPointCount`, `pointSelectionRotation`,
    and `@ObservationIgnored applyPointRotation: ((Double) -> Void)?`.
  • **CanvasView.swift** — new `PointAddress: Hashable` (contour, index) pairs
    with `PathPointTarget.anchor`; `selectedPointAddresses: Set<PointAddress>`
    + `lastEditedPathID` state; two new `DragMode` cases (`pathPointGroup`,
    `pointMarquee`); rewrote `nodeToolMouseDown` to take a `shift` flag and
    handle anchor-hit (toggle on shift / select+drag otherwise), shape-body-hit
    with an existing selection (group-drags the whole selection), different-
    path-hit (switches edited path), and empty/own-body-with-no-hit (starts a
    point marquee); added `setSelectedPoints` (keeps the Inspector channel in
    sync), `syncPointSelectionIfNeeded` (clears a stale selection when the
    edited path or tool changes — called from `CanvasView.updateNSView`),
    `beginPathPointGroupDrag`/`pathPointGroupDrag` (rigid group move),
    `finishPointMarquee` (box-select by view-space hit test), and
    `rotateSelectedPoints(by:)` (rotates selected anchors+handles about their
    own bbox center, reusing the existing private `rotatePoint` helper).
    `drawPathPoints` now takes a `selected: Set<PointAddress>` and fills
    selected anchors solid (white otherwise) — the missing highlight. Marquee
    rubber-band rendering extended to cover `.pointMarquee` too.
  • **MainWindow.swift** — `pointRotationBinding` (a delta-dispatching dial,
    not a stored value — same shape as `nodeRotationBinding` but sends through
    `applyPointRotation`) and a new "N points selected" + R° field at the top
    of `pathControls()`, shown only when `app.tool == .node && selectedPointCount > 0`.
  Not yet built/run in Xcode — next session should confirm it compiles and
  test all four behaviors (highlight, marquee, group-drag, rotate) before
  considering this closed.

- **2026-06-24 — Session 108 (fix: Convert to Outlines silently failing for some fonts/box sizes):**
  Root cause: `TextContent.outlineGlyphs(in:)` (Typography.swift) handed
  `CTFramesetterCreateFrame` a path sized to the text node's STORED frame height —
  but CoreText returns ZERO lines if that height is shorter than one line at the
  font's actual natural line height. Canvas drawing never hit this because that
  draw path doesn't go through the strict framesetter, so a manually-resized box
  (or just a font with a taller em-square) could draw fine on-screen yet outline
  to nothing with no error. Whether the bug showed up depended entirely on the
  gap between the box's stored height and the chosen font's line height — hence
  "works for one font, not another." Fix: `outlineGlyphs` now floors the layout
  height at `measuredSize(boxWidth:)`'s natural height before building the path.
  Safe because CoreText always starts the first line at the TOP of the rect, so
  any extra room only pads unused space below — existing glyph placement/position
  is unaffected. Diagnosed via temporary `print` instrumentation at every silent
  guard in `convertSelectedTextToShapes` (CanvasView.swift) + `outlineGlyphs`;
  removed once the failing guard (CTFrameGetLines → 0 lines) was confirmed from
  the Xcode console.
  FOLLOW-UP (same session): the first fix (floor height at TextKit's
  `measuredSize`) wasn't generous enough — still failed on the same font until
  the box was resized larger, because TextKit and CoreText measure line height
  independently and can disagree, especially for fonts with unusual ascent/
  descent. Made the floor much more generous (2× the measured floor + a flat
  400pt pad) instead of trusting TextKit's number exactly. Also added
  `NSSound.beep()` on every early-return in `convertSelectedTextToShapes` (matching
  the existing beep-on-failure convention from `exportSelectedArtboard`/
  `exportAllArtboards`) so any FUTURE edge case is felt, not silent — per the
  owner's explicit ask that "nothing happens, no error" must never recur here.

- **2026-06-20 — Session 107 (window/panel sizing + canvas centering):**
  • **Right dock default width** 300 → **332** so the full align/distribute row fits
    without clipping. Added a load-time **migration** (`AppState.loadLayout`) that
    bumps a saved right column narrower than the default — so existing layouts get
    the wider panel automatically (anyone who set it wider keeps theirs).
  • **Default window size** 1500 × 950 (`.defaultSize` on the DocumentGroup) so a
    new document opens roomy instead of at the 900 × 600 minimum.
  • **Canvas centering**: `fitContent` now centers within the VISIBLE drawing area
    (inset by the top/left ruler strips), so the artboard reads as centered instead
    of nudged down-right.

- **2026-06-20 — Session 106 (multi-select editing + inspector polish):**
  • **Multi-select style editing** (the headline): with 2+ layers selected the
    inspector now shows **Type** (font + size), **Fill**, and **Stroke** (color +
    width) sections that apply to EVERY selected layer at once — text font/size hit
    all text layers (re-measuring auto boxes), fill/stroke hit shapes/lines and a
    frame's auto-padding background, and a Fill on text sets its colour.
    (`multiStyleControls` + `mutateAllSelected` in MainWindow.swift.)
  • **Inspector polish**: removed the "Double-click the text…" instruction line
    (no other panel has one); gave the Type / Align / Effects section headers
    `.padding(.top, 4)` so they're not glued to their dividers.
  • **Text box stays selected** after committing an inline edit (Esc / click-out),
    so it can be grabbed and moved immediately — including for auto-layout reordering.
  DEFERRED (from the same request): double-clicking the EDGE of a text box (vs its
  glyphs) to select-not-edit — finicky hit-testing, its own pass. The Esc-then-grab
  flow covers the main need for now.

- **2026-06-20 — Session 105 (delete component, drop-line, gotcha note):**
  • **Delete Component** added to the Components-panel right-click menu (destructive);
    removes the source AND every instance of it (recurses groups + other sources),
    one undo step. (`ComponentRow.deleteComponent` in PanelDock.swift.)
  • **Layers drop-line** made consistent: a `Capsule` inset 6pt, offset ±1 so it
    straddles the row boundary (so "after row N" and "before row N+1" render at the
    same y). Deeper SwiftUI drag glitchiness (drops occasionally not registering)
    remains — durable fix is an AppKit-backed reorder, logged as a follow-up.
  • **Gotcha note** added to CLAUDE.md (shared-target membership + the Xcode-agent
    reflow-stub trap) so a future session catches it immediately.
  KNOWN REMAINING / candidate next features (from a roadmap re-audit): per-child
  hug/fill/fixed sizing in auto-layout (nav-bar items that should fill), drag-reorder
  drop-gap feedback, layer masks + boolean ops + outline-stroke, gradient text fill,
  zoom-to-selection, PNG scale/transparent-bg export options, markdown text, custom
  font import, multi-window polish (reorder sections, named workspace presets).
  Interface polish (panel vertical alignment, section spacing) pending owner specifics.

- **2026-06-20 — Session 104b (the stub kept coming back — Xcode agent):**
  The `resolvedChildren` reflow stub was being re-introduced by the **Xcode 26.3
  agent** auto-fixing the build error (it replaced `AutoLayoutEngine.reflowed(...)`
  with `let laid = resolved` + a TODO each time). So adding the file to EXPThumbnail
  made the build green only because the call was *still stubbed* → no re-hug.
  Now that `AutoLayoutEngine.swift` is a member of BOTH targets, restored the real
  call (and made `laid` genuinely mutated so there's no warning to tempt another
  auto-edit). ⚠️ If override re-hug ever breaks again, FIRST check this line in
  `Document.resolvedChildren` hasn't been reverted to `let laid = resolved`.

- **2026-06-20 — Session 104 (ROOT CAUSE: resolvedChildren reflow was stubbed out):**
  The real reason instance overrides never re-hugged: `Document.resolvedChildren`
  had its `AutoLayoutEngine.reflowed(...)` call replaced with `let laid = resolved`
  (comment: "reflow happens here when AutoLayoutEngine is available") — almost
  certainly to make the **EXPThumbnail** extension target compile, since
  `Document.swift` is a member of that target but **`AutoLayoutEngine.swift` is not**.
  With reflow removed, the live instance only got the override (text changed) but the
  frame never re-hugged; **Detach** still worked because its `commitNodes` reflows the
  baked nodes afterward — which is exactly the symptom reported.
  • RESTORED the `AutoLayoutEngine.reflowed` call in `resolvedChildren`.
  • ⚠️ REQUIRED XCODE STEP: add **`Model/AutoLayoutEngine.swift`** to the
    **EXPThumbnail** target membership (File Inspector ▸ Target Membership), same as
    Document/Paint/Typography/ExportRenderer already are — otherwise the extension
    target won't build. (If it had been added when AutoLayoutEngine landed, this
    stub would never have happened.)

- **2026-06-20 — Session 103 (override commit button, fill override, scroll):**
  • **Inspector scrolls**: the selection details are now inside a `ScrollView`
    (title + zoom stay pinned), so tall inspectors (auto layout + auto padding +
    effects + align) no longer hide controls until you resize the window.
  • **Text override = explicit commit**: instance text overrides moved to a local
    draft with a ✓ button (and Return) — `InstanceTextRow`. The model + re-hug now
    fire ONCE per edit instead of on every keystroke (lighter, and the resize
    reliably registers on commit). New `commitTextOverride` / `resetOverride`.
  • **Frame fill override**: a button's background (its auto-padding fill, which
    isn't a child layer) is now overridable per instance — `overridableChildren`
    surfaces groups that have an auto-padding fill, and a `.fill` override on a group
    targets `autoPadding.fill` (`applyingOverrides`). So you can recolor a button
    instance even though the rectangle was absorbed into the frame.
  • Re-confirmed `ExpDocument.model` is `@Published` (setModel repaints), so the
    earlier "doesn't register" was the per-keystroke churn + the fixed-box measure
    gate (Session 102), both now addressed.

- **2026-06-20 — Session 102 (fix: overridden label didn't re-measure):**
  Root cause of "auto padding doesn't follow a component override": the text
  re-measure in `applyingOverrides` was gated to `box == .auto`, but a button label
  is usually a FIXED box, so the override changed the string without resizing the
  text node — leaving the auto-padding frame hugging the ORIGINAL dimensions. Now an
  overridden label ALWAYS re-measures to hug a single line (grows width), regardless
  of box mode, so the surrounding frame re-hugs the new text. This is why detach
  "snapped it into place" (detach's commit reflow ran on the baked nodes) while the
  live instance didn't.

- **2026-06-20 — Session 101 (component rename + instance frame sync):**
  • **Rename components** in the Components panel: double-click a row (or right-click
    ▸ Rename) to edit the name inline; Enter/blur commits ("Rename Component", undoable),
    Esc cancels. Single click still opens the source editor (`ComponentRow` in
    PanelDock.swift).
  • **Instance frame sync**: `updateSelectedInstance` now sets the instance's stored
    frame to its `resolvedSize` after an override, so the selection box / hit area /
    export bounds track the re-hugged size.
  • OPEN ITEM — auto padding on an INSTANCE: render + detach both go through the same
    `resolvedChildren`, so they should match; couldn't repro the divergence from the
    code. Need a repro detail: does a FRESH instance (no override) show the padded
    background, or only break after a text override? Is the background visible at all
    on the instance? (If text overrides show live but padding doesn't re-hug, the
    source text box is probably `.fixed`, not `.auto`, so it isn't re-measured.)

- **2026-06-20 — Session 100 (Auto Layout/Padding flows through components):**
  Instances now reflow auto-layout/padding for their own overrides — override a
  button component's text and the instance re-hugs, just like the source.
  • `ComponentInstance.applyingOverrides(to:)` now **recurses into groups** (so a
    text nested inside a button frame actually receives its override — previously
    only top-level source children did) and **re-measures** an overridden auto-size
    text node so the frame around it can hug it. Nested instance-hidden layers are
    dropped during resolve.
  • New `Document.resolvedChildren(of:)` / `resolvedSize(of:)`: apply overrides +
    visibility, run `AutoLayoutEngine.reflowed`, normalise to (0,0). This is the
    single source of truth for what an instance shows.
  • Canvas render, raster/PDF + SVG export, selection box, hit-testing, and
    **Detach** all route through `resolvedChildren`/`resolvedSize`, so an instance
    draws, selects, exports, and detaches at its true re-hugged size.
  NOTE: resolve runs per draw/hit (reflow + text measure); fine for now, can cache
  if instance-heavy files feel slow. Build a button as a GROUP with Auto Padding,
  THEN Create Component, so the frame travels into the source.

- **2026-06-20 — Session 99 (fix: inspector toggle didn't absorb background):**
  The Auto Padding **inspector switch** turned the trait on with a bare
  `AutoPadding()` and never absorbed the enclosing background rectangle (only the
  ⌥⌘P menu path did), so the rectangle stayed a child and padding hugged it instead
  of the text. Moved `enableAutoPadding` / `backgroundChildIndex` / `backgroundStyle`
  into `AutoLayoutEngine` (shared) and pointed BOTH the canvas action and the
  inspector toggle at it. Now flipping the switch absorbs the background → fill shows
  on the frame, padding hugs the text. (Re-toggle Auto Padding off/on for any button
  built before this fix.)

- **2026-06-20 — Session 98 (Auto Padding = CSS box model: padding + margin):**
  Reworked Auto Padding into the full CSS box model:
  `content → PADDING → background box (fill/corner/stroke) → MARGIN → frame edge`.
    – **Padding** is the gap from the content to the background-box edge; the
      background grows with it.
    – **Margin** is transparent space OUTSIDE the background (the old "outside the
      whole element" behaviour, now its own control).
  • Model: `AutoPadding` gains `margin{Top,Right,Bottom,Left}` (+ `marginW/H`).
  • Engine: `padBlock` frame = content + padding + margin (content anchored);
    `stack` total inset per side = margin + padding.
  • Render (canvas + raster/PDF + SVG): the background is drawn at the **padding box**
    = frame inset by the margin (not the full frame).
  • Overlay: two bands now — **teal** padding (background → content) and **orange**
    margin (frame → background) — both update live.
  • Inspector: Auto Padding shows a **Padding** row and a **Margin** row, then
    Fill / Corner / Stroke.
  NOTE: the content box is the text NODE's frame (its measured line box). If you want
  padding measured from the tighter glyph ink later, that's a future refinement.

- **2026-06-20 — Session 97 (Auto Padding hugs the CONTENT, not the group):**
  Padding was wrapping the whole group because the background rectangle was still
  being counted as content (absorb unreliable) and/or padding was inherited from the
  rectangle's empty space. Now: a more robust **background detector**
  (`backgroundChildIndex`) picks the largest filled child that encloses the rest
  (10% tolerance for descenders/anti-aliasing) and absorbs it as the frame
  background, so only the TEXT remains as content. Padding starts at the defaults
  and the frame hugs the text — the background is the frame itself, so it follows the
  padding exactly. Content stays anchored in place on activation (no position jump);
  the background resizes to hug. Reverted Session 96's gap-inheritance (that kept the
  old oversized look).

- **2026-06-20 — Session 96 (Auto Padding polish: overlay, no-jump, fit):**
  • **Padding overlay**: a selected auto-padding frame now shades the padding band
    (teal, dashed inner edge) so you can see the padding and watch it change live as
    you edit the values (`drawNodeSelection`).
  • **No jump on activate**: enabling Auto Padding on a text-over-rectangle now reads
    the padding straight off the background's gaps (left/top/right/bottom), so the
    frame keeps its exact size — and `padBlock` shifts the frame ORIGIN so content
    stays put in document space as padding changes (frame grows outward, not the
    content shoved over).
  • **Selection box** for a frame uses its stored (padded) frame instead of the
    content union, so the box + background + overlay all line up.
  (Background fill already tracks the frame size; the earlier "not expanding" was a
  rectangle left as a child when absorb didn't fire — the gap-based absorb is more
  reliable now.)

- **2026-06-20 — Session 95 (split Auto Layout / Auto Padding + reorder):**
  Reworked the feature into **two independent frame traits** a group can carry
  (either, both, or neither), per the owner's mental model:
    – **Auto Layout** = STACKING only (direction, gap vs space-between, cross-axis
      alignment). Items are ordered by on-canvas position, so dragging one past
      another reorders the stack.
    – **Auto Padding** = HUG + per-side padding + the frame **background**
      (fill / corner / stroke) — the button / tag / card surface. On its own it pads
      around the children's current arrangement; combined with Auto Layout it insets
      the stack. The enclosing-background absorb (rect-behind-text → frame fill) now
      lives here.
  • **Model** (`Document.swift`): `AutoLayout` slimmed to direction/distribution/
    gap/primary/cross; new `AutoPadding` struct (4 paddings + fill/corner/stroke);
    `Node.autoPadding` added next to `autoLayout` (both optional, defaulting Codable).
    ⚠️ MIGRATION: frames made in Sessions 93–94 stored padding/background ON
    autoLayout — those fields are dropped on load. Re-apply **Auto Padding** to old
    test frames (buttons especially). New files are clean.
  • **Engine** (`AutoLayoutEngine.swift`): `stack()` (padding sourced from
    autoPadding), `padBlock()` (pad around the content bounding box, arrangement
    preserved), and the combined path. Still bottom-up + idempotent.
  • **Reorder**: drag-to-reorder works on drop (position-sort). New **Move Item
    Forward / Backward** nudges a selected item one slot along its stack
    (⌥⌘] / ⌥⌘[), via right-click too.
  • **Command coverage**: `toggleAutoLayoutAction` (⌥⌘A) and `toggleAutoPaddingAction`
    (⌥⌘P) — @objc actions, Object-menu items, right-click items, validateMenuItem
    (titles flip Add/Remove). Render (canvas + raster/PDF + SVG) and full-rect
    hit-testing now read the background from `autoPadding`.
  • **Inspector**: two separate sections — **Auto Layout** (direction / gap /
    align) and **Auto Padding** (T·R·B·L padding + Fill + Corner + Stroke), each
    with its own enable switch.
  BUTTON RECIPE now: text over a filled rectangle → select both → **⌥⌘P** (the rect
  becomes the frame fill, text hugged with padding). Nav bar: select the items →
  **⌥⌘A** to stack; add **⌥⌘P** to pad + back the bar.
  REMAINING / NEXT: drag-reorder drop-gap feedback; per-child hug/fill/fixed sizing;
  a faint frame outline on canvas; inspector arrows for nudge.

- **2026-06-20 — Session 94 (Auto Layout fixes: order + frame backgrounds):**
  Fixed two issues from first testing.
  • **Items reordered to array/z-order** (lines between menu items jumped to the
    end): the engine now orders flow children by their **current on-canvas position**
    along the axis (ties keep array order), so layout matches the visual arrangement
    — and dragging an item past a neighbour now reorders the flow for free.
  • **Button background became a side-by-side item**: frames now have their own
    **background** (`AutoLayout.fill` + `cornerRadius` + `stroke`/`strokeWidth`),
    drawn behind the children (canvas + raster/PDF + SVG export). When you add auto
    layout to a selection where one filled shape **encloses** the others (text over a
    rectangle), that shape is **absorbed** into the frame's fill and dropped as a
    child — so the rectangle becomes the button surface and the text sits on it with
    padding. A filled/stroked frame is also now **hit-testable across its whole rect**
    (click the padding to select it). Inspector gained a **Frame** group: Fill
    (PaintWell), Corner, and Stroke + width.
  PROPER BUTTON RECIPE now: text over a filled rectangle → select both → ⌥⌘A. Or:
  select just the text → ⌥⌘A → set a Frame fill. Either hugs the text with padding.

- **2026-06-20 — Session 93 (Auto Layout frames — Figma-style, v1):**
  Groups can now be turned into **auto-layout frames**: a container that positions
  its children along an axis with padding + spacing and **hugs** them, reflowing
  siblings whenever anything changes (the button/tab/nav-bar case the owner asked
  for). Scope chosen: direction (H/V), 4-side padding, spacing (fixed gap *or*
  space-between), cross-axis alignment; frame hugs contents. Per-child hug/fill/
  fixed sizing deferred.
  • **Model** (`Document.swift`): new `AutoLayout` struct (direction, distribution
    `.packed`/`.spaceBetween`, gap, 4 paddings, primary + cross `Align`) with a
    defaulting Codable. Added `Node.autoLayout: AutoLayout?` (nil = plain group) —
    init param + CodingKey + `decodeIfPresent`, so old files load unchanged.
  • **Engine** (`Model/AutoLayoutEngine.swift`): pure, idempotent `reflowed(_:)`
    that walks the tree **bottom-up** (nested frames size before their parents),
    lays out each frame's visible children in LOCAL space, and sets the frame size
    (packed hugs both axes; space-between keeps the user's along-axis size and
    distributes; cross axis always hugs).
  • **Triggers**: reflow runs at the three commit funnels so every edit path ripples
    — canvas `commitNodes`, canvas `updateNode` (text-edit commit), and inspector
    `commitScoped`. No per-feature wiring needed.
  • **Command coverage** (`CanvasView` + App + context menu): `toggleAutoLayoutAction:`
    — a single selected group flips its frame on/off; any other selection is grouped
    first then framed (Figma-style). Wired as an @objc action, **Object ▸ Auto
    Layout (⌥⌘A)** (⌥⌘A chosen over Figma's ⇧A so it can't eat a capital "A" while
    typing), a right-click item, and `validateMenuItem` (title flips Add/Remove).
  • **Inspector** (`MainWindow.swift`): an **Auto Layout** section on group selection
    — enable switch, direction segmented (→ / ↓), Gap vs Space-Between with a gap
    field, four padding fields (T/R/B/L), and a cross-axis align control whose labels
    track the direction (Top/Center/Bottom for a row, Left/Center/Right for a column).
  BUILD WATCH-POINTS: add **`AutoLayoutEngine.swift`** to the app target (new file).
  `Node` gained an init param (`autoLayout:` before `content:`, defaulted) — existing
  `Node(name:frame:content:)` call sites are unaffected. Managed children snap back
  if dragged (expected for v1 — drag-to-reorder is a later pass).
  REMAINING / NEXT: per-child hug/fill/fixed sizing; drag-to-reorder inside a frame;
  a faint frame outline + badge on canvas; primary-axis alignment UI for fixed-width
  frames; nested-frame resize handles.

- **2026-06-20 — Session 92 (SVG import as editable vector layers):**
  • New **`Model/SVGImporter.swift`** — a Foundation + CoreGraphics DOM parser
    (`XMLDocument`) that turns an SVG document into a single editable **group Node**
    (children in group-local coords, frame at the origin), so an imported SVG is a
    real layer tree — not a flattened raster. Scope built per the owner's choice
    ("subset + gradients/text"):
      – Elements: `<g>`/`<svg>`/`<a>` → nested groups; `<path>` (full `d` parser:
        M/L/H/V/C/S/Q/T/A + relative, arcs→béziers, multi-subpath via `contours`);
        `<rect>` (corner radius), `<circle>`/`<ellipse>`, `<line>`,
        `<polyline>`/`<polygon>`, `<text>` (position/size/family/fill, one run).
      – **Transforms** (`translate/scale/rotate/matrix/skewX/skewY`, including the
        transform list) are baked into geometry. Axis-aligned rect/ellipse stay as
        native Rectangle/Ellipse shapes; rotated/skewed ones fall back to a Path so
        nothing is distorted.
      – **Fills/strokes**: solid colors (hex #rgb/#rrggbb/#rrggbbaa, rgb()/rgba(),
        named), `fill-opacity`/`stroke-opacity`/`opacity`, presentation attrs **and**
        inline `style="…"` (style wins). `url(#id)` fills resolve to
        `<linearGradient>`/`<radialGradient>` → our angle-based `GradientFill`
        (objectBoundingBox; linear angle from x1,y1→x2,y2; stops via stop-color /
        stop-opacity / style).
      – **viewBox** maps to the declared width/height so 1 user unit ≈ 1 pt.
  • **Wiring** (`Canvas/CanvasView.swift`): `looksLikeSVG`, `svgData(from:)`
    (file URL `.svg`, raw SVG pasteboard data, or pasted `<svg…>` markup),
    `placeSVG(_:at:)` → imports the group centred at the drop/viewport point as one
    undo step ("Import SVG"), **falling back to raster** if parsing fails so a drop
    never just disappears. Hooked into **drag-drop** (registered `UTType.svg` +
    `.string` drag types, `canDrop`, `performDragOperation` prefers vector),
    **paste**, and **File ▸ Place Image…** (NSOpenPanel now allows `.svg`; routes
    SVG → `placeSVG`, else → `placeImageData`).
  • Each imported element becomes its own editable layer (move/resize/rotate, edit
    fill/stroke, edit path points, regroup) — verified the group renderer offsets
    children by the group origin, so the whole import moves as a unit and re-localizes
    cleanly.
  BUILD WATCH-POINTS: `SVGImporter.swift` must be added to the **app target** (new
  file). No `NodeContent` switches changed (importer only constructs nodes), so no
  exhaustiveness fallout expected. Round-trip self-check: SVG→layers→SVG-export
  should look the same for the supported subset.
  REMAINING / NEXT: `<use>`/symbols, clip paths/masks, dash patterns, multi-run
  `<tspan>` text, percentage/`em` units, CSS `<style>` selectors (only inline style +
  presentation attrs today); named workspace presets; multi-window panel polish.

- **2026-06-16 — Session 91 (raster image layers + thumbnail extension):**
  • **Images**: new `NodeContent.image(ImageContent)` (bytes stored base64 in the
    .design JSON → self-contained) + `naturalSize`. Threaded `.image` through every
    content switch (drawNodeContent with a flipped CGImage draw + decode cache,
    silhouette, isBoxResizable, SelectionTransform, layer icon, export). Input:
    **File ▸ Place Image…** (⇧⌘P, NSOpenPanel), **paste** an image from the
    clipboard, and **drag-drop** image files onto the canvas (registerForDraggedTypes
    + performDragOperation), each creating an image node sized-to-fit at the drop
    point (one undo step). Export: PNG/PDF draw the image; SVG embeds a base64 PNG
    data URI `<image>`. Images get the generic frame/opacity/blend/effects controls;
    resize/rotate/group all work. (SVG-as-vector import still deferred — SVG files
    rasterize via NSImage if droppable.)
  • **QuickLook thumbnail for .design**: wrote `ThumbnailExtension/ThumbnailProvider.swift`
    (decodes Document, renders the first artboard via `ExportRenderer.pngData`).
    REQUIRES a one-time Xcode step the owner must do: add a Thumbnail Extension
    target, set its `QLSupportedContentTypes = [tapps.exp-design.designfile]`, use
    this provider, and add the model + ExportRenderer files to the target's
    membership. Steps given in chat.
  REMAINING / NEXT: SVG vector import; named workspace presets; multi-window
  refinements (de-emphasise inapplicable panels, drag-tear-out gesture); panel
  styling polish.

- **2026-06-16 — Session 90 (file extension RESOLVED + layer blend modes):**
  • File open finally works: the saga was (1) LaunchServices hadn't registered
    the dev build, then (2) a sticky LS cache on the old type id/extension. Fixed
    by a FRESH type id (`tapps.exp-design.designfile`) + extension **`.design`**,
    plus `lsregister -f <built app>`. Verified the built Info.plist merges
    correctly. Old `.exp` files still open via the Open panel for migration.
  • **Layer blend modes** (Photoshop-style): new `BlendMode` enum (normal …
    luminosity) on `Node` (`blendMode`, tolerant-decoded default normal) mapping
    to `CGBlendMode` + CSS `mix-blend-mode`. Canvas + PNG/PDF export apply it via
    the node's transparency-layer composite (set blend before `beginTransparencyLayer`,
    which resets to normal inside and composites with it); SVG export emits
    `style="mix-blend-mode:…"` on the node's `<g>`. Inspector got a **Blend** picker
    next to opacity (single selection), routed through `mutateScopedNode`. Works on
    any node incl. groups (the group's layer blends as a unit).
  NEXT (deferred): raster image layers (place/paste/drag PNG/JPG/GIF), then SVG;
  QuickLook thumbnail extension for `.design`.

- **2026-06-16 — Session 89 (file extension → ".design"; LS-cache lesson):**
  Owner's testing clarified the real story: `.exp` actually DOES work once the
  app's type is registered — the original "nothing happens" was just
  LaunchServices not having registered the build yet. The catch is LS **caches**
  the registration, so changing the extension (to `.expd` last session) didn't
  take — a new Save still offered the cached `.exp`. Per owner preference, set the
  extension to **`.design`** (Info.plist `UTTypeTagSpecification` → `design`; UTI
  id unchanged; `.exp` kept in `readableContentTypes` via `legacyExp` for opening
  old files). KEY: an extension change only applies after LS re-registers — Clean
  Build Folder + run, or `lsregister -f <app>` / nuke DerivedData. NEXT: QuickLook
  thumbnail extension for `.design`.

- **2026-06-16 — Session 88 (can't open files → ".exp" extension collision):**
  Root cause (from Get Info: Kind "Symbol Export", opens with Xcode): **macOS
  already owns the `.exp` extension** as the developer "Symbol Export" (linker
  exports) type, so our app's exported UTI can't claim it — `.exp` files resolve
  to the system type, never match `readableContentTypes`, and the app silently
  ignores them (Finder AND the in-app Open panel). Fix: switched the document
  extension to **`.expd`** (Info.plist `UTTypeTagSpecification` exp → expd; the
  UTI identifier `tapps.exp-design.document` is unchanged, so new saves are
  `.expd` and associate/open correctly). To migrate, the Open panel still lists
  old `.exp` files via `UTType.legacyExp` (the system type for `.exp`) added to
  `readableContentTypes`; they decode as the same JSON, then Save As writes
  `.expd`. (Needs a clean build so LaunchServices registers the new type.) NEXT:
  QuickLook **thumbnail extension** for `.expd` (chosen) — new Xcode target.

- **2026-06-16 — Session 87 (text "jumps right" while editing):** Root cause: the
  inline editor forced the auto-box NSTextView to a 220pt minimum width, while the
  canvas draws text in a container the width of the node's frame. For a text node
  narrower than 220 with centre/right alignment, the editor centred the text in
  the wider container → it shifted sideways during editing, snapping back on
  commit (the user's short system-font sample surfaced it). Fix: size the editor
  to the actual box width for existing nodes (`max(base.width, isNew ? 220 : 1)`),
  keeping the typing-room minimum only for brand-new empty nodes — so the editor's
  container matches the canvas and alignment renders identically.

- **2026-06-16 — Session 86 (bug-fix batch from real use):**
  1. **Component overrides** — the override rows only iterated the source's
     TOP-LEVEL children, so a component whose content is grouped showed the
     "Overrides" title and nothing else. `instanceControls` now recurses into
     groups (`overridableChildren`) to list every text/fill leaf.
  2. **Double-click rename** in the Layers panel — re-added (`.onTapGesture(count:2)`
     on the row name → `beginRename`), alongside right-click + the Inspector field.
  3. **Layers drop-line math** — `LayerDropDelegate` used a fixed 24pt row height,
     so the insertion line landed inconsistently on taller rows. Now measures the
     actual row height (GeometryReader) and uses it for the before/after/into
     thresholds.
  4. **Text editing in groups** — was gated to top-level nodes, AND the editor was
     positioned with the node's group-LOCAL frame (so it appeared offset from the
     box — likely the "jumps outside the box" symptom), AND commit wrote back with
     a top-level-only `firstIndex` (so a nested edit would be lost). Fixed: allow
     editing nested text (when no ancestor is rotated), position the NSTextView at
     the ABSOLUTE frame (`nodeOffset`), write back via recursive `updateNode`, and
     skip drawing the edited node at any depth (no double-draw). NOTE: if the
     "jumps outside the box" still happens for a TOP-LEVEL text node, need a repro
     (box type / alignment / zoom) — top-level positioning was already absolute.

- **2026-06-16 — Session 85 (shared panels across documents):** Fixed a 2nd
  document spawning a 2nd set of floating panels. The tray arrangement + active
  context moved out of per-document `AppState` into a new global
  **`PanelHub.shared`** (@Observable): `trays` (persisted app-wide at
  `exp.trays.v1`), the tray mutation methods, and weak `activeApp`/`activeDocument`
  + `activeUndo`. `PanelWindowManager` is now global (windows keyed by tray id)
  with a single `reconcile()` entry point — shows the trays when the active
  document is Multi-Window, hides them otherwise. `TrayWindowView` binds to
  `hub.activeApp/activeDocument`, so switching document windows **re-points the
  same panels** at the new document (content re-renders; no second set). The undo
  manager is vended dynamically from `hub.activeUndo`. `MainWindow` claims the
  panels via `@Environment(\.controlActiveState)` (on appear / becoming key) and
  reconciles on mode + `PanelHub.trays` changes. `AppState` keeps per-window
  things (single-window docks, workspace mode) and now delegates
  `isPanelShown`/`togglePanel`/`ensurePanelTray` to the hub for the multi case.
  Note: per-document mode still applies — switching to a Single-Window document
  hides the shared panels; back to a Multi-Window document shows them again.

- **2026-06-16 — Session 84 (Window menu redesign + tray-close fix):**
  • **Bug:** closing a tray via its ✕ left the tray in the model, so its panels
    couldn't be reopened. Now `TrayWindowDelegate.windowWillClose` →
    `PanelWindowManager.trayWindowClosed` removes the tray from the model on a
    USER close (a `programmaticClose` flag distinguishes our own mode-switch/merge
    closes, which keep the model so toggling back restores).
  • **"Untitled" windows:** tray windows now set a `title` and
    `isExcludedFromWindowsMenu = true`, so they no longer clutter the system list.
  • **Panels menu → Window menu:** dropped the custom "Panels" menu; appended to
    the system Window menu via `CommandGroup(after: .windowList)`, so the document
    window stays in its own (auto) section. New `WindowMenuItems` (driven by a
    `WindowMenuModel` published through `@FocusedValue` from MainWindow + each tray
    window) renders: a **panels section** (icon + name, checkmark when visible,
    click = reveal/focus, NEVER closes — closing is the panel's ✕; disabled in
    single-window) and a **single-window dock section** (Show/Hide left/right with
    a flipping label; disabled in multi-window). Reveal uses a Toggle whose setter
    always reveals (so the checkmark reflects state but a click can't close).
  • Dropped the old "Reset Panel Layout" menu item (can re-add later).
  Risk note: `@FocusedValue` from the manually-hosted tray windows may not always
  feed the scene's command focus; MainWindow covers the common case, and if a
  tray window is key and the menu greys out, that's the cause — fix would be an
  app-level active-document holder. Toggling/reveal actions use captured closures
  so they fire regardless once the value is present.

- **2026-06-16 — Session 83 (tray polish + Panels menu reflects state):** Two
  follow-ups on the tray model. (1) The tray **grab bar now only appears when a
  tray has >1 panel** — a lone-panel tray moves via its (transparent) native
  title bar, so there's no redundant second header. (2) The **Panels menu now
  reflects + toggles the actually-shown panels in BOTH modes**: `togglePanel` is
  mode-aware (tray membership in Multi-Window, dock membership in Single-Window),
  `isPanelShown` reports per-mode visibility, and `validateMenuItem` sets each
  item's checkmark (Layers/Properties/Components + the dock toggles show ✓ when
  shown). Note: menu checkmarks rely on the AppKit validateMenuItem path through
  SwiftUI commands — toggling is solid regardless; if a checkmark ever doesn't
  render we'd switch those items to FocusedValue-bound Toggles. Owner notes
  panels/groups/tabs styling polish is wanted "eventually" — parked, fine for the
  current feature/panel count.

- **2026-06-16 — Session 82 (multi-window → TRAY model; replaces snapping):**
  Reworked multi-window per owner feedback. Separate-window snapping/grouped-move
  (Session 80) was choppy because it synced several NSWindows every drag tick; it
  is replaced by a **tray** model: panels combine into ONE window (a tray) with a
  **grab bar** on top — dragging the bar moves the whole unit smoothly (native,
  single window). New `PanelTray` (panels + per-panel collapsed + frame) lives in
  `AppState.trays` (Codable, persisted alongside the rest of the layout).
  `PanelWindowManager` now maps trays→windows (`syncTrays`: open new, close gone),
  records each window's frame back via `setTrayFrame`, and **removes the
  full-screen/zoom button**. `TrayWindowView` renders the grab bar + stacked
  `PanelSection`s. Interactions: drag a panel **header** onto a tray to
  merge/reorder (horizontal insertion line, cross-window via SwiftUI DnD with the
  dragged id shared through `AppState.trayDraggingPanel`); **click a header** to
  collapse/expand its body (Adobe-style); a header **pop-out button** tears a panel
  into its own tray. MainWindow seeds trays on first multi entry, syncs on
  `app.trays` change, restores on launch.
  DEFERRED (told owner): side-by-side docking inside one tray (vertical line /
  multi-column — currently vertical stacking only); the pure drag-header-OUT tear
  gesture (pop-out button stands in, since SwiftUI DnD can't catch a drop on empty
  space); single-window dock still collapses via its chevron.

- **2026-06-16 — Session 81 (panel window snapping + grouped move):** Floating
  panel windows now **snap together** and **move as a unit**. While dragging a
  panel, its edges magnetize (12pt) to nearby panel windows' edges (flush docking
  or alignment); once windows are flush they form a **cluster**, and dragging any
  one drags the whole connected cluster. Implemented in `PanelWindowManager`:
  `windowMoved` computes the docked cluster from live frames, translates the
  others by the same delta, then applies an edge-snap to non-cluster neighbours;
  `moveWindows` does programmatic neighbour moves behind a re-entrancy guard.
  `PanelWindowDelegate` (was PanelUndoDelegate) forwards `windowDidMove` /
  `windowDidResize` via `MainActor.assumeIsolated`; `liveFrames` + `appPrefixForKey`
  track open windows per document. Snapping during a live OS drag can be slightly
  jittery near thresholds — tune `snapDistance`/`flushTolerance` after testing.

- **2026-06-16 — Session 80 (remember floating panel window frames):** Floating
  panel windows now keep their size + position across single⇄multi toggles (and
  launches). `PanelWindowManager` records each window's `frame` on close
  (`closePanels` runs on toggle-to-single and on document-window close), keyed by
  panel (global, `exp.panelFrames.v1`), and restores it on open instead of the
  staggered default. First-time-only windows still stagger. This sets up the
  intended model for named workspaces later: **picking a saved workspace = reset
  to that preset; toggling/opening = restore your last live state.** Avoided a
  delegate/concurrency detour by capturing frames in the @MainActor manager at
  close time rather than via window move/resize callbacks (good enough — captures
  the last state on every toggle and on quit).

- **2026-06-16 — Session 79 (layout persistence + multi-window toggle polish):**
  Two small wins. (1) Disabled the left/right dock toggle buttons + their
  Panels-menu items in Multi-Window mode (no docks there) — buttons via
  `.disabled(workspaceMode == .multiWindow)`, menu via `validateMenuItem`.
  (2) **Layout now persists between launches:** `AppState` saves a `PersistedLayout`
  (workspace arrangement incl. collapse/weights/**column widths**, workspace mode,
  dock visibility) to UserDefaults on change (property `didSet`s, guarded by a
  `restoringLayout` flag) and restores it in `init()`. Real column widths are
  captured as the splitter is dragged (`DockColumnView` reports `geo.size.width`
  → `AppState.setColumnWidth`). If the saved mode was Multi-Window, `MainWindow`
  re-floats the panels on `.onAppear` (deferred a tick). `WorkspaceMode` is now
  Codable. It's an app-wide workspace preference, separate from document data.
  NEXT (13d remainder): multiple **named** workspace presets + a picker. Plus the
  outstanding 13c refinements (live single-panel open/close in multi mode,
  de-emphasis, tear-out/re-dock).

- **2026-06-16 — Session 78 (multi-window mode, first pass):** The Multi-Window
  workspace mode now does something real: switching to it (top-right mode switch)
  **floats every layout panel into its own macOS window** that can be dragged to a
  second monitor — the multi-monitor payoff. New `UI/PanelWindow.swift`
  (`PanelWindowManager`): hosts each panel via `panelContent` in an `NSWindow`,
  injects the SAME `AppState` + document and vends the doc's undo manager through
  a window delegate; staggered placement. `MainWindow` hides its docks in
  multi-window mode (canvas fills) and drives open/close via
  `.onChange(of: app.workspaceMode)`, plus `closePanels` on `.onDisappear`.
  `AppState.layoutPanels` enumerates the panels to float. Because AppState is
  shared, the floating **Properties** window tracks the main canvas selection live
  and its edits land on the document's undo stack. Default workspace floats
  Layers · Properties · Components.
  NEXT (tracked in 13c): live open/close when toggling a single panel in multi
  mode (today it syncs on mode-switch only); de-emphasise inapplicable panels;
  drag-to-re-dock / tear-out. Then **13d persistence/workspaces**. Build note: new
  file `PanelWindow.swift` — ensure it's in the target if not auto-synced.

- **2026-06-16 — Session 77 (panel reorder + Panels menu → single-window mode
  done):** Drag a panel **heading** to reorder it within a column or move it to
  the other column — insertion line shows where it lands, the dragged section
  dims. Built with the Layers-panel drop-delegate pattern (closure does the move
  so there's no actor-isolation snag); `AppState.moveGroup(_:toSide:before:)`
  handles remove-from-any-column + insert. New **Panels menu**: Show/Hide
  Layers · Properties · Components, Show/Hide Left Dock (⌥⌘\) · Right Dock (⌘\),
  Reset Panel Layout — dispatched to the focused canvas (`togglePanel*` /
  `toggleLeft|RightDock` / `resetPanelLayout` @objc actions) → `AppState.togglePanel`
  / `resetWorkspace`. With this, **single-window mode is feature-complete**
  (tabbed-when-needed headings, collapse/expand, resize, reorder, contextual
  hide, show/hide + reset). NEXT per the plan: **13c multi-window mode** (panels
  as separate NSWindows for multi-monitor), then **13d persistence/workspaces**.

- **2026-06-16 — Session 76 (multi-selection + group resize/rotate):** Closed the
  long-standing block: you can now resize AND rotate a multi-selection or a
  single group — on the canvas and in the Inspector. New `Model/SelectionTransform.swift`
  holds the shared, pure math (so canvas + inspector agree): `scaled(node, about:
  sx:sy:)` (recursively scales group children + path points + line endpoints),
  `rotated(node, aboutDoc:deg:)` (orbits each node's centre + adds the delta to
  its own rotation — works for every shape incl. lines), `visualBounds` (rotation-
  aware AABB) + `unionBounds`. Canvas: new `.resizeSelection` / `.rotateSelection`
  drag modes draw a unified 8-handle box + rotate knob over the selection bounds
  whenever >1 node OR a single group is selected (a lone non-group node keeps the
  existing single-node path). Free drag = non-uniform; **Shift = proportional**
  (reuses `proportionalFrame`); rotate snaps to 15° with Shift; transforms read
  from a start-of-gesture baseline snapshot so there's no drift; one undo step per
  gesture. Inspector: group W/H now scales children (was frame-only); a
  multi-selection shows X/Y/W/H acting on the selection's bounding box (move all /
  scale-about-top-left). Group rotation in the Inspector already worked (it sets
  `group.rotation`, which the renderer applies to children).
  KNOWN GAPS (noted, not blocking): numeric **rotation field for a *multi*-selection**
  isn't added (needs a stored selection angle) — use the canvas knob; resizing a
  selection that contains already-rotated items scales in screen axes (shear-ish,
  like most tools) rather than per-item local axes; nested-CHILD direct handles
  remain move-only (separate backlog item).

- **2026-06-16 — Session 75 (single-window polish + system line + mode scaffold):**
  Reframed Phase 13 into **two workspace modes** (single-window default vs.
  multi-window/Photoshop later) — see the Phase 13 decision block. This session:
  • **Top-right system line** (`TopSystemControls` in MainWindow toolbar): moved
    the zoom cluster out of the Inspector into a one-line, always-visible group
    with the dock show/hide toggles + a workspace-mode switch (`AppState.workspaceMode`).
    Removed the old far-left sidebar toggle; New Artboard stays centered.
  • **Single-window polish:** `Workspace.default` is now one panel per group (no
    combined tabs — tabs parked for multi-window). Rewrote `DockColumnView` with an
    **explicit-height model** (GeometryReader + `columnMetrics`): groups pack from
    the top, collapsed = header-only, expanded share leftover by `weight` — fixes
    the "collapsed header flung to the bottom" bug. **Animated** collapse/expand
    (Reduce-Motion aware; content stays mounted + `.clipped()` so it slides).
    **Draggable dividers** resize adjacent expanded groups (`PanelGroup.weight` +
    `AppState.adjustGroupHeights`). Default widths bumped to 264/300 so content
    doesn't start clipped.
  • **Removed dock panels' internal titles** (Layers/Inspector) — group heading is
    the only title now; source-editor window keeps its own via new
    `showsTitle`/`showsZoom` flags on LayersPanel/RightPanel (default true).
  • **Contextual whole-panel visibility** (`isApplicable`): in single mode,
    Components hides until a component exists; Color reserved/hidden. Multi mode
    will show all (de-emphasized) — not built yet.
  NEXT: panel-section **reorder** (drag heading) in single mode; then 13c
  multi-window (separate NSWindows for multi-monitor) + Window menu.

- **2026-06-16 — Session 74 notes (13a testing → next-session punch list):** Tabs
  look good. Owner feedback to address next session (logged in Phase 13 as 13a.1 +
  a promoted 13c):
  1. **Default widths too narrow** — right dock starts clipping the left edge of
     panel content on every launch; owner has to widen it each time. Give docks
     sane default/ideal widths (and/or persist width). Never start clipped.
  2. **Collapse direction is wrong** — collapsing a group flings its header to the
     bottom of the column. Wanted: header **stays put**, space collapses **upward**,
     header position stable (no jumping). Rework the height model accordingly.
  3. **Animate** collapse/expand + resize (slight, non-jarring; respect Reduce
     Motion → instant).
  4. **Remove the panels' own internal header titles** now that the tab shows the
     name (quick space-saving polish).
  5. **Independent/floating windows needed EARLY** — the main motivation is moving
     panels to a **second monitor** to see everything at once. So real separate
     NSWindows is promoted from "later/optional" to a near-term goal: single-window
     is the default, "float all panels" is a workspace option. (Panels are already
     environment-hosted, so reuse the SourceEditorWindow hosting pattern.)

- **2026-06-16 — Session 74 (Phase 13a — dock foundation):** Started the
  Photoshop-style dockable-panel system. Decision: **in-window** float/dock
  first (panels stay environment-hosted, so true separate windows can come later
  without a rewrite); dock manages **Layers + Properties** now plus reserved
  **Color** and a real **Components** panel. New `UI/PanelDock.swift`: the layout
  model (`PanelID`, `PanelGroup`, `DockColumn`, `Workspace.default`) and the
  rendering views (`DockColumnView`, `PanelGroupView`, `PanelTab`, `panelContent`
  router, `ComponentsPanel`, `ReservedPanel`). `AppState` gained `workspace` +
  `dockGroups`/`setActivePanel`/`toggleGroupCollapsed`/`resetWorkspace`.
  MainWindow now renders both dock columns from the model (left = Layers; right =
  Properties/Color tabs above Components), gated by the existing show-left/right
  toggles; column width via the HSplitView. Delivers **tabbed groups** + **collapse
  /expand** + width resize. Components list opens the same source-editor window the
  canvas double-click uses and auto-populates from `model.sources`. NEXT (13b):
  drag-to-rearrange tabs/groups + Window-menu panel show/hide; then 13c float,
  13d saveable/persisted workspaces.

- **2026-06-11 — Session 73 (polygon tool + tool-icon swaps):** Swapped the Edit-Points
  icon → `beziercurve` and Pen → `point.topleft.down.to.point.bottomright.filled.curvepath`.
  New **Polygon** tool/shape: `PolygonShape` (sides clamped 3–25, fill/stroke/strokeWidth)
  + `NodeContent.polygon`; vertices inscribed point-up in the frame so it resizes like
  rect/ellipse. Drawn by dragging (default 3 = triangle; `AppState.polygonSides` remembers
  the last count), shortcut **G**, in the tools strip's shapes group (icon `triangle`).
  Rendered on canvas + PNG/PDF + SVG (`<polygon>`); supports rotation, opacity, effects
  (silhouette), snapping, convert-to-path, pen add-point, and nesting — all the shape
  machinery. Inspector shows the standard fill/stroke + a **Sides** field/stepper (3–25)
  that also updates the tool default. _Tested: build pending; new `.polygon` case threaded
  through every NodeContent switch (render/export/hit/convert/icons)._

- **2026-06-11 — Session 72 (UI polish round 1: align row + tools strip):** Owner started
  the visual-polish phase (focus: panel layout + tools strip; icon swaps deferred — owner
  will supply exact SF Symbol names). Inspector **Align** section redesigned: the
  Selection/Artboard scope is now a labeled "Relative to" **segmented** control (distinct
  shape from the icon buttons) and **Distribute** is its own clearly-labeled row — fixes
  the mis-click between the scope dropdown and the distribute buttons. **Tools strip**:
  grouped into selection · shapes · make with hairline dividers, added a hover highlight,
  firmer active state (semibold glyph + accent fill), and a separator hairline against the
  canvas. _Broad inspector section-spacing unification deferred (do incrementally to avoid
  blind visual regressions)._

- **2026-06-11 — Session 71 (⌘G crash fix):** Session 70's `group()` used
  `reorderInParents`, which visits EVERY array holding a selected id — including the
  group it had just created (whose children are those ids) — so it regrouped endlessly
  → stack overflow / crash. Rewrote `group()` to act on the one target array directly:
  top-level selection groups in `currentNodes`; a same-parent-group selection groups via
  `mutateNested(parentID)` on that group's children; mixed parents pull to a top-level
  group. No re-descent, no recursion.

- **2026-06-11 — Session 70 (group/ungroup + pen-add inside groups):** `group()` now
  works at any level: selection sharing one parent is grouped IN PLACE there (via
  `reorderInParents` + `parentGroupID`), a selection spanning parents is pulled to a
  top-level group (absolute frames). `ungroup()` recursively dissolves a selected group
  anywhere in the tree, rebasing children into the parent's space; `selectionHasGroup`
  resolves nested. So ⌘G / ⇧⌘G work inside and outside groups. Pen "add point" now
  targets the DEEPEST shape under the cursor (so it hits shapes nested in a group),
  converts it to a path if needed, and inserts the anchor using chain-aware local coords
  (`docToParentLocal` + node rotation); the "+" cursor lights up over nested shapes too.

- **2026-06-11 — Session 69 (right-click + convert on nested):** Right-clicking a layer
  inside a group no longer jumps focus to the parent group. `menu(for:)` now targets the
  selected node when it's under the cursor (via `hitPath`), keeping a drilled-in child
  active; falls back to top-level only when nothing relevant is selected. Also made the
  conversions work on nested items: `convertSelectionToPaths` converts each selected
  shape in place via `mutateNested`; `convertSelectedTextToShapes` replaces the text node
  in its parent array via `inParentArray` (the outline is already built in the text's
  parent-local space); and `selectionConvertibleToPath` now resolves nested nodes. So
  Convert to Path / Convert to Outlines work on shapes already inside a group.

- **2026-06-11 — Session 68 (nested line selection + point editing):** Two consistency
  fixes. (1) Line selection now maps endpoints through the node's own rotation AND
  ancestor-group rotations (`nodeLocalToView`) so a nested/rotated line's highlight sits
  on the line, matching shapes. (2) The path point editor works on paths inside groups:
  `drawPathPoints`/`hitTestPathPoint` map anchors via `nodeLocalToView`, `pathPointDrag`
  inverts with `viewToNodeLocal` (new `docToParentLocal` inverse), and the node tool now
  selects the DEEPEST element under the cursor so you can grab a nested path directly.
  Added `nodeLocalToView`/`viewToNodeLocal`/`docToParentLocal` helpers.

- **2026-06-11 — Session 67 (rotated-group selection box):** The selection outline for a
  child of a rotated group was axis-aligned at the un-rotated location. Now
  `drawNodeSelection` detects rotated ancestors (`ancestorGroups`) and draws a
  transformed quad — the node's frame corners (with its own rotation) mapped through each
  ancestor group's rotation via `parentLocalToDoc` — so the box sits on the shape.

- **2026-06-11 — Session 66 (drag inside rotated group):** Dragging a child within a
  rotated group now moves along the group's rotated axes, not the screen axes. The
  `.nodes` drag converts the document-space delta into each node's parent space via
  `ancestorRotation(of:)` (sum of ancestor group rotations) + `rotateVector(_:by:)`.
  Resolves the follow-up logged in Session 65.

- **2026-06-11 — Session 65 (rotated-group hit-path fix):** Clicking/drilling into a
  ROTATED group missed its children — `hitPath` (the select/drill walk) passed the raw
  cursor down without undoing each group's rotation. Now it inverse-rotates the point
  about each rotated group's center while descending (mirroring `nodeHit`/`drawNode`),
  so children of rotated groups select where they actually appear. _Known follow-up:
  dragging a child WITHIN a rotated group still applies the move in doc space, not the
  group's rotated local space — logged for later._

- **2026-06-11 — Session 64 (nested layer select + group box):** Two fixes. (1) Clicking
  a layer INSIDE a group in the Layers panel now selects just that layer — manual
  `DisclosureGroup` children don't reliably feed `List(selection:)`, so nested rows get
  an explicit select-on-tap (`NestedTapSelect`; top-level rows keep native List
  selection for Shift/⌘ multi-select). (2) A group's on-canvas selection box now draws
  around the live union of its descendants (`groupContentBounds`) instead of the stored
  group frame, so it updates immediately when the group's footprint changes (e.g. a
  layer dragged into it via the panel) — matching the hit area, which was already correct.

- **2026-06-11 — Session 63 (Layers drag-into-group / component):** Replaced the Layers
  panel's native `onMove` with a location-aware `LayerDropDelegate`: top/bottom edge of a
  row = reorder (before/after, drawn with an accent insertion line), middle of a group OR
  component-instance row = drop INTO it (accent fill highlight). `handleDrop` recursively
  extracts the dragged node and re-inserts it — into a group's children (at the back =
  display bottom), as a sibling before/after a target, or (onto an instance) into that
  component's shared **source** — preserving absolute position via parent-offset math, and
  blocking a group from being dropped into its own subtree. New model helpers: `parentOffset`,
  `parentNodeID`, `extract`, `insertIntoGroup`, `insertSibling`, `moveIntoSource`. Works in
  the component source editor too (scope-aware). _Refinement: dropping among an expanded
  group's children shows the child's line but not a simultaneous parent-group highlight yet._

- **2026-06-11 — Session 62 (universal edit ops for nested):** Made the edit
  operations work on nested children, however deep, in both document and component-
  source scopes. New recursive helpers `inParentArray` (mutate the array that
  directly holds a node) and `reorderInParents` (transform every parent array that
  holds a selection). `duplicateSelectedInPlace` now clones each selected node right
  after itself inside its own parent (fresh ids via `cloned`), so duplicate (⌘D) and
  option-drag work nested (removed the old top-level guard). `collectSelectedNodes`
  gathers nested selections with absolute frames so copy/cut/paste position correctly.
  `nudgeOrder`/`reorderSelection` (bring/send) reorder within each selection's parent
  group. Delete was already nested-aware (`removeNested`); rotate/opacity/etc. via the
  Inspector were made recursive in Session 61. _Still top-level only: align/distribute
  (logged to backlog)._ Next: Layers-panel drag INTO a group/component.

- **2026-06-11 — Session 61 (select inside groups):** Drill into groups. Canvas:
  `node(_:)`/`updateNode` are now recursive (search/mutate into groups), plus
  `nodeOffset`, `isTopLevelNode`, `hitPath`, `mutateNested`, `removeNested`.
  **Double-click** drills one level deeper along the cursor's hit path (repeat to go
  deeper); **⌘-click** selects the deepest leaf directly; single-clicking a
  drilled-in element keeps it so you can drag it. Selection drawing, `selectedNode
  Origins`, and delete are offset/nesting aware; resize/rotate handles are suppressed
  for nested (move-only) so handle math stays correct. Inspector: `selectedNode`
  resolves nested, and all node-edit commits (position/size/name/rotation/opacity,
  text, shape, path, instance, effects) route through a recursive `mutateScopedNode`,
  so editing a nested child works. Known gaps logged to the refinement backlog
  (nested inline text-edit positioning, nested resize handles, node-tool overlay).

- **2026-06-11 — Session 60 (full menu bar + command-coverage convention):** Owner asked
  to build all the menus AND make it a permanent rule. Added the **Command-coverage rule**
  to CLAUDE.md (every action wired 5 ways in one change: canvas @objc action, menu item +
  shortcut, right-click where contextual, `validateMenuItem`, Inspector control if it has
  params). Restructured `.commands` into File / Edit / Object / Type / Arrange / View
  (Window is system). New canvas actions `selectAll(_:)` (top-level visible/unlocked nodes)
  + `deselectAllAction(_:)` with validation; Edit gained Duplicate ⌘D + Deselect All ⇧⌘A
  (Select All ⌘A rides the system Edit item → `selectAll:`). Right-click gained an
  "Align & Distribute" submenu for 2+ selections. Also wrote **docs/DESIGN-ASSETS.md**
  (icon/cursor/color/button formats, sizes, naming, `design-assets/` handoff manifest) and
  linked it from CLAUDE.md's read-first list, ahead of the panel/icon refinement phase.

- **2026-06-11 — Session 59 (grids):** Both requested kinds. Uniform square grid is a
  session workspace pref (AppState `showGrid`/`gridSize`/`gridSubdivisions`), drawn
  globally with minor+major lines (`drawUniformGrid`), settings in the no-selection
  Inspector, ⌘' toggle. Per-artboard layout grids persist on `Artboard.layoutGrids`
  (`LayoutGrid`: columns/rows with count·gutter·margin, or baseline spacing; +color
  +visible), drawn clipped per board (`drawLayoutGrids`), edited in a new artboard
  "Layout Grids" Inspector section (add menu, per-grid kind/visible/color + numeric
  fields, remove). `snapToGrid` (⇧⌘') extends `snapNodeOffset` with the uniform minor
  lines + layout column/row/baseline edges; ⌘ still disables snapping. Phase 11 done.

- **2026-06-11 — Session 58 (rulers + guides):** Photoshop-style. Rulers draw as top/left
  chrome strips (`drawRulers`/`drawRulerTicks`, nice 1·2·5×10ⁿ steps, pointer marker).
  `Document.guides: [Guide]` (axis + position, persisted with a backward-compatible
  Document decoder). Drag from a ruler creates a guide, drag a guide moves it, drop on a
  ruler deletes it — a new `.guide` DragMode handled in mouseDown/Dragged/Up via
  `beginGuideDrag`/`updateGuideDrag`/`finishGuideDrag`, each one undo step through the
  existing gesture-undo path. `snapNodeOffset` snaps a dragged selection's edges/centers
  to guides + the owning artboard's edges/center (⌘ disables). AppState toggles
  `showRulers`/`showGuides`/`guidesLocked`; View menu adds Show/Hide Rulers (⌘R),
  Show/Hide Guides (⌘;), Lock Guides (⌥⌘;), Clear Guides. Document-scope only (source
  editor unchanged). Completes Phase 11 except the optional grid overlay.

- **2026-06-11 — Session 57 (⌥-hover spacing measurements):** Figma-style measurement
  overlay. `optionHeld` tracked in `mouseMoved`/`flagsChanged`; while held with a
  selection (and not dragging), `drawMeasurements` shows red measure lines + point
  labels: H/V gaps between the selection box and the hovered shape, or the four
  distances to the artboard edges when hovering empty space. Works in document and
  source scopes. Also logged a refinement-backlog note to separate the Align-to
  dropdown from the distribute buttons (owner mis-clicked).

- **2026-06-11 — Session 56 (align & distribute):** Phase 11 kickoff. `AppState.alignTarget`
  (Selection | Artboard) drives the reference rect. `CanvasNSView` gained `align(_:)` (six
  edges/centers) and `distribute(horizontal:)` (equal-gap spacing, extremes pinned, 3+),
  each one undo step on the scoped node list. Reference = selection union, or — in Artboard
  mode — the board owning the selection (single-item align works there too). UI three ways:
  an Inspector "Align" row (six align buttons + two distribute + an Align-to picker, shown
  for any selection, distribute disabled <3, align disabled for a lone item in Selection
  mode), an Arrange-menu block, and `validateMenuItem` gating. Owner chose the Illustrator-
  style toggle over Figma-auto. Next in Phase 11: ⌥-hover spacing measurements, guides.

- **2026-06-11 — Session 55 (outline winding + hit-test):** Two font-dependent bugs in
  convert-to-outlines. (1) Letters showed gaps where contours overlap (an 'e' bar, grunge
  faces) — caused by **even-odd** fill subtracting overlaps. Switched multi-contour paths
  to **nonzero** winding (the rule fonts are designed for) on canvas, PNG/PDF, and SVG
  (dropped `fill-rule="evenodd"`). (2) Only a tiny piece of a glyph was clickable — path
  hit-testing only checked the first contour. Multi-contour paths now hit-test against
  their tight bounding box, so a letter is grabbable anywhere. (3) Point editing was
  first-contour-only — refactored the Edit-Points subsystem to be contour-aware:
  `PathPointTarget` carries a `(contour, index)` address; new `PathShape.editContours`
  / `editPoint` / `mutatePoint` / `contourClosed` helpers route reads & writes to the
  right contour (mirroring `points` to the first). `hitTestPathPoint`, `drawPathPoints`,
  `pathPointDrag`, and the corner/curve toggle now cover every contour; `normalizePath`
  skips multi-contour glyphs (keeps the conversion box). So all sub-shapes of a glyph —
  the inside of an 'o', every piece of a grunge face — are now editable.

- **2026-06-11 — Session 54 (outline refinements):** Owner feedback on convert-to-
  outlines: (1) bounds should hug the ink, not the text frame; (2) only the first
  letter was selectable; (3) want one shape per letter, auto-grouped + ungroupable.
  Rebuilt the outliner as `outlineGlyphs(in:)` returning ONE `GlyphOutline` per glyph
  (character, color, tight `boundingBoxOfPath`, box-relative contours). Convert now
  makes one path node per glyph at its tight box and auto-groups them with the same
  convention as `group()` (union frame + children offset by -union.origin), so each
  letter selects independently and Ungroup splits them. Single glyph → lone node.

- **2026-06-11 — Session 53 (convert text → shapes + CSS shadow sign, checkpoint 3 —
  batch complete):** (1) Shadow Y now matches CSS — negated the CG shadow height in
  the flipped context so +Y reads as *down* (SVG `feOffset` already was). (2)
  Convert-to-outlines: new `PathShape.contours` (optional multi-subpath, even-odd
  fill, backward-compatible decoder) + `renderContours`/`isMultiContour`; canvas
  `bezierPath`, export `nsPath`, and SVG `svgPathData` all honor it (SVG adds
  `fill-rule="evenodd"`). `TextContent.outlineContours(in:)` uses Core Text to glyph-
  outline the laid-out, case-applied text grouped by run color → flipped to local
  y-down → `[PathPoint]` contours (quads promoted to cubics). `convertSelectedText
  ToShapes` replaces the text node with one path (or a group per color), carrying
  rotation/opacity/effects; right-click + Format ▸ ⇧⌘O. This completes the
  typography + effects batch (opacity, case, shadows, outlines).
- **2026-06-11 — Session 52 (drop + inner shadow, checkpoint 2):** New shared
  `EffectsRender` (Color/EffectsRender.swift) with a `Silhouette` helper. Drop shadow
  = stamp the shape outline (or the node's own content for text/lines/groups) into a
  CG-shadowed transparency layer, then draw the real node on top; inner shadow = clip
  to the shape and cast the color inward. Wired into the canvas (`drawNode` split into
  effect passes + `drawNodeContent`), raster export (`drawExportNode` split likewise),
  and SVG (`svgEffectsFilter` → `<filter>`). Inspector gained an "Effects" section
  (add Drop/Inner, per-effect enable/type/color/X/Y/Blur/Spread, remove) for any node
  type. `numericStepping` gained a `max:` clamp. Next: convert text → shapes (last).

- **2026-06-11 — Session 51 (typography + effects batch, checkpoint 1):** Owner asked
  for the rest of typography + basic effects; doing it in order (opacity → case →
  shadows → text-to-shapes), checkpointing between. **Model foundation (all four):**
  `Node` gained `opacity` + `effects` with a custom decoder (also hardens the old
  `rotation` default); new `Effect` type (drop/inner shadow, CSS box-shadow geometry);
  `TextContent.textCase` (CSS text-transform). **Shipped this checkpoint:** (1) Layer
  opacity — model + grouped-transparency render on canvas/PNG/PDF + SVG `opacity` +
  Inspector 0–100%. (2) Case transforms — non-destructive, display-only via
  `displayStrings()`/`attributedString(applyCase:)`, editor edits originals, Inspector
  picker. Next: drop/inner shadow, then convert-text-to-shapes.

- **2026-06-11 — Session 51 (fresh-eyes text commit fix):** Revisited the text
  bug loop from first principles. The "Undo brings the size change back" symptom
  points to a stale focus-loss commit overwriting a newer Inspector/edit state.
  Tightened the split in two places: (1) Inspector font/size/color setters now
  route off the live `app.applyTextStyle` hook directly, instead of trusting
  `app.textSelection` as the "are we editing?" flag (that published style can be
  nil/stale during first-responder churn). (2) `commitTextEditing()` now first
  makes the `NSTextView` first responder again, while the hook is still installed,
  so a pending Inspector text-field value (e.g. Size) commits into the editor
  before the editor snapshot is read. Also guarded deferred selection-style
  publishes so an async selection update cannot resurrect `app.textSelection`
  after the editor has been torn down. For the edit↔view metric jump, switched
  committed canvas text drawing from `NSAttributedString.draw(in:)` to a small
  TextKit (`NSTextStorage`/`NSLayoutManager`/`NSTextContainer`) draw path with
  zero line-fragment padding, closer to the live `NSTextView`. Deliberately did
  **not** reintroduce the Session-44/45 custom-bounds `NSTextView` crash path.
  Verified with `xcodebuild -project "EXP [design].xcodeproj" -scheme "EXP [design]"
  -configuration Debug -destination "platform=macOS" -derivedDataPath
  /private/tmp/exp-design-derived build` → **BUILD SUCCEEDED**. Watch in-app:
  partial selection size change should persist on direct click-out; any remaining
  metric jump is expected to be smaller at 100% but may still need the future
  NSScrollView/magnification editor approach for non-100% zoom.

- **2026-06-11 — Session 50 (synchronous Inspector→editor apply):** The Session-48/49
  fixes didn't take — changes still only stuck if you collapsed the selection first,
  and the *"Publishing changes from within view updates"* warnings persisted. Root
  problem was the **indirection itself**: the Inspector set `app.textStyleOp`, and the
  canvas applied it later on a deferred tick keyed off `updateNSView`. That tick was
  racing the commit and depending on view-update timing. Replaced the whole channel
  with a direct synchronous hook: `AppState.applyTextStyle: ((TextStyleOp)->Void)?`
  (`@ObservationIgnored`), installed by `beginEditingText`, torn down in
  `commitTextEditing`. Inspector control handlers now call `app.applyTextStyle?(op)`
  and the editor is mutated **immediately**, in the same user-event turn — no async,
  no `updateNSView` dependency, no commit race. Combined with the Session-49
  `editorSelectedRange` (targets the real selection even after the Inspector steals
  focus), a size/color/bold change made on a selection now persists on a direct
  click-out. Removed the deferred-apply block from `updateNSView` and the dead
  commit-time flush. _Unrelated, still open: the launch-time state-restoration error
  ("symbol export list" UTType) — autosave trying to reopen a doc; benign but noisy._

- **2026-06-11 — Session 49 (the real "changes lost on click-out" fix):** Inspector
  style changes (size/color/bold/italic/underline) made on a *selection* were lost
  unless you first re-clicked into the editor to collapse the selection. Root cause:
  clicking an Inspector control resigns the `NSTextView`'s first responder, which
  **collapses its live `selectedRange()` to a caret**. The style op (applied on a
  deferred tick / at commit) then read that collapsed range → wrote *typing
  attributes* instead of the selected characters → commit rebuilt the model from an
  unchanged editor → change gone. Fix: remember the last *focused* selection
  (`editorSelectedRange`, updated in `textViewDidChangeSelection` only while the
  editor is first responder) and target it via `effectiveEditorRange()` in
  `applyTextStyleOp`, `applyFontTrait`, `toggleUnderlineText`, and
  `publishTextSelection`; the op also re-asserts that range with `setSelectedRange`
  so the change is visible and the highlight persists. No more need to deselect
  first.

- **2026-06-11 — Session 48 (rich-text fixes):** Three follow-ups. (1) Residual
  *"Publishing changes from within view updates"* — `publishTextSelection()` (called
  from AppKit's `textViewDidChangeSelection`, which can fire during the window's
  layout pass) now writes `app.textSelection` on the next runloop tick via a new
  `setTextSelection(_:)` async helper instead of inline. (2) *"Picker: the selection
  '' / 'Zapfino' is invalid"* warnings — replaced the weight/face `Picker` (which
  reconciles + writes back a missing tag) with a `Menu` of Buttons calling
  `applyFontName`; no selection binding, no write-back. (3) Line-height / alignment /
  letter-spacing only applied **after** the box was deselected — added a `.paragraph`
  `TextStyleOp` case. Extracted `TextContent.paragraphStyle(scale:)` so the canvas can
  re-apply the model's paragraph style to the live `NSTextView` while editing;
  `updateTextContent` fires `.paragraph` whenever `isEditingText`. _Still open: the
  slight edit↔view metric jump at non-100% zoom (scaled-font editor vs CTM render);
  case transforms + convert-to-shapes._

- **2026-06-11 — Session 47 (fix):** Selection size change leaked to the whole node
  on click-out. Cause: the style op is applied on a deferred tick (crash fix). If you
  clicked out before that tick, `commitTextEditing` ran first (`editingNodeID` nil),
  then the queued op took the **whole-node** model path + registered its own undo
  step (hence ⌘Z revealed the correct partial edit). Fix: `commitTextEditing` now
  flushes any pending `textStyleOp` into the editor selection first, then clears it,
  so the queued apply no-ops. Both orderings now apply only to the selection.

- **2026-06-11 — Session 46 (REAL crash fix):** Crash log showed endless
  *"Publishing changes from within view updates"* → infinite Update-Constraints pass
  → `NSGenericException`. Cause: `CanvasView.updateNSView` applied `app.textStyleOp`
  **inline during the SwiftUI update**, and `applyTextStyleOp` publishes
  `app.textSelection`. The op wasn't cleared until an async hop, so each re-render
  re-applied it → publish → invalidate → loop. Fix: defer the apply to
  `DispatchQueue.main.async` AND clear `textStyleOp` first (so a re-entrant update
  can't re-schedule). Also guarded the weight/face `Picker` to only show when its
  selection matches a real face (kills the "selection 'Zapfino' is invalid" /
  empty-tag warnings + their layout churn). (The Session-45 bounds-editor revert was
  a red herring — kept on the safe scaled-font path anyway.) Side note: the
  "symbol export list" state-restoration error is a benign `.exp` UTType clash with a
  system dev type — cleanup later (LSHandlerRank/Owner). **No compiler in chat.**

- **2026-06-11 — Session 45 (crash revert):** App froze+crashed — reverted the
  Session-44 **scaled-bounds NSTextView** (a custom-`bounds` text view outside an
  NSScrollView can send TextKit into a layout loop / assertion). The fixed/paragraph
  editor is back on the proven **scaled-font** path (`textEditScale = zoom`). Also
  removed the per-`updateNSView` commit-poll (mutating the document inside the
  SwiftUI update cycle is reentrancy-prone). Kept the safe Session-44 wins:
  selection-level font size (commit-on-blur removed) and line-height units. Net:
  the edit↔view line-height jump is back to "slight" (the supported fix later is an
  NSTextView in an NSScrollView with `magnification = zoom`, not a bounds hack).
  (Couldn't read the user's crash log from here — project-folder access only.)

- **2026-06-11 — Session 44 (text fixes + line-height units):** (1) **Independent
  font size on a selection now works** — the editor was committing on focus loss, so
  clicking the size field ended editing and dropped the selection. Removed
  commit-on-`textDidEndEditing`; the editor now keeps its selection while you use the
  Inspector and commits on real triggers (canvas click outside, or selection moving
  to another node via `commitTextEditingIfSelectionChanged`). (2) **Line-height
  units** (CSS-style): `LineHeightUnit` = auto / × (unitless, scales with text) / px
  / em, applied in the paragraph style with scale; Inspector unit picker + value.
  (3) **Double-click line-height jump**: the fixed/paragraph editor now lays out at
  TRUE size and scales the VIEW (frame vs bounds) so its wrapping + line metrics
  match the canvas render exactly (`textEditScale` tracks the editor's font scale:
  1 for fixed, zoom for auto). **No compiler in chat.** Watch: the scaled-bounds
  NSTextView for fixed boxes (cursor/caret placement, overflow clipping), and that
  size/font ops still divide by the right scale on commit.

- **2026-06-11 — Session 43:** **Rich text Build 2 (paragraph) + zoom-stable text.**
  Fixed the zoom "hopping": text now lays out at TRUE size and the canvas scales the
  *drawing* (CTM translate+scale, draw in local doc-size rect), so wrap points and
  line height are identical at every zoom (and `draw(in:)` clips a fixed box = the
  crop). Paragraph features: **Auto/Text-box toggle** + **drag-to-create** a fixed
  box with the text tool (`.drawTextBox` drag mode; click = auto, drag = fixed);
  auto hugs, fixed keeps its user size (no height auto-grow → can overflow). Added a
  **red "+" overflow badge** at the box bottom-right when content exceeds a fixed
  box. Added inspector **alignment (L/C/R), line height, letter spacing** (paragraph
  style already in `attributedString`). Selection font-size already works via the
  Session-42 channel. **No compiler in chat.** Remaining Build 2: case transforms +
  convert-to-shapes. Watch: drawTextBox click-vs-drag threshold, fixed-box overflow
  measure, and the CTM text scaling composing with node rotation.

- **2026-06-11 — Session 42 (rich-text fixes):** Fixed the inspector-vs-editor split.
  Font family / face / size / color edited the *model* while the live editor owned
  the text, so they didn't show and were overwritten on commit (only the B/I/U
  buttons worked, since they edit the editor). Added a **style channel**:
  `AppState.textStyleOp` (Inspector → editor selection or whole node, applied in
  `updateNSView`) and `AppState.textSelection` (canvas publishes the selection's
  style on every selection/text change). Inspector controls now read/write the
  selection while editing and the node otherwise; **"Multiple"/Mixed reflects the
  actual selection**, and B/I/U buttons show active state. Fixed **system-font
  styles dropping on commit** (`nsFont` rebuilds bold/italic from the stored name
  when `NSFont(name:)` can't reload a system variant). Double-click now **places
  the caret at the click point** (was jumping to the end), and the editor gets a
  line of slack + a measure pad so the **last line no longer clips**. **No compiler
  in chat.** Watch: the op channel clear (async, no loop), selection summary on
  empty selection (typing attributes), and caret placement before layout.

- **2026-06-11 — Session 41 (fix):** **Paragraph text width was lost on font change.**
  Auto boxes re-measure to a tight single line, so changing the font collapsed a
  resized (wrapped) box back to one line. Pulled the fixed-width box forward from
  Build 2: resizing a text box now sets `box = .fixed`; `measuredSize(boxWidth:)`
  keeps the width and grows height for fixed boxes (auto still hugs); the inline
  editor wraps to the box width; commit preserves it. Explicit line/paragraph
  toggle + drag-to-create remain for Build 2.

- **2026-06-11 — Session 40:** **Rich text — Build 1 (foundation + B/I/U).** Replaced
  plain-string `TextContent` with **styled runs** (`TextRun`) + paragraph props
  (align/lineHeight/tracking/box); backward-compatible Codable (old text → one run).
  New NSAttributedString bridge in `Typography.swift` (`attributedString(scale:)` +
  `init(attributed:…)` rebuilding runs, dividing zoomed sizes back out). Threaded
  through canvas draw, the **rich** inline `NSTextView` (selection works; commit →
  runs), text measuring, PNG/PDF export, and SVG (`<tspan>` per run). **Bold/Italic/
  Underline** via a new **Format menu (⌘B/⌘I/⌘U)** + inspector buttons — selection
  while editing (mutate textStorage), else whole node (toggle all runs via
  NSFontManager traits). Removed the inspector text field (item 1); whole-text
  typeface/size/color show **"Multiple"** when runs differ. **Build 2 next**:
  line/paragraph box + drag, cropped indicator, alignment/line-height/letter-spacing,
  case transforms, selection font-size, convert-to-shapes. **No compiler in chat.**
  Watch: legacy decode (old `.exp` text), attributed↔runs round-trip (esp. system
  vs named faces + size un-scaling), and ⌘B reaching the field editor while editing.

- **2026-06-11 — Session 39:** **Phase 9 — Typography.** `TextContent.fontName`
  (PostScript face; empty = system; defaulted → old files load). New
  `UI/Typography.swift`: `FontCatalog` (cached families/faces via NSFontManager) +
  `TextContent.resolvedFont(scale:)`, `measuredSize()`, `familyName`. Inspector
  text controls gained a **typeface menu** (each family rendered in its own face)
  and a **weight/style Picker**. Routed the resolved font through canvas text draw,
  the inline NSTextView editor, text box measuring (replaced the old system-font-
  only `measureText`/`textSize`), PNG/PDF export, and SVG (`font-family` +
  bold/italic from symbolic traits). **No compiler in chat.** Watch: font menu
  build with many families (cached static), face Picker tag matching the stored
  PostScript name, and measured box sizing with non-system fonts.

- **2026-06-10 — Session 38 (fix):** **Paths resizable/rotatable on canvas + bounds
  toggle.** Root cause of both reported bugs: paths drew only their outline and
  returned early in `drawNodeSelection`, so they had no box, handles, or rotate
  knob — making ⇧⌘B look broken (nothing to toggle when a path was selected) and
  leaving paths only editable via the Inspector. Fix: `isBoxResizable` now includes
  `.path`; the path case draws its outline AND falls through to the box + 8 handles
  + rotate knob. Added **path resize**: a `resizePathBaseline` captured at grab,
  scaled to the new frame (points + bézier handles) so dragging a corner scales the
  path (works rotated too via the existing world-anchor correction). `showSelection
  Bounds` still gates only the thin box outline; handles/knob always show.

- **2026-06-10 — Session 37 (fix):** **Rotated path/point editing.** Pen add-point,
  point drag, bezier-handle drag, anchor hit-testing, and the anchor overlay all
  converted the cursor to path-local space without undoing the node's rotation, so
  points landed at the unrotated location. Added `docToLocal`/`localToDoc` (inverse/
  forward rotation about the node center) and routed every path-edit conversion
  through them. Also fixed `normalizePath`: re-basing the bbox moves the rotation
  pivot, so it now shifts the frame by `(R−I)(Δcenter)` to keep a rotated path
  visually put after edits.

- **2026-06-10 — Session 36:** **Gradient overrides + Rotation.** (1) Component fill
  **overrides now carry gradients**: `InstanceOverride.Value.fill` → `Paint`,
  override UI uses `PaintWell` (legacy solid overrides decode unchanged via Paint's
  RGBAColor path). (2) **Rotation** (Phase 8.5): new `Node.rotation` (deg, CW about
  center, defaulted so old files load). Rendered via CTM rotate on canvas + export,
  and `<g transform="rotate cx cy">` in SVG. Interactions: `nodeHit` inverse-rotates
  the cursor; `drawNodeSelection` draws the box/handles/path-outline inside the
  rotation and adds a **rotate knob** above top-center; new `.rotate` drag sets the
  angle from the cursor (Shift snaps 15°); **rotated resize** transforms the cursor
  to local space and re-pins the opposite corner in world space (`anchorPoint` +
  correction). Inspector gained an **R°** field (stepping). Works in the source
  editor too (shared scope-aware RightPanel + canvas). **No compiler in chat.**
  Watch: rotation sign/flip convention (CTM vs hit-test vs knob angle), rotated
  resize anchor math, and that the knob hit-target tracks the rotated position.

- **2026-06-10 — Session 35:** **Phase 8 build 2 — gradients.** New `Paint` enum
  (`Model/Paint.swift`: `.solid | .gradient`, `GradientFill` = linear/radial +
  multi-stop + angle) now backs rectangle/ellipse/path fills and `Artboard.background`.
  **Backward-compatible Codable**: a solid encodes as a bare `RGBAColor` so existing
  `.exp` files load unchanged; only gradients add a tagged object. Shared
  **`PaintRender`** (CoreGraphics) draws solid+gradient identically on the canvas and
  in the export NSView (so PNG/PDF match); **SVG** gained `<defs>` with
  linear/radial gradients in objectBoundingBox units. New **gradient editor**
  (`Color/PaintEditor.swift`: `PaintWell` + `PaintEditor` + `GradientBar`) — Solid/
  Linear/Radial segmented, stop bar (drag-add/move, select, delete, min 2), stop
  color+position, angle for linear — wired into shape & path fills + artboard bg
  wells. Instance fill overrides pass `representativeColor` (stay solid). Text fill
  stays solid (gradient text + on-canvas handles deferred). **No compiler in chat.**
  Watch: (1) Paint legacy decode (`try? RGBAColor(from:)` path), (2) gradient clip/
  geometry on canvas vs export vs SVG angle, (3) the stop-bar drag add/move gesture,
  (4) the solid↔gradient mode conversion seeding.

- **2026-06-10 — Session 34 (fix):** Component fill overrides now recognize
  **pen-made paths** — added a `.path` case to `ComponentInstance.applyingOverrides`
  (so a path child's fill override actually renders) and to the instance override
  list in the Inspector (a fill `ColorWell` per path child, like rect/ellipse).

- **2026-06-10 — Session 33:** **Inspector in the source-component editor.** Made
  `RightPanel` scope-aware (`scope: CanvasScope`): reads `scopedNodes` (document
  nodes vs a source's children) and writes through one `commitScoped` funnel; all
  eight edit paths (dims, rename, text, line, instance, corner, shape fill/stroke,
  path) now route through it, and `ownerOffset`/`selectedArtboard` no-op in source
  scope. Added `RightPanel(scope: .source(id))` as a third column in the source
  editor window (widened to 880×520, min 760) — so the custom color wells + all
  styling now work on component-source children, updating every instance live.
  **No compiler in chat.** Watch: source-window undo routing through the shared
  manager, and that selecting a source child shows/edits its styling correctly.

- **2026-06-10 — Session 32:** **Phase 8 build 1 — custom color picker + formats +
  OKLCH + artboard background.** New `Color/ColorMath.swift` (sRGB ↔ HSB/HSL/CIE-LCH/
  OKLCH + HEX, lenient parsers/formatters) and `Color/ColorPopover.swift`
  (`ColorWell` swatch button → popover with SV field, hue/alpha sliders, eyedropper
  via `NSColorSampler`, and a format-selector + editable/copyable code field for
  HEX/RGB/HSL/LCH/OKLCH). Replaced **every** SwiftUI `ColorPicker` in the Inspector
  (text/line/shape fill+stroke, path fill+stroke, instance fill overrides) with
  `ColorWell`; bindings are now `Binding<RGBAColor>` (no lossy Color round-trip).
  Added **`Artboard.background`** (backward-compatible decoder, default white),
  rendered on the canvas and in PNG/PDF/SVG export, with a "Background" well in the
  Inspector. Model stays sRGB; OKLCH/LCH authoring converts to gamut-clamped sRGB.
  **Gradients = build 2 (next).** **No compiler in chat.** Watch: color-space round
  trips (esp. OKLCH/LCH parse), popover open not registering a spurious undo (push
  only on user edit), swatch alpha checkerboard, and per-drag undo volume (known).

- **2026-06-10 — Session 31:** **Phase 7 — Inspector & input polish.** (1) Reusable
  `NumericStepping` view modifier: ↑/↓ ±1, ⇧ ±10, ⌥ ±0.1, hold-to-accelerate
  (grows every 5 repeats); attached to all numeric inspector fields + zoom %.
  (2) Inspector **layer rename** field (synced to Layers via the shared model);
  `dimensions()` title now optional. (3) **Zoom cluster** in the RightPanel —
  editable %, preset menu (Fit/Actual/25–400), log slider, ± buttons — plus View-
  menu shortcuts ⌘+/⌘-/⌘0 (Actual)/⌘1 (Fit). Centered-zoom math lives in
  `AppState.zoomTo` using `viewportSize` reported by `CanvasNSView.layout()`;
  canvas `zoomInAction`/`zoomOutAction`/`zoomActualAction` selectors. **No compiler
  in chat.** Watch: ⌘+ shortcut resolution, the `onKeyPress(phases:)` repeat
  acceleration, and that inspector zoom edits keep the view centered.

- **2026-06-10 — Session 30 (planning):** Organized the owner's big polish list
  into **Phases 7–16** (see "Polish roadmap" above). Order = value/effort: 7
  Inspector/input polish (universal stepping, inspector rename, zoom cluster) →
  8 Color & gradients (inline popover, HEX/RGB/HSL/LCH/OKLCH, gradients, artboard
  bg) → 9 Typography (font preview) → 10 Effects (shadows, opacity; blend modes
  lower-pri) → 11 Layout/align/guides → 12 Command-coverage & full menu bar →
  13 Workspace & dockable panels (LARGE; absorbed the old "V2 panels" + settings/
  saved views) → 14 Images (low-pri) → 15 Auto-layout/padding (BIG) → 16 Masks/
  outline-stroke/type-to-shapes (BIG). Folded the stray "Future styling" stub into
  8/9/10. No code this session — next: build, starting with Phase 7.

- **2026-06-10 — Session 29:** **Notes editor upgrade.** Replaced the single-field
  notes input with an `NSTextView`-backed `NotesEditor` (+ `NotesTextView`): real
  multi-line editing — Return inserts line breaks, Tab/Shift-Tab indent/outdent
  (4 spaces), and bullet lines (`•`, `-`, `*`) auto-continue on Return (an empty
  bullet ends the list); leading indentation carries to the next line. Editor
  auto-grows to fit (reports `usedRect` height up to a cap, then scrolls) and the
  panel still resizes via the grip. Storage stays a plain `String` so it's
  Markdown-ready. Panel **size now persists per board across close/open**
  (`AppState.notesPanelSize`, keyed by id). The PDF notes page already renders the
  newlines/tabs/bullets as literal text. **No compiler in chat.** Watch: NSTextView
  first-responder focus on open, content-height reporting loop (guarded by a 0.5pt
  threshold), and Tab being captured by the editor rather than moving focus.

- **2026-06-10 — Session 28:** **Notes fixes.** (1) Notes toggle button was "way
  off" + appeared to drift on zoom: the overlay's `ZStack` was being centered by
  the bare `.overlay`, so its (0,0) sat at the canvas center, not top-left. Wrapped
  the overlay in a `GeometryReader` (+ fill frame, + `.overlay(alignment:.topLeading)`)
  so content origin = canvas top-left; `doc*zoom+pan` now matches the canvas at all
  zooms. (2) Removed the second "Notes" starter artboard — `Document.starter` is now
  a single "Artboard 1" (393×852) at the origin; the initial fit centers it.

- **2026-06-10 — Session 27:** **Phase 6 — Structured notes & handoff.** Notes now
  live on `Artboard.notes` (backward-compatible decoder; memberwise init keeps the
  `notes:` default) so they move/duplicate/delete with the board automatically.
  New **`ArtboardNotesOverlay`** (SwiftUI, layered over the canvas via `.overlay`,
  positioned with the same `docPoint*zoom+pan` transform): a small toggle button
  sits just left of each board's name label — **muted when empty, accent-bordered
  when it has content** (no notification badge) — and opens an editable panel that
  **expands down-and-to-the-left** (off the board), is **manually resizable** (a
  bottom-left grip) and **auto-grows** with the text (`TextField(axis:.vertical)`).
  Open/closed state is ephemeral (`AppState.openNotesArtboardIDs`); panel size is
  local `@State` keyed by board id. Export gained an **"Include notes"** checkbox
  (PDF only, both panels): renders a Letter "Notes — <board>" page after each board
  that has notes, merged via PDFKit (`NotesRenderView`, `notesPDFData`,
  `pdfData(includeNotes:)`, `multiPagePDFData(includeNotes:)`). **No compiler in
  chat.** Watch: (1) **overlay hit-testing pass-through** — confirm clicks in empty
  overlay areas still reach the canvas (top risk); (2) notes button/panel position
  tracking pan/zoom; (3) the resize grip base-size capture; (4) notes edits are
  per-keystroke undo (known, matches other text fields).

- **2026-06-10 — Session 26:** **Artboard refinements.** (1) **Rename** boards:
  Inspector name field, double-click label → inline `NSTextField` editor (commits
  on Return / focus loss), right-click ▸ Rename. (2) **Marquee fully enclosing**
  boards selects the boards (partial still selects items). (3) **Rearrange mode**:
  with 2+ boards selected, dragging inside any selected board moves the whole set
  + contents (gated to the select tool). (4) **Copy/paste artboards** via ⌘C/⌘V +
  context menu (boards + owned shapes, new ids); richer clipboard (`NodeClipboard`
  / `ArtboardClipboard`). (5) **Artboard-aware shape paste**: shapes paste onto the
  focused board at the same position relative to it, or centered when they don't
  fit. validateMenuItem + context menu updated for boards. **No compiler in chat.**
  Watch: inline-rename field commit/focus timing, paste reposition math (fit vs
  center), copy branch (boards-vs-nodes selection), and the rearrange-drag gate.

- **2026-06-10 — Session 25:** **Export options + Phase 5.5 artboard improvements.**
  Export round 2: format **popup** in the Save panel for a single board, and the
  all-artboards folder panel got a **format popup (PNG/PDF/SVG/All) + "Combine PDF
  pages into one file"** checkbox; multi-page PDF merges per-board single-page PDFs
  via **PDFKit** (`ExportPanels.swift`, `ExportRenderer.multiPagePDFData`). Then a
  cohesive artboard batch: (1) **size presets** (split New-Artboard menu, `Artboard
  Preset`); (2) **artboard resize** (8 handles, Shift = proportional; frame-only,
  wall re-derives ownership); (3) **multi-select boards** (`AppState.selected
  ArtboardIDs` Set + single-select wrapper; Shift-click labels; outline + Inspector
  count); (4) **multi-move** (drag/arrows/delete act on all selected boards + their
  owned shapes, Shift axis-lock); (5) **Option-drag duplicates** boards + contents
  (one undo). **Export Selected** now does 1 board → save panel, 2+ → folder+format
  +combine. **Notes feature deferred to Phase 6** with a full design spec recorded
  above (notes live on the Artboard, a left-of-name toggle button, expand down-left,
  auto-grow, "include notes" on export). **No compiler in chat.** Watch: the
  `selectedArtboardID` compatibility wrapper at the ~25 call sites, artboard handle
  hit/resize math, option-duplicate undo (restores baseline = removes copies), and
  the export-panel accessory enabling/disabling the combine checkbox.

- **2026-06-03 — Session 24:** **Pen/path refinements.** (1) Layers **Rename**
  now focuses + select-all (type to replace; Esc cancels) via `@FocusState` +
  `selectAll:` to the field editor. (2) **Pen adds points to existing geometry**:
  with no active pen path, clicking an existing path/shape/line inserts a corner
  anchor on the nearest segment (basic shapes auto-convert to a path first); the
  cursor shows the "+" (dragCopy) badge when hovering addable geometry. Once a
  path is in progress, clicks continue it as before. (3) Right-click an anchor →
  **Make Curved / Make Corner** (adds symmetric tangent handles or strips them).
  (4) **Bounding box rework**: selected paths now trace their actual outline (no
  misleading square); box shapes' outline is gated behind `AppState.showSelection
  Bounds`, toggled via **View ▸ Toggle Selection Bounds (⇧⌘B)** (a Settings panel
  will own it later). **No compiler in chat.** Watch: rename select-all timing,
  pen add-point insert index, and the anchor right-click menu. **Owner: build &
  report.** Next: **Phase 5 — Export.**

- **2026-06-03 — Session 23:** **Vector paths + Pen tool (build 2 of the batch).**
  New `NodeContent.path(PathShape)` — anchors (`PathPoint`: point + optional
  bezier `controlIn`/`controlOut`, nil = corner), `closed`, fill/stroke/width;
  anchors stored LOCAL like LineShape, frame = anchor bbox (`normalizePath`
  re-bases, absolute-invariant). **Pen tool** (P): click = corner, click-drag =
  symmetric handles in one motion, click first anchor (≥2 pts) = close; the path
  builds live in the model, Return/Esc/tool-switch finishes (one undo). **Edit
  Points** tool (A, direct-selection): drag anchors (handles follow) + bezier
  handles; anchor/handle overlay drawn for the selected path (and the in-progress
  pen path). **Convert to Path** (right-click) turns rect→4 corners, ellipse→4
  kappa-bezier anchors, line→2 anchors. Path rendering via NSBezierPath (cubic;
  missing handle = straight). Inspector: path fill (when closed), stroke
  color/width, closed toggle. Path hit-testing = point-in-polygon (closed) or
  distance-to-polyline (open). **HUGE unverified batch — no compiler in chat.**
  Likely snag spots: pen handle math / normalize, the new `DragMode` cases
  (`penHandle`/`pathPoint`), exhaustive `NodeContent` switches, and the
  `RightPanel` same-file `private` access in the path-controls extension.
  **Owner: build & report** — and this is the last thing before **Phase 5 —
  Export**. Deferred: add/remove anchors, line stroke in overrides.

- **2026-06-03 — Session 22:** **Shape styling (build 1 of the styling+vector
  batch).** Rectangle/ellipse gained **stroke** (`stroke` + `strokeWidth`, where
  0 = no stroke) — rendered (fill then stroke on the same path) and editable in
  the Inspector; rect **corner radius** now has a field; **fill color pickers**
  added for rect/ellipse. One shared `updateShape` path edits fill/stroke/width
  for both via a tiny `ShapeStyle` helper. Added **backward-compatible decoders**
  for RectangleShape/EllipseShape (decodeIfPresent) so files made since the last
  format change still open. Owner asked for the whole styling+vector list "in one
  pass," but with no compiler in chat I'm shipping it in TWO back-to-back builds
  to keep it debuggable: **this build = styling**; **next build = Pen tool +
  editable Path + point editing + Convert to Path + path inspector**, then Phase
  5 (export). **Owner: build & report.**

- **2026-06-03 — Session 21:** **Bounded overrides → Phase 4 COMPLETE.**
  Per-instance **text + color overrides** (`InstanceOverride`, was already in the
  model). Added `ComponentInstance.applyingOverrides(to:)` + `textOverride`/
  `fillOverride` helpers; rendering and Detach now bake overrides in. **Inspector
  UI:** select an instance → an "Overrides" section lists the source's text
  layers (editable multi-line text fields) and rect/ellipse layers (color
  pickers), each with a reset-to-source button (drops the override → re-inherits).
  Overrides target top-level source layers for now (nested layers + line stroke =
  later). So components now do real variations: same source, different copy/colors
  per instance, plus per-instance layer visibility. **Phase 4 done; next is Phase
  5 — Export (PNG/PDF/SVG).** **Owner: build & report.** Watch: ColorPicker ⇄
  RGBAColor round-trip and the text-field override binding.

- **2026-06-03 — Session 20:** **Per-instance visibility is now a true override.**
  The old `hiddenLayerIDs` (could only hide, gated by the source's `isVisible`)
  is replaced by `ComponentInstance.layerVisibility: [LayerVisibilityOverride]`
  ({layerID, isVisible}). Effective visibility = the override if present, else
  the source layer's own `isVisible` — so an instance can **show a layer that's
  hidden in the source** and vice-versa. Toggling that matches the source default
  drops the override (re-inherits, follows future source edits). Render, the
  panel rows, and detach all use `inst.isLayerVisible(_:sourceDefault:)`.
  **HEADS-UP: old `.exp` files with component instances that had `hiddenLayerIDs`
  won't decode** (field renamed) — make fresh ones. **Owner: build & report.**
  **Phase 4 remaining: bounded text/color overrides.**

- **2026-06-03 — Session 19:** **Layers tree (expand/collapse) + Group menu fix +
  visibility-sync bug.** (1) Fixed the per-instance row eye icon: now reflects
  EFFECTIVE visibility (`!child.isVisible || hiddenLayerIDs.contains`), so a
  source layer hidden by default reads as hidden on the instance too. (2)
  **Expand/collapse** in the Layers panel via a recursive `LayerOutlineRow` +
  `DisclosureGroup`: group rows reveal their children; instance rows reveal the
  source's layers with the per-instance eye toggles (replaces the old
  on-selection "Component ·" section — now inline). Edits recurse the tree
  (`updateNodeTree`/`findNode`) so nested group layers toggle/rename correctly.
  Nested drag-reorder still deferred (top-level reorder unchanged). (3) **⌘G /
  ⇧⌘G now actually group/ungroup** — the problem was ⌘G = system "Find Next"
  eating the key before the canvas. Added an **Arrange menu** (App `.commands`)
  that routes ⌘G/⇧⌘G (+ bring/send order, Create/Detach Component) through the
  responder chain via `NSApp.sendAction`, and removed the text-find command group.
  **No compiler in chat — sizable Layers rewrite + new menu.** Watch: DisclosureGroup
  inside List(selection:)+onMove behavior, and whether ⌘G now triggers Group
  (vs Find). **Owner: build & report.** **Phase 4 remaining: bounded overrides.**

- **2026-06-03 — Session 18:** **Reorder shortcuts + per-instance visibility.**
  Wired ⌘[ / ⌘] (send backward / bring forward, one step, keeps multi-selection
  grouped) and ⇧⌘[ / ⇧⌘] (to back / to front); added Bring Forward / Send
  Backward to the right-click menu. **Per-instance layer visibility** (Phase 4
  box ✓): select a single instance and the Layers panel shows a "Component ·
  <name>" section listing the source's layers, each with an eye toggle that
  writes THIS instance's `hiddenLayerIDs` — hide a layer in one instance without
  touching the source or other instances; reflected live in render. Rows are
  non-selectable (`.selectionDisabled`). Only top-level source layers for now.
  **Phase 4 remaining: bounded overrides (text/color).** **Owner: build &
  report.**

- **2026-06-03 — Session 17:** **Fixed Layers drag "dead spots" + clunky
  selection.** Root cause: the custom per-row `.onTapGesture(count:1/2)` (our
  hand-rolled select + double-click rename) was fighting the List's drag-reorder,
  so dragging from over a row's text didn't initiate and rename felt off.
  Switched the Layers list to **native `List(selection:)`** (crisp click,
  Shift-range, ⌘-toggle, and drag-from-anywhere reorder all free) and moved
  **Rename to the row's right-click context menu**. Removed the custom
  `handleClick`/anchor selection path. Net: smoother reorder + selection. Trades:
  toggle is ⌘-click (was Option), rename is right-click → Rename (was
  double-click) — easy to revisit. Selection still two-way with the canvas via
  AppState. **Owner: build & report.** **Next:** per-instance visibility +
  overrides, and the ⌘[ / ⌘] reorder shortcuts.

- **2026-06-03 — Session 16:** **Detach Component** (the inverse of Create).
  ⇧⌘K or right-click → Detach Component replaces selected instance(s) with fresh,
  independent copies of the source's children at the instance's position; the
  source stays in the library for any other instances. Per-instance hidden
  layers carry over (copy `isVisible = false`). Works in both windows (scoped via
  `currentNodes`/`commitNodes`). NB: overrides aren't baked in on detach yet,
  since overrides aren't applied in rendering yet — revisit when overrides land.
  **Owner: build & report.** **Next:** per-instance visibility toggles +
  overrides.

- **2026-06-03 — Session 15:** **Source editor gets a Layers panel + window
  polish.** Generalized `LayersPanel` with a `scope`: in `.source` it shows a
  single flat group of the source's children (show/hide, lock, double-click
  rename, drag-reorder, selection synced to that window's AppState); `.document`
  unchanged. Added it to the source-editor window (tools · layers · canvas) and
  made the window layout fill (maxWidth/Height ∞, min 560×320) so the canvas
  pans/zooms like the main one rather than feeling pinned. The canvas pan/zoom
  is the same code as the main window (two-finger scroll both axes, pinch,
  space-drag, ⌘±, ⌘0 fit). **Backlog added:** (1) layer-reorder refinement +
  shortcuts ⌘[ / ⌘] (down/up) and ⇧⌘[ / ⇧⌘] (to back/front); (2) confirm
  horizontal-pan parity in the source window (owner saw vertical-only — if it
  persists it's likely the NSHostingController scroll path, to investigate).
  **No compiler in chat.** **Owner: build & report** — especially whether the
  source window now pans both axes and the Layers panel feels useful. **Next:**
  per-instance visibility toggles + bounded overrides (the variations/states
  groundwork), then the reorder shortcuts.

- **2026-06-03 — Session 14:** **Components round 2 — the source editor edits for
  real.** Big architectural move: the canvas is now **scope-parameterized**
  (`CanvasScope = .document | .source(UUID)`). All node access goes through
  `currentNodes` / `withNodes` / `commitNodes`, so the SAME `CanvasNSView` drives
  both the main window (document's top-level nodes + artboards) and the source
  editor (a source's `children`). Artboards/wall-clipping apply only in document
  scope; source scope draws a white source-bounds frame and fits to the source
  size. **Model:** `ComponentSource` now holds `{ size, children }` directly
  (was a `root` group node) — much cleaner for scoped editing. The source-editor
  window now hosts a live `CanvasView(scope:.source)` + its own ToolsStrip +
  own AppState; it shares the document's UndoManager via a window delegate
  (`windowWillReturnUndoManager`) so ⌘Z + Save behave. Edit a source → all
  instances update live (both windows observe the one document). **Deferred to
  next round:** an Inspector inside the source window (so stroke/font/color edits
  work there — currently only via canvas gestures + inline text), source-bounds
  auto-grow, then per-instance visibility toggles + overrides. **HEADS-UP: old
  `.exp` files with saved components won't open** (ComponentSource shape changed;
  fresh files fine). **No compiler in chat — large refactor (~25 call sites
  rescoped).** Watch: source-scope edits writing to the right array, undo across
  the two windows, and instance live-update. **Owner: build & report.**

- **2026-06-03 — Session 13:** **Phase 4 begins — components round 1.**
  **Create Component** (⌘K + right-click): wraps the selection into a
  `ComponentSource` (root group, children stored source-local) and drops an
  `.instance` node where the selection was. **Instances render** by resolving the
  source and drawing its root recursively at the instance's origin (honors
  `hiddenLayerIDs`); duplicate / copy-paste yields more true instances of the one
  source (clone keeps `sourceID`). Instances move/select like any node; box-resize
  is gated off for them (move-only) for now. **Source-editor window scaffolded**
  (`UI/SourceEditorWindow.swift`): double-click an instance (or right-click →
  Edit Component) opens a SEPARATE, movable, resizable NSWindow that shares the
  same ExpDocument, with a placeholder tools column + a live read-only SwiftUI
  `Canvas` preview of the source. It's AppKit-windowed (not a SwiftUI Window
  scene) specifically so it can share the document object → future edits will
  propagate to all instances and share undo. **Round 2:** wire real editing
  inside that window (its own canvas + tools), which needs the main canvas
  generalized to operate on an arbitrary node list (a source's children). Round
  3+: per-instance visibility toggles + bounded overrides (model already carries
  `hiddenLayerIDs` + `overrides`). **No compiler in chat.** Watch: the auxiliary
  NSWindow lifecycle (retained in `SourceEditorWindowManager`), instance render
  offset math, and clone preserving `sourceID`. **Owner: build & report.**

- **2026-06-03 — Session 12:** **Line tool + grouping.** Added
  `NodeContent.line(LineShape)` (endpoints stored node-local, frame kept as the
  tight bbox so moving moves the line; min-1pt so it can still be owned/clipped).
  **Line tool** (L): drag to draw, bare click = default 100pt line; renders as a
  stroked segment (round caps) clipped to its owner; hit-tested by distance to
  the segment; single-line selection shows **2 endpoint handles** to edit each
  end (re-bbox on drag); Inspector gets stroke **width** + **color**.
  **Group/ungroup:** ⌘G groups selected top-level nodes (children → group-local,
  frame = union), ⇧⌘G ungroups (children → doc coords, in place); both in the
  right-click menu with validation. Groups render via **recursive drawNode with
  an offset**, select/move/clip as a single unit, and hit-test only when over a
  child's real geometry. `nodeHit` recurses; box resize handles now gated to
  rect/ellipse/text only (lines use endpoint handles, groups none yet). This
  finishes the Phase 3 primitives box; pen/bézier path is explicitly a later
  subsystem. **Deferred:** nested group rows in the Layers panel, group
  box-resize. **No compiler in chat — biggish batch.** Watch: line endpoint
  drag math + bbox normalization, group/ungroup coordinate round-trips, and
  recursive group rendering offsets. **Owner: build & report.** **Next: Phase 4
  — components** (the reference-based subsystem).

- **2026-06-03 — Session 11:** **Text tool.** New `Tool.text` (T shortcut,
  i-beam cursor) in the tools strip. Click with the Text tool places a text node
  and immediately enters **inline editing** via an `NSTextView` overlay
  positioned over the node (transparent, matches font/color) — real cursor,
  selection, IME. Double-click an existing text shape to re-edit. Commit on
  click-away / scroll / zoom (one undo step: "Add Text" / "Edit Text");
  a brand-new node left empty is silently dropped. The node being edited is
  skipped in the canvas draw so only the overlay shows. On commit the box
  auto-measures to fit the text. **Inspector** (single text shape): editable
  text string, font **Size**, and **Color** (SwiftUI `ColorPicker` ⇄ `RGBAColor`
  via an sRGB bridge in the UI layer); size/string changes re-measure the box.
  Also logged the Layers Shift-click "clunky" feel in a new Refinement backlog.
  **No compiler in chat.** Watch: `NSTextView` overlay focus/commit cycle
  (delegate `textDidEndEditing` + the re-entrancy guard), and text rendering vs
  the editor's font at non-100% zoom. **Owner: build & report.** **Next:**
  line/path tool + group/ungroup, then **Phase 4 — components**.

- **2026-06-03 — Session 10:** **Layers panel** (`UI/LayersPanel.swift`), replaced
  the LeftPanel placeholder. A grouped `List`: one section per artboard (shapes it
  geometrically owns) plus a "Wall" section, **front-of-stack at top**. Each row
  has eye (visibility) + lock toggles, a type icon, and **double-click to
  rename**. **Drag-to-reorder** within a group, translated back to the document's
  global back-to-front z-order so other groups stay put. **Selection is two-way
  bound** to `app.selectedNodeIDs` — select in the panel ⇄ select on the canvas.
  Every edit (show/hide, lock, rename, reorder) is one undo step. Locked shapes
  already skip canvas hit-testing; hidden shapes already skip drawing, so both
  toggles "just work." **Still pending for the box:** group/ungroup folders.
  **No compiler in chat.** Watch: `List` multi-select + `.onMove` behavior on
  macOS, and double-click rename vs row selection. **Owner: build & report.**
  **Next:** Phase 3 remainder — text + line tools (and group/ungroup), then
  Phase 4 (components).

- **2026-06-03 — Session 9:** **The "wall" + geometric membership.** Shapes can
  now live outside artboards, on the canvas backdrop ("wall"). **Model refactor
  (formatVersion → 2):** shapes moved out of `Artboard.layers` into a single
  document-coordinate list `Document.nodes`; `Artboard` is now just id/name/
  frame. Ownership is **derived, not stored**: `Document.owningArtboard(of:)`
  returns the artboard covering >50% of a shape (else nil = wall). Rendering
  clips each shape to its live owner, so a shape **crops the instant >half of it
  crosses into a frame** and un-crops when it leaves — the snap-to-frame behavior
  you wanted (vs Figma). Dragging an artboard by its label carries the shapes it
  currently owns (drag + keyboard-nudge). You can now also **draw shapes on the
  wall**. Inspector shows X/Y **artboard-relative when a shape is owned**, else
  document coords; editing converts back. All prior interactions (multi-select,
  marquee, copy/paste, duplicate, option-drag, shift-constraints, resize, menu)
  rebuilt onto the single list. **HEADS-UP: old `.exp` test files won't open**
  (format changed; make fresh ones). **No compiler in chat** — large refactor,
  watch for any missed coordinate conversions. **Owner: build & report.**
  **Next: finish Phase 3** — line/path + text tools, then the Layers panel.

- **2026-06-03 — Session 8:** **Big interaction-polish batch (one cycle).**
  Selection is now **multi**: `AppState.selectedNodeIDs: Set<UUID>` (+
  `singleSelectedNodeID` convenience). Added **shift-click** to add/remove from
  selection and **marquee drag-select** on empty space (Shift = add). Move,
  nudge, delete, and the halos all act on the whole selection; resize handles
  show only for a single shape. **Clipboard:** responder `copy/cut/paste/delete`
  (so the standard Edit menu + ⌘C/X/V/⌫ work) via a custom pasteboard type
  (nodes as JSON, fresh UUIDs on paste, +10/+10 offset). **⌘D duplicate** and
  **Option-drag duplicate** (clone in place, drag the copy). **Shift
  constraints:** axis-locked move + aspect-preserving resize (anchored at the
  opposite corner/edge). **Cursors:** crosshair for shape tools, hand for
  space-pan, dragCopy when Option-hovering a shape, resize cursors over edge
  handles. **Inspector:** ↑/↓ bump a field by 1 (Shift = 10) to match the
  canvas; multi-selection shows a count. **Right-click menu skeleton**
  (`menu(for:)`): on a shape → Cut/Copy/Duplicate/Delete/Bring-to-Front/
  Send-to-Back; empty artboard → Paste/Select All; backdrop → Paste/Fit; with
  `validateMenuItem` enable/disable. Z-order (front/back) actually works now.
  **Behavior change you'll notice:** artboards now move by **dragging their name
  label** (dragging an artboard's empty interior starts a marquee instead).
  Did NOT add constrained draw (you opted out). **This is the largest unverified
  batch yet — no compiler in chat.** Likely snag spots: responder-action
  selectors (`selectAll(_:)` etc.) under the MainActor-default setting,
  `.onKeyPress` on the TextField, and the marquee/duplicate edge cases.
  **Owner: build & report** — paste any errors. **Next: finish Phase 3** —
  line/path + text tools, then the Layers panel.

- **2026-06-03 — Session 7:** **Inspector is now two-way.** X/Y/W/H are editable
  `TextField`s bound to the selected shape (or artboard); committing a value
  (Return / focus-out) writes back through `ExpDocument.setModel`, so the canvas
  moves/resizes and it's one undo step. Width/height clamped to ≥1pt; positions
  may be negative. Read path unchanged (fields still reflect drag/resize live).
  Built a small reusable `DimField`. **Owner: build & report.** Watch: does
  editing W/H resize from the top-left anchor as expected; does committing feel
  right (Return/Tab/click-away). **Couldn't compile here.** **Next: finish
  Phase 3** — line/path + text tools, then the Layers panel.

- **2026-06-03 — Session 6:** **Phase 3 underway — it draws now.** Added a fixed
  left **tools strip** (`UI/ToolsStrip.swift`) with Select / Rectangle / Ellipse
  (shortcuts V / R / O, Esc → Select), pinned outside the HSplitView per the
  v2 layout plan. AppState gained `tool` + `selectedNodeID` (both view state).
  Rewrote `Canvas/CanvasView.swift` around a single `DragMode` enum so exactly
  one thing happens per gesture: **draw** (drag a rect/ellipse into the artboard
  under the cursor; bare click = default 100×100; tool snaps back to Select after
  one shape), **move** (drag a selected shape), **resize** (8 handles, normalized
  so dragging past the far edge flips rather than going negative), plus the
  existing artboard move/select. Shapes render clipped to their artboard, in
  artboard-local coords; selection chrome (accent outline + handles) draws on top
  in view space so it's a constant size at any zoom. Every gesture is one undo
  step. Arrow-nudge + Delete now act on the selected shape if there is one, else
  the artboard. Inspector shows the selected shape's name + X/Y/W/H (artboard-
  relative). Added a `RGBAColor → NSColor` bridge in the UI layer (model stays
  UI-free). New default shapes are light grey so they read on the white artboard.
  **Couldn't compile here (no Swift toolchain) — careful hand-review.** Watch:
  hit-testing/selection feel, resize handle grab size, draw-into-artboard
  behavior when starting outside an artboard (currently ignored). **Owner:
  build & report.** **Next:** finish Phase 3 — line/path + text tools, then the
  **Layers panel** (order, visibility, lock, groups).

- **2026-06-03 — Session 5 (fix):** Save failed at runtime with "unable to save
  using this document type" — the exported `.exp` UTI wasn't registered because
  the `Info.plist` wasn't wired into the build (I'd left that as an optional
  manual step). Fixed directly: added `INFOPLIST_FILE = "Info.plist"` to both
  build configs (Info.plist lives at the project root, beside the .xcodeproj,
  kept out of the synchronized source folder so it isn't double-copied as a
  resource). Note: the build itself compiled fine — the MainActor-default vs
  ReferenceFileDocument concurrency worry did NOT materialize. `FileWrapper`
  initializer corrected to `regularFileWithContents:` during the build loop.
  After a clean build, Save/Open `.exp` should work and Finder should associate
  the type.

- **2026-06-03 — Session 5:** **Phase 2 COMPLETE — the document system.** Added
  `Model/ExpDocument.swift`, a `ReferenceFileDocument` wrapping `Document`;
  read/write is just `Document` ⇄ pretty-printed JSON (`.exp`). App scene is now
  a `DocumentGroup`, so New / Open / Save / Duplicate / Rename / Revert and
  multi-window all come for free. **Architecture shift:** the design data now
  lives in `ExpDocument.model` (the file); `AppState` was slimmed to pure view
  state (camera, selection, panel layout — none saved). The canvas takes both;
  all artboard edits route through `ExpDocument.setModel`, an undo-aware funnel
  that powers ⌘Z and (crucially for ReferenceFileDocument) marks the doc dirty
  so Save actually fires. Drag = one undo step; nudge/create/delete each
  register. **Project changes I made directly:** flipped the sandbox setting
  `ENABLE_USER_SELECTED_FILES` to `readwrite` (Debug+Release) — required or Save
  fails under the sandbox.
  **TWO MANUAL STEPS for you (optional, for Finder `.exp` association):**
    1. Target → Build Settings → search "Info.plist File" (`INFOPLIST_FILE`) →
       set to `Info.plist` (it's at the project root, beside the .xcodeproj).
    2. Leave "Generate Info.plist File" = Yes; Xcode merges. Then a clean build
       registers the `.exp` type with Finder.
  Skipping these is fine — New/Open/Save still work in-app without them.
  **Likely first-build snag to watch:** the project sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so `ExpDocument` is MainActor by
  default; if `ReferenceFileDocument` conformance complains about isolation on
  `snapshot`/`fileWrapper`/`init(configuration:)`, paste the exact error and
  I'll add the right `nonisolated` annotations. (Couldn't compile here — no
  Swift toolchain in chat.) **Owner: build & report.** **Next: Phase 3 —
  primitives & layers** (draw rectangle/ellipse/line/text inside artboards,
  selection/move/resize of nodes, the Layers panel).

- **2026-06-03 — Session 4:** **Phase 2 — document model (2 of 3 boxes).** Built
  the real model in `Model/Document.swift`: `Document → Artboards → Layers →
  Nodes`, all value-type + `Codable` + UI-free (imports only Foundation/
  CoreGraphics, so it can render, export, or be tested headless). It's
  **reference-based from day one** — a `Node` can be `.instance(ComponentInstance)`
  holding a `sourceID` (+ bounded `overrides` + per-layer `hiddenLayerIDs`)
  pointing at a document-level `ComponentSource`; instances reference, never
  copy. Added `RGBAColor` (Codable color → also makes SVG/CSS export trivial
  later). **Migration:** split persisted data from session state — `Document`
  is the file, `AppState` keeps camera/selection/panel layout (which won't be
  saved). Moved `Artboard` into the model (now carries `layers: [Node]`),
  repointed all canvas rendering/hit-testing/move/nudge/create/delete at
  `app.document.artboards`. Rendering behavior is unchanged (artboards still
  draw as frames; node drawing is Phase 3), so this was a low-risk swap of the
  data layer underneath. No disk I/O yet — but the model is Codable-ready and
  the file approach is **locked to native DocumentGroup + ReferenceFileDocument
  (JSON `.exp`)**. NB: couldn't compile here (no Swift toolchain in chat), so
  this is a careful hand-review — watch the build for Codable synthesis on the
  `NodeContent`/`InstanceOverride.Value` enums and CG-geometry Codable.
  **Owner: build & report.** **Next:** finish Phase 2 — adopt DocumentGroup /
  ReferenceFileDocument so New/Open/Save work; then Phase 3 primitives & layers.

- **2026-06-03 — Session 3 (cont.):** **Phase 1 complete.** Closed the two
  remaining boxes. Added the camera *inverse* transform (`viewToDoc`) and
  artboard **hit-testing**; click selects the artboard under the cursor (accent
  halo, respects system accent + increase-contrast), clicking empty space
  deselects. **Move:** drag a selected artboard (tracks cursor 1:1 in doc space
  at any zoom); arrow keys nudge 1pt, Shift+arrow 10pt. **Create/delete:** New
  Artboard toolbar button (⇧⌘N) adds one to the right of existing content;
  Delete/⌫ removes the selected one. **Tab / ⇧Tab** cycle selection (keyboard-only
  canvas navigation). Selection lives in AppState; the Inspector now shows the
  selected artboard's name + X/Y/W/H, proving selection round-trips AppKit→state→
  SwiftUI. Accessibility: full keyboard operability for select/move/create/delete,
  semantic + accent colors throughout. **Owner: build & report.** Watch for:
  ⇧⌘N not firing if the canvas isn't first responder; drag feel; whether Tab
  steals focus anywhere. **Next: Phase 2 — the document model** (Document →
  Artboards → Layers → Nodes, reference-based for components, instant-open file
  format).

- **2026-06-03 — Session 3:** Started Phase 1 (the canvas). Built the founding
  shared **AppState** (`Model/AppState.swift`) as an `@Observable @MainActor`
  class holding panel visibility, the camera (`zoom` + `panOffset`), and a
  minimal `Artboard` model — the single source of truth panels read/write,
  which both the v2 floating-panel plan and the component system need.
  Replaced the placeholder canvas with a real **AppKit-backed `NSView`**
  (`Canvas/CanvasView.swift`) wrapped in `NSViewRepresentable`, drawing
  artboards via Core Graphics. Full macOS-native **pan/zoom**: trackpad
  two-finger scroll pans, pinch zooms (toward cursor), space-bar+drag = hand
  tool, ⌘+ / ⌘− zoom, ⌘0 fits content. Artboards drawn in view space so the
  shadow + 1px border stay crisp at any zoom; artboard stays white per the
  locked exception. MainWindow now owns AppState via `@State` and injects it
  with `.environment`; the Inspector shows a live zoom % to prove the
  AppKit→AppState→SwiftUI round-trip. Semantic colors throughout (light/dark +
  increase-contrast); VoiceOver label on the canvas; keyboard-operable zoom.
  **Owner: build & report.** Watch for: pan direction feel (scroll sign),
  pinch sensitivity, whether ⌘+/-/0 fight any menu shortcuts. **Next:** finish
  Phase 1 — artboard *create* UI + mouse hit-testing/selection (Phase 3 overlap),
  then Phase 2 document model.

- **(date) — Session 2:** Phase 0 complete — three-pane editor shell runs
  (HSplitView, toolbar panel toggles, placeholder artboard). Confirmed Xcode
  26.3 / Swift 6.2. Added two founding notes: (1) follow system light/dark via
  semantic colors, artboard stays white on purpose; (2) FLOATING/DETACHABLE
  panels for multi-monitor as a locked principle — v1 keeps docked layout but
  every panel is written self-contained & state-driven so v2 can pop them into
  their own windows without a rewrite. Next step: Phase 1 — set up shared
  app-state object, then build the real AppKit-backed canvas with smooth
  pan/zoom.

- **(date) — Session 1:** Scoped v1, locked architecture decisions, created
  this roadmap. Next step: Phase 0 — stand up the Xcode project and get an
  empty window running, confirm Swift/Xcode versions.
