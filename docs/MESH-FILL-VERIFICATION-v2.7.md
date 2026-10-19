# Mesh fill — v2.7 owner review

October 18, 2026 · FEAT-033 · development 2.7/build 18.
Owner accepted the initial editable functionality October 19 (“that works nicely”).
The requested refinement slice awaits review; see `GRADIENT-EDITING-v2.7.md`.
Full AT/display/stress/library gates remain open.

## Try it in the rebuilt Xcode app

1. Select a rectangle/ellipse/polygon/closed path. Open Fill and choose **Mesh**.
   Edit → Mesh Fill → Use Mesh Fill and the selection context menu create the
   same seeded fill. The base keeps your previous representative color.
2. Change Base; Add a color point; select its numbered button and change its
   color, X/Y percentages, Radius and Opacity. Radius is a fraction: 1 means one
   horizontal width and one vertical height. Back/Front change the point order;
   Remove deletes the selected point. At most eight points; all can be removed
   to leave the base. Numeric controls provide the keyboard alternative.
3. Keep the popover open. On shape fills, drag a colored center to move it; select
   a point to see its dashed elliptical extent and white radius handle. Drag
   that white handle to resize. Escape restores the drag baseline; returning
   to the original value does not create an Undo step. Artboard/auto-padding
   backgrounds and library/instance paint controls use the numeric route.
4. Right-click selected artwork → Add Mesh Point Here to place a point there;
   Edit → Mesh Fill also adds/removes/reorders points without dragging.
5. Check one Undo per numeric edit/add/reorder and per canvas drag/color session.
   Save, close, reopen, duplicate and copy/paste appearance. Try actual components,
   source states and Design Language assets. Compare PNG/JPEG/PDF/SVG, including
   layer opacity and transparent colors, on your normal displays.

Mesh follows the chosen **base plus layered radial points** representation; it is
not a Bézier patch mesh. Existing solid/linear/radial/pattern encodings are unchanged.
The new distinct Paint case stores the actual point values and stable local IDs.
An older public build does not understand this paint; use the development build
for review and do not save Mesh documents back through an older app.

## Rendering, opacity and stroke policy

The shared drawing code serves the app and thumbnail target. Live fills use up to
8 vector radial operations. Mesh is multiple paint operations: the canvas/export
single-operation shortcut excludes it, so layer opacity/blending is applied once
to the completed appearance. Source images and the parked shadow renderer are
unchanged.

At unit layer opacity/normal blend, PDF fill colors remain vector with explicit
coverage masks (up to 3× model resolution, 1024×1024 / 1 MP / 4 MiB each). Quartz's
PDF transparency group caused a measured 9/255 color shift at 50% layer opacity.
For nodes with Mesh and non-unit opacity/non-normal blend, raster export instead
captures the finished node through the existing bounded sRGB layer engine before
one composite. The two actual PNG/SVG fixtures now differ by only 2/255. This
capture is capped at 16 MP / 8192 per axis / 32 MP aggregate; it uses the requested
PNG/JPEG scale and model-point scale for PDF, and fails explicitly above budget.
SVG remains a standards-readable editable radial stack in a paint-server pattern.
The existing SVG policy omits artboard backgrounds; use a shape for a background
that should travel in SVG. PNG/PDF still include the artboard background.

For outlines with positive two-dimensional geometry, the finished Mesh repeats at
its editing-frame boundaries, matching the SVG pattern's paint semantics. Native
outline tiles have a bounded roughly 4 MP / 4096-axis raster, with an evictable
32 MiB / 32-entry cache keyed by point data and pixel dimensions. This can soften
extreme zoom/export sizes. The ordinary Line inspector keeps its prior paint
options because a zero-area line has no two-dimensional Mesh tile. A forced invalid
Mesh outline produces an explicit unavailable render/export, not a flat-color
success. Semantic HTML CSS borders report their base-color fallback; SVG path
strokes retain the real paint. Sanaa reports Mesh backing contrast as unresolved
until spatial sampling is implemented; it never treats the base as proven contrast.

These are capture/cache budgets, not a measured hard process-RSS ceiling. Full
stress, high-resolution edge/profile and display certification remain open.

## SVG / CSS editable import

SVG exports use bounded data-only `data-exp-mesh-v1` JSON/Base64 on a unit pattern
placed explicitly in the logical editing frame with `userSpaceOnUse`, plus ordinary
rect/radial-gradient visuals. Native curved fills/strokes use that same frame as
their handles. A regression first measured a 51/255 native error against editing-frame
math; the fix reduces it to 2/255, with native/SVG interior error 2 and native own
SVG re-import error 0. Before-fix log: `/tmp/exp-mesh-curve-frame-before-20261018.log`.
Import regenerates the canonical pattern/gradient graph and checks carrier placement
before reconstructing points (0.02-point tolerance for the existing SVG geometry
rounding). Changed tile placement is rejected. Historical object-bounding-box
metadata collapse is limited to rectangle/ellipse/circle carriers. Modified
colors/positions, invalid/oversized metadata, extra graph content, stylesheet
visual overrides or animations cannot silently collapse from stale metadata.
Only EXP's inert `:root` hex-color variables are ignored. Unsupported variants
retain supported pattern/geometry with import notes. Separate SVG fill/stroke
opacity, skew and nonuniformly scaled vector carriers remain bounded-reader
limits; orthogonal rotated rectangles/ellipses and rotation/reflection on unit-scale
vector carriers retain their native pose. Native layer opacity is supported.

Semantic HTML emits real layered CSS plus `--exp-mesh-v1` metadata. The production
WebKit extraction compares the resolved background with a newly parsed expected
background, without adding anything to the page, before marking that metadata
usable. Swift validates its strict version/point/numeric/UUID/size limits again.
Changed CSS does not revert to old points and is reported. Full page/root opacity,
complex clipping/filters and arbitrary third-party gradient stacks are not claimed
as universal editable Mesh reconstruction.

EXP JSON retains Mesh directly. Design Tokens use an explicit `exp-mesh-v1` custom
type/payload rather than pretending it is a standard solid/linear-gradient token;
the EXP token reader restores it. Third-party token tools may ignore that extension.

## Fresh evidence

- `bash scripts/verify_mesh_fill.sh [optional-receipt.json]`: 14 native/math/
  WebKit CSS/SVG/actual-PDF foundation cases plus the actual Paint → PNG/PDF/SVG
  path, 100%/50% layer opacity, deterministic export, SVG restore/stale-data/style
  override checks, document codec, rotated non-square SVG/native round-trip,
  real production CSS extraction → importer and changed-CSS rejection, plus
  tiled outline parity at both opacities and curved-path editing-frame math/own
  import checks. Native/SVG fills: 2/255; rotated native
  re-import: 0; outline parity: 2–3/255. Foundation quantization limits remain
  those in `MESH-FILL-FOUNDATION-v2.7.md`, not a bit-exact claim.
  Log: `/tmp/exp-mesh-integration-final-20261018.log`.
- Existing semantic Handoff goldens remain unchanged; the suite adds Mesh CSS/
  metadata, explicit border fallback and custom token round-trip checks.
  `/tmp/exp-mesh-integration-semantic-final-20261018.log`.
- Appearance copy/paste and codec retain editable point data;
  `/tmp/exp-mesh-appearance-20261018.log`.
- Existing effects, rendered-HTML import and real pattern fixtures pass:
  `/tmp/exp-mesh-effects-regression-20261018.log`,
  `/tmp/exp-mesh-html-regression-20261018.log`,
  `/tmp/exp-mesh-pattern-regression-20261018.log` (86/86; not skipped).
- Color Matrix integration/export/import/resource regressions still pass:
  `/tmp/exp-mesh-matrix-regression-20261018.log`.
- Unsigned app and EXPThumbnail build pass:
  `/tmp/exp-mesh-editor-final-build-20261018.log`. Existing warnings remain.
- **Actual isolated native app:** numeric X 35% → 40% → one Undo → 35%, and
  four points → Add fifth → one Undo → four. Saved JSON independently confirms
  both, stable point data and unchanged artwork bounds. Restart/reopen retains
  the Mesh and values. Controls fit the 250-point paint popover; eight buttons
  use a four-column grid. Selected-point extent/handle chrome is visible.
  Native evidence: ignored `output/a11y/visual-features-20261018/mesh-controls.png`
  and `mesh-controls-ax.txt`. No-op formatted commits are guarded to avoid empty
  Undo steps. This copy predates the final selected-state trait/seed unification
  and outline/curved-frame rendering refinements, which subsequently compile/check.
  A CUA coordinate drag did not establish a document edit; physical center/radius
  drags, drag cancellation/Undo, color-picker grouping, menu/context activation,
  large interface type and full keyboard/VoiceOver remain owner checks.

Only the agent-owned sandbox fixture and generated document were used. Its bundle
identity/preferences are isolated, updater feed/checks are disabled, document type
registration is removed, and the parent has no network entitlement. The owner's
running app/documents were not stopped or changed. No push/deployment/live changes.

Native accessible labels and selected-state trait were checked against
[Apple accessibilityLabel](https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)-1d7jv)
and [isSelected](https://developer.apple.com/documentation/swiftui/accessibilitytraits/isselected).
They describe contents/state without repeating native control roles. This is not
full AT certification; exported ARIA/semantic host mappings are unchanged.
