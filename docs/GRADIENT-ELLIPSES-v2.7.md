# Matching radial and Mesh ellipse editing — next v2.7 slice

Owner request October 19, 2026 · FEAT-076 · planned, not implemented.
Starts after owner verifies BUG-081 pattern pan/anchor repair, per AGENTS.md.

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
