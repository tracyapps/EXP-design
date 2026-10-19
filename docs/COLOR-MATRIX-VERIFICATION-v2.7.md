# Duotone / Color Matrix — v2.7 owner review

October 18, 2026 · FEAT-073 · development 2.7/build 18.
Implemented and locally checked; **owner acceptance remains open**. Mesh follows
this review, per the repository's sequential verification rule.

## Try it

1. Select an image (or a shape/group). Properties → Effects → **+ → Duotone /
   Color Matrix**. The same action is in Edit and the selection's context menu.
   Change Shadows, Highlights and Strength; zero strength restores original color.
   Swatch alpha is intentionally unavailable: duotone preserves image alpha.
2. Open **Advanced: 20 coefficients**. Every output channel has RGBA weights and
   an offset, with sliders and numeric fields. Sliders cover −2…2; exact numeric
   values beyond that interval remain stored. Editing a coefficient or working
   space switches to Matrix mode. Choosing Duotone explicitly starts its preset.
3. Reset to Identity and Undo. Drag a slider and confirm one Undo restores the
   whole drag. Color-picker sessions also group into one document Undo. Disable
   and enable the effect; duplicate/copy effects; save, close and reopen.
4. Compare transparent images in SVG, PNG and PDF. Also try your actual photo,
   a component/source state, a group, narrow Properties, and your usual displays.
   Keyboard/VoiceOver and Large interface type remain owner/release checks.

No source-image bytes are rewritten. Optional effect fields preserve old-document
encoding; new documents keep coefficients, working space, region and duotone
settings. An imported matrix opens in Matrix mode rather than guessing swatches.

## Ordering and limits

Color Matrix runs **after the older shadow/blur/noise/dissolve family**, in the
order of the Color Matrix effects, before the layer's opacity, blend and transform.
It changes the finished appearance of images, shapes, groups and instances. This
is a bounded effect pipeline, not a general SVG filter-graph evaluator.

The default evaluation region extends 50% beyond each layer-frame edge. Imported
supported regions remain explicit. Very large shadows/content outside that region
can clip; include those cases in owner review. Alpha-generating offsets operate
on transparent pixels inside the region too. The SVG exporter uses explicit
user-space regions; for positive alpha offset it supplies a transparent
`feFlood`/`feMerge` input so measured WebKit output includes the full region.
Without that input the integrated alpha-offset test differed by 51/255 outside
the artwork; with it, the case agrees exactly and re-imports.

Preview captures are limited to 4 MP and reduce resolution when necessary. PNG/JPG
uses the selected scale for matrix rasterization; PDF uses model-point resolution.
Raster export **does not downsample to evade its limit**: a filter capture over
16 MP or 8192 pixels on an axis fails the export. The app does not write a blank
PDF or quietly omit the filter. SVG retains the coefficient literals. Native
coefficients above ±4096 are preserved but show a warning and unavailable preview;
reduce them to render natively. At most 32 matrix effects can be added per layer.
Simultaneously live captures have aggregate limits of 8 MP for preview and 32 MP
for export, so deeply nested/large stacks can hit a limit earlier. A failed native
preview shows a red crossed region rather than the original, unfiltered artwork.
These are work/cache budgets, not a measured hard process-RSS guarantee.
Pattern-tile captures use their actual viewBox-to-pixel mapping. A matrix failure
inside a pattern fails the outer PNG/PDF export instead of painting a fallback
color and reporting success. Ordinary missing-pattern fallback is unchanged.

Floating-point processing is tiled at 1024×1024; there is no full-layer float
buffer. Source/output capture bitmaps and the evictable 64 MiB layer cache remain
bounded. Cache keys include document generation, canvas/source scope, page/state,
ancestor path, offsets, sampling scale and editing context. Image-decode and noise-
tile completion invalidate the cached pixels. Matrix captures request image mips
for their own pixel density, independent of the viewport crop.

Semantic HTML/CSS continues to report enabled effects as visual fallbacks and
keeps the editable data in design.json. This change does not add CSS filter support
or claim that a semantic Handoff package visually reproduces these filters.

## SVG import contract

Supported: finite 20-value `type="matrix"` filters on positive axis-aligned
carriers with unit carrier/group opacity; linear, unbranched matrix chains with implicit input or explicit preceding
results; explicit sRGB/linearRGB (including inherited filter color space); default
object-bounding-box percentage/fraction regions, or explicit numeric user-space
regions. EXP's transparent-input prelude is recognized as an equivalent bounded
chain. Embedded ImageIO-readable data-URI images remain editable, including ordinary
meet placement and `preserveAspectRatio="none"`; no image URL is fetched.

Branches, other matrix types, arbitrary primitive subregions, inherited filters,
user-space percentage regions, non-unit SVG carrier/group opacity, and
rotated/skewed/reflected matrix carriers are
outside this first importer slice. Direct SVG import shows notes for unsupported
matrix graphs/carriers; rendered-HTML imports carry those warnings in their report.
Existing editable geometry is retained, with the unsupported filter omitted.
The older SVG reader bakes inherited group opacity into leaves; supporting matrix
composition through that path needs a separate group-compositing repair. Native
layer opacity and its visual SVG/raster export remain supported.
Image transforms/crops beyond the bounded image reader remain unsupported. Do not
claim arbitrary third-party SVG equivalence from the successful fixtures below.

## Fresh local evidence

- `bash scripts/verify_color_matrix.sh [optional-JSON-path]`: 13 known-pixel
  cases × 10 samples still pass against independent math and real WebKit SVG.
  Actual ExportRenderer PNG/PDF versus its own SVG: identity, duotone, linear RGB
  and alpha offset agree exactly; stacked matrices differ by at most 3/255.
  All five SVG exports re-import and render identically to their native originals.
  Horizontal and vertical 1024-pixel tile boundaries pass in 1280×32/32×1280
  group fixtures (tolerance 4/255). Matrix-after-noise comparison differs by 1/255;
  appearance copy/paste keeps values and creates independent effect identities.
  Invalid duotone JSON, unsupported graph reporting, oversized/native coefficient
  failures and no-successful-empty-PDF behavior pass.
  Added regressions first exposed silent pattern fallback and then a ceil-rounded
  capture edge: a 6000-point viewBox in a 24-pixel tile must use tile density,
  and the rounded bitmap must map to its complete capture bounds. Both are fixed;
  the real exported pattern agrees with WebKit SVG within 4/255. Invalid matrices
  inside patterns now fail outer PDF and PNG exports explicitly.
  Final log: `/tmp/exp-matrix-final-pattern-pixels-20261018.log`.
- Existing all-effect raster/SVG sweep now includes Color Matrix. Final command:
  `bash scripts/verify_effect_export_coverage.sh`;
  `/tmp/exp-matrix-final-pattern-effects-20261018.log`.
- `bash scripts/verify_svg_pattern_import.sh`: 86/86 existing real-fixture
  pattern import/raster/SVG round-trip checks pass (not skipped).
  Log: `/tmp/exp-matrix-final-pattern-import-20261018.log`.
- `bash scripts/verify_rendered_html_importer.sh`;
  `/tmp/exp-matrix-final-html-import-20261018.log`.
- `bash scripts/verify_semantic_html_package.sh` passes the existing deterministic
  package, manifest/hash and semantic/relationship/mask/CodePen assertions unchanged.
  Log: `/tmp/exp-matrix-release-slice-semantic-20261018.log`.
- Unsigned app and EXPThumbnail build pass; final build log:
  `/tmp/exp-matrix-final-pattern-build-20261018.log`. Existing project warnings remain;
  this is not signed-release or warning-free certification.
- **Actual native UI, isolated signed sandbox copy with no network entitlement:**
  selected the image, edited Strength to 0.5 by keyboard, saved, reset identity,
  then one Cmd-Z restored duotone at 0.5. Expanded all twenty named slider/field
  pairs, entered 3.125 beyond the slider range, saved and independently checked
  the real document JSON. Closed/reopened the file: Matrix mode and altered pixels
  remain. Default-width panel contained the controls. UI evidence is in ignored
  `output/a11y/visual-features-20261018/matrix-advanced-ax.txt` and
  `matrix-advanced.png`. A subsequent label/help refinement removes repeated
  native role words and moves policy help to the treatment picker.
  Edit menu showed enabled add/reset commands; CUA could not invoke its transient
  menu items (stale element handles), so actual Add/menu/context invocation and
  physical slider-drag grouping remain owner checks. This is not reported as a
  failing application command. Only the agent-owned fixture process was stopped.

Native UI coverage is not full VoiceOver/FKA, 1x/2x/light/dark/contrast certification,
real-document stress profiling, or owner acceptance. Do not start Mesh until the
owner accepts this document-mutating slice. Public/release claims remain gated.

References checked: [W3C matrix](https://www.w3.org/TR/filter-effects-1/#feColorMatrixElement),
[primitive regions](https://www.w3.org/TR/filter-effects-1/#FilterPrimitiveSubRegion),
[filter color space](https://www.w3.org/TR/filter-effects-1/#color-interpolation-filters-property),
[Apple accessibility labels](https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)-1d7jv)
and native Slider API/installed SDK. Apple advises descriptive labels without
repeating the control's native role. These are native labels; no exported ARIA
roles or semantic mappings change, and no screen-reader conformance is asserted.
