# EXP [design] — Architecture Map

A one-read orientation to how the app fits together, so a new session (human or
agent) can find the right file fast. Depth lives in the code + ROADMAP.md; this is
the map. **Guiding split:** SwiftUI for chrome, AppKit/Core Graphics for the canvas.

---

## 1. Big picture
```
                 ┌───────────────────────────── MainWindow (SwiftUI) ─────────────────────────────┐
                 │  headingBar (glass) · ToolsStrip · [ LeftDock · CanvasView · RightDock ]         │
                 └───────┬───────────────────────────────┬──────────────────────────────┬──────────┘
                         │ reads/writes                   │ hosts (NSViewRepresentable)  │ reads/writes
                   ┌─────▼─────┐                     ┌────▼─────────┐               ┌─────▼──────┐
                   │  AppState │  (per-window,       │ CanvasNSView │ (AppKit +      │ ExpDocument │
                   │ @Observable│   view/session)    │  Core Graphics│  hit-testing) │ (the model) │
                   └─────┬─────┘                     └────┬─────────┘               └─────┬──────┘
                         └───────────── both point at ────┴───── document.model ──────────┘
```
- **Chrome** (panels, inspector, heading, menus) = SwiftUI, styled by the design
  system (§7). **Canvas** (artboards, shapes, rulers, handles, selection) =
  hand-drawn Core Graphics in one big `NSView`, wrapped for SwiftUI.
- Everything hangs off the **document model** (§2). An instance is a *reference*
  to a source, never a copy — this was designed in from line one.

---

## 2. The data model — `Model/Document.swift` (value types, Codable, UI-free)
```
Document
 ├─ artboards: [Artboard]     // frame, name, background(Paint), notes, layoutGrids
 ├─ nodes: [Node]             // free layers on the "wall" + owned-by-artboard layers
 ├─ sources: [ComponentSource]// component definitions (children stored source-local)
 └─ guides                    // document-scope rulers/guides
Node            = id, name, frame, rotation, opacity, effects[], isVisible/Locked,
                  isMask/isMaskShape, content: NodeContent
NodeContent     = .rectangle | .ellipse | .polygon | .line | .path | .text
                  | .group([Node]) | .instance(ComponentInstance) | .image
ComponentInstance = sourceID + bounded overrides + per-layer visibility (references!)
```
- Pure structs, `Codable`, `Sendable`, **no UI imports** — so the same model powers
  the app AND the Thumbnail extension (§9).
- Ownership of a node by an artboard is *derived* from geometry (the "wall" rule),
  not stored — see `owningArtboard`.

## 3. Document + undo — `Model/ExpDocument.swift`
- `ExpDocument` is a SwiftUI **`ReferenceFileDocument`**; the file format is
  pretty-printed JSON with the `.design` extension (opens instantly; legacy
  `.exp` files still open for migration).
- **The single write funnel is `setModel(_:undoManager:actionName:)`** — every edit
  goes through it. It registers undo (so ⌘Z works), bumps a `resolveGeneration`
  (invalidates the instance cache, see §5), and marks the doc dirty (so Save works).
  *If you mutate the model anywhere, do it through `setModel`.*
- `DocumentGroup` in `EXP__design_App.swift` gives New/Open/Save/multi-window free.

## 4. Per-window state — `Model/AppState.swift` (`@Observable`)
- Holds **view/session** state, not document data: camera (zoom/pan), selection
  (`selectedNodeIDs`, artboards, anchors), the current `Tool`, workspace/panel
  layout, and the app-preference bridge (UserDefaults ⇄ Settings).
- Handed down with `.environment(app)` so **every panel is host-agnostic** — the
  same panel view works docked (main window) or floated (a tray window). That's why
  panels never assume where they live.

---

## 5. Canvas render pipeline — `Canvas/CanvasView.swift` (~6.5k lines, `CanvasNSView`)
- `CanvasView: NSViewRepresentable` wraps `CanvasNSView` (the AppKit view). One
  `draw(_:)` → `renderCanvas(into:)` paints the wall, artboards, every node, then
  chrome (rulers, guides, grids, selection handles, measurements).
- **Coordinate systems:** document space ⇄ view space via `docToView` / `viewToDoc`
  (zoom + pan). Hit-testing inverse-maps the cursor (incl. inverse-rotate for
  rotated shapes).
- **Performance invariants (see the `exp-canvas-perf` memory note):** off-screen
  culling + an instance-resolution cache keyed on `resolveGeneration` (bumped in
  `setModel`). Background-blur is deferred during pan/zoom (CPU CG can't readback per
  frame) and catches up on settle.
- **Scope-parameterized:** the same canvas renders `.document` OR `.source(id)` (the
  component editor). Tools, selection, and drawing all respect `scope`.
- **Interaction lives here:** `mouseDown/Dragged/Up`, `keyDown` (tool shortcuts),
  drag/marquee/resize/rotate, pen/point editing, and **all the `@objc` action
  methods** (§8).

## 6. Components (source/instance) & the source editor
- `createComponentAction` wraps a selection into a `ComponentSource` + replaces it
  with an `.instance`. `newEmptyComponentAction` makes an empty source. Instances
  render by *resolving* the source recursively (with overrides + per-layer
  visibility) — never copying.
- Double-click / Edit opens `UI/SourceEditorWindow.swift` — its own window hosting a
  `CanvasView(scope:.source)` sharing the document's undo manager, so edits update
  every instance live.

## 7. Design system (the Phase-17 layer) — `UI/`
- `DesignTokens.swift` — the single source of truth: `EXPColor` (appearance-resolving,
  overridable accent + `accentForeground` auto-contrast), `EXPType`/`Font` (SF Pro +
  bundled **SF Compact**, see `FontRegistration.swift`), `EXPMetric`, `EXPMotion`,
  `EXPGlass` values, and `EXPFieldStyle`.
- `GlassSurface.swift` — `expGlass(.thin/.medium/.thick)` (native macOS-26 Liquid
  Glass), `WindowGlassBackground` (behind-window, active-aware), `expTopEdge`, and
  `expTooltip` (keycap tooltip).
- `Controls.swift` — `EXPSegmented`, `EXPButtonStyle`. Inspector-specific controls
  (fields, `InspectorIconButton`) live in `MainWindow.swift`.
- Rule: **never hardcode a hex/font** in chrome — go through the tokens.

## 8. Command-coverage pattern (a hard convention — see CLAUDE.md)
Every user-facing action is wired ALL of these ways in the same change:
1. an `@objc` method on `CanvasNSView` (the single source of truth for the behavior),
2. a **menu-bar item** (in `EXP__design_App.swift`) with a shortcut where conventional,
3. a **right-click** item where contextual (canvas `menu(for:)`),
4. a `validateMenuItem(_:)` case (enable/disable),
5. an **Inspector control** when it has parameters.
Menu items dispatch through the responder chain via `NSApp.sendAction(_:to:nil…)`
(`send("selector:")`) so they reach the focused canvas — including a floating
source-editor window.

## 9. Two targets — app + **EXPThumbnail** (Quick Look thumbnails)
- `Document.swift`, `Paint.swift`, `AutoLayoutEngine.swift`, and the renderers
  (`PaintRender`, `EffectsRender`, `ExportRenderer`) are members of **BOTH** targets.
- ⚠ **Any new model/render file referenced by a shared file must also be added to
  EXPThumbnail's target membership**, or the extension won't build. (The project uses
  Xcode file-system-synchronized folders, so new files auto-join the *app* target;
  the extension uses explicit membership exceptions.)
- Chrome/UI files (DesignTokens, GlassSurface, Controls, all of `UI/`) are **app-only**.

## 10. Export — `Export/`
- `ExportRenderer` draws artboards to PNG (raster @2x), PDF (vector), and SVG (a
  hand-written emitter that walks the model — y-down like us). Shares the render
  helpers with the canvas so output matches on-screen. Notes ride the PDF/handoff path.

---

## Where do I put a new…?
| Kind of change | File(s) |
|---|---|
| New shape/primitive or model field | `Model/Document.swift` (+ EXPThumbnail membership), render in CanvasView + ExportRenderer |
| New tool | `Model/AppState.swift` (Tool enum) + `UI/ToolsStrip.swift` + `CanvasNSView` behavior/cursor/keyDown |
| New action/command | `CanvasNSView` @objc + menu (App) + right-click + `validateMenuItem` (+ inspector) |
| New inspector control | `UI/MainWindow.swift` (RightPanel) using DesignTokens / Controls |
| New chrome surface/panel | `UI/` — host-agnostic `View` reading AppState; style via tokens/glass |
| Color/gradient UI | `Color/ColorPopover.swift` / `PaintEditor.swift`; math in `ColorMath.swift` |
| A design token | `UI/DesignTokens.swift` only |

See **CLAUDE.md** (gotchas), **ROADMAP.md** (plan + Progress Log), **BACKLOG.md**
(the queue), **WORKING-AGREEMENT.md** (how we collaborate).
