# v2.7 visual features — owner scope October 18, 2026

Selected release additions: **Mesh fill (FEAT-033)** and **Duotone / Color Matrix
(FEAT-073)**. These supersede FEAT-033's earlier deferrals. They are implementation
targets, not shipped capabilities or marketing claims. No pricing/tier assignment
is implied. Existing free editing/exports stay available.

## Sequence and dates

Internal targets, America/Chicago. The release remains conditional on all gates.
Owner capacity remains 12 planned hours/week plus up to 3 hours contingency.

| Dates | Codex work | Owner review / exit gate |
| --- | --- | --- |
| Oct 18–20 | Source inventory; shared matrix/image-engine foundation and bounded pixel/color-space/alpha proof; native/CSS/SVG representation examples for Mesh. Editor integration follows. | Notes FEAT-072 accepted Oct 18. About 1 hour used for that review gate. |
| Oct 20–23 | First vertical slice: Color Matrix model → native image rendering → SVG export/import → Duotone and advanced controls. Shared thumbnail and package coverage. | Use owned raster/SVG images, transparency, save/reopen, Undo, keyboard and narrow panels. About 2 hours; acceptance precedes Mesh integration. |
| Oct 26–30 | Mesh fill model/render/export and EXP-authored round-trip, then point controls/handles and numeric editing. | Owned non-square, clipped/transformed and patterned/component documents; preview performance and export comparison. About 2–3 hours. |
| Nov 2–6 | Repair observed failures; finish both feature matrices, real-document demos and accessibility evidence. | Nov 6 scope/date review. If time or fidelity fails, agree a revised scope/date; do not silently drop either selected feature or waive a gate. |
| Nov 9–13 | Regression/fidelity fixes and freeze preparation. | Accepted demo, actual keyboard/VoiceOver and 1x/2x review. No new feature expansion. |
| Nov 16 / 20 / Dec 1 | RC review / conditional release / campaign. | Existing privacy, account, legal, paid-offer if applicable, signed packaging and real update gates remain. |

The new work uses the original plan's early implementation capacity because font,
signup and account foundations advanced early; it does not consume every remaining
owner block. Reserve roughly 2–3 hours/week for these visual reviews, 4 for AT and
core verification, 3 for account/onboarding/legal work and 2 for interviews/marketing.
Adjust with actual results; reviews must not become an unbounded queue. Optional
clip-path expansion and BUG-017 export work follow the selected features and core
gates, rather than competing for the same review block.

## FEAT-073 — Duotone / Color Matrix first

Everyday controls: Shadows color, Highlights color and Strength, with identity
reset and enable/disable. Advanced: all **20 coefficients** of the 4×5 matrix,
with sliders and exact numeric fields. Use output-channel groups that fit the
existing narrow inspector; do not squeeze twenty tiny unlabeled fields across it.
Each value gets its full output/input-channel name and a numeric keyboard route.
Finite imported values outside the convenient slider range must survive unchanged.

Default duotone maps brightness between two RGB colors and preserves original
alpha; it must not put opaque rectangles around transparent images. Source images
remain intact, with edits stored non-destructively. Define strength as an explicit
matrix interpolation with identity, rather than stacking an unrelated opacity.

The implementation must resolve these seams before enabling controls:

- **Color math:** choose/document the working space for authored presets. W3C
  matrices operate on non-premultiplied channels; premultiplication and clipping
  still matter in native image buffers. Explicitly export the chosen filter color
  space. Imported sRGB versus linearRGB cannot silently use the wrong math.
- **Pipeline:** current EffectsRender/export paths group effect kinds rather than
  evaluate an arbitrary ordered SVG filter graph. Decide where Color Matrix runs
  relative to dissolve, blur, shadows and noise, then match every output. Do not
  turn this into a filter-graph rewrite or touch parked BUG-034 work.
- **Import:** begin with bounded standalone/unbranched matrix chains that can be
  represented exactly. Preserve coefficient order/space. Unsupported inputs,
  branching and other primitives retain accurate Import Report entries.
- **Rendering:** reuse bounded image work and caching; never allocate buffers
  proportional to zoom squared or do an uncapped offscreen redraw per slider tick.
  Preview throttling may coalesce gestures, but saved/exported values remain exact.
- **Reachability:** Effects Add action, menu/context routes and validation, Inspector
  controls; one Undo per gesture, cancel/no-op unchanged, copy/paste and component
  state behavior consistent with other effects. Keyboard and VoiceOver are gates.

Source seams: `Model/Document.swift` Effect codec; `Color/EffectsRender.swift`;
`Canvas/CanvasView.swift`; `Export/ExportRenderer.swift` and semantic exporter;
`Model/SVGImporter.swift`; `Model/RenderedHTMLImporter.swift` filter reporting;
existing Properties effect editor and menu/action validation. Shared model/render
dependencies must remain in app and thumbnail targets.

Evidence: independent known-pixel identity/channel/bias/duotone/alpha cases,
negative/out-of-range coefficients, finite-value handling, sRGB/linearRGB distinction,
real native versus browser SVG pixels, PNG/PDF/SVG and save/reopen round-trip,
actual imported example, old-document unchanged goldens and stress/memory receipts.
Do not mark this complete from a CPU formula or a Core Image-only probe.

## FEAT-033 — Mesh fill second

Keep the owner's August 19 representation: **solid base plus an ordered stack of
radial color points**. Each point has a stable ID, position, radius, color and
opacity. The feature's UI name can be Mesh; the documentation must accurately
describe the layered-radial behavior. A Bézier patch mesh is outside this scope.

First prove common compositing: the same positions, elliptical/circular radius
definition, falloff, alpha, working color space and layer order in Core Graphics,
CSS background layers and SVG radial-gradient layers. Fade each point to the same
RGB at zero alpha to avoid accidental dark fringes. Do not assume browser and
native interpolation agree without measured pixels.

Then expose a base-color control, point list and add/remove/reorder actions,
on-object placement/radius handles, and synchronized numeric X/Y/radius/opacity
fields. The existing command-coverage rule applies; no drag-only authoring route.
Use a measured point-count/resource budget, per-gesture Undo and stable caches.
Old solid/linear/radial/pattern paints must retain their original decode/rendering.

Source seams: `Model/Paint.swift` representation/codec; `Color/PaintRender.swift`;
fill popover/Properties and canvas gradient editing; SVG/CSS/semantic exporters;
SVG and rendered-HTML import; Design Language paints, state overrides, stroke
policy and shared thumbnail target. Inventory every exhaustive Paint switch.
Do not silently treat a mesh stroke as a solid or flatten its points on save.

EXP's own SVG/CSS exports must retain enough safe metadata to reconstruct editable
points, alongside standards-readable visuals. Specify the exact metadata and
sanitization contract before coding. A third-party stack may legitimately remain
editable layers; do not guess it is a Mesh fill or claim universal mesh re-import.

Evidence: opaque/translucent points, base-alpha, order/radius edits, non-square
and rotated/clipped carriers, fill/background and explicit stroke policy,
duplicate/components/states/library, one-step Undo and save/reopen, real browser
CSS/SVG versus native pixels, PNG/PDF and EXP-authored re-import, stress-document
interactive performance and transparent edge inspection.

## Current evidence and limits

**Current integration:** editable FEAT-073 is implemented/local checked and awaits
owner acceptance. `COLOR-MATRIX-VERIFICATION-v2.7.md` is the current contract,
including ordering, native/raster budgets, SVG graph/region/image limits, native
UI receipts and remaining owner checks. Earlier probe/foundation text below is
historical and does not describe the final exposed feature state.


Initial October 18 source inventory, before integration, confirmed:

- Paint currently supports solid, linear/radial gradient and pattern references;
  it has no Mesh representation.
- Effect.Kind has shadow/blur/noise/dissolve, no Color Matrix effect. SVG import
  recognizes matrices only inside turbulence chains. General matrix support is
  explicitly reported as unsupported by rendered-HTML import.
- The native/export pipeline groups kinds; its existing sRGB SVG filter setting
  does not establish Core Image matrix parity or imported linearRGB support.
- The old inventory's Color Adjust request is broader than this selected slice:
  general component transfer/displacement/all CSS filter functions remain later.

First independent rendering probe is complete:
`bash scripts/probe_visual_color.sh` compiles a standalone Core Image-only program.
It compares software-rendered explicit-sRGB matrix results against direct
non-premultiplied-channel calculations on nine known premultiplied RGBA pixels
(black/white/gray, primaries, transparent and half-alpha edges). Identity, channel
swap, duotone, signed bias and alpha scaling all pass: 45 pixel comparisons, maximum
one 8-bit channel value error, tolerance two. The image is only 9×1 pixels; no owner
image/document, large allocation, GPU-only path or production renderer is involved.
It does not establish SVG/browser, linearRGB, color-profile or app integration parity.
Log: `/tmp/exp-visual-color-probe-20261018.log`; per-pixel JSON:
`output/a11y/visual-features-20261018/core-image-matrix.json` (ignored local receipt).
The probe deliberately remains separate from shipping Effect/Paint types.

### Shared image-engine foundation — October 18

At foundation commit `8122c8b`, `ColorMatrix` lives beside `Effect` in the always-shared Document model;
`EffectsRender.colorMatrixImage` accepts immutable CGImages/mips. Both compile
into the app and thumbnail target. This is the first implementation seam, **not
an exposed editor feature**. No Effect.Kind, document field, effect ordering,
SVGImporter support, actual exporter or inspector control is changed yet.

- Exactly twenty finite Double values; malformed SVG number lists, wrong-length
  JSON, NaN/infinite edits and invalid coefficient indices are rejected. SVG
  decimal strings and JSON preserve finite values outside convenience ranges.
  The standalone SVG-value initializer defaults to linearRGB; authored duotone
  uses sRGB and an identity alpha row. Strength interpolates with identity.
- Per-primitive clipping, explicit color profiles and full-float intermediates.
  Rendering is eager to avoid retaining deferred filter graphs. An additional
  chain of channel swaps followed by large signed cancellation exposed a
  **239-byte reference error** with half-float intermediates. The same check
  passes with full float; this is a real reduced regression, not an owner crash.
- Nonidentity work rejects images over **4,194,304 pixels**, dimensions over
  **4096**, or chains over **32** primitives before filtering. Identity returns
  the exact source object without allocation. A backend coefficient magnitude
  over 4096 returns an explicit error; the finite model value still survives
  JSON. The editor must surface resource/backend errors, never silently draw
  an unchanged source and claim success. Integration must choose a documented
  preview mip/export strategy rather than dropping these guards.
- Evictable NSCache has a 64 MiB cost target and 32-entry target, accounting for
  retained source plus final output. Keys include source identity, every value
  and working space. Entries retain their source to prevent address-reuse hits.
  These are cache targets, not a measured hard process-memory ceiling.

`bash scripts/verify_color_matrix.sh [optional-JSON-receipt-path]` compiles the
actual shared model/renderer and runs an LSUIElement AppKit/WebKit fixture.
**13 cases × 10 known RGBA pixels** pass against independent straight-channel
math and actual WebKit-rendered SVG. Maximum channel error is **1/255** for both
comparisons. Cases: identity, channel swap, duotone, signed bias, alpha scaling,
alpha bias, RGB halving in sRGB versus linearRGB, per-primitive clipping, mixed
spaces, large signed coefficients, intermediate precision and all twenty nonzero
coefficients. Additional checks cover codec validation, zero-strength identity,
alpha preservation, source immutability, cache reuse/separation and resource
rejection. SVG pixels use a standards fixture constructed from the matrix values;
**they do not pass through EXP's SVG exporter/importer**.

Logs: `/tmp/exp-color-matrix-20261018.log`; reduced half-float failure:
`/tmp/exp-color-matrix-precision-before-20261018.log`. Ignored per-pixel receipt:
`output/a11y/visual-features-20261018/production-matrix.json`.
Final checks also pass (exit 0): `bash scripts/verify_effect_export_coverage.sh`
(`/tmp/exp-matrix-coverage-final-20261018.log`),
`bash scripts/verify_semantic_html_package.sh`
(`/tmp/exp-matrix-semantic-20261018.log`) and unsigned app/EXPThumbnail build
(`/tmp/exp-matrix-build-final-20261018.log`). Existing project warnings remain.
No claim of integrated canvas/PNG/PDF fidelity, real-image/stress performance,
profile/display coverage, narrow-panel layout, Undo or accessibility acceptance.
Those remain FEAT-073 gates. No owner test is requested for this hidden foundation.

Owner accepts FEAT-072 notes and BUG-073/074 repairs October 18: “that all is
verified working now.” See `NOTES-UNDO-VERIFICATION-v2.7.md`. Production sequence
is now **Color Matrix → accept → Mesh**. Full physical AT/display certification
remains a separate release gate.

Specification sources reviewed October 18:
[W3C color matrix](https://www.w3.org/TR/filter-effects-1/#feColorMatrixElement),
[filter color space](https://www.w3.org/TR/filter-effects-1/#color-interpolation-filters-property),
[CSS radial gradients](https://www.w3.org/TR/css-images-3/#radial-gradients),
[Apple CIColorMatrix](https://developer.apple.com/documentation/coreimage/cicolormatrix).
These are design constraints, not app, browser-parity, performance or AT proof.

No release feature is checked complete by this planning document. Public claims
and demo assets follow accepted builds. No production document mutation starts
while the preceding owner verification remains pending.
