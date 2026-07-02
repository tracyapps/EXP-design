# Canvas Performance — Session 161 Handoff

**Date:** 2026-07-02 (Sessions 161–161g, one long perf push)
**Status:** In progress — one fix awaiting verification, one feature designed but not built.
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
**Safety valve:** a capture over 250ms (`blitCaptureBudget`) sets
`panZoomBlitDisabled` for the rest of the run and logs it — the beach ball can
never return; worst case is the old live-render behavior.

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
- **Content drawing being slow offscreen**: disproved by buckets — shadows
  1.1 + images 6.8 + text 0.9 + shapes 11.4 + boards 1.1 + makeImage 0.1
  ≈ 21ms of a 745ms render. The cost was always layer allocation.

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
3. **Then the drag-overlay blit — THE remaining complaint.** In the final
   log, drag frames run 45–105ms (~10–20fps); this is the "moving things
   still a little laggy" the owner reports. Everything needed for the fix
   now exists (cheap capture, invalidation pattern). Design:
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
