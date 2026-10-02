# Knife and nested-folder Unite — FEAT-066/067

Owner requested this slice on 2026-10-01 after accepting the full-wall navigation
fix, then amended Knife to follow a drawn stroke, select/cut artwork directly,
include masks/images, and provide a movable straight-line preview. Built,
agent-verified and owner-verified 2026-10-01. Owner: “spectacular. that works
perfectly. exactly how i want. check that all off as verified.” The shared
FEAT-066/067 gate is cleared. v2.6/build 17 and the document schema are unchanged.
This acceptance does not establish a separate formal assistive-technology audit.

## Knife behavior

- **K** activates Knife, now using the requested trial **contact.sensor** icon.
  Click eligible artwork to select it. Drag across artwork to cut along the
  sampled pointer stroke; no curve fitting or smoothing changes its direction.
  Preselection is unnecessary: the tool cuts eligible artwork under the stroke.
  Mouse-up commits once. Escape/tool/context changes cancel a pending gesture;
  **V** returns to Select for moving either piece.
- Properties shows independent **Shapes, Lines, Paths, Images** checkboxes.
  Shapes/Lines/Paths default on; Images defaults off. Shapes means primitive
  rectangle/ellipse/polygon nodes; imported/converted vectors are Paths.
- Scope is **Top layer**, **All within group**, or **All layers / groups**.
  Top layer cuts the frontmost eligible intersected layer. Group cuts intersected
  eligible descendants within that layer's outermost containing folder, including
  nested folders. A root layer without a folder behaves like Top layer. All cuts
  every eligible intersected layer in the current editable page/scope. Prior
  selection does not restrict a freehand cut. Hidden/locked layers and descendants
  of hidden/locked folders are protected.
- Closed vector results are ordinary editable paths, with curves/holes retained.
  Lines and single-contour open paths separate at crossings; existing cubic
  curves retain their original geometry and handles. Endpoint markers stay on
  the original outer ends rather than appearing at every new cut.
- Masked artwork is one atomic target. Selecting its clipping shape for the
  straight command promotes to the enclosing mask. Pieces retain the original
  mask/content inside new editable mask groups, so each piece moves independently.
  A mask is eligible if an enabled type occurs in its subtree; a locked descendant
  protects the entire mask. This avoids cutting clip and content separately.
- Images become editable mask groups around the original pixels. No resampling
  or destructive cropping occurs; each piece retains the original image bytes
  and pixel mapping through nested rotations/flips. Keeping full pixels in each
  piece can increase saved document size. Selection boxes, handles and Inspector
  dimensions exclude hidden content beyond the cut.

## Cut with Line

**Object → Path → Cut with Line…**, canvas context menu and Inspector open an
on-canvas straight preview for the eligible selected layers. It passes through
selection center initially. The dashed extension shows the full cutting axis.

Drag the center or line body to move it; drag an end to rotate it. **Shift** snaps
handle rotation to 45° increments. Properties automatically reveals **X, Y and
Angle** fields: **Up/Down** steps values, **Shift** steps ×10 and **Option** ×0.1,
using the existing numeric-field stepping behavior. Canvas arrows move the line
with the same increments. **Cut**, or **Return on canvas**, applies it; **Cancel**
or **Escape** discards it. Moving/rotating/typing changes only the preview until
Cut. Selection/document/scope/tool changes cancel a stale preview.

The straight command operates on the explicit selection, independently of the
freehand tool's type/scope settings. Ordinary folders are not expanded by Knife;
select their eligible contents instead. Text and component instances cannot be
cut directly. Mask silhouettes composed only of unsupported text/instances also
remain unsupported.

## Geometry and paint boundaries

For an open freehand stroke through a closed shape, begin and end outside that
shape's local bounding box and cross it completely. Interior endpoints do not
invent extensions or cuts. A stroke returning exactly to its start can cut an
interior closed loop; there is no automatic closure or smoothing. Multi-contour
open paths are unsupported. Tangent/miss/zero-length operations do not mutate.
Each side of a closed vector can contain disconnected contours or holes.

Vector pieces inherit fill/stroke values and normal styles. Gradients and
patterns defined relative to shape bounds fit the new piece bounds; continuous
paint placement is not frozen. Strokes follow each newly closed edge. Core
Graphics Boolean normalization can make tiny boundary changes, as it does for
Pathfinder; tests permit membership differences only within a 0.02-document-point
band of the source boundary. Open cubics are split analytically, not flattened.
Images/masked content keep their original content placement under the new clip.

One piece retains the original root ID; additional pieces receive fresh IDs.
Original mask child IDs remain once, and duplicated subtrees receive unique IDs.
Both Knife routes register geometry and selection with structural Undo/Redo and
persist using existing PathShape/group/image/mask data. Tool settings and pending
previews are session state, not saved document content.

## Nested-folder Unite

Select a vector **folder**, then **Unite** in Inspector, Object → Pathfinder, or
the canvas context menu. Closed vectors in nested folders participate; redundant
selected descendants count once. Same-parent selections remain in that parent at
the frontmost consumed position. Across different parents, Pathfinder's existing
scope-root promotion remains. The frontmost selected root supplies identity/name/
metadata and the frontmost vector supplies appearance. Removed child references
are cleaned through the existing anchor cleanup.

Unite requires at least two closed vector leaves. It rejects a selected folder
as a whole if it contains text/images/instances/open paths, hidden/locked/mask
layers, or a consumed folder has a background, enabled effects, opacity or blend
change. It does not silently discard incompatible content. Subtract, Intersect
and Exclude retain their existing direct-shape selection policy.

## Verification receipts

- Mask regression failed before the amendment (`/tmp/exp-knife-amendment-baseline.log`).
  Native image testing also revealed that outline/Inspector bounds still included
  hidden pixels. The added regression failed before fixing painted bounds
  (`/tmp/exp-knife-bounds-baseline.log`) and passes afterward.
  A rotated mask whose content sits entirely outside its clip also failed a
  finite-bounds regression (`/tmp/exp-knife-empty-mask-baseline.log`). Empty masks
  now retain the clip as a finite editing surface instead of rotating null bounds.
- `bash scripts/verify_vector_shape_editing.sh` passes: straight and bent sampled
  cuts, exact closed loops, no invented interior extensions, analytic open cubics,
  lines, masks/clip selection promotion, image bytes/pixel transforms, clipped
  visual/painted bounds (including empty rotated masks), type/scope/protection
  rules, nested group scope, original
  curve/hole/no-op/style/ID cases, recursive Unite and JSON persistence.
  Optional output-path argument generates a disposable native fixture with a
  procedural PNG and an ellipse mask. Final log: `/tmp/exp-knife-final-model.log`.
- `bash scripts/verify_canvas_pages.sh` and
  `bash scripts/verify_node_tree_performance.sh` pass page ownership/isolation,
  duplication/persistence, selection/transform/style parity and cache invalidation.
  Logs: `/tmp/exp-knife-amendment-pages.log`, `/tmp/exp-knife-amendment-node-tree.log`.
- Fresh unsigned Debug `xcodebuild` succeeds with derived data
  `/tmp/exp-knife-amendment-build`; log `/tmp/exp-knife-amendment-build.log`.
  `git diff --check` passes. Existing unrelated compiler warnings remain.
- Disposable native builds verify the contact.sensor icon, K, canvas click selection,
  unselected raster/mask cutting, independent image-piece movement and image
  Undo/Redo. Numeric Up/Down updates values and preview; center drag translates,
  end drag rotates to 90°, Cut splits the ellipse and Undo restores it. Preview
  opens scrolled into view and Cancel leaves the original intact. The final build
  confirms a 90.5-point image-piece Inspector height and matching canvas handles,
  rather than the original 180-point height. All within group cuts both primitive
  shapes across nested folders into four selected paths.
- Earlier native FEAT-067 evidence remains: nested folder → one editable path,
  Undo/Redo, and disabled mixed-folder Unite without loss. Amendment model tests
  rerun this contract. Owner acceptance of Unite is now recorded above.
- Disposable apps were closed; the owner's app/documents were not used or stopped.
  Agent-native coverage did not exercise full hand-drawn curves or every scope/type
  combination; model tests cover bent strokes and the scope/type matrix. Owner
  acceptance clears the feature gate without inventing a per-case test transcript.
  Full VoiceOver/Full Keyboard Access testing remains separately unverified.
- Native naming/keyboard references: [Apple accessibilityLabel](https://developer.apple.com/documentation/appkit/nsaccessibility-c.protocol/accessibilitylabel),
  [Apple keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards/).

## Owner Xcode gate — cleared 2026-10-01

The owner accepted the shared slice. The original test checklist is retained
below for future regressions; it is not an outstanding implementation gate.

1. Rebuild/run. Press K, click-select artwork, then draw a bent cut completely
   across its bounds without preselecting. Try each type toggle and all three
   scopes with overlapping/nested artwork. Move/edit pieces, Undo/Redo, save/reopen.
2. Try a mask and enable Images for a raster. Check the original clip/pixels,
   independent movement and piece dimensions. Images remain masks with full
   original pixels underneath.
3. Open Cut with Line, step X/Y/Angle with Up/Down (also Shift/Option), drag its
   center/end handles, then Cut or Cancel. Check rotated/imported shapes and
   ordinary per-piece gradient/pattern/stroke behavior.
4. Select a nested vector folder and Unite. Check location, stacking, appearance,
   Undo/Redo and rejection of folders containing text or hidden/locked vectors.
   Decide whether the trial contact.sensor icon reads well in everyday use.

The shared gate is cleared; subsequent feature/release scope is chosen separately.
