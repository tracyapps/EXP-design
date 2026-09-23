# EXP [design] v2.5

## Paint, everywhere—and a Sanaa that does the busywork.

EXP [design] 2.5 finishes the paint model: any paint—solid, gradient, or
vector pattern—can now be a fill or a stroke, patterns import from SVG as
live editable tiles, and mask groups export correctly to every surface. Sanaa
learns the cleanup work it was always meant for: bulk restyles, renames,
token application, and spacing normalization as consented, undoable batches.

### Patterns, as a first-class paint

- SVG `<pattern>` fills import as real, editable pattern paints—the generated
  background files designers actually meet round-trip as patterns, not
  flattened images or a single flat color. Percentage lengths (`width="100%"`)
  and gradient `href` stop inheritance that used to blank these files now
  import correctly.
- Any shape's fill or stroke can be a pattern (or gradient) from the
  inspector's paint editor, and it renders identically on canvas, in SVG, in
  the Handoff Package, and in raster export.
- Each pattern anchors its own way: artwork-anchored patterns ride the layer
  they paint, while imported shape-anchored (`objectBoundingBox`) patterns
  keep their authored behavior—and the choice is per pattern, in the
  inspector.
- Patterns save into the Design Language, apply from it, and import across
  documents.
- A vector pattern survives SVG export as a true `<pattern>` definition that
  browsers and Preview render live—where most professional tools rasterize
  pattern swatches on SVG export or drop them entirely.

### Strokes are paints now

- Gradient and pattern strokes, on every shape, authored from the same paint
  editor fills use—on canvas, in SVG, and through the path geometry of the
  Handoff Package.
- Documents from every earlier version open unchanged; solid strokes keep
  their exact rendering, and Outline Stroke converts a gradient-stroked shape
  into an outline carrying the same paint.

### Mask groups export as masks

- A masked group now exports masked: SVG gains a real `<clipPath>` built from
  the authored silhouette, and the semantic HTML handoff clips through the
  same silhouette via CSS `clip-path`—one definition shared by every export
  surface.
- The shape that defines a mask no longer appears as a real filled shape over
  the content in exports. Its fidelity row states whether the clip used its
  exact outline or its bounds rectangle.

### Sanaa: cleanup and repetitive work

- New consented, undoable batch operations for the tedious parts: restyle
  every layer matching a predicate (`restyleNodes`), apply a Design Language
  token by value (`applyToken`), snap spacing to a scale
  (`normalizeSpacing`), and rename by rule—find/replace, prefix, suffix, or
  sequence (`renameNodes`).
- The permission sheet now shows what a batch will do before you allow it:
  how many layers change, what scope the request covers, and a plain warning
  when a change reaches a component source ("every placement of it updates").
- Every batch reports exactly what it did—matched, changed, skipped, with
  sample layer names—and remains one named Undo step. Token application sets
  values without creating links, and says so.

### Export and workflow fixes

- The export panel remembers format and size separately, with an explicit
  scale control (0.5×–4×).
- Vector paths with a gradient or pattern stroke export to CodePen and the
  Handoff Package with the paint intact.

### Honest limits

- An exported mask renders correctly in browsers and Preview, but re-imports
  into EXP unclipped until SVG `clip-path` import lands (tracked).
- Sanaa bulk operations edit document layers and component sources; the
  internals of a placed component instance are never edited by a bulk op—an
  instance changes as a whole layer or through its source.
- Design tokens omit patterns rather than mislabel them: the W3C token format
  has no pattern concept, and extending it would break the format's promise.
- Browser rendering remains the SVG conformance target.

EXP [design] 2.5 is build 16 and requires macOS 26.2 or later.
