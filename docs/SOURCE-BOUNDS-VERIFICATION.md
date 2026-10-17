# Pattern/component authoring and window ordering — v2.7

Owner scope: October 17, 2026. FEAT-071, BUG-071, BUG-072. Local development
build 2.7/18; public releases and update artifacts are unchanged. Owner review
remains required before the next document-mutating slice.

## Observable changes

- **First pattern:** Fill → Pattern → New Pattern works with no imported tiles.
  It creates a blank 100×100 source, applies it to that paint and opens the editor.
  Patterns panel → New Pattern creates an unassigned tile. Object → Component →
  New Empty Pattern and canvas context menu provide the command routes.
- **Open the actual pattern:** the fill popover passes its document and pattern ID
  directly, including while it owns focus. Anchoring changes also use the known
  document; the pattern editor no longer needs a canvas responder for its picker.
- **Bounds:** pattern editor W/H controls the repeat interval; Shape anchoring
  displays percentages. Tile handles change bounds. Components expose X/Y/W/H.
  Expanding the tile adds empty space; it does not scale the child artwork.
  Imported viewBox mappings retain their scale. All uses share the edited source,
  through the existing model-generation/cache-invalidation path.
- **Fit to Artwork:** both editors, Object → Component and canvas context menu.
  Fits visible selection geometry including strokes, rotation and masks. Hidden
  descendants and empty unpainted groups do not enlarge the result. Managed layout
  container frames follow existing inspector conventions; soft shadows/effects do
  not enter geometry dimensions. No raster-alpha trimming is claimed.
- **Component persistence:** an explicit-bounds flag prevents managed-root layout
  from immediately overwriting a deliberate resize. Missing flag in old documents
  means automatic, preserving existing behavior. Follow layout bounds restores
  managed-root sizing when applicable. Component Fit respects the edited state.
- **Windows:** detached trays use ordinary peer ordering. Settings follows the
  active canvas display when presented from another display. Window menu reveals
  existing detached panels, keeping stable glue-parent links. Transient popovers
  and drag indicators retain their intentional transient levels.

## Fresh automated evidence

- `bash scripts/verify_source_bounds.sh` — passes actual model/render checks:
  stroked and hidden/nested-hidden bounds, pattern fit/resize without child scaling,
  real raster size/opaque/transparent pixel probes, imported viewBox ratio and units,
  component explicit sizing/resolution, JSON save/reopen and legacy decode.
  Log: `/tmp/exp-source-bounds-check.log`. The stand-alone compiler still reports
  existing TurbulenceNoise Sendable-capture warnings; the executable exits zero.
- `bash scripts/verify_svg_pattern_import.sh` — **86/86 pass**, real SVG fixtures,
  including bounds-relative import, round-trip rendering and anchoring conversions.
  Log: `/tmp/exp-pattern-import-regression.log`.
- `bash scripts/verify_nested_component_graph.sh` — passes existing component graph,
  nested layout, cycle and duplication checks.
  Log: `/tmp/exp-pattern-nested-regression.log`.
- App, thumbnail and UI test build: `xcodebuild -project 'EXP [design].xcodeproj'
  -scheme 'EXP Accessibility' -configuration Debug -destination
  'platform=macOS,arch=arm64' -derivedDataPath /tmp/exp-a11y-derived
  build-for-testing CODE_SIGNING_ALLOWED=NO` — passes.
  Log: `/tmp/exp-pattern-authoring-build.log`. Existing XCTest setup/teardown
  isolation warnings remain; this is not a warning-free build claim.
- **Four native UI workflows pass, zero failures/skips:** first tile from empty
  fill, close/reopen retains width 160; first tile from Patterns panel; component
  width 140 then Fit returns 80; detached Sanaa → Settings interaction, normal
  peer window layers and Window → Properties reveals an interactive existing tray.
  Receipt: `output/a11y/pattern-authoring-confirmed-20261017/native/results.xcresult`.
  Log: `/tmp/exp-pattern-authoring-confirmed-runtime.log`. Cropped component,
  pattern and Settings screenshots inspected. This proves local window interaction
  and levels; the physical second-display placement remains an owner gate.
- `bash scripts/verify_backlog_ids.sh` and `git diff --check` pass.

Native copies are re-identified and ad-hoc signed under `output/a11y/`, with no
network entitlement, production helpers, document associations or shared keychain.
Tests never launch the installed app or edit the owner's test document.

Earlier runs are retained: `pattern-authoring-20261017` had a component creation
shortcut/focus harness failure; `pattern-authoring-final-20261017` caught a real
stale focused-number-field display after Fit (now corrected) plus a test looking
for a dock-only collapse button in a detached tray (now checks the real dialog).
Those failures are not treated as passing evidence.

## Owner review — running Xcode build

1. In a fresh document, select a rectangle, choose Fill → Pattern → New Pattern.
   Draw a small shape in the tile. Leave the main canvas visible behind the editor.
   Change W/H and drag tile handles: confirm the main canvas retiles immediately,
   without stretching the artwork. Undo/redo, close/reopen the editor, save/reopen
   the document. Also create the first tile from the Patterns tab.
2. In the real test document, use Edit Pattern from its existing fill. Confirm the
   correct imported tile opens. Try numeric bounds and Fit; inspect clipping,
   transformed/viewBox and Shape-anchored patterns. All uses should update.
3. Open a component source; set X/Y/W/H, Fit, undo/redo and save/reopen. For a
   managed-layout source, explicit dimensions should stay fixed; Follow layout
   bounds should restore automatic sizing. Try an alternate state.
4. Put detached palettes on a side monitor. From Sanaa choose Agent settings:
   Settings should open on the canvas display and remain reachable. Use Window →
   Properties/Sanaa/Components to raise existing trays. Test source editors,
   popovers, glued movement and app deactivate/reactivate on the real arrangement.
5. Check 1x/2x, light/dark, large interface text and real VoiceOver traversal.
   These broader visual/AT gates are not certified by focused workflow tests.

Official sources rechecked: [Apple VoiceOver alternative labels](https://developer.apple.com/design/human-interface-guidelines/voiceover)
and [NSWindow.Level ordering](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct).
The Markdown versions were read when the HTML required JavaScript. Native names
use native accessibility APIs; no exported ARIA semantics were changed.
