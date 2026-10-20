# Pattern pan and anchor continuity — October 19, 2026

Development 2.7/build 18 · BUG-081 · local repair, owner verification pending.
Supersedes the canvas coordinate handling and anchor-switch behavior described in
`PATTERN-PLACEMENT-v2.7.md`; the fixed tile sizing and export corrections remain.

## Confirmed mechanisms and changes

The owner's report is reproducible in a real layer-backed AppKit view. CGPattern
maps into **default user space**, not the current flipped view's coordinates.
Using CGContext.ctm alone reproduces reverse Y movement. Using device coordinates
alone also fails: backing scale, the backing layer's height, and its axis mapping
must be accounted for. Window coordinates add the docked panel offsets again.

Canvas captures its initial CTM and maps the flipped view into its local backing
layer's unflipped point space. The resolver carries that adjustment to CGPattern.
Fresh bitmap/PDF destinations keep the identity adjustment. Dense canvas stamps
use userSpaceToDeviceSpaceTransform for allocation, keys and composition; their
fresh bitmap resolver does not inherit the native window adjustment.

The other regression was independent: changing anchor recomputed its origin at
the shape corner. PatternPlacement now saves a per-fill lattice offset. Switching
anchors computes old and new origins at the current paint bounds, compensating
without changing the displayed motif. Subsequent Shape movement carries the
pattern; Document movement leaves its phase fixed. Inspector and Object/context
routes use the same model operation; nested parent offsets and path ink bounds
are included. Default-zero offset preserves existing files, codecs, appearance
and shared-source behavior. Source artwork/dimensions still update every use.

Reference: [Apple CGPattern initializer, matrix parameter](https://developer.apple.com/documentation/coregraphics/cgpattern/init(info:bounds:matrix:xstep:ystep:tiling:iscolored:callbacks:)).

## Fresh evidence

All final commands exit 0; intermediate failed hypotheses are not success receipts.

- `bash scripts/verify_mesh_fill.sh output/a11y/pattern-pan-20261019/render-receipt.json --integration-only --owner-pattern-file output/a11y/pattern-followup-20261019/owner-board.design`
  passes. Added real AppKit focus-context pan checks at 2x have **zero mean pixel
  difference** from independent SVG at (0,0), (19,23), (-13,-17). Neutral tiles keep
  this geometry check separate from focus-context gamut clipping. Physical-phase
  preservation, independent SVG definitions after movement, frozen size,
  appearance/codec, rotated lattices, Mesh/effects and owner artwork pass.
  Owner board/crop means remain 0.476/0.861 per channel, not pixel identity.
  `/tmp/exp-pattern-pan-integration-20261019.log`. Focused final rerun after
  removing temporary image dumps: `/tmp/exp-pattern-pan-final-20261019.log`.
- `bash scripts/verify_svg_pattern_import.sh`: **96/96**, including opaque and
  translucent seams. `/tmp/exp-pattern-pan-seams-20261019.log`.
- `bash scripts/verify_pattern_raster_performance.sh '/Users/tapps/Desktop/test2/perf-tests-2.5/stresstest.design'`
  passes real document cached/live parity. Added native AppKit cache checks at
  (0,0) and (19,-13) are **mean/max 0/0**. Existing bitmap/backing/zoom/pan/revision
  and transparent lattice/winding matrix passes. Cache timing is diagnostic:
  warm 8.5→6.7ms and zoom 5.0→49.1ms over twenty passes; no whole-app speedup claim.
  `/tmp/exp-pattern-pan-cache2-20261019.log`.
- App plus shared thumbnail Debug build:
  `/tmp/exp-pattern-pan-build-final-20261019.log`, BUILD SUCCEEDED.
- Appearance, interface policy, semantic HTML/package checks pass:
  `/tmp/exp-pattern-pan-{appearance,interface,handoff}-20261019.log`.

Native verification used a separately identified, sandboxed app copy with no
network/update capability; owner app and originals were not edited. Receipts live
in ignored `output/a11y/pattern-pan-20261019/`:

| Check | Result |
| --- | --- |
| Layer-backed subview probe, old CTM vs independent explicit repeats | 6,768/36,542 interior sample mismatches before pan; 7,071/37,308 after pan |
| Corrected subview probe vs independent repeats | 0 mismatches before and after pan |
| Actual editor, +37 vertical pan | 0/46,123 interior motif sample shifts |
| Document → Shape at current position | 0/86,130 motif sample changes |
| Shape move +10,+10 | 0/86,130 motif sample changes relative to the object |
| Shape → Document after moving | 0/86,130 motif sample changes |
| Document move +10,+10 | 0/72,250 motif changes in the fixed overlapping canvas region |
| Undo anchor/moves, then Redo | Shape at (40,40), restored Document at (50,50) |
| Save | Offset (10,10) on first reference; other shared-source fill unchanged |

PNG screenshots and comparison Swift files retain these tests. Interior comparison
excludes the independent repeat reference's antialiased edges; full-pixel mismatch
counts are not represented as zero. The actual editor's pan comparison excludes
two pixels around motif boundaries. Anchor switches and movement comparisons
cover all pixels in the stated crop. Later native drag attempts were blocked by
an automation no-window error despite a readable live AX tree; no further drag
coverage is claimed. Keyboard movement, anchor switches, Undo/Redo/save continued.

## Owner repeat and sequencing

- Pan horizontally and vertically, including live movement and the settled view,
  with both anchors and your physical monitor setup.
- In Document mode, move the object until the motif looks right. Switch to Shape:
  it must stay exactly there. Move the object: the motif must follow. Switch back
  to Document: no jump; subsequent movement slides the shape over the fixed motif.
- Confirm resize still preserves motif proportions; Undo/Redo and save/reopen.
- Real complex/rotated/nested/pattern-stroke, native dense-path, display/AT and
  cross-monitor combinations remain owner/release gates.

The requested matching radial/Mesh ellipse controls are recorded as FEAT-076 in
`GRADIENT-ELLIPSES-v2.7.md`. No new gradient model/rendering change starts while
this repair awaits owner verification (AGENTS.md sequencing rule).
