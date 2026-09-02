# Canvas Performance — Session 161 Handoff

**Date:** 2026-07-02 (Sessions 161–161l, one long perf push)
**Status:** ✅ PHASE CLOSED — all verified by owner stress test (161l).
Final numbers: drag frames 1.5–3.6ms (was 45–105ms), pan/zoom 0.4–0.9ms,
baseline renders 9–35ms at 435 nodes. Remaining non-perf items are listed in
the ROADMAP 161l entry (SwiftUI publishing warning is the top candidate).
**Read with:** ROADMAP.md Progress Log entries 161–161g (same day, newest on top).

This document exists so ANY agent (or the owner) can resume the perf work
without re-deriving anything. Everything below was established by measurement,
not guesswork — several plausible theories died along the way and are listed so
nobody retries them.

---

## 1. The original complaint

Canvas felt "klunky" with many images/layers (~473 nodes, 2 boards, lots of
semi-transparent items, images, text, a few component instances). Two asks:
performance, and the canvas/inspector pixel mismatch (fixed — see §5).

## 2. Architecture added this session (all in `EXP [design]/Canvas/CanvasView.swift`)

**Pan/zoom bitmap blit.** First tick of a pan/zoom gesture renders the scene
once into the reusable offscreen backing (`capturePanZoomSnapshot`), records
zoom/pan/size; subsequent ticks blit that bitmap translated/scaled
(`drawPanZoomBlit`, ~0.7ms/frame, measured). A 0.12s settle timer (`.common`
run-loop mode) restores full vector rendering. Rulers are excluded from the
snapshot and drawn live on top. Snapshot recaptures if mid-gesture zoom drifts
past 1.75×/0.6×. Hooks: `scrollWheel`, `zoom(by:anchor:)`, hand-drag — each
calls `beginPanZoomInteraction()` BEFORE mutating `app.zoom`/`app.panOffset`.
**Safety valve (updated 2026-08-30):** the current budget is 400ms. A slow halo
capture permanently reduces that canvas to viewport-only captures; if one of
those also exceeds the budget, `panZoomBlitDisabled` restores the old live-render
behavior. The reduced mode deliberately does not retry the halo after a fast
viewport capture — that retry loop caused multi-second hitches to return on later
gestures. Budget warnings stay in the diagnostic file and mirror to Xcode only
when hidden Testing Mode is enabled.

**Complex offscreen preflight + drag safety (built 2026-08-31; owner gate open):** the safety valve
cannot interrupt a bitmap render already underway, so it still permits one huge
first hitch when a live-text face has unusually detailed glyph outlines. Before
capture, `textHasExpensiveGlyphOutlines` now measures the actual used glyphs with
CoreText and caches counts by PostScript face + glyph. A ≥600-element glyph or
≥2,000 elements across a text layer selects the existing live-render gesture path
up front. These thresholds separate the measured regression faces (`Prequel Demo`
and `A Love of Thunder`: about 3,900–4,350 sample elements, ≥1,161 in one glyph)
from system text (about 200 / 50) without hard-coding font names.

The font-only diagnosis was incomplete. A live beachball while moving plain squares
sampled at 99.5% CPU inside `captureDragSnapshots`; virtually the whole stack was a
static complex `PathShape` stroke in Core Graphics' antialias coverage rasterizer,
and the capture consumed about 30.7 CPU seconds before returning. Paths at ≥400
anchors now receive the same live-interaction treatment. Drag snapshots preflight
their static subtrees (excluding dragged top-level subtrees), inherit any prior slow
pan-capture verdict, and time below/above layers separately. One layer over 400ms
prevents the second capture and disables drag snapshots for that canvas. See PERF-008.

**Downsampled image cache.** `cgImage(for:targetPx:)` serves power-of-two
"mip" variants via ImageIO thumbnails (`kCGImageSourceShouldCacheImmediately`,
EXIF-aware), NSCache with ~256MB cost limit. A 4000px photo in a 200px frame
no longer resamples the full bitmap per frame. Export keeps its own full-res
path — do NOT route export through this cache.

**Text layout cache.** TextKit stacks (`NSTextStorage`+`NSLayoutManager`+
`NSTextContainer`) cached per node id, validated by a content fingerprint
(`textFingerprint`: runs, colors, size, align, tracking…), cleared on
`resolveGeneration` bump. The stored `storage` reference is load-bearing —
the layout manager does not retain its text storage.

**Drag-warm caches.** `frameOnlyGestureActive` (dragMode != .none) skips the
generation-clear for BOTH the instance-resolve cache and the text-layout
cache during drags. SOUND ONLY BECAUSE: drags mutate node *frames* only, and
`Document.resolvedChildren(of:)` reads sources + overrides, never frames.
If resolve ever grows a frame dependency, remove this. Measured effect:
group drags 320ms → 35–47ms/frame (log shows `instCacheHit 4` during drags;
before the fix it was `instCacheMiss 4` every frame).

**Capture instrumentation (Testing Mode ⌃⌘T).** One-shot buckets printed on
the first gesture of a run: `blit-capture` (total), `blit-render`,
`blit-makeImage`, `blit-shadows`, `blit-images`, `blit-text`, `blit-shapes`
(leaf drawNodeContent; groups/instances excluded so recursion doesn't
double-count), `blit-boards`. Keep these — they are how every root cause
below was found, and how the next one will be.

That Control-Command-T shortcut is historical: the View-menu item and shortcut
were removed from the public UI on 2026-07-19. `AppState.testingMode` is
session-only, defaults off, and is not persisted. Seeing a blit-budget warning
in an older build therefore does not prove Testing Mode was enabled; those
warnings were unconditional until the 2026-08-30 safety-valve repair.

## 3. THE key finding — the transparency-layer rule

> **Never call `beginTransparencyLayer` or `setShadow`+fill without first
> clipping the context to the painter's reach.**

A CG transparency layer allocates its buffer at the size of the CURRENT CLIP.
On-screen the window/dirty-rect bounds it; in ANY offscreen bitmap (snapshot
capture, PNG/PDF export, the thumbnail extension) the clip is the whole
canvas — so every shadowed or semi-transparent node paid a ~screen-sized CPU
alloc + clear + composite (~9ms each; hundreds of nodes = seconds).

Applied in four places (keep all four):
1. `EffectsRender.drawDropShadow` — new `castBounds:` param, clips to caster
   + blur + offset + 8px. Call sites in CanvasView + ExportRenderer pass it.
2. `CanvasView.drawArtboardBackground` — board shadow clips to board + 24px.
3. `CanvasView.drawNode` opacity/blend layer — clips to `paintBoundsView`.
4. `ExportRenderer.drawExportNode` opacity/blend layer — clips to
   `exportPaintBounds`.

`paintBoundsView(_:offset:)` = conservative view-space paint reach: leaf →
frame + `nodeCullMargin` (the existing culling invariant: stroke + shadow +
rotation); group → recursive union of visible children + rotation growth +
2px; instance → its viewBox (canvas instance drawing hard-clips to it).
`exportPaintBounds` mirrors it, EXCEPT export instances union their
*resolved children* — export draws instance children WITHOUT the viewBox
crop (pre-existing canvas/export inconsistency; observed, deliberately not
changed; worth a BACKLOG entry).

**Measured impact — VERIFIED (owner's final 161g log):** capture 3,325ms →
745ms (leaf clip) → **13–75ms typical** (group/instance clip). The blit now
stays enabled for the whole run; `frame(blit)` holds 0.6–2.5ms across pans
and zooms. Occasional capture spikes to ~140–190ms come from `blit-images`
— first-time ImageIO mip decodes when images newly enter view; one-off per
image/zoom-bucket, self-healing, under budget.

## 4. Dead theories — do not retry

- **Pixel format** (premultipliedLast RGBA vs native BGRA): switching to
  BGRA (`premultipliedFirst | byteOrder32Little`) did NOT change capture
  time. Kept anyway (harmless, arguably correct).
- **Colorspace** (sRGB backing vs window's Display P3): no change. Kept
  (backing now uses `window.colorSpace`, rebuilds on change via VALUE
  equality — identity comparison would rebuild every call).
- **Ordinary content drawing being slow offscreen**: disproved by the original
  buckets — shadows
  1.1 + images 6.8 + text 0.9 + shapes 11.4 + boards 1.1 + makeImage 0.1
  ≈ 21ms of a 745ms render. The cost there was layer allocation. Do not generalize
  that result to newly installed decorative fonts: PERF-008 measured a real
  glyph-outline exception and now preflights it before offscreen capture.

## 5. Pixel snap + honest inspector (done, verified working)

Owner's decision: "snap + honest decimals" (Figma-style). Canvas gestures
snap to whole document pixels (`pxSnap`/`pxSnapRect` in CanvasView, applied
in every mouseDragged case + text placement); **⌘ bypasses** (same modifier
that skips smart guides — ⌥-drag was taken by duplicate); smart-guide
alignment runs AFTER pixel snap and wins. `pxSnapRect` floors size at 1.
Inspector `DimField`s use `.fractionLength(0...2)` (truthful decimals,
accepts typed fractions; ⌥-arrows step 0.1); measure HUD matches (2dp).

## 6. CURRENT STATE — what the next agent must do first

1. ~~Verify 161g~~ **DONE.** Owner's final log: capture 13–75ms typical, blit
   enabled all run, `frame(blit)` 0.6–2.5ms. Pan/zoom is solved.
2. **Visual regression pass** (cheap, important): semi-transparent nodes and
   GROUPS still composite identically (no double-darkening, nothing cropped
   — especially group children hanging OUTSIDE the group frame, rotated
   semi-transparent groups); drop shadows unchanged; one PNG and one PDF
   export compared against canvas.
3. **Drag-overlay blit — IMPLEMENTED (161i), needs owner verification.**
   Drag frames ran 45–105ms (~10–20fps). Now: below/above z-split snapshots
   around the dragged top-level subtrees, per-tick blit + live redraw of only
   the dragged nodes + chrome. Perf keys: `frame(drag)` (~1–3ms expected),
   `dragblit-capture` (≈ two frames, once per gesture). Verify with a group
   drag in Testing Mode; also regression-check: nested-child drag, drag while
   scrolling, ⌥-drag duplicate, pen/path-point edits, guide drags (fall back
   to full render by design). Original design notes kept below:
   - At node-drag start (`.nodes`/`.resize`/`.resizeSelection` etc.),
     capture the scene ONCE like the pan blit but EXCLUDING the dragged
     selection (add a `skipIDs: Set<UUID>` param to `renderCanvas`/node
     loop). Capture is now cheap (~ one frame) thanks to §3.
   - Per drag frame: blit that static snapshot (0.7ms), then draw ONLY the
     dragged nodes + selection chrome + smart guides on top.
   - Invalidate on mouseUp / doc change / zoom change (reuse the pan-blit
     invalidation pattern; note pan/zoom during a node drag is possible via
     scroll — simplest correct answer: drop the drag snapshot and fall back
     to full render for that frame, recapture on next).
   - Careful: dragged nodes under a semi-transparent sibling won't
     composite exactly while dragging (acceptable mid-gesture; settle
     restores truth). Owner accepted this class of tradeoff for pan/zoom.
4. **Known smaller items, in rough priority order:**
   - Drag-start spikes (~200–400ms one-off when a drag begins over boards —
     visible in every log; likely `dragBaseline = document.model` copy or
     first-tick capture; measure before fixing).
   - `snap` cost hits 5.5ms/tick with 968 candidates (`snapCands 968`) —
     spatially index or cap candidates if it grows.
   - The ~90× "Publishing changes from within view updates" SwiftUI warning
     (Session 124-era, still open, needs a runtime repro).
   - BACKLOG: export renders instance children unclipped (no viewBox crop),
     canvas clips — decide which is right and unify.

## 7. Verification protocol (what the owner does each round)

Owner builds in Xcode (agent cannot compile — Linux sandbox), runs, toggles
Testing Mode (View ▸ ⌃⌘T), performs: one pan, one pinch-zoom, one group
drag, one complex-vector resize. Pastes the perf log. The log answers:
- `blit-capture` line → is the snapshot path healthy?
- `frame(blit)` present during pan → blit actually being used?
- `instCacheHit 4` during drags → drag-warm caches healthy?
- `frame avg` during drags → the number that must reach ~16ms.

## 8. Gotchas carried forward (from CLAUDE.md, still true)

- Shared files (`Document.swift`, model, PaintRender/EffectsRender/
  ExportRenderer) are in BOTH app and EXPThumbnail targets. This session
  added NO new files — everything went into existing members on purpose.
  If you add a file that shared code references, add it to EXPThumbnail too.
- The Xcode agent "fixes" missing symbols by stubbing code — check
  `Document.resolvedChildren` / `AutoLayoutEngine.reflowed` wiring if
  instances stop re-hugging.
- `ExpDocument.model`'s `didSet` must keep bumping `resolveGeneration` —
  three caches (instance resolve, text layout, and their drag-warm logic)
  depend on it.
