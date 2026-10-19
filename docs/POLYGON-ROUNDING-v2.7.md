# Polygon corner radius and point menu — October 19, 2026

Development 2.7/build 18 · BUG-075 / FEAT-074 · initial behavior owner-accepted
October 19 (“corner radius works great. the menu also feels better.”). Full release
matrix remains open. Subsequent Flip report is BUG-078; see `PATTERN-POLISH-v2.7.md`.
The owner explicitly requested these two changes while testing the gradient
refinements. This does not mark the gradient or wider release matrix accepted.

## Behavior

- Path-anchor context menus offer Make Corner / Make Curved without New Empty
  Pattern. Pattern creation and Fit Source to Artwork now enter only the general
  canvas menu, after specialized point/gradient/Mesh menu branches return.
- A selected polygon has a **Corner radius** numeric field below Sides. Zero
  remains sharp. The requested radius is in document points; one uniform radius
  is clamped at neighboring edge midpoints before corners overlap. Circular
  fillets are represented by cubic Bézier arcs. Artwork remains a polygon with an
  editable side count. The chosen value is remembered for the next polygon drawn
  in the current app session, like the existing side count.
- Object → Polygon Corner Radius… and the polygon's context menu open the same
  numeric dialog. Inspector and dialog call one Canvas action with scoped model
  commits and a single Undo. Locked/non-polygon selections disable the command.
- Optional Codable cornerRadius defaults to zero for old documents and is omitted
  at zero. Appearance copy/paste retains it. Conversion to paths, native/export
  silhouettes, masks and layer thumbnails use the shared rounded outline.

## Exports and limits

Native app/thumbnail/PNG/PDF use the shared curves. SVG emits a real cubic path
for rounded polygons and keeps the existing polygon output at zero. Gradients on
rounded polygon SVG use explicit frame coordinates so tighter ink bounds cannot
move their paint; Mesh already uses explicit frame placement. Handoff HTML embeds
the curved SVG, preserving editable native data in design.json. Its rounded SVG
supports gradient/Mesh fills and strokes; existing non-center stroke-alignment
limitations are still reported. Radius-zero Handoff goldens remain unchanged.

SVG imports rounded geometry as an editable path, not a parametric polygon.
The existing user-space gradient reader limits apply to such external SVG
round-trips; native JSON retains radius and paint exactly. Pattern paint,
component-state/library, effects and full display/AT combinations are not newly
certified by the bounded fixtures below. No ARIA host mappings were changed.

## Fresh evidence

- App and EXPThumbnail unsigned build: `/tmp/exp-polygon-build-final-20261019.log`.
- Appearance/model checks: `/tmp/exp-polygon-appearance-20261019.log`.
  Legacy missing radius, zero-radius geometry, a 10-point circular right-angle
  tangent, sides 3/4/8/25 with oversized radii, native codec and appearance retention.
- Native/PDF versus actual WebKit SVG: `/tmp/exp-polygon-render-20261019.log`.
  Rounded five-sided solid/linear-gradient/Mesh fixtures, with a centered black
  stroke: interior channel errors 0/2/2 of 255; mean full-image channel differences
  0.026/0.191/0.219. The narrow antialiased stroke boundary is excluded from the
  interior color calculation; full-image mean still includes it. Prior integrated
  Mesh/radial export checks remain green.
- Handoff: `/tmp/exp-polygon-semantic-20261019.log`. New rounded polygon SVG check
  and prior deterministic/semantic/mask goldens pass. The first run caught an extra
  closing line in zero-radius silhouettes; preserving their original path builder
  restored the exact golden without rebaselining it.
- Vector conversion regression: `/tmp/exp-polygon-vector-20261019.log`.
- Actual isolated native app: radius 0 → 24; one Undo → 0; Redo → 24. Saved JSON
  independently confirms five sides, polygon type and radius 24. The Object menu
  dialog changes 24 → 32; one Undo restores 24. A right-click on the separate path
  anchor shows only Make Curved. Evidence in ignored
  `output/a11y/visual-features-20261019/polygon-radius.png` and `point-menu.png`.

The fixture has a separate bundle/preferences identity, disabled updater and no
network entitlement. Only generated artwork and its agent-owned process were
used. Owner app/documents/preferences were unchanged; no push or deployment.

Native descriptive field/dialog naming follows Apple's accessibility label
contract: https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)-1d7jv
The label describes the setting without repeating a control role. Full keyboard
and VoiceOver interaction remain owner/release checks.

## Owner review

Try radius on a triangle, pentagon and a stretched polygon; change side count,
resize, Undo and save/reopen. Convert a copy to a path and compare your exports,
including the paints/strokes/effects you use. Check both Make Curved and Make
Corner menus on your real document. Gradient refinements still await review too.
