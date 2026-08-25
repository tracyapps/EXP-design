# EXP [design] — Backlog & Bug Tracker

A single, structured list of bugs, feature ideas, and performance work — written
so BOTH a human and an AI agent can pick something up cold. It complements
ROADMAP.md (which holds the phase plan + the Progress Log). Use ROADMAP for
"what's the plan / what happened"; use THIS for "what's the queue."

## How agents should use this
1. Pick the top **unclaimed** item at the priority you're asked for (P1 → P3).
2. Read its **Repro/Detail**, **Hypothesis**, and **Acceptance** before touching code.
3. **Assigning a NEW id: take the next number above the highest ALREADY USED
   anywhere in the repo, not the highest in this file.** Ids get referenced from
   ROADMAP's Progress Log, PERF-LOG.md, and PERF-TODO.md, so an id can be taken
   without appearing as a heading here. Run `scripts/verify_backlog_ids.sh`
   (it prints the next free id per prefix and fails on collisions). A PERF-005
   collision went unnoticed across four files from 2026-07-09 to 2026-08-11.
4. Set `Status: in-progress`, implement, then set `Status: needs-verify` (owner
   builds & confirms) and add a dated **Progress Log** entry to ROADMAP.md.
5. Respect the CLAUDE.md rules (command-coverage, shared-target files, a11y).

## Entry format (copy this)
```
### <ID> — <one-line title>
- Type: bug | feature | perf
- Priority: P1 (soon) | P2 | P3 (someday)
- Area: canvas | inspector | model | color | export | chrome | perf | infra
- Status: open | in-progress | needs-verify | done
- Repro/Detail: <what happens / what's wanted, concrete steps>
- Hypothesis: <suspected cause or approach — optional>
- Acceptance: <how we know it's done>
```

---

## 🐞 Bugs

### BUG-053 — Raster export silently drops the `noise` and `dissolve` effects
- Type: bug (fidelity/divergence — the failure this tool exists to prevent)
- Priority: P1
- Area: export · effects · canvas
- Status: **open — root cause identified 2026-08-25 by source inspection; not yet
  reproduced by running the renderer, and no fix written**
- Repro/Detail: Owner built layered light-leak graphics using overlay / color /
  color-dodge layers at various opacities, one of them a blue layer carrying a
  `noise` (feTurbulence) effect. PNG export does not match the canvas: the broad
  soft wash disappears, the periphery crushes to black, a hard-edged dark rectangle
  appears that matches no authored layer, and — the owner's decisive observation —
  *"the blue layer with the noise effect is not registering as color dodge."*
  Evidence screenshots are on disk at `docs/evidence/BUG-053/`, deliberately
  UNTRACKED per the repo's screenshots-are-local-evidence rule.
- **Root cause: three of the six effect kinds are not implemented in the raster
  export path at all.** `Effect.Kind` is
  `dropShadow, innerShadow, layerBlur, backgroundBlur, noise, dissolve`
  (`Document.swift:2361`). `ExportRenderView.drawExportNode` handles exactly
  `dropShadow`, `layerBlur`, and `innerShadow`. It never calls
  `EffectsRender.drawNoise` — that function has exactly ONE call site in the whole
  app, `CanvasView.swift:5906` — and it has no `dissolve` branch.

  | Effect kind | Canvas | SVG export | PNG / JPG / PDF export |
  |---|---|---|---|
  | dropShadow | yes | yes | yes |
  | innerShadow | yes | yes | yes |
  | layerBlur | yes | yes | yes |
  | **noise** | yes | yes | **silently dropped** |
  | **dissolve** | yes | yes | **silently dropped** |
  | backgroundBlur | `backgroundBlurEnabled = false` | n/a | n/a (feature off everywhere) |

  So the canvas and the SVG exporter agree with each other, and the raster exporter
  is the odd one out. The irony is documented in the code: `svgFilter`'s comment
  says its primitive order "mirrors the raster render exactly," and it does — it
  mirrors the CANVAS raster render, which is not the one that writes PNGs.
- **Why the whole image changes, not just the noisy layer.** A full-artboard noise
  layer composited with color-dodge lifts the entire backdrop. Drop it and the
  periphery collapses toward black while the untouched core bloom dominates —
  which is exactly the radial luminance measured on the owner's evidence: export
  2.31× the canvas at the bloom centre, crossing 1.0 near radius 50, 0.34–0.57×
  beyond radius 60. The apparent hue shift is the same story: the green/teal wash
  was a dropped layer's contribution, not a recolouring.
- **The mystery dark rectangle is the same bug, seen from the other side.** A layer
  whose `dissolve` eats most of its pixels renders as the SOLID, hard-edged shape
  underneath when the dissolve is dropped. That accounts for a square-cornered dark
  panel appearing behind a rounded box and matching no layer the owner can find —
  it IS a layer, drawn as authored geometry instead of as the texture it should be.
  Confirm by locating any node with a `dissolve` or `noise` effect near the box.
- Secondary suspect, lower confidence, worth a look once the above is fixed:
  `EffectsRender.drawDropShadow` uses `ctx.setBlendMode(.destinationOut)` for the
  preserve-transparency knockout (`EffectsRender.swift:205`), and the knockout
  closure fills the silhouette with **opaque black**. `.destinationOut` is a
  Porter-Duff compositing mode with no PDF equivalent, and PNG/JPG export
  rasterizes through a PDF intermediate (`ExportRenderer.pngData`). If CoreGraphics
  falls back to Normal when emitting that to PDF, the knockout paints a black
  silhouette instead of erasing one. The owner already tried disabling one
  preserve-transparency shadow without the artifact clearing, which argues against
  this being the cause of the rectangle — but the mode is genuinely unrepresentable
  in PDF, so verify it rather than assume. Test: disable preserve-transparency on
  EVERY drop shadow in the document at once.
- **Decisive test before writing any fix: `docs/EXPORT-FIDELITY-TEST-FIXTURES.md`,
  Fixture A (~15 min).** Build instructions are exact and self-contained — artboard
  size, layer positions, effect values, which exports to take, and a table of what
  each outcome means. In short: three identical rects, one plain, one with a `noise`
  effect at Color Dodge, one with a `dissolve`; export PNG and SVG. Predicted result
  is that SVG matches the canvas for all three and PNG matches only the plain one.
  A failed prediction means this diagnosis is wrong — record that rather than
  adjusting the theory.
- Fix direction: the raster export needs `noise` and `dissolve`, in the canvas's
  order (dissolve first, so every later primitive including shadows sees the
  dissolved node — the order `svgFilter` already documents). The deeper problem is
  that `drawExportNode` and the canvas draw path are separate implementations that
  "mirror" each other by comment; adding two more branches to the copy leaves the
  next effect kind free to go missing the same way. Prefer one shared effect
  pipeline over a fourth hand-kept mirror. See also BUG-054, found the same day,
  which is the same drift in the blur geometry.
- Acceptance: every `Effect.Kind` renders in canvas, SVG, PNG, JPG, and PDF, or is
  refused at authoring time — no effect is silently ignored by an exporter. A
  regression fixture covering all six kinds exports identically across raster and
  SVG. Adding a new effect kind without wiring every exporter fails a check rather
  than shipping a silent divergence.

### BUG-054 — Effect blur radii live in three different spaces across two render paths
- Type: bug (fidelity/divergence)
- Priority: P2
- Area: export · effects · canvas · perf
- Status: **open — found 2026-08-25 while tracing BUG-053; NOT the cause of the
  owner's reported divergence (see BUG-053), but a real one in its own right**
- **Honest history:** this was first written up as the explanation for BUG-053's
  evidence. It is not. The owner's observation that a noise layer "is not
  registering" led to the real cause. The measurements that pointed here — light
  concentrated from the periphery into the core — are equally well explained by a
  dropped full-artboard noise layer, so this entry is a code-reading finding with
  no confirmed symptom attached. Keep it; do not credit it with BUG-053's evidence.
- Detail: `EffectsRender.maxShadowBlurPx = 200` is a PERFORMANCE guard applied in
  DEVICE space — `min(e.blur * scale, 200)` — and the canvas passes
  `scale: app.zoom` (`CanvasView.swift:5841,5853`) while export passes `scale: 1`
  (`ExportRenderer.swift:806,815`). The surviving model-space blur is therefore
  `min(blur, 200/zoom)` on canvas and `min(blur, 200)` in export: equal only at
  100% zoom. A blur wider than 200pt authored while zoomed out renders in full on
  canvas and truncated in export. A performance guard must not change the picture.
- Two more in the same family:
  1. `EffectsRender.drawLayerBlur` computes
     `sigma = min(200, effect.blur * max(1, deviceScale))`. The canvas passes
     `backingScale` and draws in VIEW space (already zoomed), so a model-point blur
     is multiplied by the backing scale but NOT by zoom, while its `bounds` and
     `pad` are view-space. Canvas layer blur is self-consistent only at 100% zoom;
     export (`deviceScale: 1`, model space) is self-consistent. They disagree by
     construction.
  2. `drawLayerBlur`'s size guards (`maxLayerDimension` 12000, `maxLayerPixels`
     32M) **fail open to `draw(ctx)` — the content with NO BLUR AT ALL**, silently.
     A large heavily-blurred layer is exactly what trips them. Degrading resolution
     is defensible; dropping the effect without a word is not.
- **Test: `docs/EXPORT-FIDELITY-TEST-FIXTURES.md`, Fixture B (~15 min, optional).**
  Exact build instructions and an outcome table live there. In short: two rows of
  four rects, one row with layer blurs and one with drop shadows, at 50 / 150 / 250
  / 400 points; export PNG from three different canvas zooms and at three scales.
  Predicted result is that the 250 and 400 rects are identical in every export
  (both clamped to 200), that exports do not vary with canvas zoom, and that the
  canvas does. `scripts/measure_export_divergence.py` quantifies any pair.
- Acceptance: a blur renders at the same MODEL-space radius on canvas at every zoom
  and in export at every scale. A blur too large to render at full resolution
  degrades in resolution, never in radius, and never silently.

### BUG-052 — Reveal in Layers and layer-tree commands lose the live floating panel
- Type: bug
- Priority: P1
- Area: layers · chrome · multi-window
- Status: **needs-verify — implemented 2026-08-24**
- Repro/Detail: In Multi-Window mode, select a canvas object whose row is nested or
  outside the visible Layers range and invoke Reveal in Layers. The floating Layers
  panel does not reliably expand/scroll to it. View ▸ Expand All Layers and Collapse
  All Layers cross the same connection and can target the wrong/no panel after dock
  ↔ tray, collapse/reopen, or active-document changes.
- Root cause/fix: the canvas stored two `@ObservationIgnored` closures installed by
  whichever `LayersPanel` view appeared last. Those closures captured view-local
  state and a `ScrollViewProxy`; when SwiftUI replaced that dock/tray tree, the
  command could keep calling a dead proxy with no observable lifecycle handoff. The
  callbacks are replaced by one sequenced `AppState.LayersPanelCommand` request that
  exactly one currently mounted Layers surface consumes. A request remains pending
  if Reveal has just created or uncollapsed the panel, so its new view consumes it on
  appearance. Reveal now distinguishes panel membership from visible content: it
  activates/expands a dock tab or creates/uncollapses the floating tray before asking
  the live list to open ancestors and scroll. Source-editor Layers uses the same route.
- Acceptance: in Single-Window and Multi-Window modes, Reveal in Layers opens a
  hidden Layers surface, activates it when it is an inactive dock tab, expands a
  collapsed floating section, opens every ancestor group/section, and centers a
  single selected row. Repeat after switching modes and active documents; only the
  correct document panel moves. View ▸ Expand/Collapse All works in docked,
  floating, and source-editor Layers. Ordinary canvas selection still opens required
  ancestors but never auto-scrolls. No duplicate request or scroll hang returns.

### BUG-051 — Floating panels do not return to the front across displays when EXP is reactivated by a canvas click
- Type: bug
- Priority: P1
- Area: chrome · workspace · multi-window
- Status: **needs-verify — implemented 2026-08-24**
- Repro/Detail: In Multi-Window mode, leave EXP's document on the main display and
  trays on a second display. After another app covers the second display, clicking
  and working on EXP's canvas does not bring those trays forward there. Command-Tab
  to EXP does, producing two inconsistent activation paths.
- Root cause/fix: tray windows were ordinary-level `NSWindow`s. They were shared and
  non-main, but nothing gave them palette ordering across display window stacks.
  Every tray is now an active-app floating palette and hides when EXP deactivates;
  AppKit therefore restores all trays above ordinary windows when EXP reactivates,
  whether activation came from Command-Tab or clicking the canvas. The document
  window remains main/key for canvas keyboard input.
- Acceptance: place independent and glued trays on a second monitor, cover them by
  activating another app, then reactivate EXP once by clicking its canvas and once
  by Command-Tab. Both routes restore every tray at its saved frame above ordinary
  windows without stealing canvas keyboard focus. Deactivating EXP hides its trays
  so they never float above the active application. Verify multiple EXP documents,
  tray text fields, panel drag/resize/glue, and Window-menu focus.

### BUG-050 — A layer selected in Layers does not consistently receive arrow-key nudges
- Type: bug
- Priority: P1
- Area: layers · canvas · keyboard
- Status: **needs-verify — implemented 2026-08-24**
- Repro/Detail: Click a buried layer in the Layers panel, then press an arrow key.
  Depending on which panel control previously owned focus, the layer may not move.
  This is especially costly when higher layers cover it, because canvas hit-testing
  selects the covering layer instead.
- Root cause/fix: Layers uses custom tap rows rather than native `List` selection,
  so AppKit did not reliably return first-responder ownership to the canvas after a
  row click. The first fix explicitly focused the document canvas and solved
  Single-Window mode, but owner verification exposed the missing window half: in
  Multi-Window mode the floating Layers tray remained the **key window**, so changing
  first responder inside the inactive document window could not redirect keyboard
  events. A row selection now makes its document window key and then focuses that
  canvas; the trays remain visually forward as non-key floating palettes.
- Acceptance: one click on any visible Layers row followed immediately by an arrow
  moves that layer by one point; Shift-arrow moves it by ten. This works after focus
  was in an Inspector text field, from both docked and floating Layers panels, and
  for nested or visually covered layers. The click remains a normal accessible layer
  selection and does not start a move. Double-click rename and panel text fields can
  still reclaim key focus when deliberately invoked.

### BUG-049 — Keyboard point moves leave path bounds, hit-testing, and shadows stale
- Type: bug
- Priority: P1
- Area: canvas · vector · effects
- Status: **needs-verify — implemented 2026-08-24**
- Repro/Detail: Select several path points and move them with the arrow keys. The
  anchors move, but the object's selection box remains at its old frame. Geometry
  beyond that frame cannot be clicked and a drop shadow is clipped to the stale
  paint bounds (owner screenshot 2026-08-24).
- Root cause/fix: pointer point drags normalized the path frame at gesture close,
  but keyboard nudge, Inspector rotation, and point deletion wrote path coordinates
  directly and never ran that normalization. Frame refitting is now a shared in-place
  operation used by every point-edit route before the same single undo commit.
- Acceptance: arrow-nudge one or several anchors beyond every side of the original
  frame; the bounding box follows, all moved geometry remains clickable, and an
  outside drop shadow is fully painted. Repeat with Inspector point rotation and
  deletion, a multi-contour outlined-text path, and a rotated/flipped nested path.
  Each command remains one undo step and the rendered path does not jump.

### BUG-048 — Placed SVG `stroke-dasharray` imports as the wrong stroke pattern
- Type: bug
- Priority: P2
- Area: import · SVG · vector
- Status: **needs-verify — the mapping is implemented 2026-08-25 and builds clean;
  the import-report half of the acceptance is NOT built (see below)**
- Repro/Detail: Owner found during FEAT-031 export verification that placing an
  SVG carrying `stroke-dasharray` does not reconstruct the dashed/dotted stroke
  correctly. The same exported SVG renders correctly in a browser, so this is the
  editable SVG import path, not the SVG emitter or arrow/end-cap model.
- Root cause: confirmed in source. `SVGImporter.Style` has no stroke-pattern/dash
  field, `presentationAttributeKeys` omits `stroke-dasharray`, and `resolveStyle`
  never interprets it. Imported `LineShape` / `PathShape` therefore keep their
  default solid `StrokePattern` regardless of the SVG declaration.
- Implementation 2026-08-25: `SVGImporter.Style` gains `strokePattern`,
  `stroke-dasharray` joins `presentationAttributeKeys` (so it arrives from a
  presentation attribute, an inline style, or a matched stylesheet rule — all three
  flow through the same `props` dictionary), `resolveStyle` interprets it, and both
  `PathShape` and `LineShape` construction carry it through.
- **Read by RULE, not by matching EXP's own numbers.** EXP exports Dot as a
  zero-length dash with a round cap (`0.001 <gap>`) — the standard SVG dot idiom —
  and Dash as `<dash> <gap>` with a butt cap. The importer reads any array by that
  same rule, so a third-party dashed line imports as dashed rather than as "not our
  numbers, therefore solid." A dash length of effectively zero is read as Dot even
  when the cap is butt, where the author's own file would have painted nothing: the
  nearest EDITABLE intent is a dot.
- **Verified by table, not by eye.** The mapping was run standalone against 14 cases
  including EXP's own dashed and dotted exports at two stroke widths, comma and
  whitespace separators, `px` units, single-value arrays, all-zero arrays, `none`,
  and an unparseable value. All 14 match — importantly, EXP's own exports round-trip
  to the preset they were written from.
- **NOT built, and it is part of the acceptance: the import report.** An array EXP
  cannot represent (a four-value rhythm, say) is approximated to the nearest preset
  rather than announced. `SVGImporter` deliberately imports only Foundation and
  CoreGraphics and has no report channel — `Context` is passed by value, so notes
  collected during a parse do not reach the caller. Adding one is its own small
  piece of work (a returned notes array threaded through the entry point, or a
  summary surface at the place-SVG action) and should be logged as such rather than
  bolted on here. Until then the failure mode is "approximated silently," which is
  strictly better than the "solid silently" this bug was filed for, but is not what
  the acceptance asks for.
- Acceptance: placing SVGs with `stroke-dasharray` supplied as a presentation
  attribute, inline style, or matched stylesheet rule reconstructs EXP's Dash or
  Dot preset when the array matches one of those semantics. EXP's own dashed and
  dotted SVG exports round-trip to the same editable `StrokePattern`. A custom
  array that cannot fit EXP's preset model produces an explicit import-report
  approximation instead of silently becoming solid. Stroke cap, markers, opacity,
  transforms, and geometry remain unchanged.

### BUG-047 — Artboard-bound snapping cannot catch a layer approaching from the wall
- Type: bug (incomplete shipped behavior)
- Priority: P2
- Area: canvas · snapping · input
- Status: **done 2026-08-21 — owner verified.**
- Repro/Detail: Tester request relayed by the owner 2026-08-21: add a subtle,
  default snap to artboard bounds. The canvas already claimed this behavior, but
  `snapNodeOffset` took candidates only from `owningArtboard(of:)`. A wall layer
  does not acquire an owner until it overlaps more than 50%; when it is flush
  OUTSIDE an artboard it has zero overlap. So the exact placement where the snap is
  most useful could never see that artboard. Snapping inside an already-owned board
  worked, which hid the gap.
- Root cause/fix: artboard candidates now come from a selection-box probe expanded
  by the existing magnetic threshold (6 screen points). Any board the selection
  touches or is genuinely close to contributes its edges and centres; a far-away
  board that merely shares an x/y coordinate cannot pull the drag. With Smart
  Guides on, the existing dashed guide is drawn across the matched artboard bound.
  The snap box now uses the same visual-bounds path as Align, so nested, rotated and
  flipped selections do not snap from a stale parent-local frame.
- Related bug fixed in the same gate: BUG-036(b) made whole-pixel snapping a separate
  preference in the UI, but `mouseDragged` used `pixelSnap == false` as a reason to
  bypass `snapNodeOffset` entirely. That quietly disabled ruler guides, grid/layout
  grid, element guides, and artboard bounds along with pixel rounding. The gesture
  now has two explicit decisions: ⌘ bypasses all snapping temporarily; the persisted
  pixel preference controls only whole-point rounding.
- Acceptance: drag a shape from the wall toward each outside edge of an artboard and
  it catches flush within 6 screen points; the same edges and centres still catch
  from inside. With Smart Guides on, the matched artboard line appears; with it off,
  no line appears. Turn Snap to Whole Pixels off and confirm artboard/ruler/element
  snapping still works while free movement can remain fractional. Hold ⌘ and every
  snap is bypassed. A rotated shape and a nested selection snap by their visible
  bounds. A distant artboard sharing only one coordinate does not exert a pull.

### BUG-024 — The canvas ignores the first click after focus moves to it
- Type: bug
- Priority: P1
- Area: canvas · chrome · input
- Status: **closed 2026-08-11 — DUPLICATE of BUG-025.** Owner, after building the
  Wave 1 fixes: *"I can't seem to get close to that feeling of the tools not
  responding. So I think we got it."* No repro exists that does not involve
  Option-drag, which is what BUG-025 turned out to be. Two lessons recorded rather
  than quietly dropped: (1) this entry was created by splitting ONE owner report into
  two bugs on the strength of a guess about the cause, and the guess was wrong on both
  counts — the split and the mechanism; (2) the `acceptsFirstMouse` hypothesis was
  written into the backlog as though it were a finding, and a later session could
  easily have implemented it. Prefer "cause unknown, here is the observation" over a
  confident-sounding hypothesis that has not been checked against the source.
- Repro/Detail: Owner report 2026-08-11. "Sometimes clicking or actions only happen
  the second time." Owner notes other apps do not behave this way, so it is not a
  macOS convention being followed.
- **HYPOTHESIS DISPROVEN — do not re-file it.** The entry below guessed a missing
  `acceptsFirstMouse(for:)`. Checked the source before writing any code:
  `CanvasView.swift:149` already has `override func acceptsFirstMouse(for:) -> Bool
  { true }`, and `:148` already returns true from `acceptsFirstResponder`. `mouseDown`
  additionally calls `window?.makeFirstResponder(self)` on every click, with a comment
  explaining it exists precisely so a click reclaims keyboard ownership from a panel.
  All three of the obvious causes are therefore already handled.
- **AND the reported evidence may all belong to BUG-025.** Re-reading the owner's
  report, the whole paragraph is about Option-drag: *"especially with the drag to
  duplicate while holding down the option key... it works only if I have the button
  pressed for a time before moving."* BUG-025 is now confirmed and fixed, and it
  produces exactly a "nothing happened, do it again" symptom. So this entry may have
  been over-read from a single report describing one bug.
- **NEEDED BEFORE MORE WORK:** a repro that does NOT involve Option-drag. If the
  owner cannot reproduce a swallowed first click once BUG-025 is verified, close this
  as a duplicate rather than leaving a speculative bug open.
- Hypothesis: `CanvasNSView` almost certainly does not override
  `acceptsFirstMouse(for:) -> true`. By default AppKit treats the first click in an
  inactive window/view as a pure activation click and swallows it. This would fire
  constantly given the owner runs floating panel trays across multiple monitors —
  every trip from a panel back to the canvas costs a click. Check
  `acceptsFirstResponder` and the window's `acceptsMouseMovedEvents` in the same
  pass. Verify against `NSView.acceptsFirstMouse(for:)` documentation before
  changing, since returning true unconditionally can make destructive actions
  fire on an activating click — gate it to selection/drag, not to delete-like
  operations.
- Acceptance: with focus in any panel or floating tray, a single click on a canvas
  shape selects it. Same for starting a marquee, a drag, and a tool press. No
  destructive action becomes reachable on an activation click. Verified in both
  single-window and multi-window workspace modes.

### BUG-025 — Option-drag to duplicate requires precise, unforgiving key/mouse timing
- Type: bug
- Priority: P1
- Area: canvas · input
- Status: **done — owner verified 2026-08-11** ("feels much smoother and less picky, exactly what I'm expecting to happen")
- Root cause CONFIRMED in source: `CanvasView.mouseDown` read
  `event.modifierFlags.contains(.option)` ONCE and, if set, called
  `duplicateSelectedInPlace` immediately, before any drag threshold. macOS delivers
  `flagsChanged` and `mouseDown` as SEPARATE events, so pressing Option and the mouse
  button at nearly the same instant gives a nondeterministic order — press Option a
  hair late and the flag reads false and you get a move. That is precisely the
  owner's "sometimes I must hit the key and mouse down at more of the same time, or
  slightly staggered." A second, quieter bug fell out of the same line: duplicating at
  mouseDown meant a plain Option-CLICK with no movement minted a copy and, because it
  set `didEdit`, registered an undo step for it.
- Fix applied: the duplicate decision is DEFERRED out of `mouseDown` and re-sampled
  live in the `.nodes` case of `mouseDragged`, so Option can be pressed before
  mouse-down, after mouse-down, or mid-drag, and releasing it mid-drag reverts to a
  move. New `setDragCopy(_:startDoc:)` flips the gesture by rewinding to
  `dragBaseline` and re-applying, rather than trying to surgically delete the copies —
  the baseline is the model as of mouseDown, so it is immune to whatever else the drag
  has touched (artboard membership, reparenting, snapping). It runs only when the
  modifier actually changes, never per drag tick. Origins are re-read after a flip
  because duplicating swaps the selection to new ids. Undo is unaffected: gesture undo
  is registered once at mouseUp from `dragBaseline` and `withNodes` mutates live
  without registering, so any number of mid-drag flips still yields exactly one step,
  named for whichever state the drag ended in. Per-gesture state cleared in `mouseUp`.
- Repro/Detail: Owner report 2026-08-11. Holding Option and dragging a shape to
  duplicate it only works if Option is held for a moment before the drag begins, or
  if key-down and mouse-down land close to simultaneously — sometimes slightly
  staggered. Otherwise the drag moves the original instead of duplicating. Owner:
  "other programs respond to this so check the timing."
- Hypothesis: the Option modifier is read once, latched at `mouseDown`, rather than
  sampled live. Every other app that gets this right re-reads
  `NSEvent.modifierFlags` on each `mouseDragged` and can flip a move into a
  duplicate mid-gesture (and back). Fix shape: decide duplicate-vs-move at the
  moment the drag threshold is crossed, and keep watching `flagsChanged` for the
  duration of the drag so pressing or releasing Option mid-drag updates the
  operation. This is likely the same class of problem as BUG-024 but a distinct
  cause — fix both, do not assume one fix covers the other.
- Acceptance: Option can be pressed before mouse-down, after mouse-down but before
  moving, or mid-drag, and each produces a duplicate. Releasing Option mid-drag
  reverts to a move. One undo step per completed gesture. Same behavior for
  Option-drag of points, groups, and component instances.

### BUG-026 — Gradient stop handles need off-center or repeated clicks to activate
- Type: bug
- Priority: P1
- Area: color · inspector · input
- Status: **done — owner verified 2026-08-11**
- Root cause CONFIRMED in `Color/PaintEditor.swift` → `GradientBar`, and it was not
  a tolerance problem at all. Markers were centred at `position * w` and drawn with
  `.offset(x: x - 7)`, so the stops at position 0.0 and 1.0 — which EVERY gradient has
  by default — hung half outside the bar's rect. The drag gesture carries
  `.contentShape(Rectangle())`, which limits hit-testing to that rect, so the
  overhanging half of each end marker was VISIBLE BUT NOT CLICKABLE. Clicking the
  outer half of an end stop did nothing at all; clicking slightly inward worked. That
  is precisely the owner's "the gradient points seem to need to be active slightly
  off-centre of the actual circle."
- Second bug found in the same lines: the grab tolerance was `0.05` in NORMALISED
  units, i.e. 5% of the bar's width — so how easy a stop was to grab silently changed
  with the panel width. Third: `setPosition` ran on the very first `onChanged`, so
  grabbing a stop anywhere but dead centre teleported it under the cursor.
- Fix applied: the usable track is inset by the marker radius so a stop at 0 or 1 sits
  fully inside the bar and is hittable across its whole width; tolerance is expressed
  in POINTS (12pt = a 24pt target, per WCAG 2.2 §2.5.8 Target Size (Minimum) — the
  marker still READS as 14pt, only the grab area grew) and converted through the
  track, so it no longer varies with panel width; and a `grabOffset` is recorded on
  grab so dragging a stop moves it relatively instead of snapping it to the cursor.
- **NOT addressed — still open:** (a) keyboard focus cannot reach or move individual
  stops. The selected stop's position is editable via its numeric field, but SELECTING
  a different stop is pointer-only, so this control is not yet keyboard operable. That
  is a real gap against the original acceptance and needs its own entry or a follow-up
  here — do not treat this fix as closing it. (b) Adding a stop now requires clicking
  at least 12pt from an existing one; a dedicated Add control would be the durable
  answer if that proves annoying.
- Repro/Detail: Owner report 2026-08-11. In the gradient stop bar, clicking the
  visible center of a stop often does nothing; the stop only activates when clicked
  slightly off-center, or after several clicks. Makes recoloring a stop feel broken.
- Hypothesis: the hit-test rect for a stop is offset from where the stop is drawn —
  likely the drawn marker is centered on the stop position while the hit region is
  laid out from the marker's leading edge (a half-width offset), or a drag gesture
  is consuming the click before the tap recognizer sees it. Compare the draw origin
  and the hit origin directly rather than adjusting tolerances by feel.
- Acceptance: a single click anywhere within the drawn stop marker selects that
  stop and opens its color for editing. Hit target meets the 24×24 CSS-pixel
  minimum spirit of WCAG 2.1 AA §2.5.5 Target Size (Enhanced is AAA; AA §2.5.8 in
  2.2 is 24×24 — record which we are holding ourselves to). Keyboard focus can
  reach and move each stop.

### BUG-027 — Point-select tolerance biases too hard toward the base point
- Type: bug
- Priority: P1
- Area: canvas · vector · input
- Status: **done — owner verified 2026-08-11**
- Root cause CONFIRMED in `CanvasView.hitTestPathPoint`: the function returned the
  moment ANY anchor fell inside `handleGrab` (12pt), before the handle loop ran at
  all. So the anchor owned its entire 12pt radius outright and a handle anywhere
  inside it could not be reached at any practical zoom — the owner's "requires zooming
  several hundred percent in." The original intent (an anchor beats a handle collapsed
  on top of it, because the anchor square is what you see there) was right; expressing
  it as an exclusive radius rather than a tie-break was the error.
- Fix applied: both candidates are now collected and arbitrated. The anchor wins when
  `anchorDistance <= handleDistance + anchorPriorityBias` (3 view points, converted by
  zoom exactly as `grab` is, so the feel is zoom-independent). A handle collapsed onto
  its anchor still yields to the anchor; a handle a few points away is grabbable on the
  first click at 100%.
- Repro/Detail: Owner report 2026-08-11. A deliberate earlier change made point
  selection favor the anchor (base point) over its curve handles. It over-corrected:
  when a handle sits close to — but not on top of — its anchor, grabbing the handle
  now requires zooming in several hundred percent. Owner: "the tolerance just needs
  to be tightened up a bit."
- Hypothesis: the anchor's hit radius is a fixed screen-space value that swallows
  handles inside it regardless of whether the handle is actually the nearer target.
  Better rule: keep the anchor priority ONLY when the cursor is genuinely closer to
  the anchor, and shrink the anchor's exclusive zone so a handle more than a few
  points away wins. Ties should still go to the anchor — that was the right call.
- Acceptance: at 100% zoom, a handle offset by a small but visible distance from its
  anchor is grabbable on the first click. A handle exactly coincident with its
  anchor still yields to the anchor. No regression in the original complaint that
  prompted the bias.

### BUG-028 — The point tool does not always respond to the keyboard tool-switch shortcut
- Type: bug
- Priority: P1
- Area: canvas · tools · keyboard
- Status: **done — owner verified 2026-08-11**
- Root cause CONFIRMED: the letter shortcuts are handled in `CanvasNSView.keyDown`
  (`CanvasView.swift:6419`, `case "v": setTool(.select)`), which only runs when the
  CANVAS holds focus. With focus in Layers, the inspector, or a floating tray the key
  never reaches it. Same responder-chain boundary as BUG-016 and BUG-020.
- Fixed so far: every tool now has a menu-bar home. New `Tools` menu +
  `selectToolAction:`/`nodeToolAction:`/etc. `@objc` actions routed through
  `sendCanvasAction`, so a tool can be changed from ANY focus location. This is also
  what the command-coverage rule required regardless. No `validateMenuItem` cases: a
  tool is never unavailable, so there is nothing to gate — deliberate, not an omission.
- **Shortcut half RESOLVED 2026-08-11, decided on evidence rather than argument.**
  BUG-038 turned up mid-discussion and is precisely the predicted failure, already
  shipped: BUG-020's opacity digits swallowed numbers being typed into a layer name.
  That disqualified BOTH candidate routes at once — menu key equivalents (the menu is
  offered equivalents before the first responder, so it cannot ask whether the user is
  typing) and per-panel `.onKeyPress` (the route BUG-020 took, which is what produced
  BUG-038). Implemented the third option: a single local key monitor, `ToolShortcuts`
  in `MainWindow.swift`, installed from `EXP__design_App.init()`. It declines when any
  modifier other than Shift is held, declines while `isTypingInTextField()`, and
  declines when the first responder IS the canvas — that last check leaves the
  existing canvas-focus path bit-for-bit unchanged, so this can only add the missing
  routes, never alter what already worked. ⇧A keeps the Sketch/XD Artboard alias. When
  nothing answers, the event is passed through rather than silently eaten.
- Known minor behaviour, accepted deliberately: with a non-document window key
  (Settings, the ARIA guide) a tool letter still reaches the document through
  `sendCanvasAction`'s main-window fallback and changes its active tool. A
  "key window must host a canvas" guard would fix it but would ALSO break floating
  panel trays, which are the whole point of this bug — so the wart is the better trade.
- Superseded note, kept because the reasoning is worth preserving: The obvious next step is to
  give those menu items their letter shortcuts, and it is very likely the WRONG move.
  The main menu is offered key equivalents BEFORE the event reaches the window's first
  responder, so an unmodified single-letter equivalent would fire while the user is
  typing — renaming a layer, editing a text node, filling an inspector field — and
  swallow the character. Handling them in `keyDown` is precisely why typing works
  today. **NOT VERIFIED:** the exact AppKit arbitration between a plain-letter menu key
  equivalent and an active field editor was not confirmed against Apple's
  documentation. Verify before choosing this route; the failure mode is "no letter can
  be typed anywhere in the app," which is far worse than the bug being fixed.
  Safer alternative to evaluate: a single local key monitor
  (`NSEvent.addLocalMonitorForEvents(matching: .keyDown)`) that handles the tool
  letters ONLY when the first responder is not a text-editing view — one central
  place, works from every focus location, and can never steal a keystroke from a
  field because it explicitly checks first.
- Related but separate: FEAT-025 (point tool moves whole objects with nothing
  point-selected) makes the wrong-mode state far less punishing, but must not be
  treated as the fix for this — see that entry.
- Repro/Detail: Owner report 2026-08-11. While the point/direct-select tool is
  active, pressing the shortcut for the regular Select tool sometimes does nothing.
  Because the point tool will not move a whole object when no points are selected,
  the app then feels broken rather than merely unswitched — the failure is silent
  and easy to miss.
- Hypothesis: a responder-chain boundary, same family as BUG-016 (layer copy/paste)
  and BUG-020 (number-key opacity) — a focused SwiftUI view consumes the key event
  before the AppKit canvas `keyDown` sees it. Route tool shortcuts through the same
  focus-boundary handling those two bugs established, or promote them to menu-bar
  items with real key equivalents so the responder chain handles dispatch. Note the
  command-coverage rule: tool switching should have a menu-bar home regardless.
- Acceptance: the Select-tool shortcut switches tools from every focus location —
  canvas, Layers, Properties, and a floating tray panel. The active tool is visibly
  indicated. Fix this independently of FEAT-025; the better point-tool behavior must
  not be used to paper over a real event-routing bug.

### BUG-029 — Text editing is missing standard macOS caret and selection keys
- Type: bug
- Priority: P1
- Area: canvas · type · keyboard · a11y
- Status: **investigated 2026-08-19 — NO defect found in source. Needs one
  discriminating observation from the owner before any code is written.**
- **THE HYPOTHESIS BELOW IS WRONG — corrected 2026-08-19.** It says the editor
  "is handling keys itself rather than delegating to the standard `NSTextView` /
  `NSResponder` action methods." It is not. `CanvasNSView.beginEditingText` creates a
  stock `NSTextView`, adds it as a subview and makes it first responder; the only
  command the delegate intercepts is `cancelOperation:` (Escape commits the edit).
  There is no `doCommand(by:)` reimplementation, no `move*` override anywhere in the
  project, and no menu item bound to an arrow key. The two global key routes were
  checked as well: `ToolShortcuts`'s `NSEvent` monitor declines any event with
  ⌘/⌃/⌥, declines while `isTypingInTextField()`, and only matches single letters —
  arrows and Shift+arrows fall straight through it; `NumericStepping`'s
  `.onKeyPress` is attached to inspector fields, not the canvas. So with the text
  view focused, every standard caret, by-word, by-line and Shift-extension key
  should already reach AppKit unmodified.
- **Do not "fix" this speculatively.** Writing key handling here would REPLACE
  working AppKit behaviour with a hand-rolled version — exactly the failure the
  original hypothesis warned about, and it would break alternative input methods and
  users' own remapped key bindings.
- **What is actually needed:** the discriminating observation. Ask the owner, while
  editing text on canvas: (a) does typing a letter insert it, or switch tools? (if it
  switches tools, the text view never got focus and this is a first-responder bug,
  not a key-handling one); (b) does the text BOX itself nudge when an arrow is
  pressed? (same conclusion); (c) is the node a single line or multiple lines?
  (Up on the first line and Down on the last line moving to the very start/end of the
  text IS the standard AppKit behaviour the report describes as missing); (d) is a
  non-default keyboard layout or a key-remapping utility active?
- Owner also believed at intake that this may already be resolved; no BUG-029 code
  has ever been written, so if it is resolved, something else fixed it — most likely
  the Wave 1 focus/`acceptsFirstMouse` work. Worth re-testing on the current build
  before spending anything further.
- Repro/Detail: Owner report 2026-08-11, on a text node being edited on canvas.
  (a) Up-arrow does not jump to before the first character of the line and
  down-arrow does not jump to after the last character. (b) Shift+arrow does not
  extend the selection one character at a time. (c) The by-word and by-line
  selection shortcuts are not working.
- Hypothesis: the on-canvas text editor is handling keys itself rather than
  delegating to the standard `NSTextView` / `NSResponder` action methods. The right
  fix is almost certainly to stop reimplementing and instead forward to the standard
  selectors — `moveToBeginningOfLine(_:)`, `moveToEndOfLine(_:)`,
  `moveRightAndModifySelection(_:)`, `moveWordLeftAndModifySelection(_:)`,
  `moveToBeginningOfParagraphAndModifySelection(_:)` and friends — via
  `doCommand(by:)` / `interpretKeyEvents(_:)`. Reimplementing these by hand is how
  apps end up subtly wrong for users of alternative input methods, and it breaks
  users' own remapped key bindings.
- Acceptance: every standard macOS text navigation and selection key works in an
  on-canvas text node exactly as it does in a native text field — arrows, Shift+
  arrows, Option+arrows (by word), Command+arrows (line/document), and their
  Shift-extended forms. Verified with VoiceOver reading the selection changes, and
  with a non-default keyboard layout.

### BUG-030 — Dragging a multi-selection in Layers moves only the row under the cursor
- Type: bug
- Priority: P1
- Area: layers · model
- Status: **done — owner verified 2026-08-19**, including multi-drag and one-undo restore.
- **FIX APPLIED 2026-08-19.** `handleDrop` now moves a run of nodes instead of one,
  and the four decisions above were settled first rather than guessed:
  1. **Expansion** — new `dragSet(startingAt:)` returns the whole selection when the
     dragged row is part of it, that row alone when it is not. It reads
     `app.selectedNodeIDs` inside the panel, so no new binding plumbing. It also
     PRUNES any node whose ancestor is also selected: moving the ancestor already
     carries the child, and extracting both would orphan the subtree. The set comes
     back in MODEL order (a depth-first walk of `scopeNodes`), not click order.
  2. **Insertion order** — the run is inserted with ONE `insert(contentsOf:)` call
     (`insertSiblings`, and `insertIntoGroup` for a drop into a group) rather than
     one node at a time. That is simpler than the chaining the entry proposed and
     equivalent: a single block insert cannot be reversed by the model/display
     inversion, whereas re-anchoring on the target per node reverses it and inserting
     at a group's index 0 per node reverses it too.
  3. **Mixed parents — OWNER DECISION 2026-08-19: reparent, do not refuse.** Every
     moved node lands in the target's parent (or in the target group), Finder/
     Illustrator style. Each node is converted to document coordinates before the
     move and back into the destination parent's space after it, so nothing jumps on
     screen. Refusing was offered and declined as a rule users would have to learn.
  4. **One undo step, selection survives** — a single `commitNodes`, action named
     "Move Layer" or "Move Layers", then `app.selectedNodeIDs` is restored to the run.
  Also fixed in the same pass because they were the same bug wearing other clothes:
  - `attach(_:to:)` now takes the whole run and recentres it as ONE block on its
    union bounds. Per-node centring would have stacked a multi-selection into a pile
    at the artboard's midpoint.
  - The artboard-section-header drop (`moveLayers(_:toArtboard:)`) honours the
    selection too — it had the identical single-id shape.
  - A drop INTO a component instance (`moveIntoSource`) takes the whole run,
    all-or-nothing: `Document.canInsert` was already array-shaped and is now asked
    about the entire set, so a partial insert cannot happen.
  - Dragging a row that is NOT selected now replaces the selection at `.onDrag` time,
    so the highlight during the drag matches what the drop will actually move.
  - `LayerDropDelegate` refuses (cursor + no drop line) when the destination row is
    itself part of the moving selection. **Not covered:** dropping onto a DESCENDANT
    of a moving group is still refused silently by `handleDrop` rather than visibly
    by the delegate — the delegate has no view of the tree. Pre-existing behaviour,
    unchanged, recorded here rather than left to be rediscovered.
- **Owner verification 2026-08-19:** multi-drag works, including the one-undo
  restore. The mixed-parent/nested rules below remain the implementation contract.
- Repro/Detail: Owner report 2026-08-11, flagged as "a bug that is pretty big to
  fix." Select several layers in the Layers panel, then drag to reorder. Only the
  single row directly under the pointer moves; the rest of the selection stays put.
- **INVESTIGATED 2026-08-11 — hypothesis confirmed, fix deliberately NOT attempted
  yet.** `LayersPanel.swift:1308` `.onDrag` returns `NSItemProvider(object:
  node.id.uuidString)` and sets `draggingID = node.id`; `LayerDropDelegate
  .performDrop` passes that single id to `handleDrop(_:onto:place:)`, whose whole body
  moves exactly one node. So the selection is never consulted — confirmed.
  **Why it was not fixed in the same pass as BUG-032/033:** `handleDrop` is the most
  intricate function in the panel — parent-offset conversion, artboard attachment via
  `destinationBoard`, drop-into-group vs drop-into-component-source, and
  `insertSibling`'s `afterInModel:` inversion (visual order is the reverse of model
  order). Making it move N nodes as one undoable block means restructuring it to
  accumulate into a single `nodes` array and commit once, and getting the insertion
  ORDER right against that inversion. This is document-mutating code that cannot be
  compiled or run here, and the owner flagged it as "pretty big to fix." A wrong guess
  corrupts layer trees on drag. It deserves its own focused pass, not the tail of a
  long one.
  **Design decisions to settle first, all recorded rather than guessed:**
  1. Expansion rule — dragging a row that IS in the selection moves the whole
     selection; dragging one that is NOT makes it the selection and moves alone
     (Finder/Illustrator). Cheapest correct place is inside `handleDrop`, which
     already has `app.selectedNodeIDs`, so no new `@Binding` plumbing is needed.
  2. Insertion order — chain each node after the previously placed one rather than
     re-anchoring on the target each time, so relative order survives regardless of
     the model/visual inversion.
  3. Mixed-parent and nested selections need a stated rule; refusing with a visible
     reason is better than silently dropping members.
  4. One undo step for the whole move; selection preserved afterwards.
- Original hypothesis (correct as far as it went): the drop delegate carries one layer
  id (the dragged row) rather than
  the current selection set. The `onMove`/drop payload needs to be the full
  selection, reordered as a contiguous block inserted at the drop index, applied as
  ONE undoable mutation. Watch the ordering semantics: dragging a non-contiguous
  selection should collapse it into a contiguous run at the destination, which is
  what Finder and Illustrator both do. Nested/mixed-parent selections need a defined
  rule — likely reparent all to the drop target's parent, or refuse with a clear
  reason rather than silently doing something surprising.
- Acceptance: a multi-row selection drags as a unit and lands contiguously at the
  drop point, preserving relative order. One undo restores the whole move. Selection
  survives the operation. Mixed-parent and nested selections behave per the defined
  rule and never silently drop members. Keyboard-only reordering path still works.

### BUG-031 — Bring to Front / Send to Back ignore a Layers multi-selection
- Type: bug
- Priority: P1
- Area: layers · model · keyboard
- Status: **closed 2026-08-11 — working as designed; no code needed.**
- Repro/Detail: Owner report 2026-08-11. With several layers selected in the Layers
  panel, stepping one at a time (Bring Forward / Send Backward, ⌘] / ⌘[) works, but
  the jump-to-extreme commands (Bring to Front / Send to Back, ⇧⌘] / ⇧⌘[) do not.
- Status update 2026-08-11: **CLOSED — working as designed.** Owner ran the
  discriminating test: *"exactly how I expect it to. Something outside a group would
  just skip over the group; something in the group goes within that group. Exactly
  what it should be doing."* Per-parent z-order scoping confirmed correct and matching
  the owner's mental model, so NO feedback affordance is being built — it would be
  solving a problem that turned out not to exist. The "already at the extreme is a
  silent no-op" observation stands but was not raised as a complaint once the scoping
  was understood; left unbuilt rather than added speculatively.
  One loose thread was spun out to **BUG-039** rather than being waved through: a text
  layer briefly refused to move and then started working again.
- **RE-INVESTIGATED 2026-08-11 after owner testing. The macOS-tab hypothesis below is
  DEAD, and the original symptom did not reproduce.** Owner: *"I used the shift all
  the way to back, that worked. All the way to front/top, that worked."* So ⇧⌘[ and
  ⇧⌘] arrive fine and `reorderSelection` works on a multi-selection — both halves of
  the original report are unreproducible. What the owner DID hit is different and
  intermittent: *"then the down/back keyboard stepping one at a time wouldn't work...
  going from the bottom/back up worked one at a time... unselected and reselected the
  same group of layers, tried down/back, and only one moved."* Owner's own guess —
  *"it can't jump over a group in bulk"* — points at the right place.
- **Explanation, from reading `reorderInParents` (`CanvasView.swift:2883`):** it walks
  the tree and applies the reorder to EVERY parent array containing a selected node —
  the top level, and each group's children, independently. That is deliberate and
  matches Illustrator, where z-order is scoped to the containing group. But the Layers
  panel presents one flat-looking list, so the scoping is INVISIBLE. Two consequences
  produce exactly what was reported:
  1. **"Only one moved."** If a selection spans a group boundary — some layers at top
     level, one inside a group — each moves within its own parent. The nested one may
     already be at the bottom of its group and cannot move, so only the top-level ones
     shift. Nothing is broken; the command is doing per-parent work in a view that
     hides parents.
  2. **"Down/back stopped working."** Once the selection is at the back of its parent,
     Send Backward is a correct no-op. Having just pressed Send to Back, further
     backward steps do nothing — indistinguishable, from the outside, from a dead key.
- **So this is very likely NOT a logic bug — it is missing feedback.** `nudgeOrder`'s
  swap loops were traced by hand for contiguous, non-contiguous, and already-at-extreme
  selections in both directions and are correct in each. Changing the behaviour to move
  a selection across parent boundaries would mean REPARENTING layers on a ⌘[ press,
  which would be worse than the confusion it fixes.
- **NEEDED — a discriminating test before any code, because a verbal recount cannot
  separate the two causes.** Build a document with three top-level layers and one
  group containing two layers. (a) Select two TOP-LEVEL layers only and step down
  repeatedly: they should move together until they hit the bottom, then stop. (b)
  Select one top-level layer AND one layer inside the group, step down: they should
  move independently within their own parents — if so, cause 1 is confirmed and the
  fix is feedback, not logic. (c) Note whether the Layers panel shows them where you
  expect.
- Proposed fix once confirmed, deliberately NOT coded yet since it is a design
  decision: surface the scoping rather than change it. Options to weigh — a brief
  non-blocking note when a z-order command cannot move part of the selection, an
  indication when a selection spans multiple parents, or making the panel's nesting
  read more clearly. Any of these needs to reach VoiceOver, not just be visual.
- Superseded hypothesis (kept as a record of a wrong turn): macOS claims ⇧⌘[ / ⇧⌘] as
  Show Previous/Next Tab via `DocumentGroup`'s automatic window tabbing. Plausible, and
  it fitted the reported asymmetry, but the owner's testing showed both shortcuts
  working. Do not re-file it. `reorderSelection(toFront:)` in
  `CanvasView.swift` already handles the selection correctly: it filters the moved set,
  removes it, and re-inserts as a block via `Self.reorderInParents`, preserving
  relative order. It is not a single-node command. So the bug is almost certainly that
  **the shortcut never arrives.**
  **Leading hypothesis — macOS claims ⇧⌘[ and ⇧⌘].** Those are the system's
  Show Previous Tab / Show Next Tab shortcuts, and EXP uses `DocumentGroup`, which
  gets automatic window tabbing. That would explain the exact asymmetry the owner
  reported — plain ⌘[ / ⌘] work, the shifted pair does not — which no theory about
  EXP's own reorder code can explain.
  **VERIFY BEFORE CODING** (not verified here): open the Window menu and look for
  "Show Next Tab" / "Show Previous Tab" carrying ⇧⌘] / ⇧⌘[. If present, the fix is a
  product decision, not a bug fix — either set `NSWindow.allowsAutomaticWindowTabbing
  = false` (EXP's multi-monitor floating-panel workflow makes document tabs largely
  pointless, but this removes them for everyone) or move EXP's shortcut. Confirm
  first whether the menu-bar items (Arrange ▸ Order ▸ Bring to Front) work when the
  keystroke does not — that isolates dispatch from the command itself.
- Superseded hypothesis: the step commands were written to iterate the selection while
  the jump commands take a single node. Same fix shape as BUG-030 — operate on the
  selection set as an ordered block. Order of application matters: sending several
  layers to the back naively, one by one, reverses their relative order. Apply in
  the correct direction (or move as a block) so relative stacking is preserved.
- Acceptance: with a multi-selection, ⇧⌘] moves all selected layers to the front and
  ⇧⌘[ to the back, preserving their relative order among themselves. One undo step.
  Works from both the Layers panel and the canvas, from the menu bar, and from the
  context menu (command-coverage rule).

### BUG-032 — Creating a group jumps it to the very top of the layer stack
- Type: bug
- Priority: P2
- Area: layers · model
- Status: **done — owner verified 2026-08-16.**
- Root cause CONFIRMED in `CanvasView.group()`: both branches ended in `arr.append(g)`
  / `nodes.append(g)`, and later-in-array means higher z, so the group always landed
  at the very top.
- Fix applied: the group is inserted at the z-position of its TOP-MOST member. Count
  the unselected rows below that member; after removal that count is the insertion
  index, so the group sits above everything that was below its top-most member and
  below everything that was above it.
- Partial by design, recorded so it is not discovered later: the CROSS-PARENT branch
  anchors only on a top-most TOP-LEVEL selected node. When every selected node is
  nested there is no top-level anchor and the old append behaviour is kept. Resolving
  each nested node's top-level ancestor is a bigger change and this is the rarer case.
- Repro/Detail: Owner report 2026-08-11. Grouping a selection places the new group
  at the top of the layer list regardless of where its members were. Owner's
  expectation, which matches Illustrator and Figma: the group should take the
  z-position of its top-most member and go no higher.
- Hypothesis: group creation appends to the end of the parent's children array
  instead of inserting at the index of the highest-ordered selected member. Insert
  at that index after removing the members, and inherit the parent of that
  top-most member rather than always grouping at the root.
- Acceptance: grouping a selection that sits in the middle of the stack leaves the
  group at the top-most member's former z-position, with layers above it still
  above. Ungrouping restores the members to that same position. Group of a nested
  selection stays inside its original parent. One undo step.
- Owner verification 2026-08-16: the reported group-jumps-to-top bug is fixed.

### BUG-033 — A locked layer offers no unlock action in its context menu
- Type: bug
- Priority: P2
- Area: layers · chrome · a11y
- Status: **done — owner verified 2026-08-16.**
- Root cause CONFIRMED, and it was simpler than the entry guessed: `contextMenuEntries`
  in `LayersPanel.swift` had NO lock entry at all — not a disabled one, not for locked
  rows, not for unlocked rows. The hypothesis about the menu being built from an
  "is this editable" test was wrong; the item had simply never been added. The row's
  lock button was the only route.
- Fix applied: a Lock / Unlock entry reusing the row's existing `onToggleLock`
  callback, titled for what it will do to the right-clicked row, and always ENABLED
  including on a locked row — being un-actionable is the point of a lock, being
  un-UNLOCKABLE is a trap.
- Owner clarification 2026-08-16: "right click" meant the locked ITEM ON THE
  CANVAS/WALL, not only its row in Layers. The canvas context menu already contained
  an Unlock item, but its hit path deliberately excluded every locked node, so that
  item was unreachable by clicking the object it was meant to unlock. Fixed with a
  context-menu-only lock-aware hit path. Normal canvas selection still passes through
  locked nodes; right-clicking a locked object selects it and exposes only Reveal in
  Layers + Unlock, not editing/destructive commands. A locked group stops the context
  hit at the group rather than drilling through its lock to a child.
- Command coverage now includes Object-menu Lock/Unlock responder actions. The
  Layers-row context menu still acts on the clicked row rather than a mixed
  multi-selection; that broader behavior is a follow-up, not part of the verified
  canvas dead-end fix.
- Repro/Detail: Owner report 2026-08-11. Right-clicking a locked layer in the Layers
  panel does not offer Unlock, so the only route back is the lock affordance in the
  row. A locked layer being un-actionable is correct; being un-UNLOCKABLE from the
  menu is a dead end.
- Hypothesis: the context menu is built from the "can this layer be edited" test,
  which a locked layer fails wholesale, rather than from an explicit list where
  Unlock is always permitted. Split the menu: lock/unlock, visibility, and rename
  stay available on a locked row; geometry- and content-mutating items disable via
  `validateMenuItem(_:)` with the lock as the reason.
- Acceptance: right-clicking a locked layer row or locked canvas item shows an enabled
  Unlock route; the locked canvas item does not expose editing/destructive actions;
  normal canvas clicks still pass through locked content. Lock/Unlock is also
  reachable from the Object menu and keyboard. Mixed-selection behavior remains the
  explicitly recorded follow-up above.
- Owner verification 2026-08-16: right-click Unlock on the locked canvas item works.

### BUG-034 — Spread is silently dropped on canvas but IS applied in SVG export (text, paths, lines, groups)
- Type: bug (fidelity/divergence) + feature (implement spread for arbitrary silhouettes)
- Priority: P1 — the divergence half. The implementation half is Wave 7.
- Area: color · effects · export · canvas
- Status: **Stage 1 DONE — owner verified 2026-08-19. Stage 2 deferred to v2.4 by
  owner decision 2026-08-21.** The owner confirmed the note appears on a text node with a non-zero
  spread, and independently confirmed the other half of the divergence by finding
  `feMorphology radius` in the SVG export — which is exactly the gap Stage 1 exists
  to disclose and Stage 2 exists to close.
- **STAGE 1 APPLIED 2026-08-19 — disclosure only; nothing stored changed and nothing
  in export was suppressed.** Three parts:
  1. `EffectsRender.previewsSpread(_:)` — one predicate, living next to
     `Silhouette.path(spread:)` so it cannot drift from the renderer, answering
     whether the CANVAS can honour spread for a node (rectangle, ellipse, image yes;
     everything else no). Its doc comment records why the field survives at all.
  2. The Spread field's hover/VoiceOver detail now states the truth in full: where it
     is previewed, where it is not, and that it is still applied in SVG export.
  3. A one-line `info.circle` note appears under the shadow row ONLY when the value
     would otherwise lie — a non-zero spread on a node whose canvas preview ignores
     it. Text carries the message, not colour (WCAG 2.1 AA §1.4.1); it reuses the
     established tertiary caption token rather than introducing a new colour, and
     **that token's contrast was NOT re-measured for this change.**
- Verified for Stage 1: the app target and the EXPThumbnail extension target both
  build (`EffectsRender.swift` is shared with the extension); no stored value is read
  or written by any of the above. NOT verified: the note's wording and placement at
  narrow panel widths, and with VoiceOver.
- **OWNER DECISION 2026-08-11 — keep spread in the model, implement it everywhere
  (Stage 2 committed).** The owner first proposed REMOVING spread entirely — *"if
  'spread' wasn't there, I probably wouldn't miss it... I'd rather remove it for all
  instead of feeling like something is missing because it's inconsistent."* The
  consistency instinct was right; the premise did not survive checking the importers,
  so this was pushed back on with evidence and the owner changed the call.
  **Why removal was the wrong fix — the owner does not control whether spread enters
  their documents.** Three import paths read it today:
  - `Model/RenderedHTMLImporter.swift:2112` parses CSS `box-shadow`'s FOURTH value
    as spread. Ordinary, ubiquitous real-world component CSS.
  - `Model/FigmaImporter.swift:786` reads Figma's native shadow `spread` property,
    which Figma designers use routinely.
  - `Model/SVGImporter.swift:615` reconstructs spread from `feMorphology`, including
    the negative/erode direction.
  Deleting `Effect.spread` would therefore not remove spread from the world — it
  would make EXP SILENTLY DROP it on import from all three sources. That is a direct
  hit on job #1 in the Architecture decisions: *"read a component in accurately,
  losing no important data."* A control that does nothing is an annoyance; silent
  import data loss is the failure this tool exists to prevent. Weigh those
  differently.
  **Why stacking shadows is not a substitute** (the owner's proposed workaround,
  paired with FEAT-023 Duplicate): spread grows the SILHOUETTE before the blur is
  applied; stacking layers multiple blurred copies at the SAME size. At blur 0,
  spread produces a hard sticker/outline edge that cannot be reproduced by stacking
  at any count. More decisively, stacked shadows do nothing for IMPORTED content,
  which is where spread arrives regardless of authoring habits.
  **Resolution:** consistency is achieved by making spread work on every node type,
  not by deleting it — adding rather than removing. `Effect.spread` stays in the
  model and keeps round-tripping. Stage 2 is committed to Wave 7.
- Repro/Detail: Owner report 2026-08-11: "shadow spread not working in effects."
  Clarified same day — **a drop shadow on TEXT**, i.e. a complex/content-based
  caster, not a rectangle or ellipse. So this is NOT a regression against Phase 10's
  documented behavior. But reading the source turned up something worse than the
  known limitation.
- **ROOT CAUSE — confirmed, and it is a canvas ≠ export divergence:**
  - `Color/EffectsRender.swift` → `Silhouette.path(spread:)` handles only
    `.rect`, rounded-rect (per-corner radii offset), and `.ellipse`. Its own comment
    says it plainly: *"Arbitrary custom paths ignore spread (returned unchanged)."*
    Text, open paths, lines, and groups cast from painted CONTENT rather than a
    silhouette path, and `drawDropShadow` then uses `ctx.setShadow(offset:blur:color:)`
    — which has no spread concept at all. **Canvas therefore renders spread = 0.**
  - `Export/ExportRenderer.swift` ~line 404 emits, for ANY node type, whenever
    `e.spread != 0`:
    `<feMorphology in="…" operator="dilate|erode" radius="…"/>` feeding the blur.
    **SVG export therefore renders the spread the canvas just ignored.**
  - Net effect: put a spread on a text drop shadow, see nothing on canvas, export to
    SVG, and the shadow is dilated. What you see is not what you get. By the
    project's own founding test that is the most serious class of defect here — it is
    exactly the round-trip infidelity EXP exists to prevent — so it outranks the
    "spread is unimplemented for complex shapes" framing the owner and Phase 10 both
    started from.
  - VERIFY BEFORE FIXING: (1) whether PNG/PDF raster export follows the canvas path
    (silently no spread) or the export path — if raster and vector export disagree
    with each other too, that widens the bug; (2) whether INNER shadows have the same
    gap — `drawInnerShadow` takes a `hole` described as *"clip shrunk by spread"*,
    which is again path-based, so text inner shadows are likely affected identically.
- **Fix in two stages, because they have very different costs:**
  - **Stage 1 (Wave 2, small) — disclose the gap; do not remove anything.** Waves
    2–6 sit between now and the real fix, and the divergence is live that whole time.
    So annotate the Spread control to say it is not yet previewed on canvas for
    text/paths/lines/groups, and surface the same note on export. Do NOT zero, clamp,
    or strip stored spread values, and do NOT suppress the `feMorphology` emission —
    both would destroy imported data that Stage 2 is about to render correctly. This
    is a disclosure change only. No migration is required, because nothing is being
    removed.
  - **Stage 2 (Wave 7, committed) — implement spread for arbitrary silhouettes.**
- Hypothesis for Stage 2 — more tractable than it first sounds, with one trap:
  1. **Dilate the ALPHA MASK, not the path.** Offsetting glyph outlines as geometry
     (Minkowski sum / polygon offsetting) is genuinely hard and unnecessary. Text,
     groups, lines, and open paths already cast from rendered content, i.e. an alpha
     buffer — so spread becomes a morphological dilate/erode on that buffer before it
     is blurred and offset. This also covers every complex caster in one mechanism
     instead of special-casing each.
  2. **THE TRAP: `feMorphology` uses a BOX structuring element, not a circle.** The
     SVG spec defines the operation over a rectangle of `radius` rx/ry, which is why
     dilated SVG shadows look subtly squared-off at large radii rather than rounded.
     If the canvas implements a "nicer" circular dilation or a threshold-of-blur
     approximation, canvas and SVG export will STILL disagree — just differently, and
     more insidiously, because it would look correct in isolation. To actually match
     the export the canvas must use the same box kernel and accept the squared
     corners. **Verify against the SVG spec (SVG 1.1 §15.14 feMorphology / Filter
     Effects Module Level 1) before writing the kernel; this is from reading the
     export code plus recollection of the spec, and the exact rx/ry semantics and
     edge behavior have NOT been verified.**
  3. **Performance:** naive dilation is O(r²) per pixel. Box dilation is separable
     (horizontal pass then vertical), and each pass runs in O(1) per pixel amortized
     with a running-maximum algorithm (van Herk / Gil-Werman). That keeps it
     interactive. If large radii still cost too much, reuse the EXISTING async tile
     pattern from noise/dissolve (LIFO generation via `tileReadyNotification`) rather
     than inventing a second caching mechanism.
  4. **Resolution independence:** the dilation radius must be expressed in document
     points and converted with the same `scale` already threaded through
     `drawDropShadow`, and clamped like `maxShadowBlurPx` for the same reason.
     Computing it in raw device pixels would make the shadow change shape as the user
     zooms — a classic and very visible bug.
  5. **Negative spread must erode**, matching the `operator="erode"` the exporter
     already emits. Both directions, both shadow kinds.
  6. **Glyphs merging into a blob at large spread is CORRECT** — it is what a true
     offset does and it is the sticker/outline text effect designers reach for. Do not
     let a later session "fix" it.
- Acceptance: (Stage 1) no control silently does nothing — the Spread field states
  where it is not yet previewed; no stored spread value is altered, zeroed, or
  stripped, and a document imported from CSS/Figma/SVG still round-trips its spread
  through save and export untouched.
  (Stage 2) spread visibly grows and shrinks a drop shadow on text, open paths,
  lines, and groups; negative spread contracts; inner shadows honor spread inversely;
  canvas output matches SVG export within antialiasing tolerance INCLUDING the
  box-kernel corner shape; appearance is stable across zoom levels; large radii stay
  interactive. Add golden fixtures covering (1) a text drop
  shadow with positive and negative spread and (2) a CSS `box-shadow` with a non-zero
  fourth value imported and re-exported unchanged — this is precisely the class of
  bug goldens exist to catch, and the import round-trip is the reason the field
  survives at all.

### BUG-035 — Resize/rotate handles disappear inconsistently for items inside groups
- Type: bug
- Priority: P1
- Area: canvas · selection
- Status: **DONE — owner verified 2026-08-19** against their own five-case matrix
  below; all three previously-failing rows now show handles and the two working rows
  did not regress. Diagnosis was confirmed by source reading first, then by that
  matrix.
- Owner also noticed that the edge-resize CURSOR can look flipped when resizing from a
  flat side deep inside repeatedly rotated/flipped groups. **They explicitly decided
  NOT to log it** — nothing is broken, it is a rare arrangement, and they will report
  it if it ever costs them functionality. Recorded here in one line only so a later
  session does not "discover" it and spend time on it uninvited.
- **OWNER'S TEST MATRIX 2026-08-19 (this is the acceptance checklist).** Screenshots
  attached to the report; the artboard's outer group is rotated, which is what makes
  the pattern legible:
  | selection | before | after |
  |---|---|---|
  | one element inside a group | handles ✓ | unchanged ✓ |
  | the whole outer group (a group of groups) | handles ✓ | unchanged ✓ |
  | a group inside a group | **no handles** | handles ✓ |
  | multiple layers inside a group | **no handles** | handles ✓ |
  | multiple groups inside a group | **no handles** | handles ✓ |
  The matrix matched the source reading exactly: the two working rows are the two that
  either pass the `isBoxResizable` type test or sit at the top level where document
  space is valid; the three failing rows are the ones the unified box refused.
- **FIX APPLIED 2026-08-19 — the unified selection transform now runs in the deepest
  COMMON ANCESTOR's local space instead of document space.** New `SelectionSpace`
  (`chain`, `nodes`, `offsets`) replaces `selectionTransformNodesDoc`. It collects the
  selected nodes (minus any with a selected ancestor), takes the longest common
  ancestor-chain prefix, and expresses every frame in that space. Inside a rotated
  group everything is axis-aligned again relative to that group, so one honest box
  exists and no shear can arise on write-back.
  - **Collapses to document space whenever the shared ancestors are a pure
    translation**, so every case that already worked takes the identical code path —
    that is what keeps the two passing rows above from regressing.
  - **Still refuses** (falls back to per-node chrome) when a rotated or flipped group
    sits BETWEEN the common space and a selected node — e.g. a selection spanning a
    rotated group and something outside it. There is no single axis-aligned box that
    is honest about that, so it says so by not drawing one.
  - Drawing, hit-testing and both write-backs were moved into the space together:
    `drawSelectionTransformBox` takes the chain and draws a mapped QUAD (empty chain
    keeps the original axis-aligned `ctx.stroke(rect)` path); `hitTestSelectionHandle`
    computes handle positions in the space and maps them, so handles are hit exactly
    where they are drawn; `snapshotSelectionBaseline` captures the chain for the whole
    gesture so the math cannot change space mid-drag; `.resizeSelection` brings the
    cursor back through the chain; `.rotateSelection` measures BOTH angles in the
    space rather than in view space — measuring in view space would let a flipped
    ancestor reverse the direction of the turn. The now-dead view-space
    `selectionAngle(of:around:)` was deleted rather than left lying around.
  - Perf: `selectionSpace` runs on every mouse-move through the hit-tests, so it walks
    with one mutable ancestor stack and copies the chain only for nodes that are
    actually selected, rather than allocating `stack + [node]` per group.
- **NOT verified:** the owner has not exercised it. Watch, in this order: the two
  previously-working rows (regression risk is highest there, since they now flow
  through a renamed path), then the three fixed rows — check that dragging a handle
  produces the geometry the handle implies inside the rotated group, that ROTATING a
  multi-selection turns the right way (the flip-handedness case), and that undo is one
  step. Instances still get no handles, by design and for the reason below.
- **CONFIRMED RULE (answers the entry's "confirm this first" question).** It is
  PARTLY the Session 61 Refinement item, and that item is now out of date: nested
  leaf nodes were fixed at some point. `drawTransformedSelectionBox` maps handles
  through rotated/flipped ancestor chains, and `hitTestHandle`'s own comment says
  handles "work under ANY ancestor chain … because the resize math itself runs in
  parent-local space." So a rectangle, ellipse, polygon, text, path or image gets
  handles at ANY depth, including inside a rotated group. What is left is two gaps,
  neither about depth:
  1. **`isBoxResizable` is a TYPE test** (`Canvas/CanvasView.swift`): true for
     rectangle / ellipse / polygon / text / path / image, false for group, instance
     and line. Both the drawing and the hit-testing gate on it.
  2. **The unified transform box refuses to engage under a transformed ancestor.**
     `selectionTransformNodesDoc` only collects a selected node when every ancestor
     above it is unrotated and unflipped (`ancestorsUntransformed`), because it lifts
     frames into DOCUMENT space and a doc-space non-uniform scale cannot be written
     back through a rotated ancestor without shearing. A group normally gets its
     handles from that box, so a group inside a rotated group falls through to the
     type test in (1), fails it, and draws a bare outline. Same for a multi-selection
     inside a rotated group: every member is dropped, so there is no box at all.
- **OWNER REQUIREMENT 2026-08-19, stated plainly and worth keeping in these words:**
  *"if a group is selected inside a group, the bounds of that group. or multiple
  layers, ensure the resize and rotate handles surround all that are selected."*
  So the acceptance is behavioural, not architectural: whatever is selected, the
  handles surround it.
- **Proposed fix — run the unified transform in the deepest COMMON ANCESTOR's local
  space instead of document space.** `SelectionTransform`'s own doc comment already
  invites this: *"The caller chooses the shared coordinate space (a group's local
  space or document space)."* Take the selected nodes (minus any with a selected
  ancestor), compute the longest common ancestor-chain prefix, and require only that
  there be no rotated/flipped group BETWEEN that prefix and each selected node. When
  the prefix is empty this is bit-for-bit today's behaviour. When several layers — or
  one group — live inside the same rotated group, that group IS in the common prefix,
  so the box is computed axis-aligned in its local space, drawn as a quad mapped
  through the chain (`parentLocalToDoc`, exactly as `drawTransformedSelectionBox`
  already does), and resize/rotate write-back runs in that same local space where no
  shear can arise. Genuinely ambiguous case that should still refuse visibly: a
  selection that spans a rotated group AND something outside it — there is no shared
  space in which one axis-aligned box is honest.
- Touches drawing, unified-box hit-testing, drag-start baselines and both
  `.resizeSelection` / `.rotateSelection` write-backs. Delicate coordinate code that
  cannot be run here — it deserves its own focused pass, the way BUG-030 did.
- **Instances are a separate question, not part of this fix.** An instance has no
  size of its own in the model: `resolvedSize(of:)` derives it from the source plus
  overrides and auto-layout re-hug, and `InstanceOverride` has no size case. Handle-
  resizing an instance would mean inventing an instance size override, which is a
  fidelity decision (what does a resized instance export as?) rather than a bug fix.
  Logged here so it is not silently folded in.
- Repro/Detail: Owner report 2026-08-11. Selecting some elements inside groups shows
  only a solid bounding box with no corner handles — no resize, no rotate. It is
  inconsistent: sometimes the handles are there, sometimes not, for what looks like
  the same kind of selection.
- Hypothesis: this is very likely the already-logged ROADMAP "Refinement backlog →
  Nested-selection edge cases" item, which records that *"resize/rotate handles are
  hidden for nested items (move-only)"* from Session 61. If so it is not random — it
  is deterministic on nesting depth, and the inconsistency the owner sees is the
  difference between a top-level and a drilled-into selection. Confirm that first;
  if the handles are also missing on some TOP-LEVEL selections, there is a second,
  separate bug. Fixing it properly means resolving the nested item's transform to
  document space, drawing handles there, and inverse-transforming the resize/rotate
  write-back through rotated or flipped ancestors — the same approach the
  align/distribute nested work already took.
- Acceptance: any single selection shows resize handles and a rotate affordance
  regardless of nesting depth, including inside rotated and flipped ancestors.
  Dragging a handle produces the geometry the handle implies. Handle visibility is
  deterministic and explainable, never "sometimes." Closes or explicitly supersedes
  the ROADMAP refinement-backlog entry. See also FEAT-026 (point-selection box).

### BUG-042 — Align/distribute inside a rotated or flipped group works in the group's axes, not the screen's
- Type: bug
- Priority: P1
- Area: canvas · selection · a11y
- Status: **DONE — owner verified 2026-08-19.**
- Repro/Detail: Owner report 2026-08-19 with screenshots, immediately after BUG-041:
  select several layers inside a group that is flipped/rotated and press Align Left
  (to Selection) — they cluster, but not on any edge the user can see. *"Ungrouping
  flips everything back and then alignment works"* — the giveaway, since ungrouping
  bakes the ancestor transform into the children.
- Root cause CONFIRMED, and it was a deliberate design decision that turns out to be
  wrong: `align()` chose parent-local space for siblings, with the comment *"Siblings
  align in their common parent-local coordinate system — even if that group is
  rotated."* The math was correct in that space. The problem is what the command
  MEANS. "Align Left" names a direction the user can see, and its button draws a
  vertical bar. Inside a FLIPPED group, local-left is screen-right, so the control did
  the exact opposite of what it showed; inside a ROTATED group it aligned along an
  axis the user was not looking at. This is an affordance-honesty bug, not a geometry
  bug — which is why it survived: every number was right.
- Fix applied: `selectionAncestorsAreTransformed()`, added to the existing
  `documentSpace` condition in BOTH `align` and `distribute`. Document space was
  already the path used for mixed parents and Align-to-Artboard, and it already
  inverse-transforms each movement through the node's ancestor chain on write-back,
  so this reuses a proven route rather than adding a second one. Untransformed
  ancestors keep the parent-local path exactly as before.
- **Trade-off, stated so it can be reversed on evidence:** inside a group rotated 30°,
  Align Left now produces a screen-vertical line rather than one along the group's own
  axis. That matches the button's icon and the owner's report. If working inside
  rotated groups later makes the group-axis behaviour feel better, the switch is this
  one condition.
- Acceptance: Align Left inside a flipped group aligns to the left edge ON SCREEN;
  the same inside a rotated group aligns to a screen-vertical edge; distribute spaces
  along the screen axis; alignment outside any transformed group is unchanged.

### FEAT-044 — Flip is unavailable in the inspector for a multi-selection
- Type: feature (missing affordance)
- Priority: P2
- Area: inspector · canvas
- Status: **DONE — owner verified 2026-08-19.**
- Repro/Detail: Owner request 2026-08-19: *"if I have multiple items selected,
  including multiple groups, I don't have access to any of the 'flip' buttons to flip
  multiple things at a time, and have to do each manually."*
- The capability already existed — `CanvasNSView.flipSelection(horizontal:)` loops the
  whole selection and commits ONE undo step, and `validateMenuItem` enables Flip for
  any node selection, so the Object menu and right-click already worked. Only the
  INSPECTOR was missing it, which made the panel imply flipping is a single-layer
  action. A good reminder that the command-coverage rule is about every route, and
  that the missing one is usually the one people actually look at.
- Fix applied: the single-selection Flip row was extracted into
  `flipControls(multiple:)` and added to the multi-selection inspector. Single keeps
  the panel's scoped mutation (which is what makes it work inside a component-source
  editor); multi routes through `sendCanvasAction("flipHorizontalAction:")` per the
  project's dispatch rule, so it reuses the existing one-undo-step implementation
  rather than growing a second copy. Help text and VoiceOver labels say "every
  selected layer" in the multi case so the two are not confusable.
- Acceptance: select several layers, including groups, and both flip buttons appear
  and act on all of them as one undo step; the single-selection behaviour is
  unchanged; the buttons work in a component-source editor window.

### BUG-041 — Bounds math ignores flips, so a flipped group's box lands in the wrong place
- Type: bug
- Priority: P1
- Area: canvas · selection · model
- Status: **DONE — owner verified 2026-08-19** ("the bounds look good").
- Repro/Detail: Owner report 2026-08-19 with screenshots, found while verifying
  BUG-036(a): selecting the OUTER group (a group of two groups) drew a selection box
  the right size but visibly in the wrong PLACE — offset up and to the right of the
  art it claimed to bound — while selecting either inner group drew a correct box.
  Owner's own read: *"either I didn't notice this before... or this is new."*
- **NOT new, and NOT caused by the ink-bounds change.** Checked before touching
  anything: `visualBounds` (the old path) and `paintedBounds` (the new one) have
  identical structure apart from the stroke outset, so on unstroked art they return
  the same rect — the ink change cannot move a box. What made it visible is that
  BUG-035 started drawing unified boxes for selections that previously drew none, and
  that the owner was looking closely at boxes for the first time.
- Root cause CONFIRMED by source reading: **neither `visualBounds` nor `paintedBounds`
  handled `flipH`/`flipV` at all** — both only applied `rotation`. The renderer
  disagrees: `CanvasNSView.parentLocalToDoc` mirrors a group's children about the
  group's STORED frame centre and then rotates. When a group's content union is not
  centred on that frame — the normal case once anything has been moved inside it —
  omitting the mirror shifts the computed bounds by twice the distance between the two
  centres. Right size, wrong place, exactly as reported. `drawNodeSelection` already
  carried its own hand-rolled mirror for the per-node hint, which is why the inner
  groups looked right and the outer one did not, and is a good sign the fix belongs in
  the shared math rather than at one call site.
- Fix applied: one shared `mirrored(_:forFlipsOf:frame:)` in `SelectionTransform`,
  applied in BOTH bounds functions after the content union and BEFORE the rotation
  step — matching the renderer's flip-then-rotate order. Leaves are unaffected (a
  leaf's flip mirrors content inside its own frame, so the mirror is the identity).
- **This also silently fixes align/distribute and the inspector's outer-dimension
  readout for flipped groups**, since both read these same functions. Worth checking
  as part of verification rather than assuming.
- Acceptance: the outer group's selection box sits on its art; align a flipped group
  against others and it lands where the box says; the inspector's W/H for a flipped
  group matches what is drawn. No change for anything unflipped.

### BUG-036 — Selection bounds exclude outside strokes and resize in whole pixels
- Type: bug
- Priority: P2
- Area: canvas · selection · model
- Status: **DONE — both halves owner verified 2026-08-19.**
- **(a) IMPLEMENTED 2026-08-19, exactly as decided: ink for the visible box, geometry
  for the math.** Most of the groundwork already existed —
  `SelectionTransform.paintedBounds` and `strokeOutset` were written for the
  inspector's outer-dimension display — so this was mostly a matter of routing the
  selection chrome through them.
  - New in `SelectionTransform`: `unionPaintedBounds`, an `InkInsets` value with
    `inkInsets(of:)` / `outset(_:by:)` / `inset(_:by:)`. The insets are per EDGE, not
    a single number, because a group's widest stroke may be on one side only.
  - The accent selection outline and all eight handles — single node, nested node
    under a transformed ancestor, and the unified box — are drawn at INK bounds, and
    the three hit-tests use the same rect, so grabbing a handle is never offset by the
    stroke width.
  - **The resize math now runs in INK terms and insets back to geometry before
    writing.** That is what makes the box track the cursor exactly while the model,
    align/distribute and export keep storing geometry. The insets are captured at drag
    start and are constant, because a resize does not change stroke width. Whole-pixel
    snapping is applied to the GEOMETRY, not the ink: "whole pixel" should mean the
    stored frame is whole, and a stroke width may legitimately be fractional.
  - **Deliberately still on geometry:** auto-padding overlay bands, component-instance
    chrome, the path outline trace, align/distribute, export, and the inspector's W/H.
    Those describe layout or the authored artifact, not paint.
  - With no stroke every inset is zero and each of these paths is byte-for-byte the
    previous geometry math — the regression guard for the ordinary case.
  - **NOT verified:** owner has not exercised it. Known imprecision to watch: for a
    node whose insets are ASYMMETRIC (a group with different stroke widths on
    different sides) AND which is itself rotated, the resize pivots about the ink
    centre rather than the geometry centre, so the anchored corner can drift by a
    fraction of the stroke width. Symmetric strokes — every uniform stroke, which is
    the normal case — are exact.
- **(b) CONFIRMED then FIXED 2026-08-19.** The hypothesis was right and the cause was
  one line: `CanvasNSView.mouseDragged` computed
  `let bypassSnap = event.modifierFlags.contains(.command)`, and all twelve
  `pxSnap`/`pxSnapRect` sites keyed off it. Whole-pixel rounding therefore ran on
  every drag — move, resize, draw, line endpoints, artboards — with ⌘ as the only
  escape, and was NEVER connected to Snap to Grid. Not the BUG-001 display-only
  rounding; the stored values really were being rounded.
  **OWNER DECISION 2026-08-19: a separate "Snap to whole pixels" preference, not a
  reuse of Snap to Grid.** They are different features — grid snapping also pulls to
  layout-grid columns, rows, baselines and guides — so folding them together would
  mean losing guide snapping just to drag by a half point. Shipped as
  `AppState.pixelSnap` (persisted, default ON so nothing changes for anyone who does
  not turn it off), gating that single `bypassSnap` line so all twelve sites obey it
  at once. Command coverage per the project rule: `togglePixelSnapAction:` on
  `CanvasNSView`, a View-menu item with ⌥⌘' beside Snap to Grid (⇧⌘'), the Grid
  panel toggle next to "Snap to grid", and a Settings default. ⌘ still bypasses
  snapping for a single drag either way.
- **(b) FOLLOW-UP 2026-08-19 — the menu commands had no checked state, which is a
  defect in the same change.** Owner: *"the menu item doesn't have an 'active' state
  so I can't tell if I'm turning it on or off."* Correct, and it applied to Snap to
  Grid too — a `Button` in a menu looks identical whether the thing it toggles is on
  or off, so a toggle command built from one is unusable. Both are now SwiftUI
  `Toggle`s, which render a checkmark and, unlike a Button, expose a real checked
  state to VoiceOver. They read the PERSISTED preference (a Commands scene cannot see
  the focused window's `AppState`, and every synced AppState toggle writes straight
  through to UserDefaults, so the preference mirrors it exactly); writing still goes
  through the responder chain, so the canvas remains the only place the value
  changes. **Not converted: "Show / Hide Grid"** — `AppState.showGrid` is deliberately
  session state with no preference behind it, so there is nothing for a menu checkmark
  to read. Worth revisiting if that menu's inconsistency starts to bite.
- **(b) "not responding" report 2026-08-19 — investigated, no defect found in the
  wiring; retest with the checkmarks.** Verified by reading: the menu dispatches
  through `sendEditorAction` → `sendCanvasAction` (the project's required route, not a
  raw `NSApp.sendAction(to: nil)`); `togglePixelSnapAction:` flips `AppState.pixelSnap`
  and persists it; `mouseDragged` reads it into the single `bypassSnap` gate that all
  twelve `pxSnap`/`pxSnapRect` sites use; `reloadSyncedPrefs` includes the new key, so a
  Settings change reaches open windows live through the existing UserDefaults observer;
  and no other unconditional rounding exists on the frame-write path. The screenshot
  attached to the report shows an OUTLINED-STROKE path whose fractional W/H (49.94 ×
  49.71) predate any drag — snapping only ever acts DURING a drag, so those values are
  not evidence either way. **Decisive test:** with Snap to Whole Pixels checked, drag a
  resize handle on a plain rectangle and watch W in the inspector — it should land on
  whole numbers; uncheck it and the same drag should show two decimals. Note that
  resizing a GROUP scales its children by a ratio, so child sizes stay fractional by
  nature; only the group's own bounds snap.
- **(a) OWNER DECISION 2026-08-19: ink for the visible box, geometry for the math.**
  The box you see encloses outside/center strokes; align, distribute and export keep
  using geometry bounds, and which operation uses which gets documented. NOT yet
  implemented, on purpose: the drawn box and its handles have to move together (a box
  at ink bounds with handles at geometry bounds looks broken), which means the resize
  write-back must inset by a constant stroke outset — the same drawing, hit-testing
  and resize code BUG-035 rewrites. Doing them in one pass is cheaper and avoids two
  conflicting edits to the most delicate geometry in the app.
- Repro/Detail: Owner report 2026-08-11, two related complaints. (a) The bounding
  box still does not enclose an OUTSIDE-aligned stroke, so the visible edge of the
  art sits outside the box that claims to bound it. (b) With snap-to-grid OFF,
  resizing still jumps in whole pixels instead of moving smoothly through fractional
  values.
- Hypothesis: (a) the selection bounds come from the geometric path bounds rather
  than the rendered bounds; outside/center strokes extend past the path by half and
  full the stroke width respectively. There is a real design question here worth
  deciding once and writing down: should the box bound the GEOMETRY or the INK?
  Illustrator offers both. Ink is what the owner is asking for and is the more
  honest default, but geometry must stay available because it is what exports and
  what alignment should use — check what align/distribute currently uses before
  changing anything. (b) sounds like a rounding step applied unconditionally in the
  resize path rather than only when snapping is on; see BUG-001, which records that
  measurements were displayed as whole numbers while the real values were
  fractional — confirm this is not the same display-only rounding.
- Acceptance: (a) selection bounds visibly enclose outside and center strokes, and
  the geometry-vs-ink choice is documented with which operations use which; (b) with
  snapping off, resizing moves through fractional values smoothly and the inspector
  shows them; with snapping on, behavior is unchanged.

### BUG-039 — A layer intermittently refuses to reorder, then starts working again
- Type: bug
- Priority: P2
- Area: layers · canvas · perf
- Status: open — WATCHING, not yet reproducible
- Repro/Detail: Owner, 2026-08-11, while confirming BUG-031: *"there was a moment where
  a text layer wasn't moving up and down... but then it resolved itself moments later."*
  No reliable repro. Owner is watching for it, and suspects deep nesting —
  *"groups in groups in groups"* — may be involved.
- **Why this is logged rather than dismissed.** "It fixed itself" is the signature of a
  STALENESS bug, not of nothing happening. Transient misbehaviour that resolves without
  intervention usually means the model was correct all along and something downstream
  had not caught up. Closing it because the symptom went away would be the wrong call.
- Leading hypothesis: the LAYERS PANEL went stale, not the model. If the reorder
  committed but the panel did not re-render, the row would sit still while the document
  was already correct — and any later event that forced a refresh would make it "start
  working." Two prior notes support this shape: the SwiftUI panel-performance work
  (computed properties in `ForEach` rows causing multi-second hangs) and the
  `resolveGeneration` invalidation invariants around the instance cache. Deep nesting
  fits too — more recursion per row, more chance of a missed invalidation.
- **THE DISCRIMINATING OBSERVATION, next time it happens — this single check decides
  it:** does the CANVAS show the layer in its new z-order while the Layers panel still
  shows the old one? If YES → the model changed and the panel is stale; the bug is view
  invalidation and the panel is the place to look. If NO — the canvas is unchanged too
  → the mutation itself is being dropped, which is a different and more serious bug in
  `reorderInParents`/`commitNodes`. Also worth noting: whether Undo afterwards produces
  one step or none, and roughly how deep the nesting was.
- Do NOT guess a fix before that observation exists. The two branches lead to opposite
  files, and this session already produced three confidently-wrong hypotheses that
  reading source or owner testing had to correct.
- Acceptance: a reliable repro, or enough observations to identify the branch above;
  then the fix, plus whatever invalidation invariant it turns out to have violated
  written down so it does not silently regress.

### BUG-038 — Digits cannot be typed into a layer or component name (BUG-020's fix swallows them)
- Type: bug (regression)
- Priority: P1
- Area: layers · keyboard · a11y
- Status: **done — owner verified 2026-08-11**
- Repro/Detail: Owner report 2026-08-11, recalled while discussing the tool-shortcut
  hazard: *"I did notice a bug that I wasn't able to name something because the
  keyboard command kept activating... it was transparency. I couldn't add a number in
  a layer or object name."* Rename a layer in the Layers panel, type a digit — the
  character never appears and the layer's OPACITY changes instead. So layers cannot be
  named "Button 2", "Icon 24", or anything else containing a number.
- Root cause CONFIRMED: BUG-020 fixed opacity digits at the Layers focus boundary with
  `.onKeyPress(phases: [.down])` on the List, returning `.handled` for every unmodified
  digit. But the rename field's `editing` flag is `@State` declared INSIDE the row view
  (`LayersPanel.swift:1486`), while the key handler lives on the container
  (`:231`). The container therefore has no way to know a rename field is open, and
  swallowed the keystroke. A textbook case of a focus-boundary shortcut that forgot
  text entry is also a focus state.
- Fix applied: new shared `isTypingInTextField()` in `MainWindow.swift`, and the digit
  handler returns `.ignored` when it is true. The helper asks AppKit for the key
  window's actual first responder rather than tracking SwiftUI state, and checks the
  FIELD EDITOR as well as `NSTextField` — AppKit does not make the text field itself
  first responder while editing, it installs a shared `NSTextView` field editor, so
  testing only for `NSTextField` would miss the case that matters. That keeps it
  correct for the rename field, the component-name field, and any field added later
  with no plumbing at the call site.
- **This bug is also the evidence that settles BUG-028.** It is the exact failure mode
  predicted for giving tool letters unmodified key equivalents — a character shortcut
  firing while the user types — except it was already shipped and reached the owner.
  Any BUG-028 solution must use this same guard, and the per-panel approach is now
  disqualified on evidence: BUG-020 took it and produced this.
- Acceptance: a layer, artboard, and component can each be renamed to a string
  containing digits, and typing those digits does not change opacity. With the rename
  field CLOSED, digits still set opacity per BUG-020. Same for the component-name
  field. Verified with VoiceOver active, and with a non-default keyboard layout.
- Follow-up worth checking, not yet done: audit every other `.onKeyPress` /
  `onDeleteCommand` / `onMoveCommand` at a focus boundary for the same assumption.
  `NumericStepping` in `MainWindow.swift` was checked and is safe — it only handles
  arrow keys. The Layers `onDeleteCommand` and `onMoveCommand` were NOT audited.

### BUG-037 — Shift does not constrain new shapes or frames to a 1:1 ratio
- Type: bug
- Priority: P2
- Area: canvas · tools · input
- Status: **done — owner verified 2026-08-11**
- Root cause CONFIRMED: the `.draw` and `.drawArtboard` cases in `mouseDragged`
  never consulted `shift` at all — the constrain check existed only for RESIZING an
  existing node, exactly as hypothesised.
- Fix applied: shared `squared(from:to:)` helper; the larger dimension wins so the
  shape still follows the cursor's dominant direction, and the corner opposite the
  drag origin is the one that moves. Applied to both shape creation and frame/artboard
  creation, BEFORE the pixel snap so both edges round identically and the result stays
  square. `shift` is sampled live each tick, so it can be pressed or released mid-draw.
- STILL OPEN in this family: BUG-005 (Shift does not constrain a new Pen curve handle)
  was NOT covered — the pen path is separate and was left alone rather than guessed at.
- Repro/Detail: Owner report 2026-08-11. Holding Shift while drawing a new shape
  should produce a perfect square/circle; holding Shift while drawing a new frame
  should do the same. Neither constrains.
- Hypothesis: the constrain check exists for RESIZING an existing node but was never
  added to the creation drag. Related: BUG-005 already records that Shift does not
  constrain a new Pen curve handle — same family, likely worth one pass over every
  drag-creation path (shape, frame, line, pen, artboard) rather than three separate
  fixes. Sample the modifier live, per BUG-025, so Shift can be pressed mid-draw.
- Acceptance: Shift constrains during creation for shapes, frames, lines, and
  artboards; pressing or releasing Shift mid-draw updates the constraint live.
  Constraining from a center-drag (Option) composes correctly. Closes BUG-005 in the
  same pass if the shared fix covers it.

### BUG-021 — Cropped groups jump to the wall after child resize; masks do not reduce ownership bounds
- Type: bug
- Priority: P1
- Area: canvas · layers · model
- Status: done (owner verified 2026-08-03 — "Tapps approves")
- Repro/Detail: attach a group to an artboard, resize/move its children so the group
  becomes much wider than the board, then place it with only a small intentional
  sliver visible. EXP re-runs the >50% test as if the group had never belonged to
  the board, moves it into Wall, and removes the crop. "Mask with Top Shape" does
  not help because membership still uses the mask container's original union frame.
  A wall layer dragged into an artboard's Layers rows also has no explicit way to
  establish membership when its current geometry is below 50% overlap.
- Root cause: artboard membership was stateless and read only `node.frame`. The same
  >50% threshold controlled both entry and exit, unmanaged group descendant bounds
  were ignored, and mask content outside the clip still inflated the test geometry.
- Fix applied: schema-4 nodes now persist top-level `artboardID` membership. A wall
  layer still enters only above the existing 50% threshold, but an attached layer
  remains attached while any positive visible geometry overlaps and detaches only at
  zero overlap. Membership bounds use current descendants for unmanaged groups and
  the mask-shape/content intersection for masks; effects remain excluded. Canvas,
  Layers, export, Handoff, duplication, save/open, and artboard carry/delete paths
  use the node-aware resolver. Dropping a wall row on an artboard section header or
  beside/inside one of its rows explicitly attaches it: partial overlap preserves
  position; zero overlap centers it on the board. Group/mask creation and ungrouping
  preserve membership; header drop also covers an otherwise-empty artboard.
- Acceptance: (1) an unattached item at exactly 50% stays on Wall and above 50%
  attaches; (2) an attached group can be dragged to a 1-point visible sliver without
  leaving the artboard, but fully clearing the board moves it to Wall; (3) resizing a
  child does not cause a cropped group to jump; (4) a mask uses its crop bounds; (5)
  Layers drag from Wall into an artboard header/row preserves a partial-overlap
  position or centers a fully off-board layer; (6) save/open and Undo preserve it.

### BUG-020 — Number-key opacity shortcuts fail while the Layers panel owns focus
- Type: bug
- Priority: P1
- Area: layers · canvas · keyboard
- Status: done (owner verified 2026-08-03)
- Repro/Detail: activate Select, choose a group from the Layers panel, then press a
  number key. `1`…`9` should set 10%…90% opacity and `0` should set 100%, but the
  shortcut only worked after selecting the same group directly on the artboard.
- Root cause: the focused SwiftUI `List` consumes the digit key event before the
  sibling AppKit canvas's `keyDown` can see it. This is the same responder-chain
  boundary already handled explicitly for Delete, arrow nudging, and copy/paste.
- Fix applied: Layers now handles unmodified digit presses at its own focus boundary
  and routes them through the same recursive `LayerOpacityMutation` used by the
  canvas. Nested layers and groups update in one undoable **Opacity** mutation;
  Command/Control/Option combinations remain available to the system/app.
- Acceptance: select a top-level and a nested group from Layers, press `4`, confirm
  each becomes 40%, press `0`, confirm each returns to 100%, and confirm one Undo
  restores each change. Canvas-selected opacity shortcuts must continue to match.

### BUG-019 — Offscreen HTML capture imports entrance-animation groups at 0% opacity
- Type: bug
- Priority: P1
- Area: import · WebKit · CodePen
- Status: done (owner verified 2026-08-03; live CodePen ZIP sections visible)
- Repro/Detail: import the owner's CodePen 2.0 ZIP
  (`pure-css-glassmorphism-liquid-glass-ui-kit.zip`). Every `.section` group imports
  at 0% opacity even though the finished page shows those sections. Its CSS applies
  a delayed `cascade-in` entrance animation with an opacity-0 first keyframe and an
  opacity-1 destination.
- Root cause: WebKit may throttle an offscreen window's animations, so the importer
  sampled the finite entrance animation at its first frame after the normal settle
  interval. The CSS was rendered correctly; the captured point in time was not.
- Fix applied: immediately before DOM measurement, rendered-HTML capture enumerates
  Web Animations. It advances every finite animation to its computed end time and
  pauses it, producing the stable destination design. Infinite animations have no
  honest final state, so EXP pauses them at the current browser sample and reports
  that approximation in the Import Report instead of pretending to preserve motion.
- Acceptance: the live ZIP check finds all 26 imported `section.section` groups at
  opacity 1.0; the deterministic delayed-animation fixture passes at Phone and
  Desktop; owner re-import confirms the page sections are visible. Existing pure
  HTML and real-WebKit importer regressions remain green.

### BUG-018 — Nested landmark roles: `complementary` dropped, and the ancestry test was a proxy
- Type: bug
- Priority: P1
- Area: export
- Status: done (owner-verified 2026-08-01 — full package check green, including the
  new negative-case assertion)
- **Correction to the original entry (2026-08-01).** The first version of this entry
  claimed no ancestry check existed at all. **That was wrong.** `SemanticHTMLExporter`
  line ~345 already had
  `if (role == .banner || role == .contentinfo), !semanticAncestors.isEmpty`.
  I searched for `ancestry`/`landmark`/`sectioning` and the code says
  `semanticAncestors`, so the grep missed it. The bug is real but **narrower** than
  first written, and SEMANTIC-HTML-CONTRACT's B2 claim is accurate for two of the
  three roles.
- Repro/Detail: two genuine defects remained.
  1. **`complementary` was never escalated.** Give a component the role
     `complementary`, nest its instance inside a component whose role exports as
     sectioning content (`region` → `<section>`, `navigation` → `<nav>`, another
     `complementary` → `<aside>`, `tabpanel` → `<section>`), and export. The result is
     a bare nested `<aside>` with no `role`. Per HTML-AAM §3.5.10 an `<aside>` inside
     sectioning content computes as `complementary` ONLY with an accessible name, and
     `generic` otherwise — so the authored role is silently lost, with nothing
     reported in the handoff.
  2. **`!semanticAncestors.isEmpty` is not the spec's rule.** Only sectioning content
     and `main` rescope a nested header/footer/aside. An EXP `banner` inside an EXP
     `group`, `toolbar`, `list`, or any other `div`-hosted role is still scoped to
     `body` and already computes as `banner` — but the old condition added a
     redundant `role="banner"` anyway, which ARIA in HTML calls NOT RECOMMENDED.
- Fix applied: `AriaRole.hostRescopesNestedLandmarks` (true when the role's host tag
  is `article`/`aside`/`nav`/`section`/`main` — `search` and `form` deliberately
  excluded, since they are landmarks but not sectioning content) and
  `AriaRole.needsExplicitRoleWhenNested` (`banner`, `contentinfo`, `complementary`)
  in `SemanticHTMLContract.swift`; the exporter condition now uses both.
- Acceptance: `scripts/verify_semantic_html_package.sh` passes, including the new
  `Fixture.nestedLandmarksDocument()` case — three landmarks inside a `region` host
  each emit exactly ONE explicit role, and the same banner inside a `toolbar` host
  emits none, so both the positive and negative are covered.
- Still open, deliberately: `<header>` scoped to sectioning content (HTML-AAM §3.5.50)
  was **not read** — the spec fetch truncated at §3.5.49 — so `banner` is included by
  the same reasoning as `footer`/§3.5.44 rather than by citation. If that turns out to
  be wrong, `needsExplicitRoleWhenNested` is the one line to change. Also not changed:
  whether `complementary` should carry an `.accessibleName` requirement (APG advises
  naming when several exist; not a spec requirement, so not invented here).
- Found by: HTML-IMPORT-CONTRACT §8 reverse-mapping verification, 2026-08-01.

### BUG-017 — Artboard notes reach semantic HTML as an opaque HTML comment
- Type: bug
- Priority: P2
- Area: export
- Status: open
- Repro/Detail: put formatted notes on an artboard (heading, bullets, bold) and export
  standalone semantic HTML. `SemanticHTMLExporter` emits the whole note as a single
  `<!-- EXP artboard notes: ... -->` comment, so the structure a developer or a model
  would read is flattened into one escaped blob. The Handoff Package already does this
  correctly — `HandoffPackageWriter.orientationMarkdown` passes notes through
  `markdownBlockquote`, which does NOT escape, so `**bold**`, `# heading`, and
  `- bullet` survive as live Markdown. The two exporters disagree.
- Hypothesis: the comment predates notes carrying any structure. Notes should reach the
  HTML as real markup (or a structured `data-` payload / `<template>`) rather than a
  comment, since the point of the handoff package is that the artifact is readable.
  Changing this touches the semantic HTML contract and the deterministic package
  goldens, so it needs a contract decision first, not just an exporter edit.
- Acceptance: formatted notes appear in exported semantic HTML with their structure
  intact; SEMANTIC-HTML-CONTRACT.md records the chosen representation; golden fixtures
  updated deliberately; a note containing HTML-special characters is still escaped
  safely.

### BUG-016 — Layer copy/paste fails while the Layers list owns focus
- Type: bug
- Priority: P1
- Area: layers · canvas · clipboard
- Status: done (owner verified 2026-07-27).
- Repro/Detail: select a row in Layers and press Command-C / Command-V. The
  selection is valid, but nothing appears to happen. The layer-row context menu
  also lacked the expected Duplicate action even though the canvas menu and
  Command-D already supported it.
- Root cause: the editable canvas implements `copy(_:)` and `paste(_:)`, but a
  focused SwiftUI `List` is not in that sibling view's AppKit responder chain.
  Delete and arrow nudging already had explicit Layers handlers for the same focus
  gap; copy/paste had never received one. A canvas click also selected layers
  without explicitly reclaiming first-responder status from the last-used panel,
  so canvas-side selection could exhibit the same symptom after inspector work.
  The first fix also exposed two integration gaps: the custom clipboard UTI was
  used by SwiftUI without being exported from the app Info.plist, and SwiftUI
  hoisted nested-row context menus to their enclosing native List cell, causing a
  child-row Duplicate click to invoke the group's action.
- Fix: Layers now registers native Copy/Paste command handlers using the canvas's
  existing JSON pasteboard payload, so both keyboard shortcuts and Edit-menu
  commands work while the list is focused. Paste still routes through the canvas's
  one placement engine, and a canvas click now reclaims keyboard focus. Every
  editable layer-row context menu now includes Copy
  and Duplicate; duplication works recursively inside groups, is one undo step,
  selects the copy, and does not double-copy a child when its selected ancestor is
  also selected. Canvas and Layers duplication now share
  `Document.duplicatingNode`, which also gives copied relationships fresh ids and
  remaps both current and legacy targets. Follow-up after owner clarification:
  sibling insertion is also shared in `Document.duplicatingNodes`; its regression
  check proves a selected nested layer is inserted inside the same group, the
  enclosing group count does not change, and ancestor+child selection copies the
  subtree only once. Follow-up fix: `tapps.exp-design.nodes` is now exported as a
  JSON-conforming clipboard type, and pointer context clicks use an exact-row
  AppKit menu surface while the SwiftUI menu remains available to keyboard and
  accessibility users. Live UI verification in the isolated Debug app confirmed
  one group remains and its child count changes from two to three.
- Acceptance: select a top-level layer and a nested group child from Layers; for
  each, verify right-click Duplicate, Command-D, and Command-C then Command-V all
  create one independent copy in the correct scope. Repeat inside a component
  source editor; Undo must remove each copy in one step.

### FEAT-018 — Duplicate a component source as an independent working component
- Type: feature
- Priority: P1
- Area: components · model · canvas
- Status: done (owner verified 2026-07-27).
- Detail: “Create Instance” intentionally makes another use of the SAME source.
  The owner also needs “Duplicate Component” to fork the definition into a new,
  independently editable source.
- Implementation: Components list and grid context menus, an instance's canvas
  context menu, and Object ▸ Component now offer Duplicate Component. The copy is
  inserted beside the original, named `Name copy` / `Name copy 2`, and opened in
  its source editor. Source, child, state, and relationship ids are fresh;
  accessible-name/state/relationship targets are remapped; nested references to
  other components stay live; existing placed instances remain attached to the
  original source. One undo removes the new source. Live UI verification in the
  isolated Debug app confirmed the Components-row command opens an independent
  `Component 1 copy` source in its editor.
- Acceptance: duplicate a component containing states, nested components, public
  props, and relationships. Editing the copy must not change the original or any
  existing instance. Place an instance of the copy and verify its states,
  relationships, nested content, save/reopen, and handoff export remain intact.

### BUG-015 — Component-state blend-mode edits leak into the shared base
- Type: bug
- Priority: P1
- Area: model · components · canvas · export
- Status: done (owner verified 2026-07-27).
- Repro/Detail: while editing a named component state, change a layer's Blend
  Mode. The change appeared in Default and every sibling state instead of staying
  local to the active state, unlike opacity, fill, typography, outline, and
  visibility.
- Root cause: `InstanceOverride.Value` had no blend-mode case, so
  `ComponentStateEditing.capture` treated the edit as an unrecognized base change.
- Fix: blend mode is now a bounded state/instance override. Capture resets the
  shared base, state application restores the selected mode, instance resolution
  carries it through canvas/raster/SVG/Quick Look, and the parallel semantic HTML
  resolver emits the resolved `mix-blend-mode`. The focused check covers base
  isolation, state reapplication, and JSON round-trip.
- Acceptance: give Default, Hover, and Pressed visibly different blend modes;
  switching states changes only the active appearance; save/reopen preserves all
  three; placed instances, detach, SVG, semantic HTML, and Quick Look agree.

### BUG-014 — Deleting a component source moves its flattened instances off-canvas
- Type: bug
- Priority: P1
- Area: model · components · canvas
- Status: done (owner verified 2026-07-27).
- Repro/Detail: deleting a source from Components appeared to remove every placed
  instance from the canvas, despite the v2.1 preserving-flatten implementation.
- Root cause: `resolvedChildren` already returns source-local frames and the
  replacement group keeps the instance frame, but `flattened` also added the
  instance origin to every child. Group rendering then added the same origin a
  second time. The work remained in the model but was drawn at twice its original
  offset, commonly outside the visible canvas. The original headless check asserted
  the incorrect pre-offset child frame, so it blessed the bug.
- Fix: flattened children remain local to their replacement group. The regression
  check now asserts both local child coordinates and their composed document
  coordinates, while retaining the existing identity, nested-state, relationship,
  and no-data-loss checks.
- Acceptance: delete a source placed on the canvas, inside a group, and inside
  another source; every use becomes a plain group without moving or changing
  appearance; nested components remain live; one Undo restores the source and uses.

### BUG-011 — Reveal-target highlights inside the component, not on the canvas
- Type: bug
- Priority: P3
- Area: inspector · canvas
- Status: done (owner verified 2026-07-27). Owner 2026-07-24: the new reveal (crosshair) control
  works, but "since it's locked into it's own component, it only shows the
  highlight in the component and not on the artboard/canvas area."
- Resolution: owner verified the reveal behavior in the current build and could no
  longer reproduce the misplaced highlight. If it recurs, check active source-
  editor scope and off-screen selection before changing the endpoint logic.
- Low priority under the fidelity-not-prototyping principle: this is a
  verification convenience, not something that affects the exported artifact.

### BUG-012 — A relationship whose SUBJECT no longer exists vanishes silently on export
- Type: bug
- Priority: P1
- Area: export · a11y · fidelity
- Status: done (owner verified 2026-07-27).
- Found by inspecting a real export (owner's `five-tabtest.exph`, 2026-07-24).
  The tabs source held THREE authored relationships whose subject was node
  `658A38F8…` — a layer that exists nowhere in the document or the export. All
  three produced no attribute, no fidelity issue, and no trace of any kind. The
  owner reasonably concluded relationships "weren't working"; in fact they had
  been authored against a layer that was later removed, and the exporter dropped
  them without a word.
- Root cause: `anchoredAttributes` validated only the TARGET against
  `availableDOMIDs`. The subject's DOM id was composed and used as a dictionary
  key, and if nothing ever rendered with that id the entry was simply never
  claimed. A missing target was reported; a missing subject was not.
- Fix: the subject is now checked the same way, raising an `orphanedRelationship`
  fidelity issue that says a connection was authored on a layer that no longer
  exists and asks the designer to remove it or restore the layer.
- Why P1 despite being narrow: silent loss is the single failure mode a fidelity
  tool cannot have. Under the fidelity-not-prototyping principle, data that cannot
  be represented must be REPORTED, never discarded quietly.
- FOLLOW-UP, not done: an orphaned relationship is currently invisible in the UI
  too — its subject never appears as a participant, so the entry cannot be seen or
  deleted from the inspector. It can only be found by reading the file. Needs a
  cleanup affordance (an "unresolved connections" disclosure on the anchor, or a
  Handoff-report action that offers to remove them).

### BUG-013 — Selecting the group that holds both ends offers no anchor
- Type: bug
- Priority: P2
- Area: inspector
- Status: done (owner verified 2026-07-27).
- Detail: `relationshipAnchor` asked for the selection's ENCLOSING group. Selecting
  the group that actually holds a tab bar and its panel therefore looked for that
  group's parent, found none, and returned no anchor — a dead end with nothing on
  screen explaining why. Also made an earlier claim in this backlog wrong: that
  "selecting the enclosing group shows every participant" only held when the group
  was itself nested inside another group.
- Fix: a selected GROUP is now the anchor itself. Groups carry no role and are
  therefore never participants, only containers, so this loses nothing and matches
  what selecting a container is for.

### BUG-010 — Duplicating a group carries its relationships over pointing at the ORIGINAL
- Type: bug
- Priority: P1
- Area: model · canvas
- Status: done (owner verified 2026-07-27).
- Repro/Detail: owner 2026-07-24 duplicated an artboard, changed a link on one
  copy, and saw both behave as one.
- Root cause: `CanvasView.cloned(_:)` re-minted node ids recursively but copied
  `Node.anchoredRelationships` VERBATIM. The copy therefore held entries whose
  subject chain and target still named the original's nodes, so the duplicate
  described the original's structure rather than its own. Anchoring was correct;
  it simply was not carried through duplication.
- Fix: `cloned` now builds an old -> new id map (`freshIDs`) and runs the subtree
  through `Document.remappingAnchors(_:map:)`. Ids NOT in the map are left alone
  on purpose — a source child id is stable across every placement and must never
  be renamed, and a link that genuinely points OUTSIDE the copied subtree should
  keep pointing outside it. The same remap was added to `Document.flattened`,
  which already had an id map and had the identical latent bug.
- Known limit, deliberate: each top-level node is cloned with its OWN map, so a
  relationship anchored at the DOCUMENT root spanning two separately-cloned
  top-level nodes would not remap. Authoring cannot produce that case (the
  neighborhood rule requires a group anchor); only migration can. Revisit if the
  document-root anchor ever becomes authorable.
- Acceptance: duplicate a group holding a tab bar and its panel; set a target in
  one copy; the other is unaffected; both export distinct, non-colliding ids
  (the export half lands with FEAT-012 chunk I-d).

### FEAT-017 — Nested overrides: vary a nested component's content per placement
- Type: feature (model)
- Priority: P1 — the last big Chunk I model item, and the one the owner has hit repeatedly
- Area: model · inspector · export · handoff
- Status: done (owner verified 2026-07-28). All five chunks J-a…J-e are written
  and build clean. J-a…J-c were first owner-verified 2026-07-24 — nested content
  can now be varied per placement from the inspector. J-d built 2026-07-24; J-e's
  acceptance checks and the full signed Debug app, Quick Look, and helper build
  passed 2026-07-27. The complete placement/source/reset/duplicate/detach/save/
  Quick Look/export matrix passed 2026-07-28. J-c is the first chunk the
  owner can actually use. J-b makes nested overrides RESOLVE — they now
  affect drawing and export — but there is still no UI to author one, so the
  feature is reachable only from the headless checks until J-c. J-a is storage only and resolves nothing, so it is invisible
  at runtime — the same safety property that made FEAT-012's I-a easy to verify.
- Origin: owner, repeatedly and in their own words — *"i can't add or change tab
  names on an instance... because i can't set overrides in the nested components
  anyway. i only can edit the source, so i would have to duplicate the component."*
  That is the gap that pushed them toward forking components (FEAT-015) instead of
  reusing one, and it is why a single Tab Bar component cannot serve two tab sets.
- Root cause: `InstanceOverride.targetNodeID` is a BARE node id, resolved against
  the instance's own source children. A nested instance's children are one level
  further down, so nothing can address them — the same class of problem FEAT-012
  solved for relationships, and the fix is the same shape.
- PRECEDENT ALREADY IN THE MODEL, and it should be followed rather than reinvented:
  `NestedInstanceStateOverride` already addresses nested instances by
  `instancePath: [UUID]`, stored on the OUTERMOST placed instance, and
  `repairingStatePaths` already re-roots those paths when a source is deleted.
  Nested overrides are the same idea applied to values instead of state selection.
- DECISION: `ComponentInstance.nestedOverrides: [NestedInstanceOverride]`, each
  `(instancePath: [UUID], targetNodeID: UUID, value: InstanceOverride.Value)`,
  stored on the outermost placed instance. Reuse `InstanceOverride.Value`
  unchanged — text, fill, textStyle, opacity, stroke, componentState — so no new
  value vocabulary appears and every existing consumer already understands it.
- `publicProps` is NOT a gate. Its existing doc is explicit: false keeps an override
  local to EXP, true ADVERTISES it as part of the source's public contract. So all
  overridable fields stay overridable at any depth, and `PublicOverrideProps`
  continues to decide only what the handoff advertises. Do not repurpose it into
  permissions — that would break its stated meaning and make the feature feel
  arbitrary.
- Reset returns to the NEAREST source value: drop the nested override and the value
  falls back through the nested source, then the outer source. Same rule the flat
  case already follows, one level deeper.
- CHUNKS, in dependency order, each meant to land and be verified alone:
  - **J-a — type + storage.** `NestedInstanceOverride` with tolerant decode; no UI,
    no resolution. Invisible at runtime, like FEAT-012's I-a, so it can be verified
    safely before anything moves.
  - **J-b — resolution.** `resolvedChildren` applies nested overrides at the right
    depth. THE load-bearing chunk: every draw, hit-test, thumbnail, SVG, semantic
    HTML, Handoff, and Quick Look path already funnels through `resolvedChildren`,
    so getting this right makes the rest follow. Watch the depth cap and the
    instance cache invalidation (`resolveGeneration`).
    DONE (needs owner build): `Document.pushingNestedOverrides(_:into:)` hands each
    nested instance the overrides addressed to it, applied inside `resolvedLayout`
    BEFORE the reflow — ordering that matters, because a re-hug must measure the
    OVERRIDDEN content, which is the same mistake BUG-007 was about.
    Deliberately ONE level: a path `[a]` becomes an ordinary override on `a`, and
    `[a, b]` becomes a nested override on `a` with the head stripped. `a` then
    resolves through the same function, so arbitrary depth falls out of the existing
    recursion instead of needing its own walk. Appended LAST so the outer
    placement's value beats whatever the source baked in — which also makes RESET
    free: drop the entry and the nearest source value returns, no separate
    mechanism. Groups are descended but never named, matching relationship
    endpoints, so rearranging a layout group cannot break an override. An empty path
    matches nothing by construction (no node id equals nil), which is J-a's
    `isAddressable` contract holding without a filter someone could later delete.
    CACHE: checked, no change needed. `instanceResolveCache` keys on TOP-LEVEL
    instance node ids, which are unique, and nested instances already fall through
    to a fresh resolve. Nested overrides live on the top-level instance, so the key
    is already correct, and any override edit happens outside a drag where the
    normal `resolveGeneration` clear runs.
  - **J-c — inspector.** With an instance selected, expose overridable fields for
    nested children. Mirror the PARTICIPANTS pattern from FEAT-012 chunk I-c, which
    the owner reacted well to: a block per nested child, reached from an ancestor
    rather than by selecting the unselectable.
    DONE (needs owner build). Prompted by the owner seeing an "Overrides" header
    with NOTHING under it: `overridableChildren` recursed into groups but stopped
    dead at `.instance`, so a component whose children are all components had no
    overridable leaves to show. Nothing was broken — there was simply no address for
    a layer one level down, which is the entire point of FEAT-017.
    `overridableTargets` replaces it, returning `(instancePath, node, componentName)`
    and descending into nested components as well as groups. Rows are grouped under
    the nested LAYER's name rather than the source's, because two tabs from one
    component are told apart by their layer names, not by the component they share.
    The flat case keeps its existing bindings untouched — only a nested target
    routes through `nestedOverrides` — so nothing that already worked changes shape.
    Reset is still just the absence of an entry.
    Also fixed the honesty bug the owner actually reported: when there is genuinely
    nothing to override, the section now SAYS so instead of rendering a heading over
    empty space, which reads as broken.
    FOLLOW-UP, same day, owner-requested: rows now show the RESOLVED value — what
    the canvas draws — instead of the raw source value. It was wrong twice over: a
    nested instance normally carries its own overrides inside the parent source (a
    tab bar sets its three tabs to "one"/"two"/"three"), and an active STATE can
    change a value too, so the field said one thing while the canvas said another.
    This fixes the flat case as well, which had the same state-related mismatch.
    `hasOverride` still comes from the STORED entry, deliberately: "what does this
    show" and "has this been changed HERE" are different questions and answering
    both from one place would break the reset affordance. Resolution happens ONCE
    per body evaluation keyed by distinct path, never per row — a computed resolve
    inside a `ForEach` is precisely the shape behind the ~6.2s inspector hangs in
    PERF rounds 8 and 10, and the code says so at the point of temptation.
  - **J-d — export + handoff.** Overrides reflected in HTML/SVG; `publicProps`
    advertised per path so codegen knows what is a real prop.
    DONE (needs owner build). SVG/PDF and the canvas needed NO change — they route
    through `resolvedChildren`, so J-b already covered them. Semantic HTML did:
    `semanticHTMLResolvedChildren` is a PARALLEL resolver (it keeps hidden layers
    so it can emit `hidden`, which is why it does not call `resolvedChildren`), and
    it silently missed J-b's push-down entirely. Same call added, same position —
    before the reflow, so a re-hug measures the overridden content. The duplication
    is the real hazard here, not the logic, so `checkSemanticResolverSeesNestedOverrides`
    now fails loudly if the two resolvers ever disagree again.
    `publicProps` is now ADVERTISED. It had existed on `Node` for a long time and
    appeared nowhere in the package, so a reader had to infer a component's API from
    the raw model tree — exactly the guessing a handoff exists to prevent. The
    README gains a "Component Props" section listing every field marked public,
    including ones on layers inside nested components, addressed by the same path
    shape used elsewhere (groups add no step, since they are structure not
    identity). Its stored meaning is preserved rather than repurposed: this reports
    the declaration, it does not gate anything.
  - **J-e — checks + the acceptance matrix.** Two placements diverge independently;
    a source edit flows through to both unless overridden; reset returns the nearest
    source value; duplicate, detach, delete-source, save/reopen, Quick Look.
    DONE (needs owner build). DETACH needed no code at all — it bakes
    `resolvedChildren`, which J-b already covers, so a nested override survives into
    the detached tree by construction. Verified rather than assumed, and the check
    stays as a regression guard.
    Four acceptance checks added: a duplicate starts identical and then diverges
    without touching the original (BOTH halves matter — copying must preserve
    appearance, editing must not leak); detach bakes the resolved value instead of
    snapping back to source; deleting a component SOURCE leaves no override with an
    unusable path; and the whole document round-trips through save/reopen, which is
    the file the owner actually keeps.
    `AnchoredRelationshipCheck` now covers 17 cases across FEAT-012, FEAT-016 and
    FEAT-017.
- HAZARD, CORRECTED while writing J-a. The plan first said "duplication and flatten
  must remap nested override paths." Checking rather than assuming: DUPLICATION does
  NOT need it. `instancePath` names nested instance nodes that live inside the
  SOURCE, and cloning a placed node never renames source-internal ids — the same
  reason `nestedStateOverrides` already survives cloning untouched. FLATTEN does
  need it, because dissolving a source re-identifies the resolved children a path
  runs through. Handled in `repairingStatePaths` alongside the state-selection
  repair it already did, including remapping `targetNodeID`. Stated precisely here
  because a wrong hazard note is worse than none — it sends the next person to
  patch code that was already correct.
- DONE in J-a (needs owner build): `NestedInstanceOverride`
  (`instancePath` + `targetNodeID` + `InstanceOverride.Value`, reused unchanged),
  stored as `ComponentInstance.nestedOverrides` with tolerant decode so pre-v2.1
  files open unaffected. `isAddressable` makes the empty-path case an explicit
  question rather than a silent filter — an empty path would address the instance's
  own children, which `overrides` already covers, so resolution in J-b must not
  guess at it. Checks added to `AnchoredRelationshipCheck`: round-trip through
  JSON, a legacy instance with no key decoding to empty, and the empty-path rule.
- Acceptance: one Tab Bar component placed twice with DIFFERENT tab labels in each;
  editing the tab source updates both except where overridden; reset restores the
  source label; both export correct, independent HTML.

### FEAT-016 — Check the ROLE at the other end of a relationship, not just that it resolves
- Type: feature
- Priority: P2
- Area: export · a11y · handoff
- Status: done (owner verified 2026-07-28). Focused advisory/package checks and
  the real relationship-heavy acceptance pass both succeed.
  `SemanticHTMLFidelityIssue.Category` gains `.advisory`, kept separate from
  `.semanticRequirement` on purpose — a reader must be able to tell "a rule was
  broken" from "this is legal but probably not what you meant," and collapsing them
  makes the report either alarmist or ignorable. The Handoff README names all three
  distinctly.
  `AriaRole.expectedRelationshipTargetRoles(for:)` holds the pairings, and holds
  ONLY pairings with a spec citation in the doc comment. Two entries today: a tab's
  `aria-controls` expects a tabpanel, a tabpanel's `aria-labelledby` expects a tab
  (both quoted from the WAI-APG Tabs pattern). Everything else returns empty,
  because an advisory that fires on correct work is worse than no advisory.
  `anchoredAttributes` resolves BOTH ends to nodes so it can compare roles, raising
  `unexpectedRelationshipTarget`, and separately counts subjects per target to raise
  `sharedRelationshipTarget` when several tabs point at one panel — worded to say
  plainly that nothing is invalid, since no prohibition was found.
  `AnchoredRelationshipCheck` gained `checkAdvisoryTableIsNarrow`, which asserts the
  two verified pairings AND asserts emptiness for `describedby`, `tablist`, and
  `button` — a guard against someone quietly adding a pairing that feels right.
- Origin: reading the owner's `tab-test3.exph`. Every requirement passed and the
  export is valid, yet two things a reviewer would flag went unmentioned, because
  EXP currently only asks "does this relationship RESOLVE," never "does it point at
  the right KIND of thing."
- Case 1 — a `tabpanel` labelled by its own content. The owner's panel carries
  `aria-labelledby` pointing at a text layer INSIDE itself. `SemanticHTMLContract`
  requires `.labelledByRelationship` for `tabpanel`, and one is present, so nothing
  fires. VERIFIED against the APG Tabs pattern
  (https://www.w3.org/WAI/ARIA/apg/patterns/tabs/): "Each element with role
  `tabpanel` has the property `aria-labelledby` referring to its associated `tab`
  element." So the intended target is a `tab`, and pointing elsewhere is worth
  saying out loud — as ADVICE, since it is valid markup, not a violation.
- Case 2 — several tabs sharing one panel. All three of the owner's tabs resolve
  `aria-controls` to the SAME `tabpanel`. The APG describes a 1:1 association
  ("its associated tabpanel"), but does NOT state a prohibition, so this must be
  advisory and phrased as such. NOT VERIFIED: whether any normative text forbids
  it. Do not upgrade this to an error without finding one.
- Shape: extend the fidelity report with an advisory category — distinct from
  `semanticRequirement` (a rule was broken) and `visualFallback` (we approximated)
  — that says "this resolves, but points somewhere unexpected for this role."
  Reuse `AriaRole.expectedChildRoles` thinking: a per-kind, per-role table of what
  the far end is normally expected to BE.
- Why it matters under the fidelity principle: the export goes to a developer or a
  model that writes component code from it. A link pointing at a plausible-but-wrong
  element produces plausible-but-wrong code, and nothing in the current package
  would warn anyone.
- Acceptance: advisories appear in `manifest.fidelity` and the README, clearly
  separated from hard requirements; nothing is auto-corrected; a correct file
  produces none; each advisory cites the pattern it comes from.

### FEAT-015 — "Duplicate as New Component"
- Type: feature
- Priority: P2
- Area: model · components · menu
- Status: LOGGED 2026-07-24, NOT STARTED
- Origin: owner 2026-07-24, while working out how to make a SECOND tab set. There
  is currently no way to fork a component: you can place instances of it and you
  can edit the source, but you cannot say "give me a new component that starts as a
  copy of this one." The only workaround is rebuilding it by hand.
- Why it surfaced now: with nested overrides not yet built, a component's nested
  parts cannot be varied per instance, so a second tab set MUST be a second
  component. That makes the missing action acutely felt — but the need is not
  contingent on that gap. Forking a component to make a variant is ordinary design
  work, and every comparable tool has it.
- Design notes: fresh source id, fresh child ids, name defaulting to "<name> copy",
  and — the part that is easy to get wrong — `anchoredRelationships` and
  `a11y.rootRelationships` must be remapped through the new child id map, exactly
  as BUG-010 required for node duplication. Reuse `Document.remappingAnchors`.
  Nested instances INSIDE the copied source keep pointing at their own sources
  (a fork copies this component, not the whole dependency tree).
- Command coverage: Components panel context menu, Object menu, and the canvas
  context menu when an instance is selected.
- Acceptance: forking a component produces an independent source; editing the fork
  never affects the original or its instances; relationships inside the fork point
  at the fork's own layers; the dependency graph stays acyclic.

### BUG-009 — Expanding a component in Layers leaves a stale row height (scrollbar wrong until you scroll)
- Type: bug
- Priority: P2
- Area: chrome · layers · perf
- Status: done (owner verified 2026-07-27). If it recurs, the
  follow-up is below — do NOT reach for it first.
- Repro/Detail: owner 2026-07-24. Expanding a component in the Layers panel
  "sometimes" does not size to the expanded content — a scrollbar appears, and
  scrolling once corrects it.
- Root cause: `InstanceLayerRow` held its disclosure state in a private
  `@State var expanded`. Every visible layer inside a component lives in ONE
  `List` row (the top-level `LayerOutlineRow`), and `List` on macOS caches each
  row's measured height. A nested row expanding changed the outer row's height
  without the List being told, so the cached height stayed stale until a scroll
  forced re-measurement. The private state also explains the "sometimes":
  expansion silently reset whenever SwiftUI recycled a row.
- Fix: hoisted nested expansion to `LayersPanel.expandedNested`, a
  `Set<[UUID]>` keyed by a per-PLACEMENT row path (`rowKeyPath`), so the change is
  observable from the List row. Path-keyed rather than id-keyed because the same
  source child appears under every placement of its component — a plain node id
  would have expanded them all at once. `rowKeyPath` is deliberately separate from
  the existing `instancePath`, which addresses nested component instances for
  state overrides; overloading it would have quietly changed which layer a state
  selection applied to.
- IF IT RECURS: the remaining fix is to give each List row an explicit height, or
  to flatten the outline so every visible layer is its own List row (which would
  also make nested rows selectable and keyboard-reachable). Both are real
  refactors of a file with a documented performance history — see PERF-LOG rounds
  8 and 10, where per-row computed properties in this panel caused ~6.2s
  main-thread hangs. Any height computation MUST be hoisted out of the row bodies.

### BUG-007 — Auto layout positions component instances by a STALE stored frame, not their resolved size
- Type: bug
- Priority: P1 (soon)
- Area: model · canvas · inspector
- Status: done (owner verified 2026-07-27; fixed via `Document.reflowed(_:)`, which
  pre-sizes instances via `instanceSized(_:depth:)`, all call sites moved, depth
  capped at 24 so a cyclic legacy document still terminates; the two-tab repro
  now passes. Continue watching redraw perf on large documents.)
- Repro/Detail: Owner repro 2026-07-24. Make a component `tab` that is text
  wrapped in a group with auto padding. Place two instances side by side, group
  them, and give the group auto layout with a 2px gap. The gap and the instance
  positions are computed from something that is not the component's visible
  bounds: the drawn text spills outside the instance box, the magenta instance
  outlines are wider than the blue selection boxes and overlap each other, and
  the spacing does not match 2px. Overriding the text on one instance (e.g.
  "tab" → "tab one") makes the misalignment dramatic — the wider text runs
  straight over its sibling.
- Hypothesis: CONFIRMED by reading the code — an instance has two different
  sizes in the app and they are never reconciled.
  `AutoLayoutEngine.reflow(_:)` handles exactly two things: `.group` (recurse)
  and `.text` with `box == .auto` (re-measure). `.instance` hits neither branch
  and is returned untouched, so the stack/padBlock math uses the instance node's
  STORED `frame.size` — whatever it happened to be when the instance was placed.
  The engine cannot do better on its own: it is a pure `[Node] -> [Node]`
  function with no `Document`, so it has no way to look up a source and cannot
  call `resolvedSize(of:)`.
  Meanwhile every DRAW, hit-test, and selection path does exactly that:
  `CanvasView` lines ~1889, ~4478, ~4928, ~5252, ~5428 all size instances with
  `document.model.resolvedSize(of: inst)`, which re-hugs through
  `resolvedLayout(of:)` and therefore tracks overrides and state live. So the
  instance DRAWS at its resolved size and is LAID OUT at its stale frame. Any
  override that changes the resolved size — a longer text override is the
  obvious one — widens the drawing without moving the siblings.
- Proposed fix: give the reflow entry point document context rather than
  teaching the pure engine about sources. Add `Document.reflowed(_:)` that
  first walks the tree and sets each `.instance` node's `frame.size` to
  `resolvedSize(of:)` (recursively, so nested instances size innermost-first),
  then hands the pre-sized tree to `AutoLayoutEngine.reflowed(_:)`. Keep the
  existing pure engine entry point for callers with no document (EXPThumbnail).
  Then move the 17 `AutoLayoutEngine.reflowed(...)` call sites in
  `Document.swift`, `CanvasView.swift`, `LayersPanel.swift`, `MainWindow.swift`,
  and `DesignLanguagePanel.swift` onto the document-aware form.
  Termination is guaranteed by the Chunk I acyclic source graph. Watch PERF:
  this runs on the draw path, so it must ride the existing per-instance resolve
  cache (`ExpDocument.resolveGeneration`) rather than re-resolving per redraw —
  verify `instCacheHit/Miss` actually move (see PERF-006).
- Acceptance: with the owner's two-tab repro, the gap measures exactly 2px, the
  drawn text stays inside the instance bounds, magenta instance outlines match
  the blue selection boxes, and a text override on one instance re-hugs that
  instance AND pushes its sibling over by the same amount. Same behavior inside
  a source editor and on the document canvas. No measurable redraw regression on
  a large document.


### BUG-006 — Component-state typography and opacity leak into every state
- Type: bug
- Priority: P1 (soon)
- Area: model · inspector · canvas · export
- Status: done (v2.0.1 — owner reports fixed and pushed; extended the state-diff vocabulary with
  `.textStyle` (bounded typography) + `.opacity` cases; capture now diffs both
  into the active state and resets the base text node to pristine; apply,
  instance render, and semantic-handoff resolution all fold the new cases;
  both recorded leak repros closed)
- Repro/Detail: Create a component with Default, Hover, and Disabled states. In
  the source editor, activate Disabled, select its text layer, then change a
  typography property such as color, typeface, size, line height, tracking, or
  case; alternatively change the opacity of the text, background, or root group.
  The edit changes the shared component source, so Default and the other states
  change too. The owner reproduced both opacity and text-style leakage in the
  2026-07-23 Help recording at 37:17–38:45. This makes common state designs such
  as muted Disabled labels unsafe to author.
- Hypothesis: `ComponentStateEditing.capture` only records text-content strings,
  shape/group fills, and visibility. `InstanceOverride.Value` has only `.text`
  and `.fill`; every other visual edit intentionally falls through to the shared
  base. Extend the state-diff vocabulary for bounded typography and layer
  opacity, apply it recursively in state/instance resolution, and emit it in
  semantic handoff without turning geometry or relationships into state-local
  data. Preserve tolerant decoding for existing schema-v2 documents.
- Acceptance: changing a text layer's color, typeface/face, size, alignment,
  line-height unit/value, tracking, case, or a selected layer/group's opacity
  while a non-default state is active affects only that state. Default and sibling
  states remain byte-for-byte and visually unchanged; instances render the chosen
  state correctly; semantic HTML/CSS handoff preserves the state differences;
  undo/redo is one coherent step; old documents still open and save safely.

### BUG-005 — Shift does not constrain a new Pen curve handle
- Type: bug
- Priority: P2
- Area: canvas · vector
- Status: done (v2.0.1 — owner reports fixed and pushed; `penHandleDrag` now takes the live Shift state
  and snaps the dragged handle to axis/45° via `constrainLineEndpoint` (mirrors
  `pathPointDrag`); the opposite handle is re-derived so it stays mirrored;
  new-handle drawing now matches existing-handle constraint behavior)
- Repro/Detail: Choose Pen (P), place an anchor, then click-drag a new anchor to
  pull its Bézier handles. Hold Shift during the drag. The handle continues to
  rotate freely instead of snapping to the same axis/45-degree increments used
  when an existing handle is edited. Reproduced in the 2026-07-23 Help recording
  at 13:44–14:13.
- Hypothesis: the `.penHandle` drag branch calls `penHandleDrag` without its
  current Shift state, and `penHandleDrag` never calls `constrainLineEndpoint`.
  The existing `pathPointDrag` control-handle branches already implement the
  expected axis/45-degree constraint and can supply the behavior to mirror.
- Acceptance: while creating a curved Pen anchor, pressing or releasing Shift
  during the drag immediately toggles axis/45-degree snapping; the opposite
  handle stays mirrored; free dragging is unchanged; existing-handle editing
  remains consistent; one path draw remains one undo step.

### BUG-004 — Custom centered document title uses native popup anchor awkwardly
- Type: bug
- Priority: P2
- Area: chrome
- Status: open
- Repro/Detail: The main window draws a custom centered EXP-styled document title,
  but the native macOS rename/location bubble is still anchored to the left-side
  titlebar document controls. The centered "Edited" label can also fail to appear
  even while AppKit's native edited state is active.
- Hypothesis: AppKit's document rename/location popover is tied to private/native
  titlebar controls. The current implementation keeps those controls alive but
  visually transparent, then forwards clicks from the centered title. A robust fix
  may need either a custom rename/move popover that mirrors the native fields, or a
  better public AppKit anchor strategy using a titlebar accessory/custom view.
- Acceptance: only the centered EXP title is visible; edited state appears under it
  in `EXPColor.accent`; clicking the centered title opens rename/location UI near
  the centered title with no leftover native title glyphs or console warnings.

### BUG-003 — Gradient darkens (color shift) during pan/zoom blit
- Type: bug
- Priority: P2
- Area: canvas · color
- Status: done (v1.2 — verified by owner)
- Update (S174): switching the CGGradient space to sRGB did not resolve the darkening,
  so the root cause is elsewhere. Next hypotheses to test: (a) the offscreen backing is
  premultipliedFirst/BGRA and `cg.makeImage()` -> `ctx.draw` round-trips premultiplied
  alpha, darkening a gradient that has a SEMI-TRANSPARENT stop (check whether the
  affected gradient has an alpha<1 stop while the unaffected one is fully opaque);
  (b) the snapshot CGImage is tagged the window/offscreen space (P3) but drawn into a
  window drawRect context of a different space, so ONLY color-managed content shifts;
  (c) possible interaction with the new HSB/HSL/OKLCH authoring — verify the stored
  RGBAColor values are byte-identical before/after editing via the new picker modes;
  (d) instrument by dumping the affected gradient's stop colors + alphas.
- Update (v1.2): pan/zoom snapshots now render into a document-sRGB offscreen
  backing instead of inheriting the window/Display-P3 space. Other offscreen paths
  keep the old window-space default. Needs owner visual verification on the
  saturated semi-transparent gradient repro.
- Update (v1.2 follow-up): owner testing showed the sRGB snapshot still shifted,
  and that during node drags the moved gradient stayed correct while static
  gradients changed. That localizes the issue to bitmap flattening of static
  content. Current fix: visible gradients and enabled drop/inner shadows bypass
  pan/zoom bitmap blit and force true live compositing for drag gestures when any
  non-dragged visible gradient/shadow content is present. Plain content still uses
  the fast snapshot paths.
- Verified (2026-07-06): owner confirmed the gradient/shadow interaction shift is
  fixed.
- Repro/Detail: A saturated gradient on the canvas visibly darkens while panning or
  zooming, then snaps back to the correct color when motion stops. A near-neutral
  gradient elsewhere doesn't show it. (Anti-aliased text also shimmers slightly mid-
  gesture — that's a separate, expected blit artifact; see note.)
- Prior hypothesis: `PaintRender.drawGradient` built the `CGGradient` in
  `CGColorSpaceCreateDeviceRGB()` — an UNMANAGED device space — while its stop colors
  (and every solid fill) are sRGB. During pan/zoom the scene is drawn into the
  color-managed offscreen blit bitmap (window color space, usually Display P3); an
  unmanaged device-RGB gradient color-matches differently there than in the live
  window device context, so only the blit shifts. Live settle render looked correct.
- Fix attempt: keep gradient interpolation in sRGB, render pan/zoom snapshots in
  document sRGB for plain content, and bypass snapshot flattening entirely when
  visible gradient/shadow content would otherwise change color mid-gesture.
- Acceptance: gradient looks identical while moving and stopped; export unchanged.


### BUG-001 — Measurements shown as whole numbers while real values are fractional
- Type: bug
- Priority: P2
- Area: inspector · canvas
- Status: done (Session 161 — inspector DimFields show 0–2 truthful decimals, measure HUD matches, canvas snaps to whole px by default with ⌘ bypass)
- Repro/Detail: With snap-to-grid OFF, position it so auto-layout / free placement
  yields sub-pixel spacing. The on-canvas ⌥-hover measure labels and every inspector
  numeric field show WHOLE numbers, so a real gap of e.g. 12.4 reads as "12". You
  can't see or type sub-pixel values.
- Hypothesis: display-only precision loss. Every numeric `TextField` uses
  `format: .number.precision(.fractionLength(0))` (MainWindow) and the canvas
  measure/ruler labels round via `Int(...)` (`measureLabel`, `drawRulerNumber`).
  The model stores fractional `CGFloat`, so nothing is lost until the user TYPES a
  value (which then commits the rounded whole number).
- Acceptance: fields + measure labels show a sensible precision (e.g. up to 1–2
  fraction digits, trailing-zero-trimmed) and typing a fractional value keeps it.
  Decide a rounding policy (display vs. stored) and apply it consistently.

---

### BUG-002 — "Publishing changes from within view updates" (~40×) — repro: inspector ↑/↓ stepping
- Type: bug
- Priority: P1
- Area: inspector · chrome
- Status: done (2026-07-20 — owner reports the warning has not reappeared after
  the Session 162f deferred stepper writes and later inspector/menu cleanup; keep
  watching normal tester runs, but remove it from public known issues.)
- Repro/Detail: Owner isolated it (2026-07-02): using the KEYBOARD arrows to
  increase/decrease values in inspector fields fires the warning; it also
  floods ~40× at app launch. Session 124-era mystery, now reproducible.
- Hypothesis: `NumericStepping.onKeyPress` (UI/MainWindow.swift) writes the
  bound value SYNCHRONOUSLY inside the key-press handler, which runs during a
  SwiftUI view update — mutating an @Observable/@Published mid-update is the
  textbook trigger. Likely fix: defer the mutation one tick
  (`Task { @MainActor in value = next }` or `DispatchQueue.main.async`),
  keeping ⌥/⇧ step sizes + key-repeat acceleration identical. The launch-time
  flood may be a second site (window restoration / initial layout writing to
  AppState during body evaluation) — verify separately with a breakpoint on
  the warning after the stepper fix lands.
- Acceptance: zero warnings while arrow-stepping any inspector field (incl.
  held-key repeat), zero at launch; stepping behavior unchanged (±1, ⇧±10,
  ⌥±0.1, acceleration); undo granularity unchanged.

### BUG-040 — Idle PNG repeatedly flips blurry/sharp and drives excessive CPU
- Type: bug · performance
- Priority: P1
- Area: canvas · images · cache
- Status: **done — owner verified 2026-08-16.**
- Repro/Detail: Owner report 2026-08-16. With a screenshot PNG sitting untouched on
  the wall, it repeatedly changes from sharp to blurry and back for no user-driven
  reason. Activity Monitor simultaneously shows EXP consuming excessive CPU; no
  glaring logged error accompanies it.
- Root cause CONFIRMED in `CanvasView.cgImage(for:targetPx:)`: sharp decoded mips live
  only in a 256MB `NSCache`, which provides no retention guarantee. When the exact mip
  is evicted (especially a large screenshot near the cost limit), the next redraw
  returns the 256px fallback and launches the same async decode again. Completion
  stores the sharp mip and calls `needsDisplay`; if that entry is evicted, the redraw
  immediately starts the cycle again. That self-triggering decode/redraw loop explains
  BOTH the visual oscillation and high idle CPU. A second multiplier: requests larger
  than the source PNG produced distinct 4K/8K keys even though ImageIO decoded both to
  the same source-sized bitmap.
- Fix applied: exact image mips used by the latest full canvas render are strongly
  retained until a later full render no longer uses them; fallback mips remain pinned
  while their exact replacement is in flight. `NSCache` still owns the broader bounded
  working set. Requested mip size is clamped to the immutable source pixel dimensions
  before bucketing, so the same smaller PNG is not cached under duplicate oversized
  keys. Export remains on its independent full-resolution path.
- Acceptance: leave the reported PNG visible and do nothing: it stays sharp after its
  first decode and EXP CPU settles rather than continuously decoding. Pan/zoom may
  show one brief soft fallback when crossing a genuinely new mip bucket, then sharpens
  once and stays sharp. Moving away from an image lets the next full render release
  its strong residency; export resolution is unchanged.
- Owner verification 2026-08-16: the blur/sharp oscillation and excessive idle CPU are
  both fixed on the reported PNG document.

## ✨ Features

> **Standing rule for every ARIA / semantics item below (BUG-008, FEAT-011, the
> Chunk I containment work, and anything that follows).** Verify each decision
> against the official documentation — WAI-ARIA 1.2, ARIA in HTML, the ARIA
> Authoring Practices Guide, WCAG 2.1 AA — BEFORE writing code, and record the
> citation in the entry. Owner instruction 2026-07-24: this holds *"even if I ask
> for the wrong thing by accident."* Push back with the source when a request
> contradicts the spec; it has already caught one (removing `aria-labelledby`
> from `tabpanel` would have broken the canonical APG tabs pattern). State
> plainly what was NOT verified. Full text in `docs/WORKING-AGREEMENT.md` →
> "Accessibility decisions are verified, not remembered."

### FEAT-047 — Easily accessible Auto-select Layers canvas policy
- Type: feature
- Priority: P1
- Area: layers · canvas · input
- Status: **needs-verify — implemented 2026-08-24**
- Repro/Detail: The topmost hit-tested layer always replaces the current selection,
  so moving or resizing an object underneath other content requires hiding or
  locking every layer above it. Owner requested Photoshop's explicit Auto-select
  policy, but placed where it does not take multiple clicks to reach.
- Implementation/decision: `Auto-select` is a persistent checkbox in the Layers
  header, mirrored in View and Canvas Settings. It defaults ON to preserve EXP's
  current direct-selection behavior. OFF makes the Layers-panel selection
  authoritative: pressing or dragging the selected object's real geometry moves it
  even through a covering layer; clicking another visible object does not silently
  replace the selection. The normal move route is reused, including Option-copy,
  snapping, nesting, and one-step undo.
- Acceptance: with Auto-select ON, clicking the canvas selects the topmost eligible
  layer as before. Turn it OFF, choose a buried layer in Layers, and drag its visible
  or covered geometry without selecting the layer above it. Arrow nudge, Shift-arrow,
  Option-drag, nested-group movement, locking, and undo remain correct. The checkbox
  is keyboard- and VoiceOver-operable, persists across relaunch, and stays in sync
  between Layers, View, and Settings.

> **Sanaa cluster (FEAT-048 … FEAT-053).** EXP's optional design assistant —
> pen.dev-style "look at the canvas and draw" on the EXISTING agent bridge
> (agents reach in; no LLM or API keys in EXP; everything OFF by default).
> The full design, placement rules, architecture, and per-chunk agent
> instructions live in **`docs/SANAA-PLAN.md`** — read it before starting any
> entry below. Sequencing rule: FEAT-048 must not start until the current
> v2.4 slice (BUG-049…052, FEAT-047, FEAT-027) passes owner verification, and
> 048 → 049 → 050 is the intended order.

### FEAT-048 — Sanaa: `apply_edits` consented, undo-safe write-back (F3 spine)
- Type: feature
- Priority: P2
- Area: export · model · chrome
- Status: **needs-verify — implemented 2026-08-25; NO runtime verification has been
  run yet (see "What is NOT verified" below)**
- Repro/Detail: The agent bridge is read-only. Add ONE transactional write tool,
  `apply_edits` (typed ops: createPage/createArtboard/duplicateArtboard/
  insertNodes/replaceNode/removeNodes), gated behind new default-off switches
  (Settings ▸ Sanaa "Enable Sanaa" + "Allow Sanaa to draw" + a per-document
  first-draw consent sheet). One call = one `setModel` = one undo step named
  "Sanaa: <summary>". In-place ops (replace/remove/insert into pre-existing
  artboards) additionally require the per-document consent. Ops carry an explicit
  `placement` per the owner's 2026-08-25 rules (SANAA-PLAN §3). Fragments
  validate by decoding the real Codable model; any failure rejects the whole
  batch. Caps ≤200 ops/call. New settings are plain Bool defaults — no persisted
  Codable struct (FEAT-022 decoder trap).
- Hypothesis: no model/schema change needed ("Sanaa's desk" is an ordinary page
  by convention), so no EXPThumbnail membership impact — verify when placing any
  new file.
- Acceptance: SANAA-PLAN §6/FEAT-048 test list — socket-script create/undo pass,
  full gate matrix (each switch off ⇒ distinct error, zero mutation), real
  Claude Code batch that saves/reopens/exports identically to hand-drawn
  content, owner AX/appearance pass, and no visible trace of Sanaa when off.
- Implementation 2026-08-25: new app-target-only `Export/SanaaEdits.swift` holds
  the switches (`SanaaPreferences`, plain Bool defaults — no persisted Codable
  struct, per the FEAT-022 trap), the session-scoped per-document consent
  (`SanaaConsent`), and the whole op engine. `Export/AgentBridge.swift` gains one
  tool and becomes async end to end so a tool call can ask the designer a question
  before it answers; `apply_edits` is not even advertised in `tools/list` while
  Sanaa is off. Settings gains a Sanaa pane — the one Sanaa surface that exists
  while Sanaa is off, because it is where you turn it on — and turning either
  switch off clears live consent. The Handoff agent capsule now reads CAN DRAW or
  READ ONLY from the live switches (text, not colour).
- Two design decisions worth keeping: (1) **consent is asked after a dry run, not
  before.** The batch is applied to a copy of the document first, so a call that
  was never going to work ("no node exists with id …") cannot put a permission
  sheet in front of the designer. (2) **The committed value is rebuilt after
  consent returns**, against the document as it stands then — the sheet is
  asynchronous and the designer may have kept drawing while it was up; committing
  the pre-sheet value would silently discard that work.
- Placement/reference detail: agents cannot know an id EXP has not generated yet,
  so `artboardId` and `placement.pageId` accept `"$last"` and `"$<op index>"`
  alongside real UUIDs. That also cleanly decides consent: a batch reference can
  only point at something this batch created, so `insertNodes` is "in place" —
  and consent-gated — exactly when its `artboardId` is a real UUID.
- **What is NOT verified.** The Debug build is green for both the app and
  EXPThumbnail schemes (the new file is app-target only, confirmed against the
  synchronized-group exception set), and `git diff --check` is clean. Nothing
  else. No socket call has been made, no gate has been exercised at runtime, the
  consent sheet has never been displayed, and no VoiceOver/appearance pass has
  been run — the session had no reachable EXP instance and no access to the app's
  sandbox container. `scripts/verify_sanaa_write_gate.sh` was written to run the
  whole SANAA-PLAN §6 test-2 matrix in one command; it has never been executed.
  Treat every acceptance line above as open.

### FEAT-049 — Sanaa: presence layer (activity feed, canvas highlights, announcements)
- Type: feature
- Priority: P2
- Area: chrome · canvas
- Status: open
- Repro/Detail: Applied batches must be visible and reviewable: session-scoped
  in-memory activity feed (client, time, summary, affected ids) with "Select
  Sanaa's changes" and "Go there"; a one-pulse canvas highlight on affected
  nodes (static outline under Reduce Motion); a VoiceOver announcement per
  batch. Draw in the canvas overlay — no companion windows. Command coverage +
  `sendCanvasAction` for the two new actions. Depends on FEAT-048.
- Acceptance: SANAA-PLAN §6/FEAT-049 — scripted batches show correct feed
  order/highlights/announcements, reduced-motion variant verified, menu
  enablement matrix passes, disabling Sanaa clears every surface without
  relaunch.

### FEAT-050 — Sanaa: "Ask Sanaa" prompt starters with placement dialogs
- Type: feature
- Priority: P2
- Area: chrome · canvas
- Status: open
- Repro/Detail: Right-click + Object menu "Ask Sanaa ▸ Complete this… / Draw
  variations… / Do repetitive work…". Sheets collect the owner's placement
  decisions up front (complete: in-place vs duplicate-beside, default
  duplicate; variations: count + same page vs new page, default new page) and
  compose an id-rich prompt onto the clipboard ("Copy prompt for my agent" —
  the external-agent seam stays explicit). Full five-way command coverage; the
  sheet is the parameter surface. Depends on FEAT-048.
- Acceptance: SANAA-PLAN §6/FEAT-050 — enablement matrix across selection
  shapes, pasted prompts drive correctly-placed `apply_edits` batches in a real
  agent, sheets pass keyboard/VoiceOver checks.

### FEAT-051 — Sanaa: guided setup assistant for non-technical designers
- Type: feature
- Priority: P2
- Area: chrome · infra
- Status: open
- Repro/Detail: Three-step guided flow (pick agent → one-click/copy setup →
  "say hello" verification using the existing connection state). Plain-language,
  honest privacy copy.
- **Research gate CLOSED 2026-08-25. Findings below are from current docs; the one
  that decides feasibility has NOT been tested and must be, first.**
- **The format.** DXT was renamed: `.dxt` files are now `.mcpb`, and the CLI is
  `@anthropic-ai/mcpb` (`init`, `validate`, `pack`, `sign`, `verify`, `unsign`,
  `info`). A `.mcpb` is a zip of a local stdio MCP server plus `manifest.json`;
  users install by double-click, drag-and-drop, or Settings ▸ Extensions ▸ Advanced
  ▸ Install Extension. Signing is PKCS#7 with PEM certificates and self-signed is
  supported. **Whether signing is REQUIRED to install, and what a user sees when
  installing an unsigned bundle, is not stated in the docs — do not promise a
  frictionless install until that is observed on a real machine.**
- **Node is the recommended runtime because Claude Desktop ships one.** The docs say
  Node.js "ships with Claude Desktop on macOS and Windows, so users need no separate
  runtime," and strongly recommend it. `manifest.json` also supports a Binary server
  type.
- **Recommendation: port `exp-mcp` from Swift to Node for the bundle.** It is
  `exp-mcp/main.swift`, ~4 KB, and owns no design logic — it is a stdio ↔ Unix
  socket relay. In Node that is roughly 60–80 lines over `net.connect`. Two reasons
  beyond convenience: it uses the runtime Claude Desktop already ships, and it
  sidesteps a real Gatekeeper problem. **A bare Mach-O binary cannot have a
  notarization ticket stapled to it** — stapling supports `.app`, `.dmg`, and `.pkg`
  only, and the workaround is to wrap the binary in a `.dmg`/`.pkg`, which is
  exactly what shipping it inside a `.mcpb` zip does not do. A quarantined Swift
  binary unpacked from a downloaded bundle would depend on an online notarization
  check. Keep the Swift helper for the already-verified Claude Code path; the Node
  one exists for the bundle.
- **THE GATING QUESTION, untested: can a helper launched by Claude Desktop even
  reach EXP's socket?** The socket is at
  `~/Library/Containers/tapps.EXP--design-/Data/Library/Application Support/EXP/agent.sock`
  and `AgentBridgeLocation` notes the sandbox permits AF_UNIX bind only inside EXP's
  container, so it cannot simply be moved. Direct evidence from 2026-08-25: a shell
  running under this project's automation was **denied** even `ls` on
  `~/Library/Containers/tapps.EXP--design-/Data/Library/` — macOS protects other
  apps' container data behind TCC. The shipped Claude Code path works because the
  terminal it runs from has been granted that access. A child process of Claude
  Desktop inherits Claude Desktop's TCC, not the terminal's, and whether that is
  sufficient is unknown.
  **Five-minute test, do this before writing a line of FEAT-051:** hand-write a
  minimal `.mcpb` that does nothing but `stat` the socket path and report the
  result, install it in Claude Desktop, and call it. If it cannot see the socket,
  the one-click extension is not merely harder — it is blocked until the transport
  changes, and FEAT-051 becomes "make the copy-paste setup excellent" instead.
- **Agent detection.** EXP is sandboxed, so do not scan the filesystem for
  `/Applications/Claude.app`. Ask `NSWorkspace` for an application URL by bundle
  identifier instead, read the identifier off the installed app rather than guessing
  it, and treat a nil result as "not detected" rather than "not installed."
  Whether that call succeeds under EXP's entitlements is itself unverified. The
  fallback the owner already specified stands and should be built FIRST, not as a
  degradation: plain "which of these do you have?" buttons, so the flow never
  depends on detection working.
- Acceptance: SANAA-PLAN §6/FEAT-051 — fresh-account walkthroughs with Claude
  Desktop only, Claude Code only, and neither (kind failure naming what to
  install); full screen-reader pass; owner copy review.

### FEAT-052 — Sanaa: the avatar/character
- Type: feature
- Priority: P3
- Area: canvas · chrome
- Status: open
- Repro/Detail: Optional cute avatar (owner-designed assets via
  docs/DESIGN-ASSETS.md manifest) rendered in the canvas overlay near Sanaa's
  latest work; states idle/listening/drawing/done; separately toggleable
  (default follows "Show Sanaa's avatar" switch); decorative
  (`accessibilityHidden(true)`) because every state also surfaces as FEAT-049
  text; honors Reduce Motion; never its own window. Depends on FEAT-049.
- Acceptance: SANAA-PLAN §6/FEAT-052 — state transitions during scripted
  batches, zero trace when off, Reduce Motion swap, no Testing-Mode frame-time
  regression while animating, light/dark/increased-contrast pass.

### FEAT-053 — Sanaa: capability pack / agent etiquette guide
- Type: feature
- Priority: P3
- Area: export · infra
- Status: open
- Repro/Detail: Canonical Sanaa usage guide as a new MCP resource
  (`exp://sanaa/guide`) + repo doc: ids as reference currency, ALWAYS ask for
  unspecified placement (plan §3 verbatim), small honest batches (summaries
  become undo labels), respect Design Language tokens, no removeNodes beyond
  the ask, graceful no-app/no-consent behavior. Host-specific wrappers only
  after real-client testing; raw MCP setup must keep working without them
  (matches the existing deferred capability-packs roadmap item). Depends on
  FEAT-048; refine after FEAT-050.
- Acceptance: SANAA-PLAN §6/FEAT-053 — a cold real-agent session run through
  the three starter scenarios scores clean against the etiquette list, and a
  vague "finish this" makes the agent ask about placement instead of guessing.

### FEAT-021 — Named workspace presets ("Laptop", "Dual-monitor")
- Type: feature
- Priority: P1
- Area: chrome · workspace
- Status: **done — owner verified 2026-08-21.**
- **The entry's "cheaper than it looks" hypothesis was HALF right, and the missing
  half is the whole point of the feature.** Session 79 does persist the docks, the
  mode and dock visibility to `exp.workspaceLayout.v1` — but that is per-document
  `AppState`. The floating trays, and crucially their window FRAMES, live somewhere
  else entirely: app-wide on `PanelHub` under `exp.trays.v1`. A preset built from the
  first store alone would have restored panel ORDER and left every window exactly
  where it was — the opposite of "sick of resizing the panels back to my other
  monitors". `WorkspaceSnapshot` therefore captures BOTH halves.
- Fix applied 2026-08-19:
  - `WorkspaceSnapshot` (workspace + mode + dock visibility + trays) and
    `WorkspacePreset` (id, name, snapshot) in `PanelDock.swift`;
    `AppState.workspaceSnapshot` / `applyWorkspaceSnapshot(_:)` read and write both
    stores, writing the dock half inside one `restoringLayout` pass so the property
    observers do not save four intermediate states.
  - Presets live app-wide on `PanelHub` (`exp.workspacePresets.v1`) with save /
    update / rename / delete, plus `activePresetID` for the checkmark. Saving under an
    existing NAME replaces it rather than duplicating — two workspaces called "Laptop"
    help nobody.
  - **DECISION 1 (the entry asked for it): switching does NOT auto-save the outgoing
    preset.** Update is an explicit command. Photoshop's rule, and the less surprising
    one: an arrangement you nudged while working should not silently become the saved
    one.
  - **DECISION 2: a preset whose monitor is missing is clamped onto an attached
    screen.** `clampedToAttachedScreen` requires a real overlap — 80pt wide, enough to
    grab the tray's grab bar — before it accepts a frame, otherwise it moves the
    window onto the main screen. macOS will happily place a window somewhere with no
    way back, and a workspace feature that can strand your panels is worse than none.
  - **`PanelWindowManager.applyTrayFrames()` is new and was necessary:** `reconcile()`
    only OPENS and CLOSES windows, because in normal use frames flow the other way
    (the window moves, the delegate records it). Restoring a preset is the one case
    that needs the reverse, so it is an explicit call rather than making reconcile
    fight the user's dragging.
  - Command coverage: the same `WorkspacePresetMenuItems` view is used by **Window ▸
    Workspace** and by the toolbar's existing workspace control, so there is one
    implementation of each command and both routes agree. Naming uses an `NSAlert`
    with a labelled text field — invoked from the menu bar, where there is no view to
    hang a sheet on, and keyboard/VoiceOver operable as-is. The suggested name is
    derived from how many screens are attached ("Laptop" / "Dual-monitor").
- **FOLLOW-UP 2026-08-19 — workspace MODE is now app-wide.** Owner found it while
  testing: with two documents open, switching one window to Multi-Window left the
  other in single mode, yet the other window still showed the checkmark on the saved
  preset. The checkmark was not the bug — presets are app-wide and correctly so; the
  MODE was, because it lived per document window.
  It has to be app-wide: Multi-Window has ONE shared set of floating panels pointed at
  the frontmost document, so a second window left in single mode would show docked
  panels while the shared trays simultaneously claimed to serve it. The value still
  lives per window (each keeps its own dock arrangement, which is right), but the
  CHOICE propagates: `PanelHub` now keeps a weak registry of every open document's
  state, `propagateWorkspaceMode(_:from:)` pushes a change to the others, and a
  `propagatingMode` flag breaks the loop each `didSet` would otherwise start. A window
  opened while the app is already in Multi-Window mode joins in that mode rather than
  appearing with docks. Owner's own framing of the trade, which is the right one:
  single-window mode legitimately shows one set of panels per document window, and
  that difference between the modes is expected.
- Owner verification 2026-08-21 covered the preset workflow and multi-window
  behavior. The regression checks that matter for future changes remain: save a preset on
  the multi-monitor setup, rearrange, switch back, and confirm the floating panels
  return to the right SCREENS; save a second preset and switch between them; unplug a
  monitor and apply the preset that used it — every window must still be reachable;
  confirm presets survive relaunch; confirm rearranging after switching does NOT
  quietly change the saved preset; and with two documents open, switch modes and
  confirm BOTH windows follow, including a document opened after the switch.
- Repro/Detail: Owner request 2026-08-11, opened with "the time has come" — the
  single most-wanted item on the list. Owner runs multiple monitors (including a
  vertical 27") and is "sick of resizing the panels back to my other monitors."
  Wanted: save the current arrangement under a name, switch between saved
  arrangements, and have the app restore the right one. This is the already-open
  ROADMAP Phase 13d box: *"Save / name / switch multiple named workspace presets
  (e.g. 'Laptop', 'Dual-monitor'); a picker in the mode/workspace control."*
- Hypothesis: cheaper than it looks, because the hard half already shipped. Session
  79 persists the whole arrangement — panel order/column, collapse state, group
  weights, column widths, workspace mode, dock visibility — to UserDefaults under
  `exp.workspaceLayout.v1`, and `AppState.trays` is the multi-window arrangement
  model. A preset is that same payload keyed by a user-supplied name, so the work is
  a dictionary of blobs plus Save / Save As / Rename / Delete / Switch and a picker
  in the existing mode control. Two decisions worth making deliberately: (1) whether
  switching presets auto-saves modifications to the outgoing preset (Photoshop does
  not; it requires an explicit re-save, which is less surprising) and (2) what
  happens when a preset references a monitor that is not currently attached —
  clamping windows back onto an available screen is the humane behavior, and macOS
  will otherwise happily place a window somewhere unreachable.
- Acceptance: an arrangement can be saved under a name, listed, switched, renamed,
  and deleted. Switching restores panel positions, sizes, collapse state, and
  workspace mode. A preset whose monitor is missing restores onto an attached screen
  with every window reachable. Presets survive relaunch. The picker is fully
  keyboard operable with sensible VoiceOver names, and Reset Panel Layout still
  works. Command-coverage: menu-bar items under Panels, plus the picker control.

### BUG-046 — Workspace checkmark shown against a preset that is not active
- Type: bug
- Priority: P3
- Area: chrome · workspace
- Status: **fixed 2026-08-20, builds clean, owner verified 2026-08-20.**
- Repro/Detail: Owner 2026-08-20 — *"the workspace name has a checkmark next to it
  pretty much always."*
- Cause: the checkmark tracked `PanelHub.activePresetID`, which is set when a preset
  is applied or saved and — by FEAT-021's own deliberate decision — never cleared
  when the user rearranges panels. That decision was made to stop the checkmark
  flickering during a drag, and it traded a flicker for a checkmark that means
  nothing.
- Fix: `WorkspaceSnapshot.matches(_:)` compares the CURRENT arrangement against each
  preset — mode, dock visibility, a dock signature (groups, order, active tab,
  collapsed, weights, widths), and the trays matched by content rather than array
  position, with their glue grouping compared structurally rather than by group
  UUID so re-making the same pairing by hand still counts. Window frames compare
  with a 2pt tolerance, which is what kills the flicker without lying: a one-point
  nudge, or macOS rounding a frame as it clamps a window onto a screen, does not
  drop the tick.
- `activePresetID` is unchanged and still drives Update / Rename / Delete. Those act
  on the preset you are WORKING ON, which is a different question from what is on
  screen — updating a preset you have drifted away from is the entire point of
  Update.
- Acceptance: the checkmark appears beside exactly the preset whose arrangement is
  displayed, disappears as soon as the layout is changed, and returns if the layout
  is changed back. No preset shows a checkmark when the current layout matches none.

### FEAT-022 — Panel edge-snap ("magnet") with an explicit pop-apart control
- Type: feature
- Priority: P2
- Area: chrome · workspace
- Status: **done — owner verified 2026-08-21.** Two earlier cuts merged the windows into one; the
  owner's second round of feedback killed that approach outright and they chose the
  replacement (see "THE MODEL CHANGED" below). Everything from the merge cuts that
  survives — the dwell gesture, the seam, the unlink control — is unchanged in
  intent; only the container changed. Built to the
  owner's design below, on the one-window/two-columns implementation, and the one
  detail flagged as "needs designing, not assuming" (item 4's leftover area) was
  decided by the owner: transparent, NOT click-through.
- **OWNER REPORT 2026-08-20, first use — two blockers and a third found chasing them.**
  Their words: *"connecting two panels does not honor the individual heights or
  position where they currently are"* and *"connecting a panel/group of panels turns
  the other one into the exact same thing."*
  1. **DUPLICATE COLUMN IDS — the visible catastrophe.** `PanelTray.allColumns`
     synthesises column 0 with `id: tray.id`. Gluing DEMOTES a whole tray into a
     column, so the merged tray held two columns carrying the same UUID.
     `ForEach(id:)` rendered one of them twice — hence "turns the other one into the
     exact same thing" — and every column-keyed lookup (`movePanel`,
     `toggleCollapsed`, `unglue`) resolved to column 0. Fixed by
     `PanelHub.uniqued(_:trayID:)`, applied inside `rebuilt` so every write funnels
     through it rather than each call site remembering.
  2. **The connect realigned the windows — and that was a DESIGN mistake, not a
     bug.** The first cut forced a shared top and kept height only, on the reasoning
     that item 2's "you shouldn't have to line them up" was about the gesture rather
     than the result. It is not: item 4 says the glue spans "the height the two
     panels actually SHARE", which only means anything if they are allowed to sit at
     different heights. `TrayColumn` now carries `topFraction` as well as
     `heightFraction`, the merged window is the vertical UNION of the two, each
     column keeps its exact on-screen rect, and the glue strip spans the
     INTERSECTION of the two spans.
  3. **Found while fixing those: every pre-FEAT-022 tray silently failed to
     decode.** `PanelTray` used SYNTHESISED `Codable`, and Swift's synthesised
     decoder does not fall back to a property's default for a missing key — it
     throws. So the first launch after FEAT-022 hit `keyNotFound(extraColumns)`,
     `loadTrays()` swallowed it, and the whole saved panel arrangement reverted to
     the seeded default with no error anywhere. `PanelTray` and `TrayColumn` now
     have hand-written `init(from:)` using `decodeIfPresent` for every post-v1
     field. **Rule this earns: any Codable persisted to UserDefaults in this app
     needs hand-written decoding the moment a field is added to it.**
- **OWNER'S DESIGN 2026-08-19 (their words, condensed — this is the spec):**
  1. Drag a panel so its edge is right next to another panel's edge and a **vertical
     insertion line** appears between them, like the Layers drag indicator.
  2. **Vertical alignment does not matter.** No lining up headers to connect.
  3. **PAUSE and the line transitions** to signal the about-to-connect state.
  4. Connected state adds a **narrow vertical "glue" strip**, spanning ONLY the
     height the two panels actually share — full height if equal, the shorter one's
     height if not.
  5. A **small unlink button** sits at the vertical middle of the glue strip.
  6. Dragging anywhere else in the glue, or any panel's header in the group, **moves
     the whole group**.
  7. Width of the glue needs tuning, and **resizing either column must still work**.
  8. Vertical stacking within a connected column keeps working exactly as it does now
     (owner: that already works great).
  9. Resizing a glued panel taller or shorter **re-spans the glue**, and the unlink
     button re-centres.
  10. **Not pausing long enough leaves them independent** — so anyone who wants panels
      merely adjacent is not forced into a connection.
  11. **⌘` window cycling treats a glued group as ONE window.**
- **Dwell timing — use the system's, not a guess.** The owner asked for a proven
  standard rather than their estimated ~1s. macOS already has one for exactly this
  gesture class (hold a drag over a target to make it act): spring-loading, read from
  `com.apple.springing.delay`, which is **0.5s** on the owner's machine, with
  `com.apple.springing.enabled` on. Reading the preference rather than hardcoding also
  means someone who has lengthened it for motor reasons gets this feature at their own
  pace, and someone who has disabled springing entirely can be given the explicit
  route instead.
- **THE CAVEAT, stated plainly because this repo has scar tissue here.** Item 6 —
  "dragging moves the whole group" — is, implemented literally as N separate windows
  moved together, EXACTLY what Session 80 did and Session 82 removed for being choppy:
  it syncs N windows on every drag tick. The approach phase in this design is cheap
  (just an indicator), but the post-connection phase would walk straight back into the
  known problem.
- **RECOMMENDED IMPLEMENTATION — one window, two columns.** Connecting MERGES the two
  trays into a single `PanelTray` window laid out as two columns, which is what Phase
  13c deferral (a) proposed. Every item in the owner's design then falls out of the
  window rather than being simulated across windows:
  - (6) moving the group is moving ONE window — smooth by construction, no per-tick
    syncing;
  - (11) ⌘` treats it as one window because it IS one window;
  - (5)(9) the glue strip and its unlink button are just a divider VIEW inside that
    window, so re-spanning and re-centring are ordinary layout;
  - (7) resizing either column is a splitter inside the window;
  - (8) vertical stacking inside each column is the existing tray behaviour untouched;
  - (5) unlink reuses the header pop-out mechanism Session 82 already shipped, which
    deferral (b) records as the answer to "drop-outside is not catchable in SwiftUI
    drag-and-drop".
- **The one detail that needs designing, not assuming:** item 4's partial-height glue.
  A window is a rectangle, so two columns of different heights inside one window leave
  an empty region. Options to decide before coding: let the shorter column's leftover
  area be transparent AND click-through (closest to the owner's picture, needs a
  hit-test opt-out so clicks reach whatever is behind); or make the columns equal
  height on connect (simplest, but silently resizes a panel the user just placed).
  Pick deliberately and write down which, because it is the difference between the
  feature looking like the sketch and looking like a normal split window.
- **THE MODEL CHANGED 2026-08-20 — one window with columns is GONE.** Owner, on the
  second cut: *"the dead space is not going to work. because it's NOT just the narrow
  space between the panels, but it is removing access to the ENTIRETY of my screen"*,
  *"the close button is really awkward"*, and *"i can only drag the panel from the
  very top bar."* All three are the same fault. Merging two panels into ONE window
  forces that window to be the UNION of both rectangles, and once the two sit at
  different heights the union is most of the screen. That gives you: a vast
  transparent region that eats every click aimed at what is behind it, one set of
  traffic lights stranded in empty space belonging to no panel, and a window whose
  only reliable drag handle is a title bar floating nowhere near a panel.
- **The replacement, chosen by the owner from three options: `NSWindow.addChildWindow`.**
  A glued group is N SEPARATE windows sharing a `PanelTray.groupID`. Each keeps its
  own size, its own position and its own close button; macOS moves and orders them
  together. There is no union rectangle, so there is no dead area to make
  click-through and nothing is ever realigned on connect.
- **This is NOT the Session 80 mistake, and the difference is exact.** Session 80
  moved N windows from OUR code on every drag tick. Here the window server does it.
  The only per-drag work is ONE re-parent at `windowWillMove`: whichever window the
  user grabbed is promoted to its group's AppKit parent, so the rest follow it
  (item 6). After that, zero work per tick. `applyGrouping()` is idempotent for the
  same reason — it runs on every `trays` change, and `trays` changes on every
  recorded move, so it must do nothing in steady state.
- **What each design item maps to now:** (4) the seam is drawn INSIDE the right-hand
  window along its glued edge and spans only the vertical range the two frames
  overlap; (5) the unlink button rides at the middle of that span; (6) the seam's
  move areas are AppKit `mouseDownCanMoveWindow` views placed as SIBLINGS of the
  button — the first cut put one UNDERNEATH the button and SwiftUI's hosting view ate
  the drag, which is exactly the "only the unlink button responds" report; (9) the
  seam reads both live frames, so resizing either window re-spans it and re-centres
  the button with no bookkeeping; (11) only a group's parent takes part in ⌘`
  cycling (`.ignoresCycle` on the rest), so the group is one stop.
- **Also fixed from that round:** every tray window now has a grab bar, even a
  single-panel one. It previously appeared only for a tray with 2+ panels, so a lone
  panel's window had no drag handle at all except the empty titlebar strip.
- **RESOLVED 2026-08-20 — the header-drag conflict.** Item 6 says "any panel top moves
  the entire group", but a panel HEADER's drag already means "move this panel to
  another tray" (Session 82, and the only way to rearrange panels between windows).
  Owner's call: *"the smaller 'panel header' for moving is fine"* — the grab bar and
  the seam move the group, header drag keeps meaning "move this panel". No modifier,
  no second gesture.
- **CRASH on first run of the third cut, then AGAIN after the first fix.
  EXC_BAD_ACCESS (code=2) at a stack address — a ~27,500-frame stack overflow.**
  - **First diagnosis (WRONG, kept as the record of a misread):** the trace showed
    `windowWillMove` → `promoteToGroupParent` → `applyGrouping` → `addChildWindow`
    and I read it as our own mutual recursion — `addChildWindow` orders the window
    it adopts, posting that window's `willMove`, which promotes it, which re-parents
    again. A re-entrancy guard plus a "mouse button is actually down" precondition
    were added. **It crashed again in exactly the same place**, which was the clue:
    the ~27,500 repeated frames contained NONE of ours. Our recursion would have
    shown our frames.
  - **Real cause: a parent/child CYCLE.** `applyGrouping` detached and attached in a
    single pass over an unordered dictionary. When the parent role swapped (A was
    B's child; A must now be B's parent) the loop could reach B first and attach B
    to A *while A was still a child of B*. AppKit then recurses without bound inside
    `addChildWindow` trying to order a cycle. Fixed by making it TWO passes: every
    stale link is removed before any new one is made, plus a `want !== window` guard.
  - **And the mid-drag re-parent is gone entirely, because it was the wrong idea.**
    Handing the parent role to whichever window was grabbed meant re-parenting live
    windows during an active drag — the thing that created the cycle in the first
    place. A group's parent is now STABLE for the life of the group, and a window
    that merely follows it redirects its own drag: `WindowMoveArea` reports
    `mouseDownCanMoveWindow` only when this window IS the one that should move, and
    otherwise takes the mouse itself and moves the parent one `setFrameOrigin` per
    event. Still ONE window moved per tick — the Session 80 failure was N.
  - **Lessons for this file:** any AppKit call that moves or orders a window is heard
    by our own window delegates; and **when a stack overflow's repeated frames are
    all system frames, the recursion is in the framework, not in your callback** —
    look for a structure you handed it that cannot terminate.
- **DECISION on the open detail (item 4's leftover area).** The owner was given the
  trade plainly: transparent-and-click-through matches the sketch but needs a global
  mouse-moved monitor to hit-test, which this app's input-to-frame budget cannot
  absorb. Their instruction: *"IF the cursor-tracking hack will not affect performance
  of the app, then do that. If it would add or threaten to add 'delay' to anything in
  the app, then the dead spot would be slightly better."* It would. So the leftover
  area below a shorter column is **transparent but a dead zone** — the window is
  `isOpaque = false` and nothing is drawn there, so it genuinely disappears; clicks
  land on it rather than passing through. No global monitor was added.
  **_MOOT as of the third cut_** — with separate windows there is no leftover area at
  all. Kept because the reasoning still applies to any future one-window idea: the
  moment a panel container is the union of two rectangles, this question comes back.
- Fix applied 2026-08-20:
  - `TrayColumn` + `PanelTray.extraColumns` / `firstWidth` / `firstHeight` / `isGlued`
    / `allColumns` in `PanelDock.swift`. Column 0 IS the tray's own `panels` /
    `collapsed`, so every operation written before columns existed keeps working on an
    unglued tray untouched — that is what makes item 8 (vertical stacking works
    exactly as it does now) true by construction rather than by re-testing. Trays
    written before this decode unchanged: `extraColumns` defaults to empty.
  - `PanelHub.glue(_:into:movingOnLeft:)` merges two trays into one window whose
    columns keep the widths and heights they had, `unglue(columnID:from:)` detaches a
    column in place and shrinks the window by exactly the width that left, and
    `resizeColumns` / `setColumnHeight` / `normalizeColumnHeights` drive the splitters.
    `movePanel`, `toggleCollapsed`, `tearOutPanel`, `togglePanel` and `isPanelInTrays`
    are all column-aware.
  - `TrayWindowView` renders a glued tray as an HStack of columns separated by a glue
    strip: the strip spans only the shared height (item 4), carries the unlink button
    at its vertical middle (item 5), drags the whole group from its body (item 6 — one
    window, so this is a native window drag, not per-tick syncing), and puts the column
    splitter in a 5pt hot zone at each of its edges so item 7 does not eat item 6.
    Re-spanning and re-centring (item 9) are ordinary layout, so they are free.
  - `GlueGesture` is the connect gesture: a tray window's `windowDidMove` looks for
    another tray's facing edge within 14pt with at least 40pt of vertical overlap
    (item 2 — no lining up), shows a vertical insertion line between them (item 1),
    and arms after the drag PAUSES for the system spring-loading delay (item 3).
    Releasing while armed glues; releasing early leaves them independent (item 10).
  - `tearOutPanel` on a glued column's last panel routes to `unglue`, so the pop-out
    button Session 82 shipped is the unlink control too, rather than a second
    mechanism.
- **Dwell is the SYSTEM's, read not hardcoded** — `com.apple.springing.delay` (0.5s on
  the owner's machine). Someone who has lengthened it for motor reasons gets this
  gesture at their own pace; someone who has turned `com.apple.springing.enabled` off
  gets no dwell gesture at all, and reaches the same result through the pop-out button
  and the drag-a-header-into-a-tray route, both of which already existed.
- **The "transition" (item 3) is a state change, not a blink.** The owner's words were
  "blink/transition". A looping flash is a vestibular and photosensitivity hazard, so
  the armed state is expressed as the line going from 2pt at 55% opacity to a 6pt
  rounded bar at full opacity, with no animation and no repeat. Reduce Motion needs no
  special case because nothing moves.
- **Why a 30 Hz timer and not an event monitor.** Ending the gesture needs "mouse
  released", and a native window drag runs its own event loop a local monitor cannot be
  relied on to see. A global mouse-MOVED monitor is the exact thing the dead-zone
  decision above ruled out. The timer exists only while two panels are actually near
  each other and reads `NSEvent.pressedMouseButtons` directly.
- **OWNER TEST 2026-08-20 — connect, group-move and chaining all confirmed working**
  (*"docking a panel/panel group to another works great. line, pause, snapping. no
  resizing or weird location jumping. A+"*, and a third panel chains onto a pair).
  Two things broke, both now fixed:
  - **Only the group's PARENT window carried the others.** Dragging any follower moved
    just that window. Two facts shaped the fix. First, these windows are
    `fullSizeContentView`, so their top strip belongs to the TITLEBAR — a drag there
    never reaches our `WindowMoveArea`, which is why "make the follower's grab bar
    move the parent instead" cannot work. Second — and this took a failed attempt to
    learn — **letting the follower drag itself and then applying its delta to the
    parent is Session 80 in miniature.** Owner on that build: *"the dragging is super
    laggy... the panels don't always move at the same pace, so if i stop before one
    has caught up, it leaves an empty space."* Of course: the group was being animated
    by our code one tick behind the mouse.
    **The fix is `performDrag(with:)`.** `TrayWindow.sendEvent` intercepts a
    left-mouse-down in a follower's drag regions and hands the gesture to AppKit's own
    window-drag loop running on the PARENT. The follower never moves under its own
    power at all — it moves because it is a child window. Zero code per tick, the same
    path as dragging any macOS window by its titlebar. Intercepting in `sendEvent`
    rather than a view is what lets it cover the titlebar strip too.
  - **Resizing a glued window left a gap or overlapped its neighbour.** `trayDidResize`
    now slides the rest of the group by the change at the edge that moved, so they
    stay flush. Guarded both ways: a move that comes with a size change is not
    treated as a drag, and the reflow's own window moves are not treated as the user
    dragging them.
- **Seam gutter, 2026-08-20.** The seam is drawn exactly on top of the right-hand
  window's own resize border, so its move areas were swallowing the resize. Owner:
  *"if we need to narrow the click area to 'move' between panels to a very small
  area, i'm fine with that."* The seam's leading `GlueMetric.seamResizeGutter` (9pt
  of its 14) is now left to the window's resize edge; the move area is the inner
  strip. Resizing is the more frequent gesture at that spot, and the group can still
  be moved from any panel's top strip.
- **THE ONE THAT MADE FOLLOWER PANELS UNUSABLE, 2026-08-20.** Owner: *"the whole
  panel is draggable and no buttons can be clicked. no layers can be selected."*
  Nothing to do with the seam — `TrayWindow.sendEvent` was claiming the ENTIRE
  follower window. Two faults, either enough on its own: the titlebar strip was
  measured as `frame.height - contentLayoutRect.height` with **no ceiling**, and the
  fallback asked a generic `mouseDownCanMoveWindow` of whatever view the point hit —
  which an `NSHostingView` can answer yes to. Every click in a follower became a
  group drag. Fixed by clamping the strip to 40pt and testing for one specific marker
  class, `WindowDragRegionView`, instead of a property anything may return true for.
  **`sendEvent` interception is all-or-nothing: a predicate that is slightly too
  generous does not degrade, it removes the window's entire UI.**
- **The seam carries NO drag, 2026-08-20 — item 6 partially withdrawn by the owner.**
  The seam sits on top of the window's leading resize border AND over the Layers
  list, so a move area there first fought the column resize and then broke layer
  reordering. Owner: *"remove the dragging from within that gutter... keep the moving
  of the linked panels only on the header bars."* The seam is now hit-test
  transparent except for the unlink button. Item 6's "dragging anywhere in the glue
  moves the group" is therefore NOT implemented, deliberately; moving a group from
  any panel's top strip covers the need. Do not re-add it without asking.
- **Unlink button moved off the resize border, 2026-08-20.** Adding the gutter above
  made the button unclickable: centred in a 14pt seam sitting at the window's leading
  edge, most of it fell inside the resize border, which wins every click there. It is
  now drawn last, starts where the gutter ends, and is allowed to overhang into the
  panel — clear of the border, and easier to see for it.
- **OPEN, worth deciding rather than drifting into:** dragging the seam resizes the
  RIGHT panel's left edge, and the reflow then slides the left panel to stay flush —
  so the pair keeps its total width and the left panel moves rather than growing. A
  real split-view divider would grow one and shrink the other. Not built, because the
  owner asked only for the click areas to stop fighting; ask before assuming.
- **Still needs owner verification (re-verify after the 2026-08-20 rebuild):** two
  panels at different heights AND different vertical positions staying exactly where
  they were on connect; each column showing its OWN panels; connect from both sides;
  the pause threshold
  feeling right; the glue strip WIDTH (item 7 explicitly called this out as needing
  tuning — it is one constant, `GlueMetric.stripWidth`, currently 14pt); column resize
  and column height-drag; unlink from a 2- and a 3-column group; ⌘` seeing one window
  (item 11); and a glued arrangement surviving a FEAT-021 preset save/restore.
- Original hypothesis retained below; it predicted the columns-in-one-tray shape, and
  the owner's design is compatible with it.
- Repro/Detail: Owner request 2026-08-11, paired with FEAT-021: revisit the "magnet"
  behavior where a panel attaches to the side of another panel, with a way to pop
  them apart again — owner suggests a button, and notes this is only needed in
  multi-window view.
- Hypothesis: this is ROADMAP Phase 13c deferral (a), *"side-by-side docking within
  one tray (multi-column / vertical insertion line) — panels currently stack
  vertically only."* Important history to not re-litigate: Session 80 tried
  free-window snapping and it was CHOPPY, because it synced N windows on every drag
  tick; Session 82 replaced it with the tray model, where one window holds a stack
  and the grab bar moves the whole unit smoothly. So the right implementation is
  almost certainly horizontal columns WITHIN a tray, not magnetism between separate
  NSWindows. Do not rebuild the thing that was already removed for being choppy. The
  pop-apart affordance already exists in one direction: Session 82 shipped a header
  pop-out button that tears a panel into its own tray, because deferral (b) records
  that drop-outside is not catchable via SwiftUI drag-and-drop. Extend that same
  button to the horizontal case rather than inventing a second mechanism.
- Acceptance: in multi-window mode a panel can be dropped beside another within a
  tray (vertical insertion line) to form a column, and the header pop-out button
  separates it again. Dragging the tray grab bar moves the combined unit smoothly,
  with no per-tick multi-window syncing. Arrangement persists and is captured by
  FEAT-021 presets. Fully keyboard reachable; Reduce Motion respected. Closes Phase
  13c deferral (a) and extends (b).

### FEAT-023 — Duplicate an effect, and move Delete out of misclick range
- Type: feature
- Priority: P2
- Area: inspector · effects
- Status: **done — owner verified 2026-08-21.**
- Implementation 2026-08-21: each effect row now has one clearly labelled actions
  menu. Duplicate and destructive Remove are separated inside it, and the same
  operations are available from the row context menu. Edit ▸ Duplicate Effect adds
  the keyboard/menu-bar route through the responder chain. A duplicate is inserted
  directly above the source, receives a new identity, becomes the selected row, and
  is one undoable edit. Shadow controls also moved to an adaptive two-by-two grid
  with unabbreviated labels. Follow-up 2026-08-21: every effect row now has an
  independent disclosure. Collapsed rows retain enable, type, a one-line live
  settings summary, and the actions menu; the summary is also a large expand target.
  New and duplicated effects start expanded, and disclosure state remains Inspector
  UI state rather than leaking into the saved design document. Live keyboard/
  VoiceOver, collapse/expand, tooltip handoff, and action behavior are owner-verified.
- Repro/Detail: Owner request 2026-08-11: a Duplicate action for an effect in the
  Effects section, noting this "might need a rework of where the delete effect is to
  make this easy, and avoid accidentally deleting when trying to duplicate."
- Hypothesis: the layout concern is the real content of this request — adding
  Duplicate next to a Delete that is already easy to hit makes an existing hazard
  worse. Two reasonable shapes: a per-effect overflow menu holding Duplicate /
  Delete (safest, one click deeper), or Duplicate inline with Delete moved to the
  row's trailing edge with clear separation. Prefer whichever the FEAT-010 panel
  pass lands on so the Effects rows do not become a one-off pattern. Duplicating
  should insert the copy directly above the original and select it, since the next
  move is almost always to change one parameter.
- Acceptance: an effect can be duplicated from the inspector, from the menu bar, and
  from a context menu, in one undo step; the copy lands adjacent to the original and
  becomes the edited row. Delete is not adjacent enough to Duplicate to invite a
  misclick, and remains undoable. Both are keyboard reachable with distinct VoiceOver
  labels. Stacking order of the duplicated effect is preserved on export.

### FEAT-024 — Select the existing text when entering a text field or text node
- Type: feature
- Priority: P1
- Area: type · inspector · canvas · a11y
- Status: **(a) shipped 2026-08-19, builds clean. Owner verified fix 2026-08-19.**
- **FIX APPLIED 2026-08-19 — part (a) only, exactly as the recommended shape put it.**
  `CanvasNSView.beginEditingText` now opens with the node's full contents SELECTED
  instead of placing a caret. The `at viewPoint:` parameter that used to put the
  caret under the double-click was removed rather than left unused, so the double-
  click call site reads honestly. A brand-new or empty node just gets a caret.
  Because the editor is a live, focused, stock `NSTextView`, part (c) comes for
  free: one more click inside it places a caret normally, so a one-character edit
  is still one click away.
- Accessibility: the opening selection is announced with an explicit
  `NSAccessibility.post(element:notification:.selectedTextChanged)` — AppKit posts
  that for ordinary selection changes, but here the range is set as part of taking
  focus, and a VoiceOver user needs to hear that the text is selected BEFORE typing
  replaces it. **NOT verified with VoiceOver running** — owner check required.
- (b) Tab into an inspector field selecting its contents is SwiftUI/AppKit default
  behaviour and was not touched; verify rather than assume.
- No Settings toggle was added, per the entry: the behaviour is the design, a
  preference is the fallback if it proves annoying in practice.
- Repro/Detail: Owner request 2026-08-11: "make text easier to select and edit
  (auto select all option?)... most of the time I want to remove that text or type
  over it. So if it's highlighted by default then I'm not clicking, double clicking,
  multiple times to get the whole line of text to be selected."
- Hypothesis: this is the standard macOS behavior for a field entered by KEYBOARD
  (Tab focus selects all) but not for one entered by CLICK (click places a caret) —
  and that distinction is deliberate, because select-all-on-click makes it hard to
  place a caret to make a small edit. Recommended shape rather than a blanket
  toggle: (a) entering a text node's edit mode from the canvas selects all, since
  the user has already committed to editing that node; (b) Tab into an inspector
  field selects all, which it should already do — verify; (c) a click inside a field
  that is ALREADY focused places a caret normally. That gets the owner what they
  want without destroying precise editing. Offer the preference in Settings if (a)
  proves annoying in practice, but try the behavior first — a setting is the fallback,
  not the design. Pairs with BUG-029, which fixes the caret keys that make the
  "click several times" workaround necessary today.
- Acceptance: double-clicking a canvas text node to edit selects its full contents,
  ready to be typed over; a subsequent click inside places a caret. Tab into any
  inspector text field selects its contents. Escape reverts, Return commits. The
  selection change is announced by VoiceOver. No regression in placing a caret for a
  one-character edit.

### FEAT-025 — Direct-select tool moves whole objects when no points are selected
- Type: feature
- Priority: P1
- Area: canvas · tools · vector
- Status: **done — owner verified 2026-08-25** ("feels natural. exactly what i
  expect to happen").
- Owner verification 2026-08-25 covered the core behaviour AND the flagged change:
  pressing a different object's body now selects and drags in one gesture, and the
  owner confirmed that is what they expect. The wider regression list below
  (Option-drag, snapping, groups, rotated/flipped ancestors, locked objects,
  click-without-drag) was not separately walked through — recorded here so a later
  session does not read this sign-off as broader than it was.
- Repro/Detail: Owner request 2026-08-11. Because the point tool will not move a
  whole object when nothing is point-selected, a failed tool switch (BUG-028) leaves
  the app feeling broken rather than merely in the wrong mode. Owner's proposal:
  follow Illustrator, where the direct-selection tool does move whole objects when
  no individual points are selected.
- Hypothesis: agreed, and it is the correct interaction model — Illustrator's Direct
  Selection drags the whole path when you press inside a filled object with no
  points selected, and drags points when points are selected or when you press
  directly on one. Precise shape: press on a point or handle → edit that point;
  press on a path segment → edit that segment; press inside the fill with no point
  selection → move the whole object. This is a real improvement independent of the
  bug. CRITICAL: it must NOT be treated as a fix for BUG-028. Making the wrong mode
  less painful is not the same as making the tool switch work, and shipping only
  this would hide a live event-routing bug.
- Implementation 2026-08-25, in `nodeToolMouseDown` (`CanvasView.swift`). The
  press-target ladder now reads: (1) an anchor or handle wins, unchanged; (2) a
  point selection on the object under the cursor wins, unchanged; (3) **new** — the
  press landed on an object's body with nothing finer to edit, so the whole object
  moves. Reaching step 3 is itself the proof that a point edit was not what was
  asked for, which is why no extra "is anything point-selected" test is needed.
  `.last` of the hit chain is the deepest leaf rather than its enclosing group,
  because addressing individual objects IS the direct-selection semantic.
- **It reuses `beginSelectedNodeDrag`, the route the select tool and Auto-select
  already share**, so Option-copy, snapping, nested movement, smart guides, and
  one-step undo remain one implementation rather than a second copy that drifts.
  That also means arming the drag costs a plain click nothing: the `.nodes` case in
  `mouseUp` registers undo only `if didEdit`, so a press that never moves still just
  selects, exactly as before.
- **One deliberate behaviour change beyond the literal acceptance text — please look
  at this specifically.** Pressing a DIFFERENT object's body previously only
  switched which object the tool addressed; it took a second press to move it. It
  now switches AND arms the drag, so the tool behaves the same way wherever you
  press. That is Illustrator's model and it removes exactly the two-step friction
  this entry was filed about, but it IS a change to existing behaviour and it is the
  most likely thing to feel wrong. If it does, the fix is one `if` — restore the
  early return in the switching branch.
- **Not implemented, and not claimed:** the Hypothesis paragraph above also
  describes "press on a path segment → edit that segment." EXP has no segment
  hit-test or segment drag today, and this change did not add one. A press on a
  segment that is not near an anchor falls through to the whole-object move. Segment
  editing remains unbuilt; log it separately if it is wanted.
- **Still NOT a fix for BUG-028.** The code carries that warning at the call site so
  a later reader cannot mistake one for the other. BUG-028 remains open, live, and
  separately verifiable.
- **What was verified:** `xcodebuild` Debug for the `EXP [design]` scheme succeeds
  with signing disabled, zero errors, and no new warnings (46 total, all
  pre-existing; none in the edited range). `CanvasView.swift` is app-target only, so
  the EXPThumbnail scheme is unaffected. **That is the entire claim** — no pointer
  interaction has been exercised, so every line of the acceptance below is open.
- Acceptance: with the point tool active and nothing point-selected, dragging inside
  an object's fill moves the whole object in one undo step. With points selected,
  dragging moves the points as before. Pressing directly on a point or handle always
  wins over the whole-object drag. BUG-028 is fixed separately and verified
  separately.
- Owner regression pass to run alongside the acceptance above: Option-drag copies,
  snapping and smart guides, dragging a node that lives inside a group, dragging
  inside a rotated or flipped ancestor, a locked object (must stay unmovable), a
  plain click with no movement (must select and register no undo step), and
  switching between two objects by pressing each in turn.

### FEAT-026 — Transform box (resize + rotate) for a selection of points
- Type: feature
- Priority: P2
- Area: canvas · vector · selection
- Status: **done — owner verified 2026-08-19.** Closes Wave 3.
- **BUILT 2026-08-19, on the box BUG-035 produced, as the entry asked.** Selecting two
  or more points with the node tool now draws a transform box with eight handles and
  the same outside-corner rotate region every other selection uses.
  - **Space: the path's NODE-LOCAL space** — the space `PathPoint.point` already lives
    in. The box, its hit-tests and the write-back are all expressed there and mapped
    with the existing `nodeLocalToView` / `viewToNodeLocal`, so the node's own
    rotation and flip and every ancestor transform come for free. That is what
    satisfies "works inside groups and inside rotated/flipped ancestors" without a
    single new coordinate case.
  - **The two design questions the entry asked are now answered, one by precedent and
    one by the data model.** (1) Control handles ALWAYS travel with their selected
    anchor — already the convention in `moveSelectedPoints`, `rotateSelectedPoints`
    and arrow-nudge, and now written down. A handle whose anchor is not selected is
    left alone, so the curve into an unselected neighbour changes shape only because
    one of its endpoints moved, which is correct. (2) A handle canNOT be transformed
    independently, because `PointAddress` names ANCHORS only — there is no such thing
    as a selected handle in the model. Recorded as a `PointBaseline` typealias comment
    so the next session does not re-litigate it.
  - **The box is padded outward** by a constant on-screen amount rather than being
    tight to the anchors. Without that, the corner handle sits exactly ON the extreme
    anchor and makes that anchor impossible to grab. The padding is also what makes it
    safe to hit-test the box BEFORE the anchors in `nodeToolMouseDown`.
  - **Drawn DASHED**, so a point-selection box cannot be mistaken for an object
    selection — it bounds points inside a shape, not the shape.
  - Baselines are captured at drag start and every tick transforms from them, so no
    rounding accumulates. Shift constrains proportion on resize and snaps rotation to
    15°, matching the rest of the app. Both gestures close out through
    `normalizePath` + `registerUndoForGesture`, so the frame is refitted to the moved
    points and the whole drag is ONE undo step.
  - A degenerate axis (all selected points on one line) holds its scale at 1 rather
    than dividing by ~0. Dragging a handle past the opposite edge does NOT mirror the
    points, because `resizedFrame` normalises — same as shape resize, noted here
    because Illustrator does mirror and someone will ask.
- Owner verification 2026-08-19 is recorded in the ROADMAP Progress Log. The
  degenerate-axis and transformed-ancestor cases below remain the regression matrix.
- Repro/Detail: Owner request 2026-08-11, raised alongside the missing-handles bug:
  select a group of points — for example one end of a line — and get a bounding box
  with resize and rotate handles, "just as if they were their own object... just...
  attached still."
- Hypothesis: this is the natural companion to BUG-035 and should reuse whatever
  transform-box code that fix lands on, rather than growing a parallel
  implementation. The math is the standard one: compute the bounds of the selected
  points, apply the resize/rotate transform to those points only, and leave the
  unselected points of the path untouched. The genuinely fiddly part is curve
  handles — when an anchor is inside the selection but its neighbor is not, the
  handle between them has to be transformed consistently or the curve kinks. Decide
  and document whether handles belonging to a selected anchor always travel with it
  (they should) and whether a selected handle can be transformed independently.
- Acceptance: selecting two or more points shows a transform box with resize and
  rotate handles; dragging them transforms only the selected points, and the rest of
  the path stays anchored. Shift constrains proportion, and rotation snaps with
  Shift as elsewhere. One undo step per gesture. Works inside groups and inside
  rotated/flipped ancestors. Blocked by BUG-035 — build on the same box.

### FEAT-027 — Create Outlines / Outline Stroke on groups and mixed selections
- Type: feature
- Priority: P2
- Area: canvas · vector · type
- Status: **needs-verify — owner reprioritized and implementation landed 2026-08-24**
- Repro/Detail: Owner request 2026-08-11: add Create Outlines / Outline Stroke for a
  group or a multi-element selection. Explicit requirement, and it is the
  inclusive-design instinct applied to command design: *"only apply to layers that
  it is relevant to, but don't prevent me from the action if one of the layers
  doesn't apply."*
- Hypothesis: both operations already exist for single eligible nodes — Phase 16
  records convert-type-to-shapes (Session 53) and outline-stroke (2026-07-20,
  including center/inside/outside and open round-capped strokes). So this is a
  traversal and reporting problem, not new geometry: walk the selection recursively,
  apply to each eligible descendant, skip the rest, and do it in ONE undo step. The
  part worth designing carefully is the report. Silent partial success is the
  failure mode here — the user cannot tell whether nothing happened or everything
  did. Prefer a brief, dismissible summary ("Outlined 6 of 9 layers; 3 had no
  stroke") over either a blocking dialog or silence, and make it available to
  VoiceOver rather than as a purely visual flash.
- Implementation 2026-08-24: Convert to Outlines, Convert to Path, and Outline
  Stroke now treat a selected group as a recursive operation scope. Eligible leaves
  at any nesting depth are transformed in place while unrelated text, images,
  existing paths, and other ineligible layers remain untouched. Type outlines retain
  the original layer identity and non-text contracts (visibility/lock, transforms,
  opacity/effects/blend, auto-layout placement, masks, relationships, public props,
  and recovered semantics); the vector operations preserve hierarchy and run in one
  commit. Menu, context-menu, and Inspector enablement now inspect selected subtrees.
  The existing Fill/Stroke Inspector route was source-verified to already recurse
  through groups and groups-within-groups, so it required no duplicate implementation.
  **The originally proposed sighted non-blocking partial-success summary remains a
  follow-up; no new toast/status surface was invented in this input-and-traversal
  slice.** Commands beep only when nothing was changed.
- Acceptance: the command enables whenever at least one selected layer (at any
  nesting depth) is eligible, and applies to exactly those, preserving z-order and
  group structure; ineligible layers are untouched. One undo restores everything. A
  non-blocking, screen-reader-available summary states what was and was not
  converted. `validateMenuItem(_:)` disables only when nothing at all is eligible,
  with the reason discoverable. Command coverage: action, Object menu, right-click,
  validation.

### FEAT-028 — Outline (stroke) on live text
- Type: feature
- Priority: P2
- Area: type · canvas · export
- Status: **partly done — owner verified the stroke itself 2026-08-25 ("text stroke
  working well"). ONE acceptance line remains unbuilt: Convert to Outlines is not
  known to preserve a stroked appearance, and was not part of what was verified.**
- Repro/Detail: Owner request 2026-08-11: "outline text (even just as type)" — i.e.
  a stroke applied to text that is still editable text, not converted to paths.
- Hypothesis: the model already carries stroke on shapes and paths; this extends it
  to text nodes, rendered by stroking the glyph outlines. The fidelity question
  decides the design, per the project's own test — CSS has two competing mechanisms:
  the widely supported non-standard `-webkit-text-stroke`, which centers the stroke
  on the glyph outline, and `paint-order: stroke fill` with SVG-style `stroke`/
  `stroke-width`, which is what actually lets a stroke sit BEHIND the fill so thick
  strokes do not eat the letterforms. SVG export is straightforward (`stroke` +
  `paint-order`). Verify current browser support and the semantic-HTML/CSS export
  contract before committing to which one EXP's model mirrors, and record the
  citation — getting this wrong means text that looks right on canvas and wrong in
  handoff, which is the failure this tool exists to prevent. Also decide stroke
  alignment (outside/center/inside), since designers overwhelmingly want outside.
- **Research gate CLOSED 2026-08-25 — and the premise above was wrong.** This entry
  described `-webkit-text-stroke` and `paint-order: stroke fill` as two competing
  mechanisms to choose between. They are not competing; they compose, and you need
  both. There is no standard CSS `stroke` property for HTML text, and MDN is
  explicit that for HTML text `paint-order` only has an effect when the stroke comes
  from `-webkit-text-stroke`. So the HTML/CSS handoff emits the pair:

  ```css
  -webkit-text-stroke-width: <2 × authored width>;
  -webkit-text-stroke-color: <color>;
  paint-order: stroke fill;
  ```

  The doubling is the outside-stroke convention: `-webkit-text-stroke` centers the
  stroke on the glyph outline and that is not adjustable, so half of it is painted
  over by the fill once `paint-order` puts the stroke underneath. A 2× width
  therefore reads as an outside stroke of the authored width. Canvas, PNG, and PDF
  must use the SAME convention or the four disagree — which is the failure this
  feature exists to avoid.
- **Support, measured 2026-08-25, not remembered:** `-webkit-text-stroke` is
  non-standard but Baseline **Widely available** (since April 2017), ~96.4% global —
  Chrome 4+, Edge 15+, Safari 3.1+, Firefox 49+, iOS Safari 3.2+. The CSS
  `paint-order` property is Baseline **Newly available** (March 2024), ~96.4% global
  but only 90.3% FULL support: Chrome and Edge were partial from 35/79 through 122
  and full only at **123**, with Firefox 60+ and Safari 11+ full. That partial band
  is the caveat that has to be stated rather than implied: those browsers honour
  `paint-order` for SVG but not for HTML text, so the stroke renders CENTERED over
  the fill and a thick stroke eats the letterforms. Roughly 6% of traffic sees the
  wrong picture, and it degrades toward "too heavy," not toward "no stroke."
- **SVG is the easy half and stays live text.** `ExportRenderer` already emits real
  `<text>`/`<tspan>` rather than outlining, so the stroke is
  `stroke` + `stroke-width` + `paint-order="stroke"` on the `<text>` element, with
  the same doubling convention. SVG `paint-order` support predates and exceeds the
  HTML-text case.
- **Alignment decision:** support OUTSIDE (the default designers want) and CENTER.
  INSIDE is not expressible for HTML text in CSS at all — it needs a clip, which
  only SVG can do — so either leave it out of v1 or state plainly that it does not
  survive the HTML round trip. Do not offer a control that silently lies in handoff.
- **Owner decision 2026-08-25 — the limitations are ACCEPTED, do not reopen this.**
  Having read the mechanism, the owner is fine shipping live-text stroke with the
  centered-stroke fallback on older Chrome/Edge and with no inside alignment: it is
  a small use case, and **Convert to Outlines is the full-control escape hatch**
  when exact stroke geometry matters. That reframes the feature's job — live-text
  stroke is the convenient path, outlines are the guaranteed one — so the UI should
  make that route discoverable at the moment it matters rather than hiding the
  limitation. State the caveat in the handoff output; do not build a workaround.
- **Accessibility note, flagged not solved:** a stroke changes the effective contrast
  at glyph edges, and FEAT-005's checker compares fill against background. Stroked
  text can pass the checker and still read badly. Decide before shipping whether the
  checker should account for a stroke or say that it does not; do not leave the
  question implicit.
- Implementation 2026-08-25, built straight from the closed research gate.
  - **Model:** `TextContent` gains `strokeColor`, `strokeWidth`, `strokeAlignment`,
    with hand-written decoding so every existing document opens as width 0 = no
    stroke. `TextStrokeAlignment` is `outside | center` — **INSIDE is absent by
    decision, and the enum says why at the declaration** so a later session cannot
    "helpfully" add it.
  - **One predicate, four renderers.** `TextContent.paintedStroke` answers "is there
    a stroke, and what is it" in one place, so "is there a stroke" cannot come out
    differently in the canvas and in an exporter. That is the direct lesson of
    BUG-053, applied before the drift could happen rather than after.
  - **One attribute builder, two passes.** The stroke lives in
    `TextContent.attributedString(strokePass:)`, which BOTH the canvas layout cache
    and the raster exporter already call. Centre alignment is one pass with a
    NEGATIVE `.strokeWidth` (AppKit paints that fill-then-stroke, the same centred
    result `-webkit-text-stroke` gives alone). Outside is a `.strokeOnly` underlay at
    DOUBLE width with a clear fill, drawn first so the fill covers the inner half.
    Note `.strokeWidth` is a PERCENTAGE OF FONT SIZE in AppKit, not points — and
    because the font is already scaled, the scale cancels out of the percentage, so
    it is correct at every zoom.
  - **Canvas:** `TextLayoutEntry` gained an optional stroke layout, built and cached
    beside the fill layout and nil for the common no-stroke case, so a stroked text
    node costs one extra layout per cache fill rather than one per frame. The
    fingerprint now includes the stroke fields — without that a stroke change would
    reuse a stale layout and appear to do nothing.
  - **SVG** keeps the text LIVE: `stroke`, `stroke-width` (doubled for outside),
    `stroke-linejoin="round"`, `paint-order="stroke"` on the `<text>` element.
  - **HTML/CSS** emits `-webkit-text-stroke-width` (doubled for outside),
    `-webkit-text-stroke-color`, and `paint-order: stroke fill` TOGETHER, because
    they compose rather than compete — the finding that closed the research gate.
    The ~6%-of-traffic caveat is written at the emission site with the date it was
    measured.
  - **Inspector:** a Stroke width field in the Type panel, with colour and an
    Outside/Center control appearing only once width > 0, plus a caption stating the
    browser limit and pointing at Convert to Outlines for exact control. The
    limitation is disclosed where the decision is made, not buried in a doc.
- **What was verified:** `xcodebuild` Debug succeeds for both the `EXP [design]` and
  `EXPThumbnail` schemes (`Document.swift` and `Typography.swift` are both shared, so
  both targets matter here), zero errors, no warnings in any touched file. **That is
  the entire claim** — no stroked text has been drawn, exported, or opened in a
  browser.
- **Not done, and part of the acceptance:** "converting the text to outlines
  afterward preserves the appearance" has NOT been implemented or checked. Convert to
  Outlines produces a path from the glyph fill; whether it carries the stroke across
  is unknown and is the most likely gap. Also untouched: the FEAT-005 contrast
  checker still compares fill against background and knows nothing about a stroke —
  flagged in the research and still open.
- Acceptance: a text node can carry a stroke with color, width, and alignment while
  remaining editable text; canvas, PNG, PDF, and SVG all agree; the HTML/CSS handoff
  emits a documented, verified equivalent with its browser-support caveat stated
  rather than implied. Converting the text to outlines afterward preserves the
  appearance.

### FEAT-029 — Pencil tool (freehand draw auto-fitted to bezier points)
- Type: feature
- Priority: P2
- Area: canvas · tools · vector
- Status: **done — owner verified 2026-08-25** ("much better. works great").
- Owner verification 2026-08-25 was iterative and is worth reading as a record of
  what four rounds of fixes actually cost: the fitting was wrong at corners (fixed),
  fast strokes lost their points to event coalescing plus per-sample publishing
  (fixed), and then the two performance fixes cancelled each other and made the
  stroke invisible (fixed). The owner confirmed each round. **Not separately walked
  through:** save/reopen, SVG and PNG export of a pencil path, drawing inside a
  group or a rotated ancestor, and the proximity-close behaviour — all listed in the
  owner pass below and all still open.
- Repro/Detail: Owner request 2026-08-11: "add pencil, to just click/draw which turns
  into pen points automatically."
- Hypothesis: the standard approach is capture the pointer polyline, then fit cubic
  beziers to it — Philip Schneider's curve-fitting algorithm ("An Algorithm for
  Automatically Fitting Digitized Curves," *Graphics Gems*, 1990) is the one nearly
  every drawing app uses, and it produces far fewer, better-placed points than
  naive per-sample conversion. `PathShape.contours` already stores multi-subpath
  cubic contours, so the output has a home with no model change. The one control
  that matters to users is fit tolerance — Illustrator calls it Fidelity, and it is
  the difference between a usable tool and an unusable one; expose it. Consider
  pressure/tilt from `NSEvent` as a later addition, not part of this entry.
  Accessibility note: a freehand tool cannot be the ONLY way to do anything, so it
  must produce a path that is then fully editable by the existing keyboard-operable
  point tools — which it will be.
- Implementation 2026-08-25.
  - **`Model/CurveFitting.swift` (new, app-target only)** — Schneider's algorithm
    as the entry specified: chord-length parameterisation, a least-squares solve
    for the two control points with endpoints and tangent directions fixed,
    Newton-Raphson reparameterisation when the fit is close, and recursive
    splitting at the worst sample when it is not. Pure geometry — no AppKit, no
    model mutation, no drawing — so it is testable on its own.
  - **One deliberate deviation from the paper, called out at the code site.**
    Schneider writes `iterationError = error * error`, which is unit-ambiguous:
    `error` is compared against a SQUARED distance, so squaring it again means
    something different at every scale. This reparameterises when the fit is within
    4× the tolerance in real distance (16× squared) — scale-independent, and a
    judgement call rather than a value from the paper.
  - **Two defensive limits, both chosen to fail loose rather than wrong.** A
    recursion ceiling of 16 accepts the current fit instead of splitting forever on
    a tight scribble at a small tolerance; and a singular least-squares solve falls
    back to Schneider's own one-third-chord heuristic rather than emitting inverted
    handles.
  - **Capture.** Samples are taken in DOCUMENT space, so zoom changes only how
    densely a stroke is sampled on screen, never what gets drawn. Samples closer
    than 1.5pt are dropped. The live preview during the drag is the RAW polyline —
    cheap, honest about what was captured, and replaced by the fitted curve on
    release; re-fitting per tick would cost far more and show a curve rewriting
    itself under the cursor.
  - **The frame is refitted live, not just at the end**, because `nodeHit` uses it
    as its bounding-box reject and culling uses it too — a stale frame mid-stroke
    makes the ink unclickable and can make it vanish while being drawn.
  - **Closing:** proximity, the freehand convention — the stroke closes if the
    release lands within 12 VIEW points of where it began AND there are at least 8
    samples, so a short scribble that happens to end near its start is not closed
    behind the designer's back. Measured on screen so the gesture means the same
    thing at every zoom. **This is the most likely thing to feel wrong; if it
    does, both numbers are one constant each.**
  - **Fidelity control:** `exp.pref.pencilFidelity` (Double, default 2.0 points of
    allowed deviation), exposed as Settings ▸ Canvas ▸ Pencil ▸ Fidelity, a slider
    from 0.5 to 10 labelled Accurate ↔ Smooth with the live value in points. The
    footnote states which direction is which, because "fidelity" alone tells a
    designer nothing, and states that it affects new strokes only.
  - **Command coverage:** Tool case + symbol + label, ToolsStrip button beside the
    pen, `N` in `keyDown` (Illustrator's Pencil key), `@objc pencilToolAction:`,
    and a Tools-menu item routed through `sendCanvasAction`. Switching tools
    mid-stroke finishes the stroke rather than abandoning it.
  - **A click is not a stroke:** fewer than two samples removes the node, restores
    the baseline, and registers no undo step at all.
- **The output is an ordinary path and nothing about it is special afterwards** —
  that was the accessibility requirement in this entry (a freehand tool cannot be
  the only way to do anything), and it is satisfied structurally rather than by a
  promise: the pencil emits the same `PathShape` the pen does, so every existing
  keyboard-operable point tool, the Inspector, export, and Convert to Outlines all
  work on it with no new code.
- **Not implemented, and not claimed:** pressure and tilt from `NSEvent`, which the
  entry explicitly scoped out as a later addition. Also no smoothing pass before
  fitting — the tolerance is the only control, deliberately.
- **Lag reported by the owner on first use, 2026-08-25 — two defects, both mine,
  fixed the same day.** Neither was in the curve fitting; both were in how the live
  stroke talked to the canvas.
  1. **`applyPencilPoints` used `updateNode` during the drag.** That is the
     SEMANTIC-change funnel, and it runs `model.reflowed(nodes)` — a full auto-layout
     reflow across every node on the page — on every captured sample. `updateNode`'s
     own comment states the rule I broke: "live drags use withNodes directly and
     reflow on mouse-up." It now takes a `live` flag and uses `updateNodeLive` for
     samples, `updateNode` only for the one commit.
  2. **`.pencilStroke` was missing from `activeDragNodeIDs()`**, so it fell through
     to `default: return nil` and `drawDragBlit` refused the gesture. Every sample
     therefore re-rendered the ENTIRE scene instead of compositing the stroke over
     the static below/above snapshots the drag machinery already builds. A pencil
     stroke is a node drag like any other and now says so.
- **One cost considered and deliberately NOT changed:** each sample still rebuilds
  the whole point array and its bounding box, which is O(n) per sample and O(n²)
  over a stroke. For a realistic stroke (a few hundred samples at 1.5pt spacing)
  that is tens of microseconds of array work per tick — real, but orders of
  magnitude below a page reflow or a full scene render. It was left simple on
  purpose. If profiling ever says otherwise, the fix is an incremental bbox that
  re-bases the locals only when the origin actually moves.
- **Owner findings on second use, 2026-08-25 — three reports, two fixed, one NOT
  reproduced.**
  1. *"Shows only straight lines while drawing."* Working as built: the live preview
     is the raw captured polyline. Left as-is for now, because the real complaint
     underneath it is (3) — when the fit tracks the stroke, preview and result stop
     disagreeing. If it still reads wrong afterwards, the fix is to fit the tail of
     the stroke live, not to change the capture.
  2. **Sharp corners were fitted as smooth curves — FIXED.** Schneider's algorithm
     assumes smooth data. At a genuine corner it splits and computes the shared
     tangent as the AVERAGE of the incoming and outgoing directions, which describes
     neither and very nearly cancels; the solve then returns enormous handle lengths
     chasing an impossible tangent. `CurveFitting` now finds corners FIRST
     (direction measured over a 3-sample window, 55° threshold, minimum arm length
     so tremor does not register) and fits each run between them independently. The
     two runs meet at an anchor whose handles were fitted separately — which is what
     a corner point is. Verified on a synthetic 7-vertex zigzag: all 5 interior
     corners detected.
  3. **Unbounded handle length — FIXED.** Schneider's least-squares solve has no
     upper bound, and an unbounded handle is exactly the "one node flew way beyond
     where I drew" failure: a control point placed far outside the stroke draws a
     large loop. Handles are now clamped to 1.5× the segment chord (a quarter-circle
     needs ~0.39×, a half-circle ~0.67×, so real curves are untouched). A clamped
     handle merely fits worse, which the error test then resolves by splitting.
- **NOT REPRODUCED, and therefore NOT claimed fixed.** A standalone port of the
  fitter was run against synthetic zigzags — clean, and with ±0.8pt noise and 60%
  speed variation — at tolerances 0.5 through 4.0. Worst deviation stayed under 3pt
  and no control point escaped the drawn bounds by more than 3.3pt. **Nothing in
  those runs resembles the large excursion in the owner's screenshot.** Both fixes
  above are defensible on their own terms, but the actual failure has not been
  demonstrated, so it must not be marked fixed on this evidence.
- **The decisive next step is real data, not another hypothesis.** A `.design` file
  stores every `PathPoint`, so one bad stroke saved into the connected folder gives
  the exact anchors and handles the fitter produced. That answers in one read
  whether an ANCHOR landed outside the stroke (impossible by construction — every
  anchor is an input sample — so it would mean the sample list is wrong) or a HANDLE
  did (a fitting problem, which the clamp now bounds). Those two causes need
  completely different fixes and guessing between them has already cost one wrong
  answer today.
- **Owner verification 2026-08-25 (partial): the corner and overshoot fixes work.**
  "the points are landing much better now. no weird strange wild curves." The
  not-reproduced excursion has not recurred. Corner detection and handle clamping
  are therefore confirmed in practice even though the original failure was never
  reproduced synthetically — recorded that way rather than as "diagnosed correctly."
- **Fast strokes lost most of their points — two causes, both addressed 2026-08-25,
  NOT yet verified.** The owner drew a fast shading line and got a near-straight
  line instead of the path they drew; slow strokes were faithful. Their instinct
  that this was related to the lag was right, and the mechanism connects them:
  1. **macOS coalesces mouse-dragged events.** Move fast and several moves are
     merged into one, so a quick stroke arrives as a few far-apart points and is
     drawn as straight lines between them. `NSEvent.isMouseCoalescingEnabled` is now
     set false for the duration of a stroke and restored in `finishPencilStroke`'s
     `defer`, which runs on every exit path including a tool switch mid-stroke.
  2. **`ExpDocument.model` is `@Published`, and the stroke was writing it per
     sample.** Every write publishes to every view observing the document — Layers,
     Inspector, all of it. That is enough work to back the event queue up, and a
     backed-up queue is coalesced HARDER by macOS. So the cost did not present as a
     low frame rate; it presented as lost points. **Nothing is written to the
     document during a stroke now.** The in-flight stroke is chrome, painted from
     `pencilSamples` in the overlay pass exactly as the marquee is, using the
     destination node's own stroke colour and width so the preview looks like what
     is about to exist. The document is written once, with the fitted curve, on
     release.
- **The stroke went INVISIBLE while the mouse was down — my two fixes fought each
  other, fixed 2026-08-25.** Moving the in-flight stroke to the overlay chrome was
  right, and registering `.pencilStroke` in `activeDragNodeIDs()` was right, but
  together they cancelled out: **`drawDragBlit` RETURNS from `draw(_:)` before the
  chrome pass ever runs.** So the blit painted the static scene, the placeholder node
  in the document was (correctly) still empty, and nothing drew the stroke. It was
  briefly visible at the very start because the blit takes a tick to arm — which is
  exactly the "starts drawing, then goes away" the owner described. The preview is
  now drawn in BOTH branches: inside the blit path before it returns, and in the
  ordinary chrome pass for when the blit is unavailable.
- **General lesson worth keeping:** `draw(_:)` has three early-return fast paths
  (pan/zoom blit, drag blit, background-blur offscreen). Anything drawn as chrome
  during a gesture must be drawn on the path that gesture actually takes, not only
  in the full-render chrome section.
- Also removed the stray mark at the press point: the placeholder node was being
  selected at mouse-down, so selection chrome drew around its 2×2 frame. Nothing is
  selected until the finished path exists.
- This also removes `pencilFrame` and the live/commit split in `applyPencilPoints`:
  with one write per stroke there is no live path left to get wrong.
- **Still not verified:** whether fast strokes now capture faithfully, and whether
  the lag is gone. Both are one stroke to check. If lag persists with no document
  writes and no coalescing, the remaining suspect is the full-scene redraw per
  frame, and Testing Mode's perf HUD is the instrument.
- **Lag: one more per-sample cost removed, still unmeasured.** Each sample used to
  re-base every existing point to a moving frame origin — O(n) per sample, O(n²) per
  stroke. The origin only moves when the stroke extends past its own left or top
  edge, so the common case now appends ONE point and touches nothing else. Whether
  that is enough is unknown; Testing Mode's perf HUD names the frame cost directly
  and is the right instrument rather than a third guess.
- **What was verified:** `xcodebuild` Debug succeeds for both the `EXP [design]`
  and `EXPThumbnail` schemes with signing disabled, zero errors, and no warnings in
  the new file or any edited range. **The lag fix itself is NOT measured** — the
  two defects are unambiguous and the reasoning is above, but nobody has drawn a
  stroke since. If it still lags, Testing Mode's perf HUD names the frame cost
  directly and is the right next step rather than more guessing. `CurveFitting.swift` is app-target only, as the
  synchronized-group exception set confirms. **That is the entire claim** — no
  stroke has ever been drawn with this tool, so every acceptance line below is open,
  and the fitted output has never been looked at.
- Acceptance: dragging with the pencil produces an editable `PathShape` with a
  sensible number of anchors and handles; a fidelity/smoothing control adjusts it;
  the result is indistinguishable in the model from a pen-drawn path and is fully
  point-editable, exportable, and undoable in one step. Closing the path is
  possible. Tool is reachable per the command-coverage rule.
- Owner pass to run: draw slow and fast strokes, and a deliberate circle to test the
  proximity close; check the anchor count looks sane rather than one-per-sample;
  move the fidelity slider to both ends and confirm the difference is obvious;
  edit a pencil path with the node tool including keyboard nudge; undo one stroke in
  one step; save, reopen, and export it to SVG and PNG; draw inside a group and
  inside a rotated ancestor; switch tools mid-stroke; and confirm a single click
  leaves nothing behind and nothing in the undo stack.

### FEAT-030 — "Balanced" curve handle mode
- Type: feature
- Priority: P3
- Area: canvas · vector
- Status: **deferred to v2.4 by owner decision 2026-08-21**
- Repro/Detail: Owner request 2026-08-11: "add 'balanced' curve handle option?
  unsure how."
- Hypothesis: the owner's uncertainty is about naming, not concept. There are three
  standard anchor behaviors and EXP presumably has two: SMOOTH (handles locked
  collinear, lengths independent), CORNER (handles fully independent), and the third
  — variously called SYMMETRIC, mirrored, or in Affinity Designer "Smooth" —
  where handles are collinear AND equal length, so dragging one mirrors the other
  exactly. "Balanced" is almost certainly this symmetric mode. Confirm with the
  owner which of the three is missing before building. Implementation is small: an
  enum on the anchor plus a constraint applied on handle drag, with a way to convert
  an existing anchor between modes (Illustrator uses Option-drag on a handle to
  break symmetry).
- Acceptance: an anchor can be set to symmetric/balanced, smooth, or corner from the
  inspector, a context menu, and the menu bar; dragging a handle on a balanced
  anchor mirrors the opposite handle in both direction and length; converting
  between modes is undoable and does not move the anchor. Round-trips through save
  and SVG export (noting SVG stores only resulting coordinates — if the mode itself
  cannot round-trip through export, say so rather than implying it does).

### FEAT-031 — Line end options (square / arrow / round), settable per point
- Type: feature
- Priority: P2
- Area: canvas · vector · export
- Status: **done 2026-08-21 — owner verified canvas, save/render, and SVG export.**
- Repro/Detail: Owner request 2026-08-11: line ending options — square, arrow,
  rounded (currently the only option) — and the ability to set each end
  differently when the point-select tool is active on that point.
- Hypothesis: two different mechanisms are bundled here and should be separated in
  the model. Square/round/butt are stroke LINE CAPS (`CGLineCap`, CSS
  `stroke-linecap`) and are a property of the whole stroke, not of a point — SVG has
  no per-end linecap. Arrows are MARKERS (SVG `marker-start` / `marker-end`), which
  genuinely are per-end. So: expose caps as a stroke property, and arrowheads as
  separate start/end marker slots. This split is what makes the feature export
  faithfully; modeling arrows as "a kind of cap" would produce something EXP could
  draw but not hand off. The model decision was verified against SVG 2: `stroke-linecap`
  is whole-stroke, while `marker-start` / `marker-end` are endpoint properties;
  `markerUnits="strokeWidth"` gives the requested proportional arrow sizing
  ([SVG 2 painting](https://www.w3.org/TR/SVG/painting.html),
  [SVG markers](https://www.w3.org/TR/svg-markers/)). Markers on an open path
  also want `marker-mid` eventually.
- Result: lines and open paths now persist a whole-stroke Flat / Round / Square
  cap plus independent None / Arrow start and end markers. Existing files decode
  as Round + None, preserving their appearance. Canvas and PNG/PDF share one
  Core Graphics marker geometry; SVG emits `stroke-linecap` plus per-node markers
  with `markerUnits="strokeWidth"` and `auto-start-reverse`. EXP SVG import restores
  these fields, supported Figma `strokeCap` values map into them, Convert to Path
  preserves them, and selection/culling bounds include arrow ink. The inspector
  uses labelled, keyboard-operable controls; with the node tool, selecting an open
  path or line endpoint offers just that endpoint's marker slot. Public document
  schema is now 5. Owner visual review caught the first marker geometry anchoring
  the triangle point at the endpoint, which consumed line length. Corrected the
  shared canvas/PNG/PDF geometry and SVG marker so the flat base is the authored
  endpoint and the triangle point projects outward, at both start and end. Owner
  verified the corrected canvas result and clean SVG rendering in a browser.
- Known interop note, non-gating: macOS Preview/Quick Look shows small transform
  differences, while Illustrator and Affinity do not reconstruct these SVG markers
  and nested transforms faithfully. The same file renders correctly in a browser,
  which is the actual SVG rendering target, so FEAT-031 remains verified rather than
  being reopened for downstream importer/preview behavior.
- Acceptance: a line/open path exposes start and end treatments independently; caps
  and arrow markers render identically on canvas, PNG, PDF, and SVG; selecting an
  endpoint with the point tool offers that end's options. Arrow size scales sensibly
  with stroke width. All controls keyboard reachable with distinct VoiceOver labels
  ("Start marker", "End marker"), not icon-only.

### FEAT-045 — Edit gradient stops directly on the canvas (add, recolour, right-click)
- Type: feature
- Priority: P2
- Area: color · canvas · a11y
- Status: **done — core interaction owner-verified 2026-08-19; selected-stop and
  angle synchronization owner-verified 2026-08-21.**
- Repro/Detail: Owner request 2026-08-19, straight after FEAT-032's handles landed:
  add a stop by clicking the line; change a stop's colour (or eyedrop it) from the
  knob itself, because *"if I'm editing and modifying the gradient using the inspector
  panel, the color pickers on/near the points can disappear"*; and a right-click menu
  on a stop for exact position/colour/opacity plus delete.
- **The conflict question, answered before building.** Shape POINTS are safe: path
  anchors only exist under the node tool and the gradient line only under select, so
  the two can never be on screen together. The real conflict is with DRAGGING THE
  SHAPE, since a click inside a filled shape currently picks it up and the line runs
  through the middle of that area.
  **OWNER DECISION 2026-08-19: single click on the line adds a stop, and the CURSOR
  carries the discoverability** — crosshair over the line, open hand over a knob. The
  line wins over the shape drag; grab the shape anywhere else.
- **OWNER REQUIREMENT, and the more interesting half:** the line must be clickable
  along its whole length *"even when there is technically nothing underneath it"* — a
  hole in the shape, a gap between contours, or empty canvas beyond the ink — and
  clicking it must never deselect the object being edited. The line is CHROME for the
  selected object, not part of the object. Implemented as a purely geometric
  segment hit-test that runs before ordinary picking and returns early, so nothing
  falls through to selection.
- Fix applied 2026-08-19:
  - Hit priority is ends → stops → line. A stop at 0 or 1 sits under an end, and every
    stop sits on the line, so the order is what makes each reachable.
  - **Adding never changes the gradient.** A new stop takes the colour already showing
    at that point (`GradientFill.color(at:)`), so a stray click is visually a no-op —
    then the same gesture continues as a drag, so click-and-drag places a stop in one
    motion.
  - **Click a knob → the stop's editor opens as a popover anchored to that knob.** It
    wraps the existing `ColorPopover`, so the eyedropper, the HEX/RGB/OKLCH field, the
    WCAG contrast strip and "add to Design Language" all come with it — the canvas
    gains a second PLACE to edit a colour, not a second colour editor. Position lives
    there too, as a percentage. Press-and-release with no movement is a click; a drag
    is a drag.
  - Right-click on a stop: **Edit Stop…**, **Add Color to Design Language**, Copy
    Stop, Paste Stop Here, Delete Stop. Delete is disabled below three stops — a
    gradient with one stop is not a gradient. Paste is disabled with nothing copied.
  - **"Copy Color" was replaced by "Add Color to Design Language"** (owner 2026-08-19,
    after using it): copying a hex only to turn around and paste it into the library
    was a step that did not need to exist, and the library is where a colour worth
    keeping belongs. It uses the same `save` + `remember` pair as the picker's own Save
    button, with `provenance: "gradient stop"`, so a colour added from the canvas is
    indistinguishable from one added anywhere else. **This also partly delivers
    FEAT-034** ("Add to Design Language" from the gradient controls) for this surface.
    Note the earlier Copy-Stop-vs-Copy-Color redundancy question is now settled by
    deletion rather than by choosing between them.
  - **Paste puts the stop WHERE THE POINTER IS** (owner revision 2026-08-19, after
    using it: *"tweak the paste stop just a bit, and put it where the mouse is"*).
    Pasting onto an existing stop lands on its position and recolours it rather than
    stacking an unseparable duplicate.
  - **The bare LINE is right-clickable too**, which the owner spotted falls out of the
    same change: if paste goes where the pointer is, the empty stretches of line have
    to be reachable or there is nowhere to paste into. Its menu is **Add Stop Here** /
    **Paste Stop Here**. The two END knobs deliberately have no menu — they are not
    stops.
  - Paste no longer uses the position stored by Copy Stop. The position is still
    copied because it honestly describes the stop; it is simply unused for now. The
    redundancy this created with Copy Color resolved itself when Copy Color was
    replaced by Add Color to Design Language.
  - `AppState.selectedGradientStopID` is the shared idea of "the" stop. It had to be
    lifted out of `PaintEditor`, where it was `@State` private to the picker — the
    same shape of problem as BUG-038, where state hidden inside a row view was
    invisible to the thing that needed it.
- **REMAINDER CLOSED 2026-08-21:** `PaintWell` / `PaintEditor` now accept an optional
  selected-stop binding, so document Inspector wells share
  `AppState.selectedGradientStopID` while Design Language and other isolated wells
  safely retain local state. Canvas selection receives the same ID and draws a
  non-colour-only accent ring. The Inspector angle field now updates explicit
  endpoint gradients by rotating their existing line about its midpoint, preserving
  line length and midpoint instead of writing an angle that the endpoint renderer
  ignores. Dragged endpoints and the Inspector angle therefore remain two views of
  one gradient geometry. Both directions are owner-verified.

  Also not done: Delete/Backspace on a selected stop. Menu only, on purpose — the
  Delete key currently deletes the selected SHAPE, and quietly changing what it
  destroys based on an invisible sub-selection is how people lose work.
- Owner verification 2026-08-19 covered adding, copying, editing, and the subsequent
  pointer-position paste revisions. The selected-stop and angle synchronization
  additions need the 2026-08-21 owner pass; retain the hole/undo/delete cases as
  regressions.

### FEAT-032 — On-canvas control for linear gradients
- Type: feature
- Priority: P2
- Area: color · canvas
- Status: **COMPLETE 2026-08-19 — model, export AND the on-canvas handles. Builds
  clean; owner verified the export half, the handles need verification.**
- **The model decision this entry asked for, taken and implemented 2026-08-19.**
  `GradientFill` now carries an optional `start`/`end` gradient LINE in UNIT space
  (0…1 of the fill rect — the objectBoundingBox convention CSS and SVG already use).
  `nil` means "derive from `angle`", which is exactly what every existing document
  contains, so old files load and draw identically. Decode is tolerant and a
  half-written line falls back to the angle rather than guessing. `angle` stays in
  sync with the line (`settingLine(start:end:in:)`) so the inspector's numeric field
  and every angle reader stay truthful — the entry's accessibility requirement that
  the numeric route keep working is a property of the model, not of the UI.
- **The entry told us to "check what SVG export currently emits in objectBoundingBox
  units." It was wrong, and had been for a while.** `ExportRenderer.svgGradientDef`
  built the line inside a unit SQUARE (`0.5 ± 0.5·cos/sin`) while the canvas builds it
  with CSS's aspect-aware construction (`half = (|w·cosθ| + |h·sinθ|)/2`). On any
  non-square shape at any angle other than 0/90 the exported SVG and the canvas
  quietly disagreed. Both now derive from one `unitLinearPoints(in:)`, which is exact
  for the explicit and the angle-derived case alike, because objectBoundingBox units
  ARE the rect-normalised coordinates. The element's frame is threaded to the def for
  this; call sites without a frame fall back to the unit square, which is still exact
  for square elements and for 0/90° in any element.
- **CSS keeps the line too.** `linear-gradient(<deg>, …)` always sweeps the full
  angle-derived line, so an offset start or shortened line has no direct syntax — but
  it has an exact equivalent: the two lines are parallel, so projecting one onto the
  other turns offset and length into stop percentages, which CSS permits outside
  0–100%. `cssStopPositions(in:)` does that, and returns the stops untouched when
  there is no explicit line, so ordinary gradients export byte-for-byte as before.
- **SVG import stopped throwing the line away.** `SVGImporter` collapsed x1/y1/x2/y2
  to an angle, normalising every imported gradient to a centred full-width sweep.
  It now keeps the line when `gradientUnits` is objectBoundingBox (the default);
  `userSpaceOnUse` keeps the angle-only path because those coordinates are absolute
  and would be nonsense as unit values. `gradientTransform` is still unhandled — it
  was before too, recorded so it is not mistaken for a regression.
- **THE HANDLES, built 2026-08-19.** Selecting a shape with a linear gradient draws
  the gradient line on the canvas: a knob at each end and one knob per stop, sitting
  at its position along the line and filled with that stop's own colour.
  - The line lives in UNIT space and maps through `nodeLocalToView` /
    `viewToNodeLocal`, so it follows the shape through its own rotation and flip and
    every ancestor transform — the same route the point box uses, rather than a second
    coordinate story.
  - Dragging an end sets direction AND extent, because the model now stores a line
    rather than an angle. Shift snaps to 15°, measured in the node's LOCAL POINT space
    — snapping in unit space would mean a different real angle on every aspect ratio.
  - Dragging a stop projects the cursor onto the line **in local points, not unit
    space**: on a non-square shape those are not the same direction, and projecting in
    unit space slides the stop to the wrong place.
  - `settingLine` refreshes `angle` on every tick, so the inspector's numeric field
    stays live and correct while you drag — which is how the entry's accessibility
    requirement (the numeric route must remain fully usable on its own) is met.
  - Drawn white over a dark halo. A single-colour line disappears into roughly half
    the gradients it is meant to control.
  - Hit-tested BEFORE the selection chrome, because the handles live inside the shape
    where nothing else is grabbable; ends win over stops, since a stop at 0 or 1 sits
    underneath an end. One undo step per gesture via the standard drag baseline.
  - LINEAR only. Radial's on-canvas control is a different shape (centre + radius) and
    was not what was asked for; it is not started and not implied.
- NOT verified: owner has not exercised any of it. Highest-value checks: export a
  NON-SQUARE shape with a 45° gradient to SVG and compare it with the canvas (that is
  the divergence above — it should now match, and it did not before); re-import an
  SVG whose gradient has a partial line and confirm the ramp keeps its offset; and
  confirm an existing document with gradients opens looking exactly as it did.
- Repro/Detail: Owner request 2026-08-11: adjust a linear gradient directly on the
  object "instead of trying to eye up a correct rotation degree."
- Hypothesis: this is the already-open ROADMAP Phase 8 box — *"(later) on-canvas
  gradient handles."* The conventional control is a draggable line with a start
  handle, an end handle, and the stops living on that line, so angle, length, and
  offset are all set by direct manipulation. Note the model implication: today
  `GradientFill` stores an ANGLE for linear gradients, which cannot express a start
  offset or length. Expressing the handle line faithfully means storing two points
  (as CSS/SVG gradients do) rather than an angle, with a backward-compatible decode
  from the existing angle. Decide that before building the UI, because it is a model
  change, and check what SVG export currently emits in objectBoundingBox units.
  Accessibility: a direct-manipulation control cannot be the only route — the
  numeric angle/position fields must remain and stay in sync.
- Acceptance: selecting an object with a linear gradient shows an on-canvas handle
  line; dragging its ends sets direction and extent, and stops can be dragged along
  it; the inspector fields update live and remain fully usable on their own. Shift
  constrains the angle. Old documents load with identical appearance. Canvas and
  SVG/PNG/PDF export agree. One undo step per gesture.

### FEAT-033 — Advanced multi-point gradient edited directly on the object
- Type: feature
- Priority: P3
- Area: color · canvas · export
- Status: open
- Repro/Detail: Owner request 2026-08-11: an "advanced" gradient where points are
  added directly on the object, each color's radius is definable, more can be added,
  and the flow of placing and resizing points on the object is smooth. Owner cannot
  recall which program does this.
- Hypothesis: the described interaction is Illustrator's FREEFORM GRADIENT (points
  mode), where colour stops are placed anywhere in the object and each has a spread
  radius. This is a significantly bigger piece of work than FEAT-032 and should not
  be bundled with it. The honest constraint to settle FIRST, before any UI: freeform
  gradients have NO equivalent in SVG or CSS — Illustrator itself rasterizes them on
  SVG export. Given the project's own decision test, that matters more here than the
  canvas experience: a fill that can only export as a raster image is a fidelity
  regression, and this tool exists so things survive the round trip. Options worth
  evaluating before committing: approximate with layered radial gradients (exports
  faithfully, limited), emit an SVG mesh gradient (SVG 2 meshes were dropped from
  the spec and are not supported by browsers — verify current status), or accept
  rasterization with an explicit, visible warning at export. Recommend deciding the
  export contract before writing the editor.
- **OWNER DIRECTION 2026-08-19 — the export question is answered, and it is option
  one: layered radial gradients.** The owner found the CSS "mesh gradient" technique
  (example: csshero.org/mesher) and confirmed it as the intended approach: a solid
  `background-color` plus a stack of `radial-gradient(at X% Y%, hsla(...) 0px,
  transparent 50%)` layers, one per colour point. That is exactly the
  "approximate with layered radial gradients (exports faithfully, limited)" option
  above, promoted from something to evaluate to the chosen direction — which means
  this feature no longer starts from an unanswered question.
  **Why this matters for the fidelity test:** a freeform-looking gradient built this
  way is REAL CSS, not a raster, so it survives the round trip. Each point maps to one
  radial-gradient layer with a position and a radius, which is very close to the
  owner's original description of "points placed on the object, each colour's radius
  definable."
  **Still to verify before any UI, and NOT yet checked:** (a) the SVG story — the same
  idea should express as overlapping shapes with `<radialGradient>` fading to
  transparent, but that has not been confirmed against the exporter or against how
  other tools import it; (b) whether canvas rendering of N stacked radial gradients
  stays interactive (the noise/dissolve tiling work is the precedent to reuse if not);
  (c) how the layer stack round-trips back IN through the CSS/SVG importers, since
  reading it back as one editable freeform fill is the harder half.
  **Scheduled for v2.4 by the owner** (2026-08-19): *"it can be next version since
  we're improving quite a bit in this next release already."* FEAT-032 ships first.
- Acceptance: not ready for an acceptance contract, but the export story is no longer
  the blocker — the first deliverable is now the SVG half of it plus the import
  round-trip question, then a UI spec.

### FEAT-034 — "Add to Design Language" from the gradient and font controls
- Type: feature
- Priority: P2
- Area: color · type · design-language
- Status: **partly delivered by FEAT-045; remaining surfaces deferred to v2.4 by
  owner decision 2026-08-21**
- Repro/Detail: Owner request 2026-08-11: an add-to-Design-Language button on the
  gradient control, so adding a gradient does not require opening the Design
  Language panel — while keeping that route too. Owner: "can be the same 'save' icon
  even." Then, immediately after: "oh, and fonts too."
- Hypothesis: this is a consistency fix more than a feature. Colors already have
  multiple ways in (FEAT-001 landed document-model save/pick/recents in the color
  popover, Session 167); gradients and fonts do not, so the app teaches one pattern
  and then breaks it. Reuse the existing save affordance and the same
  `DesignLanguage` entry shape (id, name, status candidate/official/archived, value,
  provenance) rather than inventing per-type flows. Naming is the interaction worth
  getting right: prompt inline for a name with a sensible default, and do not silently
  create unnamed entries that the Design Language panel then has to explain.
- Acceptance: a gradient and a font/type style can each be added to the document's
  Design Language directly from their inspector control, with the same icon and
  interaction as the color path; the entry appears in the Design Language panel with
  a name and candidate status; the panel route still works; one undo step; the
  control is keyboard reachable and its VoiceOver label states what will be saved.

### FEAT-035 — Give the font dropdown the same visual definition as other dropdowns
- Type: feature
- Priority: P2
- Area: inspector · chrome · a11y
- Status: **done — measured and owner verified 2026-08-21.**
- Implementation 2026-08-21: custom popup triggers now share one hover-aware chrome
  and an opaque boundary token. Measured boundary contrast against the dark panel,
  dark raised, light panel, and light raised surfaces is respectively 5.11:1,
  4.82:1, 5.37:1, and 4.89:1. The same opaque token is retained under Increase
  Contrast and the focus ring remains system-owned. Visual verification in both
  appearances and Increase Contrast is owner-verified; measurements and inventory are
  recorded in `docs/ACCESSIBILITY-CONTROL-AUDIT.md`.
- Repro/Detail: Owner report 2026-08-11: since the new font dropdown shipped
  (`FontFamilyPicker`, FEAT-008a), it "fades in too much with the background."
  Owner's framing: style it up to be as defined as the other dropdowns, OR bring the
  other dropdowns up to match — "just with slightly more definition to see easily,
  whichever is easier."
- Hypothesis: the custom popover trigger is drawn as a borderless/plain control
  while the native `Menu`/`Picker` controls around it get the system's bordered
  treatment, so it reads as text rather than as a control. Recommend the second
  option the owner offered — one consistent, slightly more defined treatment across
  ALL dropdowns — because "which control is interactive?" is an affordance problem,
  not a font-picker problem, and fixing only the outlier leaves the rest quietly
  under-defined. Fold this into the FEAT-010 panel pass so it is decided once. This
  is also a real accessibility item, not taste: WCAG 2.1 AA §1.4.11 Non-text Contrast
  requires a 3:1 contrast ratio for the visual boundary of user-interface components
  against adjacent colors. Measure the current boundary contrast before and after,
  in light and dark, and record the numbers — do not eyeball it.
- Acceptance: every dropdown in the inspector shares one boundary treatment whose
  contrast against its background measures at least 3:1 in light mode, dark mode,
  and Increase Contrast; the font picker is no longer the outlier; the measured
  ratios are recorded in this entry. Hover/focus/pressed states are visible and
  keyboard focus rings are unaffected.

### FEAT-036 — Replace the text-case dropdown with an icon control
- Type: feature
- Priority: P3
- Area: inspector · type · a11y
- Status: **done — owner verified 2026-08-21.**
- Implementation 2026-08-21: Case is now one exclusive segmented icon control for
  As typed, Uppercase, Lowercase, Capitalize each word, and Sentence case. Each
  segment has an independent accessible name and supplemental help, the selection
  is indicated structurally as well as by colour, and all four arrow keys move the
  selection. Keyboard, VoiceOver, larger interface type, and Increase Contrast are
  owner-verified.
- Repro/Detail: Owner request 2026-08-11: change the "case" dropdown to the standard
  icons, noting "we've got a good pattern for tooltips as well."
- Hypothesis: a segmented control of the conventional case glyphs (AA / aa / Aa,
  plus none) is the familiar pattern and saves horizontal space in a panel that
  FEAT-010 says is already cramped — so this helps that problem too. The
  accessibility requirement is firm and worth stating because icon-only controls are
  where tools usually fail: each segment needs a programmatic accessible NAME
  (`accessibilityLabel`), and a tooltip is NOT an accessible name. Tooltips help
  sighted mouse users only; they do nothing for a screen-reader or keyboard user and
  are not exposed reliably. So: real labels first, tooltips as an addition (see
  FEAT-037). Also confirm the icons remain distinguishable in Increase Contrast and
  at larger UI type sizes, and that the control is not conveying its state by color
  alone (WCAG 2.1 AA §1.4.1 Use of Color).
- Acceptance: text case is set from an icon segmented control with correct
  accessible names on every segment; the active segment is indicated by more than
  color; the control is keyboard operable with arrow keys; it survives Increase
  Contrast and larger type sizes; tooltips supplement rather than replace the labels.

### FEAT-037 — Tooltip audit across every inspector and tool control
- Type: feature
- Priority: P2
- Area: chrome · inspector · a11y
- Status: **done — code/inventory complete and owner verified 2026-08-21.**
- Implementation 2026-08-21: the committed inventory is
  `docs/ACCESSIBILITY-CONTROL-AUDIT.md`. Ambiguous abbreviations and icon actions in
  the tools strip, top bar, transform, align/distribute, layout, paint, effect,
  typography, grid, and point-selection surfaces now have stable programmatic names.
  The shared rich-tip presenter opens from hover or keyboard focus, is hoverable,
  persists across the pointer gap, and dismisses with Escape. Follow-up 2026-08-21:
  registered control bounds now give adjacent fields priority over an overlapping
  bubble—the prior tip closes immediately when the pointer reaches another control,
  while non-control tooltip text remains hoverable. This implements the code side of
  WCAG 2.1 SC 1.4.13; it has NOT yet been verified with VoiceOver,
  Accessibility Inspector, keyboard-only traversal, or the appearance settings.
- Repro/Detail: Owner request 2026-08-11: audit all the settings labels and add
  tooltips to "even the things we think are common sense." Owner's example is the
  right one — *"'R' for rotate, sure, but 'resize' also starts with an R. So does
  'rectangle'. We assume nothing."*
- Hypothesis: an inventory pass, not an engineering one — enumerate every abbreviated
  label, icon-only button, and unlabelled field across the inspector, tools strip,
  and panels, and give each a tooltip plus a verified accessible name. Two rules to
  hold while doing it, both from the spec rather than preference: (1) a tooltip is
  never the accessible name — screen readers do not reliably expose `help(_:)`
  content, so `accessibilityLabel` must carry the meaning independently; (2) tooltip
  behavior must satisfy WCAG 2.1 AA §1.4.13 Content on Hover or Focus — dismissable
  without moving the pointer, hoverable (the pointer can move onto the tooltip
  without it vanishing), and persistent until dismissed or invalid. macOS's native
  `help(_:)` tooltips do not fully satisfy 1.4.13 on their own; check what the system
  actually provides before promising conformance, and record what was NOT verified.
  Deliverable is a checklist table (control → tooltip text → accessible name → done)
  so the work is resumable across sessions.
- Acceptance: every abbreviated or icon-only control has both a tooltip and a
  distinct accessible name; ambiguous single letters are spelled out ("Rotate", not
  "R"); the audit table is committed to the repo and complete; tooltip behavior is
  measured against §1.4.13 with the result stated honestly, including any gap left by
  the platform. Verified with VoiceOver, keyboard-only, and Increase Contrast.

### FEAT-038 — User-configurable tooltip verbosity
- Type: feature
- Priority: P3
- Area: chrome · settings · a11y
- Status: **done — owner verified at all three levels 2026-08-21.**
- Implementation 2026-08-21: Settings ▸ General now offers Full, Standard, and
  Minimal tooltip detail, persisted app-wide. Minimal means shorter visible copy,
  not fewer reachable controls. The complete description remains the accessibility
  hint at every level, and holding Option temporarily reveals the full explanation.
  The accessible name never changes. Live verification at all three levels remains.
- Repro/Detail: Owner request 2026-08-11, by analogy: like a game's advisor setting,
  where you pick "new to the game" and see all tips, or "familiar with the franchise,
  new to this version" and see only version-specific ones. Owner was unsure how to
  express it; the analogy is clear enough to build from.
- Hypothesis: a small enum in Settings — e.g. Full / Standard / Minimal — with each
  tooltip tagged by level, so the audit table from FEAT-037 gains a column rather
  than needing separate copy. Build it on top of FEAT-037; it is meaningless before
  the audit exists. Two constraints that must not be traded away: (1) lowering
  verbosity may only remove information available elsewhere, never information that
  exists ONLY in the tooltip — otherwise the setting removes an accessibility
  affordance rather than reducing noise; (2) the accessible name is not part of this
  setting and never varies by level, because it is the only thing some users get.
  Worth confirming with the owner whether "Minimal" should mean shorter tooltips or
  fewer tooltips — those are different products, and shorter is likely safer.
- Acceptance: a Settings control chooses tooltip verbosity; the choice persists;
  every level leaves every control's accessible name intact and every piece of
  information reachable somewhere; the default is the level a new user benefits from
  most. Verified with VoiceOver at each level. Blocked by FEAT-037.

### FEAT-039 — EPS import (research first — the platform path is not obvious)
- Type: feature
- Priority: P3
- Area: import · research
- Status: open — research, not committed
- Repro/Detail: Owner request 2026-08-11: "import EPS files (is this possible?)" —
  the question mark is the owner's own, and it is the right instinct.
- Hypothesis / honest constraint: EPS is encapsulated PostScript, a full programming
  language, not a data format — which is why support for it keeps disappearing rather
  than improving. macOS's own EPS handling has been retreating for years: the
  `pstopdf` command-line converter was removed in macOS Ventura, and `NSEPSImageRep`
  is long-deprecated and was never a general-purpose interpreter. So there is very
  likely no supported native path on the macOS 26 SDK, which means the realistic
  options are (a) Ghostscript, which is AGPL — a licensing decision with real
  consequences for a shipped app and one the owner must make, not one to be assumed;
  (b) handling only the common case where an EPS carries an embedded PDF or a
  preview, which covers many Illustrator-authored EPS files and nothing else;
  (c) declining, and documenting why. THIS IS FROM MEMORY AND MUST BE VERIFIED
  against current Apple documentation and the macOS 26 SDK before any of it is
  treated as settled — do not quote these specifics to the owner as confirmed. Note
  that most workflows that "need EPS" are satisfied by PDF or SVG import, which is
  worth checking with the owner before spending anything here. The existing PDF
  importer work is the natural comparison point.
- Acceptance: first deliverable is a verified written finding — what the macOS 26
  SDK actually supports, what Ghostscript would cost in licensing terms, and what
  fraction of real EPS files the embedded-preview path would handle — with sources.
  No implementation commitment until the owner reads it and decides.

### FEAT-040 — Data import (parking lot)
- Type: feature
- Priority: P3
- Area: import · model · research
- Status: parking lot — not scoped
- Repro/Detail: Owner note 2026-08-11: "data import? might be a future addition. Not
  sure on it, but park it."
- Hypothesis: parked deliberately with no design, because the request has at least
  three very different readings and picking one now would be guessing: (a) populating
  repeated component instances from a CSV/JSON table (Figma's "Contents" / Sketch's
  Data plugin — realistic content instead of lorem ipsum, and a genuinely good fit
  for a fidelity tool since it makes the exported artifact more representative);
  (b) importing design tokens as data into the Design Language; (c) charts/data
  visualization, which is a different product. When this comes off the parking lot,
  the first question is which of these the owner meant. (a) is the one that fits the
  project's stated purpose.
- Acceptance: none yet — parked. Revisit by asking the owner which reading they
  meant before any design work.

### FEAT-043 — Line-height unit switch converts the value; arrows step by the unit
- Type: feature
- Priority: P1
- Area: type · inspector
- Status: **done — owner verified 2026-08-19** ("that's fixed and works well").
- Repro/Detail: Owner request 2026-08-19, while verifying Wave 2: *"if the line
  height unit selector, when changed, would adjust the value to match instead of
  just changing the unit. For example, if I've got large text, so the line height is
  64px, switching to × or ems is DRASTICALLY different. Also, especially with the
  ×/no units, I'd love if arrow keys up/down move by decimal point instead of
  forcing whole point stepping."*
- Both halves were true. `lineHeightUnitBinding` wrote the new unit and left
  `lineHeight` alone, so 64px became 64× — with TextKit's `lineHeightMultiple` that
  is a line box thousands of points tall. And the field used the app-wide default
  `numericStepping` step of 1, which is the right step for points and useless for a
  multiplier that lives between roughly 0.8 and 2.
- Fix applied 2026-08-19:
  1. `TextContent.renderedLineHeightPoints` and
     `TextContent.lineHeightValue(for:in:)` in `UI/Typography.swift` — conversion
     lives next to `paragraphStyle(scale:)`, the code that defines what each unit
     MEANS, so the two cannot drift. The unit binding now reads the rendered height
     in points, sets the unit, and writes the converted number back, rounded to 3
     decimals so the displayed 1.40 is not secretly 1.3999 when an arrow steps it.
  2. **`.multiple` divides by the font's NATURAL line height, not by the font
     size.** `NSParagraphStyle.lineHeightMultiple` multiplies the natural line
     height; CSS's unitless `line-height` multiplies the font size. They are not the
     same number, and since this app lays out through TextKit, TextKit's definition
     is the one that has to be inverted. Uses the same
     `NSLayoutManager.defaultLineHeight(for:)` as the existing fixed-line-height
     leading correction, so "natural" means one thing in this file.
  3. `lineHeightStep` — 0.1 for × and em, 1 for px, keeping the app-wide modifier
     relationship (Shift 10×, Option 0.1×), so ×/em give 0.1 / 1.0 / 0.01.
  4. The field's hover/VoiceOver help now states both behaviours.
- **Switching TO Auto is the deliberate exception** and is documented in the code:
  Auto is not a free-floating unit, it IS a value (the font's natural line height),
  so selecting it changes the rendering by definition. The authored number is kept
  untouched there, so switching back off Auto lands on exactly what Auto was
  drawing rather than on a stale number.
- Acceptance: set 64px on large type, switch to × — the text does not move and the
  field shows the equivalent multiplier; switch to em and back to px and land on 64
  again (± rounding). Arrow keys move × and em by 0.1, Shift by 1, Option by 0.01;
  px still moves by 1. Every unit change is one undo step. Exported CSS and the
  `.design` round trip are unchanged in meaning.
- NOT verified: owner has not exercised it; no VoiceOver pass on the revised help
  text; conversion uses the FIRST run's font, consistent with how `.em` already
  renders, so a mixed-size selection converts against the first run — correct but
  worth a look with genuinely mixed text.

### FEAT-041 — Shape tracing / auto-trace (parking lot, with eyes open)
- Type: feature
- Priority: P3
- Area: canvas · vector · research
- Status: parking lot — not scoped
- Repro/Detail: Owner request 2026-08-11, with an accurate assessment attached:
  "how hard would it be to add a 'trace shape'? I can imagine it's a beast since
  Adobe has had this in Illustrator for 7 billion years and it still sucks. Maybe
  include a future parking-lot exploration."
- Hypothesis: the owner's read is correct and worth recording so it does not get
  re-litigated optimistically later. Raster-to-vector tracing is a genuinely hard
  problem with no clean answer — the well-trodden path is Potrace (bitmap → bezier;
  GPL, which carries the same licensing question as FEAT-039) for bilevel images, or
  a colour-quantize-then-trace-each-layer pipeline for full colour, which is where
  quality falls apart. Even a good implementation produces output a designer must
  clean up, which sits awkwardly against "the tool should get out of the way."
  Before any work, the project's own decision test should be applied honestly: does
  tracing make the exported artifact more faithful, or does it just make the canvas
  more impressive? A traced logo is an approximation of something that usually exists
  as a real vector somewhere — so the highest-value version of this request might be
  better PDF/SVG/AI import rather than tracing at all. Worth asking the owner what
  they actually reach for tracing to accomplish.
- Acceptance: none yet — parked. If revisited, start with the question above, not
  with an algorithm.

### FEAT-019 — Notes checkboxes should round-trip as GFM task lists
- Type: feature
- Priority: P3
- Area: export · notes
- Status: open
- Repro/Detail: the notes editor writes checkboxes as `[ ] ` / `[x] ` at the start of a
  line and styles them in place (checked lines strike through). The Handoff Package
  emits notes as live Markdown inside a blockquote, but GitHub-flavoured Markdown needs
  `- [ ] ` to render a task list — a bare `[ ] ` renders as literal text. So checkboxes
  are the one notes affordance that does not survive the round trip.
- Hypothesis: either write `- [ ] ` in the editor (and style the leading `- ` as part of
  the marker so it still reads as a checkbox, not a bullet-plus-brackets), or normalize
  `[ ] ` to `- [ ] ` at package-write time. Prefer the editor, so what is stored is what
  is exported — the model stays a plain String either way.
- Acceptance: a checklist typed in artboard notes renders as a real task list in the
  Handoff Package's orientation Markdown; existing notes with bare `[ ] ` still render
  acceptably; the notes editor's checkbox styling and Return-continuation are unchanged.

### FEAT-020 — Select All Artboards command
- Type: feature
- Priority: P2
- Area: chrome · canvas
- Status: **done — owner verified 2026-08-16 through the contextual Select All
  Artboards → Clean Up workflow.**
- Repro/Detail: Arrange ▸ Clean Up (and artboard Align/Distribute) require 2+ boards
  SELECTED, by deliberate design — they never fall back to acting on the whole page, so
  a stray keystroke cannot rearrange a document. The gap is that tidying a whole page
  therefore means selecting every board by hand, and Select All targets nodes.
- Hypothesis: add `selectAllArtboardsAction:` on `CanvasNSView` (document scope only),
  with an Edit-menu item near Select All, a canvas context-menu entry on empty canvas,
  and a `validateMenuItem` case requiring a non-empty artboard list. Full
  command-coverage wiring per CLAUDE.md; no Inspector control needed (no parameters).
  ⇧⌘A is the conventional neighbour to ⌘A if it is free.
- Resolution: a separate command was unnecessary. The existing Select All behavior is
  contextual: with an artboard selection active, it selects all artboards on the
  current page. The owner confirmed that selection followed by Clean Up works well.
- Acceptance: one command selects every artboard on the active page; Clean Up and
  artboard Align/Distribute then work page-wide in one further step; the command is
  disabled on a page with no artboards and in component-source scope.

### FEAT-012 — Anchored relationships: endpoints as instance paths, stored at the nearest common ancestor
- Type: feature (model)
- Priority: P1 — blocks BUG-008 acceptance, and everything downstream of Chunk I
- Area: model · inspector · export · handoff · import
- Status: done (owner verified 2026-07-28). All five chunks I-a…I-e are written
  and build clean. I-d was confirmed
  in a real export (`tab-test3.exph`: three `aria-controls` resolving to the panel
  with depth-2 chain ids), and I-c's participant display was owner-verified on
  2026-07-24. On 2026-07-27 the anchored, graph, semantic-contract, deterministic
  package, and SVG suites all passed, followed by the full signed Debug app,
  Quick Look, and helper build. The owner-facing duplicate independence,
  save/reopen, Quick Look, relationship, and export matrix passed 2026-07-28.
- DISCOVERABILITY finding, owner 2026-07-24: they first selected the individual tab
  and saw nothing, because a nested tab is not selectable and the participants only
  appear on an ANCESTOR. Selecting the enclosing group shows every participant
  (`participants(from:)` recurses through groups), and selecting the Tab Bar shows
  it plus its tabs — but neither is signposted. Nothing is broken; the affordance is
  just invisible until someone tells you. Candidates when the F2 / panel-IA pass
  lands: surface the anchor's participants when a NON-roled layer inside the anchor
  is selected, rather than showing only `unroledSelectionNote`; or make the Layers
  row for a nested roled component reveal its relationships. Do NOT solve this by
  making nested layers selectable — they exist once per placement, which is the
  whole reason FEAT-012 exists. Both are deliberately runtime-INVISIBLE: the
  exporter still reads the legacy `Node.relationships`, and the switch-over happens
  in I-d. That is what makes it safe to have written them ahead of a build.
- Origin: owner tried to author the APG tabs pattern and could not. Structure was
  a Tab Bar component (role `tablist`) whose children are Tab components (role
  `tab`), placed in an artboard group beside a Tab Panel component (role
  `tabpanel`). Widening the target picker was the obvious-looking fix and is the
  WRONG one — recorded so nobody tries it again.
- VERIFIED against the WAI-APG Tabs pattern, 2026-07-24
  (https://www.w3.org/WAI/ARIA/apg/patterns/tabs/):
  - "Each element that serves as a tab has role `tab` and is contained within the
    element with role `tablist`." The owner's nesting is CORRECT; do not advise
    restructuring it.
  - "Each element with role `tab` has the property `aria-controls` referring to
    its associated `tabpanel` element", and "each element with role `tabpanel` has
    the property `aria-labelledby` referring to its associated `tab` element." So
    the link is tab-to-panel, individual to individual — never tablist-to-panel.
  NOT VERIFIED: whether a single `tabpanel` shared by several tabs conforms. The
  APG describes a 1:1 pairing and says nothing explicit about the shared case;
  this was NOT resolved and FEAT-013 depends on it. Do not assert either way.
- Root cause: a relationship is stored ON THE SUBJECT NODE. The subject here (a
  tab) lives inside the Tab Bar SOURCE, and anything stored in a source applies to
  every placement of it — so all placements of Tab Bar would point at one panel.
  The link has to vary per PLACEMENT, so it cannot live in the source. This is a
  storage problem, not a picker-scope problem. Widening the neighborhood would
  only let someone author a link that cannot export correctly.
- DECISION (owner delegated the mechanism 2026-07-24: "just find the most stable
  and scaleable method"): **a relationship lives at the nearest node that contains
  BOTH of its ends, and addresses each end by instance PATH rather than raw id.**
  For the owner's file the anchor is the artboard group holding Tab Bar and Tab
  Panel; the tab end is `[TabBarInstance, TabOne]`, the panel end is
  `[TabPanelInstance]`. Place that group twice and each copy resolves to its own
  ids — no cross-placement leak, no duplicate DOM ids.
  Why this over the alternatives:
  - It makes the NEIGHBOURHOOD rule fall out instead of being a separate
    constraint bolted on: the neighborhood IS the anchor's subtree. One concept.
  - It is the same machinery Chunk I already needs for "stable instance paths"
    (nested overrides, visibility, DOM ids, import reports), so it is not new
    surface area — it is the planned surface area, reached from the front door.
  - Roles-on-plain-groups (FEAT-014) was considered FIRST and REJECTED as the fix.
    It would not have helped this case at all: the owner's roles are already on
    components, correctly. Logged separately on its own merits.
- CHUNKS, in dependency order. Each is meant to land and be verified on its own.
  - **I-a — `RelationshipEndpoint` path type.** `[UUID]`, innermost-last. Tolerant
    decode so a legacy single `targetID` becomes a one-element path and behaves
    exactly as today. Resolution + validation helpers on `Document`. NO UI and NO
    behavior change: this chunk should be invisible at runtime, which is what
    makes it safe to verify.
    DONE (needs owner build): `RelationshipEndpoint` (an `instanceChain` outermost
    first + a non-optional `nodeID`, so an endpoint cannot be malformed the way a
    bare `[UUID]` could); `NodeRelationship.target` replaces the stored `targetID`,
    which survives as a get/set accessor so every existing call site compiles and
    behaves identically; decode accepts either form; encode writes BOTH, so a v2.1
    file still opens in a v2.0 build and degrades to sibling behavior instead of
    failing to decode. `Document.resolveEndpoint(_:in:)` walks a path, descending
    through component instances via `resolvedChildren` and treating plain groups as
    transparent — a path never names a group, so links survive regrouping — with
    the same depth cap the dependency walker uses so a damaged document terminates.
  - **I-b — Anchored storage + migration.** Move relationships off the subject node
    onto the anchor. Add the anchor container, decide it by nearest-common-ancestor
    at author time, and migrate existing node-stored relationships (subject and
    target already share a parent today, so every existing one migrates to that
    parent without ambiguity). Repair anchors on move, regroup, ungroup, delete,
    and component-source deletion — the same paths that already repair
    `nestedStateOverrides`.
    DONE (needs owner build): `AnchoredRelationship` (kind + subject endpoint +
    target endpoint). THREE anchor stores, because three things can contain both
    ends — `Node.anchoredRelationships` (groups),
    `ComponentSource.anchoredRelationships`, and `Document.anchoredRelationships`
    as the top-level fallback. Authoring will never create the document-root case
    (the neighborhood rule requires a group), but migration can, so it exists
    rather than silently dropping a legacy link. A subject may name the ANCHOR
    ITSELF, which is how a component's own relationships are expressed — the
    element carrying the role hosts the instance, so it IS the anchor — needing no
    special case in the data, only `endpointNamesAnchor(_:anchorID:)`.
    `migrateRelationshipsToAnchors()` runs at decode and is ADDITIVE: the legacy
    `Node.relationships` and `a11y.rootRelationships` are left intact and still
    encoded, so a wrong migration is recoverable rather than destroying a document
    the first time it is saved. Idempotent, with dedupe on (kind, subject, target)
    and NOT on `id` — `id` is freshly minted each run and would have defeated the
    check, a bug that would only surface as slow duplication over many open/save
    cycles. `nearestCommonAncestorGroup` considers GROUPS only: a legacy
    relationship could only ever address a sibling, so it never crossed an instance
    boundary, and treating instances as containers would invent nesting the stored
    data does not have.
    STILL TO DO in I-b: anchor REPAIR on move, regroup, ungroup, delete, and
    component-source deletion. Deferred on purpose — nothing reads the anchored
    form until I-d, so a stale anchor cannot affect anything yet, and repair is far
    easier to write against the authoring UI I-c adds than against nothing.
  - **I-c — Authoring UI.** The subject picker must now reach INTO nested instances
    (selecting one tab inside Tab Bar), and the target picker likewise, both scoped
    to the anchor's subtree. Keeps FEAT-011 wording and the role annotation already
    shipped. This is where the owner can finally test the tabs pattern.
    DONE (needs owner build): the inspector no longer authors "the selected node's
    relationships" — it authors the ANCHOR's, and lists a block per PARTICIPANT.
    A participant is anything roled that the selection can reach: the selection
    itself, the component root in source scope, and every roled component nested
    inside the selection. That is what makes one tab inside a placed Tab Bar
    authorable even though it cannot be selected — which was the blocking problem.
    `relationshipEndpoints(in:chain:depth:)` builds the pickable ends: groups are
    transparent (a path never names one, so a link survives regrouping), and
    component instances contribute themselves plus ONLY their roled descendants.
    That last rule is deliberate — an unroled layer inside a component is that
    component's private business, and linking to one from outside couples two
    components at a level that breaks the moment either is edited, while a
    component's roled parts are its public semantic surface and the only thing ARIA
    has any use for out here. A target that no longer resolves stays SELECTABLE as
    "Missing layer" instead of silently reverting to None.
    `Document.hasRelationshipParticipant(in:)` now backs the Object-menu item, the
    canvas context menu, AND the inspector, replacing three separate copies of the
    same test — the arrangement that lets a menu and a panel drift apart.
    NOT YET: export still reads the legacy `Node.relationships`, so links authored
    this way persist and round-trip but do NOT appear in exported HTML until I-d.
    Verify I-c on authoring and persistence only.
  - **I-d — Export.** Resolve paths to emitted DOM ids. Note
    `SemanticHTMLIdentity.nodeDOMID(_:instanceID:)` takes ONE instance id, so ids
    collide at nesting depth 2+ — this chunk must widen it to a path and therefore
    CLOSES the roadmap's "replace ambiguous raw descendant ids with stable instance
    paths" item. Handoff Package and Quick Look ride the same resolution.
    DONE (needs owner build): `nodeDOMID(_:chain:)` composes an id from the whole
    instance chain, outermost first. Depth-1 output is UNCHANGED, so existing
    exports keep their ids and only the previously-colliding depth-2+ cases move.
    `render`, `collectDOMIDs`, and BOTH CSS emitters (`append`, `appendState`) now
    carry the chain — the CSS half matters as much as the HTML: a selector minted
    from a single instance id stops matching its element at depth 2, which would
    have been a silent styling bug rather than a loud one.
    Relationships are now READ FROM ANCHORS, not from `Node.relationships`.
    `anchoredAttributes(...)` resolves one anchor's entries into attributes keyed by
    the DOM id of the element that must carry them, and `render` passes that map
    down so a subject simply looks itself up. Anchors encountered: the document root,
    any group holding entries, and every component source. Reading only the anchored
    form is what makes a DELETE actually delete — emitting both would let a stale
    legacy entry resurrect an attribute the designer removed. Nothing is lost,
    because migration writes an anchored twin at decode.
    The BUG-008 prohibition moved to the point of EMISSION, where the host's role is
    known: `aria-labelledby` on a roleless element is dropped with a
    `prohibitedRelationship` issue, while the two GLOBAL properties are emitted.
    The now-dead legacy `relationshipAttributes` was deleted rather than left in
    place, so there is exactly one read path.
    NOT DONE: I-e's headless checks.
  - **I-e — Fidelity + checks.** Headless coverage for: same group placed twice
    resolving independently; anchor repaired on regroup/ungroup/delete; an endpoint
    whose path no longer resolves reported as `unresolvedRelationship` rather than
    silently dropped; no duplicate ids at depth 2.
    DONE (needs owner build): the REPAIR half, which was the urgent part —
    `CanvasView.ungroup` used to replace a group node with its children and take
    its `anchoredRelationships` with it, destroying authored semantics on an
    ordinary edit with no warning. Entries are now HOISTED to whatever still
    contains both ends: the enclosing group, or the scope root via
    `commitNodes(appendingRootAnchors:)` so the whole thing stays ONE undo step.
    Endpoints need no rewriting, because a path names component instances only and
    never groups. GROUPING needs no repair at all for the same reason — a pleasant
    consequence of the path design, now covered by a check so nobody "fixes" it.
    Explicit DELETE drops relationships naming the removed subtree at either end
    (`Document.removingAnchors(referencing:)`), collected over the whole subtree so
    deleting a group also clears links to layers inside it. Deliberately keyed to a
    specific id set rather than "prune anything unresolved" — a mid-edit tree can be
    briefly unresolvable and a general sweep would eat real work.
    `scripts/AnchoredRelationshipCheck.swift` + `verify_anchored_relationships.sh`
    cover: groups transparent to paths, duplicate independence (BUG-010),
    delete precision, ungroup hoisting, depth-2 id uniqueness with depth-1 output
    unchanged, and migration being lossless AND idempotent.
    NOT DONE: MOVE repair (dragging a node out of its anchor's subtree still strands
    the link — it now reports as orphaned rather than vanishing, which is the
    important half), and the UI to see and clear orphaned entries (BUG-012's
    follow-up).
- Acceptance: author `tab → controls → tabpanel` across two sibling components in
  one group; place that group twice; both copies export correct, distinct,
  non-colliding `aria-controls` / `aria-labelledby`; regroup and ungroup without
  losing links; save/reopen; no cross-placement leakage.

### FEAT-013 — Relationships that vary by component state
- Type: feature (model)
- Priority: P3 — NOT needed for the tabs file after all (see resolved question below); depends on FEAT-012
- Area: model · export · handoff · a11y
- Status: LOGGED 2026-07-24, NOT STARTED
- Origin: owner's Tab Panel is ONE `tabpanel` component holding three text areas
  with two hidden — and confirmed the hiding is deliberate: those are component
  STATES, not three separate panels. That is a coherent model, but it means the
  panel's accessible name has to change with the active state: `aria-labelledby`
  should name whichever tab is currently selected.
- Why it fits EXP rather than fighting it: states are already override-diffs
  against the base, and the exporter already emits `data-state` per active state.
  A relationship that lives in the state diff says exactly the right thing in
  handoff — "in state Tab Two, this panel is named by Tab Two" — without EXP ever
  storing behavior or shipping JS. That is the whole thesis of the file format.
- OPEN QUESTION — NOW RESOLVED, 2026-07-24, and the answer is that FEAT-013 is NOT
  the fix for tabs. Verified against the APG Tabs pattern
  (https://www.w3.org/WAI/ARIA/apg/patterns/tabs/): "Each element that CONTAINS THE
  CONTENT PANEL FOR A TAB has role `tabpanel`", and "when the user activates one of
  the other tab elements, the previously displayed tab panel is HIDDEN, the tab
  panel associated with the activated tab BECOMES VISIBLE." So the pattern has one
  panel PER TAB, all present, with visibility toggling between them — which is
  exactly what a real tabs widget renders.
  That reframes the owner's structure rather than blocking it. Their tab panel
  component holds three text areas with two hidden, modelled as three component
  STATES. Semantically those three areas already ARE three tabpanels; the "states"
  are the visibility toggle the pattern describes. The right structure is three
  roled panels (three instances of a Panel component, each with its own text
  override — supported today at the top level), one per tab, 1:1. That exports
  statically with no dynamic attributes and needs nothing from FEAT-013.
  The reason one shared panel does not work is concrete: `aria-labelledby` on the
  panel must name the ACTIVE tab, so with three tabs it would have to change at
  runtime. Not expressible statically, and EXP ships no JS.
- STILL WORTH BUILDING, for a different reason: a relationship that legitimately
  varies by state — a disclosure whose description differs when expanded, an input
  whose helper text becomes an error message. Those are genuinely per-state and
  have no structural workaround. Re-scope this entry to those cases; do NOT justify
  it with tabs.
- Acceptance: a relationship can be authored per state; the base and each state
  round-trip; export emits the base attribute plus per-state guidance; the handoff
  reads as a sentence a developer can implement; nothing is emitted that implies
  EXP is producing behavior.

### FEAT-014 — Let a plain group carry an ARIA role
- Type: feature (model)
- Priority: P2
- Area: model · inspector · export · a11y
- Status: LOGGED 2026-07-24, NOT STARTED
- Detail: `Node` has no `a11y` at all — only `ComponentSource` does. So a role can
  ONLY be carried by a component instance, which is an EXP artifact, not an ARIA
  one: in ARIA any element may carry a role. The practical cost is that a designer
  must componentize a wrapper just to say "this is a list" or "this is a region",
  and every group that is not a component exports as an unroled `<div>` whose
  implicit role is `generic` — which is exactly the population BUG-008 had to
  suppress relationship offers on.
- Explicitly NOT the fix for FEAT-012. It was considered first and rejected: the
  owner's roles were already on components and correctly placed, so this would
  have changed nothing about their blocked case. Recorded here on its own merits.
- Design question to settle first: precedence when an INSTANCE node carries a role
  and its source also does. Options are node-overrides-source, source-wins, or
  forbid the combination. Pick one deliberately and write it down — an ambiguous
  precedence rule here would rot quietly for years.
- Acceptance: a group can be given any curated role; the inspector offers the same
  picker it offers a component; export emits the role on the group element; the
  containment advice and relationship rules treat it exactly like a roled instance;
  old files decode unchanged.

### BUG-008 — Relationship authoring offers ARIA kinds on layers that cannot carry them
- Type: bug
- Priority: P1 (soon)
- Area: model · inspector · export · a11y
- Status: done (owner verified 2026-07-27). Shipped together
  with FEAT-011 as the owner sequenced. What landed:
  - `NodeRelationship.Kind.isProhibitedWithoutRole` — true for `labelledby` ONLY.
    The doc comment spells out why the other two are not the same case, so nobody
    "tidies" the three into one rule later.
  - `A11ySemantics.rootRelationships` — the component's OWN relationships, stored
    on the SOURCE (tolerant decode; absent in every pre-v2.1 file). Owner chose
    the "component root row in the source editor" option over authoring on a
    placed instance, so these are part of the component CONTRACT and two uses
    cannot drift apart.
  - Inspector: `layerRelationshipKinds` now reads the selected layer's OWN
    effective export role (`effectiveExportRole(of:)` — an instance carries its
    source's role, everything else has none), not the enclosing source's. The
    Relationships section splits into "This component" and "This layer"; the
    layer block appears only when that layer has a role of its own or already has
    authored relationships. A note under a roleless layer distinguishes the
    prohibited case from the merely-pointless one.
  - Exporter: `relationshipAttributes(hostRole:authored:)` drops a prohibited
    naming attribute and raises a `prohibitedRelationship` fidelity issue;
    root relationships are emitted on the instance-hosting element, resolved
    per-instance so two uses never cross-link.
  - `Document.flattened` carries root `controls`/`describedby` onto the group
    that replaces a deleted source's instance (retargeted via the existing
    id map) and drops root naming, which is invalid on a roleless group.
  - Menu validation updated in BOTH `MainWindow` and `CanvasView` so the Object ▸
    Relationships… item and the panel can never disagree.
  - Document-scope authoring + the NEIGHBOURHOOD rule (added same day, after the
    owner pointed out that a tab and its panel are two PLACED instances, so
    nothing was testable without it). Relationships now render on the canvas for
    any layer with a role of its own. Targets come from the nearest enclosing
    GROUP and there is NO artboard fallback — owner call: an artboard fallback
    quietly reintroduces the long-list problem and makes the rule change with
    context, whereas "things you connect live in a group together" is one rule
    that always holds, and it is how the owner already works ("I put them in
    groups already because I don't want to accidentally move the tab titles away
    from the tab content"). An ungrouped selection gets an INSTRUCTION naming
    ⌘G, not an empty dropdown; already-authored links are kept and still export,
    and the note says so. Targets walk into groups but NOT into component
    instances, since a layer inside another component is not addressable from
    outside — its id is minted per instance at export. The picker annotates each
    target with its role ("Panel One — Tab Panel") so choosing is not guesswork.
  Real-world acceptance was initially blocked by FEAT-012 because the required
  tab → panel link crosses a component boundary and varies per placement. That
  path is now built, and the owner verified this bug's acceptance behavior on
  2026-07-27. Widening the picker globally remains explicitly not the fix.
- Repro/Detail: Owner report 2026-07-24. Editing a component categorized Tab
  Panel, EVERY layer inside it offers Labelled By and Described By — a decorative
  rectangle, a background group, any text layer.
- VERIFIED against WAI-ARIA 1.2 / MDN — 2026-07-24, EXTENDED 2026-07-24 (2nd session):
  1. ARIA roles do NOT inherit. Each element has its own role, explicit or
     implicit; nothing cascades to descendants. So deriving a layer's available
     relationship kinds from its CONTAINER's role has no basis in the spec.
  2. An unroled group/rectangle exports as `<div>`, whose implicit role is
     `generic`. MDN on the generic role: "Because the generic role is nameless,
     the aria-labelledby and aria-label attributes are prohibited," and
     aria-labelledby lists `generic` among the roles it is NOT supported on. So
     the offer is not merely noisy — the attribute is invalid there. The same
     sentence also prohibits `aria-roledescription` and
     `aria-brailleroledescription` on `generic`; EXP emits neither, so nothing to
     do there. https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Reference/Roles/generic_role
  3. None of EXP's curated roles are in the naming-prohibited list
     (caption, code, deletion, emphasis, generic, insertion, mark, paragraph,
     presentation/none, strong, subscript, suggestion, superscript, term, time),
     so every category EXP offers does support naming. Only the NO-ROLE case is
     the problem.
  4. tabpanel + aria-labelledby is CORRECT and expected — the WAI-APG tabs
     pattern labels the panel by its tab, and `SemanticHTMLContract` already
     lists `.labelledByRelationship` as a requirement for tabpanel. Do not
     remove it.
  5. CORRECTION — `aria-controls` IS global. This entry previously assumed it was
     not, and planned to enforce a supported-roles list. There is no such list to
     enforce. MDN: "The global `aria-controls` property…"; Associated roles:
     "Used in **ALL** roles."
     https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Reference/Attributes/aria-controls
  6. `aria-describedby` IS global and carries NO role prohibition. MDN: "The
     global `aria-describedby` attribute…"; Associated roles: "Used in **all**
     roles. Usable in all HTML elements as well."
     https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Reference/Attributes/aria-describedby
  7. CONSEQUENCE — the three kinds are NOT the same kind of problem, and the fix
     must not flatten them into one rule:
     - `labelledby` on an unroled layer is a CONFORMANCE violation. Authors MUST
       NOT set a prohibited property (WAI-ARIA 1.2 §5.2.5). Suppress the offer and
       never emit the attribute.
     - `describedby` and `controls` on an unroled layer are spec-VALID. They are
       merely pointless: a `generic` element is nameless and, per MDN, is exposed
       to accessibility APIs only "so that assistive technologies can gather
       certain properties such as layout and bounds" — so a description hung on it
       has no named thing to attach to, and `aria-controls` only means anything on
       an element a user can actually operate. Treat these as a QUALITY default
       (do not offer them on unroled layers, do not invent them) rather than as a
       prohibition. UI copy and fidelity issues MUST NOT call them invalid.
  NOT VERIFIED — stated explicitly so it is not mistaken for settled:
  - WAI-ARIA 1.2 §6.5 "Global States and Properties" was NOT read verbatim; the
    W3C TR fetch truncated before that section. The globality claims in 5 and 6
    rest on MDN, which cites https://w3c.github.io/aria/#aria-controls and
    #aria-describedby. Re-read the spec text before relying on this for any
    stricter rule than "do not offer by default."
  - No screen-reader behavior was tested. Whether VoiceOver/NVDA/JAWS actually
    announce a description on a generic div is an implementation question, not a
    spec one; nothing above depends on the answer.
  - MDN's generic-role line "If a global ARIA state and property is set, `generic`
    or `none` will be ignored, and the implicit role of the element will be used"
    was read but NOT resolved. It concerns an EXPLICITLY authored
    `role="generic"`/`role="none"`, and EXP emits neither. Do not build on it.
- Root cause / modeling gap: `availableRelationshipKinds` reads
  `document.model.source(for: sid)?.a11y.role` — the CONTAINER's role — and
  offers those kinds on every node in the source. But the exporter puts
  `source.a11y.role` on the element hosting the INSTANCE, so every layer inside a
  source is an unroled div. Meanwhile `relationshipControls` only renders in
  `.source` scope. Net effect: the kinds are offered exactly where they are
  invalid, and there is currently NO conformant place to author the component's
  own relationships, because the element that carries the role is the instance
  and that is not selectable from inside the component.
- Proposed fix: derive kinds from the node's OWN effective export role —
  a `.instance` node uses its source's role, any other layer has no role and so
  offers nothing — and give the component's own relationships a home (either
  author them on a placed instance in document scope, or add an explicit
  "component root" row in the source editor that stands for the instance
  element). Keep already-authored relationships visible and editable regardless,
  so nothing is stranded. Emit nothing for a layer with no role.
  Per finding 7, the SUPPRESSION reason differs by kind and the code should say
  so: `labelledby` is suppressed because it is prohibited, `describedby` and
  `controls` because they are meaningless on a nameless container. No
  supported-roles gate is needed for `aria-controls` — it is global (finding 5).
- Design constraint — RELATIONSHIP SCOPE ("neighborhood", not global). Owner
  call 2026-07-24: once a component can point at something outside itself, the
  target list must NOT be the whole document. Scope it to the nearest meaningful
  container — the enclosing artboard, or an enclosing group — because a real
  document with hundreds of components would otherwise produce novel-length
  dropdowns that are unusable for everyone and actively hostile with a screen
  reader or keyboard. This also matches the DOM reality: `aria-labelledby` and
  friends are id references resolved within a document, and EXP already reports
  an `unresolvedRelationship` fidelity issue when a target lands outside the
  exported artboard (`SemanticHTMLExporter.relationshipAttributes`) — so
  artboard-scoping the PICKER simply stops people authoring links the exporter
  is going to reject anyway.
  Today `relationshipTargets` collects from `relationshipSourceNodes`, i.e. the
  current source's own children, so the scaling problem does not exist yet — it
  appears the moment this fix opens targets up. Decide the scope rule in the
  SAME change, not after. Sketch: default to the enclosing artboard, narrow to
  the enclosing group when one exists, show the container's name in the picker
  so the boundary is visible, and keep an already-authored out-of-scope target
  selectable-but-flagged rather than silently dropping it.
- Acceptance: no relationship kind is offered on a layer that would export as an
  unroled div; a Tab Panel component can still be labelled by its tab; existing
  authored relationships survive and remain editable; the semantic export emits
  no `aria-labelledby` on a `generic` host; the target picker is scoped to the
  artboard/group rather than the document and stays usable at 100+ components;
  headless check covers each case.

### FEAT-011 — Plain-language relationship UI (translate ARIA out of the interface)
- Type: feature
- Priority: P2
- Area: inspector · a11y · content design
- Status: WRITTEN 2026-07-24, NOT YET BUILT OR OWNER-VERIFIED. Shipped inside the
  BUG-008 change as sequenced. `NodeRelationship.Kind.friendlyLabel(for:)` and
  `.friendlyHelp(for:)` carry the wording; `label` is now documented as
  internal-only (undo action names, diagnostics) and no longer reaches the
  inspector. Owner chose HELP-TIP-ONLY for the raw attribute: the plain-language
  phrase is the primary label, the literal `aria-*` name appears in the hover tip
  and the VoiceOver hint, and nothing extra is added to the row — which also
  keeps FEAT-010's cramped-panel problem from getting worse.
  Wording that shipped: Tab ▸ controls = "Opens this panel"; button/link/menuitem/
  option ▸ controls = "Opens or changes"; otherwise "Operates". Tab Panel ▸
  labelledby = "Named by its tab"; dialog/alertdialog = "Named by its title";
  otherwise "Gets its name from". describedby = "Helper or error text" on form
  controls, "Extra explanation" elsewhere.
  STILL TO REVIEW: the wording has NOT been read back against every WAI-APG
  pattern — only tab/tabpanel and the dialog naming case were checked, since
  those are the ones a rename could make factually wrong. The generic phrasings
  are content-design judgment, not verified spec claims.
- Repro/Detail: Owner insight 2026-07-24, and it is a good one: "I was confusing
  labelled by as only being relevant to form elements... I bet others would be
  confused as well." Working inside tab-one's content, the expected mental model
  was "link/connect this to the tab nav item" — not "labelled by." The owner has
  a11y training and still finds Described By hard to hold onto; most designers do
  not think in ARIA vocabulary at all.
- Detail: keep the functionality and the emitted attributes exactly as they are —
  change only the words, and make them context-aware. The ARIA token should be
  secondary/on-hover for people who want it, not the primary label.
  Sketch, to be refined:
  - `controls` on a Tab → "Opens this panel" (aria-controls)
  - `labelledby` on a Tab Panel → "Named by its tab" (aria-labelledby)
  - `labelledby` generally → "Gets its name from…" with the hint that the target
    is the visible text a screen reader will read as this thing's name
  - `describedby` → "Extra explanation" / "Has helper text…" — framed as the
    hint, error, or helper text read AFTER the name, which is the part that is
    hard to remember
  Show the role-specific phrasing when the role is known, fall back to the
  generic phrasing otherwise, and keep the literal attribute in the help tip so
  the mapping stays learnable rather than hidden.
- Acceptance: no ARIA attribute name appears as a primary label; each phrasing is
  correct for the role in context; the underlying attribute is discoverable on
  hover and in the handoff; VoiceOver reads the friendly label; wording reviewed
  against the WAI-APG pattern for each role so nothing is renamed into being
  wrong.
- Note on standards language: the ADA does not specify ARIA. The applicable
  technical standards are WCAG 2.1 AA (DOJ Title II rule, Section 508,
  EN 301 549) plus WAI-ARIA 1.2 and ARIA in HTML. Use those names in docs and
  UI copy rather than "ADA compliant."
- SEQUENCING — ships WITH the component-classification work, not after it. Owner
  call 2026-07-24: roll this in as soon as work starts on adjusting and verifying
  the component classification / role authoring surfaces (BUG-008 and the
  remaining Chunk I containment items). The reasoning is sound — those changes
  are already rewriting when and where each relationship kind is offered, so
  rewording them at the same time costs almost nothing extra, whereas doing it
  later means touching the same views twice and shipping one release where the
  offers are correct but still unreadable to most designers. Treat FEAT-011 as
  part of that work's definition of done, not as a follow-up ticket.

### FEAT-009 — Per-corner radius ("Advanced") for Auto Padding / Auto Layout groups
- Type: feature
- Priority: P2
- Area: model · inspector · canvas · export
- Status: open
- Repro/Detail: Owner request 2026-07-24. An auto-padding group draws its own
  background with a single `cornerRadius`. Rectangles already support four
  independent corners; auto groups should match, behind the same "Advanced"
  disclosure so the simple case stays one field.
- Hypothesis: mostly mirroring work — the pattern already exists end to end.
  `RectangleShape` has `cornerRadii: CornerRadii?` plus
  `effectiveRadii { cornerRadii ?? CornerRadii(all: cornerRadius) }`, and the
  inspector already has the disclosure (`cornersAdvancedOpen`, the `cornerField`
  helper, and the "Matching all four snaps back to the single Corner field."
  hint) in `shapeControls`. Add the same optional field + `effectiveRadii` to
  `AutoPadding` with a tolerant decode, then update the draw and emit sites:
  `CanvasView.swift:~4892` (`pad.cornerRadius * z`), `PanelDock.swift:~793`
  (component preview thumbnail), `ExportRenderer.swift:~284/291` (SVG `rx`, plus
  the inset stroke radius), and `SemanticHTMLExporter.swift:~1025`
  (`border-radius`). Reuse whatever rounded-path builder the rectangle per-corner
  drawing already uses rather than writing a second one.
  `AutoLayoutEngine.swift:~210` (`pad.cornerRadius = style.corner`) converts a
  background child into auto padding — decide there whether a per-corner
  rectangle promotes its four radii.
- Acceptance: four corners settable and independent; matching all four collapses
  back to the single field; canvas, component preview, SVG, and semantic HTML all
  render the same shape; old documents decode unchanged; one undo step per edit;
  fields keyboard reachable with correct VoiceOver labels.

### FEAT-010 — Inspector/panel responsiveness pass + user type-size preference
- Type: feature
- Priority: P2
- Area: chrome · inspector · a11y
- Status: **done — shared polish pass owner-verified 2026-08-21; first
  effects-field slice owner-verified 2026-08-16.**
- Repro/Detail: Owner report 2026-07-24 with screenshot. At the right panel's
  DEFAULT width, the left edge of most rows sits very close to — or slightly
  clipped by — the panel edge, and the right scrollbar crowds the controls.
  Wanted: panel layouts that flex instead of assuming one width. Controls should
  be able to drop below their label when horizontal space runs out rather than
  truncating, sections should reflow at narrow widths, and the whole thing needs
  to survive a user-chosen larger UI type size.
- Hypothesis: the rows are built as fixed `HStack`s with fixed-width `TextField`s
  (`.frame(width: 56)` is used throughout), so they cannot reflow. Likely shape:
  a shared adaptive row container that switches label-beside → label-above under
  a width threshold via `ViewThatFits` or a measured container width, plus
  auditing the fixed frames into min/ideal widths. The type-size preference
  should ride Dynamic Type / the existing `EXPType` scale rather than a bespoke
  multiplier, so it composes with the system accessibility settings EXP already
  promises to follow. Reserve gutter space for the scrollbar.
- Acceptance: no clipped labels or controls at the default panel width; panels
  remain usable when narrowed and when the user raises the UI type size; nothing
  truncates without an accessible full value; VoiceOver order stays correct in
  both the beside and above arrangements; verified in light/dark and increased
  contrast.
- Fit: owner suggested "another polish version soonish" — sequence it as its own
  polish release alongside the F2 panel/tool-discoverability pass rather than
  squeezing it into v2.1.

- **OWNER ADDITIONS 2026-08-11 — scope grows from "responsiveness" to
  "responsiveness + hierarchy."** Owner: *"I want to take a close look at the
  properties panel and get some polish and clearer hierarchy."* Three specifics:
  1. **The Flip buttons "always just get lost."** A discoverability failure, not a
     spacing one — flip is a common action with no visual weight and no obvious
     group to belong to. Likely wants to sit with the other transform controls
     (rotate, dimensions) rather than floating among unrelated rows.
  2. **"A lot of elements/buttons/alignment that doesn't feel intentional."** The
     panel has accumulated per-section layouts. The fix is a small set of shared row
     patterns applied everywhere, which is also the prerequisite for FEAT-023's
     effect-row rework and FEAT-035's dropdown treatment — do those three together
     so the panel is decided once rather than three times.
  3. **Multi-column controls crush their labels** — "the text ends up only having
     about 2 letters of space so breaks out into 3 or more lines." Concrete evidence
     for the fixed-`HStack`/`.frame(width: 56)` hypothesis already recorded above,
     and the strongest argument for the label-beside → label-above reflow.
- Related entries to land in the same pass: FEAT-035 (dropdown definition +
  §1.4.11 contrast), FEAT-036 (case control as icons, which also reclaims width),
  FEAT-037 (tooltip audit), FEAT-023 (effect row layout), and the already-logged
  ROADMAP refinement-backlog item *"Inspector 'Align' row layout — the Align-to
  dropdown sits too close to the distribute buttons; owner mis-clicked distribute
  when reaching for the dropdown."* That mis-click is the same class of problem as
  the Duplicate/Delete adjacency in FEAT-023: destructive or hard-to-undo controls
  placed next to the ones people reach for constantly.

- **FIRST SLICE 2026-08-16 — Noise/Dissolve Advanced fields.** Owner supplied a
  concrete screenshot: Frequency, Octaves, and Seed stayed at a fixed 40pt even when
  the panel widened, labels sat beside the fields, and Frequency displayed at most
  two decimals despite meaningful 0.001 differences. Replaced that one-off row with
  two flexible columns and labels above the controls; fields now consume the panel's
  available width, use full labels, and use monospaced digits. Frequency displays
  three decimals, accepts values down to 0.001, steps by 0.01, and Option-steps by
  0.001. Visible labels are hidden from accessibility because each field retains its
  full programmatic label, preventing duplicate VoiceOver stops. Full app Debug build
  passed; the owner confirmed the revised fields work much better. This does NOT close
  FEAT-010: the shared adaptive-row pattern, remaining
  inspector sections, type-size preference, appearance/contrast pass, and owner visual
  verification of those later slices remain.

- **SHARED PASS 2026-08-21.** Settings ▸ General now provides Compact, Standard,
  and Large interface type, applied consistently to docked panels, floating trays,
  the source editor, and Settings through SwiftUI dynamic type. Shared fields,
  segmented controls, and compact buttons scale with that choice. Flip is now a
  visible Horizontal / Vertical pair in the transform hierarchy. Shadow labels no
  longer collapse into abbreviations, the Align-to and Distribute groups remain
  spatially distinct, and FEAT-023/035/036/037/038 use the same shared control
  patterns instead of adding one-offs. The owner verified narrow widths, all three
  type sizes, light/dark, Increase Contrast, and VoiceOver order.

### FEAT-008 — Font picker: remember scroll position, plus "Fonts used" and "Recent fonts" filters
- Type: feature
- Priority: P1 for v2.3 discovery/design
- Area: inspector · chrome
- Status: **done — fully owner-verified 2026-08-21, including VoiceOver**
- Repro/Detail: Owner request 2026-07-24. Changing a font means scrolling the
  whole font list from the top every single time. Designers routinely have
  hundreds of families installed, so the list is long and the same handful of
  faces get used over and over.
  Wanted: (a) the picker reopens where it was — scrolled to, and highlighting,
  the currently applied font rather than the top of the list; (b) a **Fonts
  used** filter scoped to the current document, built from the faces actually
  referenced by text nodes, component sources, and type styles; (c) a **Recent
  fonts** filter persisted across sessions (app-level, not per document).
  ADDED 2026-07-24 after using (a): (d) **type-to-jump** — start typing a name and
  the list jumps to it, the behaviour every long list in macOS has and the thing
  that makes a few hundred families genuinely navigable; (e) a **search/filter
  field** over the same list. Owner's words: "some ideas for the improvements for
  v2.2 including some filtering, or start typing to jump to a font." Both belong on
  `FontFamilyPicker` alongside (b) and (c) — four filters over ONE list, not four
  controls. Owner also reported the shorter popover "scrolls better with more
  control" than the old full-length menu, so the fixed 320pt height is a deliberate
  keeper rather than an arbitrary number.
- Hypothesis: (a) is the cheap, high-value half and could ship on its own —
  scroll-to-current-selection on open is a small change and fixes the daily
  irritation. (b) reuses the same document walk the Design Language panel and
  the handoff type audit already do to enumerate faces in use. (c) needs a small
  UserDefaults MRU list, capped, deduped by family.
- Owner scope decision 2026-08-05: do not implement (b)–(e) for v2.2. The owner
  has additional font-filter ideas and wants to mock up and test the combined
  design before deciding whether it works or whether every mechanism should ship.
  v2.3 therefore begins with discovery/design, not with the four remaining ideas
  treated as an already-approved UI specification.
- Acceptance: opening the picker lands on the current font with it visibly
  marked; the two filters narrow the list and are reachable by keyboard with
  correct VoiceOver labels; filter choice persists sensibly between openings;
  an empty "Fonts used" or "Recent" state explains itself rather than showing a
  blank list. **Revalidate this acceptance contract against the owner's v2.3
  mockups before implementation; it is not frozen.**
- Fit: first-priority **v2.3 discovery/design**, followed by implementation only
  after the filter/navigation model is tested. It is not a v2.2 release gate.
- **(a) PULLED FORWARD into v2.1, WRITTEN 2026-07-24, needs owner build.** Owner
  call: keep v2.1 focused but take the cheap relief now.
  Implemented as `UI/FontFamilyPicker.swift`, a shared popover replacing the two
  `Menu`-of-`Button` call sites in the inspector (single text, and the
  multi-selection Type section).
  WHY NOT A PLAIN `Picker`: it would give scroll-to-selection and a checkmark for
  free, but menu items in a SwiftUI `Picker` do not reliably render in a custom
  face, and seeing each family SET IN ITSELF is most of the value of a typeface
  list in a design tool. Trading that away for free scrolling would have been a
  quiet regression in exactly the thing the control is for. A popover +
  `ScrollViewReader` keeps the previews AND scrolls.
  Details worth keeping: scrolls with `.center` anchor rather than `.top`, so the
  neighbouring faces are visible — picking a sibling face is the common next move;
  the checkmark column is reserved whether or not it is ticked, so names stay
  aligned and the list does not jitter; a multi-selection passes a fixed label and
  ticks nothing, which is honest about there being no single value; the System row
  is keyed on an EMPTY family, matching the model's meaning of `fontName == ""`
  ("no face chosen") rather than inventing a family called System.
  This is also where (b)–(e) belong — "Fonts used", "Recent fonts", type-to-jump
  and search are all filters/navigation over THIS list, not separate controls.
  BUG FIXED SAME DAY, owner-reported: on first open the rows ABOVE the selected
  font rendered as blank space until a real scroll brought them in. A `LazyVStack`
  only builds the rows it believes are visible, and the `onAppear` scroll ran
  before the popover had been laid out — so the surrounding rows were never built.
  Now scrolled twice: once immediately, then again via `DispatchQueue.main.async`
  after layout, when the visible window is known. The comment says why, because a
  duplicated-looking call is exactly what a future reader would "clean up."

- **OWNER MOCKUP/SPEC PASS DELIVERED 2026-08-11 — this is the discovery evidence
  v2.3 was waiting on.** The owner described the intended control directly, which
  resolves most of the open information-architecture question:
  - **Type-to-jump** confirmed as wanted — (d) above.
  - **A small left-hand filter rail, collapsible/hideable**, running down the side of
    the picker. This is the answer to "four filters over ONE list, not four
    controls": the rail is the single home for every filter, and the list to its
    right is the single result surface.
  - Rail contents: **font CATEGORY filters** (sans serif, serif, handwriting, etc.)
    — a NEW mechanism not previously in (a)–(e); **Fonts Used**, scoped to the
    current document, as one filter option among the categories rather than a
    separate control; and **Recent**, explicitly described as "more across the
    latest, not dependent on the document itself" — i.e. app-level MRU, confirming
    the (c) design.
  - So the shipped set is: scroll-to-current (done), type-to-jump, a hideable
    category/scope rail, Fonts Used, and Recent. A separate always-visible search
    field is NOT clearly needed if type-to-jump works well — treat (e) as optional
    and decide from use, not by default.
- Open questions this spec does NOT settle, to resolve before coding:
  1. **Where do categories come from?** macOS exposes font traits via
     `NSFontDescriptor` (`NSFontDescriptor.SymbolicTraits` has serif/monospace-ish
     signals) and `kCTFontTraitsAttribute`, but there is no reliable system-provided
     "handwriting" or "display" classification — the PANOSE/`sFamilyClass` data in
     the OS/2 table is often absent or wrong in real fonts. So category filtering
     will be partly heuristic. Verify what the macOS 26 SDK actually exposes before
     promising categories, and decide what an unclassifiable font does (an "Other"
     bucket is honest; silently hiding it is not).
  2. **Are rail filters exclusive or additive?** Category + Fonts Used together
     could mean intersection or replacement. Recommend single-select scopes
     (Recent / Fonts Used / All) with categories filtering within the chosen scope.
  3. **Rail keyboard model.** The rail is a second focusable region inside a
     popover, so Tab order, arrow-key behavior within the rail, and how focus moves
     to the list all need specifying. Per the APG, this is either a listbox-like
     single-select or a set of toggle buttons — pick one and follow that pattern
     rather than inventing. Verify against the ARIA Authoring Practices Guide and
     record the citation, per WORKING-AGREEMENT.
  4. **What does the hidden state remember?** If the rail is collapsed while a
     filter is active, the active filter must stay visible somewhere or the list
     silently lies about being complete.
  5. **Empty states** for each rail item (no recents yet; document uses one font;
     no fonts in this category), each explaining itself.
- Accessibility contract to write before implementation (not after): the rail's
  accessible name and role, per-item names, the announcement when filtering changes
  the result count, and the fact that no filter may be reachable by pointer only.

- **IMPLEMENTED 2026-08-21; UI REVISED FROM OWNER MOCKUPS SAME DAY.** The first
  owner run proved the data behavior but exposed the wrong visual/interaction shape:
  two labelled radio groups wrapped badly in the narrow rail, and combining scope +
  category made it too easy to facet-filter every font away. `FontFamilyPicker`
  still keeps one previewed list and the proven double scroll-to-current behavior,
  but the rail is now ONE mutually-exclusive set: All Fonts / Fonts Used / Recent /
  Sans Serif / Serif / Monospaced / Handwriting / Display / Symbol / Other. Picking
  any item replaces the prior filter; there is no second active set to disable or
  intersect. The icon-only toggle buttons carry count badges, hover states and full
  tooltips; a native radio-group accessibility representation supplies stable full
  names and exclusive checked state to VoiceOver. Filter and rail visibility persist.
  The show/hide switch and visible `Filters` label live in the leading header cell,
  immediately above the rail.
  - **Classification:** uses the macOS 26 SDK's
    `NSFontDescriptor.SymbolicTraits` family-class mask plus `monoSpace`; serif
    classes combine under Serif, Scripts map to Handwriting, Ornamentals to Display,
    Symbolic to Symbol, and missing/unknown metadata remains visible under Other.
    Classifications are cached once per process. The UI explicitly says these are
    the metadata supplied to macOS; no family-name guess is presented as fact.
  - **Fonts Used:** computed only when the popover opens (not during routine
    inspector redraws), across every canvas page, component source, state/instance
    typography override, and saved type style. It filters the installed catalog,
    so unavailable document fonts are not falsely offered as selectable choices.
  - **Recent:** app-level `UserDefaults` MRU, capped at 12 and deduped by family;
    System participates using the model's real empty-string identity.
  - **Search:** the ambiguous "Type a font name to jump" help string is now a real,
    live `Search` field. It filters case/diacritic-insensitively as the owner types,
    has a clear action, and its text column aligns with the font names below whenever
    the filter rail is visible. While the popover is open, the app-wide tool-letter
    monitor yields so A/F/T/etc. reach Search instead of switching canvas tools.
  - **Adaptive height (owner follow-up after approving the cleaner UI):** the fixed
    356-point popover was still unnecessarily short on a large display. It now uses
    62% of the active window's screen `visibleFrame` (menu bar and Dock excluded),
    bounded to 480–780 points. This gives smaller screens a useful minimum, lets a
    large monitor show many more families, and avoids a nearly full-screen picker.
  - **Empty/accessibility states:** distinct explanatory copy for no recents, no
    document fonts, and no category match; explicit rail/scope/category/list names;
    current-family selected state; debounced result-count announcements after search
    and filter changes; every filter and collapse action is keyboard reachable.
  - **Verified contract sources:** W3C APG Radio Group Pattern
    (`https://www.w3.org/WAI/ARIA/apg/patterns/radio/`) specifies one checked item,
    Tab into/out of the group, arrow-key movement/change, and group/item names.
    Apple's Segmented Controls HIG
    (`https://developer.apple.com/design/human-interface-guidelines/segmented-controls`)
    confirms a single choice for closely related options affecting one view; the
    Search Fields HIG (`https://developer.apple.com/design/human-interface-guidelines/search-fields`)
    recommends live search and an inline field above the list it filters. Apple's `NSFontDescriptor`
    documentation (`https://developer.apple.com/documentation/appkit/nsfontdescriptor`)
    documents symbolic traits/family classes; the installed Xcode 26.5 SDK headers
    were also checked directly for the exact classes used.
  - **Owner verification 2026-08-21:** the exclusive icon-filter UI is "much
    cleaner," and the subsequent display-aware height is verified as much better.
    Live VoiceOver announcements/focus order remain unverified. A full app +
    thumbnail + helper Debug build succeeds.

### FEAT-046 — Type tool remembers the last font, size, and color
- Type: feature
- Priority: P1
- Area: typography · canvas
- Status: **done — owner verified 2026-08-21**
- Repro/Detail: every new point-text or dragged text box previously restarted at
  System 16 pt black, even immediately after editing another treatment. The owner
  asked for the next text item to start with the last font/size/color used.
- Contract implemented: `AppState.rememberedTextStyle` is an app-wide tool default,
  persisted in `UserDefaults` and synchronized across document windows. Entering
  inline editing, moving the caret/selection onto a concrete rich-text run, changing
  font/size/color in the inspector, using whole-text formatting, or applying a saved
  Type Style updates the concrete values. Mixed rich-text selections update only
  the components that are unambiguous, so "Multiple" never erases a useful default.
  Point text and dragged paragraph boxes share the same creation helper. If a saved
  PostScript face is no longer installed, creation safely falls back to System;
  document files do not store this preference.
- Acceptance: edit text to a distinctive installed face, fractional size, and color;
  create both point text and a dragged text box and confirm both inherit all three.
  Repeat after switching documents and relaunching the app. Confirm a mixed-style
  selection does not reset the remembered values, and an unavailable font falls
  back to System rather than creating a broken face reference.
- Verification: full Debug build (app + thumbnail + helper) succeeds; the owner
  verified the resulting text-tool memory behavior 2026-08-21.

### FEAT-001 — Color: saved / recent colors + palettes (doc-linked, import/export)
- Type: feature
- Priority: P2
- Area: color · model
- Status: in progress (Session 167) — document model + panel save/pick/recents landed; import/export (FEAT-007/18e) still open
- Repro/Detail: Recent-colors strip and a saved-swatches area in the color popover;
  named colors that live ON the document (so they travel with the file) AND can be
  exported/imported to share between documents. This is the first slice of ROADMAP
  Phase 18's Design Language model: document-local assets, not app chrome tokens.
- Hypothesis: add a document-level `DesignLanguage` or `colorLibrary` with
  `recentPaints` plus named entries (`id`, `name`, `status: candidate/official/
  archived`, `value`, provenance). Backward-compatible decode. Surface a minimal
  save/pick flow in `ColorPopover` first; graduate to the Design Language panel in
  FEAT-006. Generation can reuse `ColorMath` (OKLCH) for perceptually-even ramps.
- Acceptance: pick from recents/saved; save and rename a swatch; mark candidate vs.
  official; export a small JSON from doc A and import into doc B; entries persist in
  the `.design` file.

### FEAT-002 — Color-mode-specific picker behavior
- Type: feature
- Priority: P3
- Area: color
- Status: in progress (Session 166) — HSB/HSL/OKLCH mode-aware controls + sRGB gamut warning landed; wide-gamut ColorValue not pursued
- Repro/Detail: Phase 8 can type/copy HSL/LCH/OKLCH, but the visual editor is still
  essentially HSB/SV + hue/alpha with sRGB storage. Owner wants truly model-aware
  authoring, especially HSL and OKLCH, with honest gamut handling.
- Hypothesis: redesign `ColorPopover` around editing modes. HSB/HSL/OKLCH each get
  controls that match their axes; OKLCH should also drive ramp/adjustment helpers.
  Before adding Display-P3, decide whether the model stays sRGB-with-warnings or
  grows a richer `ColorValue(colorSpace:components:)`.
- Acceptance: switching mode changes the picker's controls, not just its code field;
  OKLCH edits can warn when clamped to sRGB; copied values match the selected mode.

### FEAT-003 — In-app bug/feedback reporter (agent-ingestible)
- Type: feature
- Priority: P2
- Area: infra · chrome
- Status: open
- Repro/Detail: A Help ▸ "Report an Issue / Idea…" that opens a small form (title,
  type: bug/idea, description, optional screenshot) and auto-attaches CONTEXT:
  app version, macOS version, current tool, selection summary, doc stats (artboards/
  nodes/sources), and the last few undo action names. Writes a structured record.
- Hypothesis: capture to a Markdown/JSON file matching THIS backlog's entry format
  (so an agent can drop it straight into Bugs), saved to a chosen folder and/or opened
  as a prefilled GitHub issue / mail draft. Keep the payload PII-free (no doc content,
  just stats) unless the user opts to attach the file.
- Acceptance: one action produces a ready-to-triage entry with reproducible context;
  agents can read the folder and pick items up.

### FEAT-005 — Color contrast checker (WCAG-first, APCA advisory)
- Type: feature
- Priority: P2
- Area: color · inspector · a11y
- Status: in progress (Session 166) — ContrastMath (WCAG 2.x) + picker contrast strip landed; APCA and panel comparisons pending
- Repro/Detail: Designers need to check foreground/background contrast while choosing
  colors, saving library entries, and editing text/fills. This should be part of the
  color workflow, not a separate external chore.
- Hypothesis: add pure `ContrastMath` beside `ColorMath`: WCAG 2.x relative
  luminance/contrast ratio, AA/AAA thresholds for normal text, large text, and
  non-text UI components. Flatten alpha colors over the relevant artboard/background.
  APCA can appear as advisory/exploratory if useful, but not as the primary pass/fail.
- Acceptance: picker/panel can compare two colors, selected text vs. background, and
  library swatch pairs; labels are clear; suggestions can adjust OKLCH lightness to
  reach AA without silently changing the document.

### FEAT-006 — Design Language panel (colors + gradients first)
- Type: feature
- Priority: P2
- Area: color · chrome · model
- Status: in progress (Session 167) — panel live with sections + apply/save/promote/rename/copy; in-place value edit, reveal-uses, and menu-bar command pending
- Repro/Detail: The reserved Color panel should grow into a document-local "Design
  Language" panel, similar in spirit to Components/library panels: saved colors,
  gradients, candidates/maybes, official entries, and later type/spacing/effects.
- Hypothesis: add `PanelID.designLanguage` (or rename the reserved Color panel) using
  the existing host-agnostic panel pattern. Sections: Official Colors, Candidate
  Colors, Gradients, Recents. Actions: apply to selection, rename/edit, promote,
  archive, copy values, import/export, reveal uses.
- Acceptance: panel works docked/floating, reflects the document model live, and lets
  the owner move a candidate color/gradient into the official list.

### FEAT-007 — Palette inspiration/import providers
- Type: feature
- Priority: P3
- Area: color · import
- Status: in progress (Session 169) — import + local generators done (EXP JSON / CSS / paste / OKLCH ramp / harmonies / accessible pair); image extraction + remote providers still open
- Repro/Detail: Owner wants to browse/import palette inspiration from places like
  Adobe Color, Coolors, RandomA11y, and Figma palettes, with an easy way to add
  options to the document as candidates or official entries.
- Hypothesis: build a provider/import framework before any service-specific UI. Local
  providers first: OKLCH ramps, harmonies, accessible pairs, image extraction. Remote
  or web sources should use documented APIs, user-pasted URLs, or exported files only;
  avoid scraping private/undocumented endpoints. Research snapshot lives in ROADMAP
  Phase 18f.
- Acceptance: paste/import a palette representation into the document as candidates;
  local generation produces usable options; each imported option keeps a visible source
  label/provenance.

---

## ⚡ Performance

### PERF-001 — Large / complex document performance (standing epic)
- Type: perf
- Priority: P2 (ongoing)
- Area: perf · canvas · model
- Status: open
- Repro/Detail: Keep interaction smooth (pan/zoom/drag ~60fps, fast open/save) as
  documents grow — many artboards, deep groups, many component instances, heavy paths.
- Hypothesis / levers: profile with Instruments (Time Profiler + Core Animation) on a
  stress doc; known areas — the CPU Core-Graphics canvas redraw, instance re-resolve
  cache (see the `exp-canvas-perf` memory note: culling + `resolveGeneration` invariants),
  background-blur readback (already deferred during gestures), SVG export walk. Possible
  moves: tighter dirty-rect invalidation, cache laid-out instances harder, move blur/
  compositing to a GPU/Metal layer (its own phase, see ROADMAP 16.5).
- Acceptance: a repeatable stress-test doc + before/after frame-time numbers; no
  interaction regressions.

### PERF-002 — Blend/opacity fidelity while dragging (conditional true-composite mode)
- Type: perf · feature
- Priority: P2
- Area: canvas · perf
- Status: needs-verify (Session 162 — implemented as the per-gesture TRUE/FAST
  decision in `CanvasNSView.shouldTrueCompositeDrag`: dragged subtree uses a
  non-normal blend mode AND `fullFrameEMA` (always-on rolling full-render cost)
  fits the budget from the user's performance mode → full live render for the
  gesture; else fast blit. The cheaper "re-render only the ABOVE region" middle
  option is NOT built — revisit if TRUE mode's budgets feel too conservative.)
- Repro/Detail: With the Session 161i drag-overlay blit, a shape with a blend
  mode (difference/overlay/…) reads as its plain color against anything baked
  into the ABOVE snapshot layer while it's being moved — it only composites
  truly against content BELOW it, and snaps to the correct look on mouseUp.
  Owner wants design-truth kept while moving when the doc can afford it.
- Hypothesis: conditional fidelity. During a drag, choose per-gesture between
  (a) TRUE mode — full live render every tick (the pre-161i path, correct
  compositing) and (b) FAST mode — the current below/above blit. Pick TRUE
  when the gesture is cheap enough: e.g. recent full-frame cost < ~20ms, or
  visible node count under a threshold, or the dragged node has a non-normal
  blend mode AND the scene is small; else FAST. The measured `frame` perf
  stats already exist to drive the decision. Cheaper middle option worth
  trying first: when ANY dragged node has a non-normal blend mode, re-render
  only the ABOVE layer's intersecting region live instead of blitting it.
- Acceptance: moving a difference/overlay shape over other content keeps its
  true composite on small/medium docs; huge docs degrade gracefully to FAST
  with no beachball; no regression to the 1.5–3.6ms drag frames in FAST mode.

### PERF-003 — Panning refinements (bigger/smarter snapshot)
- Type: perf
- Priority: P3
- Area: canvas · perf
- Status: open (partial — halo size + settle delay are now user-tuned via
  PERF-004; adaptive/directional halo and tiled snapshots still open)
- Repro/Detail: 161j's 25% halo + containment recapture works, but long fast
  pans still hit periodic ~30–80ms recaptures, and the settle render redraws
  everything. Ideas queue: adaptive halo (grow toward pan direction/velocity),
  tile-based snapshot (recapture only newly exposed tiles), reuse the drag
  blit's below/above machinery for partial invalidation.
- Acceptance: flick-panning a huge doc shows no blank edges AND no visible
  hitch; Testing Mode shows recapture cost amortized under one frame.

### PERF-004 — User-facing "Speed ↔ Detail" preference (Photoshop memory dial, humane edition)
- Type: feature
- Priority: P3
- Area: chrome · perf
- Status: needs-verify (Session 162 — Settings ▸ Canvas ▸ Performance:
  EXPSegmented "Speed focus / Balanced / Detail focus", persisted via the
  synced-prefs pattern (`AppState.CanvasPerformanceMode`,
  `exp.pref.performanceMode`). Drives: TRUE-drag budget 0/18/40ms, pan halo
  0.15/0.25/0.40, settle delay 0.12/0.08/0.05s. A11y label + hint on the
  control; plain-language footnote.)
- Repro/Detail: Owner idea: a single friendly setting (Settings ▸ Canvas) —
  a slider or segmented control from "Speed focus" to "Design detail focus" —
  instead of Photoshop's raw memory-% dial. It would set the thresholds used
  by PERF-002's conditional fidelity (and possibly halo size, mip cache
  budget, settle delay). Defaults = current behavior ("balanced").
- Hypothesis: implement AFTER PERF-002 proves out the thresholds; the setting
  is just exposing those constants. Follow the command-coverage rule for any
  user-facing control, and persist via the existing settings store.
- Acceptance: moving the control observably trades drag/pan fidelity against
  frame cost, survives relaunch, is fully keyboard/VoiceOver accessible.

### PERF-005 — Ruler pointer markers force a full canvas redraw per mouse move
- Type: perf
- Priority: P2
- Area: canvas · perf
- Status: open
- Repro/Detail: With rulers shown, `mouseMoved` sets `needsDisplay = true` to
  update the two accent pointer lines — a FULL scene render per mouse twitch.
  On the image-heavy doc (frames ~60–80ms) this reads as constant sluggishness
  even when nothing is being edited (visible in the 162c/d logs as repeated
  frame lines a few per second while idle).
- Hypothesis: the clean fix is a RETAINED last-frame snapshot: let the settle
  render also capture the scene (the machinery exists — capturePanZoomSnapshot),
  keep it while the transform + model are unchanged, and let ruler-marker /
  hover-only updates blit it + redraw rulers/chrome. This generalizes the pan
  blit into "idle repaints are blits," which also covers selection flashes.
  Cheaper stopgap: draw pointer markers in an NSView overlay above the canvas
  so marker moves never touch the canvas at all.
- Acceptance: with rulers on, waving the mouse over a heavy doc produces no
  full renders (Testing Mode shows no frame lines from pointer movement);
  markers still track exactly.

### PERF-006 — instCacheHit/Miss counters flat at 0 — verify they still track
- Type: perf
- Priority: P3 (someday)
- Area: perf
- Status: open
- Renumbered 2026-08-11: filed as PERF-005 on 2026-07-09, but that ID was
  already held by the ruler-redraw entry filed 2026-07-02. First claim wins;
  this entry moved to PERF-006. Old references in PERF-TODO T5 and the
  ROADMAP Progress Log were updated.
- Repro/Detail: Both Testing Mode counters read 0 (max 0) across every sample
  in the 2026-07-09 v1.2.1 logs. The doc under test may simply contain no
  component instances — but if the counters are ALSO flat on an
  instance-heavy doc, the instrumentation (or the instance cache itself) has
  silently stopped tracking. Owner is keeping an eye out.
- Hypothesis: Doc had no instances (benign) OR counter increments were lost in
  a refactor (check the instance-cache hit/miss paths against the
  resolveGeneration invariants).
- Acceptance: Testing Mode on an instance-heavy doc shows nonzero hits/misses;
  or confirmed benign and this entry closed with a note.

### FEAT-004 — Wider zoom-out range for "the wall is everything" workflows
- Type: feature
- Priority: P2
- Area: canvas
- Status: **done — owner verified 2026-08-16.**
- Repro/Detail: Owner's process spreads branding, color tests, archives, and
  inspiration "miles" apart on the wall and zooms way out for the big picture.
  `AppState.minZoom` is 5% (a pre-original-perf-work constant) — potentially
  too tight for that. Owner suggestion: if a floor is still needed for
  performance, tie it to the Speed↔Detail performance setting.
- Hypothesis: lower `minZoom` to ~1% (0.01) and verify: extreme-zoom-out
  full renders scale with total node count (culling can't help when all is
  visible) but the pan/zoom blit covers gestures; check `rulerStep`,
  `pxSnap` UX (1 screen px = 100 doc px at 1%), and the zoom slider's log
  mapping still feel right. Only add a performance-mode-dependent floor if
  measured frames actually justify one.
- Acceptance: owner can zoom out far enough to see their whole wall on real
  documents without the app feeling broken; zoom slider/field/menu items all
  respect the new range.
- Owner verification 2026-08-16: 1% zoom-out is working.

## 🛠 Infrastructure

### INFRA-003 — Orphaned doc comment above `sendCanvasAction`
- Type: chore
- Priority: P3
- Area: infra
- Status: open
- Repro/Detail: in MainWindow.swift a `/// Right panel — the Inspector. X/Y/W/H are
  two-way...` doc comment sits directly above the `sendCanvasAction` function, which it
  does not describe. It documents the Inspector view further down the file; something
  was inserted between them. Harmless, but it is actively misleading in a file this
  large, and `sendCanvasAction` is a function people now arrive at while debugging
  command routing.
- Acceptance: the comment sits on the declaration it describes, or is removed if that
  declaration already carries its own; no behavior change.

### INFRA-001 — One-command "approve → Roadmap → website" triage sync
- Type: feature (workflow/tooling)
- Priority: P2
- Area: infra
- Status: open
- Repro/Detail: When the owner approves a bug/idea (here, in GitHub Issues, or from
  the in-app reporter), it should be easy to PROMOTE it: move it out of the queue and
  onto the ROADMAP — and have the public roadmap on expdesign.app update automatically.
- Hypothesis / approach:
  1. **Canonical source:** keep a machine-readable roadmap the site can read —
     e.g. `docs/roadmap.json` (or a curated "public" subset) with `{id, title, area,
     status: planned|in-progress|shipped, blurb}`. ROADMAP.md stays the human plan;
     roadmap.json is the feed. (Or generate roadmap.json FROM tagged ROADMAP entries.)
  2. **Promote step:** an agent/skill "promote <ID>" that (a) moves the BACKLOG/issue
     item into ROADMAP.md as a phase/task, (b) appends/updates its entry in
     roadmap.json with `status`, (c) closes the GitHub issue with a "→ roadmap" label,
     (d) adds a ROADMAP Progress Log line.
  3. **Website sync:** if the site is static and reads `roadmap.json` from the repo,
     a push (or the site's build hook) republishes automatically; if the site fetches
     at runtime, point it at the raw file / a small endpoint. NEEDS: confirm the
     site's stack + how it currently sources roadmap/changelog content.
- Acceptance: approving an item + running one command updates ROADMAP.md, roadmap.json,
  and the GitHub issue in sync; the website reflects it on its next deploy with no
  hand-editing.

### INFRA-002 — Point the reporters at the real repo (small setup)
- Type: chore
- Priority: P1 (once the GitHub repo exists)
- Area: infra
- Status: open
- Detail: Set `FeedbackConfig.githubRepo = "owner/repo"` in `UI/Feedback.swift` and
  replace `OWNER/REPO` in `.github/ISSUE_TEMPLATE/config.yml`. Then the in-app "Send
  Feedback" opens a prefilled New Issue instead of the website fallback.

---

## Notes
- **v2.1 release alignment audit (2026-07-28):** every bug and bounded feature
  closed during the nested-component, pages, XD/Figma import, and Handoff cycle
  is marked `done` with owner verification. The website's generated known-issues
  feed therefore exposes BUG-004 as the only open item whose type is `bug`;
  longer-term feature and performance entries remain honestly open and are not
  release blockers unless promoted into a release gate.
- When an item ships, set `Status: done`, keep it here for one cycle for reference,
  then prune (or move a short line to ROADMAP's Progress Log).
- Big architectural features still get a real phase in ROADMAP.md; this list is for
  the smaller, pick-up-able queue.
