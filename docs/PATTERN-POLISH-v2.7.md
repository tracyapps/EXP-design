# Pattern repeats, scale and palette ordering — October 19, 2026

Development 2.7/build 18 · BUG-076 / BUG-077 / FEAT-075.
Local implementation verified; owner review and the wider release matrix remain.
Owner accepts the preceding polygon radius and point-menu behavior October 19:
“corner radius works great. the menu also feels better.”

## Follow-up supersedes two implementation choices

The owner's next real-artwork review found rounded repeat spacing, shared anchor
scope, SVG phase/viewBox mismatch and palette ordering below Sanaa. See
`PATTERN-PLACEMENT-v2.7.md` for the current implementation and fresh evidence.
The continuous tiled-image sampler and normal palette ordering described below
are historical first-pass decisions, superseded by that follow-up.

## Behavior and scope

- Fractional pattern tiles fill their entire rounded pixel bitmap. Repeats use
  Core Graphics' continuous tiled-image sampler instead of separately antialiased
  rectangles. No epsilon overlap: translucent artwork keeps the same alpha at joins.
- A pattern fill has its own **Scale** slider (1–400%) and exact percentage field
  (1–10,000%). At 100% it uses the original tile size. Scaling enlarges both the
  artwork and repeat interval about the existing lattice anchor. Shared tile
  dimensions, anchoring and other fills stay unchanged. The slider groups a drag
  into one paint Undo; the numeric field and Object/context **Pattern Scale…**
  command provide precise alternatives. The picker also works for pattern strokes
  and backgrounds through their existing paint bindings.
- Native JSON defaults old references to 100%, omits that default when encoding,
  rejects out-of-range serialized scale and preserves explicit scale in appearance
  and imported design-language assets. SVG emits one standard pattern definition
  per source/scale pair, with scaled content (or retained viewBox). Pattern lattice
  values preserve precision: 0.125 no longer becomes 0.13. SVG re-import preserves
  appearance as standard pattern variants, not a promise to merge their sources.
- Paint and nested color palettes use normal app window ordering. The persistent
  primary palette closes on app deactivation and when any route opens a pattern
  editor. Presentation state is cleared before AppKit's animated close, preventing
  it from reopening when returning from the editor. Canvas editing still keeps it
  open. Done/Escape remain available. Unrelated font/tip windows are unchanged.

## Evidence

- The new fractional-tile fixture failed 6/6 added checks before the seam repair.
  A fully opaque tile fell to alpha 124 at bitmap edges and 117 between repeats.
  Correcting the bitmap mapping alone still failed the repeat checks (alpha 173).
  The integrated repair passes **96/96** pattern import/render checks, including
  constant opaque and half-transparent coverage at fractional zoom/pan and rotation,
  including 1% scale with a deliberately transparent fallback (so fallback cannot
  pass the test). The old 40,000-image loop cap is removed from the now-continuous
  sampler; raster tile and optional canvas-stamp allocation budgets stay bounded:
  `/tmp/exp-pattern-import-final-20261019.log`.
- Real WebKit SVG versus native PNG at 50/100/175/200%, both anchoring modes, with
  and without viewBox and with fractional shape anchors: mean channel differences
  0–0.0085/255. PDF rasterization at an explicit 128×80 resolution and standard SVG
  re-import pass the same bounded visual check (mean <3/255). Missing-scale legacy
  decode, invalid scale rejection, save/reopen and distinct SVG variants for two
  fills sharing one source pass. `/tmp/exp-pattern-render-final-20261019.log`.
  An initial PDF test incorrectly requested a display-resolution CGImage (256×160)
  and compared it with a 128×80 PNG; explicit-size PDF rasterization fixed the test.
- Dense-pattern regression uses the durable owner stress document read-only:
  `/Users/tapps/Desktop/test2/perf-tests-2.5/stresstest.design`.
  `/tmp/exp-pattern-performance-final-20261019.log`: cached/live pixels match exactly
  across tested zoom/backing/pan and synthetic alpha/lattice/winding cases. The
  harness previously assumed a smaller fixture's cache budget at .13 zoom/2×;
  it now derives the pixel-budget expectation from the supplied file's geometry.
  Twenty six-wave passes measured 10.8→9.4 ms warm, 7.9→6.3 ms pan,
  16.4→25.4 ms zoom and 17.0→25.7 ms cold. Continuous tiling makes the uncached
  route much cheaper; these are isolated fill passes, not full interaction proof.
- Unsigned app plus thumbnail target build:
  `/tmp/exp-pattern-build-complete-20261019.log`.
  Appearance, interface policy, Handoff goldens and transient-order source checks
  pass in `/tmp/exp-pattern-{appearance,interface,handoff}-20261019.log` and
  `scripts/verify_transient_surface_levels.sh`. Existing compiler warnings remain;
  no unrelated cleanup or golden rebaseline.
- Isolated sandboxed native app: two shapes share a source at different scales;
  exact 200→175 edit and canvas Undo→200 while the palette stays open. The native
  slider's accessibility Increment changes 200→239.9; Undo returns to 200.
  Edit Pattern opens its editor, dismisses the palette, and returning to the canvas
  leaves it dismissed. Done also closes it. Generated artwork only, separate
  bundle/preferences, no network entitlement, updater disabled. Owner app and
  documents were not modified. Physical multi-monitor/app-switch behavior and
  mouse-drag grouping still require owner checks; CUA targets isolated app surfaces.

Apple API and native naming references checked for this change:
- https://developer.apple.com/documentation/coregraphics/cgcontextdrawtiledimage
- https://developer.apple.com/documentation/swiftui/accessibility-fundamentals

No ARIA/export-host semantics changed. Full VoiceOver, text/target sizes, color
management/display combinations, components/states/library and original-document
PNG/PDF/SVG checks are still release gates.

## Owner check, next

1. Rebuild and reopen the paisley document. Check the old joins at fractional zoom
   and after changing the tile size; inspect your PNG/PDF/SVG exports.
2. Change Scale with a drag and with the exact field. One Undo should restore the
   pre-drag size; another use of the same source should stay at its own scale.
   Save/reopen, including the Shape anchoring mode.
3. Open Edit Pattern from the palette, then return. It should stay dismissed.
   Reopen the palette, switch to another app, and test your detached-panel/multiple
   display arrangement. The palette should close when EXP loses activation.

## Reported Flip follow-up — BUG-078

The owner reports polygons do not flip, including after conversion to paths.
No transform fix has been guessed. Fresh native checks show vertical Flip changes
an odd-sided triangle, horizontal Flip mirrors an asymmetric path, and vertical
Flip still works after converting that triangle to a path. Saved fixture flags
confirm polygon flipV=true and asymmetric path flipH=true. Screenshots:
`output/a11y/visual-features-20261019/flip-before.png` / `flip-after.png` (ignored).
Regular polygons are horizontally symmetric; even-sided regular polygons are
vertically symmetric too. This is a possible explanation, not a conclusion about
owner artwork. Asked for side count and whether individual points were moved;
owner clarifies a rotated three-sided triangle used for a bowtie. This identifies
an axis mismatch: current Flip mirrors in local coordinates before rotation;
the intended Horizontal/Vertical directions are those of the canvas. A focused
follow-up will correct the command transform, including converted paths. No flip
behavior has changed in this pattern slice.

Follow-up implemented in the subsequent local slice: `CANVAS-AXIS-FLIP-v2.7.md`
records the corrected canvas-axis command and fresh native/geometry/render proof.
The initial report is no longer awaiting reproduction details; owner review remains.

## Remaining pattern owner review accepted — October 19

Owner confirms seamless repeats, per-fill scaling and SVG export in real artwork/
browser or Quick Look: “Yes, all three work.” BUG-076/080 and FEAT-075 are closed.
Anchoring and window ordering were accepted separately in the same session.
Full accessibility/source-library combinations remain release gates.
