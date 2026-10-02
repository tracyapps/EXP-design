# PERF-009/010/011/012: stress-document editing and wall rendering

Owner requested this bounded v2.6 performance pass on 2026-10-01. Implementation,
source checks and isolated native checks pass. The owner confirmed faster icon
selection/movement/fills and accepted the full-wall navigation fix, closing
PERF-012 on 2026-10-01. Remaining PERF-009 editing checks retain their status.

## Workload and reproduction

Initial fixture `/Users/tapps/Desktop/test2/perf-tests-2.5/stresstest.design` was 298,243,643 bytes
(284 MiB), with one page, one artboard, 231 top-level layers, 3,323 page nodes,
28 images, 23 pattern sources, and 169 top-level icons named `np_*`.
Owner reproduction in public v2.5/build 16: marquee the icon cluster, move the
selection, change every icon's fill, deselect; each causes seconds of beachball.
Pan/zoom can also feel slow. The document models the owner's real workflow of
retaining variations, references and many candidate vectors in one file.

Read-only inventory and initial selection profiling used the installed app.
All implemented-build document edits used disposable copies under `/tmp`.
The original remained byte-identical to the untouched verification copy during
the initial pass. The owner has since edited the document; later rendering tests
use the preserved `/tmp/exp-wall-verification.design` with the green SVG present.

## Findings and changes

The installed Release app's 20-second main-thread sample caught repeated
`RightPanel.selectionTransformIDs`, `selectionDocNodes`, `selectedResolvedNodes`,
ancestor searches and union calculations during SwiftUI layout. Every Inspector
field could search the entire tree separately for every selected icon.

Independently, the canvas `.nodes` drag loop called `updateNode` for each icon.
That function publishes a model mutation and reflows the complete tree. A single
169-icon mouse event therefore did this work 169 times.

- `NodeTreeIndex.swift`: one read index per editable-tree revision, retaining
  parent chains, translation offsets and accumulated ancestor rotation. Shared
  selection snapshots retain exact selections, roots, style descendants and
  lazily evaluated selection bounds. Batch mutation visits the tree once.
- `MainWindow.swift`: the Inspector's fields reuse those reads; style changes
  use a batch traversal through the existing recursive style mutation rule.
- `CanvasView.swift`: node/ancestor lookups reuse the index. Drag positions are
  calculated through existing flip/rotation mapping before one batch update,
  one layout reflow and one model publish per mouse event. Gesture undo remains
  in the existing funnel.

Cache keys include document identity, model generation, canvas page, editing
scope and active component state. Camera changes keep the cache warm. Selection
changes replace selection reads; model edits/undo invalidate all relevant reads.
No document schema, saved artwork, export rendering, accessibility control,
appearance setting, public release artifact or project version was changed.

## Measured code paths

Optimized Swift benchmark on the actual saved document, run after integration:

| Work | Prior algorithm | Updated algorithm |
| --- | ---: | ---: |
| 20 sets of Inspector selection/style/bounds reads | 5,104.2 ms | 6.7 ms |
| One 169-icon move update, including layout reflow | 205.5 ms | 2.2 ms |
| Bulk fill tree traversal | 35.9 ms | 1.3 ms |

An earlier read benchmark measured 5,141.3 → 2.8 ms. Variance in tiny cached
operations is expected. These figures isolate code paths: they do **not** measure
whole-app input latency, frame rate, save time, image memory, or total fill latency.
The move benchmark excludes publish/SwiftUI costs; the implementation also removes
168 redundant publishes. The read baseline reproduces the previous recursive
selection/ancestor/style/bounds reads, not every individual Inspector property.

Complete sorted-key JSON encodings of the resulting page trees match for both
old/new move and fill algorithms, including all image data and unrelated nodes.

## Verification receipts

```sh
bash scripts/verify_node_tree_performance.sh \
  /Users/tapps/Desktop/test2/perf-tests-2.5/stresstest.design
bash scripts/verify_canvas_pages.sh
bash scripts/verify_backlog_ids.sh
xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' \
  -configuration Debug -derivedDataPath /tmp/exp-stress-perf-build \
  CODE_SIGNING_ALLOWED=NO build
git diff --check
```

All passed. The node-tree suite covers nested selections, ancestor order/offset,
rotations/flips, parent+child deduplication, missing ids, style descendants,
batch mutation, and invalidation on revision/page/scope/state/document/selection.
The canvas-page suite checks persistence, migration, ownership and duplication.
Fresh unsigned Debug build succeeds across the scheme's app and dependencies;
existing concurrency warnings elsewhere remain outside this slice.

Native checks passed in a temporary copy of the Debug app named **EXP Performance
Test**, with a unique temporary bundle identifier to avoid automation choosing
between two processes sharing EXP's normal bundle identity. This adjustment is
only in `/tmp`; project and installed app identities are unchanged.

- At 14% zoom, marquee selected **169 shapes** (confirmed in the Inspector).
- Drag preserved all 169 selected and updated X/Y together.
- Fill `#32A6D3` visibly recolored the full icon cluster.
- Deselect returned the Inspector to “No selection.”
- Pan moved the scene in both directions and returned it.
- One Undo restored all icon fills; another Undo restored the move.

The original selection sample lives at `/tmp/exp-stress-selection-before.sample.txt`;
updated selection/navigation samples at `/tmp/exp-stress-selection-after.sample.txt`
and `/tmp/exp-stress-navigation-after.sample.txt`. The latter used a Debug build
and a different window size, so sample counts are diagnostic evidence rather
than directly comparable performance numbers. The previous hot Inspector walks
ceased to dominate; remaining samples include rendering, layer-panel ancestry
reads and menu-model lookups. Tool action durations include automation waits and
are deliberately not reported as application timings.

## Owner gate and limits

Rebuild/run the normal v2.6 app in Xcode; repeat the owner's original sequence
several times on this file. Include trackpad pinch and pan through the detailed
SVGs/photos, undo/redo, multi-page and source/pattern editing, and nested selections
in everyday documents. No full-document 60fps claim or all-documents performance
claim is made. Detailed artwork rendering may have separate remaining costs;
profile any residual stall before selecting the next optimization.

PERF-009 has partial owner verification (icon selection/move/fill improved). No further document-mutating slice
starts before this gate clears. Existing changes to
`scripts/verify_svg_pattern_import.sh` and `.zcodeignore` were preserved.

## PERF-010: full-wall follow-up

Owner feedback after rebuilding: icons select, move and recolor quickly, but
zooming out to the complete wall still causes lag and movement delay. This
follow-up changes only canvas rendering within the authorized performance pass.

The running Xcode Debug app was sampled at 4% while panning the original document
without editing artwork. `/tmp/exp-stress-wall-before.sample.txt` shows path
construction and `nodeSilhouette` beneath active canvas drawing. Every curve's
anchor and two controls separately accessed observable `app.zoom`/`panOffset`,
registering those reads repeatedly in the surrounding observation context.
Every closed path also built a silhouette before content drawing, even when
there were no effects consuming it.

`bezierPath` now reads camera values once per path and applies the same arithmetic
to every point. `drawNode` obtains a silhouette only for drop shadows, inner
shadows or enabled noise with positive amount. Dissolve and layer blur do not
consume it. Mask and background-blur callers still obtain their own silhouettes.
No new raster preview, loss of vector detail, saved-data or export change.

Fresh Debug benchmark compiles the actual private production path builder,
extracted from `CanvasView.swift`, against an independent copy of the prior
builder. The camera uses Swift Observation; timing runs inside observation
tracking to exercise the sampled mechanism. On the real file's 2,729 paths,
ten geometry passes (content plus formerly discarded effect outlines) measured
**1,555.2ms before → 182.1ms after, 8.5× faster**. Built path command count
fell from 1,539,970 to 774,540 because unused outlines are skipped.

Exact path-command/control-point/closure/winding comparison passes for every
stress-file path at 1%, 4%, 14%, 100% and 375%, plus empty, single-anchor, open,
curved, multi-contour and nil-camera fixtures. These numbers exclude paint,
rasterization, effects, images, ownership/culling and UI scheduling. They do
not establish full-frame latency, frame rate or gesture smoothness.

```sh
bash scripts/verify_canvas_path_performance.sh \
  /Users/tapps/Desktop/test2/perf-tests-2.5/stresstest.design
xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' \
  -configuration Debug -derivedDataPath /tmp/exp-stress-perf-build \
  CODE_SIGNING_ALLOWED=NO build
```

Both pass; logs are `/tmp/exp-stress-wall-benchmark.log` and
`/tmp/exp-stress-wall-build.log`. The rebuilt isolated **EXP Wall Performance
Test** app opened `/tmp/exp-wall-verification.design` and rendered the full
wall at 2%, including photos and complex patterns. Camera field changes and
overview rendering were verified visually. Native pan/drag attempts repeatedly
failed with `windowNotFoundAtPosition`, even after selecting by the unique
temporary bundle id and moving only the test window to the built-in display.
The after sample (`/tmp/exp-stress-wall-after.sample.txt`) includes these failed
attempts, so it is not a comparable gesture benchmark. After-patch pan/drag
smoothness, pinch and effect/mask visual acceptance remain owner gates.
The isolated test app was closed afterward. SHA-256 comparison confirmed the
original stress file and the untouched test copy remained byte-identical.

Rebuild the normal app in Xcode. Repeat full-wall pan/pinch and move a selection
at overview zoom; zoom into vectors and check effects/masks in everyday docs.

## PERF-011: residual full-wall pan/zoom and development-run overhead

Owner verified another improvement after PERF-010, but still sees small beachballs
most times. Clarification: full-wall zooming/panning is the remaining trigger.

Profiles of the actual Xcode Debug process show substantial Core Animation frame
presentation/raster work after `CanvasNSView.draw` returns. The 45-second sample
covering a 2%→3%→2% overview zoom sequence is
`/tmp/exp-stress-validation-on.sample.txt`: max inclusive branch counts are 163
for EXP draw, 4,919 for transaction flushing, 2,576 for the CA raster worker, and
204 beneath `MTLDebugCommandBuffer.renderCommandEncoderWithDescriptor`. Branches
overlap and must not be summed or interpreted as whole-frame/FPS measurements.
The earlier `/tmp/exp-stress-residual-before.sample.txt` also shows Metal debug
wrappers and repeated image-rectangle command encoding. Native pan attempts had
window-routing errors; verified zoom field changes provide the live reproduction.

A process environment check printed only a fixed allowlist of debug keys and
confirmed `MTL_DEBUG_LAYER=1`. Xcode was validating framework Metal rendering.
[Apple documents API Validation and its environment controls](https://developer.apple.com/documentation/xcode/validating-your-apps-metal-api-usage).
The scheme's absent setting defaults to enabled; the shared Run action now has
`enableGPUValidationMode="1"`, which means **disabled**, as established by
[CMake's Xcode scheme writer](https://fuchsia.googlesource.com/third_party/cmake/+/0897d4438f39787e29b796500af52369279c9ecd/Source/cmXCodeScheme.cxx).
The setting can be deliberately re-enabled via Xcode's Run → Diagnostics when
investigating Metal usage. Ordinary Debug compilation/main-thread checking and
Release Profile/Archive are preserved. This is a development-run correction;
installed public apps already run without Xcode injecting this validation layer.

Fresh unsigned Debug build succeeds (`/tmp/exp-stress-residual-build.log`). Parsed
scheme XML confirms the launch flag and configuration. `git diff --check` passes.
The running process was not stopped; it retains its old launch environment until
the owner uses **Stop → Run**. No post-relaunch improvement claim is made yet.
Compare full-wall pan/zoom again after relaunch before selecting another renderer
optimization. If stalls remain, profile that process without the debug layer.

A native pattern-tiling experiment was rejected: the SDK's one-operation tiled
image API changed low-zoom sampling on transparent/asymmetric patterns. Twenty-four
bitmap comparisons found mean channel differences as high as 21/255. Its code and
temporary verification scripts were removed; `PaintRender.swift` and
`ExportRenderer.swift` have no remaining diffs. The trial log is
`/tmp/exp-pattern-tiling-benchmark.log`. A performance win cannot justify silently
changing the owner's artwork.

## PERF-012: the green wavy SVG's dense pattern fills

Owner reports that navigation delay disappears when removing the very large
green wavy SVG. This narrows the remaining trigger beyond PERF-011's development
configuration overhead; that earlier change alone did not solve the lag.

The preserved fixture's `jagged-alternations` root contains six 30-anchor wavy
paths. Its nominal root frame is 2,000×1,500 document points, but its child group
extends roughly 12,770 points vertically. Each tall path repeats a 40×40 tile
through a rotated/scaled pattern transform. Counting the **actual rotated bounds**
through the existing `PaintRender` tile-loop formula gives **60,099 tile draws**
for the six fills per redraw. The earlier rough frame-based estimate of 30,000
understated these bounds. This work persists when zoomed out: the loop counts
document-space tile intervals, rather than the small destination footprint.

`CanvasPatternRasterCache.swift` rasterizes the existing explicit tile loop into
a stamp at the destination's actual device-pixel grid, using the same resolver,
source image, pattern transform/origin and clip path. Each eligible fill then
submits one image to the destination canvas. This avoids changing tile sampling
to the native tiled-image API rejected in PERF-011.

- Dense plain closed path fills only: at least 1,024 repeated tiles and no more
  than the existing 40,000-per-fill limit. Canvas traversal disables the cache
  for a node or ancestor with effects, masks, non-unit opacity, non-normal blend,
  rotation/flips or an instance's cropped viewBox. These retain existing drawing.
- Each stamp uses integral device bounds, two pixels of padding and no image
  resampling. Cache identity includes node id, revision, source tile identity,
  reference, normalized path/winding, dimensions and complete pattern lattice.
  Integer-pixel pans reuse the stamp; fractional pans and changed zoom rebuild
  it at the new pixel grid. A 32 MiB LRU limits retained images; stamps above
  1,048,576 pixels or 2,048 pixels on either side use the original renderer.
- Document identity/generation, scope, page and component-state keys invalidate
  changed artwork, including edits and undo. Geometry remains editable and
  strokes use the existing renderer. No saved-data, shared paint renderer,
  export renderer, accessibility/appearance setting or release artifact changes.

The optimized benchmark compiles the production cache together with the real
pattern resolver/rasterizer and existing paint/stroke implementations. It decodes
the actual stress file's green artwork, including its overflowing descendants.
Twenty complete six-path fill+stroke passes in a 1,024×1,024 bitmap measure:

| Work | Original | Canvas stamp | Ratio |
| --- | ---: | ---: | ---: |
| Repeated 4% view | 401.1ms | 9.6ms | 41.9× |
| Integer-pixel pan sequence at 4% | 391.2ms | 9.5ms | 41.0× |
| Changing 2%→3.9% zoom | 383.4ms | 383.3ms | 1.0× |
| Cold revision on every render at 4% | 393.0ms | 394.9ms | 1.0× |

These are **CPU bitmap render measurements**, excluding Core Animation frame
presentation, other wall layers and UI work. Cold/zoom rendering still performs
the tile loop and costs about 19ms/pass; its destination submission now uses six
fill images rather than 60,099 tile-image commands. GPU/presentation improvement
is not quantified here, and these results do not establish full-app FPS or pinch
latency. Fractional pan also rebuilds stamps and can retain that CPU cost.

Eighteen real-artwork pixel comparisons cover 2/4/13% zoom, 1×/2× backing and zero,
integer or fractional pan. Maximum channel difference is **3/255**, with a full
image mean at most **0.01118/255**. At 13%/2×, size limits deliberately retain the
live renderer and pixels match exactly. Additional asymmetric transparent tiles
on light/dark backgrounds, changed source tiles, geometry, winding and lattice,
revision changes, missing resolver and sparse-pattern bypass pass. Transparent
fixtures differ by at most 1/255. The test allows a bounded 4/255 maximum; the
stamp's extra premultiplied 8-bit compositing step is not pixel-identical.

```sh
bash scripts/verify_pattern_raster_performance.sh /tmp/exp-wall-verification.design
bash scripts/verify_canvas_pages.sh
bash scripts/verify_backlog_ids.sh
xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' \
  -configuration Debug -derivedDataPath /tmp/exp-stress-perf-build \
  CODE_SIGNING_ALLOWED=NO build
git diff --check
```

All pass. Benchmark/build/page receipts are `/tmp/exp-green-wave-benchmark.log`,
`/tmp/exp-green-wave-build.log` and `/tmp/exp-green-wave-pages.log`.
The isolated **EXP Green Wave Test** opened the preserved full-wall copy, showed
2%→4%→2% zoom with the green SVG present, and panned 100 points out/back with the
pattern visibly following the artwork. Native pan succeeded this time. The test
app was closed afterward; original app/document were not edited or stopped.
Automation action durations include internal waits and are not app timings.

Owner acceptance, 2026-10-01: “great. that is much better. we can mark that
resolved.” **PERF-012 is owner-verified and resolved**, closing the reported
green SVG/full-wall navigation issue. This acceptance does not imply additional
owner tests of pattern editing/undo, vector detail, masks or effects; their
source/native verification evidence remains as recorded above. PERF-009's
remaining editing acceptance stays open. No separate validation-setting gain
or full-app FPS measurement is attributed to the owner's confirmation.
