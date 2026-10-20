# EXP [design] v2.7

Version 2.7 / build 18 · October 20, 2026.

## More control over color, with handles that stay out of the way

- Mesh fills combine a base color with editable color points. Select a point on
  the artwork, move it, change its color and opacity, and shape its spread.
- Radial gradients and Mesh points have matching ellipse controls: drag the main
  radius to turn and lengthen it, and the second radius to narrow or widen it.
  Exact Radius X, Radius Y and Angle fields support numeric editing.
- The paint editor stays open while you work on the canvas. Selected points and
  stops keep their color controls in sync, including when palettes are spread
  across multiple monitors.
- Duotone and Color Matrix effects offer simple color choices plus all twenty
  matrix coefficients for fine control over image color and opacity.

## Everyday editing refinements

- Editable polygon corner radii and a cleaner path-point context menu.
- Pattern fills repeat seamlessly at fractional positions, with independent
  per-fill scale and SVG export.
- Pattern fills keep their anchoring through canvas movement and anchor changes;
  changing one fill's anchoring no longer changes every use of its shared tile.
- Horizontal and Vertical Flip follow canvas axes on rotated artwork, including
  triangles and converted paths.
- Artboard notes support headings, emphasis and links. Notes Undo works reliably,
  and tooltips display their intended text.
- Pattern and component source dimensions can be edited directly; detached
  windows and reveal commands support a workspace spread across displays.

## Export and compatibility limits

Mesh is a base plus layered radial colors, rather than a Bézier patch mesh.
Native and EXP-authored export/re-import paths have focused checks; this does not
promise editable third-party meshes. Rotated gradient HTML uses a scalable,
self-contained SVG image when CSS cannot represent the authored ellipse angle.
External nonuniform CSS resizing can change that angle. Legacy imported Shape
patterns retain their original sizing until explicitly changed to fixed tile size.

## Interface and accessibility

- Settings → General links to your optional free EXP account for your profile,
  email preferences and beta/feedback choices. Account preferences apply to the
  website; app settings and design files are not synced.
- Settings → Accessibility offers independent interface text size, larger click
  targets and panel help choices. These settings leave document artwork intact.
- Layer names use clear, standard macOS system typography. Small interface labels
  have stronger contrast, and panel instructions wrap and scroll within their space.
- Detached panels have named Collapse/Expand buttons. Artboard and document
  controls have clearer names, and hover help preserves VoiceOver navigation.

Extensive automated and owner accessibility testing has been completed, including
VoiceOver, contrast, interface text size, click areas and save/open. Full Keyboard
Access remains unverified because it could not be enabled on the test Mac.
Accessibility work continues; confirmed barriers reported by users will receive
high-priority investigation and hotfix treatment.

Existing export limits remain: SVG inner-shadow spread can differ from the
canvas, and unsupported imported clipping/effects may need adjustment. Review
exports before delivery; use a raster export where exact rendered appearance is
required. This release does not claim complete fidelity for every external file.

EXP remains usable without an account or paid entitlement. Optional website
accounts, Pro offers and usage collection have separate rollout requirements;
this native update does not announce paid features or enable usage collection.
