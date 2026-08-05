# Web / SVG Native-Fidelity Inventory

Status: first audit, 2026-08-03. This is a prioritized design/import backlog,
not a promise to reproduce every CSS property or execute arbitrary source code.

## Product rule

When imported web or SVG content uses a visual capability EXP cannot author:

1. Keep source geometry, text, and semantics editable.
2. Map the capability to a native paint, effect, mask, typography, transform,
   or layout control when a coherent EXP concept exists.
3. Preserve ordering and parameters even when the friendly UI needs an
   Advanced disclosure.
4. Report the exact unsupported capability and location until it is native.
5. Rasterize only the smallest irreducible subtree, never the whole SVG/page,
   and label that fallback explicitly.

Do not expose every SVG filter primitive as an undifferentiated top-level
effect. Common concepts should have humane controls; an Advanced Filter Stack
can preserve/order the lower-level graph for expert use and round-trip fidelity.

## What EXP can already author

- Solid, multi-stop linear, and simple centered radial fills.
- Uniform/per-corner radius; inside/center/outside solid, dashed, or dotted
  strokes.
- Whole-layer opacity and the standard separable/non-separable blend modes.
- Drop shadow, inner shadow, Layer Blur, noise, and dissolve effects.
- Editable vector paths/primitives, groups, affine rotation/flip, and native
  shape masks.
- Rich text runs with face, size, weight/style through the font face,
  color/underline, alignment, tracking, case, and line height.
- SVG gradients, transforms, `symbol`/`use`, the supported filter chains above,
  and repeating SVG CSS backgrounds through editable tile groups.

## P0 — highest import value

These are common enough to justify native authoring during v2.2 rather than
accumulating raster fallbacks.

### Effects / filters

- [ ] **Color Adjust / 4×5 Color Matrix.** Native matrix storage plus friendly
      brightness, contrast, saturation, hue rotation, grayscale, sepia, invert,
      opacity, and channel-mix presets. Import general SVG `feColorMatrix` and
      the equivalent CSS `filter()` functions; export the exact matrix. Keep an
      Advanced 20-value editor for uncommon channel work.
- [ ] **Component Transfer.** Per-channel linear, gamma, table, and discrete
      transfer functions (`feComponentTransfer` / `feFuncR|G|B|A`). Friendly
      Levels/Gamma controls first; advanced curves/table editing later. EXP's
      dissolve implementation uses one narrow internal transfer today but cannot
      author the general effect.
- [ ] **Standalone Morphology.** Editable dilate/erode (Expand/Contract) with
      radius. Shadow spread already uses this idea internally; expose it as a
      content effect and map general `feMorphology`.
- [ ] **Displacement.** Scale plus X/Y channel selectors and a source (noise,
      image, or another layer), mapping `feDisplacementMap`. This is high value
      for SVG textures, glass/distortion, and organic effects, but must have
      bounded raster working surfaces.
- [ ] **Ordered filter pipeline.** Preserve the order and named inputs/results
      of imported filter operations. Current `Effect[]` ordering is enough for
      simple independent effects but not multi-input SVG graphs. Add an Advanced
      Filter Stack/graph payload before implementing primitives whose meaning
      depends on another primitive's result.

### Paint / SVG structure

- [ ] **SVG Pattern Paint.** Preserve `<pattern>` as an editable reusable tile
      (children + view box + transform + repeat) instead of substituting a flat
      fill. This is a primary logo/background/texture requirement.
- [ ] **Layered fills/backgrounds.** Multiple solid/gradient/image/SVG fills on
      one layer, each with opacity, blend, clip/origin, size, position, and repeat.
      This maps CSS's comma-separated background layers without manufacturing
      overlapping anonymous boxes. Single SVG background layers work today.
- [ ] **Full clip-path and mask import/export.** Map SVG `<clipPath>` to the
      existing editable shape-mask model. Add alpha versus luminance mask mode,
      nested/intersecting clips, object-bounding-box units, and SVG export. Map
      CSS `clip-path` and `mask-image` when their sources are supported.
- [ ] **Gradient geometry fidelity.** Radial focal point/radii, gradient
      transforms, user-space versus object-box units, spread method
      (pad/reflect/repeat), repeating gradients, and conic gradients. Preserve
      interpolation color space where it materially changes the result.
- [ ] **Stroke fidelity.** Explicit line cap/join/miter, custom dash array and
      dash offset, vector-effect/non-scaling stroke, paint-order, and SVG marker
      start/mid/end. Keep EXP's Dash/Dot presets as shortcuts, not as the only
      representable values.
- [ ] **Fill/clip winding.** Retain `fill-rule` and `clip-rule` (`nonzero` /
      `evenodd`) per shape and contour instead of assuming one winding rule.

### CSS appearance

- [ ] **Multiple box/text shadows.** EXP effects already stack; extend HTML
      parsing beyond the first `box-shadow`, preserve inset/order, and add
      `text-shadow` as a text/layer effect.
- [ ] **Border and outline fidelity.** Independent side widths/colors/styles,
      double/groove/ridge/inset/outset where worth preserving, outline + offset,
      and `border-image`/nine-slice as a reusable border paint.
- [ ] **Foreground filter mapping.** Map CSS `blur`, brightness, contrast,
      grayscale, hue-rotate, invert, opacity, saturate, sepia, and drop-shadow
      to Layer Blur, Color Adjust, opacity, and shadow effects rather than one
      generic unsupported `filter` row.
- [ ] **Performant backdrop blur.** Re-enable the existing Background Blur model
      only after its rendering path no longer forces expensive whole-scene
      readback. Map CSS `backdrop-filter` once the native effect is safe.

## P1 — important fidelity, after the P0 model foundations

- [ ] **Composite/blend graph operations.** General `feBlend` and
      `feComposite`, including arithmetic composite coefficients and multi-input
      chains. Prefer named friendly blend/combine controls with the raw graph in
      Advanced.
- [ ] **Convolution kernels.** `feConvolveMatrix` for sharpen, edge, emboss, and
      custom kernels. Useful but less common than color/displacement.
- [ ] **Diffuse/specular lighting.** `feDiffuseLighting`, `feSpecularLighting`,
      distant/point/spot lights, surface scale, and lighting color. Treat these
      as a Lighting effect assembled from native controls.
- [ ] **Filter image/tile/flood sources.** General `feImage`, `feTile`, and
      `feFlood` as inputs in the advanced filter pipeline. A standalone flood is
      usually better represented as a fill.
- [ ] **Filter regions and color processing.** Preserve filter primitive
      subregions, edge behavior, `color-interpolation-filters`, and clipping so
      blur/shadow edges do not crop or shift color unexpectedly.
- [ ] **Embedded SVG images.** Preserve SVG `<image>` as an editable linked or
      embedded image node, including data URLs and aspect-ratio behavior.
- [ ] **SVG text structure.** Multiple positioned `<tspan>` runs, baseline
      shifts, text anchors, text-on-path, writing direction, and percentage/em
      units. Convert to outlines only by explicit user action.
- [ ] **Typography expansion.** Variable-font axes, OpenType features,
      strikethrough/overline and decoration style/thickness/offset, word spacing,
      paragraph indents/spacing, baseline shift, text stroke, gradient text,
      and vertical writing. Preserve unknown font axes in metadata even before
      every axis has a custom UI.
- [ ] **Affine/3D transforms.** Native skew and arbitrary 2D matrix first.
      Perspective/3D transforms may remain a clearly reported flattened pose
      until EXP has a coherent 3D editing interaction.
- [ ] **Color spaces.** Preserve Display-P3, Lab/LCH, and OKLab/OKLCH source
      colors and gradient interpolation instead of coercing every source to sRGB.

## P2 — specialized or deliberately bounded

- [ ] `feDropShadow` direct import (can decompose into EXP shadow controls),
      advanced edge modes, and additional future Filter Effects primitives.
- [ ] Paint servers or filters with cyclic/external references: preserve source
      metadata, block unsafe loads, and require an explicit trusted local asset.
- [ ] CSS generated content/counters/list markers beyond the current measured
      pseudo-element capture.
- [ ] CSS shapes, exclusions, multi-column fragmentation, vertical/ruby text,
      and uncommon print-specific visual properties.
- [ ] Animation/transition/keyframe import. Default remains a captured static
      state plus an Import Report note. Component states/Storybook args are a
      better editable abstraction than importing arbitrary timelines blindly.
- [ ] Canvas/WebGL/video/animated-image internals. Preserve the measured box,
      semantics, poster/current-frame preview, and source receipt; do not claim
      the imperative drawing program is editable vector geometry.

## Import telemetry before implementation

- [ ] Normalize every unsupported web/SVG feature to a stable capability key.
- [ ] Count occurrences and affected painted area across checked-in synthetic
      fixtures plus owner-supplied local fixtures (never check third-party source
      into the repository without permission).
- [ ] Record whether each occurrence caused missing pixels, an approximation,
      or metadata-only loss.
- [ ] Use that evidence to order P0 work. Frequency alone is insufficient: a
      single missing logo/mask can matter more than hundreds of harmless style
      declarations.

## Adjacent source connectors: what actually transfers

| Source | Reuses rendered importer | Adds useful identity | Safe first boundary | Write-back reality |
|---|---|---|---|---|
| Local/Chrome-saved folder | Yes, complete now | File/resource receipt | User-selected folder | No source binding unless authored ids/manifests exist |
| Public static page URL | Yes | Usually none | Non-persistent session, bounded navigation, explicit origins | Visual import only; DOM pixels do not identify source expressions |
| Static/published Storybook | Yes | Strong: story id, title, args, argTypes, tags, parameters | `index.json` + isolated story render; local static build first | Args/tokens can become patches; component source still needs provenance |
| GitHub repository | Not by itself | File/commit paths, if a manifest supplies them | User-selected local checkout or prebuilt artifact; do not execute an unknown repo in-app | GitHub can carry a branch/PR, but framework-aware code transformation is separate |
| CodePen 2.0 | Deployed preview or exported `dist/` can render; exported ZIP also carries `src/` | Pen/version, real filesystem, config, paths and processors | Export-first via POST-to-Prefill; import user-exported ZIP; narrow deployed URL later | New-Pen handoff is supported; no general authenticated file CRUD, so do not promise update-in-place sync |

**Owner decision (2026-08-03):** defer unrestricted arbitrary-URL import as a v2.2
gate. Build Storybook import on the controlled rendered-source seam first, then add
narrow published-source modes only for connectors that prove useful (hosted
Storybook and, later, deployed CodePen are the first candidates). Keep authenticated
sites and general web crawling out of scope. The privacy/session work is reusable;
the dynamic-site tail is not, and none of it solves source-code write-back.

Write-back should begin with stable, reviewable data: design tokens, Storybook args,
explicitly bound source properties, semantic Handoff diffs, and a branch/draft PR.
Never infer a destructive JSX/template rewrite from anonymous rendered geometry.

## Interop provenance layer

Two-way component work needs a hidden, versioned `CodeBridgeManifest` in the EXP
document, not a user-visible note and not executable code in the canvas renderer.
It preserves connector/source/revision identity, framework and build metadata,
file/resource hashes, Storybook or CodePen configuration, EXP-node-to-source/token/
DOM bindings, behavior contracts, and opaque source/config/JavaScript that EXP does
not understand. Credentials remain in Keychain and never enter the document.

Sync must compare the imported baseline, current design and current source. EXP
patches only explicitly owned, high-confidence bindings; preserves opaque behavior;
and presents conflicts instead of overwriting either side. First write-back targets
are tokens, CSS custom properties, Storybook args and bound content/style values.
Framework-aware structural transforms are later adapters. The rendered importer
therefore stays useful across framework generations—including legacy enterprise
Angular/AngularJS output—even where direct source write-back is unavailable.

## Standards used for this inventory

- [W3C Filter Effects Module Level 1](https://www.w3.org/TR/filter-effects-1/)
- [W3C CSS Masking Module Level 1](https://www.w3.org/TR/css-masking-1/)
- [W3C CSS Backgrounds and Borders Level 3](https://www.w3.org/TR/css-backgrounds-3/)
- [W3C CSS Images Level 4](https://www.w3.org/TR/css-images-4/)
- [W3C CSS Color Level 4](https://www.w3.org/TR/css-color-4/)
- [Storybook framework feature support](https://storybook.js.org/docs/configure/integration/frameworks-feature-support)
- [Storybook publishing and Component Publishing Protocol](https://storybook.js.org/docs/sharing/publish-storybook)
- [Storybook portable stories](https://storybook.js.org/docs/api/portable-stories/portable-stories-jest)
- [GitHub repository contents API](https://docs.github.com/en/rest/repos/contents)
- [GitHub App permissions](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app)
- [CodePen API boundary](https://blog.codepen.io/docs/api/)
- [CodePen 2.0 launch and filesystem](https://blog.codepen.io/2026/07/23/two-point-oh/)
- [CodePen POST-to-Prefill API](https://blog.codepen.io/docs/api/post-to-prefill-pen/)
- [CodePen Prefill embeds and 2.0 payload boundary](https://blog.codepen.io/docs/embeds/prefill/)
- [CodePen 2.0 files and configuration](https://blog.codepen.io/docs/pens/files/)
- [CodePen deployment](https://blog.codepen.io/docs/pens/deployment/)
- [CodePen exports](https://blog.codepen.io/docs/pens/exporting/)
