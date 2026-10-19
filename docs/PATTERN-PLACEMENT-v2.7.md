# Pattern placement and SVG follow-up — October 19, 2026

Development 2.7/build 18 · BUG-077 / BUG-079 / BUG-080.
Implemented and locally checked; owner artwork/display review remains open.
This supersedes the sampler and normal-window-ordering choices in
`PATTERN-POLISH-v2.7.md`; that document retains the first pass's receipts.

## Behavior

- Anchoring now belongs to each paint reference, alongside scale. Document keeps
  a fixed document origin; Shape follows the layer with a fixed physical tile
  size. Nonuniform shape resizing crops/repeats instead of stretching the motif.
  Tile artwork and source dimensions remain shared. Fill, stroke and background
  pickers retain their existing bindings; Object/context anchoring commands operate
  on the single unlocked selected fill. Shared editor no longer changes anchoring.
- Legacy references decode unchanged. SVG objectBoundingBox fractions retain their
  imported behavior until the designer chooses an anchor or clicks **Keep imported
  tile size fixed**. That freezes conversion at the current shape dimensions;
  subsequent resizing preserves the repeat size. No automatic rewrite on load.
  Appearance and design-language remapping retain placement and reference size.
- Paint windows float above ordinary EXP panels, hide on app deactivation and close
  on Settings, pattern/component editor and Sanaa response handoffs. They no longer
  use global popUpMenu level. The setting applies to NSWindow as well as NSPanel.
- SVG compensates document-space pattern phase for the exported artboard origin.
  Explicit per-fill placements emit independent user-space pattern definitions.
  Pattern viewBox uses preserveAspectRatio=none, matching EXP's existing tile
  rasterizer. Tile-local nested patterns do not inherit the outer board offset.
- Fractional spacing uses a noDistortion CGPattern. Tiled-image drawing rounds
  repeat periods (21.6 becomes 22 device pixels at 1x). Rounded pattern cells can
  overlap, so callback image drawing disables geometric antialiasing and uses copy
  inside the cell; translucent edges cannot accumulate alpha. The enclosing paint
  retains its compositing mode. Rounded bitmap extent mapping remains in place.

## Real owner artwork

Read copies of `~/_dev/apps/a11ycat/_design/logobrainstorm.design` and
`a11ycat-square.svg`; originals retain identical SHA-256 to the initial copies:

- Document: f27146a3c3bafa55c62dea663472d4e6006f361402687d53370407d248f4366a
- SVG: 4d592f352762311ad356c3a5f296a0b6542feb745284397ce74e01cae43f2bc7

The board starts at (1086,1634). Its paisley tile is 906.4170612548216 by
637.0627795271641, with an 86 by 78 viewBox at (13,91). Missing phase translation
and the SVG default viewBox fitting explained the misplaced/differently sized
bowtie motif and right patch. No speculative Mesh/blend rewrite was needed.

At 540 by 540, repaired SVG versus native PNG mean absolute channel difference
is 0.476/255 for the board and 0.861/255 for the bowtie crop. This is approximate
renderer parity, not pixel identity or proof of every renderer. Native, exact
WebKit and Quick Look images were visually inspected. Files are in the ignored
`output/a11y/pattern-followup-20261019/` directory, including `owner-current.svg`.
The reduced board retains its pattern, sources and Mesh overlays.

## Fresh checks

All commands below exit 0:

- `bash scripts/verify_svg_pattern_import.sh`: 96/96, opaque and half-transparent
  repeats at fractional pan/zoom/rotation, including 1% scale and clear fallback.
  `/tmp/exp-pattern-import-final3-20261019.log`.
- `bash scripts/verify_mesh_fill.sh output/a11y/pattern-followup-20261019/mesh-receipt.json --integration-only --owner-pattern-file output/a11y/pattern-followup-20261019/owner-board.design`:
  offset/viewBox/Mesh-overlay fixtures, owner board/crop, independent per-fill
  anchors, fixed dimensions during move/resize, 135% scale, codec/appearance,
  native/PDF/SVG, translucent fills, rotated source-lattice movement, rounded
  polygons and Mesh import/effects integration pass. The transformed-placement
  check fails before correcting document-space anchor movement.
  `/tmp/exp-pattern-final-integration2-20261019.log`.
- `bash scripts/verify_pattern_raster_performance.sh '/Users/tapps/Desktop/test2/perf-tests-2.5/stresstest.design'`:
  cached/live parity passes at 1x/2x, pan/zoom/revisions and translucent variants.
  `/tmp/exp-pattern-cache-final3-20261019.log`. Timing is diagnostic: new continuous
  rendering is cheap enough that stamp caching is slower on cold/zoom passes
  (11.5→51.6ms over twenty six-path passes), and faster in the pan sample
  (22.0→5.9ms). No claim of universal cache speedup or whole-app stress proof.
- App and shared thumbnail Debug build pass:
  `/tmp/exp-pattern-build-final4-20261019.log`.
- Appearance, interface accessibility policy, semantic HTML/package goldens and
  transient-window contracts pass; no golden rebaseline. Logs:
  `/tmp/exp-pattern-final-{appearance,interface,handoff}-20261019.log`.
- Quick Look thumbnail generation succeeds for repaired SVG:
  `/tmp/exp-pattern-quicklook-final-20261019.log`.

Native isolated, sandboxed app (separate identity, no updater/network): changed
Original scale to Shape; Double scale remained Document and 200%. Saved JSON
confirmed only the first ref gained placement. Dragging 300x350 to 230x206 kept
motif size/proportions. Undo restored dimensions, then prior anchor. Settings and
pattern-editor handoffs dismissed the palette; return/reopen retained Shape and
saved placement. Window menu raised detached Properties/Layers. Screenshot
receipts: `native-resized.png`, `native-editor-handoff.png` in that output directory.

One native automation connection timed out after closing Settings; process sample
showed an idle AppKit event loop, not a crash. Restarting only the disposable app
restored automation. Sanaa overlap and physical app-switch/multi-display behavior
remain owner checks; cropped panel captures cannot establish cross-window stacking.

## Owner checks

1. Two shapes sharing a tile: change only one anchor; move and resize it in both
   directions, Undo/Redo, save/reopen. Existing imported Shape fractions: click
   Keep imported tile size fixed once before testing resize. Shared tile edits
   should still update both uses.
2. Re-export a11ycat-square and compare the bowtie, right edge and Mesh overlays
   in EXP, browser and Quick Look. Existing exported files are not rewritten.
3. With Sanaa beside Properties, open the paint palette: it must be readable above
   the neighbor. Open Sanaa setup, pattern/component editor, then another app;
   no old palette should obstruct them. Repeat on the physical monitor setup.
4. Full keyboard/VoiceOver, light/dark, rotated/nested instances, patterned strokes
   and library/component combinations remain release gates.

References: [Apple window deactivation](https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate),
[SVG paint servers](https://www.w3.org/TR/SVG/latest/pservers.html),
[SVG coordinate systems/viewBox](https://www.w3.org/TR/SVG2/coords.html).
