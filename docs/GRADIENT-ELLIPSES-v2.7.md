# Matching radial and Mesh ellipse editing — next v2.7 slice

Owner request October 19, 2026 · FEAT-076 · implemented locally; owner verification pending.
Owner explicitly authorized this slice October 19; BUG-081 physical/full review stays open.

The existing radial secondary handle edits the second ellipse radius; it is not a
3D plane. Mesh currently has one radius, applied to both unit-box axes. Radial
handles currently stay on the horizontal/vertical axes. The owner wants to narrow
an ellipse and turn it to any angle, consistently on a radial fill or each Mesh
point, while keeping the selected point/color active in the persistent palette.

## Observable contract

- Both editors have a center, a primary radius handle that can turn around the
  center, and a second axis handle for independent ellipse width/height.
- Primary handle dragging changes its radius and orientation; the second handle
  adjusts the perpendicular radius. The ellipse outline and color-stop handles
  follow the same geometry. No perspective/3D behavior is introduced.
- Provide exact Radius X, Radius Y and Angle fields with descriptive names and
  keyboard editing. Keep point-color dots, selected accents, active stop/color,
  palette persistence, compact/icon settings and numeric alternatives.
- Preserve old rendering with additive, default-zero angle and equal Mesh radii
  unless edited. Shape resizing continues the established bounds-relative sizing.
- One gesture is one Undo. Native save/reopen, appearance, shared libraries,
  component instances, and source editing retain both axes and rotation.
- Native canvas, thumbnails, PNG/PDF, SVG, semantic HTML/CSS and supported own-import
  must agree. Check the CSS representation against the current official grammar
  before coding; do not silently drop the angle or export a different ellipse.
  Keep vector/scalable output where the existing contract provides it.

## Implementation seams to inspect

- `Model/Paint.swift`: RadialGradientGeometry currently stores center/radius;
  MeshPoint stores radius/position/color/opacity. Extend bounded decoding and
  data-only metadata without invalidating legacy files or stable point IDs.
- `Color/PaintRender.swift`: radial transform and Mesh vector/PDF coverage paths.
  Use one geometric transform for display, analytic alpha and handles; compute
  the angle in physical local points so a non-square carrier stays predictable.
- `Canvas/CanvasView.swift`: gradientHandleLine/hitTestGradientHandle,
  hitMesh/drawMeshHandles, radialY/gradientEnd/gradientStop and meshPoint drags.
- `Color/PaintEditor.swift`: add independent Mesh radii/angle and radial angle;
  preserve existing paint-gesture grouping and selected stop synchronization.
- `Export/ExportRenderer.swift`, `Model/SVGImporter.swift`,
  `Export/SemanticHTMLExporter.swift`, `Model/RenderedHTMLImporter.swift`,
  `Color/DesignLanguageIO.swift`: matching transforms, strict metadata validation,
  honest CSS/vector fallback, own-import checks and swatch/library fidelity.

## Acceptance evidence before handoff

An asymmetric, narrow ellipse at a non-axis angle on a non-square shape, in both
fill types; both handles and exact fields agree; stops stay editable on the turned
radius; transformed/nested shapes, opacity and Mesh layering retain geometry.
Compare native/PDF/SVG/browser pixels and independently calculated ellipse coverage;
verify malformed geometry is rejected, old fixtures unchanged, Undo/save/reopen,
shared target builds and accessible numeric alternatives. Owner native interaction
and physical display/AT checks remain distinct from synthetic evidence.

## Implemented October 19 — local evidence, owner review pending

The owner explicitly said “go ahead and continue on the radial controls.” This
starts FEAT-076 by owner direction; it does not close BUG-081's physical-display
checks. No other document-changing feature was started.

Both fill types now use a physical-point ellipse transform. Drag the main radius
around its center to turn it and change its length; drag the perpendicular handle
to change only the second radius. Radius X/Y are percentages of carrier width/
height before rotation. Angle wraps into 0–359.99 degrees clockwise in local space,
then node/ancestor rotations and flips apply. Stop handles/projected positions use
the same turned primary axis. Numeric fields keep the persistent palette, point
selection and existing gesture Undo. A nearest-handle rule prevents narrow Mesh
ellipses from reserving their center for the secondary radius's larger hit target.

`RadialGradientGeometry.angle` defaults to zero. Mesh's optional `radiusY` defaults
to its original `radius`; angle defaults to zero. Zero/default fields are omitted
when encoding, retaining byte-canonical legacy Mesh metadata and old appearance.
An independent edit freezes Mesh's other axis, atomically, before changing it.
Values remain finite/bounded; IDs, opacity, layer order and metadata limits remain.

Native/PDF coverage, thumbnails, swatches and SVG share the transform. SVG own-import
resolves concentric gradient matrices against carrier bounds before deriving axes;
separate focal points and unrepresentable skew retain the documented warning.
Curved radial fills/strokes use actual ink bounds; polygon radial paint uses its
logical frame via SVG user space. Translucent radial stroke PDF masks cover the
whole stroked outline while retaining the original gradient geometry, preventing
the outer half from being cut off at the path bounds.
HTML uses ordinary CSS for axis-aligned gradients, and a self-contained scalable
SVG data image when rotation is authored. Export supplies each carrier's dimensions;
the fallback has no network resources or scripts. Editable own-import requires a
byte-canonical, bounded image, unchanged background placement/color and matching
aspect. Changed markup or placement falls back through the normal image importer;
metadata never hides the visible change. A verified element gets one editable fill,
not another SVG/image layer. CSS/SCSS swatch values without a carrier use a square
reference; exported semantic elements use actual dimensions and bypass a generic
rotated-gradient variable. This is a fixed-layout export, not a claim that external
nonuniform CSS resizing preserves the physical angle.

Design-token Mesh payloads retain axes/angle. Radial tokens keep the normal gradient
stop array and add `app.expdesign.radial-v1` under `$extensions`; own-import uses it
only while the standard stops still agree. Third-party token tools may ignore that
extension and retain the stops. Native design-language/source/component storage
uses the shared paint codec. Full owner interaction across those surfaces remains.

### Fresh verification

- `bash scripts/verify_mesh_fill.sh output/a11y/gradient-ellipses-20261019/receipt.json`:
  full legacy and new math/render integration passes. At 33°, 127° and 298° on
  128×80 and 60×144 carriers, Mesh native/actual PDF independent analytic error
  is at most 2/255, SVG/CSS at most 2/255. Radial PNG (rasterized actual PDF)/SVG
  error at most 3/255, CSS and SVG own-import at most 1/255. Primary/secondary axis
  orthogonality, physical angle, stop projection, codec/defaults and invalid geometry
  checks pass. Legacy alpha/layering/outline/path/pattern checks remain green.
- Nested rotated/flipped carriers: interior SVG error 2/255; whole-image mean
  Mesh 0.7441 and radial 0.3244/255. Silhouette antialias edge maxima are 39/14;
  these are not pixel-identical claims. Own-import maxima are 0/1. The test separates
  full-alpha interior paint from edge coverage and records both.
- Final element-import and stale-placement checks plus complete integration rerun:
  `output/a11y/gradient-ellipses-final-20261019/receipt.json`, logs
  `/tmp/exp-ellipse-integration-final-20261019.log` and final full run
  `/tmp/exp-ellipse-full-final-20261019.log`. Curved-path and triangle radial
  fill/stroke SVG means are 0.1636/0.1150; own-import means 0.0164/0.0176 of 255.
- `verify_semantic_html_package.sh`: actual carrier-sized vector CSS, embedded path
  SVG rotation, token round-trip and changed-stop rejection, plus all existing
  Handoff/semantic fixtures. `/tmp/exp-ellipse-handoff-final-20261019.log`.
- `verify_appearance_style.sh`, `verify_interface_accessibility.sh`,
  `verify_svg_pattern_import.sh` (96/96), and app/thumbnail Xcode Debug build pass.
  Build log `/tmp/exp-ellipse-build-complete-20261019.log`. Standalone Swift checks
  retain the pre-existing TurbulenceNoise Sendable warnings. The app build also
  retains existing warnings in unchanged Canvas point-address/importer/interop code;
  this is a successful build, not a warning-free claim.
- An isolated sandboxed copy of the actual editor, with updater/network/document
  registration removed, edits generated `ellipse-native.design` only. Radial angle
  33→57; primary drag changes X radius/angle to 55.27%/359.92° while palette stays;
  one Undo restores 56%/57°. Mesh secondary drag changes only Y 17→64.213%; one Undo
  restores 17%. Keyboard entry −45 wraps to 315°. Saving/reopening in the final
  build retains Mesh 56%/24%/315° and radial 56%/17%/57°, with descriptive AX fields.
  The final very-narrow-center drag could not be exercised: native automation
  returned `noWindowsAvailable` while AX editing still worked. No AT/physical
  display/complete native interaction matrix is claimed. The test app is closed.

### Owner verification before another document-changing slice

1. On radial and Mesh fills, narrow the ellipse with the secondary handle, then
   turn/lengthen it with the primary handle. Check center grabbing on very narrow
   ellipses, active color/point and exact fields while the palette remains open.
2. On ordinary radial, add/move an intermediate stop along the turned radius.
   Try a rotated/flipped/nested shape and a resized wide/tall shape.
3. Undo/Redo each gesture and numeric edit, then save/reopen. Check exports with
   transparent/opaque paint, multiple Mesh points and your actual artwork.
4. Review compact/large text, keyboard/VoiceOver and multi-monitor placement.
   Components/libraries/padding/background/stroke combinations remain release gates.

### Standards checked before implementation

- CSS Images 3 §3.2 syntax has position/ellipse radii and no radial orientation
  parameter: https://www.w3.org/TR/css-images-3/#radial-gradients .
- SVG 2 radial paint-server transforms:
  https://www.w3.org/TR/SVG2/pservers.html#RadialGradients .
- Native fields use descriptive accessible names following Apple's label guidance:
  https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:) .
  AX labels were inspected; complete VoiceOver interaction is pending. No ARIA
  role/relationship or semantic host mapping changed.
- DTCG permits vendor extension data alongside the standard gradient stop value:
  https://www.designtokens.org/tr/drafts/format/ . Existing third-party support is
  not assumed, and the extension cannot override changed standard stops.
