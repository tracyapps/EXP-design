# UX Design Tool — Project Roadmap & Progress Log

A native macOS design application built around an actual UX workflow,
not feature-count parity with Figma/XD. Guiding principle: **the tool
should get out of the way.**

---

## How we work together

See **WORKING-AGREEMENT.md** in this folder for the collaboration rules
(who runs the compiler, how sessions resume, how this file stays the memory).
Short version: Claude writes code, the user runs it in Xcode and reports back;
this file is the source of truth and the Progress Log is updated every session.

---

## The v1 scope (locked)

A fast native canvas with:

1. Pan / zoom / artboards — buttery smooth, this is the whole thesis
2. Shapes + text + layers
3. **Source/instance components** — the one heavy subsystem; built the
   *simple* way (double-click opens source in its own editing context;
   each instance carries per-layer visibility + a small bounded set of
   overrides). Terminology: **"source,"** never "master."
4. Export to PNG / PDF / SVG
5. **Structured artboard notes** — interaction notes, "assumptions,"
   "test this first" — with a handoff export. This is the point-of-view
   feature that makes it *your* tool.

Explicitly NOT in v1: prototyping/interactions, auto-layout/constraints,
plugins, multiplayer, advanced typography.

---

## v1.1 — shipped (2026-07-05)

Tag `v1.1`, build 2. Headline: the **Design Language** system — a per-document
library of colors + gradients (swatch/list views, categories, recents,
JSON + HEX/CSS/Coolors import/export, and a bulk editor in Settings → Document).
Plus an OKLCH, WCAG-AA-aware color picker with local palette suggestions,
transparent PNG export, a System Monospaced document font, sharper raster
imports, the centered document titlebar, and the App/Document Settings split.
Full notes: `RELEASE-NOTES-v1.1.md`.

## v1.2 — shipped (2026-07-09)

Tag `v1.2`, build 3. Headline: **Noise & Dissolve** — stackable, SVG-native
texture effects (grain/noise and threshold-based dissolve on any shape, text, or
group) that round-trip through SVG export and import. Plus a big canvas-interaction
pass: **precise ink-based hit-testing** (clicks hit the actual drawn shape, not its
bounding box; transparent areas pass through to what's underneath), **editing inside
rotated & flipped groups** (move/resize/rotate children correctly, selection chrome
on the ink), pen add/remove-point that targets the right shape and lands on the
curve, **hover field tips** on inspector controls (with VoiceOver hints),
**multi-window action routing** (align/distribute, text-style, zoom-to-fit work when
panels float as their own windows), the **BUG-003** fix (semi-transparent gradients
and shadows no longer darken during pan/zoom or drag), **noise/dissolve pan-zoom
performance** (parallel + async tile generation), and **transparent SVG export by
default**. Full notes: `RELEASE-NOTES-v1.2.md`.

## v1.2.1 scope (setup patch)

Build 4, `MARKETING_VERSION 1.2.1`. Small on purpose: perf fixes + the first
live rehearsal of the Sparkle update pipeline (Phase 20), so the update payload
was low-stakes. v1.3 is the first full Design Language + Sparkle-update release.

- [x] Sparkle app-side integration complete (package added, keys generated,
      public key in Info.plist — see Phase 20).
- [x] **PERF: zoomed-out "flashing" on noise/dissolve-heavy docs.** Root cause
      was the tile cache, not memory: cache hits never promoted in the LRU
      order, so eviction was FIFO — a zoomed-out frame with more live tiles
      than the 48-tile cap evicted tiles still on screen (skip-a-frame flash →
      regenerate → evict others → churn). Fixed: true promote-on-hit LRU;
      byte-budgeted eviction (256 MB, count as safety net) since tiles range
      KBs→8 MB; `tileReadyNotification` coalesced to ≤30/sec so a big warm-up
      no longer rapid-fires snapshot-dropping redraws.
- [x] Owner verify: reload the noise-heavy doc, zoom out, confirm no flashing
      (Testing Mode on; watch for regenerate churn). VERIFIED 2026-07-09 —
      no flashing, frames 1–10 ms (one-off ≤23 ms spikes on full-doc redraws
      only), no EdDSA error in the log (real key accepted).
- [x] Treat the remaining end-to-end update verification as a v1.3 release
      gate, not a v1.2.1 blocker. v1.2.1 did the app-side Sparkle integration
      and first appcast/signing rehearsal; v1.3 does the real previous-build →
      update → relaunch test.

---

## v1.3 — shipped (2026-07-12)

Build 5, `MARKETING_VERSION 1.3`. Public notes live in
`RELEASE-NOTES-v1.3.md`. Primary focus: the **Design Language** system
(Phase 18), component semantics prep (Phase 19a), and Sparkle release plumbing
(Phase 20).

- [x] **Type styles in the Design Language** (kickoff decision 2026-07-09): a
  saved type style captures **everything except color** — face, size, underline,
  alignment, line-height (+unit), tracking, text case. Color stays with the DL
  colors so type + color remain independently reusable. `box` excluded (layout,
  not style). Shares the SAME cross-cutting categories as colors/gradients.
  Built: `TypeStyle` model (tolerant decode) + capture/apply; save from Type
  menu / right-click / DL panel menu; apply via panel double-click, panel
  context menu, and canvas right-click "Apply Type Style ▸"; rename / category
  / update-from-selection / delete in the panel; EXP JSON export/import
  (schema-compatible: `typeStyles` array, old files unaffected) and CSS export
  as `.type-<slug>` classes (font-* only, honestly no color).
  **FUTURE (needs discovery, do not spec yet):** per-style "color notes" /
  variations — a style RECOMMENDING pairings from the color library without
  owning them. Workflow undesigned; revisit after type styles get real use.
  Settings-window editor parity for type styles is also still open (panel is
  the primary surface for now).
- [x] **Component categories → Phase 19a shipped** (see Phase 19 below; boxes
  checked there). Vocabulary = curated ARIA roles, friendly labels shown,
  tokens stored.
- [x] **Tester diagnostics: file-based perf logging** (owner choice: BOTH modes).
  New `UI/DiagnosticLog.swift` (app target ONLY — do not add to EXPThumbnail):
  Testing Mode (⌃⌘T) streams every perf summary + blit-budget warning to a
  per-day rotating log (keep 5) in ~/Library/Logs/EXP [design]/ (sandbox
  container) with an app/macOS/hardware session header; Help ▸ Save Diagnostic
  Report… bundles header + display info + doc stats + geometry audit + log
  tail via NSSavePanel; Help ▸ Reveal Diagnostic Log in Finder. Writes are on
  a serial background queue (`nonisolated` + `@unchecked Sendable` — the queue
  is the isolation); logging never blocks the canvas.
- [x] **Pixel-measurement audit** (owner report: equal-dimension shape+artboard
  "didn't quite line up"). Finding: no transform bug is possible in the math —
  both fills go through the identical `docToView`; equal doc frames give
  identical view rects. The visual mismatch mechanisms are (1) shape strokes
  are CENTERED on the frame (extend strokeWidth/2 outside; artboard hairline
  draws fully INSIDE its frame), (2) the artboard drop shadow softens its
  bottom edge, (3) fractional origins antialias across 2px. Built numeric
  proof: **View ▸ Log Geometry Audit** — logs doc frames + exact view rects
  for the selection (or everything), cross-checks equal-sized pairs, alert
  summarizes MATCH/MISMATCH, details go to the diagnostic log. If it ever
  reports a mismatch, THAT is a real bug. OWNER VERIFIED 2026-07-10: full-doc
  audit (82 objects) passed with zero mismatches. The log also identified the
  original repro's true cause: SVG-imported content carries FRACTIONAL frames
  (e.g. artboard "wrapping-paper-orange-01" is 148×150 at x 3954 while its SVG
  content is 150.781×150.755 at x 3953) — the dimensions were never actually
  equal; the inspector's rounded display made them look it. Closed as
  not-a-renderer-bug.
  Follow-up (owner pulled (a) and (b) into v1.3 same day — see the
  2026-07-10 log entry): stroke alignment and Round to Pixel are DONE;
  (c) rounding SVG-import frames at import time remains an open backlog
  candidate.
- [x] **Stroke alignment (inside / center / outside)** for closed shapes —
  rect, ellipse, polygon, closed/multi-contour paths; lines + open paths stay
  center (no interior). `StrokeAlignment` on each shape payload (tolerant
  decode; default center = legacy). EXACT rendering everywhere: canvas +
  raster export use clip/2×-width (`PaintRender.strokeAligned`); SVG export
  offsets geometry ±w/2 for rect/ellipse and uses clipPath (inside) / mask
  (outside) for polygon/path — no approximations. `strokeReach` (hit-test +
  cull margins) is alignment-aware. Inspector: segmented Center/Inside/Outside
  in the Stroke section, shown only when a closed shape is selected.
- [x] **Round to Pixel** — snaps selected node AND artboard frames (origin +
  size, min 1×1) to whole pixels in one undo step; auto-layout reflows in the
  same step; works in the source-editor scope too. Command coverage: `@objc
  roundToPixelAction:`, Object menu, right-click (nodes + artboards),
  validateMenuItem. The one-step fix for imported-SVG fractional fuzziness.
- [x] **Drop shadow "Preserve transparency"** (owner request 2026-07-10: a
  semi-transparent object went black on its own shadow). Per-shadow checkbox,
  DEFAULT OFF so every existing document renders unchanged; ON knocks the
  shadow out from behind the object (cast only OUTSIDE the silhouette).
  Canvas/raster: `.destinationOut` punch of the TRUE silhouette (spread-0 —
  the spread ring survives) inside the shadow layer; dissolve masks respected.
  SVG: `feComposite operator="out"` against the source alpha — identical
  proportional-alpha semantics. Checkbox sits under the shadow's X/Y/Blur/Spr
  row with a plain-language field tip. OWNER VERIFIED 2026-07-10.
- [x] **Per-corner border radius** (rectangles) — `CornerRadii` (+ CSS overlap
  clamp + CGPath builder) in Document.swift; nil = uniform `cornerRadius`
  stays the default simple control; Advanced disclosure in the inspector with
  TL/TR/BL/BR; auto-collapses to uniform when corners match. Renders exactly
  on canvas, raster export, SVG (arc path), and shadow silhouettes.
- [x] **BUG FIX: convert-to-path dropped corner radius** — rounded rects now
  convert with κ-bézier corner anchors (per-corner aware); conversions also
  preserve stroke alignment.
- [x] **FIX: stroke position picker was multi-select-only** — added to the
  single-selection shape and (closed) path inspector sections.
- Carry-overs still open: Phase 9.5 rich-text editor bug, BUG-004 (centered-title
  rename popover anchor), and the nested-group unified multi-select/transform box
  (still move-only under transformed ancestors).

### Planned next (owner-flagged 2026-07-10 — design the interface first, don't tack on)
- [ ] **Instance navigation:** from a Components-panel row, center the canvas
      on an instance and page next/back through all N of them. The ×N badge +
      select-all shipped as step one; the navigation UI needs a proper design
      pass before building (owner explicitly wants it to not feel bolted on).
      Sketch ideas: expander under the row? prev/next chevrons flanking the
      badge? a HUD once paging starts?
- [x] **Components panel grid view:** second view mode — thumbnails in a grid
      for fast visual scanning (list stays the default). Needs a component
      thumbnail renderer (the EXPThumbnail extension's render path may be
      reusable) + the same EXPSegmented grid/list toggle as the DL panel.
      DONE 2026-07-19 in the v1.6 Components panel redesign.

Follow-up patch release: v1.4 below.

---

## v1.4 — released (2026-07-15)

Build 6, `MARKETING_VERSION 1.4`. Small patch/minor release after v1.3,
focused on the late-found performance culprit. Public appcast/GitHub release
went live and installed v1.3 can discover v1.4, but the first install attempt
exposed a release-archive problem: the published zip preserved forbidden
extended attributes on Sparkle's embedded XPC services, causing strict
code-signing verification to fail after unzip and Sparkle to show "An error
occurred while launching the installer." Fix: strip xattrs from the exported
app, re-zip with `ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent`,
regenerate the appcast signature from that exact archive, replace the GitHub
asset, deploy the updated appcast, then rerun the v1.3 -> v1.4
install/relaunch proof.

- [x] **PERF: Layers-panel recomputation storm fixed.** The multi-second
      beachballs on click/nudge/point-move were `LayersPanel` computed
      properties `groups` and `activeSectionID` being evaluated per row/header
      during SwiftUI List rebuilds. Fixed by computing groups/active-section
      once per body pass and single-pass bucketing nodes by owning artboard.
- [x] **PERF: drag-overlay blit no longer disabled by unrelated gradients or
      shadows.** Static gradient/shadow content stays in the 1:1 drag snapshot;
      only true compositing cases force live rendering.
- [x] **PERF-TODO T1: pan/zoom all-clear sensitivity memo.** Plain/flat docs no
      longer repeat the full scene sensitivity walk on every pan/zoom tick;
      docs with sensitive content still use the precise viewport check.
- [x] **Explicit Reveal in Layers.** Normal canvas selection no longer
      auto-scrolls the Layers panel; View -> Reveal Selection in Layers and
      canvas right-click reveal deliberately expand/scroll on demand.
- [x] **Near-term v2 prep:** top-level `Document.schemaVersion = 1` on new
      `.design` saves, with tolerant decode for existing files.
- [x] Release notes and checklist updated for v1.4/build 6.
- [x] v1.4 appcast published and installed v1.3 sees the v1.4 update prompt.
- [x] Clean local v1.4 archive regenerated with metadata-preserving `ditto`
      defaults disabled; strict deep codesign + Gatekeeper pass after unzip, and
      local appcast regenerated for the cleaned zip bytes.
- [x] Replace the v1.4 GitHub asset and deploy the regenerated appcast, then
      verify Sparkle install -> relaunch; confirm About shows 1.4 / build 6.

v1.5 is now live; local installer-launch failures after that point were traced
to metadata on the already-installed baseline app, not to the public archives.

---

## v1.5 — released (2026-07-19)

Build 7, `MARKETING_VERSION 1.5`. First interop/handoff release. Public
appcast/GitHub release went live 2026-07-19; the live v1.5 zip is
byte-identical to local release/archive copies and passes strict deep
codesign plus Gatekeeper after unzip.

- [x] **Chunk A — Schema + Handoff Package:** documented/versioned
      `design.json` schema, migration policy, package writer, manifest, and
      `README.llm.md`. DONE 2026-07-17: `docs/HANDOFF-SCHEMA.md`;
      `Export/HandoffPackageWriter.swift`; File ▸ Export Handoff Package…
      writes an inspectable `.exph` folder containing `manifest.json`,
      `design.json`, `tokens.json`, and `README.llm.md`.
- [x] **Chunk C — DTCG design-tokens import/export:** Design Language ↔
      `tokens.json` using the stable W3C DTCG shape. DONE 2026-07-17:
      existing export kept; import now accepts pasted/file Design Tokens JSON
      (nested groups, inherited `$type`, color/gradient/typography tokens).
- [x] Candidate small UX carry-over if it fits: **Instance navigation** from
      Components-panel rows. DONE 2026-07-17: compact prev/next chevrons flank
      the existing instance badge; paging selects one instance and centers the
      canvas, while the badge still selects all instances.
- [x] Candidate small UX carry-over decision: **Components panel grid view**
      deferred/absorbed into v1.6 Chunk H. Scope check 2026-07-17: Quick Look
      currently renders artboards only; a real component grid needs a reusable
      component-source thumbnail renderer and belongs with the v1.6 component
      panel redesign/state-preview work.

Not v1.5 unless it becomes urgent: full semantic HTML/CSS export, Figma import,
code/storybook import, boolean ops, rich text root-cause work.

---

## v1.6 — shipped (2026-07-20)

Build 8, `MARKETING_VERSION 1.6`. Component contract release; detail in
docs/V2-INTEROP-PLAN.md Chunk H.

How interaction data round-trips to code without storing implementations:
components carry a three-part CONTRACT — named **states** (override-diffs,
same machinery as instance overrides → CSS pseudo-classes/`data-state`),
**behavior** implied by ARIA role + typed node **relationships**
(controls/labelledby/describedby → real ARIA attributes; WAI-APG pattern
defines the rest), and **motion** as DTCG duration/cubicBezier/transition
tokens (rides Chunk C). JS is never stored — it regenerates from the contract.

Tester-facing v1.6 highlights for `expdesign.app/download#tester-features`:

- [x] Component states: conventional + custom states, source-editor chips,
      active-state editing, per-instance state picker, on-canvas state display,
      and state-aware text/fill/visibility overrides.
- [x] Accessibility surface: component role/category assignment stays visible in
      the source editor, Components panel, and Object menu; per-state contrast
      checks report WCAG ratio + AA/AAA status as the active state changes.
- [x] Components panel improvements: list/grid display, generated thumbnails,
      per-source state previews, category/role filtering, and matching actions
      for open, rename, categorize, instantiate, select instances, and delete.
- [x] Import/media tester notes: PDF import and embedded raster image support are
      ready to include in the next public tester-feature list.

- [x] Model: `states` on component definitions (override-diff per state) +
      schema bump/migration. DONE 2026-07-19: `ComponentState` in
      Document.swift (shared file, no new EXPThumbnail membership needed),
      `schemaVersion` 2 with save-migrates-forward encode, state resolution
      reuses instance machinery.
- [x] Model: typed `relationships` on nodes + "public prop" flag on
      overridable fields. DONE 2026-07-19: `Node.relationships`
      (`controls`/`labelledby`/`describedby`) and `Node.publicProps`
      (`text`/`fill`) added in Document.swift with tolerant decode; schema v2
      docs now describe the behavior-contract spine.
- [x] Components panel redesign: grid view w/ thumbnails (absorbs the
      earlier v1.5 candidate item; EXPThumbnail membership gotcha applies),
      state-preview switcher, room reserved for v2.2 library-sync status.
      DONE 2026-07-19: list/grid toggle (same EXPSegmented pattern as Design
      Language), generated component-source thumbnails in grid cards, per-source
      state preview menus, and matching card actions for open/rename/category/
      create instance/select instances/delete.
- [x] Source editor: states bar + state EDITING (owner mock, 2026-07-19).
      Header cleanup (editable name, banner text removed, category moved
      right), extended ":h" chip row / compact dropdown (persisted), add
      via conventional-names menu + custom, manage mode (rename/reorder/
      delete), text+fill edits captured into the active state's diff via
      ComponentStateEditing at both funnels (canvas commitNodes, inspector
      commitScoped).
- [x] States follow-ups: command-coverage wiring for state actions (menu
      items/shortcuts/validateMenuItem for add + cycle states); per-state
      layer visibility editing (model supports it; Layers-panel eye still
      edits the base); managed frames don't re-hug overridden text in the
      editing preview (instances render correctly). DONE 2026-07-19:
      Object-menu actions + shortcuts route to source-editor canvas
      responders; Layers source scope now applies active state visibility and
      captures eye toggles into `ComponentState.layerVisibility`; source-canvas
      drawing and inspector reads can use state-applied reflow so overridden
      text re-hugs managed frames in preview without using that reflowed tree
      as the canvas commit baseline.
- [x] Inspector: state picker. DONE 2026-07-19 — per-instance
      `activeStateID` dropdown in the instance inspector.
- [x] Inspector: relationship picker. DONE 2026-07-20 — source-editor
      Properties inspector shows `Controls`, `Labelled By`, and `Described By`
      target pickers for a selected source layer, offering only layers from the
      same component source and excluding the selected layer itself. Writes go to
      the base source even while a visual state is active, so relationships stay
      semantic rather than state-specific. Command coverage: Object ▸ Component ▸
      Relationships… plus source-canvas context menu, both validated/greyed out
      unless a single source layer is selected.
- [x] Contrast checks run per-state, not just default. DONE 2026-07-19:
      `ComponentContrastAudit` (SourceEditorWindow.swift) evaluates each text
      layer against the surface it sits on, resolved through the same instance
      machinery states use; a live "Contrast N.NN:1 · AA / below AA" strip under
      the source-editor states bar re-checks as you switch states. Advisory only.

## v1.6.1 — bug-fix stabilization (RELEASE CANDIDATE)

Build 9, `MARKETING_VERSION 1.6.1`. Close confirmed defects after v1.6, led by
the long-standing rich-text commit bug, plus the small owner-approved vector
workflow additions needed to make custom cursors directly in EXP.

- [x] **Rich text: preserve selected-run styling on direct click-out.** The
      inline editor now keeps a stable attributed-text snapshot refreshed by
      every typing/style mutation and commits that snapshot without making the
      `NSTextView` first responder again. This removes the AppKit
      focus/selection lifecycle from the final run reconstruction. Selection
      changes originating outside the canvas now also commit the editor on the
      next runloop tick without stealing the user's new selection. Verified in
      the Debug app with the exact regression: select one word, change 16 → 32
      pt, click directly onto the artboard, reopen, reselect — 32 pt survives.
- [x] **OWNER VERIFIED 2026-07-20:** Repeat the direct-click-out repro in the real document,
      covering word/line/character-level size, color, weight, and underline.
- [x] **Sparkle installer launch for sandboxed builds.** Fresh system logs from
      the installed v1.4 baseline exposed the actual app-wide failure:
      authorization error `-60005`, followed by Sparkle's “Failed to submit
      installer job” and sandbox-integration warning. The app had outbound
      network access (so discovery/download worked) but was missing both
      `SUEnableInstallerLauncherService = YES` and the required
      `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` / `-spki` Mach lookup exceptions.
      Added the installer-launcher key, a checked-in app entitlements file, and
      preflight checks for the complete sandboxed Sparkle contract. v1.6 and
      earlier cannot repair their own missing entitlement, so v1.6.1 requires
      one manual install; automatic-update proof resumes from that baseline.
- [x] **Signed Release entitlement preflight.** A locally development-signed
      universal Release app passes strict deep signature verification and carries
      sandbox, network, user-selected-file, and expanded `-spks` / `-spki`
      exceptions; its Info.plist reports 1.6.1/build 9 and enables the launcher.
- [ ] **OWNER DISTRIBUTION VERIFY:** Direct Distribution must repeat those checks
      on the final Developer ID/notarized/stapled export. After manually installing
      v1.6.1, preserve it as the baseline for the next live Sparkle update proof.
- [x] **Named/batched media import.** Finder SVG and raster filenames (without
      extensions) now become their default layer names. Dragging/pasting multiple
      SVG files imports every file as a side-by-side batch, selects the batch,
      and records one undo step instead of stopping after the first pasteboard URL.
      Native pasteboard verification passed with two named SVG files.
- [x] **Layer names in SVG export.** Every exported node is wrapped in a
      CSS-safe `layer-<slug>` class derived from its layer name. Classes may
      intentionally repeat, avoiding invalid duplicate IDs while remaining easy
      to target or extend by hand. Verified in a real exported SVG.
- [x] **Adobe-style corner rotation.** Removed the top-center rotate notch.
      Hover/drag just outside any of the four bounds corners now uses a rotate
      cursor and delta-based rotation (including existing Shift 15° snapping),
      so starting from a diagonal never jumps the object to an absolute angle.
- [x] **Authored canvas cursors.** Imported the owner-supplied pointer,
      add-point, delete-point, and four corner-rotate SVGs as preserved-vector
      asset-catalog images. Pointer/add/delete use the arrow tip as their
      hotspot; rotate cursors use their center. Rotation chooses an authored
      orientation from the corner's actual view-space quadrant, so the arrows
      keep pointing inward for rotated and flipped objects. All other tool,
      resize, pan, text, and modifier cursors remain unchanged.
- [x] **Inspector geometry coherence.** Single-layer X/Y/W/H now use the painted
      outside edge of Inside/Center/Outside outlines (shadows excluded). Group
      dimensions use the live painted descendant union instead of a potentially
      stale imported viewBox frame; numeric SVG-path resizing now scales its
      actual points/controls as well as its frame. Geometry Audit logs both stored
      and Inspector-outer bounds with the correct stroke-position description.
- [x] **Outline Stroke.** Object ▸ Path ▸ Outline Stroke expands center/inside/
      outside strokes into ordinary editable filled path geometry. Stroke-only
      lines/open paths become one filled shape; a filled+stroked object becomes a
      group containing separate fill and outline paths in the original paint order,
      so resizing scales the former stroke with the artwork. Rotation, flip,
      opacity, effects, blend mode, layer identity, and one-step undo are preserved.
- [x] **Pathfinder essentials.** Object ▸ Pathfinder and the canvas context menu
      provide Unite, Subtract Front, Intersect, and Exclude Overlap. Native
      curve-aware Core Graphics boolean operations preserve Bézier geometry and
      compound contours without a flattening dependency; results are one editable
      path, work across nested/rotated/flipped selections, and undo in one step.
- [x] **VECTOR TOOL VERIFICATION:** Outline centered/inside/outside strokes on filled shapes,
      lines, and curved paths, then resize the result. Exercise all four Pathfinder
      modes with two and three overlapping shapes; Subtract Front uses the bottom
      shape as its base and every selected shape above it as a cutter. Focused
      native geometry smoke coverage passed all operations/stroke positions;
      owner accepted the release scope with no reported issue.
- [x] **OWNER VERIFIED 2026-07-20:** In a real document, drag several SVGs and named raster
      images; inspect an exported SVG's layer classes; rotate narrow/wide objects
      from all corners with and without Shift; compare group/child dimensions at
      several zoom levels and across Inside/Center/Outside strokes.
- [x] **OWNER VERIFIED 2026-07-20:** Check the authored pointer at normal canvas scale; use
      the Pen tool over an existing shape and anchor to see the add/delete
      badges; hover all four rotate corners on normal, rotated, and flipped
      objects. Confirm visual size, arrow-tip/center hotspots, and inward-facing
      rotate artwork feel right in use.
- [x] **Bug sweep complete.** No additional v1.6 regression is open. The general
      backlog's older centered-title popover polish remains a non-blocking P2
      carry-over rather than a v1.6.1 defect.
- [x] **Release-candidate prep.** Release notes finalized; versions fixed at
      1.6.1/build 9; clean universal Release build, Sparkle configuration
      preflight, vector-geometry smoke suite, and production website build pass.
      A signed local `.xcarchive` is prepared in Xcode's local Archives folder;
      strict nested-code verification passes on the archived app.
- [ ] **External distribution:** Direct Distribution, notarize, staple, verify the signed
      app's entitlements/signatures, create the exact Sparkle zip/appcast, publish
      the GitHub release and website, then manually install v1.6.1 as the repaired
      baseline for the next release's automatic-update proof.

---

## v2.0 — Interop & Handoff (PLANNED — anchor doc: docs/V2-INTEROP-PLAN.md)

Owner-set focus (2026-07-14): make EXP the design tool that lets go — hand
work to dev teams, LLM agents, IDEs, or CodePen, and read work back in.
Export/handoff is the spine (decided 2026-07-14); notes + ARIA roles travel
with the design. Full chunk breakdown, risks, and release mapping live in
**docs/V2-INTEROP-PLAN.md**. Summary:

- [x] **Chunk A — Schema + Handoff Package** (documented/versioned design.json
      schema, package writer, manifest, README.llm.md) — v1.5
- [x] **Chunk C — W3C DTCG design-tokens import/export** (Design Language ↔
      tokens.json, standard stable 2025.10) — v1.5
- [ ] **Chunk B — Semantic HTML/CSS export** (ARIA roles → real elements,
      tokens → custom properties, notes → comments; the v2.0 headline demo).
      Include the same bridge in standalone SVG export: when a fill/stroke exactly
      matches a Design Language color, emit/use its CSS custom property while
      retaining a standalone-safe fallback. Do not lose token identity during the
      broader import/export codec work.
- [ ] **Chunk D — Figma import** (REST API path first; .fig best-effort later) — v2.1
- [ ] **Chunk E — Code/Storybook/HTML-CSS import** — v2.2
- [ ] **Chunk F — Agent Bridge** (EXP as a LOCAL MCP server the designer's own
      agent connects to; opt-in, OFF by default; stdio helper + Unix socket;
      no vendor API keys, no fake usage bars) — F1 spine dark in v2.0 →
      F2 **Handoff panel** in v2.1 (named 2026-07-17: one panel for exports,
      packages, AND the agent section; PNG/PDF/SVG surface there too, with
      File ▸ Export menus kept per command-coverage rule) → F3 write-back v2.3+
- [ ] **Chunk G — XD import** (.xd = frozen ZIP-of-JSON; rides the same
      InteropCodec pipeline; proves importers before Figma) — v2.1
- [x] **Chunk H — Component states & behavior contract** (states as
      override-diffs, ARIA relationships, motion tokens; interaction data as
      contract, never JS; components-panel grid redesign) — v1.6 shipped:
      component states, per-instance state selection, per-state contrast checks,
      component role/category assignment surfaces, and Components-panel grid/state
      previews are done. Inspector relationship authoring is now wired. Motion
      token UI remains intentionally deferred to the later Design Tokens /
      transitions authoring pass; the model hook is present.
- [x] Near-term prep (shipped in v1.4): add `schemaVersion` to
      saved .design files so v1.x files self-identify to future readers.
      DONE 2026-07-15: top-level `Document.schemaVersion = 1`, tolerant decode
      for existing files, automatic write on save.

---

## Architecture decisions

- **Language/UI:** Swift + SwiftUI for app chrome (panels, inspectors,
  menus) because declarative UI suits how you think. AppKit/Core Graphics
  (and likely Core Animation / Metal-backed layers) for the canvas itself,
  where SwiftUI isn't the right tool for high-performance custom drawing.
- **Rendering:** Use Apple's own frameworks (Core Graphics / Core Animation,
  Metal where needed). Do NOT build a renderer from scratch.
- **Document model is the foundation.** An instance is a *reference* to a
  source + overrides, never a copy. This must exist from the first lines of
  code — retrofitting it later is a project-killing rewrite. Everything
  else hangs off this model.
- **Export dividend:** PNG and PDF come nearly free from the native drawing
  system. SVG requires walking the document model and emitting markup
  ourselves (you know SVG by hand, so we can make this output genuinely good).
- **Appearance:** use Apple *semantic* system colors everywhere (e.g.
  `.underPageBackgroundColor`, `.windowBackgroundColor`, `.labelColor`) so the
  whole app follows system light/dark automatically. Deliberate exception: the
  **artboard stays white regardless of app theme** — you're designing a screen,
  not theming the tool. Don't "fix" this later by accident.
- **Editor layout, not navigation layout:** the side panels are persistent
  inspectors, NOT a navigation hierarchy. Use `HSplitView` (resizable panes),
  not `NavigationSplitView` (which is built for Mail/Notes-style navigation and
  fights an editor UI). Confirmed via research before building the shell.
- **FLOATING/DETACHABLE PANELS — founding principle (scaffolding-sensitive).**
  The end goal is Photoshop/Illustrator-style independent palettes, not
  edge-locked panels. User runs multiple monitors (incl. a vertical 27") and
  wants to push 90% of panels onto other screens, open many at once side-by-side
  (e.g. Layers + Components together, no forced tabs), and expand the canvas to
  fill a 30" display. Tools strip stays fixed on the left of the main screen;
  everything else is free-floating.
  - Full version is **v2**, BUT the decision is locked now because it changes
    how the window is built. The cheap-now / brutal-later rule applies.
  - **The key architectural move:** every panel is written as a fully
    self-contained `View` that reads/writes **shared app state** and makes NO
    assumption about *where* it's hosted. Then the same panel code can be
    docked-in-main-window (v1, good for single-screen/laptop) OR popped into its
    own floating macOS panel-window on any monitor (v2). macOS already handles
    multi-monitor window placement, so once a palette is its own window, it
    "just works."
  - This is why we introduce a shared **app-state object** early (Phase 1/2)
    instead of scattering `@State` in the window — required for portable panels
    AND needed by the component system anyway.

### Cost map (why the timeline is what it is)
- *Cheap* (sit on the canvas): shapes, alignment/snapping/guides, keyboard
  control, color handling, grids/spacing, export options, opinionated defaults.
- *Expensive* (own subsystem): components/instances ✅ (in v1, simple version),
  auto-layout, prototyping, advanced text, plugins, multiplayer (all deferred).

---

## Build phases (the actual sequence)

### Phase 0 — Project skeleton & first runnable window ✅ DONE
- [x] Xcode project created, runs an empty window
- [x] Basic app structure / folder layout agreed (Model / Canvas / UI groups)
- [x] Confirm Swift/Xcode versions: **Xcode 26.3, Swift 6.2.x, macOS 26 SDK**
- [x] Three-pane editor shell built (HSplitView: LeftPanel · CanvasView · RightPanel)
      with toolbar toggles and a placeholder artboard. Runs correctly.
- App name: **EXP [design]** ("exp"). Location: ~/Dropbox/work/custom-work-tools/apps/
  NOTE: Dropbox + Xcode build folders can occasionally conflict; if weird build
  errors appear, suspect Dropbox syncing build/DerivedData first.

### Phase 1 — The canvas (the make-or-break piece) ✅ DONE
- [x] Introduce shared app-state object (foundation for portable panels + components)
- [x] A canvas view that renders (AppKit-backed)
- [x] Pan (space-drag / trackpad) and zoom, smooth
- [x] Artboards: create, position, render — New Artboard button (⇧⌘N), drag to
      move, arrow-key nudge (Shift = 10pt), drawn crisp in view space at any zoom
- [x] Coordinate system / hit-testing groundwork — doc↔view transform both ways,
      artboard hit-testing, click-to-select with accent halo, Tab cycles
      selection, Delete removes (NB: this is artboard-level; per-layer
      hit-testing/selection still belongs to Phase 3)

### Phase 2 — The document model ✅ DONE
- [x] Core data structures: Document → Artboards → Layers → Nodes
      (`Model/Document.swift`, value types, Codable, UI-free)
- [x] Reference-based design so instances can point at sources later
      (`ComponentSource` + `.instance(ComponentInstance)` carrying `sourceID` +
      bounded overrides + per-layer visibility — references, never copies)
- [x] Save / open a file format that opens *instantly* — native **DocumentGroup
      + ReferenceFileDocument** (`Model/ExpDocument.swift`), pretty-printed JSON
      **`.design`** (extension changed from `.exp` in Session 88/89 — Xcode owns
      `.exp`; legacy `.exp` files still open for migration). Undo-aware `setModel`
      funnel powers ⌘Z AND marks the doc dirty so
      Save works. Sandbox set to `user-selected files: readwrite`. Finder file
      association needs the one-time `Info.plist` build-setting step (see log).

### Phase 3 — Primitives & layers ✅ DONE
- [x] Rectangle, ellipse, line/path, text — rectangle, ellipse, text, and
      **straight line** all done. Line: L tool, drag to draw, 2 endpoint handles
      to edit, stroke color + width in the Inspector, hit-tested by distance to
      the segment. (Full **pen/bézier path** editing is deferred to its own later
      subsystem — out of v1 primitives scope.)
- [x] Selection, move, resize — click-select topmost shape, drag to move,
      8-handle resize, arrow-nudge, delete; one undo step per gesture
- [x] Layers panel: order, visibility, lock, folders/groups — **panel built**
      (`UI/LayersPanel.swift`): grouped by owning artboard + Wall, front-of-stack
      at top, eye/lock toggles, double-click rename, drag-reorder (mapped to
      global z-order), two-way selection sync with the canvas. Multi-select:
      click = replace, **Shift-click = range**, **Option/⌘-click = toggle**
      (anchor in AppState, shared with canvas clicks). **Group/ungroup done**
      (⌘G / ⇧⌘G + context menu; groups render/move/clip as a unit, children stored
      group-local). (Later polish: nested-row display of group children in
      the panel, and group box-resize.)

### Phase 4 — Source/instance components ✅ DONE
- [x] Define a "source" from selected layers — **Create Component** (⌘K +
      context menu): wraps selection into a `ComponentSource` (root group,
      children source-local) and replaces it with an `.instance` node.
- [x] Place instances that reference the source — instances render by resolving
      the source (recursive draw at the instance origin); duplicate/copy-paste
      makes more true instances (clone keeps `sourceID`).
- [x] Double-click instance → edit source in its own context → return, instances
      update — the source-editor window now **really edits**. The canvas is
      scope-parameterized (`.document` vs `.source(id)`); the editor window hosts
      a live `CanvasView(scope:.source)` + its own ToolsStrip + own AppState, and
      shares the document's undo manager (window delegate vends it) so ⌘Z works
      and Save sees the change. Edits to a source update every instance live.
      Polish still pending: an Inspector inside the source window (stroke/font/
      color editing there), and auto-growing the source bounds.
- [x] **Detach Component** (⇧⌘K + right-click) — convert an instance back into
      independent layers (fresh copies of the source's children at the instance's
      position; source left intact for other instances; hidden layers carry over).
- [x] Per-instance layer/folder visibility toggles (the InDesign behavior) —
      expand an instance in the Layers panel to see its source layers, each with
      an eye toggle that's a TRUE per-instance override (`layerVisibility`): it can
      show a source-hidden layer or hide a source-visible one, independent of the
      source; matching the source default drops the override so it inherits again.
      Honored live in render + on detach. (Top-level source layers for now.)
- [x] Bounded overrides (text/color swaps) — per-instance text + fill overrides
      (`InstanceOverride`). Select an instance → Inspector "Overrides" section
      lists the source's text layers (editable text fields) and fillable layers
      (color pickers); each has a reset-to-source button. Applied live in render
      and baked in on detach. (Top-level source layers; nested + stroke later.)

### Phase 5 — Export ✅ DONE
_`Export/ExportRenderer.swift` (rendering) + `Export/ExportPanels.swift` (the
panels). File ▸ Export Selected Artboard… (⇧⌘E) → NSSavePanel with a **Format
popup** (PNG/PDF/SVG); File ▸ Export All Artboards… → folder picker with a
**Format popup (PNG/PDF/SVG/All)** plus a **"Combine PDF pages into one file"**
checkbox. Renders in artboard-local coords._
- [x] PNG export — rasterized from the vector PDF at @2x (crisp; not upscaled)
- [x] PDF export — drawn via a flipped offscreen NSView (vector, correct text)
- [x] SVG export (custom emitter) — straight from the model (SVG is y-down like
      us); rect/ellipse/line/path(bezier)/text/group/instance(+overrides+visibility)
- [x] Format picker accessory in both panels; updates the save panel live
- [x] Multi-page PDF — one page per artboard, merged via PDFKit (`Artboards.pdf`)
- [x] **Export Selected Artboard(s)** handles multiple boards: 1 board → save
      panel; 2+ → folder + format + combine-PDF (shares the all-artboards panel)
- [ ] (later) PNG scale chooser, transparent-bg option

### Phase 5.5 — Artboard improvements ✅ DONE
- [x] **Size presets** — New Artboard is now a split menu (Phone/Tablet/Desktop/
      Web/Square/Story/Slide/A4/Letter); primary click = default. `ArtboardPreset`
      list in MainWindow, easy to extend.
- [x] **Artboard resizing** — 8 resize handles on the lone selected board; Shift =
      proportional. Resizing changes the frame only; the wall rule re-derives
      ownership (shapes don't scale — matches frame-resize expectations).
- [x] **Multi-select artboards** — `AppState.selectedArtboardIDs` (Set);
      `selectedArtboardID` kept as a single-select compatibility wrapper.
      Shift-click a board's label to add/remove; all selected boards draw the
      accent outline; Inspector shows "N artboards selected".
- [x] **Move multiple boards** — dragging any selected board's label moves the
      whole set + every shape each owns (Shift = axis-lock). Arrow-nudge + Delete
      also act on all selected boards.
- [x] **Option-drag duplicates** boards + all their contents (new ids; one undo
      step), then drags the copies — mirrors shape option-drag.
- [x] **Rename artboards** — Inspector name field, double-click the label for an
      inline editor, and right-click ▸ Rename.
- [x] **Marquee = boards when fully enclosed** — a lasso that completely surrounds
      one+ artboards selects the boards; partial drags still select items.
- [x] **Rearrange mode** — with 2+ boards selected, dragging anywhere inside a
      selected board moves the whole set + contents (not the shape under cursor).
- [x] **Copy/paste artboards** (⌘C/⌘V + context menu) — pastes boards + contents.
- [x] **Artboard-aware shape paste** — pasting shapes lands on the focused board
      at the same position relative to it, or centered if it won't fit.

### Phase 6 — Structured notes & handoff ✅ DONE
- [x] Notes attached per artboard (NOT an artboard themselves) — `Artboard.notes`
      (backward-compatible decoder); travels with the board on move/dup/delete.
- [x] Notes UI: SwiftUI `ArtboardNotesOverlay` aligned to the canvas camera — a
      toggle button left of each board's name (muted when empty, accent when it
      has content; no badge), opening a resizable, auto-growing, editable panel
      that expands down-and-to-the-left (off the board). Keyboard + VoiceOver.
- [x] Handoff export "Include notes" — PDF only (single + multi-page); adds a
      Letter "Notes — <board>" page after each board with notes (PPT-style).
- [x] Notes editor is a real multi-line `NSTextView` (`NotesEditor`/`NotesTextView`):
      Return = line break, Tab/Shift-Tab = indent/outdent (4 spaces), bullet lines
      ("•/-/\*") auto-continue (empty bullet ends the list), indentation carries to
      the next line. Plain-text storage → Markdown-ready. Panel size persists per
      board across close/open (`AppState.notesPanelSize`).
- [ ] (later) **Markdown** rendering + styling (headings, bold/italic, highlight);
      batch notes undo (currently per-keystroke like the other text fields)

#### Phase 6 design spec (agreed Session 25)
- **Model:** notes are a property *on* `Artboard` (e.g. `notes: String` or a small
  `ArtboardNotes` struct — likely rich-ish text later, plain string first). They
  are NOT nodes and NOT artboards, so they never appear on the wall, in Layers, or
  in shape hit-testing. Because they live on the artboard, they **move, duplicate,
  and delete with it for free** (artboard duplication already deep-copies the
  struct; multi-move carries it).
- **Affordance:** a small **menu / "more" button to the LEFT of the artboard name
  label**. Clicking it toggles a notes panel that **expands down-and-to-the-left**
  (so it never overlaps the artboard itself). The same button collapses it again.
- **Button state:** subtly differentiated when notes exist vs empty — like the
  difference between a primary and a muted/disabled button. **Not** a badge or
  notification dot; just "slightly more prominent" to signal there's content.
- **Panel sizing:** manually resizable, AND auto-grows to at least the height of
  its text content (never clips the note).
- **Export:** when exporting a board that has notes, offer an **"include notes"**
  option (conceptually like PowerPoint exporting slides with speaker notes) —
  rides on the PDF/handoff path. Plain export stays note-free.
- **A11y/ethics tie-in:** this is the point-of-view feature (fight thoughtless
  handoff). Keyboard-operable toggle + VoiceOver label on the notes button.

---

## Polish roadmap (Phases 7+) — planned Session 30

The owner's polish list, organized by value/effort. Within-phase order is
flexible; the two **BIG** phases (15, 16) and explicitly **lower-priority** items
(blend modes, grid auto-lines, images) are deferred to the end on purpose. Each
phase is independently shippable.

### Phase 7 — Inspector & input polish ✅ DONE
- [x] **Universal numeric stepping** (`NumericStepping` modifier in MainWindow):
      ↑/↓ = ±1, ⇧ = ±10, ⌥ = ±0.1, **hold accelerates** (step grows every 5 key
      repeats). Applied to X/Y/W/H (`DimField`), corner radius, stroke widths,
      font size, and the zoom %.
- [x] **Rename element in the Inspector** — inline "Layer" name field above the
      dimensions (`nodeNameBinding` → setModel "Rename Layer"); the Layers panel
      reads the same model, so it stays in sync.
- [x] **Zoom cluster** (RightPanel): editable % field (with stepping), preset menu
      (Fit, Actual 100 %, 25/50/100/200/400 %), a log-scaled slider, and ± buttons.
      Shortcuts in the View menu: ⌘+ in, ⌘- out, ⌘0 Actual, ⌘1 Fit. Zoom keeps the
      viewport center fixed (`AppState.zoomTo`, fed by `viewportSize` from layout).
- [ ] (later) "Fill" preset; zoom-to-selection

### Phase 8 — Color system & gradients ✅ DONE — refinements planned
**Build 1 ✅ DONE (Session 32) — custom picker + formats + OKLCH + artboard bg**
- [x] **Inline color popover** at each swatch (`ColorWell` + `ColorPopover` in
      `Color/`): saturation–brightness field, hue + alpha sliders, screen
      **eyedropper** (`NSColorSampler`). Replaces the macOS `ColorPicker` everywhere
      (Inspector fill/stroke/text/path + instance fill overrides).
- [x] **Multi-format readout + copy/paste**: a format selector (HEX / RGB / HSL /
      LCH / OKLCH) with one editable, copyable code field; typing a valid code in
      any space sets the color. `ColorMath` does the conversions/parsers.
- [x] **OKLCH (+ LCH) authoring** — convert to sRGB (gamut-clamped) on input; model
      stays sRGB `RGBAColor` on disk.
- [x] **Artboard background color** — `Artboard.background` (backward-compatible
      decoder, default white); rendered on canvas + PNG/PDF/SVG export; Inspector
      "Background" well.
**Build 2 ✅ DONE (Session 35) — gradients**
- [x] **`Paint` type** (`.solid | .gradient`) replaces the `RGBAColor` fill on
      rectangle/ellipse/path + `Artboard.background`. Backward-compatible: a solid
      encodes as a bare `RGBAColor` (old files load unchanged); gradients add a
      tagged object. `GradientFill` = kind (linear/radial) + multi-stop + angle.
- [x] **Rendering** via shared `PaintRender` (CoreGraphics) — identical on canvas
      and in PNG/PDF export. **SVG** emits `<linearGradient>`/`<radialGradient>`
      defs in objectBoundingBox units (one def fits any element size).
- [x] **Gradient editor** (`PaintWell` + `PaintEditor`): Solid / Linear / Radial
      segmented; a stop bar (drag to add/move, select to recolor, delete; min 2),
      stop color + position, and an angle control for linear. Wired into shape +
      path fills and the artboard background well.
- [x] **Gradient as a component fill override** (Session 36) — `InstanceOverride
      .Value.fill` is now `Paint`; the override well is a `PaintWell`. Legacy
      solid overrides decode unchanged.
- [ ] (later) **gradient text fill** (text stays solid for now); **on-canvas
      gradient handles**

### Phase 8.5 — Rotation ✅ DONE (Session 36)
- [x] **`Node.rotation`** (degrees, clockwise about center; defaulted → old files
      load). Rendered on canvas + PNG/PDF export (CTM rotate) and SVG
      (`<g transform="rotate(...)">`).
- [x] **Interactions**: hit-testing inverse-rotates the cursor; selection box +
      handles + a **rotate knob** draw on the rotated shape; dragging the knob sets
      the angle (Shift = snap 15°); **resize while rotated** keeps the opposite
      corner pinned in world space (resize in local space + world-anchor
      correction). Inspector **R°** field with stepping.
- [x] (later) rotate handle for paths/lines/groups (today: box shapes get the
      knob; everything rotates via the R field); rotated-bounds marquee

### Phase 9 — Typography ✅ DONE (Session 39)
- [x] **Typeface picker with live preview** — `TextContent.fontName` (PostScript
      face; empty = system, backward-compatible). Inspector menu lists families
      each rendered IN their own face, plus a weight/style Picker for the family.
      `UI/Typography.swift` (`FontCatalog` + `resolvedFont`/`measuredSize`/
      `familyName`). Font threads through canvas draw, inline editor, text
      measuring, PNG/PDF export, and SVG (`font-family` + bold/italic).
- [ ] (later) custom/embedded **font import** beyond installed system fonts;
      font search field for long lists

### Phase 9.5 — Rich text (multi-style) — IN PROGRESS
_Owner chose to go straight to full rich text. Staged across builds._
**Build 1 ✅ DONE (Session 40) — foundation + B/I/U**
- [x] `TextContent` is now **styled runs** (`[TextRun]` = string + face + size +
      color + underline) + paragraph props (align/lineHeight/tracking/box).
      Backward-compatible decode (old single-style → one run).
- [x] NSAttributedString **bridge** (`Typography.swift`): build for draw/measure/
      edit, rebuild runs from the edited attributed string. Threaded through canvas
      render, the **rich** on-canvas editor (`isRichText`), measuring, PNG/PDF, and
      SVG (`<tspan>` per run).
- [x] **Bold / Italic / Underline** — Format menu (⌘B/⌘I/⌘U) + inspector buttons;
      apply to the **selection while editing**, else the whole node.
- [x] Removed the inspector text field (item 1); typeface/size/color now apply to
      the whole node and show **"Multiple"** when runs differ.
**Build 2 ✅ (mostly) DONE (Session 43) — paragraph + type settings**
- [x] **Line vs paragraph** box — explicit **Auto/Text-box** toggle in the
      inspector; **drag-to-create** a fixed box with the text tool (click = auto);
      auto hugs, fixed keeps its size and wraps. Resizing a box makes it fixed.
- [x] **Cropped-text indicator** — red "+" badge at the box's bottom-right when a
      fixed box has more text than fits (`draw(in:)` clips to the box).
- [x] **Alignment** (L/C/R) + **line height** + **letter spacing** in the type area
      (model already in the paragraph style; wired controls).
- [x] **Selection font-size** in the inspector (size field drives the selection
      while editing via the Session-42 style channel; "Multiple" shown).
- [x] **Zoom-stable text** — text now lays out at TRUE size and the *drawing* is
      scaled (CTM), so wrapping/line-height no longer "hop" between zoom levels.
- [x] **Case transforms** (as-written / UPPER / lower / Sentence / Title) — Session 51.
      Non-destructive (CSS `text-transform`): stored runs untouched, applied at
      display/measure/export via `TextContent.displayStrings()` +
      `attributedString(applyCase:)`. The inline editor uses `applyCase: false` so you
      always edit the original characters. Inspector "Case" picker.
- [x] **Convert text → shapes** (glyph outlines → path nodes) — Session 53, refined
      Session 54. Core Text (`CTFramesetter`/`CTFontCreatePathForGlyph`) outlines the
      laid-out, case-applied text into **one path node per glyph**, each sized to its
      TIGHT ink box (no ascender/descender padding) and stored on a new
      `PathShape.contours` (multi-subpath, even-odd fill so counters punch through).
      The letters are **auto-grouped** (group frame = tight union, children relative —
      matches `group()`), so each letter is independently selectable and **Ungroup
      splits them into individual letter shapes**. Single glyph → a lone path node.
      Layer named per character; transform / opacity / effects carry over. Renders +
      exports (PNG/PDF/SVG, nonzero winding). Right-click "Convert to Outlines" +
      Format ▸ ⇧⌘O. Point editing is contour-aware (Session 55) — the Edit-Points tool
      shows and drags anchors/handles on **every** contour of a glyph (inner counter
      of an 'o', all pieces of a complex face). _Underline strokes aren't outlined._

> **v1.6.1 FIX — owner verified 2026-07-20.** Selected-run styling is now
> committed from a stable attributed-text snapshot, independent of the
> `NSTextView` first-responder/selection teardown. The exact direct-click-out
> regression passes in the Debug app and the owner's real workflow.

### Phase 10 — Effects ✅ DONE — refinements planned
- [x] **Layer opacity** (Session 51) — `Node.opacity` (0…1, default 1, hardened
      decoder that also back-fills `rotation`). Rendered as a grouped transparency
      layer on canvas + PNG/PDF (`beginTransparencyLayer` + `setAlpha`) and SVG
      (`opacity` on the element/group). Inspector 0–100% field next to R°.
      **Number-key shortcuts** (Session 51): canvas focused + shapes selected + not
      editing text → 1–9 = 10–90%, 0 = 100%, applied to all selected nodes as one
      undo step (`setOpacityOnSelection` in `keyDown`).
- [x] **Drop shadow** + **inner shadow** (Session 52) — `Node.effects: [Effect]`
      (CSS box-shadow geometry: color, dx, dy, blur, spread, enable toggle). Shared
      `EffectsRender` (Color/) + `Silhouette` helper, used by canvas + export. Drop
      shadow stamps the shape silhouette (or, for text/lines/open-paths/groups, the
      node's own painted content) into a shadowed transparency layer; inner shadow
      clips to the shape and casts inward. Rendered on canvas, PNG/PDF, and SVG
      (`<filter>` with feGaussianBlur/feOffset/feMorphology-for-spread/feFlood +
      feMerge; drops under source, inners over). Inspector "Effects" section: add
      menu (Drop/Inner), per-effect enable / type / color / X / Y / Blur / Spread,
      remove. _Spread is exact for rect/ellipse; ignored for arbitrary closed paths._
- [x] **Noise + dissolve effects** (Session 189) — two new stackable
      `Effect.Kind`s built for texture work. Parameters mirror SVG
      `<feTurbulence>` (type fractal/turbulence, baseFrequency, octaves, seed)
      and the canvas renders them with the SVG spec's own Perlin algorithm
      (`TurbulenceNoise`, Color/ — shared with EXPThumbnail), so SVG export
      emits real `feTurbulence` filter chains that match. Noise = turbulence
      composited over the node (per-effect blend mode + amount, monochrome or
      RGB); dissolve = turbulence thresholded at `amount` into an alpha mask
      that also masks shadow casters. SVG **import** reconstructs noise,
      dissolve, AND drop/inner-shadow effects from filter defs (round-trip;
      tolerant of wild feTurbulence). Inspector: add menu + full turbulence
      controls, seed shuffle, blend picker. _Known limits: noise tile samples
      node-local space so texture travels with the node (SVG samples user
      space — same statistics, different phase); tiles cached, capped ~2Mpx._
- [x] (lower priority) **Blend modes** — the CSS `mix-blend-mode` subset
      (multiply / screen / overlay / darken / lighten / …).

### Phase 11 — Layout, alignment & guides ✅ DONE
- [x] **Align & distribute** (Session 56) — edges/centers (L/C/R, T/M/B) + distribute
      horizontal/vertical spacing (equal gaps, extremes pinned, needs 3+). Illustrator-
      style **Align-to** toggle (`AppState.alignTarget` = Selection | Artboard); aligning
      to the artboard works on a single item too (center one thing on a board). Logic in
      `CanvasNSView` (`align(_:)` / `distribute(horizontal:)`, one undo step). Reachable
      three ways: Inspector row (icon buttons + Align-to picker, shown for selections),
      Arrange menu, and menu validation gates them (2+ to align, 3+ to distribute).
- [x] **Spacing measurements on ⌥-hover** (Session 57) — hold ⌥ with a selection and
      hover: red measure lines + point labels show the H/V gaps to the shape under the
      cursor, or the four distances to the artboard edges when hovering empty space.
      Live in `CanvasNSView.draw` (`drawMeasurements`), gated on `optionHeld` (tracked
      in `mouseMoved`/`flagsChanged`) and a non-drag state.
- [x] **Rulers + guides** (Session 58) — Photoshop-style rulers (top + left strips,
      document-coord ticks with zoom-aware nice steps + a pointer marker). Guides live
      in `Document.guides` (persisted, backward-compatible). Drag from the top ruler =
      horizontal guide, left ruler = vertical; drag a guide to move, drop on a ruler to
      delete (each one undo step). Cyan lines, drawn under selection chrome. Snapping:
      dragging a node snaps its edges/centers to guides + the owning artboard's
      edges/center (⌘ skips). View menu: Show/Hide Rulers (⌘R), Show/Hide Guides (⌘;),
      Lock Guides (⌥⌘;), Clear Guides. _Rulers/guides are document-scope only for now._
- [x] **Grid overlays** (Session 59) — two kinds. (1) Uniform square grid (Photoshop-
      style, global, session pref in AppState: `showGrid`/`gridSize`/`gridSubdivisions`)
      with minor + major lines aligned to the doc origin; settings in the no-selection
      Inspector; toggle ⌘'. (2) Per-artboard **layout grids** (`Artboard.layoutGrids`,
      persisted): columns / rows (count, gutter, margin) + baseline (spacing), each with
      color + visibility, edited in the artboard Inspector's "Layout Grids" section,
      drawn clipped to the board. **Snap to grid** (`snapToGrid`, toggle ⇧⌘') extends
      `snapNodeOffset` to the uniform grid's minor lines and layout column/row/baseline
      edges (⌘ still disables). Completes Phase 11.

### Phase 12 — Command coverage & menus (cross-cutting)
- [x] **Full menu bar** (Session 60) — File (+Export), Edit (Undo/Redo + Cut/Copy/
      Paste/Delete/Select All from system, + Duplicate ⌘D / Deselect All ⇧⌘A),
      **Object** (Group/Ungroup, Components, Convert to Path), **Type** (B/I/U,
      Convert to Outlines), **Arrange** (z-order + 6 align + 2 distribute), **View**
      (zoom, selection bounds, rulers/guides/grid/snap). Align/distribute also added to
      the right-click "Align & Distribute" submenu (2+). `selectAll(_:)`/
      `deselectAllAction(_:)` added + validated. Every action is reachable keyboard
      (where conventional) + menu + (contextual) right-click, gated by
      `validateMenuItem`. **This is now a standing convention — see CLAUDE.md
      "Command-coverage rule"; every new feature wires all surfaces in one change.**
- [ ] (ongoing) Re-audit for gaps as features land; add shortcuts/checkmark state for
      toggles (rulers/guides/grid/bounds) and align where conventional.

### Phase 13 — Workspace & dockable panels (Photoshop-style) ✅ DONE
_The shipped tray/panel workspace system is complete and stable. Remaining
unchecked items below are deferred nice-to-haves (multi-window tab drag,
named workspace presets, etc.) kept for future reference._
_Panels are already state-driven, so this is layout/hosting work, not a UI
rewrite. Built in sub-phases._

**Architecture decision (Session 75) — two distinct WORKSPACE MODES, not one
hybrid.** `AppState.workspaceMode`:
- **Single Window (DEFAULT):** the compact editor. Panels are their OWN stacked,
  headed sections (NO combined tabs by default). Contextual: whole panels hide
  when not applicable to the current tool/selection (e.g. Components hidden until
  a component exists), and Properties sub-sections show only when relevant.
- **Multi-Window (later):** the Photoshop-style mode. Panels become **separate
  NSWindows** that can move to another monitor, with **tab grouping**. Panels
  stay VISIBLE here even when not applicable — just **de-emphasized** (lower
  priority look) — rather than disappearing.
- **Visual unity (hard requirement):** the single-window panel **heading bar**
  and the multi-window **tab bar** are the SAME component (`PanelTab` styling).
  Multi-window adds affordances on top: grab/drag markings, active-tab highlight.
  The tab/grouping code from 13a is KEPT (parked for multi-window), not rolled back.
- Mode switch lives in the top-right system line. Earlier "in-window floating
  first" note (Session 74) is superseded: real separate windows are the goal for
  multi-window mode.

- **13a — Dock foundation (model + render)** ✓ Session 74
  - [x] Data model: `PanelID` (layers/properties/color/components, + reserved
        slots), `PanelGroup` (tabs + active + collapsed), `DockColumn`,
        `Workspace(.default)`; `AppState.workspace` + mutation helpers.
  - [x] `DockColumnView` / `PanelGroupView`: **tabbed groups**, **collapse /
        expand** (Photoshop "minimize"), flexible height split, column-width
        resize (via the HSplitView). MainWindow renders both docks from the model.
  - [x] **Components panel** (live list of `model.sources`, opens source editor;
        auto-populates as components are created) + **Color** reserved placeholder.
- **13a.1 — Single-window polish** ✓ Session 75
  - [x] **Sane default widths** — docks start at 264 (left) / 300 (right) so panel
        content no longer starts clipped; owner needn't widen every launch. (True
        persistence of a custom width still comes in 13d.)
  - [x] **Collapse direction fixed** — new explicit-height model packs groups from
        the TOP; a collapsed group is exactly its header tall and the freed space
        goes to the EXPANDED groups, so headers stay put (no flinging to the bottom).
  - [x] **Animate collapse/expand** (easeInOut 0.2s; content stays mounted +
        clipped so it slides). Respects Reduce Motion → instant. (Resize drag is
        intentionally NOT animated — it tracks the cursor.)
  - [x] **Removed panels' internal header titles** in the dock (Layers/Inspector);
        the group heading is now the only title. Source-editor window keeps its own
        (showsTitle/showsZoom flags, default true).
  - [x] **Group resize** — draggable divider between two expanded groups (weights).
  - [x] **Default ungrouped** — `Workspace.default` is one panel per group (no
        combined tabs); tabs reserved for multi-window mode.
  - [x] **Reorder** (drag a panel heading to a new position) ✓ Session 77 —
        drag/drop on headings reorders within a column AND moves a panel across
        to the other column (insertion line + dragged section dims). Reuses the
        Layers-panel drop-delegate pattern (`AppState.moveGroup`).
- **13a.2 — Workspace mode scaffold** ✓ Session 75 (partial)
  - [x] `AppState.workspaceMode` (single / multiWindow) + top-right mode switch.
  - [x] Contextual **whole-panel** hide in single mode (`isApplicable`): Components
        hidden until a component exists; Color reserved/hidden. Multi mode shows all.
  - [ ] Wire the multi-window mode to actually do something (see 13c).
- **13b — Rearrange**
  - [ ] **Reorder** panel sections within a column (single-window) — drag the
        heading to a new slot.
  - [ ] Multi-window: drag a tab to reorder / move between groups / drop to make a
        new group (drop-zone highlights, grab markings, active highlight).
  - [x] **Panels menu** (show / hide Layers / Properties / Components, toggle
        left/right dock ⌘\ / ⌥⌘\, Reset Panel Layout) ✓ Session 77. (Used a
        dedicated "Panels" menu rather than the native Window menu — clearer for
        this app; canvas @objc actions + `AppState.togglePanel`/`resetWorkspace`.)
- **13c — Multi-window mode (separate NSWindows; the multi-monitor payoff):**
  _Owner's primary motivation: spread panels across a second monitor to see
  everything at once. Single-window stays DEFAULT; this is the other mode._
  - [x] Switching to Multi-Window **floats panels into separate NSWindows** ✓
        Session 78 — `PanelWindowManager` hosts each layout panel
        (`panelContent` + shared AppState + document; undo via window delegate),
        staggered placement; the main window hides its docks (canvas fills);
        windows close on switch-back or when the document window closes. Shared
        AppState = the floating Properties window tracks the main canvas selection
        live; edits undo on the document stack.
  - [ ] Live open/close when toggling a SINGLE panel in multi mode (currently the
        window set syncs on MODE switch only).
  - [ ] In multi-window, panels stay visible but **de-emphasized** when not
        applicable (instead of hiding). Tab grouping in floating windows.
  - [~] Window snapping + grouped move (Session 80) — SUPERSEDED by the tray model
        (Session 82). The separate-window snapping was choppy (syncing N windows
        every drag tick); replaced by combining panels into one **tray** window.
  - [x] **Tray model** ✓ Session 82 — a tray is ONE window holding a vertical
        stack of panels with a grab bar (drag the bar = move the whole unit,
        smooth + native). `AppState.trays` ([PanelTray], persisted) is the
        arrangement; `PanelWindowManager` maps trays → windows (open/close on
        change, frame recorded back on move). Full-screen/zoom button removed.
  - [x] **Merge / reorder / collapse / tear-out** ✓ Session 82 — drag a panel's
        **header** onto a tray to merge/reorder (horizontal insertion line);
        **click a header** to collapse/expand its body (Adobe-style); a header
        **pop-out button** tears the panel into its own tray. Cross-window via
        SwiftUI drag-and-drop; the dragged panel id is shared through
        `AppState.trayDraggingPanel`.
  - [ ] DEFERRED: (a) **side-by-side docking** within one tray (multi-column /
        vertical insertion line) — panels currently stack vertically only;
        (b) pure **drag-the-header-OUT** tear gesture (today tear-out is the
        pop-out button — drop-outside isn't catchable via SwiftUI DnD);
        (c) header-click collapse in the single-window dock (still uses the
        chevron there).
- **13d — Workspaces**
  - [x] **Persist** the layout between launches ✓ Session 79 — panel arrangement
        (order/column), collapse state, group weights, **column widths**, the
        **workspace mode**, and dock visibility are saved to UserDefaults
        (`exp.workspaceLayout.v1`) and restored on launch (multi-window re-floats
        its panels). It's a workspace preference, not document data.
  - [ ] Save / name / switch multiple **named** workspace presets (e.g. "Laptop",
        "Dual-monitor"); a picker in the mode/workspace control.
- **App settings / preferences** panel (owns toggles like selection-bounds; home
  for saved views). Tools strip stays pinned left; canvas fills freed space.
  → STARTED Session 123: a full-window Settings screen (sidebar + detail,
  `SettingsWindow.swift`) reachable via ⌘, exists and owns the app-wide DEFAULTS
  for smart-guides, selection-bounds, snap, and grid size/subdivisions, plus a
  restore-layout toggle and a Design-Tokens placeholder pane. Per-window View-menu
  toggles still override per session; the screen is built to scale (one enum case
  + one view per new options group).

### Phase 14 — Images (low priority)
- [x] Place / embed **raster images** as an image node type; render + export.

### Phase 15 — Auto-layout / padding (BIG — later)
- [x] **Content-driven padding + spacing** for a group: inter-element gaps + edge
      padding that **reflow** as content changes (the button pattern — text/icon
      group with a gap and T/B + L/R padding; editing "Button" → "Buy" shrinks the
      background, "Learn more about us" stretches it). Likely a layout-container
      node with rules.

### Phase 16 — Vector & masking power tools (BIG — later)
- [x] **convert type to shapes** (text → editable paths) — done in Session 53 (see
      Phase 9.5). `PathShape.contours` (multi-subpath, even-odd) is the foundation
      future boolean ops / masks can reuse.
- [x] **Outline stroke** (expand stroke → fill path).
      DONE 2026-07-20: center/inside/outside and open round-capped strokes expand
      to editable `PathShape` contours. Filled+stroked art becomes a fill+outline
      group so both pieces scale together; stroke-only art becomes one filled path.

#### 16a — Shape mask (requested) — IMPLEMENTED Session 120
DONE: a mask is a `.group` flagged `isMask`; its children marked `isMaskShape`
form the clip (additive union of their silhouettes), the rest are masked content.
Reusing `.group` (instead of a new `NodeContent` case) means enter-to-edit,
drag-in, layers, copy/paste, instances all work unchanged. Model: `Node.isMask` +
`Node.isMaskShape` (Codable, default false). Render: `drawNodeContent` `.group`
case clips content to the mask union and draws the mask-shape outline (dashed
accent) while the mask/its descendants are selected; raster export mirrors it.
Create: "Mask with Top Shape" (Object menu ⌃⌘M + right-click + validate) wraps the
selection, topmost = mask shape; "Release Mask" reverts to a plain group. Editing:
double-click to enter, select/move/resize/point-edit the mask shape or content;
dragging a layer in via Layers adds it as content (reuses drag-into-group).
Rotated/flipped mask shapes clip correctly (Session 120 follow-up): each node's
own rotation/flip is baked into the clip path about its center and composed with
ancestor transforms, on canvas AND in raster export.
DEFERRALS (flagged): SVG export doesn't emit `<clipPath>` yet (raster/PDF do);
no Layers-panel badge marking which child is the mask shape (the on-canvas dashed
outline is the cue for now).

ORIGINAL PLAN (kept for reference):
- **Model**: a new `.mask` container `NodeContent` (or reuse `.group` + a
  `maskShapeID`): holds `maskChildren: [Node]` (the shape(s) acting as the mask,
  a group = merged/additive) + `content: [Node]` (the masked elements). Both
  editable; nothing is baked.
- **Render**: build the mask path from `maskChildren` (union of their silhouettes,
  even-odd/additive), `ctx.clip` to it, draw the content, restore. Mirrors how
  `nodeSilhouette` already builds shape paths.
- **Create**: select the top shape + the elements under it → "Mask with Top Shape"
  (Object menu + right-click) wraps them into a `.mask` node.
- **Edit like a component**: double-click to enter; the mask shapes + content are
  live-editable (move/resize/points), live on canvas — reuse the group enter/exit
  + the component inline-edit patterns.
- **Drag-in**: dragging a layer onto the mask node adds it to `content` — reuse the
  Layers drag-into-group machinery (`mutateNested` + drop delegate).
- Command coverage: action + Object/right-click + validate + Layers row affordance.

#### 16b — Pathfinder / boolean ops (IMPLEMENTED 2026-07-20)
- [x] **Subtract / cut-out, unite, intersect, exclude.** Uses macOS's native
      curve-aware `CGPath` boolean operations (no polygon flattening), converts the
      result back into editable cubic `PathShape.contours`, and bakes nested rotation/
      flip transforms correctly. Destructive by default with one-step undo; duplicate
      first when originals are needed. Subtract Front keeps the bottom selected shape
      and cuts every selected shape above it, matching the familiar Pathfinder model.

#### 16c — Copy / paste styles (FUTURE; requested)
- [ ] **Copy Style / Paste Style** (⌥⌘C / ⌥⌘V) — carry fill, stroke, corner,
      opacity, blend, effects (and auto-padding background) from one layer to
      compatible targets. A small `Style` payload + apply-to-each-selected.

### Phase 16.5 — Background blur effect (requested; needs an offscreen render pass)
- [x] **Background blur** — a stackable `Effect.Kind.backgroundBlur` (reuses the
      effect list UI, amount = `blur`), blurring whatever is BEHIND the node within
      its silhouette. ARCHITECTURE NOTE: the live canvas draws straight to the
      window context, so there's no backdrop to sample. Real impl = render the
      artboard CONTENT into an **offscreen bitmap** each frame (so a blur node can
      `makeImage()` the accumulated backdrop, `CIGaussianBlur` it, clip to the
      silhouette, composite), then blit + draw chrome. Same offscreen technique in
      `ExportRenderer`. This is why it's a focused build, not a quick add — a
      half-done version that mishandles the flipped bitmap would corrupt the canvas.
- [ ] **FUTURE IMPROVEMENT — live (gesture-time) blur.** Today blur is deferred
      during pan/zoom and "catches up" on settle (see Session 119 log), because the
      CPU Core Graphics canvas can't do a full-scene readback + Core Image per frame
      at 60fps. To make it truly live: move the canvas (or at least the blur
      compositing) onto a GPU/layer-backed surface — `CALayer` backdrop filter /
      `NSVisualEffectView`, or a Metal `CIContext` drawing to a `CAMetalLayer` so
      the blur stays on-GPU with no CPU `makeImage` roundtrip. Big, own-phase job.
- [ ] **FUTURE — background blur in `ExportRenderer`** (canvas-only right now).

---

### Phase 17 — Design-system rollout (apply the finalized visual language)

The visual language is now **finalized and exported** to `design/EXP [design]
Design System/` — token files (`tokens/colors.css`, `typography.css`,
`spacing.css`, `glass.css`), a React UI-kit recreation of every chrome component,
guideline cards, the SF font files, and the dark three-pane "north star"
screenshot. It is the concrete implementation of `docs/VISUAL-HANDOFF.md`, every
value pinned. **The CSS/JSON is the source of truth for values; this phase ports
it into the SwiftUI chrome.**

**Why this is a phase, not a quick reskin.** The chrome today rides on raw system
semantics — `.primary` / `.secondary` / `Color.accentColor` / `.separatorColor`
and `.bar` / `.regularMaterial` (~87 scattered calls across `MainWindow`,
`ToolsStrip`, `LayersPanel`, `PanelDock`, `PanelWindow`, `SettingsWindow`). That
follows light/dark and the user accent for free, but carries **none** of the
brand's specifics: the `#181819` purple-tinted base + neutral ramp, the
opacity-tiered text hierarchy (100 / 62 / 42 / 28 %), the named surfaces, the two
core glass thicknesses + modal, SF Compact for layer names / dense labels, the
small-and-varied radii (4·5·6·7·8·12), and lime as identity-only spice. **There is
no central token layer in Swift.** Build that seam first; everything else hangs
off it (mirrors the "introduce shared state early" move from Phase 1).

**Decisions locked (this session):**
- **Materials = native Liquid Glass first.** Use the real macOS 26 Liquid Glass
  APIs for docked chrome (panels, inspector, tools rail, popovers). Fall back to
  `NSVisualEffectView` / SwiftUI `Material` **only** where glass sits directly on
  the hand-drawn Core Graphics canvas (rulers, notes overlay, on-canvas chrome) —
  no backdrop there to sample, per `VISUAL-HANDOFF.md`. Reduce-Transparency swaps
  to the opaque `--surface-*-solid` plates.
- **First pass scope = token foundation + core *docked* chrome only.** Tools
  strip, left dock, inspector, layer rows, section headers, fields/controls.
  Floating **trays**, the thick-glass **component-editor modal**, popovers, and
  canvas-overlay chrome are explicitly deferred to **17e+** (below).
- **Full light + dark parity at every step.** Build/tune in dark (the design
  home) but wire both token sets from the start and verify light per component —
  no light-mode debt against the "faithful mirror" commitment.

**Hard constraints carried in:** keep using Apple *semantic* behavior where it
already buys correctness (system accent tracking, the canvas-stays-its-own-thing
rule — `--canvas-*` tokens are isolated, change sparingly). Accessibility is a
gate, not polish: Reduce Transparency, Increase Contrast, Reduce Motion, full
keyboard + VoiceOver must all still hold after the reskin. Lowercase house copy /
UPPERCASE panel titles unchanged. Fonts: SF Pro / SF Compact are **system fonts**
on every target Mac — reference them natively, do **not** bundle the `design/.../
fonts/*.otf` (Apple license; they exist in the export only for the web kit).

#### 17a — Swift token layer (the seam) — DO FIRST
- [x] New `UI/DesignTokens.swift` (member of the app target; **add to the
      EXPThumbnail target too if any shared/rendered code references it** — see
      CLAUDE.md gotcha). Port the CSS verbatim:
  - [x] **Color** — `enum EXPColor` (or `Color`/`NSColor` extension) resolving the
        neutral ramp `n0...n900`, surfaces, row states, text tiers, accent set,
        semantics, hairlines/borders, and the isolated `canvas*` set. Each token is
        **appearance-resolving** via a dynamic `NSColor(name:dynamicProvider:)` so a
        single token serves light + dark (mirrors `.exp-dark` / light scopes). Dark
        values from `colors.css` `:root,.exp-dark`; light from the `@media`/`.exp-light`
        block. Opacity-tiered text via alpha, not new hues.
        - [ ] **App accent override (consider early — touches the token seam).**
          The `accent*` tokens must NOT hardcode `Color.accentColor`; route them
          through an app setting `accentOverride: NSColor?` (nil = follow the macOS
          system accent, the DEFAULT — like System Settings). When set, every
          `accent` / `accent-hover` / `accent-press` / `accent-subtle*` derives from
          the override (hover/press/subtle computed, not stored). Selection, active
          tool, focus rings, primary buttons, segmented-on all follow it for free
          because they read the token. UI lives in Settings (17i). Build the hook in
          17a so the reskin never bakes a raw accent in.
  - [x] **Type** — `EXPType`/`Font` roles matching `typography.css`: docName (15 light),
        panelTitle (13 regular, UPPERCASE +0.06em tracking), section (11 ultralight),
        artboard (12 medium), layer (12 light, **SF Compact**), label (12 light),
        numeric (12 regular, tabular). Helpers return `Font`/`NSFont` with the right
        family (SF Pro Text / Display / **Compact** / Mono) + weight.
  - [x] **Spacing / radii / stroke / layout** — constants from `spacing.css`
        (space 2–32, panel-pad-h 12, row-gap 6, section-gap 8/+4; radii drop4 field5
        row/card/tool6 control7 button8 panel12 pill; strokes hairline1 selection1.5
        dropline2 focus2; metrics dock 264/332, tools 44, ruler 20, control-h 24/30,
        hit-target 28).
  - [x] **Motion** — `ease-standard` / `ease-emphasis` curves + durations
        (fast120 / base180 / slow260); a `reduceMotion`-aware animation helper.
- [x] **Proof step:** restyle **one** control (a button) and **one** surface (a
      panel section header) onto tokens, in both appearances, and eyeball against
      the matching UI-kit card / north-star before mass adoption. (Cheap insurance
      the token resolution + SF Compact actually render as intended.)

#### 17b — Materials: the glass primitives
- [x] A reusable `glass(.thin|.medium|.thick)` surface modifier: native Liquid
      Glass + tint (`--glass-tint-*`), lit top rim (`--border-glass`), sheen, and
      the layered elevation shadows (`shadow-1/2/panel/popover/modal/drag` from
      `glass.css`). Reduce-Transparency → opaque `surface-*-solid`.
- [x] Map thicknesses to roles per the readme: **thin** = tools rail / toolbars,
      **medium** = the default dock panel, **thick** = modals (lands in 17f).
- [x] Verify against `guidelines/glass-thicknesses.html` + `elevation.html`.

#### 17c — Core chrome reskin (first pass) — onto 17a/17b
- [x] **Tools strip** (`ToolsStrip.swift`, 44 wide, thin glass): tokenize the
      active/hover/idle states (`accent-subtle` active, `row-hover` hover), 15pt
      SF Symbols at token tint, tool radius 6. **Also re-orders the strip and adds
      three tools** (see below) — note the new tools are FUNCTIONAL work
      (`Tool` enum + behavior + full command-coverage), not just chrome, so they may
      be split out if the reskin should ship first.
  - [x] **New tool order / grouping** (`toolGroups`): `[pan, select, node]` ·
        `[rectangle, ellipse, polygon, line, pen]` · `[text, image, component]`.
        (Pen moves up into the shapes group; two spacers as shown.)
  - [x] **DEFINITIVE SF Symbols (owner-supplied Session 142 — no guesswork):**
        pan `hand.point.up.left.fill` · select `pointer.arrow` · point-select
        `beziercurve` · rectangle `rectangle` · ellipse `circle` · polygon
        `triangleshape` · line `line.diagonal` · pen `point.topleft.down.to.point.bottomright.curvepath.fill`
        · text `character.textbox` · image `photo.fill` · component
        `square.on.square.squareshape.controlhandles`. The EXISTING tools' symbols
        are already updated in `Tool.symbolName` (Session 142); pan/image/component
        land when those tools are built.
  - [x] **(ADD) `pan` / hand tool** — a dedicated Adobe-style hand tool that ONLY
        pans the canvas (never selects/moves). Distinct from today's space-drag /
        trackpad pan (which stays). `Tool.pan`, SF `hand.raised` (filled when
        active), H shortcut (and hold-space still temporarily pans within any tool).
        Cursor = open/closed hand.
  - [x] **(ADD) `image` tool** — opens an `NSOpenPanel` (multi-select) to import
        image(s) onto the canvas. **Depends on Phase 14** (raster image node type +
        render + export), which isn't built yet — pull a minimal image node forward
        or gate this tool on it. SF `photo`.
  - [x] **(ADD) `component` tool** — creates an EMPTY `ComponentSource` and opens
        the source-editor window to author it from scratch / paste into it (the
        inverse of today's ⌘K which wraps a selection). SF `square.on.square` /
        component glyph. Reuses the Phase-4 source-editor window + scope.
  - [x] Command-coverage for each new tool (canvas @objc + menu + shortcut +
        validate + the strip button), per the standing rule.
- [~] **Left dock + panel headers** (`PanelDock.swift` / `PanelHub.swift`): medium
      glass plate, UPPERCASE panel-title role, section headers (11 ultralight),
      panel-pad-h 12, section-gap, panel radius 12.
  - [x] Headers→toolbar tint, tabs→UPPERCASE + accent-subtle, dividers/drop-line/
        component rows tokenized (Session 137). **DEFERRED (on-device visual step):**
        the dock COLUMN native-`expGlass(.medium)` + making the sidebar `List`
        transparent so the glass shows — these fight each other and need live
        iteration; column bg is the `surfaceWindow` token for now.
- [x] **Layer rows** (`LayersPanel.swift`): 28-tall rows, **SF Compact** layer
      name (12 light; active layer 12 medium), eye/lock at token tints, row
      hover/active/selected fills, drop-into radius 4 / dropline 2 accent. Match
      `components/structure/LayerRow.*` + `structure.card.html`.
- [x] **Inspector fields & controls** (`MainWindow.swift` right pane): numeric /
      text fields (radius 5, field surfaces + focus, inset hairline), section
      labels, segmented (align-to, paint kind), buttons. Match `components/inputs/*`
      + `controls/*`.
- [x] **Window chrome**: window bg `surface-window` (`#181819` in dark), titlebar
      treatment, default 1500×950 / min 900×600 (already set — verify).
- [x] **Lime, sparingly**: only the `[design]` wordmark mark + (later) a single
      live-status dot / focus glow. Never a fill or button. Blue owns interaction.

#### 17d — A11y + appearance verification (gate for the first pass)
- [ ] Toggle System Settings: light <-> dark, **Increase Contrast**, **Reduce
      Transparency** (glass → solid plates), **Reduce Motion** (curves → instant) —
      chrome stays correct and legible in all.
- [ ] Full keyboard path + VoiceOver labels intact on every restyled control.
- [ ] Contrast check text tiers on their surfaces (primary/secondary/tertiary on
      panel + field) to WCAG AA for body, both appearances.
- [ ] Side-by-side the running app vs. `ui_kits/exp-editor/index.html` and the
      north-star screenshot; log deltas.

#### 17e+ — Deferred to later passes (parked, not dropped)
- [ ] **17e — Floating trays** (`PanelWindow.swift` / tray model) onto the same
      glass + token system (de-emphasized-when-inapplicable look from Phase 13c).
- [ ] **17f — Thick-glass component-editor modal** (`SourceEditorWindow.swift`) —
      the "north star" floating editor; thick glass + `shadow-modal`.
- [x] **17g — Popovers / menus** (color popover, paint editor tokenized Session 148;
        split menus + popover containers use native macOS Liquid Glass chrome) onto
      `surface-popover` + `shadow-popover`.
- [ ] **17h — Canvas-overlay chrome** (rulers, guides labels, notes overlay,
      measurement lines): the **NSVisualEffectView/Material fallback** path — glass
      that can't use the native API because it sits on the CG canvas. Keep
      `--canvas-*` tokens isolated; this is the one place to be careful.
- [x] **17i — Settings "Design Tokens" pane** (`SettingsWindow.swift` already has
      the placeholder) — surface the live token values for reference.

#### 17 — Owner design callouts (captured Session 133, from the redesign screenshots)
These refine the reskin specifics; fold each into the sub-phase noted.
- [x] **Layer-row order flipped (→ 17c).** The **lock toggle now sits on the RIGHT**
      edge of the row (was left). Row L→R: disclosure chevron · eye · type-glyph ·
      name (SF Compact) · …flex… · lock (right). Open padlock = unlocked, solid =
      locked; locked rows dim the name to `text-tertiary`.
- [x] **Active-layer treatment (→ 17c).** The selected layer row gets a **thicker
      accent border on its LEFT edge** (a ~1.5–2px accent bar) plus the
      `row-selected` fill — distinct from plain hover. One clear "this is active".
- [x] **Active-artboard treatment (→ 17c / canvas group header).** The active
      artboard's highlight is a **hairline accent line moved to the FARThest-left
      edge** of its layers group (a thin vertical accent rule), marking which board
      is active without a heavy fill. Inactive boards ("Non active artboard
      example") show no rule. NB this is the Layers-panel group header; keep it in
      sync with the on-canvas active-board cue.
- [x] **Glass unity across ALL windows (→ 17b cross-cutting; gates 17e/17f).** The
      glass surfaces, tints, rim, sheen and elevation must read **identically**
      across single-window chrome, the multi-window floating trays, AND the
      source-component editor window — same `glass()` primitive + tokens everywhere,
      so moving between them never feels jarring. Don't let any window grow its own
      one-off material. Verify all three side-by-side as part of 17d.
- [x] **App accent override (→ 17a hook + 17i UI).** Settings "Design" option to
      override the app accent (default = follow macOS system accent, exactly like
      System Settings). See the 17a accent-override sub-bullet for the token wiring.

**Acceptance (whole phase):** zero raw chrome color/font literals left in the
restyled files (all via `DesignTokens`); the running app in dark reads as the
north-star screenshot; light is a faithful mirror; every macOS accessibility +
appearance setting honored; no regression in keyboard/VoiceOver. Update CLAUDE.md
"Current status" (it still says Phase 0) as part of closing this phase.

### Phase 18 — Design language library & color workflow (✅ DONE 2026-07-10 — improvements planned)

_CLOSED at the owner's call: colors, gradients, categories, import/export,
contrast, palette generation, and type styles (18h) are all shipped and in
tester hands. The unchecked boxes below (OKLCH ramp generation 18b, APCA
advisory + contrast surfacing helpers 18c, panel core-action completeness 18d,
local palette providers 18f, type-style color-notes + Settings-editor parity
18h) are the "improvements planned" backlog — real, wanted, and deliberately
not blocking the phase._

_Owner brain dump captured 2026-07-05. This is the bridge from "a good color
picker" to "a document-local design language": colors, gradients, candidates,
contrast, imports/exports, and eventually type/components/tokens. Important
distinction: this is the USER'S design language inside a `.design` document,
not the app chrome's own `DesignTokens.swift`._

Current baseline:
- Phase 8 already supports HEX/RGB/HSL/LCH/OKLCH readout + parsing through
  `ColorMath`, but the visual picker is still HSB/SV + hue/alpha and stores
  sRGB `RGBAColor` on disk.
- Gradients already exist as `Paint.gradient`, but they are not yet saved,
  named, searched, imported/exported, or treated as library assets.
- Phase 13 reserved a Color panel placeholder; v2 can turn that into the
  first Design Language panel instead of making color a tiny inspector-only
  affordance.

#### 18a — Document design-language model
- [x] Add a document-level `DesignLanguage` (name TBD) with backward-compatible
      decode. First contents: named **solid colors** and **gradients**; later
      type styles, spacing, effects, and other design-system tokens.
- [x] Model each entry with stable `id`, `name`, optional notes/tags, status
      (`candidate` / `official` / `archived`), provenance/import source, and a
      value (`RGBAColor` for solid; `Paint.gradient` for gradient). Candidates
      are a real workflow state, not a junk drawer.
- [x] Keep **recent colors/paints** separate from named library assets. Recents
      are quick memory; library entries are intentional design language.
- [x] Add promotion paths: selection/recent → candidate; candidate → official;
      official → archived (non-destructive, undoable).

#### 18b — Color picker v2: real color-model authoring
- [x] Convert the picker from "HSB visual picker + format code field" into a
      mode-aware editor: HSB/HSV, HSL, OKLCH (and maybe LCH) each get controls
      that match the model's mental shape instead of only typed conversion.
- [x] Decide the storage strategy before expanding gamut: either keep sRGB
      storage with honest gamut warnings/clamping, or introduce a richer
      `ColorValue` that stores color space (`sRGB`, `Display P3`, future).
      Do not sneak wide-gamut values into an sRGB-only model.
- [x] Add gamut feedback: original typed value, clamped display value, and a
      clear warning when an OKLCH/P3 color cannot be represented in the chosen
      output space.
- [ ] Use OKLCH for palette generation/ramp adjustment because lightness and
      chroma changes are perceptually more predictable than HSL.

#### 18c — Accessibility / contrast checker
- [x] Add `ContrastMath`: WCAG 2.x contrast ratio, AA/AAA labels for normal
      text, large text, and non-text UI components. Alpha colors must be
      flattened over the relevant background before scoring.
- [ ] Add APCA as an **advisory** readout only if/when useful; do not present it
      as a replacement pass/fail standard while WCAG 3 remains unsettled.
- [ ] Surface contrast in the color picker and Design Language panel: compare
      selected foreground/background, text color vs. artboard/background, and
      any two library swatches.
- [ ] Offer adjustment helpers: "raise/lower OKLCH lightness to pass AA",
      "preserve hue", "preserve chroma as much as possible", and "swap
      foreground/background". These should suggest, not silently mutate.

#### 18d — Design Language panel
- [x] Replace the reserved Color panel with **Design Language** (or similar),
      using the same host-agnostic panel architecture as Layers/Components so
      it works docked or floating.
- [x] First sections: Official Colors, Candidate Colors, Gradients, Recents.
      Later sections: Type, Effects, Spacing, maybe component tokens.
- [ ] Core actions: apply to selection, rename, edit, duplicate, delete/archive,
      promote/demote, copy value as HEX/RGB/HSL/OKLCH/CSS, and reveal all uses
      in the current document.
- [x] Gradients display separately from solids but share the same naming,
      status, apply, copy, import/export, and provenance behaviors.

#### 18e — Import / export (v1.3 transfer sheet added 2026-07-11 — see log)
- [x] Define a canonical EXP design-language JSON export for document-to-document
      sharing. Keep it small, readable, versioned, and stable.
- [x] Export useful developer/design formats: CSS custom properties for colors
      and gradients, JSON tokens, and maybe ASE later if the format work is
      worth it.
- [x] Import with merge behavior: keep both / replace / skip, name conflicts,
      provenance retained, and an undoable single import operation.
- [x] Support paste/import from common palette representations where legal and
      stable: comma/newline HEX lists, CSS variables, Coolors share URLs or
      exported formats, and local files. Avoid scraping private web endpoints.

#### 18f — Palette inspiration providers
- [x] Provider framework first, services later: `PaletteProvider` returns
      candidate palettes/gradients with source labels, license/terms notes, and
      "add as candidate" / "add as official" actions.
- [ ] Local/offline providers should come first: OKLCH ramps from a seed color,
      complements/triads/analogous sets, accessible foreground/background pairs,
      and image extraction.
- [ ] Research snapshot (2026-07-05): Adobe Color/Express and Coolors expose
      strong browse/export experiences, but no clearly documented public
      "trending palettes" API was found. Figma's developer docs expose official
      FigJam base palettes through plugin constants, not the public
      `figma.com/color-palettes` browse library. The Color API offers public
      `/id` and `/scheme` endpoints for conversion and generated schemes.
      RandomA11y is open-source / generator-shaped rather than a documented
      remote API. Build EXP around imports, local generation, and honest
      provider boundaries unless official APIs appear.

#### 18g — Acceptance for the whole phase
- [x] A user can save named solid colors and gradients to the current document,
      mark candidates vs. official entries, and apply them to selected layers.
- [x] A user can copy/export/import color values in practical formats without
      losing names/status.
- [x] Contrast checking is visible where decisions happen and follows WCAG 2.x
      rules honestly.
- [x] OKLCH is not just a text field: it meaningfully powers picker controls,
      palette/ramp generation, and contrast-preserving adjustments.
- [x] The Design Language panel feels like the start of a styleguide/design
      system workflow, while leaving type/spacing/effects open for later.

#### 18h — Type styles (v1.3, DONE 2026-07-09)
- [x] `TypeStyle` in the document design language: everything EXCEPT color
      (owner decision) — face, size, underline, align, line-height (+unit),
      tracking, text case; `box` excluded (layout). Same cross-cutting
      categories as colors/gradients; tolerant decode both directions.
- [x] Capture: Type ▸ Save as Type Style / right-click a text layer / DL panel
      menu "Save Type Style from Selection" (named after the layer; rename in
      panel). Apply: panel double-click, panel context menu, canvas right-click
      "Apply Type Style ▸" — every path re-hugs frames + reflows auto-layout in
      one undo step. "Update from Selection" re-captures values keeping
      identity/name/category.
- [x] Panel rows preview the style name in its own face (display size capped),
      with VoiceOver labels; detail line carries face/size/lh/tracking/category.
- [x] Export/import: EXP JSON `typeStyles` array (merge modes incl. value
      de-dup via `sameValues`), CSS `.type-<slug>` classes (font-* only — no
      color, on purpose).
- [ ] FUTURE (discovery first): per-style color notes / recommended pairings
      from the color library. Do not spec until the workflow is designed.
- [ ] Settings-window Design Language editor: type-style section parity
      (panel is the primary surface for now).

### Phase 19 — Accessibility-native components (NORTH STAR)

**The idea:** give every step of the design process an accessibility affordance,
introduced as an *organizing* feature so it never reads as a separate chore. We
add a **category** to components whose vocabulary is sourced directly from **ARIA
roles**. On day one it's a way to filter/sort/organize the components a designer
builds. Underneath, that same choice is the semantic anchor that later powers
accessible code export. The role *is* the filter — accessibility work happens as
a side effect of work the designer already wanted to do. ("Hiding the health
food in the dessert.")

**Why this fits EXP specifically:** the tool's point of view is clean,
accessible *outputs* to hand to an AI agent / dev tool / code prototype — not
in-app prototyping. This phase is that thesis made real. It builds on subsystems
we already own: `ComponentSource` (backward-compatible `decodeIfPresent`
decode), the custom **SVG emitter** that renders straight from the model
(Phase 5), and `ContrastMath` / WCAG work (Phase 18c). Sub-phase 19c below is not
a new export system — it teaches an emitter we already have to write semantic
markup.

**Design decisions locked (planning session):**
- **Metadata depth:** Phase 1 surfaces the **role only**. The model, however,
  bakes in an accessible-name hook now (which child layer supplies the label) so
  export has something real to work with later — even though no UI sets it yet.
  Component **states** (e.g. `aria-checked`, `aria-selected`) are parked as an
  explicit *explore-later* note, to be modeled once a component-state system
  exists.
- **Role scope:** a **curated, design-relevant subset** of non-abstract ARIA
  roles (landmarks, widgets, structure roles a designer actually places).
  Abstract / author-forbidden roles are never offered.
- **Labels:** **designer-friendly names shown, ARIA role token stored** — UI
  shows "Button", "Navigation", "Dialog"; the model persists `button`,
  `navigation`, `dialog`.

> **Shared-target gotcha (read before coding):** any new model type referenced
> by `Document.swift` must be added to the **EXPThumbnail** target too, or the
> extension won't build. Prefer defining `AriaRole` + `A11ySemantics` **inline in
> `Document.swift`** (or a file already shared with the extension) to sidestep
> the Target-Membership trap and the Xcode-agent auto-stubbing behavior.

#### 19a — Component categories (✅ SHIPPED — improvements planned; see "Planned next")
_Shipped 2026-07-09 (v1.3 kickoff); owner verified 2026-07-10 ("that looks
good") after adding the source-editor category row + role blurbs, drag-to-
canvas instances, and the ×N instance badge. Remaining polish (instance
navigation UI, grid view) lives in "Planned next" under the v1.3 scope._ All types inline in `Document.swift` per the
shared-target gotcha; unknown future role tokens decode to nil instead of
failing the document._
- [x] **Model:** add `var a11y: A11ySemantics = .init()` to `ComponentSource`
      with a `decodeIfPresent` decoder so every legacy `.design`/`.exp` file opens
      unchanged.
      ```swift
      struct A11ySemantics: Codable, Sendable {
          var role: AriaRole?                // nil = uncategorized
          var accessibleNameLayerID: UUID?   // wired now, no UI yet
          // TODO(explore later): required/expressible states per role,
          // modeled once component states exist.
      }
      enum AriaRole: String, Codable, Sendable, CaseIterable {
          // curated, non-abstract subset, grouped by ARIA category:
          // landmarks: banner, navigation, main, complementary, contentinfo, search, form, region
          // widgets:   button, link, checkbox, radio, switch, textbox, searchbox, slider, ...
          // composite: tablist/tab/tabpanel, menu/menuitem, listbox/option, dialog, ...
          // structure: heading, list, listitem, img, figure, table, ...
          var friendlyLabel: String { /* "Button", "Navigation", ... */ }
          var ariaCategory: AriaCategory { /* for grouping in the picker */ }
      }
      ```
- [x] **Category picker** — designer-friendly labels grouped by ARIA category,
      with a clear "Uncategorized" default. Store the role token, show the label.
- [x] **Components panel:** filter by category (menu of roles present in the
      document + Uncategorized); role tag shown on
      each component row so the organizing value is immediate.
- [x] **Command coverage (per CLAUDE.md rule — wire ALL ways in one change):**
      `@objc setComponentCategoryAction:` on `CanvasNSView` (single source of
      truth; the ARIA token rides in the sender NSMenuItem's representedObject —
      the SwiftUI Object-menu leg wraps it in a stand-in item since `send()` is
      parameterless);
      **Object menu** item (e.g. "Set Category…", submenu of roles) with
      `validateMenuItem` enabling only when a component source is selected;
      **right-click** on a component / its instance; **Inspector control** (the
      picker) when a component source is the selection. No keyboard shortcut
      required (inherently a menu/inspector choice).
- [x] **A11y of the feature itself:** the picker follows system appearance +
      accessibility settings; role labels are readable by VoiceOver; the tag is
      not color-only.
- [x] **Acceptance (owner verified 2026-07-10):** a designer can assign a category to a component, see it on
      the row, filter by it, and reopen the file with the category intact. No
      accessibility "task" was ever presented — it felt like organizing.

#### 19b — Semantics layer (the hidden "health food")
- [ ] Surface the **accessible-name source** captured in 19a: let the designer
      pick which child text layer names the component (or fall back to a typed
      label). Still lightweight — one control.
- [ ] Lint/nudge, advisory only: flag a categorized component missing an
      accessible name; reuse Phase 18c `ContrastMath` to flag text/background
      pairs that fail WCAG AA *within a categorized component*. Suggestions, never
      silent mutation.
- [ ] **(Explore later)** component **states** → expressible ARIA state attrs;
      modeled once the component-state system lands.
- [ ] **Acceptance:** every categorized component can resolve to (role +
      accessible name), which is exactly what 19c needs to emit real markup.

#### 19c — Accessible export / handoff (the payoff)
- [ ] Extend the existing **SVG emitter** and add an **HTML/JSX semantic
      emitter** that maps role → correct element (`button`→`<button>`,
      `navigation`→`<nav>`, `heading`→`<h*>`, generic→`<div role="…">`), emits
      `aria-label`/visible label from the accessible-name source, and stays valid
      per ARIA authoring rules (no author-forbidden roles can reach output — the
      curated vocabulary guarantees this).
- [ ] Target: clean, **ADA/WCAG-minded** output a designer-who-codes can drop
      into a prototype, or hand to an AI agent / dev tool as pre-baked accessible
      scaffolding. Keep EXP's stance: outputs, not in-app prototyping.
- [ ] Handoff doc: per-component role, accessible name, and any advisory contrast
      flags, alongside the existing notes/handoff export (Phase 6).
- [ ] **Acceptance:** exporting a categorized design yields semantic,
      role-correct, named, contrast-checked scaffolding — accessibility that was
      "designed in" without the designer ever doing a separate a11y pass.

**Sequencing note:** 19a is independently shippable and valuable on its own
(organizing components). 19b and 19c can follow whenever; nothing downstream is
blocked by shipping 19a first. That's the whole point — the health food is
already on the plate before anyone orders the vegetables.


### Phase 20 — Sparkle auto-updates (v1.4 update-path proof)

Self-hosted updates for the direct-download build — no App Store required.
Sparkle 2.x via SPM; appcast served from expdesign.app; EdDSA-signed archives
on top of the existing Developer ID signing + notarization. Consent-first: no
silent automatic checks — Sparkle asks the user for permission on second
launch, and manual "Check for Updates…" always works.

- [x] `UI/UpdaterController.swift` — `UpdaterModel` wrapping
      `SPUStandardUpdaterController`, guarded by `#if canImport(Sparkle)` so the
      project builds BEFORE the package is added (menu item disabled until then).
      Guard also defends against the Xcode-agent stubbing gotcha (see CLAUDE.md).
- [x] App menu ▸ "Check for Updates…" (`CommandGroup(after: .appInfo)`), enabled
      state driven by Sparkle's `canCheckForUpdates`. App-chrome action, so the
      command-coverage rule's canvas legs don't apply.
- [x] Info.plist: `SUFeedURL` → `https://expdesign.app/appcast.xml`;
      `SUPublicEDKey` placeholder awaiting the real key.
- [x] Placeholder `website/public/appcast.xml` (valid empty channel = "no
      updates"; `generate_appcast` overwrites it each release).
- [x] RELEASE-CHECKLIST.md §4.5 — the per-release appcast routine.
- [x] OWNER (Xcode): File ▸ Add Package Dependencies… →
      `https://github.com/sparkle-project/Sparkle` (Up to Next Major, 2.x),
      add the **Sparkle** product to the **app target ONLY** (not EXPThumbnail).
      Then build — the canImport guard flips on automatically.
- [x] OWNER (once): run Sparkle's `generate_keys` (bundled in the SPM
      artifacts under DerivedData, or download a Sparkle release for the
      `bin/` tools). Paste the printed public key into Info.plist
      `SUPublicEDKey`. The private key lives in the login Keychain — NEVER in
      the repo or Dropbox.
- [x] First signed release: run `generate_appcast` (see §4.5), deploy the
      site, confirm `https://expdesign.app/appcast.xml` serves the entry.
      (v1.2.1 rehearsal, 2026-07-09 — owner ran the §4.5 flow.)
- [x] Release helpers added: `scripts/set_release_version.sh`,
      `scripts/verify_sparkle_setup.sh`, and
      `scripts/generate_sparkle_appcast.sh` reduce the version/appcast/signature
      steps to repeatable commands and reject common mistakes (wrong GitHub URL,
      missing notes, wrong build number, non-identical replacement zip).
- [x] v1.3 release build includes the network entitlement Sparkle needs to fetch
      the appcast; release checklist has a post-export entitlement check.
- [x] Live v1.4 → v1.6 proof confirmed appcast discovery, download, and archive
      signature/notarization. Immediate updater logs exposed the remaining
      app-wide failure: sandboxed builds through v1.6 omitted Sparkle's installer
      launcher key and `-spks` / `-spki` Mach lookup exceptions.
- [x] v1.6.1 adds the complete sandboxed Sparkle contract and release preflights
      for it. Because an older build cannot add its own missing entitlement,
      v1.6.1 is a one-time manual install.
- [ ] Verify the first install + relaunch proof from manually installed v1.6.1
      to the next published build. Also verify the update dialog with VoiceOver
      and increased-contrast mode (a11y is a hard requirement here).

### Phase 4.5 — Shape styling + vector paths (pulled in before export)
- [x] Stroke color + width on rectangle/ellipse (model + render + Inspector;
      `strokeWidth == 0` = none; backward-compatible decoders so older files open)
- [x] Corner radius UI for rectangle
- [x] Fill color pickers for rectangle/ellipse (ColorPicker ⇄ RGBAColor)
- [x] **Pen tool** (P) — click = corner anchor, click-drag = symmetric bezier in
      one motion, click the first anchor = close; Return/Esc/tool-switch finishes;
      open path strokes, closed path fills. One undo step per path.
- [x] Editable **Path** node + point editing — the **Edit Points** tool (A,
      direct-selection) drags anchors (handles follow) and bezier handles;
      **Convert to Path** (right-click) for rect/ellipse/line.
- [x] Path stroke/fill + closed toggle in the Inspector
- [x] Pen adds a point to an existing shape/path (Pen over existing geometry shows
      a "+" cursor; converts basic shapes to a path first); right-click an anchor →
      Make Curved / Make Corner; selection draws the path outline (no square box);
      View ▸ Toggle Selection Bounds (⇧⌘B) hides the box for shapes too.
- [ ] (later) remove anchor points; line stroke in overrides; nested-source
      overrides; a real Settings panel to own the bounds toggle

### Future phase — more styling (post-v1)
_Folded into the Polish roadmap above: gradients/advanced picker → Phase 8,
font import → Phase 9, shadows → Phase 10._

### Later (post-v1, only once the above is solid)
- [ ] Whatever the cheap-bucket friction-fixers turn out to be in real use
- [ ] Reconsider any expensive subsystem only if daily use demands it

### Refinement backlog (small polish, revisit when convenient)
- [ ] **Nested-selection edge cases** — drilling into groups (Session 61) supports
      select / move / delete / inspector edits / point-editing for nested children, but
      two paths still assume top-level: resize/rotate **handles** are hidden for nested
      items (move-only), and inline **text editing** of a nested text node isn't
      positioned yet (double-click only drills/selects it). Revisit when needed.
- [ ] **Align/distribute on nested selections** — still operate on top-level
      `currentNodes` only (Session 62 made duplicate/copy/cut/paste/delete/order
      nested-aware; align would need absolute-frame math + recursive write-back).
- [ ] **Inspector "Align" row layout** — the Align-to dropdown sits too close to the
      distribute buttons; owner mis-clicked distribute when reaching for the dropdown.
      Separate/regroup them (and revisit overall panel layout) in the panels phase.
- [x] Layers-panel **Shift-click range** clunkiness + drag-reorder "dead spots"
      over the row text — RESOLVED in Session 17 by switching to native
      `List(selection:)` + native drag-reorder and moving Rename to the row's
      context menu (no custom tap gestures to fight the drag). Trade: row
      multi-select toggle is now ⌘-click (macOS-native) rather than Option;
      rename is right-click → Rename (no longer double-click). Say the word if
      you want Option-toggle / double-click rename back (would need the custom
      gesture layer again, or an AppKit NSOutlineView-backed list).
- [x] Layer-reorder keyboard shortcuts (Session 17): ⌘[ send backward, ⌘] bring
      forward, ⇧⌘[ send to back, ⇧⌘] bring to front — all wired (+ Bring Forward /
      Send Backward added to the context menu). Drag-reorder feel improved by the
      native-List switch the same session.
- [ ] Source-editor window: confirm horizontal pan parity with the main canvas;
      if two-finger horizontal scroll still doesn't pan there, investigate the
      NSHostingController scroll-event path (owner reported vertical-only feel).

---

## Accessibility & ethics commitments (non-negotiable, baked in from day 1)
- Full keyboard operability of the app's own UI
- Respect ALL macOS system accessibility & appearance settings: reduce motion,
  increase contrast, AND light/dark mode (via semantic colors — see Architecture)
- VoiceOver-sensible labels on app controls
- "Source" not "master"; inclusive language throughout
- The handoff/notes feature itself exists to fight thoughtless dev handoff —
  ethics as a feature, not an afterthought

---

## Progress Log

- **2026-07-20 — v1.6.1 release candidate closed and preflighted:** Owner
  confirmed the rich-text click-out fix and the complete authored cursor family,
  accepted the focused release scope, and reported no new regression. Closed the
  bug sweep with the older centered-title popover polish explicitly remaining a
  non-blocking general-backlog item. Finalized release notes for the vector
  workflow additions. Version is locked at 1.6.1/build 9; clean universal Release
  build plus a development-signed universal Release whose nested signatures and
  expanded installer entitlements validate, Sparkle package/appcast preflight,
  focused vector geometry smoke suite, asset-catalog vector compilation, and
  production website build all pass. A signed local `.xcarchive` is ready in
  Xcode's local Archives folder. The archive check caught a delayed synced-folder/
  Finder metadata write attaching `com.apple.FinderInfo` to `EXPThumbnail.appex`
  and Sparkle XPC services; clearing those attributes restores strict verification.
  The reusable checklist now keeps archives local and requires cleanup immediately
  before distribution plus a second cleanup/round-trip proof on the final zip.
  Only external distribution
  remains: Xcode Direct Distribution,
  notarization/stapling, exact-zip verification/signing, appcast generation,
  GitHub/site publication, and one-time manual baseline installation.

- **2026-07-20 — Owner-authored cursor family integrated:** Added the supplied
  SVG pointer, add-point, delete-point, and four corner-specific rotate cursors
  to `Assets.xcassets` with their vector representations preserved. The canvas
  uses explicit arrow-tip hotspots for pointer/badge cursors and centered
  hotspots for rotate cursors; rotate hover resolves by actual screen quadrant
  so authored arrows point inward even when object transforms move a logical
  corner. Existing crosshair, resize, I-beam, hand, and Option-copy behavior is
  untouched, with safe system/code-drawn fallbacks if an asset cannot load.
  Clean Debug build passed, and `assetutil` confirmed all seven names include
  compiled 1×, 2×, and vector renditions. Owner feel/scale verification remains.

- **2026-07-20 — Outline Stroke + essential Pathfinder tools:** Added Object ▸
  Path ▸ Outline Stroke and Object ▸ Pathfinder (also available on the canvas
  context menu). Outline Stroke expands the exact visible center/inside/outside
  band into editable filled contours; filled art keeps separate fill + outline
  children in a scalable group, while stroke-only art becomes one filled path.
  Pathfinder now supports Unite, Subtract Front, Intersect, and Exclude Overlap
  with native curve-aware Core Graphics booleans, compound-path reconstruction,
  nested transform support, familiar bottom-base/front-cutter subtraction, and
  one-step undo. Debug and Release builds passed; focused geometry smoke tests
  passed all four boolean modes, all three stroke positions, and an open
  round-capped path. Owner visual/resize verification remains.

- **2026-07-20 — v1.6.1 media/SVG/rotation/geometry quality pass:** Finder file
  basenames now survive SVG/raster import as layer names; pasteboard SVG reads
  every file and places the batch side by side in one undo step. SVG export now
  emits readable `layer-<slug>` classes for every node (repeat names stay valid
  classes, never duplicate IDs). Replaced the top rotate notch with four
  outside-corner rotate regions + a dedicated cursor and delta math, preserving
  Shift snapping without diagonal-start jumps. Inspector geometry now measures
  the painted outline exterior, group dimensions use live painted descendant
  bounds, numeric path W/H scales vector points, and Geometry Audit reports both
  structural and painted bounds. Debug build passed; native checks confirmed a
  two-SVG named batch, outside-corner multi-rotation, and exported layer classes.
  Recorded the Design Language color → CSS custom-property bridge in the v2
  interop plan; owner real-document/zoom/stroke-position verification remains.

- **2026-07-20 — Sparkle installer failure is app-wide; sandbox integration fixed:**
  Reproduced v1.4 → v1.6 from the cleaned, strictly valid installed baseline;
  discovery and download succeeded, but installer launch still failed. The
  immediate unified log named the missing integration: authorization `-60005`,
  “Failed to submit installer job,” and Sparkle's sandbox warning. Added
  `SUEnableInstallerLauncherService`, the required `-spks` / `-spki` Mach lookup
  exceptions in a checked-in app entitlements file, and preflight enforcement.
  The public v1.6 archive itself remains byte-identical to local release copies,
  notarized/strict-signature clean, and free of forbidden Finder metadata. Since
  old builds lack the entitlement needed to launch their own updater, v1.6.1 is
  a one-time manual install; validate automatic updates from v1.6.1 forward.

- **2026-07-20 — v1.6.1 stabilization opened; rich-text click-out fix:** Marked
  v1.6 shipped and opened the intentionally narrow v1.6.1/build-9 bug-fix lane.
  Reworked inline-text commit around a stable attributed-text snapshot so
  selected word/line/character styling no longer depends on AppKit preserving
  attributes while first responder and selection tear down. Also wired deferred
  commit for selection changes originating outside the canvas without stealing
  the new selection. Debug build succeeded in Xcode 26.6; the exact word-size
  regression passed end-to-end (16 → 32 pt, direct artboard click-out, reopen and
  reselect still reports 32). Owner verification remains for the real document
  and size/color/weight/underline coverage.

- **2026-07-20 — v1.6 release prep:** Confirmed the v1.6 checklist is closed and
  moved the roadmap section from NEXT to release-candidate. Added
  `RELEASE-NOTES-v1.6.md` for build 8, covering component states, per-instance
  state selection, per-state contrast checks, ARIA role/category metadata,
  relationship authoring, Components-panel previews, source-editor lifecycle
  polish, PDF import, embedded images, menu validation, grouped styling, flip
  controls, and console/testing-menu cleanup. Updated the generated website
  tester-feature copy so the component/PDF-image cards read as v1.6 release
  features. Remaining release blockers are external packaging steps only:
  archive/notarize/staple in Xcode, zip the exported app, generate the Sparkle
  appcast from that exact zip, create the GitHub release, deploy the website, and
  test Sparkle update from installed v1.5.

- **2026-07-20 — v1.6 source-editor polish + lifecycle cleanup:** Added icon
  markers to the Properties inspector section titles and a Relationships help
  tooltip that explains when to use `controls`, `labelledby`, and `describedby`
  in designer-facing language. Made component source-editor windows larger by
  default, widened the source Properties panel, and persisted the last component
  editor window frame plus left/right split widths for the next source window.
  Manual source-window closes now clean up their manager entry, and closing the
  owning document closes its component source windows with it.

- **2026-07-20 — v1.6 scope closed: relationship authoring:** Finished the last
  concrete v1.6 Chunk H checklist item. The source-editor Properties inspector
  now has a Relationships section for selected source layers with `Controls`,
  `Labelled By`, and `Described By` pickers; targets are scoped to the same
  component source and skip the selected layer. Relationship writes bypass
  state-diff capture and update the base source even while viewing/editing a
  visual state, keeping ARIA semantics stable across hover/focus/etc. Command
  coverage added Object ▸ Component ▸ Relationships… and a source-canvas
  context-menu item, both greyed out unless a single source layer is selected.
  Marked Chunk H complete for v1.6; motion-token authoring stays deferred to the
  later Design Tokens/transitions UI while the model hook remains in place.
  VERIFIED: Debug xcodebuild succeeds with existing warnings only.

- **2026-07-20 — v1.6 tester-feature roadmap/site sync:** Added an explicit
  tester-facing v1.6 highlight block so `expdesign.app/download#tester-features`
  can list component states, per-state accessibility contrast checks, ARIA
  role/category assignment, Components-panel list/grid previews, PDF import, and
  embedded raster images in the next release push. Marked v2 Chunk H as partially
  shipped rather than fully closed: component states and panel previews are done;
  relationship-picker UI and motion-token authoring remain. Marked the resolved
  SwiftUI view-update warning done in BACKLOG after owner verification, which
  removes it from generated public known issues.

- **2026-07-19 — Console/testing-menu cleanup:** Quieted the old developer
  instrumentation surfaces for normal Xcode runs. Removed the automatic
  `[EXP save]` encode print from `ExpDocument.fileWrapper`, hid View-menu
  Testing Mode and Log Geometry Audit, and removed Help ▸ Reveal Diagnostic Log
  in Finder. Help ▸ Save Diagnostic Report… stays public, but now exports the
  user-shareable header/document-stats/geometry report without appending the
  hidden perf-stream tail. Hidden perf instrumentation now writes to the
  diagnostic file only if toggled internally, not to the Xcode console. VERIFIED:
  Debug xcodebuild succeeds.

- **2026-07-19 — Type inspector cleanup:** Removed the redundant Bold / Italic /
  Underline button row from the single-text Type inspector section; weight/style
  stays handled by the family face dropdown, with Type-menu keyboard commands
  still available. Trimmed the now-unused inspector helper state. VERIFIED:
  Debug xcodebuild succeeds.

- **2026-07-19 — v1.6 polish: grouped styling + menu audit:** Addressed the
  owner testing pass. Inspector multi-style controls now flatten selected groups
  and apply fill/stroke/font/text-size changes through the normal `commitScoped`
  funnel, so a single selected group behaves like selecting its contents (while
  still supporting group auto-padding where present). The Layer settings area now
  includes Flip Horizontal / Flip Vertical icon buttons under Blend. Menu audit:
  custom File/Edit/Object/Type/Arrange/View entries now read a focused
  `EditorMenuModel` from the active document/source window, so irrelevant actions
  grey out visibly (e.g. Detach Component only for instances, state commands only
  in source editors, Release Mask only for masks); Object is grouped into Mask,
  Frame, and Component submenus, and Arrange into Order, Flip, Align, Distribute.
  Canvas `validateMenuItem` was tightened to match. Roadmap cleanup: checked off
  the old Components-grid carry-over and split the completed inspector state
  picker from the still-open relationship picker. VERIFIED: Debug xcodebuild
  succeeds.

- **2026-07-19 — v1.6 states follow-ups:** Closed the three loose state-editing
  loops. Object menu now exposes source-editor state commands with responder
  actions on CanvasNSView: add the next conventional state (⌃⌘N) and cycle
  previous/next (⌃⌘[ / ⌃⌘]) with `validateMenuItem` gating and contextual "Add
  Hover/Pressed/Focus/Disabled State" titles. `ComponentStateEditing` now applies
  and captures `layerVisibility`, and LayersPanel source scope resolves the
  active state so its eye button writes per-state visibility overrides instead
  of mutating the base source default. Source-canvas drawing and inspector reads
  can request state-applied auto-layout reflow, so managed frames re-hug around
  overridden text in the editing preview while the canvas commit baseline stays
  unreflowed. VERIFIED: `xcodebuild -scheme "EXP [design]" -project
  "EXP [design].xcodeproj" -configuration Debug build` succeeds.

- **2026-07-19 — v1.6 Components panel grid + state preview:** Completed the
  Components panel redesign slice in PanelDock.swift. The panel now has a sticky
  list/grid toggle using the same EXPSegmented control as Design Language
  (`exp.components.viewMode`, list default). Grid mode renders adaptive component
  cards with lightweight generated thumbnails from the resolved component-source
  children; the preview resolves the chosen source state through
  `Document.resolvedChildren(of:in:)`, so hover/pressed/focus/default visual
  diffs show without placing an instance. Each component gets a local preview
  state menu; grid cards keep the important list actions (open, double-click
  rename, category, create instance, select instances, delete, drag to canvas).
  List rows also expose the preview-state menu for consistency. This does not
  pull canvas internals into the panel; the thumbnail renderer intentionally
  simplifies effects/rotation for scanning, and the layout leaves space for the
  later v2.2 library-sync/import-report status.

- **2026-07-19 — v1.6 Chunk H behavior-contract model spine:** Added the next
  model-only leg of the component contract in Document.swift (shared with
  EXPThumbnail, no new target-membership risk): every `Node` now carries
  `relationships: [NodeRelationship]` for typed ARIA-style links
  (`controls`, `labelledby`, `describedby`, with `ariaAttribute` mapping) plus
  `publicProps: PublicOverrideProps` flags for the current bounded override
  vocabulary (`text` and `fill`). Decode is tolerant/defaulted, so old files open
  as empty/private and future malformed relationship arrays drop instead of
  blocking the whole document. HANDOFF-SCHEMA.md now documents these as part of
  schemaVersion 2 alongside component states. This is plumbing only — relationship
  picker UI, command coverage, and semantic HTML emission still remain.

- **2026-07-19 — per-state contrast checks:** New `ComponentContrastAudit`
  (SourceEditorWindow.swift) walks a component source resolved in a given state
  (reusing `resolvedChildren(of:in:)` + `ContrastMath`) and reports each text
  layer's WCAG ratio + AA/AAA level against the background it actually sits on
  (heuristic: enclosing frame fill → sibling shape behind → white). A compact
  contrast strip now sits under the source-editor states bar and reflects the
  ACTIVE state, so switching states re-checks — contrast is evaluated per state,
  not just default. Green check when all text clears AA; amber warning naming the
  offending layer(s) otherwise. Large-text threshold at 24px. Advisory only — it
  flags, never edits. NEEDS BUILD in Xcode 26.3.

- **2026-07-19 — inspector state picker:** Added a "State" dropdown to the
  instance inspector (RightPanel.instanceControls in MainWindow.swift), shown
  between Category and Overrides whenever the source defines states. It binds the
  selected instance's `activeStateID` through `updateSelectedInstance`, so the
  write is undoable ("Change Component State") and the stored frame re-hugs to the
  new state's resolved size. This is the inspector surface for the on-canvas
  instance-state switch shipped earlier today (canvas chevron + right-click ▸
  State), completing command-coverage for changing an instance's state. NEEDS
  BUILD in Xcode 26.3.

- **2026-07-19 — on-canvas component instances + per-instance state:** A component
  instance placed on the wall/artboard now carries a selectable STATE and reads
  unmistakably as a component. MODEL (Document.swift, shared w/ EXPThumbnail):
  `ComponentInstance.activeStateID: UUID?` (nil = base; decode-safe for old files)
  plus `applyingState(_:)`, folded into `resolvedLayout(of:)` so an instance
  renders in its chosen state (state diff sits UNDER the instance's own overrides —
  instance wins). CANVAS (CanvasView.swift): a selected instance draws PURPLE
  double-outline chrome (replacing the blue box) with a top label bar — component
  icon (`rectangle.3.group`) · "Name — State" · a dropdown chevron. Clicking the
  chevron (or right-click ▸ State) opens a menu of the source's states and sets the
  instance's `activeStateID` undoably ("Change Component State"). Command-coverage:
  canvas chevron + context-menu path both wired; a dedicated inspector state picker
  (ROADMAP line ~307) is still the fuller home. Earlier this session: reverted the
  states marker from the source-window Layers header (it belongs only on the top
  States bar); the Components panel (tab, empty state, row) now uses
  `rectangle.3.group`. NEEDS BUILD in Xcode 26.3 — eyeball the label-bar symbol
  orientation in the flipped canvas and the purple/handle color mix.

- **2026-07-19 — v1.6 layer/component iconography:** (1) Components (instances)
  now read clearly apart from ordinary layers on the wall/artboard: the layer-row
  type glyph tints **accent** for instances (new `isComponentInstance` in the
  outline row) and the glyph itself changed to `rectangle.3.group`
  (`nodeTypeIcon(.instance)`, LayersPanel.swift). (2) The Layers panel tab icon
  changed to `square.2.layers.3d.top.filled` (PanelDock.swift). (3) In the
  source-component window, both component sections gained a leading
  `square.filled.and.line.vertical.and.square` marker: on the "States" label
  (ComponentStatesBar) and on the Layers header — where, since there's no dock
  tab to carry an icon, the Layers glyph (`square.2.layers.3d.top.filled`) is
  also shown, so marker + layers icon sit together (gated to `.source` scope, so
  the main-window Layers panel is unchanged). NEEDS BUILD in Xcode 26.3.

- **2026-07-19 — v1.6 states UI polish (owner tweak pass):** Five refinements
  to the source-editor states/header UI (SourceEditorWindow.swift). (1) State
  chips only prefix a colon for the conventional pseudo-class states
  (hover/pressed/focus/disabled) or names literally starting with ":"; arbitrary
  custom names now show just their initial(s), no misleading ":". (2) The states
  bar sits in its own slightly-recessed strip (`surfaceToolbar` fill + hairlines
  above and below) so it reads as separate from the category area. (3) The
  View-only backdrop picker moved OUT of the header into the window TITLEBAR as a
  trailing `NSTitlebarAccessoryViewController` (new top-level `SourceBackdropPicker`
  view sharing the window's AppState — the manager now creates the AppState and
  passes it into `SourceEditorView`), so it's one row with the traffic lights +
  "Edit Component" title. (4) The always-on category blurb (variable height →
  reflow) became a "?" icon using the field-tip hover pattern (`.expFieldTip`),
  so the row below no longer jumps as the description length changes. (5) The
  component-name field now hugs its content (`minWidth 90 / maxWidth 260` +
  `fixedSize`) so the active-state pill stays a constant gap from the name
  regardless of name length. NEEDS BUILD in Xcode 26.3 to confirm.

- **2026-07-19 — v1.6 states UI: source-editor states bar + state editing (owner mock):**
  Reworked the source editor header per the owner's markup: the component name
  is now an editable field (drafts locally, commits ONE undoable rename on
  submit/focus loss), the "changes apply to every instance" banner is gone,
  and the category picker + blurb moved to the right side. New
  `ComponentStatesBar` spans below the name row: extended chip row — "default"
  spelled out, other states as ":h" two-character chips (widened to ":xx" only
  on first-letter clashes), full state name shown in a pill next to the
  component name — plus a compact dropdown layout (toggle persisted via
  `exp.pref.statesBarCompact`), an add menu (unused conventional names +
  Custom…), and a manage mode with rename/reorder/delete (single-undo-step
  renames). STATE EDITING works end-to-end for the InstanceOverride
  vocabulary: `ComponentStateEditing` (Document.swift, pure model) applies a
  state's diff for editing WITHOUT filtering hidden layers, and `capture`
  splits an edited tree back into base + diff — text/fill changes become state
  overrides; geometry/structure passes through to the shared base. Wired at
  both write funnels: `CanvasNSView.commitNodes` and the inspector's
  `commitScoped` (which now also SHOWS state-applied values via
  `scopedNodes`). Active state is per-window (`AppState.activeComponentStateID`);
  canvas redraws on state switch via the updateNSView observation tuple.
  Honest scope cuts logged as an unchecked follow-up box: no command-coverage
  wiring yet for state actions, per-state visibility UI pending, and the
  editing preview doesn't re-hug managed frames around overridden text
  (instance rendering does). NEEDS OWNER BUILD + a real poke-around: create
  hover/pressed states on a button component, recolor + retype in each, check
  undo granularity, chip contrast in light/dark, and VoiceOver labels on the
  chips ("State hover", selected trait).
- **2026-07-19 — v1.6 Chunk H model spine: component `states` shipped:**
  Added `ComponentState` to Document.swift — a named override-diff against the
  base (same `InstanceOverride`/`LayerVisibilityOverride` shapes instances
  use), with an `enterTransitionToken` hook reserved for motion tokens and
  `conventionalNames` (hover/pressed/focus/disabled) for the future picker.
  `ComponentSource.states` decodes tolerantly (empty for old files).
  `Document.schemaVersion` bumped to 2 via `currentSchemaVersion`; a custom
  `encode(to:)` always writes the current version, so re-saving any v1 file
  migrates it, while decode keeps the file's declared version for diagnostics.
  Added `Document.resolvedChildren(of:in:)` which resolves a SOURCE in a named
  state through an ephemeral instance — re-hug and nested overrides behave
  identically, ready for the state-preview switcher and per-state contrast
  checks. HandoffPackageWriter's manifest now reports
  `Document.currentSchemaVersion` (what the encoder actually writes) and
  HANDOFF-SCHEMA.md documents schema v2 + a Component States section. All
  model changes live in Document.swift on purpose — no new shared file, so the
  EXPThumbnail target-membership gotcha is not triggered. NEEDS OWNER BUILD:
  verify with the usual Debug xcodebuild, then open+resave an existing
  `.design` file to confirm migration and that instances render unchanged.
- **2026-07-19 — v1.6 dev lane opened:**
  Public v1.5/build 7 is live in the appcast. Moved local development to
  `MARKETING_VERSION 1.6` / `CURRENT_PROJECT_VERSION 8` and promoted the
  v1.6 component-contract scope to NEXT. The first unchecked box is the model
  spine: `states` on component definitions, using override-diffs with a schema
  bump/migration. Keep local Sparkle installer cleanup separate from v1.6
  feature work; the live v1.5 archive itself verified clean.
- **2026-07-19 — Sparkle installer-launch failure root-caused again, this time to installed baseline:**
  Owner hit "An error occurred while launching the installer" during the v1.4 ->
  v1.5 update after the progress/download phase began. The live v1.5 GitHub zip
  is byte-identical to the local release and Sparkle archive copies, and the
  app extracted from that zip passes strict deep codesign plus Gatekeeper. The
  installed `/Applications/EXP [design].app` baseline is the failing piece:
  it is v1.4/build 6 and its embedded `Sparkle.framework/.../Installer.xpc`
  still has forbidden `com.apple.FinderInfo` metadata, so the current app cannot
  launch Sparkle's installer service even though the downloaded update is clean.
  Added `scripts/verify_installed_update_baseline.sh` and documented it in the
  release checklist so future end-to-end update tests verify the app initiating
  the update, not only the newly downloaded zip.
- **2026-07-19 — v1.5 release-prep pass:**
  Double-checked the release path for v1.5/build 7. Bumped the Xcode project
  from v1.4/build 6 to `MARKETING_VERSION 1.5` /
  `CURRENT_PROJECT_VERSION 7`, added `RELEASE-NOTES-v1.5.md`, and updated the
  release checklist's copy/paste path for v1.5. `scripts/verify_sparkle_setup.sh
  1.5 7` passes; it correctly notes that the checked-in appcast does not contain
  v1.5 yet because appcast generation must happen after the final notarized zip
  exists. Release-configuration `xcodebuild` succeeds, and `website` build
  succeeds while still reporting public release 1.4 from the current appcast.
- **2026-07-17 — v1.5 package manifest integrity wiring:**
  Added SHA-256 checksums to each `manifest.json.entries[]` item in exported
  Handoff Packages, alongside the existing byte counts. This gives downstream
  tools, dev teams, and local agents a simple way to verify that `design.json`,
  `tokens.json`, and `README.llm.md` match the manifest. Updated
  `docs/HANDOFF-SCHEMA.md` to document manifest entry fields. Build verified
  with `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]'
  -configuration Debug -destination 'platform=macOS' build` (succeeds; existing
  warning backlog still present).
- **2026-07-17 — v1.5 component pager avoids jarring jumps:**
  Adjusted Components-panel instance paging so it only recenters the canvas when
  the target instance is outside the current visible document rect. If the
  instance is already visible, paging now updates selection and the `n/N` badge
  without moving the camera. Added an `AppState.visibleDocumentRect` helper from
  zoom, pan offset, and viewport size. Build verified with `xcodebuild -project
  'EXP [design].xcodeproj' -scheme 'EXP [design]' -configuration Debug
  -destination 'platform=macOS' build` (succeeds; existing warning backlog still
  present).
- **2026-07-17 — v1.5 component pager hit-target fix:**
  Tightened the Components-panel instance pager after first testing feedback.
  The prev/next chevrons now use explicit 24 x 24 shaped hit targets instead
  of tiny glyph-sized plain-button regions, and paging now derives the active
  index from the currently selected canvas instance when possible. This makes
  the right arrow advance from the visible/selected instance instead of doing a
  first click that can appear inert by selecting instance 1 again. Build
  verified with `xcodebuild -project 'EXP [design].xcodeproj' -scheme
  'EXP [design]' -configuration Debug -destination 'platform=macOS' build`
  (succeeds; existing warning backlog still present).
- **2026-07-17 — v1.5 complete for testing: DTCG import + instance navigation:**
  Finished Chunk C by adding tolerant W3C Design Tokens import to
  `DesignLanguageIO`: nested groups, inherited `$type`, colors (strings or
  component objects), gradients (array/object stops), and typography tokens map
  into Design Language colors/gradients/type styles. The transfer sheet now
  accepts pasted Design Tokens JSON and imports `.json` files as either EXP JSON
  or DTCG tokens; `tokens.json` export remains the same writer used by handoff
  packages. Added instance navigation to Components-panel rows: prev/next
  chevrons page through instances, select the active one, and center the canvas;
  the existing badge remains select-all and changes to `n/N` while paging.
  Grid view was scoped and intentionally deferred to v1.6 Chunk H: the only
  reusable thumbnail renderer today is artboard-based Quick Look, so a real
  component-source thumbnail renderer belongs with the component panel redesign.
  Build verified with `xcodebuild -project 'EXP [design].xcodeproj' -scheme
  'EXP [design]' -configuration Debug -destination 'platform=macOS' build`
  (succeeds; existing Swift 6 warning backlog still present).
- **2026-07-17 — v1.5 Chunk A: Handoff Package spine shipped:**
  Added `docs/HANDOFF-SCHEMA.md` as the first public schema/package contract:
  `.exph` folder layout, `design.json` top-level keys, versioning, migration
  policy, id rules, and honest fidelity notes. Added
  `Export/HandoffPackageWriter.swift`, a whole-document package writer that
  emits `manifest.json`, `design.json`, `tokens.json` (using the existing W3C
  Design Tokens exporter), and `README.llm.md` with artboard-note and ARIA-role
  orientation. Wired File ▸ Export Handoff Package… through the canvas responder
  chain with menu validation and a save panel. Build verified with
  `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]'
  -configuration Debug -destination 'platform=macOS' build` (succeeds; existing
  Swift 6 warning backlog still present, no new errors).
- **2026-07-17 — v2 plan: Agent Bridge (Chunk F) + XD import (Chunk G) drafted:**
  Owner approved the MCP-server inversion — EXP never calls AI vendors; the
  designer's agent (any MCP client, any plan incl. free) connects TO EXP, so
  usage limits live in the agent's own UI and the whole feature is a single
  opt-in toggle, OFF by default. Stability decisions written into
  V2-INTEROP-PLAN.md: stdio helper (`exp-mcp`) + local Unix socket (most
  compatible transport), ≤6 flat read-only tools designed so older/smaller
  agent models succeed (summaries-first payloads, example calls in every tool
  description, node ids as the only reference currency), back wiring (F1,
  dark, v2.0) before any user-facing UI (F2 Settings ▸ Agents, v2.1),
  write-back deferred to F3 (v2.3+, separate consent, one undo group). Also
  added Chunk G — XD import (v2.1): .xd is a frozen ZIP of JSON since Adobe
  discontinued XD; no network/auth, so it proves the InteropCodec pipeline
  before Figma. Release mapping + open decisions updated in both docs.
  LATER SAME SESSION — panel named: F2 is the **Handoff panel** — one surface
  for everything leaving EXP (PNG/PDF/SVG export, Handoff Package, HTML,
  tokens, agent section). With no agent connected it's just the export hub;
  the agent section is a collapsed opt-in. Export menu items/shortcuts stay
  (command-coverage rule).
  ALSO — interaction-data question resolved + Chunk H drafted (v1.6):
  interactions = contract, not implementation — states (override-diffs, same
  structure as instance overrides), behavior via ARIA role + typed
  relationships (WAI-APG supplies the pattern; no prototyping arrows), motion
  via DTCG transition tokens. Components-panel grid redesign rides Chunk H.
  New v1.6 section added to this file. No code changes this session.
- **2026-07-15 — v1.4 Sparkle installer error traced to archive metadata:**
  Live update discovery worked from installed v1.3: Sparkle saw v1.4/build 6
  and displayed the release notes. Install failed with Sparkle's generic
  "error occurred while launching the installer" dialog. Downloaded the live
  GitHub release zip, unpacked it locally, and found `spctl` accepted the app
  as notarized Developer ID, but `codesign --verify --deep --strict` failed in
  Sparkle's embedded XPC services due to a forbidden `com.apple.FinderInfo`
  xattr (plus Dropbox/FileProvider metadata).
  After `xattr -cr` on the unzipped app, strict codesign passed. Plain
  `ditto -c -k --keepParent` still reintroduced the metadata on unzip because
  `ditto` preserves resource data/xattrs by default; the working archive command
  is `ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent`. Hardened
  `scripts/generate_sparkle_appcast.sh` and `docs/RELEASE-CHECKLIST.md` so the
  release flow strips xattrs before zipping and verifies the exact unzipped
  archive before appcast/upload. Generated a cleaned local
  `../releases/v1.4/EXP-design-v1.4.zip`, preserved the bad zips with
  `.bad-xattrs` / `.bad-roundtrip` suffixes, and regenerated the local appcast
  for the cleaned bytes. Next action: replace the v1.4 GitHub asset with the
  cleaned zip and deploy the matching appcast.
- **2026-07-15 — Correction: this release is v1.4, not v1.3:**
  Owner double-checked the public state: v1.3 is already out (appcast pubDate
  2026-07-12, build 5). Pivoted the release docs to **v1.4 / build 6**:
  restored v1.3 notes as historical, added `RELEASE-NOTES-v1.4.md` +
  `website/public/EXP-design-v1.4.html`, updated
  `docs/RELEASE-CHECKLIST.md` commands/paths, marked v1.4 release-ready, and
  moved the first interop/handoff package scope to v1.5. v1.4 is the first
  real network-enabled Sparkle update proof from installed v1.3 -> v1.4.
- **2026-07-15 — Small checkoff night: pan/zoom sensitivity cache, explicit Reveal in Layers, and `.design` schema marker:**
  Picked up the two "tonight" follow-ups named by the 2026-07-14 perf log plus
  the smallest v2.0 prep checkbox. PERF-TODO T1 is done: `CanvasNSView` now
  memoizes the all-clear `visibleBitmapSensitiveContent` case per
  `resolveGeneration` for pan/zoom, while falling back to the existing precise
  viewport check whenever sensitive content exists. Drag helper region/exclusion
  behavior is unchanged. Added explicit **Reveal
  Selection in Layers** command coverage: View menu + canvas right-click route
  through `revealSelectionInLayersAction`, show the Layers panel if needed, and
  call a document Layers-panel hook that expands ancestors/sections and scrolls
  only on demand (the auto-scroll perf fix remains intact). Added
  `Document.schemaVersion = 1` with tolerant decode so new `.design` saves
  self-identify for v2 handoff readers while old files still open. Owner
  smoke-tested and agreed to release this as v1.4.
- **2026-07-14 (later) — THE lag bug found and fixed: LayersPanel recomputation storm [perf, 4 code changes total this session]:**
  Ten-round instrumented hunt (full detail: docs/PERF-LOG.md). The
  multi-second beachballs on click/nudge/point-move were `LayersPanel`
  computed properties `groups` (O(artboards x nodes x artboards) + Node copy
  churn) and `activeSectionID` (which recomputed `groups`) being evaluated
  PER ROW AND PER HEADER during every SwiftUI List rebuild — caught red-
  handed by an lldb backtrace during a beachball. Fixed: both hoisted to
  once-per-body locals; `groups` now single-pass-buckets nodes by owning
  artboard. Also shipped en route: (1) drag-overlay blit no longer disabled
  by visible shadows/gradients (anchor drags now blit at ~2ms; snapshots
  render documentSRGB); (2) Layers panel no longer auto-scrolls on single-
  click selection (owner UX decision; explicit "Reveal in Layers" action to
  come, command-coverage rule applies); (3) permanent Testing-Mode
  instrumentation: input-pre/input->frame latency buckets, MainThreadWatchdog,
  timestamped save-encode print. Exonerated along the way: autosave/encode
  (55-85ms off-main), Dropbox, saves, scrollTo. Owner to verify the round-10
  fix; then resume PERF-TODO steady-state items + the .design package format
  (kills base64 image re-encode per save AND is v2.0 Chunk A schema work).
- **2026-07-14 — Perf deep-dive (discovery) + v2.0 interop plan [no code changes]:**
  Owner reported returning slowness on image/complex-shape docs and hit-or-miss
  vector point drags. Full code audit produced **docs/PERF-LOG.md** (findings
  F1–F8; headline: the bitmap-sensitivity opt-out in `beginPanZoomInteraction`
  and `drawDragBlit` disables BOTH Session-161 blit fast paths whenever any
  visible node has a shadow/gradient — i.e. on most real docs — forcing live
  full-scene renders per tick; plus per-tick @Published churn, uncached
  sensitivity walk, full-view invalidation, per-frame path rebuilds). 5-minute
  owner confirmation test written up in PERF-LOG. Mechanical follow-ups for a
  smaller model in **docs/PERF-TODO.md** (T1–T5 + do-not-delegate list).
  Separately: v2.0 direction set — interop/handoff anchored on export
  (**docs/V2-INTEROP-PLAN.md**, chunks A–E, release mapping v1.4→v2.2,
  DTCG-tokens + semantic-HTML spine). New v2.0 section added above
  Architecture decisions. Next session: owner runs the PERF-LOG confirmation
  test; then F1 root-cause experiment.
- **2026-07-12 — Website release pill now follows appcast [site]:**
  The header version pill was still showing v1.2 after v1.3 because
  `website/scripts/sync-content.mjs` only parsed roadmap headings shaped like
  `## vX.Y — shipped (YYYY-MM-DD)`, while v1.3 was represented as the current
  release scope. Changed the sync source of truth for `siteContent.release` to
  `website/public/appcast.xml` first, with shipped roadmap headings as fallback,
  so the pill follows the actual public Sparkle/download release. Verified
  `npm run sync`, `npm run build`, and local browser QA: homepage header renders
  `v1.3` / `Jul 12`, and the version pill links to `/download#download-signup`.
- **2026-07-12 — Sparkle update error traced to missing sandbox network entitlement:**
  After the appcast URL/delta issues were fixed, Check for Updates still showed
  Sparkle's generic "retrieving update information" error. Verified the live
  appcast and release-note URLs were HTTP 200, then inspected the installed
  v1.2.1 app and exported v1.3 app entitlements: both were sandboxed but lacked
  `com.apple.security.network.client`, so Sparkle could not fetch
  `appcast.xml` from inside the app. Enabled
  `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` on the app target, hardened
  `scripts/verify_sparkle_setup.sh`, made `scripts/generate_sparkle_appcast.sh`
  reject zips whose contained app lacks the network entitlement, and updated the
  release checklist with a post-export entitlement check. Release build succeeds
  and the newly built app includes `com.apple.security.network.client = true`.
  Existing 1.2.1 installs cannot self-update because that shipped entitlement is
  missing; v1.3 likely needs a manual download/install once, after which future
  Sparkle updates should be able to fetch the appcast.
- **2026-07-12 — Sparkle update error root-caused: bad delta + old URL rewrite:**
  Owner tested Check for Updates after publishing v1.3 and Sparkle showed
  "An error occurred in retrieving update information." The live appcast itself
  was reachable, but it advertised a generated delta asset
  `EXP [design]5-4.delta` under the GitHub v1.3 release that had not been
  uploaded (404). It also rewrote the older v1.2.1 item to
  `releases/download/v1.3/EXP-design-v1.2.1.zip` (also 404). Fixed the local
  and website appcasts to remove deltas and restore the v1.2.1 URL, then hardened
  `scripts/generate_sparkle_appcast.sh` with `--maximum-deltas 0` because this
  release flow uploads only the full zip. Hardened `scripts/verify_sparkle_setup.sh`
  to fail if `<sparkle:deltas>` appears or if older entries point at the current
  release tag. Verified the local appcast, script syntax, website build, and both
  GitHub zip URLs. NEXT: commit/push these fixes and let Vercel redeploy before
  retrying Check for Updates.
- **2026-07-12 — Release checklist now matches owner's local folders:**
  Updated `docs/RELEASE-CHECKLIST.md` with v1.3 copy/paste commands that match
  the owner's actual release layout: Xcode exports to `../releases/v1.3/`, and
  Sparkle archives live in `../sparkle-releases/` beside the repo. Adjusted
  `scripts/generate_sparkle_appcast.sh` so its default `SPARKLE_RELEASES_DIR`
  is that sibling `../sparkle-releases` folder instead of a home-directory
  fallback. Verified `bash -n scripts/*.sh`, script help text, and
  `scripts/verify_sparkle_setup.sh 1.3 5`.
- **2026-07-12 — Sparkle release path hardened for v1.3:**
  Owner clarified that v1.2.1 was the Sparkle setup/rehearsal and v1.3 should
  be the next real release. Bumped the Xcode project to `MARKETING_VERSION 1.3`
  / build 5 across app + thumbnail configs using a new
  `scripts/set_release_version.sh` helper. Added `scripts/verify_sparkle_setup.sh`
  (checks version/build, Sparkle package, feed URL, public key, release notes,
  local `generate_appcast`, and appcast URL/signature shape) plus
  `scripts/generate_sparkle_appcast.sh` (copies the notarized zip into the local
  Sparkle releases folder, refuses non-identical replacement zips, seeds/reuses
  that folder's `appcast.xml`, generates the HTML update notes, runs Sparkle's
  `generate_appcast --versions BUILD`, and verifies the vX.Y enclosure
  URL/build/signature). Added `RELEASE-NOTES-v1.3.md`, fixed the
  checked-in v1.2.1 appcast URL from a GitHub release-page path to the downloadable
  asset path, and added the missing v1.2.1 HTML notes file referenced by the
  appcast. Updated `docs/RELEASE-CHECKLIST.md` to prefer the scripts and to call
  out the website's shipped-heading version parser. Verified:
  `scripts/verify_sparkle_setup.sh 1.3 5`, `bash -n scripts/*.sh`,
  `xcodebuild -project "EXP [design].xcodeproj" -scheme "EXP [design]"
  -configuration Debug build`, and `npm run build` in `website/` all pass.
- **2026-07-12 — Release-readiness review before next build:**
  Reviewed `docs/ROADMAP.md`, `docs/RELEASE-CHECKLIST.md`, project version
  settings, Sparkle appcast, release-note files, and current git status. Debug
  build succeeds with Sparkle 2.9.4 resolved. Before shipping, clean up the
  release identity: the project is consistently `MARKETING_VERSION 1.2.1` /
  build 4, while the roadmap also has a v1.3 current scope with substantial
  v1.3 work already in the dirty tree. Also fix/regenerate the Sparkle appcast
  before relying on it: the checked-in enclosure URL currently looks like a
  release-page path rather than the checklist's downloadable GitHub asset URL,
  and there is no checked-in `RELEASE-NOTES-v1.2.1.md` / appcast HTML note.
  Recommended blocker list: decide v1.2.1 patch vs v1.3 release, create notes,
  regenerate/deploy appcast from the byte-identical notarized zip, then verify
  install-from-1.2 -> update -> relaunch plus VoiceOver/increased-contrast on
  Sparkle UI.
- **2026-07-12 — New manageable perf baseline after image clamp:**
  Owner confirmed the canvas now feels much more manageable and pasted another
  Testing Mode log. The image-clamp pass appears to have worked: `blit-images`
  is now usually tiny (`avg_of_avgs` about 0.9ms, max 16.2ms in this run)
  instead of repeatedly spiking into ~18–30ms. `chrome-transform-box` remains
  fixed (`avg_of_avgs` about 0.1ms, max 0.2ms). The remaining ongoing perf work
  is now the general dense-vector render path: `draw-nodes` averaged ~16.8ms
  with ~33ms max spikes, while snapshot `blit-shapes` averaged ~6.5ms with
  ~12ms max spikes. No code change this pass; treat this as the current baseline
  for future targeted optimization.
- **2026-07-12 — Clamp image snapshot variants to visible pixels:**
  Owner confirmed the multi-selection fix helped and pasted an updated Testing
  Mode log. `chrome-transform-box` dropped from ~30–45ms to ~0.1–0.2ms and
  total `draw-chrome` is generally under 1ms, so the selection-chrome regression
  is no longer the bottleneck. The remaining repeat offender is image-heavy
  pan/zoom capture: `blit-images` still spikes into ~18–30ms when large stock
  photos enter the snapshot region. Tightened image rendering so canvas cache
  variants are sized from the visible portion of the placed image, not the full
  frame, and lowered interpolation quality only for temporary pan/zoom snapshot
  captures. The settle/full-quality render remains high quality. Verified with
  `xcodebuild -project "EXP [design].xcodeproj" -scheme "EXP [design]"
  -configuration Debug build` — build succeeded.
- **2026-07-12 — Fast multi-selection transform bounds after follow-up log:**
  Owner pasted the next Testing Mode log. The new sub-buckets confirmed the
  previous large-selection shortcut removed per-node chrome cost, but exposed the
  remaining culprit: `chrome-transform-box` alone stayed around ~30–45ms while
  39–46 nodes were selected. Root cause was repeated recursive selection lookup:
  every frame recomputed transform ids, ancestor state, selected-ancestor state,
  node lookup, node offsets, and union bounds through separate tree walks. Reworked
  selection transform discovery into a single traversal that lifts selected nodes
  into document space once, then reuses that result to decide whether to draw the
  transform box and to compute its union bounds. Verified with `xcodebuild
  -project "EXP [design].xcodeproj" -scheme "EXP [design]" -configuration Debug
  build` — build succeeded.
- **2026-07-12 — Selection-chrome probes for image/SVG lag report:**
  Owner pasted another Xcode log after trying large stock-photo images resized
  down in the same SVG-heavy document. The image hunch is partially right:
  snapshot capture showed `blit-images` spikes around ~7–11ms when image layers
  were in play. The persistent "thinking on click" state, though, was dominated
  by `draw-chrome` at ~45–58ms per frame while `draw-nodes` was only ~7–16ms,
  so the worst offender is selection chrome rather than raw image drawing.
  Added Testing Mode sub-buckets for `chrome-node-selection`,
  `chrome-transform-box`, path/pen point overlays, selected path outlines,
  group bounds, selection bounds, handles, and selected-node/path gauges. Also
  added a conservative large multi-selection shortcut: selections over 32 nodes
  draw the unified transform box but skip per-node hint outlines, avoiding a
  frame-budget blowup on dense imported assets. Verified with `xcodebuild
  -project "EXP [design].xcodeproj" -scheme "EXP [design]" -configuration Debug
  build` — build succeeded.
- **2026-07-12 — Render-phase probes after latest SVG point-edit log:**
  Owner pasted a final bedtime Xcode log after the point hit-test / curve-handle
  pass. New probes showed `hit-points` stayed cheap (0.0–1.1ms, even on a
  122-point path) and `select-points` was effectively 0ms, so the remaining
  "thinking" feel is not point hit-testing or Inspector point-selection sync. The
  cost is still the full redraw path: ~19–22ms baseline with frequent ~30–40ms
  spikes while drawing 80 visible nodes. Added narrow Testing Mode buckets around
  `renderCanvas`: `draw-bg`, `draw-source`, `draw-boards`, `draw-nodes`,
  `draw-grids`, `draw-guides`, `draw-smart`, `draw-chrome`, `draw-measure`, and
  `draw-rulers`. No behavioral change intended; this is instrumentation so the
  next log identifies the expensive render phase directly. Verified with
  `xcodebuild -project "EXP [design].xcodeproj" -scheme "EXP [design]"
  -configuration Debug build` — build succeeded.
- **2026-07-12 — Point hit-testing + curve-handle UX pass:**
  Owner pasted a second Xcode log after point editing still felt laggy, especially
  when simply clicking anchors in imported SVG icons. The log again showed steady
  full redraw cost (~20–30ms frames, occasional ~30–40ms spikes) rather than memory
  collapse; the direct UX bugs were in path editing. Fixed
  `Canvas/CanvasView.swift`: point hit-testing now converts the click once into
  node-local coordinates instead of projecting every anchor/handle to view space;
  invisible handles no longer hit-test; selected anchors take priority over their
  own overlapping handles; and Testing Mode now logs `hit-points`, `select-points`,
  `pathPts`, and `selectedPts` to isolate any remaining click delay. Also changed
  Make Curved's default handle length from a forced 20-document-unit minimum to a
  conservative neighbor-based value capped at 12, so tiny imported SVG corners no
  longer sprout huge curve handles. Verified with `xcodebuild -project
  "EXP [design].xcodeproj" -scheme "EXP [design]" -configuration Debug build` —
  build succeeded.
- **2026-07-12 — Point overlay optimization for dense SVG paths:**
  Owner pasted the Xcode log after point-edit lag persisted. The noisy
  `/private/var/db/DetachedSignatures` + Sparkle installer probe lines are not the
  interaction lag; EXP perf output showed steady ~20–22ms frames, 80 visible nodes,
  with repeated ~39–42ms spikes. The missing measured bucket was selection/path
  chrome. Imported SVG icons can be dense compound paths, and `drawPathPoints`
  previously drew every anchor **and every Bezier handle** for the selected/hovered
  path every frame. Optimized `Canvas/CanvasView.swift`: point chrome now culls
  off-screen anchors and only draws handles for selected anchors / the active pen
  point. Unselected anchors still show as lightweight squares for editing context,
  but the expensive handle lines/dots no longer explode on dense SVGs. Verified
  with `xcodebuild -project "EXP [design].xcodeproj" -scheme "EXP [design]"
  -configuration Debug build` — build succeeded.
- **2026-07-12 — Point-edit lag fix for imported SVG icons:**
  Owner reported more beach-balling while moving points around imported SVG icons.
  Found two hot-path issues in `Canvas/CanvasView.swift`: the reopen-camera patch
  was scheduling camera persistence from `updateNSView`, so ordinary model redraws
  during point drags churned timers; and live node-tool / pen handle drags updated
  paths through `updateNode`, which re-runs `AutoLayoutEngine.reflowed(...)` over
  the whole node list on every mouse tick. Fixed: camera persistence is now only
  scheduled from actual camera changes, and live anchor/handle drags use a new
  `updateNodeLive` path that mutates the path without whole-document auto-layout
  reflow. Mouse-up still normalizes/reflows once and registers undo. Verified with
  `xcodebuild -project "EXP [design].xcodeproj" -scheme "EXP [design]"
  -configuration Debug build` — build succeeded.
- **2026-07-12 — Restore per-document canvas position on reopen:**
  Opening a saved document no longer always starts at the broad initial
  `fitContent()` view. `DocumentGroup` now passes the file URL into `MainWindow`
  and down to `CanvasView`; the AppKit canvas stores a local per-file camera in
  `UserDefaults` (zoom + document-space viewport center, debounced after pan/zoom).
  On first layout, the canvas restores that camera if present; otherwise it keeps
  the old fit-to-content behavior. This is deliberately local view state, not part
  of the design file, so pan/zoom does not dirty the document or add undo history.
  Verified with `xcodebuild -project "EXP [design].xcodeproj" -scheme
  "EXP [design]" -configuration Debug build` — build succeeded.
- **2026-07-12 — Fix intermittent light canvas + ghosting during pan/zoom:**
  Owner reported the canvas background sometimes flipped light while panning/zooming
  and left ghosted copies of artwork/artboards. Root cause was in the fast pan/zoom
  bitmap path, not Mac memory pressure: offscreen snapshot passes reused a backing
  `CGContext` without an explicit whole-buffer clear, and semantic system colors in
  that offscreen context could resolve outside the live canvas/window appearance.
  Fixed in `Canvas/CanvasView.swift`: `CanvasNSView` is now explicitly opaque;
  pan/zoom snapshot, drag snapshot, and background-blur offscreen passes clear the
  full reused bitmap before drawing; offscreen render passes temporarily adopt the
  canvas `effectiveAppearance` so `.underPageBackgroundColor` stays dark in dark
  mode. Verified with `xcodebuild -project "EXP [design].xcodeproj" -scheme
  "EXP [design]" -configuration Debug build` — build succeeded.
- **2026-07-11 — Export: add JPG as an optional format:**
  `ExportFormat` gains `.jpg` (ext `jpg`, UTType `.jpeg`); `ExportRenderer.jpgData`
  rasterizes like PNG but flattens onto white first (JPEG has no alpha), 0.9
  quality. The export popup now lists PNG / **JPG** / PDF / SVG (folder flow also
  keeps the trailing "All = PNG + PDF + SVG" — JPG is deliberately NOT in "All",
  it's an opt-in pick). Decoupled the popup from `ExportFormat.allCases` indexing
  (new `singleFormats` list + `isAllSelected`) so the format order no longer has to
  match the enum's `allCases` order. Transparent-background checkbox stays PNG-only.
  Files: `Export/ExportRenderer.swift` (shared w/ EXPThumbnail — AppKit-only, clean),
  `Export/ExportPanels.swift`.
- **2026-07-11 — Wall usability: zoom-out, paste location, layer reveal, artboard-ownership bug:**
  Owner-requested batch after heavy wall use. **(1) Zoom out further:**
  `AppState.minZoom` 5% → **1%** (culling already handles it) so a sprawling wall
  fits on screen. **(2) Paste/place location:** `pasteTargetBoard` now returns the
  board under the VIEWPORT CENTRE (not a board selected earlier and scrolled away
  from); when the viewport is over open wall, `pasteNodes` centres the paste at the
  viewport centre via a new `centered(_:atDoc:)` helper — so paste lands where
  you're looking. (Menu Place Image/SVG/PDF already centred on the viewport.)
  **(3) Find the selected layer:** the Layers panel List is now wrapped in a
  `ScrollViewReader`; selecting a SINGLE layer scrolls it into view (`revealScroll`,
  scrolls to the top-level ancestor row after a tick) on top of the existing
  ancestor-group + section auto-expand. Multi-select (marquee) doesn't yank the
  panel. **(4) "Group popped onto the wall / exported blank" bug:**
  `Document.owningArtboard` required the overlap to cover >50% of the NODE's frame.
  A group whose bounding frame is much larger than the board (e.g. an imported logo
  carrying a big transparent/stray element inflating its bbox) fell under 50% of its
  own frame when the board was cropped tight, so it orphaned onto the wall and
  exported blank. Ownership now needs >50% of the NODE **or** >50% of the BOARD
  (`coverage > 0.5 * min(nodeArea, boardArea)`), which keeps a board-covering group
  owned. Likely root cause of the inflated frame: SVG/PDF import keeps fully
  transparent elements (a clear-fill bounding rect), which enlarges the group bbox —
  noted for a possible future "skip invisible imported elements" option. Files:
  `Model/AppState.swift`, `Model/Document.swift`, `Canvas/CanvasView.swift`,
  `UI/LayersPanel.swift`.
- **2026-07-11 — PDF import: gibberish text + heavy-path beach-ball:**
  **(1) Gibberish beside good text:** the culprit is subset fonts with no ToUnicode
  map — `CGPDFStringCopyTextString` decodes them through a scrambled built-in
  encoding, producing valid-but-WRONG letters (so the earlier output heuristic
  passed them). Now judged at the FONT level: `fontDecodesReliably` treats a font
  as reliable only if it has a ToUnicode CMap, a standard named encoding
  (WinAnsi/MacRoman/Standard/MacExpert), or is a non-subset base font; `showText`
  rasterizes the page when the font is unreliable. Consequence/trade-off: a page
  mixing reliable + unreliable fonts now rasterizes ENTIRELY (no gibberish, but the
  good text on it is no longer editable). Alternative (keep reliable text editable,
  drop the unreliable runs) is a one-line change if the owner prefers holes over a
  flat page. **(2) Beach-ball on interaction:** a single PDF path can carry tens of
  thousands of points; one such node renders + hit-tests O(n) every frame and hangs
  the canvas. `buildNode` now caps points per node (12k) and per page (60k) and
  rasterizes past that (on top of the existing 2500 node cap + finite/sane geometry
  guards). File: `Model/PDFImporter.swift`.
- **2026-07-11 — Delete an artboard → delete its artwork too:**
  `CanvasNSView.deleteSelection` (the single delete behavior behind ⌫ / Edit ▸
  Delete / right-click) previously removed only the artboard FRAME, orphaning the
  nodes it contained onto the wall — so deleting imported PDF pages left all their
  content behind (and that stray content was part of what kept crashing). It now
  resolves each board's owned nodes via `owningArtboard(of:)` BEFORE removing the
  boards, then deletes both in one undo step. Consistent with copy/paste, which
  already carried an artboard's owned nodes. File: `Canvas/CanvasView.swift`.
- **2026-07-11 — PDF import freeze guards (2nd tester pass — froze on imported pages):**
  The menu-imported pages froze even before a delete (so NOT the raw-bytes issue —
  those pages use PNG). Root-caused to invalid geometry: a degenerate/extreme PDF
  transform can yield NaN/Inf/absurd coordinates → a NaN `CGRect`, which
  beach-balls AppKit on every redraw and hit-test (so selecting-to-delete can't
  even proceed); a node explosion is the other cliff. Guards added in
  `PDFImporter`: `buildNode` rejects any non-finite/absurd point or bounds
  (`finite`/`sane`, |coord| < 1e6); `showText` skips corrupt-transform text;
  `paint`/`showText` enforce a per-page node cap (**2500** — denser pages
  rasterize instead; tunable); `rasterPNG` caps the bitmap's long side to 4096px;
  and `importOne` falls back to US-Letter if the page box is NaN/absurd.
  `ExpDocument.sanitizePDFImages` now also DROPS nodes with a corrupt frame on
  open (broadened from the PDF-bytes-image fix), so a saved bad document opens
  instead of re-freezing. Files: `Model/PDFImporter.swift`,
  `Model/ExpDocument.swift`.
- **2026-07-11 — PDF import v1 fix round (first tester pass):**
  Fixes for the three issues from the first build. **(1) Beach-ball / bricked doc
  — `'PDF' initImage failed err=-50`:** the drag fallback stored RAW PDF bytes in
  an image node (NSImage accepts PDF data + passes the size guard), so every
  redraw re-decoded a PDF as a bitmap and hung. `placePDF` now rasterizes page 1
  to PNG (`PDFImporter.rasterPNGForPage`) instead of `placeImageData(rawPDF)`; and
  `ExpDocument.sanitizePDFImages` runs on open to convert any existing PDF-bytes
  image node to a PNG raster (or drop it) — un-bricks already-saved documents.
  **(2) Upside-down / mirrored raster pages:** replaced the hand-rolled CGContext
  y-flip with PDFKit (`PDFPage.thumbnail(of:for:.cropBox)`) — the reference
  renderer, always upright + /Rotate-correct. `importOne` now takes the matching
  PDFKit page. **(3) Gibberish text:** subset/CID fonts with no ToUnicode decode
  to junk; `showText` now runs `isLikelyText` (flags control / private-use / U+FFFD
  scalars, needs ≥70% good) and undecodable strings flip the page to a faithful
  raster instead of showing garbage. Editable text still comes through whenever
  the PDF carries a usable ToUnicode/encoding.
  Known/by-design: dragging a PDF imports page 1 only (vector-paste semantics —
  use File ▸ Import PDF… for multi-page → artboards). NEXT (full-fidelity tail):
  per-image extraction, shading/pattern → GradientFill, clipping, blend/soft-mask,
  and glyph→unicode maps so subset-font text stays editable. Files:
  `Model/PDFImporter.swift`, `Model/ExpDocument.swift`, `Canvas/CanvasView.swift`.
- **2026-07-11 — Import/edit batch, part 2 of 2 (PDF import + paste-vector):**
  New **Model/PDFImporter.swift** (app-target only; the project's
  file-system-synchronized group auto-adds it — no pbxproj edit). Walks each
  page's content stream with a `CGPDFScanner` operator table into editable
  native layers: path construction (m/l/c/v/y/re/h), fill/stroke/both/close
  painting, solid color (gray/RGB/CMYK + sc/scn component heuristic), the q/Q
  graphics-state stack, `cm` transforms, **Form XObject recursion**
  (`CGPDFContentStreamCreateWithStream`), and **editable text** (BT/ET/Td/TD/Tm/
  T*/TL/Tf/Tj/TJ/'/"), decoded via `CGPDFStringCopyTextString`, positioned from
  the text matrix, measured with CoreText, system-font fallback when the PDF font
  isn't installed. PDF y-up → our y-down via `m0`.
  **v1 fidelity policy (honest staging toward "full fidelity"):** a page that
  uses an **image XObject, a shading/`sh`, a pattern (gradient) fill, or a
  rotated page** flips THAT page to a faithful flat raster (whole-page render)
  instead of shipping a broken partial reconstruction — pure vector/text pages
  come in fully editable. Peeling images/gradients/clips out of mixed pages is the
  planned next iteration. (Clipping `W` is currently ignored, not rasterized.)
  **Isolation note:** the `@convention(c)` scanner callbacks are nonisolated, so
  `PageScan` + its file-scope helpers are marked `nonisolated` and text is
  measured with CoreText rather than the MainActor `TextContent.measuredSize()`
  (build uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
  **Wiring (command coverage):** (1) `ExpDocument` adds `.pdf` to
  `readableContentTypes` (read-only) → File ▸ Open a .pdf makes a NEW document,
  each page an artboard (saves as .design). (2) `CanvasView.importPDFAction` →
  File ▸ Import PDF… — NSOpenPanel + a page-range picker (`askPageSelection` /
  `parsePageRanges`, "1-3, 5" or All) → pages appended as artboards to the
  current doc. (3) Paste (⌘V) & drag-drop of a PDF (a vector copy lands as
  `com.adobe.pdf`, not svg) → `placePDF` imports page 1 as an editable vector
  GROUP (mirrors `placeSVG`); raster fallback if unparseable. Also fixed a
  pre-existing gap: ⌘V was disabled for external SVG/image/PDF (paste
  `validateMenuItem` now uses `canDrop`). Menu item in `EXP__design_App.swift`.
  Files: `Model/PDFImporter.swift` (new), `Model/ExpDocument.swift`,
  `Canvas/CanvasView.swift`, `EXP__design_App.swift`. **Needs a build + real-file
  iteration pass** (can't compile in the authoring env). If it fails to build, the
  most likely spot is the `@convention(c)` callback isolation.
- **2026-07-11 — Import/edit batch, part 1 of 2 (four vector-editing bugs):**
  Owner-requested fixes ahead of PDF-import work. All in the SVG/vector-edit
  paths. **(1) Node-tool point nudge** — `CanvasView.nudgeSelection` now checks
  for an active Edit-Points selection FIRST and calls a new
  `nudgeSelectedPoints(dx:dy:)` (translates the doc-space delta into the path's
  local space, undoing ancestor + own rotation and flips) so arrow keys move the
  selected anchors, not the whole object. **(2) Shift axis-lock on points** —
  `pathPointGroupDrag` now takes `shift` and locks the move to the dominant axis;
  `pathPointDrag` snaps anchor/handle drags to 45°/axis about their reference via
  the existing `constrainLineEndpoint`. **(3) Layers-panel arrow nudge** — the
  focused SwiftUI List swallowed key events (same gap the existing
  `onDeleteCommand` works around), so arrow keys never reached the canvas. Added
  `.onMoveCommand` → `nudgeSelectedLayers` + a static `moveIDs` recursive mover
  (⇧ = 10pt via `NSApp.currentEvent`). **(4) SVG import data loss** in
  `SVGImporter`: the named-color table was 11 entries — any other keyword
  (`steelblue`, `crimson`, …) parsed to nil and the fill vanished; replaced with
  the full 148-keyword CSS table (`cssNamed` + `namedColor`), added
  `currentColor`/`inherit` → black, `hsl()`/`hsla()` (`hslToRGBA`), and rgb()
  percentage support. Also honored SVG's implicit fill-close: a filled `<path>`
  with no explicit `Z` now renders closed (was coming in as an open, unfilled
  stroke) via `isClearPaint` + a `parsed.contains{closed} || hasFill` rule.
  Files: `Canvas/CanvasView.swift`, `UI/LayersPanel.swift`,
  `Model/SVGImporter.swift`. **Part 2 (next): PDF import subsystem + paste-vector
  -from-other-apps** — owner chose full fidelity, editable text (system-font
  fallback), and both Open-.pdf-as-doc (pages → artboards) + Place-into-current.
  Not started; needs its own build-iterate loop on real files.
- **2026-07-11 — DL transfer sheet: real import/export window with preview:**
  Phase 18 improvement round (owner-directed). (1) Panel menu icon
  `square.and.arrow.up` → `arrow.up.arrow.down` (the old one is the system
  SHARE glyph and undersold import; owner may still swap it). (2) New
  **UI/DesignLanguageTransfer.swift** — one resizable sheet, Import/Export
  modes (EXPSegmented toggle), opened pre-set from the menu's new Import… /
  Export… items, which REPLACE Paste Palette / Import from File / Export
  JSON / Copy CSS (those flows now live inside the sheet with room for
  options + a preview). Import: forgiving CSS/SCSS variable paste
  (`DesignLanguageIO.parseVariables` — strips comments/smart quotes/!default,
  reads `--var`/`$var` colors in hex/rgb/hsl/oklch AND type from font
  shorthand or family lists, mixed paste fine, round-trips our own `.type-*`
  CSS classes, falls back to hex-list/Coolors scan), automatic preview on
  change PLUS a dedicated Preview button (anti-stale), swatch + type-row
  preview grid, batch category assign or create-new, merge mode, one undoable
  Import; EXP JSON file import on the same screen. Export: format picker with
  honest per-format blurbs — CSS vars, **SCSS vars (new: `$vars` + `@mixin
  type-*`)**, EXP JSON, **W3C Design Tokens JSON (new — Style Dictionary
  ecosystem)**, **`.sketchpalette` (new — solids only)** — live monospaced
  preview that IS the output, Copy to Clipboard ("Copied ✓") + Save File….
  Cleanup queued: the panel's old pasteSheet/importFromFile/exportToFile are
  now dead code (nothing opens them) — strip after owner verifies the sheet;
  Settings-window import/export should eventually reuse the sheet too. Import
  of W3C tokens JSON = future (export-only today). ASE stays parked. OWNER
  NEXT: build; paste something ugly (SCSS with comments + mixed fonts/colors)
  and watch the preview; check the icon; export each format; confirm sheet
  resizes.
- **2026-07-10 (close of session) — Phase 18 + 19a CLOSED (improvements
  planned):** Owner call: the component-tagging and design-language phase of
  v1.3 is done for this round. Phase 18 marked ✅ DONE (open sub-boxes =
  improvements backlog: OKLCH ramps, APCA advisory, contrast surfacing, panel
  core actions, palette providers, type-style color notes, Settings parity).
  Phase 19a marked ✅ SHIPPED with acceptance checked; its follow-ups
  (instance navigation UI — design first, components grid view) are queued in
  "Planned next" under the v1.3 scope. Still open for v1.3 elsewhere: Phase
  9.5 rich-text bug, BUG-004, nested-group transform box, v1.2.1 Sparkle
  end-to-end confirm, and owner build-verify of tonight's batch (EXPSegmented
  styling, source-editor category row, drag-to-canvas instances, ×N badge,
  group-aware DL Add, per-corner radii, stroke alignment, shadow knockout,
  Round to Pixel).
- **2026-07-10 (evening) — design-system polish + component workflow + DL Add
  upgrades:** Owner verified component tagging works. (1) All new segmented
  pickers (stroke position ×3, DL grid/list toggle) now use the design-system
  **EXPSegmented** (accent fill) instead of the stock grey `.segmented` picker;
  EXPSegmented gained per-segment `accessibilityLabel` (for icon-only
  segments) + `.isSelected` traits. (2) **Source editor** gained a Category
  row under the header: grouped role picker + a plain-language description of
  the chosen role (`AriaRole.blurb`, new — one-liners disambiguating
  confusables like Checkbox vs Switch, Menu vs Navigation). Undoable through
  the document funnel. (3) **Drag-to-canvas instances**: the Components panel
  row's existing `.onDrag` (source UUID string) now has a canvas drop side —
  `componentSourceID(from:)` guards that the string is a UUID matching a
  document source (checked before the SVG/text sniffers), instance lands
  centered at the drop point, one undo step, self-nesting into a component's
  own source editor refused. (4) **Instance count + highlight**: each
  Components row shows an ×N capsule (hidden at 0) — click selects every
  instance on the canvas; also in the row context menu. (5) **DL panel Add
  upgraded**: selecting a GROUP now adds every descendant's fill (as if
  individually selected — `selectionFlattened()` dedupes nested selections),
  and the same + button now also captures unsaved TYPE STYLES from selected/
  descendant text layers (deduped by value); help text reads "Add 2 fills and
  1 type style…". OWNER NEXT: build; check the picker styling matches primary
  buttons, categorize from the source editor (read the blurbs!), drag a
  component onto the canvas, click an ×N badge, select a mixed group and hit
  + in the DL panel. NOTE: type styles were already addable via Type ▸ Save
  as Type Style / right-click — the + button is a third, faster path.
- **2026-07-10 (later) — stroke-picker fix, per-corner radii, convert-to-path
  radius bug:** Owner verified the shadow Preserve-transparency checkbox works.
  (1) FIX: the stroke position picker only existed in the MULTI-select stroke
  section — single selection renders `shapeControls()`/`pathControls()`, which
  had no picker. Added the segmented Center/Inside/Outside to both (paths:
  closed/multi-contour only), with single-selection bindings. (2) **Per-corner
  border radius** (owner request): `CornerRadii` struct in Document.swift
  (shared target) with CSS-style overlap clamping and a CGPath arc builder;
  `RectangleShape.cornerRadii: CornerRadii?` — nil = the uniform
  `cornerRadius`, which STAYS the default simple control. Inspector: single
  Corner field (setting it clears per-corner), plus an "Advanced" disclosure
  (mirrors the noise accordion, remembered via AppStorage) with TL/TR/BL/BR
  fields; matching all four collapses back to uniform automatically.
  Rendering: canvas + raster export use the shared path builder; silhouettes
  (shadows/knockout, spread-aware) gained `.perCornerRect`; SVG emits an
  A-command arc path (uniform rects keep plain `<rect rx>`), with
  inside/outside strokes via the generic clip/mask helper. (3) BUG FIX:
  convert-to-path dropped the corner radius — `pathShape(from:)` now builds
  κ-bézier rounded anchors (`PathShape.roundedRectPoints`, per-corner aware);
  rect/ellipse/polygon conversions also carry `strokeAlignment` through now.
  OWNER NEXT: build; verify the picker appears for a single selected
  rectangle AND a closed path; try Advanced corners (one corner 0, one huge —
  watch the CSS-style clamp), shadow + per-corner rect, convert a rounded
  rect to path and check the outline matches, SVG-export a per-corner rect
  with an outside stroke.
- **2026-07-10 — v1.3 continued: geometry audit verified + stroke alignment,
  Round to Pixel, shadow Preserve transparency:** Owner ran View ▸ Log
  Geometry Audit on the full doc (82 objects): ZERO mismatches — renderer math
  verified; the original "didn't line up" repro traced to SVG-imported content
  with fractional frames (e.g. 150.781×150.755 content on a 148×150 board),
  closed as not-a-renderer-bug. Owner then pulled three items in: (1) **Stroke
  alignment** inside/center/outside on all closed shapes — `StrokeAlignment`
  enum + per-shape field (tolerant decode), exact clip/2× rendering via new
  `PaintRender.strokeAligned` on canvas + raster export, exact SVG via
  geometry offset (rect/ellipse) and clipPath/mask (polygon/path, new
  `svgAlignedStrokeCopy` helper), alignment-aware `strokeReach`, segmented
  inspector control (closed shapes only). (2) **Round to Pixel** — full
  command coverage, artboards included, reflow in the same undo step. (3)
  **Drop shadow "Preserve transparency"** (owner wording pick) — per-shadow
  checkbox, default off = legacy render for existing docs; knockout via
  `.destinationOut` punch (canvas/raster, true silhouette not the spread
  outset) and `feComposite out` (SVG). `drawDropShadow` gained an optional
  `knockout:` closure — call sites in CanvasView + ExportRenderer pass both
  casters. OWNER NEXT: build; visually check (a) a semi-transparent shape
  with shadow, toggling the new checkbox, (b) inside/outside strokes on a
  rounded rect + a star polygon at several zooms, (c) SVG export of both, (d)
  Round to Pixel on the wrapping-paper SVGs from the audit. Still open:
  v1.2.1 Sparkle end-to-end confirm; VoiceOver pass on 19a picker +
  type-style rows.
- **2026-07-09 — v1.3 kickoff: type styles, ARIA categories (19a), tester
  diagnostics, pixel audit:** Four workstreams in one session. (1) **Type
  styles** (Phase 18h, new): `TypeStyle` in `DesignLanguage` — everything
  except color per owner decision (future color-notes/variations parked for
  discovery); capture/apply/rename/categorize/update/delete wired through
  Type menu, canvas right-click, and a new Type Styles panel section; EXP JSON
  + CSS export extended (`typeStyles` array; `.type-<slug>` classes). (2)
  **Phase 19a shipped:** `A11ySemantics` + curated `AriaRole` enum inline in
  `Document.swift` (shared-target safe, tolerant decode); category picker
  grouped by ARIA category everywhere the command-coverage rule demands —
  `setComponentCategoryAction:` on CanvasNSView, Object menu submenu (token
  rides a stand-in NSMenuItem's representedObject), instance right-click,
  Components-panel row context menu + filter + text-capsule role tag (never
  color-only), Inspector Category picker on instances, validateMenuItem.
  Accessible-name hook modeled, no UI yet (as planned). (3) **Tester
  diagnostics:** new `UI/DiagnosticLog.swift` (app target ONLY) — Testing Mode
  streams perf summaries + blit-budget warnings to a per-day rotating log in
  ~/Library/Logs/EXP [design]/ with machine header; Help ▸ Save Diagnostic
  Report… (NSSavePanel bundle) + Reveal Diagnostic Log in Finder. (4) **Pixel
  audit:** analysis says equal doc frames CANNOT render at different sizes
  (same `docToView`); the look-off causes are centered shape strokes vs
  inside artboard hairline, artboard shadow, fractional coords. Added View ▸
  Log Geometry Audit (numeric proof + alert + log). OWNER NEXT: build in
  Xcode (new file DiagnosticLog.swift auto-syncs; do NOT add it to
  EXPThumbnail), run the geometry audit on the original repro, sanity-pass
  VoiceOver on the category picker + type-style rows, and confirm the v1.2.1
  Sparkle end-to-end box (still open from last session). Watch the known
  Xcode-agent stubbing gotcha if the thumbnail target complains about new
  Document.swift symbols (TypeStyle/A11ySemantics/AriaRole are all inline
  there on purpose).
- **2026-07-09 — v1.2.1 kickoff: Sparkle keys + noise-flashing fix:** Sparkle
  updater verified in-app (build clean, menu item wired; placeholder-key
  warning as expected pre-key). Owner ran `generate_keys`; real public key now
  in Info.plist. Version bumped 1.2.1 / build 4 (all configs). Then diagnosed
  the zoomed-out noise/dissolve "flashing": NOT memory — `TurbulenceNoise`
  cache hits never promoted in `tileOrder`, so eviction was FIFO and a
  zoomed-out frame with >48 live tiles evicted tiles still on screen
  (skip-frame flash + regenerate churn); per-tile `tileReadyNotification`
  posts also dropped the pan/zoom snapshot rapid-fire during warm-ups. Fixed
  in `Color/TurbulenceNoise.swift`: promote-on-hit LRU, byte-budgeted eviction
  (256 MB + 512-tile safety net, masks counted at 1 B/px vs RGBA 4 B/px), and
  coalesced notifications (≤30/sec). Perf log from the repro showed healthy
  frames (≤11.6 ms) which ruled out stalls and pointed at eviction. Owner
  VERIFIED the fix (no flashing, clean frames, real EdDSA key accepted).
  Release then run per RELEASE-CHECKLIST (incl. new §4.5): notarized ditto
  zip, GitHub release, `generate_appcast`, site deploy — appcast generation
  confirmed working by owner. STILL TO CONFIRM next session: an installed 1.2
  build actually sees + installs 1.2.1 (the end-to-end Phase 20 box). Also
  logged PERF-005 (instCache counters flat at 0 — verify on an instance-heavy
  doc). NEXT SESSION: v1.3 kickoff (Design Language, Phase 18) + website
  language update for auto-updates.
- **2026-07-09 — Sparkle auto-updates (Phase 20 kickoff):** Integrated the
  Sparkle 2.x update framework for the direct-download build (no App Store).
  New `UI/UpdaterController.swift` (`UpdaterModel` wrapping
  `SPUStandardUpdaterController`, `#if canImport(Sparkle)`-guarded so the app
  compiles before the SPM package is added); "Check for Updates…" in the app
  menu after About, enablement via `canCheckForUpdates`; Info.plist gains
  `SUFeedURL` (expdesign.app/appcast.xml) + `SUPublicEDKey` placeholder —
  `SUEnableAutomaticChecks` deliberately unset so Sparkle asks the user for
  consent before any automatic checking. Placeholder empty appcast added at
  `website/public/appcast.xml`; RELEASE-CHECKLIST §4.5 documents the
  per-release `generate_appcast` routine. NEXT (owner, in Xcode): add the
  Sparkle package (app target only), run `generate_keys` once, paste the
  public key into Info.plist. Private EdDSA key stays in the Keychain, never
  the repo.
- **2026-07-08 — Session 191 (noise/dissolve pan-zoom performance + transparent SVG):**
  (1) Killed the multi-second frame stalls when panning/zooming over noise or
  dissolve effects. `TurbulenceNoise` tiles (up to ~2M px of pure-Swift
  feTurbulence Perlin × octaves) were generated SYNCHRONOUSLY on the render
  thread the first time each node drew — so every noise/dissolve board scrolling
  into view froze the gesture for seconds (perf log showed 2–16s frames exactly
  when `nodes(drawn)` jumped). Two fixes: the per-row pixel loop now runs under
  `DispatchQueue.concurrentPerform` (rows are disjoint writes; `nonisolated(unsafe)`
  buffer pointer), and generation moved fully OFF the render thread —
  `noiseImage`/`dissolveMask` return nil on a cold cache (caller already skips
  the effect that frame) and the tile builds on a background worker, posting
  `TurbulenceNoise.tileReadyNotification` when it lands so the canvas drops its
  pan/zoom snapshot and redraws. Grain now "pops in" a frame later instead of
  stalling. (2) First async cut had a reliability bug — a strict FIFO queue meant
  a slider drag's SETTLED value landed behind a backlog of superseded ticks, so
  the texture only returned after a long drain (panning away "fixed" it). The
  worker now drains NEWEST-first (LIFO) with a `maxPending` cap that drops
  superseded work + a `generatingKey` guard, so the on-screen value generates
  first. Generation closures marked `@Sendable`. This path is CANVAS-ONLY —
  PNG/PDF/SVG export render turbulence via their own feTurbulence, so no export
  risk. (3) SVG export is now TRANSPARENT by default: `svgString` no longer emits
  the artboard-background `<rect>` (owner exports SVGs as game assets and wants
  no board fill; add a shape layer for a real background). PNG/PDF still fill via
  `drawBackground`. Owner confirmed on build: pan/zoom is smooth, texture settles
  promptly while editing values, and SVG exports no longer carry the white box.
  Files: `Color/TurbulenceNoise.swift` (new-ish, rewritten), `Canvas/CanvasView.swift`
  (tile-ready observer), `Export/ExportRenderer.swift` (svgString). See memory
  [[exp-svg-export-transparent]].
- **2026-07-08 — Session 190 (precise path hit-testing + pen targeting):**
  Fixed the two overlapping-shape complaints (pen-drawn tree branches):
  (1) `nodeHit`'s `.path` case now tests the ACTUAL ink — real cubic beziers via
  a node-local `CGPath` (`inkPath(for:)`), `.winding` fill rule matching the
  renderer, honoring rotation + flips — instead of the anchor-only polygon /
  multi-contour whole-bbox shortcut. A visible fill hits anywhere inside the
  drawn interior; unfilled or open paths hit only within the stroke width or
  grab tolerance (`CGPath.copy(strokingWithWidth:)`). Transparent regions of an
  upper shape no longer swallow clicks meant for the shape underneath. Kept a
  frame-bbox fast reject (normalizePath guarantees the frame encloses ink).
  (2) The pen tool's add/remove-point targeting (`penHover`) now gives the
  SELECTED shape first claim when the cursor is on its ink, falling back to the
  usual topmost hit — no more adding a point to the neighboring branch while
  another shape is active. (3) `addPenPoint` measures the nearest segment along
  the flattened curve (not the straight anchor chord) and inserts on curved
  segments via a de Casteljau split, so the new anchor lands exactly on the ink
  without distorting the outline. Removed now-dead `pathAnchorsDoc` /
  `pointInPolygon`. Owner decisions: ink-only hits for unfilled closed paths
  (Figma-style) and precise hit-testing for multi-contour/outlined-text too
  (bbox shortcut removed). Owner confirmed the hit-test/pen fixes feel natural.
  SAME DAY, PART 2: (4) Fixed the "shape walks sideways when a point drag grows
  the bbox" bug — `normalizePath`'s re-base now keeps the RENDERED ink fixed
  for any rotation + flip combination (C′ = C + R·F·(c′ − c − d)); the old math
  only compensated rotation, so flipped paths shifted on every bbox change.
  (5) Noise/Dissolve inspector restructured: SIMPLE row (Type, Amount, Blend)
  by default; Freq/Octaves/Seed+dice/Mono moved into an "Advanced" accordion
  whose open state persists via @AppStorage("inspector.effects.advancedOpen").
  Fixes label clipping at the default panel width. (6) New app-wide rich field
  tooltip `expFieldTip(title, detail, edge:)` in GlassSurface.swift — title +
  multi-line detail bubble above the control after a 600ms hover, detail also
  attached as accessibilityHint for VoiceOver. Applied with full copy to every
  effects control (incl. shadows) and plumbed through effectNum / effectIntNum /
  effectPercent so other fields opt in as copy gets written. FOLLOW-UP: sweep
  expFieldTip across the remaining inspector/panel form fields (W/H/X/Y,
  typography, layout grids…). NOT yet compiled — needs an Xcode build; smoke
  test: point-drag a flipped/rotated path (no drift), Advanced accordion state
  across relaunch, tooltip hover on effects fields, VoiceOver hints.
  PART 3 (owner feedback on first build): (7) Field-tip bubble was wrapping one
  word per line and landing on the controls below — an overlay proposes the
  ANCHOR's tiny width, and the alignment-guide float didn't hold. Fixed: detail
  bubbles take a fixed 232pt readable width (title-only tips hug), and the
  bubble is measured (`onGeometryChange`) then offset fully above/below the
  field by its real height. `align: .trailing` added for right-edge controls
  (blend, trash) so bubbles stay on-window. (8) Field-tip hierarchy: title now
  renders in the accent color; `detail` accepts inline markdown — **bold**
  runs brighten to primary text color, literal \n newlines break lines.
  (9) Advanced accordion rows are ELASTIC via ViewThatFits: one line when the
  panel is wide enough, wrapping to two when narrow.
  PART 4: (10) Field tips are now EDGE-AWARE — the bubble moved out of the
  SwiftUI overlay (which the panel's scroll view / window always clip) into a
  borderless, non-activating, click-through child NSPanel (`EXPFieldTipWindow`)
  positioned in SCREEN coordinates: preferred spot above the field, allowed to
  spill past the panel edge, slid horizontally inside the monitor's visible
  frame, flipped below the field when there's no room above. Anchor rect comes
  from onGeometryChange(.global) + an NSViewRepresentable window reader →
  convertToScreen. `edge`/`align` are now just the PREFERRED placement.
  Needs an Xcode build; smoke test: hover tips near the panel's right edge and
  at the very top of the screen, drag the panel while a tip is up (child window
  tracks), and confirm clicks pass through the bubble.
  PART 5: (11) Multi-window bug: align/distribute (and the inspector's text-
  style + zoom-to-fit buttons) did nothing when panels float as windows —
  `NSApp.sendAction(to: nil)` walks the KEY window's chain, the panel takes key
  on click, and the action dead-ends (selection was never lost; the message had
  no route). Fixed twofold: tray windows now override `canBecomeMain = false`
  (inspector semantics — key for text fields, never main), and a shared
  `sendCanvasAction(_:)` tries the key window then walks the MAIN document
  window's responder chain. All four inspector sendAction sites route through
  it. FOLLOW-UP: menu-bar items are likely disabled while a tray window is key
  (validateMenuItem also walks the key chain) — audit `send()` in
  EXP__design_App.swift the same way. Smoke test: float the properties panel,
  select 3 shapes, click align/distribute; bold/italic buttons; Zoom to Fit.
  PART 6: (12) FLIPPED-GROUP editing bug: children of a flipped (H/V) group
  hit-tested and MOVED as if unflipped — the renderer mirrors a group's whole
  subtree about its center, but the interaction layer only ever undid ancestor
  ROTATION. Fixed in five spots: `parentLocalToDoc` / `docToParentLocal` now
  mirror about each flipped ancestor's center (flip before/after rotation to
  match render order), `hitPath`'s descent and `nodeHit`'s group recursion
  un-mirror the cursor, and the `.nodes` move-drag converts the doc-space
  delta through the FULL ancestor chain (two-point `docToParentLocal`
  difference) instead of the rotate-only `ancestorRotation` shortcut — which
  was also wrong for rotation INSIDE a flipped group (a mirror reverses
  rotation direction). Point editing / pen / line endpoints inherit the fix
  via the shared helpers. KNOWN REMAINING: `.resize` of a node nested in a
  rotated/flipped group still uses the plain `nodeOffset` shortcut (pre-
  existing); `ancestorRotation`-based handle cursors ignore mirroring. Smoke
  test: flip a group H and V, drag a child (tracks the cursor), click-select
  children, edit a nested path's points, drag a nested line endpoint.
  PART 7 (owner screenshot: selection chrome still mirrored): the OVERLAY layer
  had its own transform math. Fixed: (13) `drawNodeSelection` routes flipped-
  ancestor chains to `drawTransformedSelectionBox` (corner-mapped through the
  now-flip-aware `parentLocalToDoc`) — same early-out rotated ancestors always
  took, so the box + path outline draw on the ink, not the mirror position.
  (14) New `ancestorsUntransformed(_:)` (unrotated AND unflipped chain) replaces
  the `isTopLevelNode || ancestorRotation == 0` gate in `hitTestHandle`,
  `rotateKnobPoint`, `selectionTransformIDs`, and the chrome's handles flag —
  under a flipped group a node is move-only, so phantom resize handles can't
  grab at the unflipped spot. (15) A flipped GROUP's own hint box mirrors the
  live content union about its center. Smoke test: select a child inside a
  flipped group — box/outline sit ON the shape; the group's own selection box
  hugs its mirrored children.
  PART 8: (16) Full RESIZE + ROTATE inside transformed groups — the move-only
  restriction under rotated/flipped ancestors is gone for single leaf nodes.
  One shared mapper `boxPointToView` (parent-local box point → own rotation →
  full ancestor chain → view) now drives the handle chrome, `hitTestHandle`,
  and `rotateKnobPoint`, so drawing and hit-testing can't disagree; the
  transformed quad draws 8 handles + knob. `.resize` converts the cursor to
  PARENT-LOCAL via `docToParentLocal` (was plain offset subtraction), so the
  existing anchor/proportional/flip-crossing math is chain-agnostic; `.rotate`
  measures the knob angle in parent-local space (two-point difference), so
  rotated ancestors' offsets and flipped ancestors' reversed handedness fall
  out. `ancestorsUntransformed` now only gates `selectionTransformIDs` — the
  UNIFIED multi-select/group box under transformed ancestors is the remaining
  gap (nested GROUPS are still move-only; resizeSelection works in doc space).
  Smoke test: inside a flipped group — resize a leaf by each handle (anchored
  corner stays put, no jump on grab), shift-proportional, drag past opposite
  edge (flip crossing), rotate by knob (tracks cursor direction), same under
  a rotated+flipped group; regression-check top-level resize/rotate.

_Newest entry on top. Update every session._

- **2026-07-07 — Session 189 (noise + dissolve effects, feTurbulence round-trip):**
  Added `Effect.Kind.noise` and `.dissolve` — stackable, SVG-native texture
  effects (owner requested "add texture easily; layer multiple effects; ideal =
  SVG-built-in"). New shared `Color/TurbulenceNoise.swift` implements the SVG
  1.1 `feTurbulence` Perlin algorithm verbatim (spec §15.7.15) with an LRU tile
  cache; added to BOTH targets' membership (per the CLAUDE.md gotcha).
  `Effect` grew feTurbulence-mirroring fields (turbulenceType/frequency/octaves/
  seed/monochrome/amount + per-effect `blend`), all `decodeIfPresent`-defaulted
  so old `.design` files open unchanged. Canvas + raster export: noise draws
  after inner shadows clipped to the silhouette (silhouette-less nodes use a
  transparency layer + destination-in punch); dissolve builds a thresholded
  luminance mask that clips content AND shadow casters. SVG export rewrites
  `svgEffectsFilter`: dissolve → feTurbulence + feColorMatrix + feComponentTransfer
  threshold + feComposite-in (shadows then cast from the dissolved source);
  noise → feTurbulence + feColorMatrix (amount into alpha, mono via R-broadcast)
  + feComposite-in + feBlend; filter now sets `color-interpolation-filters="sRGB"`
  to match Core Graphics. SVG import gains `collectFilters`: reconstructs noise /
  dissolve / drop / inner-shadow effects from filter defs (recognises our chains
  exactly, degrades unknown feTurbulence to an editable noise effect). Inspector:
  Noise + Dissolve in the add menu, type picker, Freq/Oct/Seed fields, seed
  shuffle (die icon), Amt %, Mono toggle, blend-mode picker; color well now
  shadow-only; legacy Bg-Blur picker guard preserved. NOT yet compiled — owner
  to build in Xcode and test: (1) old docs still open, (2) noise/dissolve on
  rect + text + group, (3) SVG export opens correctly in a browser, (4) paste
  that SVG back and confirm effects reattach, (5) thumbnail extension builds.
  Note: one CanvasView write was silently reverted by Dropbox sync mid-session;
  re-applied with fsync and verified (already cleaned up).

- **2026-07-06 — Session 188 (v1.2 kickoff: bug-fix lane + BUG-003 pass):**
  Confirmed v1.2 is the active cycle (`MARKETING_VERSION 1.2`, build 3) and moved
  local work onto a new `dev` branch. Deleted the stale `docs/.__writetest` file
  from prior edit-permission troubleshooting; the manually added Phase 19 planning
  block is intentional owner-authored roadmap context. Added a root `.gitignore`
  for local build/DerivedData output so Dropbox-local build folders do not pollute
  git status. First bug-fix pass targeted **BUG-003**. Initial attempt made
  pan/zoom snapshots request document-sRGB instead of the window/Display-P3 color
  space; owner testing still showed the shift, and found the crucial clue that a
  moved gradient stays correct while static gradients change during drag. Follow-up
  fix keeps gradient/shadow content on the live vector/compositing path: pan/zoom
  skips bitmap blit when visible gradient/shadow content exists, and drag gestures
  force true live compositing when any non-dragged visible gradient/shadow content
  exists. Plain content still uses the fast snapshot paths. Marked BUG-003
  fixed after owner verification: saturated semi-transparent gradients and shadows
  no longer darken/change during pan/zoom or while dragging another shape. Added
  canvas usability polish for grouped/nested layers: once a child inside a group
  is active, canvas clicks stay at that active group level instead of jumping back
  to the outer group; Shift-click toggles sibling children in the same group; and
  ⌘A expands the current selection level (group children, artboard contents,
  source-window top level, or all artboards + wall items when an artboard is
  selected). Fixed text-case preservation during text edit commits so duplicated
  text boxes keep non-destructive transforms such as uppercase instead of
  reverting to "As typed". Follow-up fix for source components with auto-padding:
  the layout engine now remeasures auto-size text leaves before managed frames
  re-hug, and the active inline text editor follows the reflowed model frame so
  text-case/paragraph metric edits do not wait for a text commit to resize the
  padded frame. Screenshot follow-up tightened the geometry contract: a component
  source whose top level is one managed frame now uses that re-hugged root as its
  dynamic source/instance bounds, and selection-transform boxes treat
  auto-padding/layout groups as real frames instead of descendant unions, so
  rendered backgrounds, handles, component-panel sizes, and placed-instance boxes
  stay in sync. Design Language panel polish: Recent colors now render as smaller,
  tighter history chips/rows so they are visually subordinate to saved palette
  swatches. Verification: Debug build succeeds with
  `xcodebuild -project "EXP [design].xcodeproj" -scheme "EXP [design]" -configuration Debug -derivedDataPath /tmp/EXP-design-DerivedData build`.

- **2026-07-05 — Session 187 (v1.1 release + v1.2 kickoff):**
  Cut the **v1.1** release. Wrote tester-facing release notes
  (`RELEASE-NOTES-v1.1.md`) covering Design Language, the OKLCH/WCAG-AA color
  picker, transparent PNG export, System Monospaced document font, sharper raster
  imports, the centered titlebar, and the App/Document Settings split. Added
  `docs/RELEASE-CHECKLIST.md` (reusable zip → tag → GitHub Release → next-version
  steps). Bumped the Xcode project to **MARKETING_VERSION 1.2 / build 3** across
  all four build configs to open the v1.2 development cycle on a `dev` branch.
  Release tagging/upload run by the owner (GitHub auth is off-box). Verification:
  `grep MARKETING_VERSION` on the pbxproj shows 1.2 in all configs; open in Xcode
  and confirm a clean build before continuing.

- **2026-07-05 — Session 186 [site] (public website tester/download refresh):**
  Unified the homepage/download navigation, moved the tester signup/download
  workflow onto the download page, added accessibility and Design Language
  feature callouts with the new screenshots, and documented the Resend-based
  release-notification path. Added optional Resend contact storage behind
  `SIGNUP_STORE_CONTACTS=true` and taught the website sync script to hide
  progress entries marked `[site]`, `[website]`, or `[internal]` from the public
  roadmap feed. Verification: `npm run build` from `website/`.

- **2026-07-05 — Session 185 (transparent PNG export option):**
  Added a `Transparent background (PNG)` checkbox to the export accessory panel.
  The option is enabled for PNG and All exports, skips only the artboard
  background during PNG rendering, and leaves PDF/SVG behavior unchanged. The PNG
  bitmap is explicitly cleared before rasterizing so transparency is preserved.
  Verified with
  `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -destination 'platform=macOS' build`
  — **BUILD SUCCEEDED**.

- **2026-07-05 — Session 184 (system monospaced font option):**
  Checked the typeface picker against AppKit's installed font catalog after SF
  Mono / JetBrains Mono did not appear in the app list. Confirmed the picker was
  already using `NSFontManager.availableFontFamilies`; JetBrains Mono is not
  currently visible to AppKit on this machine, while Apple's UI monospaced face
  is exposed through system font APIs instead of as a normal family. Added a
  `System Monospaced` pseudo-family with regular/semibold/bold faces so document
  text can match the app's monospaced UI readouts. Verified with
  `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -destination 'platform=macOS' build`
  — **BUILD SUCCEEDED**.

- **2026-07-05 — Session 183 (sharper raster image imports/rendering):**
  Checked the raster drag/drop + paste path after small screenshots appeared
  soft on import. Preserved original file bytes for dragged images, changed the
  generic clipboard image fallback to PNG instead of TIFF, set final canvas image
  draws to high interpolation, and made screenshot-sized images decode at their
  requested cache bucket immediately instead of showing the 256px placeholder
  first. Verified with
  `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -destination 'platform=macOS' build`
  — **BUILD SUCCEEDED**.

- **2026-07-05 — Session 182 (Design Language Add supports multi-selection):**
  Updated the Design Language panel's Add action so multi-select saves every
  unique selected fill/gradient that is not already in the document library,
  instead of only saving a single selected fill. The Add button/help text now
  reflects the whole selection and the save is still one undoable document edit.
  Verified with
  `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -destination 'platform=macOS' build`
  — **BUILD SUCCEEDED**.

- **2026-07-05 — Session 181 (hide native title residue; log chrome bug):**
  Added a narrow titlebar residue hider for the lingering native dash/Edited glyph
  that could remain visible left of the centered custom title. The helper targets
  small native titlebar text/separator remnants while preserving stoplights and the
  live invisible document icon/versions anchor. Logged the remaining awkward
  behavior as `BUG-004` in BACKLOG: centered Edited can fail to appear and the
  rename/location popover still anchors left even though the centered title
  click technically works. Verified with
  `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -destination 'platform=macOS' build`
  — **BUILD SUCCEEDED**.

- **2026-07-05 — Session 180 (hide title icon/edited residue; use live native anchor):**
  Refined the custom titlebar bridge after tester found AppKit still drawing the
  document icon and native `-- Edited` residue on the left, and `NSDocument.rename`
  logging "anchor hidden" when launched from the centered title. The native
  document icon and versions/edited control now stay alive but are moved under the
  centered EXP title and made visually transparent; the centered click bridge now
  performs the versions/title control first instead of calling rename on a hidden
  title anchor. Verified with
  `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -destination 'platform=macOS' build`
  — **BUILD SUCCEEDED**.

- **2026-07-05 — Session 179 (titlebar bridge correction):**
  Backed out the brittle native-title view-tree hiding from Session 178 after it
  also hid the stoplight buttons. The window now hides AppKit's drawn title again,
  keeps the centered EXP-styled title as the only visible title, and uses a tiny
  transparent AppKit hit target over that styled title to send the native
  `NSDocument.rename(_:)` action (falling back to the document versions button)
  for rename/location behavior. Added direct KVO for `isDocumentEdited` so the
  centered Edited flag updates more reliably. Verified with
  `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -destination 'platform=macOS' build`
  — **BUILD SUCCEEDED**.

- **2026-07-05 — Session 178 (centered native document title behavior):**
  Fixed the doubled document title in the editor chrome. The visible heading
  remains the centered EXP-styled title with `.design` muted and the Edited state
  shown underneath in `EXPColor.accent`, while AppKit's real document title/proxy
  view is kept alive, made invisible, and repositioned under that centered
  heading so native rename/tags/location behavior remains available. Verified with
  `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -destination 'platform=macOS' build`
  — **BUILD SUCCEEDED**.

- **2026-07-05 — Session 177 (Settings window spacing + About links):**
  Cleaned up Settings window layout. The sidebar now stays visible (removed the
  default sidebar toggle and pins column visibility back to all), preserving the
  left navigation area as the settings list grows. Non-About panes now sit closer
  to the top with tighter top padding, while About keeps a centered layout for
  the shorter content. About now includes links to `https://expdesign.app/` and
  the bug-reporting examples section at `https://expdesign.app/download#reporting`.
  Verified with `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -destination 'platform=macOS' build`
  — **BUILD SUCCEEDED**.

- **2026-07-05 — Session 176 (Design Language Settings button size):**
  Tiny panel polish: the Design Language panel's secondary "Settings" button now
  uses a compact local secondary style at 11pt (two points smaller than the
  standard EXP secondary button) while keeping the same surface/border language.
  Verified with `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -destination 'platform=macOS' build`
  — **BUILD SUCCEEDED**.

- **2026-07-05 — Session 175 (Design Language panel final refinements):**
  Finished the last piece from the previous agent's interrupted pass. The Design
  Language panel now has a real swatch/list view toggle persisted via
  `exp.dl.viewMode`; list mode renders colors/gradients and recents as compact
  rows with swatch, name/category/value metadata, double-click apply, and the
  same context menus as swatch mode. The view controls are sticky at the bottom
  as an overlay, with panel contents scrolling underneath and bottom breathing
  room so the last row is not hidden. The panel's Settings action is now an
  explicit secondary "Settings" button that requests the document Design
  Language pane before opening Settings. Verified with:
  `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -destination 'platform=macOS' build`
  — **BUILD SUCCEEDED**.

- **2026-07-04 — Session 174 (Settings reorg + Design Language editor; gradient bug reopened):**
  Gradient darkening (BUG-003) is NOT fixed — the Session-173 sRGB interpolation
  change didn't resolve it, so it's reopened as needs-investigation with fresh
  hypotheses logged (premultiplied-alpha round-trip on a semi-transparent stop;
  snapshot P3 image drawn into a differently-spaced window context; possible
  interaction with the new picker color modes — verify stored RGBA is byte-identical
  after editing). Set aside for now per owner.
  **Settings reorg:** the sidebar is now two Sections — "App" (General, Canvas,
  Design Tokens, About) and "Document" (Design Language) — giving the small section
  titles the owner asked for. `SettingsPane` gained a `scope` (app/document) and a
  `designLanguage` case; `SettingsGroup` promoted to internal for reuse.
  **New `UI/DesignLanguageSettings.swift`:** a document-scoped bulk editor reached
  through `PanelHub.activeDocument` (Settings is app-wide, so it can't hold document
  state). It covers every action: manual add of a color OR gradient via a real
  `PaintWell` picker (name + category), category management (add / inline-rename /
  delete — delete keeps the colors as Other), a bulk entries table with per-row
  inline rename + category menu + delete (local draft state so typing doesn't spam
  undo), and import/export (EXP JSON file, paste HEX/CSS/Coolors, export JSON, copy
  CSS). Every edit is one undo step on the frontmost document.
  **First-stab gaps to refine:** drag-to-reorder entries/categories isn't wired yet
  (was the other half of the owner's item 3); Figma/XD import is stubbed as "future"
  in the copy only. Empty state prompts to open a document. **Not compiled by me** —
  owner to build.

- **2026-07-04 — Session 173 (fix: gradient darkening during pan/zoom):**
  Tester saw a saturated gradient darken while panning/zooming and snap back when
  still. Traced to `PaintRender.drawGradient` building the CGGradient in unmanaged
  `CGColorSpaceCreateDeviceRGB()` while stop colors are sRGB: the color-managed
  offscreen blit bitmap (window space, usually P3) color-matches an unmanaged
  gradient differently than the live window device context, so the shift shows only
  in the blit. Switched the gradient interpolation space to sRGB — matches the stop
  colors, solid fills, and export; shared file so canvas + thumbnails + export are
  all consistent. Logged as BUG-003 (done). The slight TEXT shimmer during motion is
  separate and expected: the blit scales a cached bitmap at `.interpolationQuality
  .low` mid-gesture, so anti-aliased edges wobble a hair until the settle render;
  can raise interpolation quality later if it bothers. The "Publishing changes from
  within view updates" log spam is the pre-existing BUG-002, unrelated. **Not yet
  compiled by me** — owner to build/confirm.

- **2026-07-04 — Session 172 (build fixes + Add button / category-pill menu):**
  Session 171 shipped two build errors (both auto-fixed by the Xcode agent; noted
  here so they don't recur):
  (1) `PaintSwatch` was declared in DesignLanguagePanel.swift AND already existed
  (identical) in `Color/PaintEditor.swift` — a redeclaration. The panel now reuses
  the existing one; do NOT re-add it.
  (2) `moveCategory` used `Array.move(fromOffsets:toOffset:)`, which is a SwiftUI
  extension — unavailable in Document.swift (Foundation/CoreGraphics only). Rewritten
  as a manual reorder. GOTCHA: don't use SwiftUI collection helpers in the shared
  model file.
  Then two refinements: the panel's **Add** button now uses the app accent
  (`.tint(EXPColor.accent)`, so it follows the system or user-set accent) instead of
  system blue, and disables when the selected shape's fill is ALREADY in the design
  language (new `addableFill`, checked via `firstAsset(matching:)`). Category filter
  **pills** got a right-click menu — Rename (alert) and Delete; deleting a category
  removes the tag from its colors (they fall back to "Other") but keeps the colors.
  **Not yet compiled by me** — for the owner to build; the two prior errors are
  already resolved in the synced files.

- **2026-07-04 — Session 171 (DL refinements: categories, filter pills, picker link):**
  Reworked the Design Language panel per tester direction.
  **Model (Document.swift):** replaced the fixed `status` (official/candidate/
  archived) with USER-DEFINED categories. `DesignLanguage` now has
  `categories: [DLCategory]`; `DesignAsset.status` → `categoryID: UUID?` (nil =
  uncategorized / "Other"). Categories are cross-cutting — a color AND a gradient
  can both be "Primary". New helpers: add/ensure/rename/remove/moveCategory,
  setCategory, save(_:category:), firstAsset(matching:), count(in:), categoryLabel.
  One-time decode migration seeds a "Primary" category from anything that was
  "official" (owner's choice); everything else becomes uncategorized. Old `status`
  is read into a decode-only `legacyStatus` (never re-encoded) and consumed by the
  migration.
  **Import/export (DesignLanguageIO):** EXP JSON envelope now carries `categories`;
  import returns (assets, categories) and `merge` remaps incoming category ids by
  name (creating missing categories), one undo step. CSS export drops the archived
  filter.
  **Panel:** groups are now just "Colors" and "Gradients"; categories are wrapping
  filter PILLS along the top (count baked into each pill, additive toggle, all on by
  default) via a small `FlowLayout` — pills wrap to multiple lines while the export
  menu + a prominent primary "Add" button stay stationary. Within each type section,
  items cluster under small category sub-labels; uncategorized shows as "Other"
  (always visible, no pill). Swatch context menu gained a Category submenu
  (assign / Other / New Category…); create-category via a "+" pill, the menu, or a
  swatch. Before any category exists it's just a flat Colors/Gradients list with the
  old "N saved" label.
  **Picker link (ColorPopover, item 4):** the picker's bottom-right now shows a
  "Save" action when the current color isn't in the design language, or the saved
  swatch + name + category when it is — reading the frontmost document via PanelHub
  (no color-well plumbing). Adds via one undo step.
  **Deferred:** item 3 (a dedicated Design Language editor as a Settings tab for
  bulk rename / reorder / drag-drop) is NOT started yet — next session. Item 5 came
  through empty. **Not yet compiled** — for the owner to build and confirm.

- **2026-07-04 — Session 170 (fix: panel show/hide in both modes):**
  Tester report — the new Design Language panel never appeared and there was no way
  to show it; in Multi-Window the whole Window-menu panel section (and Show/Hide
  Left/Right) was greyed out. Root causes + fixes:
  (1) The Window menu read only `focusedSceneValue(\.windowMenu)`, which is nil
  whenever a floating panel window is key — so the entire section disabled. Fixed:
  `WindowMenuItems` now falls back to `PanelHub.shared.activeApp` (the frontmost
  document) when there's no focused scene value, so the menu stays live no matter
  which window is key.
  (2) The per-panel items only toggled in Multi-Window (`reveal` was tray-only and
  disabled elsewhere). Replaced with a `toggle` that runs in BOTH modes via
  `AppState.togglePanel` (dock in single-window, tray in multi-window); showing a
  panel in single-window now also un-hides the right dock and focuses the floated
  window in multi-window.
  (3) `isApplicable` was a LIVE filter that hard-hid empty panels (Components until
  a component existed; and it would have trapped Design Language) with no override.
  It now returns true — every panel has a real empty state, so presence is controlled
  explicitly through the Window menu. NOTE: a side effect is that Components now
  shows its empty state by default in single-window instead of auto-hiding; hide it
  from the Window menu if unwanted.
  (4) Existing saved layouts predate the panel, so added a one-time
  `AppState.migrateNewPanels()` (keyed by `exp.panels.seen.v1`) that adds any
  never-before-seen panel to the single-window dock once — Design Language now
  appears for existing users without wiping their layout — and `.designLanguage`
  was added to `PanelHub.defaultPanels` for fresh Multi-Window seeding.
  Touched: PanelDock.swift, PanelHub.swift, AppState.swift. **Not yet compiled** —
  for the owner to build and confirm.

- **2026-07-04 — Session 169 (Phase 18f: local palette providers):**
  New pure `Color/PaletteProviders.swift`: a `PaletteProvider` protocol +
  `PaletteSuggestion` (title, terms note, paints), with local/offline generators
  built on the OKLCH + contrast math — an OKLCH lightness ramp (perceptually even
  steps through the seed's hue/chroma), complementary/triadic/analogous hue
  harmonies (rotated in OKLCH), and an accessible seed-background + same-hue
  foreground pair nudged until it clears WCAG AA (falls back to black/white). The
  panel's import/export menu gained "Generate from Color..." → a sheet with an
  editable seed color well and one row per suggestion (swatch preview + terms +
  Add), where Add saves that set as candidates (provenance "generated: <kind>")
  in one undo step. Seed defaults to the selection's fill, else a saved entry,
  else black. This closes the core of Phase 18 — the acceptance criteria (18g) are
  met end-to-end: save/mark/apply, copy/export/import without losing name/status,
  contrast visible where colors are chosen, and OKLCH powering picker + ramps +
  contrast-preserving suggestions.
  **Still open (refinements, logged for later):** image-based palette extraction
  (the one local generator not built), a `PaletteProvider` "add as official"
  action (today: add as candidate then promote), plus the earlier 18d/18e items
  (in-place swatch value editing, reveal-uses, menu-bar "Save Fill" command,
  style-dictionary/ASE export). **Not yet compiled** — for the owner to build.

- **2026-07-04 — Session 168 (Phase 18e: import / export):**
  Added a pure, UI-free `Color/DesignLanguageIO.swift` and merge logic on the model.
  **Canonical EXP JSON:** a small versioned envelope (`{ expDesignLanguage: 1,
  assets: [...] }`); decoding is tolerant (envelope, bare `[DesignAsset]`, or a
  whole `DesignLanguage` all import). **CSS export:** a `:root { --slug: value; }`
  block with unique slugs — solids as hex, gradients as `linear/radial-gradient()`;
  the panel's per-swatch "Copy As CSS variable / CSS gradient" now route through the
  same helpers (removed the panel's private duplicates). **Palette paste:**
  best-effort parse of HEX lists (hashed or bare, comma/newline), CSS custom
  properties (names preserved), and Coolors share URLs — string parsing only, no
  network fetch or scraping. **Merge:** `DesignLanguage.MergeMode` (keep both /
  skip duplicate values / replace by name), incoming entries get fresh ids +
  retained provenance, one undo step via `setModel`. Panel got an import/export
  menu (Import from File, Paste Palette, Export EXP JSON, Copy All as CSS) and a
  paste sheet with a merge-mode picker. Still app-only, no `.xcodeproj` edits.
  **Open:** a dedicated style-dictionary token JSON + ASE export (deferred in 18e),
  and a richer name-conflict resolution UI (today it's a single mode chooser).
  **Not yet compiled** — for the owner to build in Xcode and report back.

- **2026-07-04 — Session 167 (Phase 18d: Design Language panel):**
  Turned the reserved Color panel into a real, document-local **Design Language**
  panel. `PanelID.color` was repurposed to `.designLanguage` (only referenced in
  `PanelDock.swift`; the other `.color` hits are the text-run enum), made
  implemented + always-applicable, added to `Workspace.default`'s right column and
  the Window-menu panel order. New app-only `UI/DesignLanguagePanel.swift` (auto-
  included via the synchronized group) reads `document.model.designLanguage` live
  and renders four sections — Official, Candidates, Gradients, Recents — as
  checkerboard-backed swatches (a new `PaintSwatch` previews solids AND gradients).
  Actions, all one undo step through `setModel`: apply to selection (walks selected
  nodes, sets each shape's fill / text run color, and records the paint under
  Recents), save the selected shape's fill as a candidate (+ button, enabled only
  when a fill is selected), promote/demote/archive/restore, rename (alert field),
  duplicate, delete, and Copy As HEX/RGB/HSL/OKLCH/CSS-variable (solids) or CSS
  gradient (gradients). Status shows as a dot (filled = official, ring = candidate);
  archived entries drop out of the working sections but stay in the file.
  **Still open in 18d:** in-place editing of a swatch's value (open a picker bound
  to the entry) and "reveal all uses" in the document; wiring a menu-bar +
  shortcut command for "Save Fill to Design Language" to satisfy the command-
  coverage rule (today the save/apply actions are panel-contextual, like align).
  Recents currently fill when you apply from the panel; feeding them from the
  inspector color popover is a small follow-up. **Not yet compiled** — for the
  owner to build in Xcode and report back.

- **2026-07-04 — Session 166 (Phase 18 first build: model + contrast + mode-aware picker):**
  Landed the foundation slices of the v2 color/design-language work — no
  `.xcodeproj` edits needed (the app folder is a synchronized group; new app-only
  files auto-join the app target, and shared model went into an already-shared file).
  **18a — document model:** added `DesignLanguage` + `DesignAsset` to
  `Model/Document.swift` (which is already a member of BOTH the app and
  EXPThumbnail targets, so no target-membership exception was required — same
  reason `RGBAColor`/`Paint` live near there). Entries carry `id`, `name`,
  `status` (candidate/official/archived), `value` (`Paint` — solids AND gradients
  share one shape), `notes`, `tags`, `provenance`; recents are a separate capped
  paint list. Non-destructive promote/archive/rename/remove helpers; all edits
  are undoable through the existing `setModel` funnel. Tolerant decode
  (`decodeIfPresent`, unknown status → candidate) and a new `Document.designLanguage`
  key that older `.design` files simply lack. Model only — the panel is 18d.
  **18c — ContrastMath:** new pure `Color/ContrastMath.swift` — WCAG 2.x relative
  luminance + contrast ratio, straight-alpha flattening over background, AA/AAA
  labels for normal/large/non-text, plus an advisory OKLCH-lightness
  `suggestForeground` (math only, no UI yet). APCA deliberately left out until
  it's more than advisory.
  **18b — mode-aware picker:** `Color/ColorPopover.swift` now has an HSB / HSL /
  OKLCH segmented authoring control that swaps the actual controls (2-D SV field
  for HSB; native, VoiceOver-friendly axis sliders for HSL and OKLCH), an honest
  "In sRGB gamut / Outside sRGB — clamped" indicator driven by a new
  `ColorMath.oklchToRGBGamut`, and a contrast strip showing the color on white and
  on black with ratio + normal-text level. Storage decision recorded: stay sRGB
  with honest gamut warnings for now (no wide-gamut `ColorValue` yet).
  **Still open in 18b/18c:** OKLCH-driven palette/ramp generation; wiring the
  contrast adjustment helper and the recents/saved-swatch UI into the popover
  (both want document access, which arrives naturally with the 18d panel);
  contrast comparison against the artboard/any two library swatches. **Not yet
  compiled** — written for the owner to build in Xcode and report back.

- **2026-07-05 — Session 165 (v2 color/design-language roadmap shaped):**
  Organized the owner's color brain dump into a real v2 plan. Added **Phase 18
  — Design language library & color workflow** covering: document-local saved
  colors/gradients, candidate vs. official status, true HSL/OKLCH authoring
  controls, sRGB/P3 gamut decisions, WCAG-first contrast checking, a new Design
  Language panel, import/export, palette inspiration providers, and first-class
  saved gradients. Updated BACKLOG with pick-up-able feature slices: FEAT-001
  expanded into the document color-library model, FEAT-002 clarified as
  mode-aware picker UI, plus FEAT-005 contrast checker, FEAT-006 Design
  Language panel, and FEAT-007 palette inspiration/import providers. Research
  note: Adobe Color/Coolors/Figma public palette pages are good inspiration/
  export surfaces but no clearly documented public "trending palettes" API was
  found; The Color API has public conversion/scheme endpoints; RandomA11y is
  open-source/generator-shaped.

- **2026-07-03 — Session 164 (doc/status sync for the public download page):**
  Trued up phase statuses that feed expdesign.app/download. Phases 3, 11, and
  13 marked ✅ DONE (13's remaining unchecked items are labeled deferred
  nice-to-haves). Introduced a third status tier — **"✅ DONE — refinements
  planned"** — applied to Phases 8 (color/gradients) and 10 (effects);
  `website/scripts/sync-content.mjs` parses it into a "done · refinements
  planned" badge (new CSS class, robust class slugs in App.jsx, and public
  titles now drop "(Session NN)" suffixes). Fixed stale `.exp` references to
  the current `.design` extension in ROADMAP Phase 2, ARCHITECTURE.md,
  BACKLOG.md (FEAT-001), the tester copy in sync-content.mjs, and two
  strings on the /download page. CLAUDE.md "Current status" rewritten to
  match reality. Verified: `npm run sync` emits the expected statuses and
  zero `.exp` mentions; App.jsx parses clean.

- **2026-07-03 — Session 163 (tester download landing page):**
  Added the direct, unlinked tester landing page at `/download` in the Vite
  website. The page matches the existing EXP site system and includes a GitHub
  Releases "download latest build" CTA, macOS install steps, early-build safety
  warnings, expectations for non-technical product testers, examples of useful
  bug reports and improvement requests, current known issues, and a
  human-readable feature snapshot synced from `docs/ROADMAP.md`. Extended
  `website/scripts/sync-content.mjs` to emit tester-facing feature highlights
  and known bugs from the roadmap/backlog sources. Added a Vercel rewrite so
  `expdesign.app/download` loads the SPA directly. Verified with `npm run build`
  and Playwright screenshots at 1440px desktop + 390px mobile; no horizontal
  overflow, correct H1, and the primary CTA targets GitHub's latest release URL.

- **2026-07-02 — Session 162f (BUG-002 squashed — deferred stepper writes):**
  The "Publishing changes from within view updates" warning (owner-isolated
  repro: holding ↑/↓ on inspector fields). `NumericStepping.onKeyPress` wrote
  the bound value synchronously inside SwiftUI's key-event update pass — every
  key repeat mutated the document's @Published model mid-update. Fix: compute
  the stepped value in the handler, write it via `DispatchQueue.main.async`
  (one tick later, outside the update). Behavior identical: ±1 / ⇧±10 / ⌥±0.1,
  acceleration every 5 repeats, float-drift rounding, undo granularity.
  **Needs owner test:** hold ↑ on X/Y/W/H, rotation, opacity, gap, zoom fields
  — values step smoothly, console stays SILENT. If a flood still appears at
  app LAUNCH without touching the inspector, that's a second site (see the
  BUG-002 entry for the breakpoint hunt).

- **2026-07-02 — Session 162e (first-appearance image placeholder + zoom-range triage):**
  Latest log: pan/zoom blit fully healthy (frame(blit) 0.4–0.8ms, zero
  strikes). Remaining blit-images spikes (43–200ms) are FIRST-APPEARANCE
  synchronous decodes — panning into territory where an image was never
  decoded at any size. Fix: first appearance now decodes only a 256px
  placeholder synchronously (a few ms, never blank) and the real bucket
  arrives via the async path; placeholder is stored under its own 256 bucket
  key so future lookups reuse it. Also: owner flagged the 5% `minZoom` floor
  as potentially cramping their spread-out wall workflow — filed FEAT-004
  (lower to ~1%, verify, only gate on the performance mode if measurements
  demand it). NOTE for next log: image spikes should now cap at ~placeholder
  cost; if 100ms+ spikes persist, verify the 162d/e build actually ran.
  **Needs owner test:** pan into fresh image-heavy areas — images appear
  soft-then-sharp with no stall; doc open still shows images immediately.

- **2026-07-02 — Session 162d (bucket verdict: images, not layers — async mip decode):**
  The blit-layers bucket ACQUITTED the group layers (1.8–6ms). The convict:
  **blit-images spiking 46–248ms** — every zoom crossing a power-of-two mip
  bucket re-decoded each large photo SYNCHRONOUSLY on the main thread. Fix in
  `cgImage(for:targetPx:)`: when the wanted bucket isn't cached, draw the
  nearest ALREADY-CACHED bucket now (larger first — sharp; else smaller —
  briefly soft) and decode the right bucket on a background queue
  (`imageDecodeQueue`, in-flight de-dupe, `UncheckedBox` to move the immutable
  CGImage across actors, needsDisplay on completion). First-ever appearance
  still decodes synchronously so images never pop in blank on document open.
  `Self.decodeImage` is nonisolated static (fresh CGImageSource per call —
  thread-safe).
  Also identified from the idle frame cadence: **rulers force a full ~80ms
  render per mouse move** on heavy docs — filed as PERF-005 with the
  retained-snapshot design (settle render doubles as a reusable last-frame
  snapshot; idle repaints become blits) + a cheap overlay-view stopgap.
  **Needs owner test on the image doc:** pinch-zoom through several levels —
  photos may go briefly soft but NO stalls (blit-images should stay single
  digits; captures under budget); confirm no blank images on document open.

- **2026-07-02 — Session 162c (two-doc comparison: bg-blur migration + cold-halo retry + layer forensics):**
  Owner tested two documents to rule out doc-specific weirdness. Readings:
  **Doc 1 (1,724 nodes):** frames 13–25ms — healthy. But BOTH pan-capture
  strikes burned at launch (860ms, 589ms → blit disabled). Diagnosis: the
  halo reaches into never-yet-rendered territory, paying first-ever text
  layouts/image decodes for off-screen content — so early captures stay slow
  until the doc has been toured. Fix: **after a strike, the retry capture
  drops the halo** (viewport-only ≈ one frame); only if THAT also blows the
  budget does the valve disable.
  **Doc 2 (476 nodes, the original image doc):** the real "waiting" — frames
  sustained at ~80ms with only 360 drawn, and capture buckets again show
  ~55ms UNACCOUNTED (blit-render 81ms vs ~25ms bucketed). Prime suspect:
  the remaining opacity/blend transparency layers on big semi-transparent
  GROUPS (bounded since 161g, but a screen-sized group still buys a
  screen-sized buffer per frame). Added a **blit-layers** bucket timing
  begin/endTransparencyLayer during capture — the next log names the cost
  instead of guessing (the 161-series lesson).
  **Bg-blur abandoned (owner decision):** documents now MIGRATE ON OPEN —
  `ExpDocument.init(configuration:)` strips every backgroundBlur effect
  (top-level nodes, nested groups, component sources); saves clean on next
  edit. The picker's legacy "Bg Blur (off)" entry stays for unsaved docs.
  **Needs owner test:** (1) reopen the old image doc — effects lists show no
  Bg Blur rows, no picker console spam; (2) doc-1 launch: expect at most one
  "will retry" line and the blit STAYING enabled; (3) doc-2: one pan in
  Testing Mode → send the blit-* line — if blit-layers ≈ 50ms we build the
  group-layer fix next (candidates: cache group composites, or skip the layer
  for groups whose children provably don't overlap).

- **2026-07-02 — Session 162b (drag-capture warm-up + two-strike valve + legacy picker):**
  Owner's 884→1724-node stress log diagnosed three things:
  1. **Drag beachball found:** `dragblit-capture 284ms` (vs 9–20ms frames) —
     cold caches: a bulk duplicate right before the drag empties the text/image
     caches and the first capture repays them all. Fix: **warm-up ticks** — the
     first two drag frames render live (10–20ms each, imperceptible, and they
     warm the caches), the capture happens on tick 3. Tiny nudge-drags now
     never pay for a capture at all.
  2. **Pan valve was one-and-done:** the single cold 500ms capture at launch
     benched the blit for the whole run even though warm captures were ~40ms.
     Now a **two-strike** valve: one slow capture logs "will retry next
     gesture"; only two consecutive slow captures disable; a fast capture
     clears the strike.
  3. **Legacy Bg Blur picker warning** ("selection backgroundBlur is invalid"):
     the effect-kind Picker now includes a "Bg Blur (off)" tag ONLY while a
     legacy effect holds that value — old docs stop tripping AppKit, adding new
     bg-blur stays impossible.
  Also confirmed from the log: frames 20–24ms with ALL 1,724 nodes drawn (no
  culling) — the base renderer holds up; snap scan at 449 candidates cost
  ~3ms/tick (fine, watch at 5k+ nodes).
  **Needs owner test:** repeat the duplicate-then-drag stress — expect two
  ordinary frames then `dragblit-capture` ≈ 2 frames and 1–3ms `frame(drag)`;
  the launch log may show one "will retry" line but pan blit should stay
  enabled; the old doc's effect row shows "Bg Blur (off)" with no console spam.

- **2026-07-02 — Session 162 (PERF-002 + PERF-004: conditional fidelity + the user dial):**
  Owner prioritized the user-controlled performance setting ("every designer
  works differently"). Built both halves as one feature:
  **Engine (PERF-002):** `fullFrameEMA` — an always-on rolling cost of a full
  scene render (two timestamps per frame, EMA so outliers don't flip modes).
  At each drag gesture's FIRST tick, `shouldTrueCompositeDrag` decides once:
  if the dragged subtree contains any non-normal blend mode AND the EMA fits
  the mode's budget, the whole gesture uses TRUE live compositing (full render
  per tick — difference/overlay shapes keep their real look while moving);
  otherwise the fast below/above snapshot blit. Plain-content drags always take
  the fast path (fidelity spend would buy nothing — they already composite
  correctly against the BELOW layer).
  **Dial (PERF-004):** Settings ▸ Canvas ▸ **Performance** — EXPSegmented
  "Speed focus / Balanced / Detail focus" (design-system control, a11y label +
  hint, plain-language footnote), persisted through the existing synced-prefs
  pattern as `AppState.CanvasPerformanceMode` (`exp.pref.performanceMode`,
  default balanced). Per mode: TRUE-drag budget 0 / 18 / 40 ms, pan-snapshot
  halo 0.15 / 0.25 / 0.40, settle delay 0.12 / 0.08 / 0.05 s. Files:
  AppState.swift (enum + synced pref), SettingsWindow.swift (key + pane group),
  CanvasView.swift (EMA + decision + halo/settle now read the mode). No new
  files; AppState/SettingsWindow are app-target only, no EXPThumbnail risk.
  **Needs owner verification:** (1) Settings shows the new group; switching
  survives relaunch and other open windows follow (synced prefs). (2) On a
  small doc, set Detail focus, give a shape "difference", drag it across
  content — it should KEEP its difference look while moving; same drag under
  Speed focus flattens until mouseUp (expected). (3) On the big stress doc,
  Detail focus must not beachball — if frames are slow the engine silently
  falls back to fast. (4) Testing Mode: `frame(drag)` lines disappear during
  TRUE-composite drags (full `frame` lines instead) — that's the tell for
  which mode a gesture chose.

- **2026-07-02 — Session 161m (triage: post-phase queue set):**
  Owner isolated the "Publishing changes from within view updates" warning:
  it fires when ARROW-STEPPING inspector values — `NumericStepping.onKeyPress`
  writes the binding synchronously during a view update. Filed as **BUG-002
  (P1)** in BACKLOG.md with the likely one-tick-defer fix; owner wants to
  tackle it this weekend alongside closer testing of pixel snapping + grid
  performance. Also filed from owner feedback: **PERF-002** — conditional
  fidelity for drags (blend-mode shapes like difference/overlay should keep
  their TRUE composite while moving when the doc is cheap enough — thresholds
  on frame cost / node count / zoom — falling back to the fast blit only when
  needed); **PERF-003** — panning refinements (adaptive halo, tiled
  snapshots); **PERF-004** — a user-facing "Speed ↔ Design detail" preference
  that exposes PERF-002's thresholds (the humane version of Photoshop's
  memory dial). BUG-001 marked done (fixed by the 161 pixel-honesty work).
  No code this session — queue only.

- **2026-07-02 — Session 161l (PERFORMANCE PHASE CLOSED — verified):**
  Owner stress-tested a fresh doc (duplicating up to 435 nodes "willy-nilly")
  and confirmed it "definitely feels much faster." Final verified numbers:
  **drag frames 1.5–3.6ms** (`frame(drag)`, was 45–105ms) after a one-time
  15–67ms `dragblit-capture` per gesture; **pan/zoom 0.4–0.9ms** (`frame(blit)`)
  with 17–84ms captures, never budget-disabled; **baseline full renders
  9–35ms at 435 nodes** (was 45–105ms at ~400). Duplication spikes
  (~140–240ms one-off per bulk duplicate) are model-copy + undo + first paint
  of the new nodes — proportional and accepted. The 161 series (a–l) is
  summarized in docs/PERF-HANDOFF.md; the transparency-layer clip rule is the
  single most important thing to preserve.
  **Remaining (not perf-critical, next sessions):**
  1. The ~40× "Publishing changes from within view updates" SwiftUI warning at
     launch (Session 124-era, clearly reproducible now — top candidate).
  2. `snap` hit 17–19ms once at 435 nodes with snapCands 0 — snapNodeOffset
     likely scans all nodes even with no candidates; spatial index if it grows.
  3. §6.2 visual regression pass on the OLD image-heavy doc (opacity groups,
     one PNG/PDF export) — quick eyeball, not yet formally done.
  4. BACKLOG: canvas clips instance children to viewBox, export doesn't — unify.

- **2026-07-02 — Session 161k (owner's SVG find — single-paint-op fast path):**
  Owner discovered imported SVG icons (Apple symbols) are groups of shapes each
  with a semi-transparent fill AND a 0-width transparent stroke. Diagnosis: the
  0-width stroke is NOT a render cost (every draw site guards `strokeWidth > 0`)
  — but the per-shape OPACITY was buying a transparency layer per shape, and
  for a node whose drawing is ONE compositing operation (a fill with no
  visible stroke — exactly these icons) the layer is pure waste: plain context
  alpha/blend composites identically. New `isSinglePaintOp(_:)` in CanvasView
  (mirrored as `exportIsSinglePaintOp` in ExportRenderer): one fill OR one
  stroke, no enabled effects → `ctx.setAlpha`/`setBlendMode` instead of
  `beginTransparencyLayer`. Text keeps the layer (glyphs can overlap under
  tight tracking); groups/instances keep it (they composite children).
  Importer cleanup (SVGImporter): `stroke: none` now stores width 0 with the
  MODEL-DEFAULT black color instead of `.clear` — a transparent chip at width 0
  lied in the inspector, and bumping width would have added an invisible
  stroke. Existing documents keep their `.clear` strokes (inert; `fillOp`/
  `strokeOp` treat zero-alpha as no-op so they still get the fast path).
  **Needs owner test:** baseline `frame avg` on the icon-heavy doc should drop
  (hundreds of layers eliminated); verify semi-transparent icons look identical
  (esp. any with BOTH visible fill and stroke — those still layer), and one
  export.

- **2026-07-02 — Session 161j (pan halo — no more blank edges):**
  Owner feedback: content panned into view showed as blank background until the
  settle render ("minor freakouts"). Three changes to the pan/zoom blit:
  1. **25% halo** (`blitHaloFraction`) — the snapshot now captures 1.5×1.5
     viewports (~2.25× capture cost, still ≈2 frames), so slow pans reveal real
     pre-rendered content. `renderCanvas` gained a `viewport:` param (culling +
     background fill follow it); `offscreenBacking(sizePt:)` is parameterized;
     the two other captures + blur path now read `cg.height` for their flip
     transform instead of `blurBackingPx`.
  2. **Mid-gesture recapture on halo exhaustion** — doc-space containment check
     in `beginPanZoomInteraction` (48pt early margin) drops the snapshot the
     tick BEFORE blank would show, so a long pan gets a ~30–80ms refresh instead
     of empty space. Blit math now includes the region-origin term.
  3. **Settle 0.12s → 0.08s** and capture budget 0.25s → 0.4s (halo is 2.25×;
     the valve is for pathology, not routine spikes).
  **Needs owner test:** slow pan and fast flick across board edges — expect no
  blank areas for pans up to ~25% of the window per capture, brief soft refresh
  beyond that, full detail ~80ms after stopping. Perf keys unchanged.

- **2026-07-02 — Session 161i (drag-overlay blit — the last perf lever):**
  Built the drag-overlay blit from PERF-HANDOFF.md §6.3. During any node-shaped
  drag (move/resize/rotate/draw/line/path-point — see `activeDragNodeIDs`), the
  static scene is captured ONCE into two bitmaps split at the dragged nodes'
  z-position: BELOW (opaque: background + boards + nodes underneath) and ABOVE
  (transparent: nodes on top + grids + guides). Each tick then blits below,
  draws only the dragged TOP-LEVEL subtrees live (nested drags map up via
  `topLevelAncestorID`, so siblings stay correct), blits above, and draws live
  chrome (smart guides + selection + rulers). Z-order stays truthful — no
  dragged-thing-floats-on-top artifact. Recaptures if zoom/pan/window-size
  change mid-drag (scroll-during-drag works); `dragBlitUnsupported` falls back
  to full rendering for gestures the capture can't represent; everything clears
  at mouseUp. Refactors: node-loop body → `drawCulledTopLevelNode` (shared by
  renderCanvas, both captures, and the live dragged draw — identical cull+clip
  everywhere); selection chrome → `drawSelectionChrome`. New perf keys:
  `frame(drag)` (expect ~1–3ms) and `dragblit-capture` (expect ≈ two frames,
  once per gesture). Known mid-gesture approximations (settle at mouseUp
  restores exactness): blend-mode statics in the ABOVE layer composite as
  normal-over; statics BETWEEN two dragged z-positions lump into ABOVE.
  Also: owner found Apple docs confirming the transparency-layer perf rule;
  Instruments (Time Profiler / Core Animation) noted as the sanctioned
  alternative to our Testing-Mode buckets for future hunts.
  **Needs owner verification:** build, Testing Mode, drag a group — expect
  `frame(drag)` ~1–3ms and drags that feel like pan/zoom now do. Then the
  §6.2 visual regression pass (opacity groups, exports) closes the phase.

- **2026-07-02 — Session 161h (handoff):**
  Owner near usage limits — full state written to **docs/PERF-HANDOFF.md**
  (root causes with evidence, dead theories, the transparency-layer clip rule,
  what's verified vs pending, drag-overlay-blit design, verification protocol).
  **161g VERIFIED by the corrected final log:** blit-capture 3,325ms →
  13–75ms typical, blit stays enabled all run, frame(blit) 0.6–2.5ms across
  pans/zooms — pan/zoom is solved. Occasional capture spikes (~140–190ms) are
  one-off ImageIO mip decodes when images first enter view (self-healing).
  Remaining complaint: node DRAGS still full-render at 45–105ms/frame — the
  drag-overlay blit (designed in PERF-HANDOFF.md §6.3) is the next lever.
  Next session: start at PERF-HANDOFF.md §6.

- **2026-07-02 — Session 161g (opacity layers, part 2 — groups/instances):**
  161f cut capture 3,325ms → 745ms; the owner confirmed the doc is full of
  semi-transparent items. The remaining ~720ms is the case 161f left wide:
  GROUPS/INSTANCES with opacity/blend still opened full-canvas layers. New
  `paintBoundsView(_:offset:)` computes conservative view-space paint bounds
  for any node kind (leaf = frame + cull margin; group = recursive union of
  visible children + rotation growth; instance = its viewBox, which instance
  drawing already hard-clips to) and the opacity/blend layer now always clips
  to it. ExportRenderer mirrors this via `exportPaintBounds` — with one
  difference discovered on the way: export draws instance children UNCLIPPED
  (no viewBox crop, unlike the canvas — pre-existing inconsistency, not
  touched), so its instance bounds union the resolved children instead.
  **Needs owner test:** Testing Mode, one pan — expect blit-capture well under
  250ms and the blit staying enabled; then judge pan/zoom + drag feel.
  Remaining known gap after this: drags still full-render every frame
  (35–60ms). Planned next lever if still not smooth enough: reuse the (now
  cheap) snapshot to blit the static scene during node drags and redraw only
  the dragged nodes on top.

- **2026-07-02 — Session 161f (FOUND IT — unclipped opacity/blend layers):**
  161e buckets: blit-render 3,325ms; shadows 1.1 + images 6.8 + text 1.3 +
  shapes 12.8 + boards 2.7 + makeImage 0.1 = **~25ms accounted**. All content
  drawing is fast — the 3.3s had to be in per-node scaffolding. Culprit: the
  whole-layer opacity/blend transparency layer in `drawNode` (any node with
  opacity < 100% or a blend mode) opens with NO clip of its own, and a
  transparency layer allocates a buffer the size of the CURRENT CLIP — the
  entire canvas in the snapshot path — per semi-transparent node. It wraps the
  whole node draw, which is exactly why no content bucket saw it. Fixed in
  `drawNode`: leaf nodes clip the layer to `rect` grown by `nodeCullMargin`
  (the culling invariant for a node's paint reach — stroke + shadow + rotation),
  so output is pixel-identical; groups/instances keep the wide clip (children
  may paint outside the frame). Same fix applied to `drawExportNode` in
  ExportRenderer (new `strokeHalfWidth` helper) — big PNG/PDF exports paid this
  cost too. Masks were checked: they clip by path, no layer, no issue.
  **Needs owner test:** Testing Mode ON, one pan — blit-capture should finally
  be ≈ one frame and the blit should stay enabled (no "disabled for this run"
  line). Also confirm opacity/blend layers still composite correctly (a
  semi-transparent overlapping fill+stroke shouldn't double-darken) and an
  export still looks right.

- **2026-07-02 — Session 161e (capture forensics, round 2):**
  161d buckets came back: blit-render 3315ms, but shadows 1.2 + images 6.8 +
  text 2.5 + makeImage 0.1 = **only ~10ms accounted for**. The colorspace theory
  is dead too (P3 backing didn't move the number). The 3.3s therefore lives in
  plain shape drawing, artboard backgrounds, or traversal — none of which were
  bucketed. Added: `blit-shapes` (all leaf rect/oval/polygon/line/path drawing,
  timed at the top of drawNodeContent, groups/instances excluded so recursion
  doesn't double-count) and `blit-boards` (drawArtboardBackground). Also clipped
  the artboard background shadow to board + 24px (same rule as the 161c
  drop-shadow clip — unclipped setShadow can allocate a context-sized surface).
  If the next log shows shapes+boards ≈ 3.3s we know the layer; if it shows a
  large UNACCOUNTED remainder, the cost is in traversal/clipping/chrome and gets
  bucketed next.
  **Needs owner test:** Testing Mode ON, one pan gesture, send the blit-* line.

- **2026-07-02 — Session 161d (capture instrumentation + colorspace):**
  Round 3 of the perf log: drag-warm caches CONFIRMED working (group drags
  320ms → 35–47ms, instCacheHit 4 throughout); pan/zoom blit frames 0.7–0.9ms.
  But blit-capture is STILL ~3.3s — both prior theories (pixel format, shadow
  transparency layers) failed to explain it, so the capture render is now
  instrumented instead of guessed at. Testing Mode prints new one-shot buckets
  on the first gesture: `blit-render` (total scene render), `blit-makeImage`
  (bitmap copy), and `blit-shadows` / `blit-images` / `blit-text` (per-category
  time inside that render). The dominant bucket names the real culprit.
  Speculative fix included: the offscreen backing now uses the WINDOW's
  colorspace (Display P3 on modern Macs) instead of generic sRGB — P3-tagged
  photos drawn into an sRGB bitmap force per-pixel CPU color matching the
  on-screen render never pays. Backing rebuilds if the colorspace changes
  (value equality, not identity).
  **Needs owner test:** Testing Mode ON, one pan gesture, send the flush line
  containing blit-render / blit-shadows / blit-images / blit-text. If capture
  is suddenly ≈ one frame, colorspace was the answer.

- **2026-07-02 — Session 161c (shadow transparency layers + drag-warm caches):**
  Second perf-log round-trip. Native BGRA did NOT fix the capture (still 3.4s) —
  real cause found: `EffectsRender.drawDropShadow` opened a transparency layer
  with **no clip**, and a transparency layer allocates its buffer at the current
  clip size — on screen that's the dirty rect, but in the offscreen snapshot it
  was the WHOLE canvas, per shadowed node. Fixed: new `castBounds` parameter
  clips to caster + blur + offset (+8px pad) before the layer — pixel-identical
  output, buffer shrinks to the node's footprint. Call sites updated in
  CanvasView + ExportRenderer (shared files, existing membership — no new files).
  Should also shave on-screen frame cost.
  Second finding: group drags ran 60ms → **320ms frames** because every
  mid-drag model bump cleared the instance-resolve cache (log: instCacheMiss 4
  per drag frame → 4 heavy re-resolves/frame). Drag mutations are frame-only and
  `resolvedChildren(of:)` never reads frames, so both the instance cache and the
  text-layout cache now stay warm while `dragMode != .none`
  (`frameOnlyGestureActive`); normal generation-clear resumes at mouseUp.
  **Needs owner re-test:** (1) blit-capture should now be ≈ one frame — if the
  "blit disabled" line still prints, send the number; (2) group drags should
  hold ~60ms with instCacheHit 4; (3) confirm drop shadows look unchanged on
  canvas AND in PNG/PDF export (the clip must be invisible).

- **2026-07-02 — Session 161b (blit beach-ball fix):**
  First test of the Session 161 blit showed 0.7ms blit frames but **4,000ms+
  captures** (beach ball at every gesture start). Root cause: `offscreenBacking()`
  used `premultipliedLast` (RGBA) — a NON-NATIVE pixel layout that forces Core
  Graphics onto a swizzling software path (~70× slower than on-screen; also why
  the old blur pass was so slow). Fixed: backing is now native BGRA
  (`premultipliedFirst | byteOrder32Little`). Added a safety valve: any capture
  over 250ms disables the blit for the rest of the run (logged), so it can never
  beach-ball again. **Needs owner re-test:** blit-capture should now be ≈ one
  frame (~60ms); if the log prints the "blit disabled" line, report the capture
  time. Baseline full frames are 45–85ms at ~400 drawn nodes — that's the next
  perf target (likely effects/shadows), separate from the blit.

- **2026-07-02 — Session 161 (canvas performance: blit + mips + text cache; pixel honesty):**
  Canvas felt klunky on image/layer-heavy documents. Three perf changes in
  `Canvas/CanvasView.swift` (view-layer only — no shared model files touched, so
  no EXPThumbnail target-membership risk):
  1. **Pan/zoom bitmap blit** — first gesture tick renders the scene once into
     the reusable offscreen backing; subsequent ticks blit that bitmap
     translated/scaled; a full-quality render settles in ~120ms after motion
     stops (same catch-up pattern as the blur path). Rulers are excluded from
     the snapshot and drawn live so they never smear. Snapshot recaptures if
     mid-gesture zoom drifts past 1.75×/0.6×. Perf keys: `frame(blit)`,
     `blit-capture`.
  2. **Downsampled image cache** — `cgImage(for:targetPx:)` now serves
     power-of-two "mip" variants via ImageIO thumbnails (force-decoded once,
     EXIF-aware), so a 4000px photo in a 200px frame no longer resamples the
     full bitmap every frame. NSCache, ~256MB cost limit. Export still renders
     full-res through its own path.
  3. **Text layout cache** — TextKit stacks per text node were rebuilt every
     frame; now cached by node id + content fingerprint, cleared on
     `resolveGeneration` bump (the instance-cache pattern).
  Also fixed the **canvas/inspector pixel mismatch** (owner decision:
  snap + honest decimals): all draw/drag/resize gestures snap to whole document
  pixels (**⌘ bypasses**, same modifier that skips smart guides; smart-guide
  alignment runs after pixel snap and wins). Inspector `DimField`s and the
  measurement HUD now show up to 2 truthful decimals instead of rounding, and
  typed fractional values stick (⌥-arrows still step 0.1).
  **Needs owner verification in Xcode:** build both targets, then feel-test
  pan/zoom on a heavy doc (Testing Mode ⌃⌘T prints the perf line), check images
  stay sharp after zoom settles, drag shapes at 133% zoom and confirm inspector
  reads whole numbers, ⌘-drag for sub-pixel.

- **2026-07-02 — Session 160 (website multi-monitor callout):**
  Added a new public-site feature callout for **Multi-window mode**, using the
  supplied multi-monitor mockup as a website asset
  (`website/public/assets/exp-multi-monitor-workspace.png`). The section sits
  between the product story and existing feature tabs, with copy focused on
  letting the canvas and panels spread across real monitor setups instead of
  replacing any current content. Also added a first-viewport hero badge that
  clearly says **macOS only / native Mac app** on the lower edge of the product
  screenshot.
  **Verified:** `npm run build` passes; in-app browser desktop/mobile checks
  confirm the multi-monitor image loads at native size, the macOS badge is
  visible, the roadmap CTA still navigates, and there is no horizontal overflow.

- **2026-06-30 — Session 157 (In-app feedback reporter — FEAT-003):**
  Built `UI/Feedback.swift`: Help ▸ **Send Feedback** (⇧⌘/) opens a native sheet (dogfoods
  EXPSegmented Bug/Idea + `.exp` field + `.exp` buttons). Auto-captures PII-free CONTEXT
  (app+build version, macOS, current tool, selection counts, doc stats: artboards/nodes/
  components — via a recursive node count) and, on submit, opens a **prefilled GitHub New
  Issue** (labels + title + markdown body incl. context) when `FeedbackConfig.githubRepo` is
  set, else the website; ALWAYS copies the report to the clipboard as a fallback.
  • Wiring: `AppState.showingFeedback` flag · `@objc sendFeedbackAction` on CanvasNSView ·
  Help `CommandGroup(replacing: .help)` · `.sheet` in MainWindow. `validateMenuItem` default
  = enabled. Brace-balanced.
  • `FeedbackConfig.githubRepo` is nil for now (→ website); set it once the repo exists
  (BACKLOG INFRA-002). Added **INFRA-001** (one-command approve → ROADMAP → roadmap.json →
  website sync; needs the site's stack confirmed) to the backlog.

- **2026-07-01 — Session 159 (website email signup + field guide copy):**
  Wired the public website tester form to a simple Vercel Function at
  `api/signup.js`. The function validates email, includes a honeypot field,
  and sends a notification email through Resend's REST API using
  `RESEND_API_KEY`, `SIGNUP_TO_EMAIL`, and optional `SIGNUP_FROM_EMAIL` env vars
  (no database yet; honest first version). Updated the tester form UX with
  submit/success/error states and changed the Field Guide section to "coming
  soon" copy. `website/DEPLOYMENT.md` now documents the Resend/Vercel env setup.
  **Verified:** website build passes; API route validation handles invalid email,
  honeypot, and wrong method; Playwright smoke with mocked `/api/signup` confirms
  the form success state, coming-soon copy, no runtime errors, and no horizontal
  overflow.

- **2026-07-01 — Session 158 (website auto-sync + Vercel root deploy):**
  Wired the website to auto-sync from project memory. Added
  `website/scripts/sync-content.mjs`, which reads `docs/ROADMAP.md` +
  `docs/BACKLOG.md` and generates `website/src/generated/siteContent.json`
  before every `npm run dev` / `npm run build`. The React roadmap section now
  imports that generated content, showing synced roadmap cards, latest progress,
  and open backlog queue items. The generated JSON is ignored to avoid timestamp
  churn. Added root `vercel.json` so Vercel can deploy from the repo root while
  building `website/`, which avoids the subdirectory-root limitation where
  `website/` cannot read `../docs`. Added `website/DEPLOYMENT.md` with exact
  Vercel settings and daily workflow. **Verified:** `npm run build` passes;
  Playwright smoke confirms generated content appears, tabs still update, no
  runtime errors, and no horizontal overflow.

- **2026-07-01 — Session 157 (EXP website prototype):**
  Added a separate React + Vite `website/` package as a living public home for
  EXP [design], using the existing design-system tokens/assets and the current
  app screenshot. The site is a dark, Apple-adjacent scroll story with a glass
  nav, product hero, interactive feature tabs (native canvas / source components /
  structured notes), expandable field-guide rows, a roadmap section that is
  written around `docs/ROADMAP.md` as the future source of truth, and a tester
  interest/download placeholder. Captured the generated concept at
  `website/docs/exp-website-concept.png` and verification renders at
  `website/docs/render-desktop.png` + `website/docs/render-mobile.png`.
  **Web build passes** (`npm run build`), Playwright smoke verified no console
  errors, no horizontal overflow, tabs update, guide rows expand, and the tester
  field accepts input. Deferred: real Markdown ingestion from ROADMAP/BACKLOG,
  real signup/download wiring, and deployment/hosting decision.

- **2026-06-30 — Session 156 (v1 milestone + project infrastructure):**
  Phase 17 (design-system rollout) is effectively COMPLETE — marked a solid v1. Set up the
  process scaffolding for ongoing work + friend testing:
  • **docs/BACKLOG.md** — structured, agent-ingestible bug/feature/perf tracker (entry schema
  + "how agents use this"). Seeded: BUG-001 fractional-measurements-shown-as-whole (cause:
  `.fractionLength(0)` on every numeric field + `Int()` on canvas labels; model stores
  fractional), FEAT-001 color saved/recent/palettes (doc-linked + import/export), FEAT-002
  color-mode picker, FEAT-003 in-app bug reporter (agent-ingestible), PERF-001 large-file perf.
  • **docs/ARCHITECTURE.md** — one-read map (model → document/undo → AppState → canvas render
  pipeline → components → design system → command-coverage → two targets → export) + a
  "where do I put a new X?" table.
  • **.github/ISSUE_TEMPLATE/** — bug + feature YAML issue forms (fields mirror BACKLOG.md) +
  config, ready for a GitHub repo. Recommended distribution path: Apple Developer Program →
  TestFlight for friends + GitHub Issues for intake; in-app reporter (FEAT-003) pre-fills.

- **2026-06-30 — Session 155 (Controls compile confirmed + auto-contrast accent text):**
  • **Build:** the Session-154 controls now COMPILE (owner fixed the ButtonStyle access-level
  issue — `makeBody` returns `Body` explicitly and `Body` is `internal`, since a `private`
  result type on a non-private method is an error). The whole 17c control set (fields,
  segmented, buttons, icon toggles) builds.
  • **Auto-contrast accent foreground:** new `EXPColor.accentForeground` / `onColor(_:)` —
  computes WCAG relative luminance of the resolved accent and returns near-black on a LIGHT
  accent, white on a DARK one, so text on a solid accent fill stays legible for ANY accent
  override. Wired into `EXPButtonStyle` (primary) + `EXPSegmented` (selected segment).
  Threshold 0.6 (tunable). `accentOn` (raw white) kept for cases that always want white.

- **2026-06-30 — Session 154 (Inspector: EXPSegmented + EXPButton — controls complete):**
  New `UI/Controls.swift` with two design-system controls:
  • **`EXPSegmented<Value>`** — the accent-fill pill toggle (inset `surface-field` groove,
  selected segment = accent fill / on-accent medium text, idle = light `text-secondary`).
  Replaced ALL 5 native `.pickerStyle(.segmented)` in the inspector: auto-layout direction
  (icons), Gap/Space-Between, cross-align (Top/Center/Bottom), Align-to (Selection/Artboard),
  and text Auto-width/Text-box. Generic over the existing enum/Bool bindings — each keeps
  its own binding + tags.
  • **`EXPButtonStyle`** (`.exp(.primary/.secondary/.ghost)`) — accent primary / neutral-glass
  secondary / borderless ghost, radius 8, medium weight, press-shrink, hover in a nested Body
  view (ButtonStyle can't hold @State). Applied to the two real standalone buttons (Settings:
  Reset Workspace Layout, Reset to system accent). Inspector "Add …" actions stay native
  Menus by design.
  All brace-balanced. **17c inspector fields & controls: COMPLETE** (fields S149, section
  labels S146, icon toggles S153, segmented + buttons S154).

- **2026-06-30 — Session 153 (Inspector icon buttons → brand toggle):**
  New `InspectorIconButton` (accent-subtle active, soft hover wash, `radiusTool`, accent
  glyph / textSecondary idle) replaces the `.buttonStyle(.bordered)` + manual accent-fill in
  the three inspector helpers — `alignOpButton` (align/distribute), `alignButton` (text
  align), `styleButton` (B/I/U). One consistent brand toggle across the align row, the text
  controls, and distribute. Brace-balanced.
  REMAINING inspector controls (next piece): the 5 native `.pickerStyle(.segmented)` toggles
  (design wants a custom accent-fill `EXPSegmented` — a real component build, each Picker has
  its own binding/options) and a primary/secondary `EXPButton` for the Add/Reset actions.

- **2026-06-30 — Session 152 (Design tooltips on the tools rail):**
  Built `.expTooltip(label:shortcut:)` in GlassSurface.swift matching the design-system
  `Tooltip`: a translucent popover (surface-popover + lit rim + popover shadow) with the
  label and a monospaced KEYCAP badge for the shortcut, shown to the right of the trigger
  after a ~0.45s hover delay. Replaced the tool buttons' native `.help` with it (kept the
  accessibilityLabel for VoiceOver). Added `.zIndex(1)` to the tools strip so the bubble
  draws over the canvas.
  ⚠ RISK to verify on build: the bubble renders to the RIGHT of the rail, over the AppKit
  `CanvasView` (NSViewRepresentable), which can OCCLUDE SwiftUI overlays. The zIndex may or
  may not be enough. If it's hidden behind the canvas, the robust fix is a native tooltip
  (NSPopover / child NSWindow) — a bigger lift, flagged rather than done blind.

- **2026-06-30 — Session 151 (Fix: heading "Edited" flag never updated):**
  `WindowChrome` read `window.isDocumentEdited` via KVO, but that key isn't reliably
  KVO-observable — it caught the launch value and never updated, so "Edited" never showed.
  Added a `NSWindow.didUpdateNotification` observer (fires around edits/saves) that re-reads
  the window state; made `update(from:)` change-guarded so the chatty signal doesn't thrash
  @Observable; marked `WindowChrome` `@unchecked Sendable` so the @Sendable notification block
  compiles. Name/extension KVO (title/representedURL) unchanged. Brace-balanced.

- **2026-06-30 — Session 150 (Tool panel: pan / image / component + reorder):**
  Added the three new tools + the new groupings. Functional, brace-balanced; needs a build.
  • **Tool enum** (`AppState`): `.pan` / `.image` / `.component` with the owner's definitive
  SF Symbols, labels, shortcuts (pan=H; image=⇧⌘P; component=none).
  • **Groups** (`ToolsStrip`): `[pan, select, node]` · `[rectangle, ellipse, polygon, line,
  pen]` · `[text, image, component]`. Mode tools set `app.tool`; the two ACTION tools
  (image, component) fire their canvas action via the responder chain and leave the tool
  as-is. Tooltip omits the `()` when a tool has no shortcut.
  • **pan** = the hand tool: reuses the existing space-drag path (`dragMode = .hand` when
  `app.tool == .pan`); open/closed-hand cursor; H selects it. • **image** triggers the
  existing `placeImageAction` (image node type already existed). • **component** →
  new `newEmptyComponentAction` on `CanvasNSView`: makes an EMPTY `ComponentSource` +
  opens its source editor (vs. ⌘K which wraps a selection). Added to the Object menu;
  `validateMenuItem` default = enabled. `desiredCursor` gained the new cases.
  • DEFERRED (owner's "if capacity"): the CUSTOM styled tooltips w/ keycap shortcut badge —
  native `.help` still shows label+shortcut; the designed hover tooltip wants live iteration
  (hover timing/positioning) so it's a focused next step. Also opt-3 Figma drag-to-create
  artboard still pending.

- **2026-06-30 — Session 149 (Inspector field chrome — flat token TextField):**
  Checked the design-system `TextField.jsx`: the field is a CUSTOM flat control (surface-field
  fill, border-strong hairline, radius 5, 12pt, accent focus ring) — the "system metric" note
  only meant the radius. Built `EXPFieldStyle: TextFieldStyle` (in DesignTokens.swift) matching
  it and swapped **all 33** `.textFieldStyle(.roundedBorder)` → `.textFieldStyle(.exp)` across
  MainWindow (28), PaintEditor (2), PanelDock / LayersPanel / ColorPopover (1 each). Every
  inspector/zoom/rename/color field is now the flat brand field, uniform 24pt height.
  Brace-balanced. CAVEAT: focus shows via the text cursor, not yet the accent RING — the ring
  needs per-field @FocusState, a later enhancement. Segmented controls + inspector buttons
  still use system styling (next inspector polish if wanted).

- **2026-06-30 — Session 148 (17g — color popover + paint/gradient editor tokenized):**
  `Color/ColorPopover.swift` + `Color/PaintEditor.swift` (both app-target-only, so tokens are
  safe) onto DesignTokens: `.secondary` labels → token text; `.secondary`-opacity swatch/bar
  strokes → `borderSoft`; `Color.accentColor` (selected gradient stop) → `EXPColor.accent`;
  corner radii 4/5/6 → `radiusDrop`/`radiusField`/`radiusRow`. 19 swaps, brace-balanced.
  Popover CONTAINERS + split/preset menus keep the native macOS popover chrome (Liquid Glass
  on 26), so nothing to override there. 17g done.

- **2026-06-30 — Session 147 (Accent override UI — feature complete):**
  Added the accent-override control to Settings ▸ Design Tokens (the 17a token hook was
  already live). New "Accent" group in `DesignTokensSettingsPane`: a **Follow system accent**
  toggle (on by default) + a `ColorPicker` and "Reset to system accent" when overridden.
  Writes `AppPreferences.accentOverride` ("#RRGGBB"; ""=follow system) — the exact key
  `EXPColor.resolvedAccentNS()` reads, so selection / active tool / focus rings / primary
  buttons all track it. Color↔hex via `NSColor(Color)` + `EXPColor.hexColor`. Brace-balanced.
  NOTE: applies as windows redraw (next render), not instantly across open windows — a live
  push (bump an @Observable on the UserDefaults change) can be added if the delay is annoying.

- **2026-06-30 — Session 146 (Inspector token sweep — section headers + text colours):**
  Safe, mechanical tokenization of the Properties inspector (`MainWindow.swift`), no layout
  risk:
  • **18 section headers** (Type/Fill/Stroke/Align/Grid/Layout Grids/Effects/Overrides/…)
  `.font(.caption).foregroundStyle(.secondary)` → `.expSectionLabel()` — now UPPERCASE, 11pt
  ultralight, tracked, matching the LAYERS/PROPERTIES panel titles.
  • **42** remaining `.foregroundStyle(.secondary)` field labels + **2** `.tertiary` → token
  text tiers; **3** `Color.accentColor` → `EXPColor.accent` (now honour the accent override).
  Brace/paren-balanced. REMAINING inspector polish (deferred, higher-touch): the numeric/
  text FIELD chrome (`DimField` + 25 `.roundedBorder` → token field surface/radius/focus) and
  the `.callout`/`.caption2` FONT roles — left for a focused pass since they change metrics.

- **2026-06-30 — Session 145 (Heading polish: centered doc name + one-bar layout + New-Artboard opt 1):**
  Heading refined per owner feedback (glass heading from S144 confirmed working):
  • **Doc name** now shows in the heading again, CENTERED, via a `WindowChrome` @Observable
  that KVO-observes the NSWindow's `title` / `representedURL` / `isDocumentEdited` (streamed
  by an extended `WindowConfigurator` + a tiny `WindowTrackingView`). Name in primary; the
  **extension shown at 30% opacity**; **Edited** flag moved UNDERNEATH in the accent colour.
  • **One-bar feel:** all clusters TOP-aligned to the stoplight line — stoplights (left),
  New-Artboard (just right of them), centered name, system controls (right); heading height
  trimmed to 44 (tunable). Name layer is non-interactive so window-drag passes through.
  • **New-Artboard button = opt 1** (recommended: least disruptive — it was already in the
  heading; just repositioned left of the controls, now icon-only split button). opt 3 (Figma
  drag-to-create tool) noted as the better long-term UX, to bundle with the pan/image/
  component tool-additions phase.
  Brace/paren-balanced; needs a build. Watch: (1) confirm the doc name/extension/Edited read
  correctly from the window (KVO on those keys); (2) fine-tune heading height / top-padding
  so the three clusters sit exactly on the stoplight line.

- **2026-06-30 — Session 144 (Real fixes: floating-window + custom main-window glass heading):**
  Screenshot showed NOTHING rendering — diagnosed two real bugs:
  • **Floating windows:** content didn't extend under the titlebar (styleMask lacked
  `.fullSizeContentView`), so the glass + gradient started BELOW the stoplight bar →
  that strip was transparent. Added `.fullSizeContentView`; the behind-window glass +
  top gradient now reach the very top.
  • **Main window heading:** the grey bar was the native opaque `.toolbar` above the
  content — canvas never went under it, nothing to blur. **Restructured** MainWindow:
  removed the native toolbar; body is now `VStack { headingBar; HStack{tools|canvas|docks} }`.
  New `headingBar` = behind-window `WindowGlassBackground` + `expTopEdge`, hosting the
  New-Artboard menu + `TopSystemControls` (moved out of the toolbar), 72pt leading clear
  for the stoplights. New `WindowConfigurator` (NSViewRepresentable) sets the window
  transparent-titlebar + `.fullSizeContentView` + **isOpaque=false** so the heading's
  behind-window glass shows. Canvas fills opaquely (`underPageBackgroundColor`), so the
  desktop won't bleed through it.
  • Gradient also fixed to SOLID-top→clear (was dark-on-dark, invisible).
  Brace/paren-balanced; **needs a build + careful check.** Watch-items: (1) the New-
  Artboard menu + zoom/dock/mode controls now live in the heading; ⇧⌘N still bound.
  (2) Window is now non-opaque — if the tools rail or any chrome gap looks see-through
  to the desktop, give that surface an opaque backing. (3) Document title isn't shown in
  the heading yet (titleVisibility hidden) — can add it back if wanted.

- **2026-06-30 — Session 143 (Correction: gradient was invisible + main heading never glassed):**
  Owner couldn't see the gradient/glass. Two real mistakes from Session 142, now corrected/
  clarified:
  • **Gradient was invisible** — it used `surfaceToolbar` (dark translucent) over already-dark
  chrome. Fixed `TopEdgeGradient` to a SOLID `surfacePanelSolid` top fading to clear, so on
  the FLOATING (glass) windows the top now reads as a solid header melting into glass.
  • **Main window heading was mis-targeted** — Session 142 put `.expTopEdge()` on the
  `DockColumnView`s, which are OPAQUE (`surfaceWindow`), so a gradient there is ~invisible;
  and the main window's actual heading is the **native macOS titlebar + `.toolbar`** (no
  custom window config — confirmed by grep), which never got any custom glass. So the main
  window heading currently has only whatever system Liquid Glass the native toolbar provides.
  • TO MATCH the floating panels' glass heading, the main window needs `.windowStyle(
  .hiddenTitleBar)` + a CUSTOM heading bar (move the New-Artboard menu + `TopSystemControls`
  out of the native toolbar into a SwiftUI strip with `WindowGlassBackground` + `expTopEdge`).
  That's a focused structural change — flagged, not yet done (awaiting owner go-ahead).

- **2026-06-30 — Session 142 (Top-edge gradient on all windows + definitive tool symbols):**
  • **Top-edge gradient:** new `TopEdgeGradient` + `.expTopEdge()` in GlassSurface.swift —
  a subtle gradient that's more opaque at the very top, fading to clear, so a grab bar /
  panel top reads solid over glass (the floating grab bar was nearly transparent after
  the glass change). Applied to the floating **tray windows** and the docked **DockColumn**
  panels. NOT applied over the canvas (left untouched, by design). One-line height/tint
  knobs in `TopEdgeGradient`.
  • **Tool symbols (owner-supplied, definitive):** updated `Tool.symbolName` — select
  `pointer.arrow`, polygon `triangleshape`, pen `…curvepath.fill`, text `character.textbox`
  (node/rectangle/ellipse/line unchanged). Recorded the FULL list incl. the not-yet-built
  pan `hand.point.up.left.fill` / image `photo.fill` / component
  `square.on.square.squareshape.controlhandles` in the 17c tools section so there's no
  guesswork when those tools are added.
  Brace-balanced; needs a build.

- **2026-06-30 — Session 141 (Floating-panel glass: thinner-when-inactive, not darker):**
  Owner: the floating panels' glass looked great while active but **darkened when the
  window went inactive** (backwards) and read too thick. Root cause: the tray windows
  leaned on a system material that follows key-state (vibrant→muted on resign-key).
  • New `WindowGlassBackground(active:)` in GlassSurface.swift — real BEHIND-window blur
  (`NSVisualEffectView .sidebar`, `state = .active` so it NEVER auto-dims). Active vs
  inactive is expressed purely as a heavier-vs-lighter brand TINT, so inactive reads
  THINNER/lighter, never darker. Reduce-Transparency → opaque plate.
  • `PanelWindow.TrayWindowView` reads `\.controlActiveState`; `active = (state == .key)`
  so the glass thins the moment the panel isn't the focused window (matches the felt
  behaviour). Tray windows set `isOpaque = false` + clear bg so behind-window glass shows.
  Applies to ALL tray windows uniformly (consistent panel behaviour).
  • Made `LayersPanel` transparent (`.scrollContentBackground(.hidden)` + clear root) so
  the window glass actually shows THROUGH the panel body, not just the header — and in
  docked mode it simply shows the dock column's `surfaceWindow` (no regression).
  • Tint knobs are one line in `WindowGlassBackground` if it still reads heavy/light.
  Brace-balanced; needs a build. (Other panels — Components/Properties — get the same
  window glass + thinning; their content-transparency can follow if wanted.)

- **2026-06-30 — Session 140 (Quick token sweep: trays, source editor, notes, settings):**
  Low-risk colour/type token swaps across four more chrome surfaces (materials/glass
  for the canvas-overlay + tray windows are still the deferred 17e/17h pieces). All
  brace-balanced; needs a build.
  • **PanelWindow** (floating trays): tray bg → `surfaceWindow`; grab bar + section
  header `.bar` → `surfaceToolbar` (matches the dock headers — unified); insertion line
  → token accent + dropline width; grab glyph → textTertiary.
  • **SourceEditorWindow** (component editor, 17f): title → `expDocName`; backdrop-swatch
  stroke → accent/borderStrong + token widths; View label + subtitle → token type/colour.
  • **ArtboardNotesOverlay** (17h colours): notes toggle fill/stroke/foreground + the
  notes panel fill/stroke onto tokens (accentSubtle, surfaceRaised, hairline, radii).
  • **SettingsWindow** (17i): pane titles → `expDocName`; type-metrics diagram label →
  textSecondary, its plate → `surfaceField`.

- **2026-06-30 — Session 139 (Layers row engine rewrite: exact layout spec + click-to-select):**
  Per the owner's per-row spec + the selection bug, rebuilt the row engine in
  `LayersPanel.swift`. **Structural change — needs a build + click-test.**
  • **Dropped native `DisclosureGroup` + `List(selection:)`** (their built-in indent and
  click-handling were exactly what pushed the accent rule off the edge and blocked
  name clicks). `LayerOutlineRow` is now a manual `VStack` with a custom chevron and
  `depth`-based indent; selection is fully manual via a row tap → modifier-aware
  `selectNested` (handles plain / ⌘-toggle / ⇧-range for every row).
  • **Row layout = the spec, L→R:** [hairline artboard-rule slot — accent only when the
  section is active] · [xxs active-layer slot — accent only when selected] · depth
  indent · [chevron block: xxs · chevron · xxs, FIXED width so leaf rows align] · eye ·
  xxs · type glyph (now smaller) · xxs · name · flex · lock · space.sm. The two accent
  slots are element 1+2 of every row, pinned far-left regardless of depth; flush
  `VStack(spacing:0)` makes them read as one continuous line down the active group.
  • **Selection fixed:** single click ANYWHERE on the row selects (name only claims the
  count:2 gesture, so a single tap falls through to the row's select); double-click the
  name renames. Added a row-selected background fill + hover. Eye/lock stay `.fill`/11pt.
  • InstanceLayerRow gained `depth` + indent + matched icon sizes. Removed the now-dead
  `NestedTapSelect` + `selection` binding. Brace-balanced; init arg orders verified.
  • ⚠ Build-test watch-list: (1) if the rule still isn't flush far-left, the remaining
  culprit is `.listStyle(.sidebar)`'s leading gutter → switch that List to `.plain`;
  (2) confirm chevron expand/collapse, drag-reorder, and ⌘/⇧ multi-select still behave;
  (3) layers-panel Delete key may need focus now that native selection is gone (canvas
  Delete unaffected).

- **2026-06-30 — Session 138 (17c bug-fixes: layer-row icons + active-artboard rule):**
  Against the north-star screenshot, fixed four row bugs to lock the pattern:
  • **Icons → `.fill` variants** — eye `eye.fill`/`eye.slash.fill`, lock `lock.fill`/
  `lock.open.fill` (was outline; this also guarantees the hidden state shows a slashed
  eye, not a greyed open eye). • **Icon size** 12→**11** (eye + lock; they read too big).
  • InstanceLayerRow eye matched.
  • **Active-artboard rule** rebuilt: was a per-row leading overlay inside an 8pt row
  inset, so it sat indented and broke between rows. Now ONE continuous line drawn once
  per top-level row spanning the whole group (incl. expanded children); rows are
  full-bleed (`listRowInsets` leading/trailing = 0) with the gutters moved into the row
  content, so the rule sits at the panel's far-left and never jogs/gaps. Nested rows
  skip it (ancestor draws it). Refactored `LayerOutlineRow.body` → `content` + a body
  overlay. Selected-row thick bar unchanged.
  • ⚠ CAVEAT to check on build: `.listStyle(.sidebar)` may still reserve a small leading
  gutter for disclosure chevrons; if the rule isn't perfectly flush-left, the next lever
  is `.listStyle(.plain)` (changes section-header look) or a small negative leading
  offset. Brace-balanced.

- **2026-06-30 — Session 137 (Phase 17c — core chrome reskin, left side):**
  Reskinned the editor's left side onto DesignTokens + `expGlass`. Self-contained,
  brace-balanced; **needs a build + look** (and the native `.glassEffect` confirm from
  17b applies to the tools rail).
  • **ToolsStrip** — thin liquid-glass rail (`expGlass(.thin)`), tokenized active/
  hover/idle (accent-subtle / rowHover, accent / textSecondary), 15pt glyphs, tool
  radius 6, medium (not semibold) active weight. (Tool reorder + new pan/image/
  component tools still pending — functional work.)
  • **LayersPanel** — the Session-133 callouts: **lock moved to the RIGHT** edge;
  selected row gets a **thick (3pt) accent bar** on the left; the active-artboard rule
  is tokenized (1.5pt accent, far-left); names render in **SF Compact** (medium when
  active), locked rows dim to text-tertiary; eye/type/drop-line/drop-into all token.
  InstanceLayerRow tokenized to match.
  • **PanelDock** — header strip → `surfaceToolbar` tint; tabs → UPPERCASE titles +
  accent-subtle active state; chevron/divider/drop-line/Components empty-state +
  ComponentRow tokenized. **Deferred (flagged):** the dock COLUMN native glass + a
  transparent sidebar `List` — they conflict and need live iteration; column is the
  `surfaceWindow` token for now.
  • Remaining 17c: **Inspector fields/controls** (`MainWindow.swift`, ~2400 lines — the
  next big chunk), **window chrome**, and the lime `[design]` mark. Checkpointing here
  so the left-side reskin can be built/verified before the inspector pass.

- **2026-06-30 — Session 136 (Phase 17b — the `expGlass` surface primitive):**
  Built `UI/GlassSurface.swift` — the one liquid-glass modifier the whole reskin
  composes, so panels/trays/popovers/modals share ONE material (the unified-glass
  callout). `.expGlass(_ thickness:style:cornerRadius:tint:interactive:)` with:
  • **.liquid** backend = native macOS-26 **Liquid Glass** (`.glassEffect(.regular
  .tint(…).interactive(…), in:)`) — DEFAULT for docked chrome (deploy target is 26.2,
  so no availability guard). • **.material** backend = `NSVisualEffectView` (real
  backdrop blur, `.withinWindow`) for canvas-overlay glass (wired in 17h). • **Reduce
  Transparency** → opaque token plate, no blur, automatically.
  • Per-thickness tint (`EXPGlass.tint`), a fading lit top **rim** (brighter under
  Increase Contrast), a top-down **sheen** (stronger in light, per glass.css), and
  **elevation** shadow (thin/medium/thick → soft/panel/modal, softened in light).
  • Convenience roles `expToolbarGlass` / `expPanelGlass` / `expPopoverGlass` /
  `expModalGlass` map the readme's thickness→surface table. DEBUG `#Preview`s show all
  three thicknesses over a busy gradient in light + dark.
  • 17b adds ONLY the primitive; ToolsStrip/PanelDock/PanelWindow stay on `.background
  (.bar)` until 17c rewires them. Brace/paren-balanced; token refs resolve. **Needs a
  build** — the one thing to confirm is the native `.glassEffect`/`Glass` API spelling
  (best recall of the 26 SDK; isolated to the `.liquid` branch if it needs a tweak).
  Next: **17c** — reskin the core docked chrome onto tokens + `expGlass`.

- **2026-06-30 — Session 135 (Font bundling — SF Compact for cross-Mac consistency):**
  Bundled the condensed voice so layer names look identical on every Mac. Decided
  (owner): bundle **SF Compact only** (SF Pro / SF Mono are the universal system
  fonts — referenced via `.system`, NOT bundled); owner **may distribute later**, so
  the embed is kept clean + flagged.
  • Copied 5 weights — **SF Compact Display** Ultralight/Light/Regular/Medium/Semibold
  (~31MB) — into `EXP [design]/Resources/Fonts/`. Synchronized-folder default makes
  them **app-target only** (EXPThumbnail only re-includes the listed shared files), so
  the extension isn't bloated.
  • `UI/FontRegistration.swift` — `EXPFonts.registerBundledFonts()` registers them
  PROCESS-scoped via CTFontManager, idempotent, looked up by name (resilient to how the
  build flattens resources). Called from `EXP__design_App.init()` before any view
  renders, so `EXPType.hasSFCompact()` sees the family on first use.
  • `EXPType.layerFont` is the single switch-point; updated its notes (no longer
  'verify availability' — it's bundled). Added `Resources/Fonts/LICENSE-NOTE.md`:
  Apple's SF license restricts redistribution, so **before public distribution** either
  confirm a license path or swap to an SIL-OFL condensed face (one-function change).
  • SF Pro / SF Mono intentionally NOT bundled (universal + cleaner license). Brace-
  balanced; **needs an Xcode build** — confirm layer names render condensed and the
  Light/Medium weights select. Phase 17a + font bundling COMPLETE → next is 17b
  (the `glass()` surface modifier).

- **2026-06-30 — Session 134 (Phase 17a — DesignTokens.swift, the seam):**
  Built the Swift token layer that the whole reskin hangs off — `UI/DesignTokens.swift`
  (334 lines, chrome-only → app target; the synchronized-folder project auto-includes
  it, and it stays OUT of EXPThumbnail since nothing shared references it). Ported the
  CSS verbatim:
  • **`EXPColor`** — neutral ramp n0–n900, surfaces, row states, opacity-tiered text
  (100/62/42/28), borders, semantics, brand, and the isolated `EXPColor.Canvas` set.
  Each token is an **appearance-resolving** dynamic NSColor (light/dark in one token,
  the Swift analogue of `.exp-dark`/light); SwiftUI reads `Color`, AppKit reads the
  `…NS` variants. Sendable-safe (only CGFloat tuples cross into the @Sendable provider).
  • **Accent override hook** — `resolvedAccentNS()` returns the app override if set,
  else `controlAccentColor` (default = follow macOS, like System Settings). Added the
  `AppPreferences.accentOverride` key ("#RRGGBB"; absent = system). hover/press derived,
  subtle = accent @ fixed low alpha. Settings UI comes in 17i.
  • **`EXPType`/`Font`** roles incl. **SF Compact** layer font with a runtime
  availability check + system fallback; `expPanelTitle`/`expSectionLabel` View modifiers
  carry UPPERCASE + tracking. **`EXPMetric`** (spacing/radii/stroke/layout) and
  **`EXPMotion`** (curves/durations, reduce-motion aware). **`EXPGlass`** token VALUES
  parked for 17b (tints/blur/saturate/shadows).
  • **Proof:** `UI/DesignTokensProof.swift` (DEBUG-only, wired nowhere) — a button,
  panel/section headers, text tiers, SF-Compact layer rows w/ active-layer accent bar,
  segmented + switch, with light & dark `#Preview`s.
  Brace/paren-balanced; all cross-refs resolve. **Needs an Xcode build + a look at the
  two previews** — verify (1) SF Compact actually renders condensed on the owner's Mac,
  (2) the accent token tracks the system accent. Next: 17b (the `glass()` modifier).

- **2026-06-29 — Session 133 (Plan: Phase 17 — design-system rollout):**
  The owner added the finalized design-system export under `design/EXP [design]
  Design System/` (token CSS + JSON, a React UI-kit recreation of every chrome
  component, guideline cards, SF fonts, and the dark three-pane "north star"
  screenshot — the concrete build of `docs/VISUAL-HANDOFF.md`). Surveyed it against
  the live app: chrome rides on raw system semantics (~87 `.primary`/`.secondary`/
  `Color.accentColor`/`.separatorColor`/`.bar` calls across `MainWindow`,
  `ToolsStrip`, `LayersPanel`, `PanelDock`, `PanelWindow`, `SettingsWindow`) with
  **no central token layer in Swift**, so it carries none of the brand specifics
  (#181819 purple base, opacity-tiered text, named surfaces, glass thicknesses, SF
  Compact, the 4·5·6·7·8·12 radii, lime-as-spice).
  • Wrote **Phase 17** above. Owner decisions: native macOS 26 **Liquid Glass
  first** (NSVisualEffectView fallback only for canvas-overlay glass); first pass =
  **token foundation + core docked chrome** (tools strip, left dock, inspector,
  layer rows, headers, fields), with trays/modal/popovers/canvas-overlay deferred to
  17e+; **full light+dark parity every step**. Sub-phases 17a (DesignTokens.swift —
  the seam, do first) → 17b (glass primitives) → 17c (reskin) → 17d (a11y/appearance
  gate). No code yet — next session starts at 17a.

  • **Owner refinements (same session):** added an **app accent override**
  (Settings "Design" option, default = follow macOS accent) — wired as a token-seam
  hook in 17a so the reskin never bakes a raw accent. Captured four redesign
  callouts in a new "17 — Owner design callouts" block: layer-row **lock moved to
  the right**; **active-layer** thick left accent bar; **active-artboard** hairline
  accent rule on the far-left edge; and **glass unity** across single/multi-window +
  source-editor windows. Expanded the 17c tools strip: new order `[pan, select,
  node]·[rectangle, ellipse, polygon, line, pen]·[text, image, component]` plus three
  NEW tools — **pan/hand**, **image** (NSOpenPanel import; depends on Phase 14 image
  node), **component** (creates an empty source + opens the editor). Those three are
  functional work, not just reskin. Still no code — work begins next session.

- **2026-06-28 — Session 132 (Fix: handles + inspector W/H for a multi-selection inside a group):**
  The selection-transform subsystem (canvas) and the inspector's multi-selection
  dimensions were both **top-level-only**, so selecting several nested layers showed
  no resize/rotate box and 0×0 in the inspector.
  • Generalized both to nested nodes by lifting each selected node's frame into
  DOCUMENT space (folding in `nodeOffset`), running the existing `SelectionTransform`
  math, then converting the result back to parent-local on write. Valid whenever the
  ancestor chain is unrotated — the same restriction the single-node handles already
  use; rotated-ancestor selections stay move-only.
  • Canvas: `selectionTopLevelIDs/Nodes` → `selectionTransformIDs` +
  `selectionTransformNodesDoc`; baseline now snapshots doc-space + a per-id offset map;
  resize/rotate apply subtracts the offset before `updateNode`. New `hasSelectedAncestor`
  excludes a node whose group is also selected (prevents double-transform).
  • Inspector (`MainWindow`): `multiSelectionBounds` now unions doc-space nested nodes;
  the multi X/Y/W/H move + scale commits recurse via `mutateNestedNode` with the same
  doc↔local conversion. Added scope-aware `scopedNodeOffset` / `scopedAncestorRotation`
  / `scopedIsTopLevel` / `scopedOffset(of:in:)` helpers.
  Touched: `Canvas/CanvasView.swift`, `UI/MainWindow.swift`. Single nested-node
  selection already worked (single-node handle path) and is unchanged. Needs a
  build + on-device check.

- **2026-06-28 — Session 131 (Fix: multi-select inside a group in the Layers panel):**
  Nested DisclosureGroup rows are hand-rolled (they don't participate in
  `List(selection:)`), so they went through `NestedTapSelect`, which *always*
  replaced the selection — you couldn't ⌘/⇧-click to multi-select within a group.
  • New `selectNested(_:)` reads `NSEvent.modifierFlags`: **⌘ toggles** the row,
  **⇧ range-selects** from `AppState.selectionAnchorID` across a new
  `visibleSelectableIDs` flat order (respects collapsed sections + expanded groups),
  plain click replaces. Plumbed down as `onNestedSelect` through `LayerOutlineRow`.
  • Repurposed the previously write-only `selectionAnchorID` as the range anchor.
  KNOWN MINOR GAP: native top-level List clicks don't set the anchor, so a
  top-level→nested ⇧-range can use a stale anchor; within-group selection (the
  reported bug) works. Touched: `UI/LayersPanel.swift`. Needs a build + on-device check.

- **2026-06-28 — Session 130 (Copy / Paste Layer Style):**
  Added a "layer style" copy/paste — carries a layer's **effects + blend mode +
  opacity** (appearance only; geometry, fill, and content are untouched) onto one
  or many other layers.
  • Model: new `LayerStyle` struct + `Node.layerStyle` / `Node.applyLayerStyle(_:)`
  in `Document.swift` (shared-target-safe; pasted effects get fresh ids). The copied
  style lives on `AppState.copiedLayerStyle` (session-only, shared by canvas + panel).
  • Full command coverage: `@objc copyLayerStyle:` / `pasteLayerStyle:` on
  `CanvasNSView` (single source of truth, one undo step via `commitNodes`); Edit-menu
  **Copy Style ⇧⌘C / Paste Style ⇧⌘V**; canvas right-click items; Layers-panel
  right-click items (reimplemented locally like Delete so they work regardless of
  focus); `validateMenuItem` cases (Paste Style disabled until a style is copied).
  Works in both document and component-source scope.
  Touched: `Model/Document.swift`, `Model/AppState.swift`, `Canvas/CanvasView.swift`,
  `UI/LayersPanel.swift`, `EXP__design_App.swift`. No Inspector control added —
  copy/paste has no adjustable parameters (the rule's condition), but an Effects-panel
  affordance is an easy optional follow-up. Needs a build + on-device check.

- **2026-06-27 — Session 129 (Component bounds = resizable SVG-style viewBox):**
  Pivoted the component source bounds from the auto-hug box (Session 128) to a
  stable, user-resizable viewBox — "its own little artboard."
  • `ComponentSource` gained a viewBox `origin` (+ `bounds`), backward-compatible
  Codable (old size-only files decode origin = .zero). Box no longer auto-hugs:
  `commitNodes` stops rewriting `size`, and the editor draws `source.bounds` (stable)
  so elements can be moved/centered within it.
  • **Resize handles** on the source box (8-handle, ⇧ = proportional), reusing the
  artboard machinery: new `hitTestSourceHandle`, `DragMode.resizeSource`,
  mouseDown/Dragged/Up + cursor wiring; edits `source.origin/size` in one undo step.
  • **Instances render the viewBox** (SVG semantics): `resolvedChildren` positions
  content relative to `source.origin`, `resolvedSize` returns the viewBox size, and
  the instance draw path clips to the box so out-of-bounds content is cropped in
  placements (the source editor itself draws unclipped for editing). Freshly created
  components are unchanged visually (viewBox == content at creation).
  Touched: `Model/Document.swift`, `Canvas/CanvasView.swift`. KNOWN TRADE-OFF: a
  fixed viewBox no longer auto-grows an auto-layout button when an instance's label
  override gets longer — revisit with an optional per-source "hug contents" toggle if
  needed. Needs a build + on-device check.

- **2026-06-27 — Session 128 (Source bounds hug content + nested instance layers):**
  • **Source-editor bounds box now hugs the live content.** It was drawn at a fixed
  origin with the stale stored `size`, so it could sit off-centre and never followed
  the elements. New `sourceContentRect()` (union of the source's children) drives the
  drawn page, the initial fit/centering, and the ⌥-spacing measures; `commitNodes`
  keeps `ComponentSource.size` in sync so the Components panel stays honest. Moving
  elements now moves the box with them; ⌘1 (Zoom to Fit) re-centres.
  • **Instance layer list expands nested groups.** A component made from a group only
  showed the group as one row, so you couldn't toggle the layers inside it per
  instance. `InstanceLayerRow` is now recursive (disclosure per nested group), and
  `toggleInstanceLayer` resolves a nested layer's source default via a tree search
  (`nodeInTree`). The model + renderer already supported nested per-instance
  visibility (`applyingOverrides` recurses) — this was the missing UI.
  Touched: `Canvas/CanvasView.swift`, `UI/LayersPanel.swift`. (Document.swift
  untouched — no EXPThumbnail target risk.) Needs a build + on-device check.

- **2026-06-27 — Session 127 (Component naming + name sync):**
  • **Create Component names itself after the selection.** When exactly one (named)
  layer is selected — typically a group the user just named — `createComponent` uses
  that name for the source + instance instead of "Component N" (multi-shape
  selections still get the auto number).
  • **Component name is now one source of truth.** A component instance displays its
  SOURCE name everywhere — Layers panel (`displayName`), Inspector
  (`nodeNameBinding`), and the Components panel all read `ComponentSource.name`.
  Renaming an instance from the Layers panel or Inspector edits the source (one undo
  step, "Rename Component"), so all three panels stay in lockstep. Sets up treating
  instance rows specially in the Layers panel later (e.g. optional per-instance name
  overrides that fall back to the component name).
  Touched: `Canvas/CanvasView.swift`, `UI/LayersPanel.swift`, `UI/MainWindow.swift`.
  Needs a build + on-device check.

- **2026-06-27 — Session 126 (Source-window backdrop view setting):**
  Added a Photoshop-style canvas-shade control to the component source editor so
  white (or black) artwork stays visible while editing. New `AppState.CanvasBackdrop`
  enum (Light / Grey / Dark, grayscale `white` value + SwiftUI `color`), persisted
  via `AppPreferences.sourceBackdrop` (seeded in `applyAppPreferenceDefaults`, live-
  synced in `reloadSyncedPrefs`). The source canvas shades the component "page"
  (`drawSourceBounds`) with the chosen value — NOT the surrounding pasteboard, which
  stays the neutral system shade so the bounds still read as a page — with a
  luminance-aware hairline. The control is a labelled "View" swatch row (radio-style)
  in the source-window header; it's explicitly view-only and never touches the
  element's own background. Canvas redraw tracks it via a new read in `updateNSView`.
  Touched: `Model/AppState.swift`, `UI/SettingsWindow.swift`, `Canvas/CanvasView.swift`,
  `UI/SourceEditorWindow.swift`. Needs a build + on-device check.

- **2026-06-27 — Session 125 (Lock/unlock commands, Layers-panel delete, source-window fix):**
  Three testing-feedback fixes.
  • **Lock / Unlock with full command coverage.** New `lockSelection:` /
  `unlockSelection:` `@objc` actions on `CanvasNSView` (`setLockOnSelection`,
  recurses into groups, one undo step, multi-selection). Wired the conventional
  five ways: Object-menu items with **⌘L** (lock) / **⇧⌘L** (unlock), a contextual
  right-click pair (shows Lock when anything's unlocked, Unlock when locked via the
  new `anySelected(_:)` helper), `validateMenuItem` cases, and an Inspector lock
  toggle in the Layer header (`toggleLockSelected`, scoped so it works in the
  source-editor window too). The per-row toggle in the Layers panel already existed.
  • **Delete from the Layers panel.** Previously delete only worked when shapes were
  selected on the canvas — the panel's List swallowed the key. Added
  `.onDeleteCommand` (Delete key) plus a destructive **Delete** in each row's
  right-click menu; both route to a new `deleteLayers(_:)` (recursive `removeIDs`,
  reflow, one undo step). Right-clicking a row that isn't in the selection deletes
  just that row (`selectionOrRow`); otherwise the whole selection.
  • **Source-editor window layering.** The component editor's middle canvas
  overdrew the header and left panel (it sat under the right panel only). Cause: the
  AppKit canvas lived in a plain `HStack`, which doesn't clip the representable's
  NSView. Restructured `SourceEditorView` to mirror the main window — `ToolsStrip`
  pinned outside an `HSplitView { Layers · Canvas · Inspector }`; split panes clip
  their contents, so the canvas stays in its pane (and the panes are now resizable).
  Touched: `Canvas/CanvasView.swift`, `EXP__design_App.swift`, `UI/MainWindow.swift`,
  `UI/LayersPanel.swift`, `UI/SourceEditorWindow.swift`. Needs a build + on-device
  check (compiled by the Xcode agent / owner).

- **2026-06-26 — Session 124 (Canvas performance: many layers/artboards):**
  Diagnosed lag on a large stress file (`allsortsofthings.design`). Root causes:
  the canvas redrew the ENTIRE scene every frame (pan/zoom included) with (1) no
  viewport culling — every node + artboard drawn regardless of being off-screen;
  (2) `owningArtboard(of:)` called per node = O(nodes × artboards) per frame; and
  (3) component instances re-resolved (`resolvedChildren` → override apply +
  `AutoLayoutEngine.reflowed`) on every single draw, uncached.
  Fixes (3 changes, behaviour-preserving):
  • **Viewport culling** in `renderCanvas` — artboards and leaf nodes whose
  (margin-expanded) view rect doesn't intersect `bounds` are skipped; owned nodes
  are additionally culled when their artboard is off-screen (exact, since they're
  clip-bound to it). Culled leaves also skip the `owningArtboard` scan, cutting the
  quadratic loop down to on-screen + container nodes. New helpers `isLeafContent`,
  `nodeCullMargin` (covers stroke/shadow/rotation reach), `strokeReach`.
  • **Cross-redraw instance cache** — `ExpDocument` gained `resolveGeneration`
  (bumped in `model`'s `didSet`, so it catches in-place drag mutations too). The
  canvas caches `resolvedChildren` by the top-level instance node's id, valid for
  one generation. Pan/zoom don't touch the model, so the cache survives them; any
  edit invalidates it. Nested instances (shared source-layer ids) fall through
  uncached to avoid key collisions.
  • **`AutoLayoutEngine.reflowed` fast path** — returns the input unchanged when no
  node in the tree carries auto-layout/auto-padding (the common case), avoiding a
  full tree rebuild on every commit/resolve.
  Touched: `Canvas/CanvasView.swift`, `Model/ExpDocument.swift`,
  `Model/AutoLayoutEngine.swift`. Needs a build + on-device check against the
  stress file; watch for any leaf wrongly culled at extreme zoom (margin math).
  • **Follow-up — smart-guide cost during wall drags:** `snapNodeOffset` rebuilt
  alignment candidates from EVERY node in the document on each mouse-move
  (`collectCandidates(currentNodes)`), so dragging on the wall with many items
  stalled while snapping against far-distant elements. Now element smart guides only
  run when the dragged selection is over an artboard, and candidates are limited to
  nodes intersecting that board. Loose-on-the-wall drags get no element guides (ruler
  guides + uniform grid still apply). Artboard-edge / grid snapping unchanged.
  • **Testing Mode (perf instrumentation):** added `AppState.testingMode` (session
  state, OFF by default, not persisted) and **View ▸ Testing Mode (⌃⌘T)** with a
  checkmark via `validateMenuItem`. When on, a tiny `PerfMeter` (appended to
  `CanvasView.swift`, no new project file) logs ONE console line ~2×/sec: frame
  time, snap time, nodes total→drawn, boards drawn, instance-cache hit/miss, snap
  candidate count. Hot loops are guarded on `perf.enabled`, so it's near-zero cost
  when off. Use it to find what's still stalling before committing to the bigger
  dirty-rect / layer-backed redraw rewrite. Touched: `Model/AppState.swift`,
  `Canvas/CanvasView.swift`, `EXP__design_App.swift`.

- **2026-06-26 — Session 125 (Disable background blur + log triage):**
  Perf logs from two stress docs showed the real hog: **background blur**. Any node
  with a background-blur effect forces `draw()` down the offscreen path — render the
  WHOLE scene into a bitmap, `makeImage()` it, run a Core Image gaussian per blur
  node — EVERY frame. Result: 30–50ms frames with only ~50 nodes drawn, escalating
  to 3,000–23,000ms frames and `Surface 16000–19000 px too large` failures at high
  zoom. **Disabled background blur** behind `CanvasNSView.backgroundBlurEnabled =
  false`: `documentHasBackgroundBlur` now returns false (so the offscreen pass never
  runs) and the per-node blur block (incl. its `makeImage()`) is gated off. Drop /
  inner shadows unchanged. Removed "Background Blur" from the effects ▸ add menu and
  the kind picker (`UI/MainWindow.swift`); a blur effect saved in an old file just
  doesn't render. To revisit: flip the one flag back on after reworking the blur to
  a clipped, region-only pass (no full-scene readback). Touched:
  `Canvas/CanvasView.swift`, `UI/MainWindow.swift`.
  Still open from the same log (NOT yet fixed): ~90× "Publishing changes from within
  view updates is not allowed" — a SwiftUI feedback loop (an @Observable mutated
  during a view update) that can trigger extra redraws; needs a runtime repro to
  pinpoint. The DetachedSignatures / networkd / ViewBridge / file-provider
  "hasn't been synced" lines are benign macOS sandbox + Dropbox/iCloud noise, not
  app bugs. Re-measure frame times now that blur is gone before deciding whether the
  dirty-rect / layer-backed redraw rewrite is still needed.

- **2026-06-26 — Session 126 (Fix launch hang: shadow convolution blowup):**
  After the blur disable the app "wouldn't run" — really it HUNG on the first frame
  reopening a doc saved at high zoom (~25×), then got SIGTERM'd. Debugger was parked
  in a gaussian convolution kernel (`conv4_8_A`) with `Surface ~19000px too large`.
  Cause: drop/inner shadows use `setShadow(blur: e.blur * zoom)` with NO ceiling, and
  the transparency layer they draw into is sized by the current clip — an artboard
  clip at 25× is ~19000px. So one shadowed node demanded a multi-thousand-pixel
  gaussian over a ~19000px surface → hang. Same blowup class as background blur, but
  zoom-driven. Fixes: (1) `EffectsRender.maxShadowBlurPx = 200` clamps shadow blur in
  device space (drop + inner); (2) `renderCanvas` now `ctx.clip(to: visible)` before
  the artboard clip, so NO transparency layer (shadow / opacity / blend) can allocate
  a surface bigger than the viewport — invisible to the user, but caps the worst case.
  Touched: `Color/EffectsRender.swift`, `Canvas/CanvasView.swift`. Note: the source
  (component) editor canvas doesn't yet apply the viewport clip — same risk if zoomed
  extremely far there; revisit if it surfaces.

- **2026-06-26 — Session 123 (Settings screen + active-artboard highlight):**
  • NEW full-window **Settings** (`SettingsWindow.swift`): a sidebar + detail
  scaffold (General / Canvas / Design Tokens / About) wired as the standard
  SwiftUI `Settings` scene, so ⌘, and the app-menu "Settings…" item come for free.
  Deliberately a real screen, not menu items, so it scales — add one
  `SettingsPane` case + one view per future options group. App-wide prefs are
  UserDefaults-backed via a shared `AppPreferences` key table (Settings can't
  reach a per-window `AppState`, so everything routes through defaults).
  • `AppState.init` now seeds smart-guides, selection-bounds, snap, and grid
  size/subdivisions from those defaults *only when the key exists*, so anyone who
  never opens Settings behaves exactly as before. `loadLayout()` honours a new
  restore-layout opt-out; `AppState.clearSavedLayout()` backs the General reset
  button. The five Settings-exposed toggles (smart-guides, selection-bounds, snap,
  grid size/subdivisions) are now LIVE two-way synced: a per-window View-menu/canvas
  change writes the default (property `didSet`), and a UserDefaults observer in
  `AppState` pulls Settings/other-window changes back into the open window — a
  re-entry guard (`applyingExternalPrefs`) breaks the loop. `showGrid` stays
  per-window display state (not in Settings).
  • Design Tokens pane is an honest "coming soon" placeholder (no dead controls)
  — the future home for the token system.
  • Layers: the section for the **active artboard** (the board owning the current
  selection, or a directly-selected board) now stands out — its name is tinted +
  semibold and a thin accent border runs down the section's leading edge (header +
  every row, incl. nested). Isolated in a `LayersActiveStyle` constant set so it
  folds into design tokens later. Source-editor scope never highlights. VoiceOver
  announces the active board's header as "…, active artboard".
  • Type-token groundwork: NEW `Model/TextMetrics.swift` — `FontMetrics` (Core Text
  ascent/descent/leading/cap/x-height) + `TextBoxTrim` insets math for leading-trim
  (cap-height→baseline optical box vs the font line box) + `inkBounds`. The
  Settings ▸ Design Tokens pane now hosts a real text-box-trim default (radio,
  `exp.pref.textBoxTrim`) with a metric-accurate Canvas schematic drawn FROM that
  helper. No app text rendering trims yet — this is the home for the math, ready
  for the token system.
  • Files: +`UI/SettingsWindow.swift`, +`Model/TextMetrics.swift`; edits to `EXP__design_App.swift` (Settings
  scene), `Model/AppState.swift` (defaults + reset), `UI/LayersPanel.swift`
  (active-section styling). New file is app-target only (no EXPThumbnail concern).

- **2026-06-25 — Session 122 (nudge + layers expand/collapse-all):**
  • Arrow-key nudge now works for a node INSIDE a group: `nudgeSelection` recursed
  via `mutateNested` (was top-level-only, same blind-spot as the earlier opacity
  bug) and rotates the doc-space delta into the node's local space for rotated
  ancestors (matches the move drag). Inspector X/Y already worked.
  • Layers •••: added an options menu in the Layers panel header (always present,
  even when docked) with Expand All / Collapse All (open/close every group +
  section). Also added View ▸ Expand All Layers / Collapse All Layers, wired through
  a new `AppState.layersExpandAll` closure hook the document panel registers
  (mirrors `applyTextStyle`); @objc `expandAllLayersAction:` / `collapseAllLayersAction:`
  + validateMenuItem (enabled only while the panel hook is live). Menu has room to
  grow with more layer options later.
  • TODO (needs more testing): residual layer-SELECTION weirdness the owner noticed —
  may be specific to an artboard carried through many edits, not a general bug.
  Revisit with fresh repro; likely folded into the deferred custom layers-list
  rebuild (see Session 121).

- **2026-06-25 — Session 121 (Layers follow-up + deferred rebuild):** Fixed
  rename-commit: the Layers rename field now commits on focus loss
  (`.onChange(of: nameFocused)` → `commit()`), so clicking another layer saves the
  edit instead of leaving it stuck in edit mode (Esc still cancels via
  `onExitCommand`, no double-commit). DECISION: the remaining Layers issues — the
  click-to-highlight DELAY and the residual "sometimes multiple lines" / vertical
  alignment drift — are structural to SwiftUI `List` + per-row `.onDrag` (the drag
  makes the system delay every tap to disambiguate; `List` owns its row spacing so
  the drop line/heights keep fighting us). The agreed SOLID FIX is to rebuild the
  layer rows on a plain `ScrollView` + `VStack` we fully control (instant selection,
  one drop line rendered in the real gap, exact row heights, manual multi-select
  shift-range/⌘-toggle, drag-into-group, instance sub-rows). DEFERRED to the
  visual-polish pass — the owner will tackle it once design tokens are ready (so the
  rebuild can bake in the final spacing/typography at the same time). Also deferred
  to that pass: smoother section collapse animation.

- **2026-06-25 — Session 121 (Layers panel fixes, batch 2 of bug list):**
  (7) Collapsible sections: each artboard / Wall section is now `Section(isExpanded:)`
  with per-section state (`collapsedSections`), so the header chevron collapses it.
  (8) Auto-reveal: `.onChange(of: app.selectedNodeIDs)` opens a selected layer's
  ancestor groups (`ancestorGroupIDs`) and un-collapses its owning section, so a
  layer selected on the canvas is findable in the panel. (Scroll-into-view noted as
  a future add — needs a ScrollViewReader around the List.)
  (9+10) Drop line + reorder reliability: rows are now a FIXED height (28) and flush
  (`listRowInsets` zeroed top/bottom, `listRowSeparator(.hidden)`), so the
  before/after insertion lines coincide into ONE line per gap (was two, separated by
  the row gap) and the drop thresholds are stable (the measured `rowHeight` jittered).
  Double-click-to-rename kept. If reorder still feels off after testing, next step is
  neighbour-aware drop mapping or a custom scroll/stack list.

- **2026-06-25 — Session 121 (canvas interaction fixes, batch 1 of bug list):**
  (1) Line shift-constrain: drawing a line or dragging an endpoint with Shift snaps
  to 45° increments (incl. horizontal/vertical) via `constrainLineEndpoint`
  (`.drawLine` / `.lineEndpoint` drags). Whole-line move already axis-locked.
  (2) Nested resize: a single node selected inside an UNrotated group now shows the
  8-handle box + rotate knob and resizes. `hitTestHandle`/`rotateKnobPoint` dropped
  the top-level-only guard (now `isTopLevelNode || ancestorRotation==0`) and use the
  absolute frame via `nodeOffset`; the `.resize` drag converts the cursor into the
  node's parent-local space by subtracting `nodeOffset`. Nested LINES also fixed:
  `hitTestLineEndpoint` + the `.lineEndpoint` setup now use a chain-aware
  `lineEndpointsResolvedDoc`, and `setLine` converts doc→parent-local via
  `docToParentLocal`, so nested line endpoints draw + drag correctly. (Nodes under a
  ROTATED group stay move-only — flagged.)
  (3) Text-in-group edit gating: a nested text now needs an extra step — first
  double-click selects/drills (so it's draggable), a further double-click (when
  already selected) opens the editor. Top-level text unchanged (double-click edits).
  (4) Esc exits text edit: added `textView(_:doCommandBy:)` handling
  `cancelOperation:` → `commitTextEditing()`, which keeps the node selected + movable
  and restores canvas first responder.
  (5) Opacity number-shortcut now reaches a layer inside a group
  (`setOpacityOnSelection` recurses via `mutateNested`).
  (6) Line inspector W/H: new `lineSizeBinding` scales the line's endpoints (they're
  frame-local, so setting `frame.size` alone did nothing); inspector branches to it
  for `.line`.
  NEEDS VISUAL CHECK (can't compile here), especially nested resize math + the
  text double-click gating feel. Layers-panel items (7–10) are the next batch.

- **2026-06-25 — Session 120 (eyedropper `i`):** Added the eyedropper shortcut.
  Two entry points, both via `NSColorSampler` (the system screen loupe):
  (1) On the canvas, `i` (no modifiers, handled in `keyDown` like the V/A/R/… tool
  letters, so it never hijacks a focused text field) → `eyedropToSelection()`
  samples a screen color and applies it to the selection: fill for
  rect/ellipse/polygon/path, stroke for a line (its fill-equivalent), text color
  for text, auto-padding background for a group; one undo step. Also exposed as
  `eyedropperAction:` (@objc) in the Object menu (no key-equivalent — the canvas
  key owns `i`) + right-click ("Eyedropper (Pick Fill)") + validateMenuItem.
  (2) In the color popover (`ColorPopover`, used for both solid fill and the
  selected gradient stop), a local `NSEvent` keyDown monitor active while the
  popover is open makes plain `i` fire the existing `sampleScreen()` even when the
  hex/value field has focus — safe to swallow there since a color code
  (hex/rgb/hsl/lch/oklch) never contains `i`. ⌘/⌃/⌥+i are left alone.

- **2026-06-25 — Session 120 (shape masking — Phase 16a):** Non-destructive,
  editable shape masks. Chose to model a mask as a `.group` with two new Node
  bools (`isMask` on the container, `isMaskShape` on the clip child) rather than a
  new `NodeContent` case — this reuses ALL group machinery (enter-to-edit, Layers
  drag-into-group for adding content, copy/paste, instances, auto-layout passthrough
  since mask groups have no autoLayout) and keeps the NodeContent switch surface
  small (less Xcode-agent stub risk). Render (`CanvasView.drawNodeContent` `.group`):
  when `isMask`, build a `CGMutablePath` = union of `isMaskShape` children's
  silhouettes (`appendSilhouette` recurses; a group mask child = merged descendants),
  `ctx.clip`, draw the non-mask content; mask shapes draw no fill. `drawMaskOutline`
  shows a dashed accent boundary while the mask or a descendant is selected
  (`maskEditingActive`). Raster/PDF export mirrors the clip (`appendExportSilhouette`).
  Create: `maskWithTopShape()` mirrors `group()` — topmost selected = mask shape;
  `releaseMask()` reverts to a plain group; `selectionHasMask()` for validation.
  Command coverage: @objc actions, Object menu (⌃⌘M + Release Mask), right-click
  (Mask with Top Shape / Release Mask), validateMenuItem cases. No new files, so no
  EXPThumbnail target change. NEEDS A VISUAL CHECK (can't compile here): confirm the
  clip aligns, the dashed outline shows when editing, and drag-in adds content.
  DEFERRED: SVG `<clipPath>` export, a Layers mask badge.
  FOLLOW-UP (same session): rotated/flipped mask shapes now clip correctly.
  `appendSilhouette` / `appendExportSilhouette` bake each node's own rotation/flip
  (CGAffineTransform about its center) into the clip path and compose it with
  ancestor transforms (`base`), mirroring the `drawNode`/`drawExportNode` CTM. The
  mask group's own rotation needs no handling — it's the active CTM when the clip
  is applied.

- **2026-06-25 — Session 119 (background blur effect):** Implemented the
  stackable `Effect.Kind.backgroundBlur`. Model: added the case to `Effect.Kind`.
  Canvas: `draw(_:)` now splits into a cheap window path and, ONLY when a blur node
  exists (`documentHasBackgroundBlur` scans the tree), an offscreen-bitmap path
  (`bitmapImageRepForCachingDisplay` → `renderCanvas(into:)` → `rep.draw`) so a blur
  node can sample its accumulated backdrop. In `drawNode` (guarded to unrotated,
  unflipped nodes), `ctx.makeImage()` grabs the backdrop, `drawBackgroundBlur`
  CIGaussianBlur's it (`sigma = amount · zoom · backingScale`) and composites it
  clipped to the node silhouette; one composite per enabled blur effect (stackable).
  Safe fallback: nil `makeImage()` → no-op, common path unchanged. Inspector: "Bg
  Blur" in the add menu + picker, single Amount field, default 8. NOT yet in
  `ExportRenderer` (canvas-only for now — flagged for a follow-up).
  FIX (same session): first cut rendered the offscreen pass into an UN-flipped
  `NSGraphicsContext(bitmapImageRep:)`, which disagreed with the flipped view —
  `NSString.draw` honors `isFlipped`, so text/artboard-name came out upside down +
  the sampled backdrop was vertically mirrored. Now the offscreen pass uses a
  cached `CGContext` wrapped in `NSGraphicsContext(cgContext:flipped:true)` with a
  CTM matching `docToView`, so text + geometry render identically to on-screen;
  the result is blitted upright with the image-node idiom. The backing bitmap is
  cached and only reallocated when the pixel size changes (was allocating a
  multi-MB `bitmapImageRepForCachingDisplay` every frame → choppy pan/zoom).
  PERF (same session): blur was Gaussian-ing the WHOLE window per blur node every
  frame. Now `drawBackgroundBlur` renders only the node's region (+ blur-radius
  margin) via `createCGImage(from: region)`, so Core Image computes a small rect
  instead of the full canvas. Still one full-window `makeImage` per blur node (the
  backdrop readback) — fine for a few nodes; revisit if many stacked blurs.
  PERF 2 (same session): full backdrop blur on a CPU Core Graphics canvas is
  inherently too heavy for 60fps live pan/zoom (per-frame full-scene `makeImage`
  readback + Core Image roundtrip). Added "blur catches up" deferral:
  `suppressBlurDuringInteraction()` (called from `scrollWheel`, `zoom(by:anchor:)`,
  hand-drag pan) sets `blurSuppressed`, so `draw(_:)` takes the cheap direct path
  during the gesture; a 0.12s settle timer clears it and forces one final blurred
  redraw. Real fix for buttery live blur would be a GPU/layer-backed canvas — out
  of scope for now. KNOWN: backdrop shows un-blurred mid-gesture, snaps to blurred
  on settle (acceptable, standard behavior).

- **2026-06-24 — Session 118 (flip: selection outline trace matches too):**
  Cleaned up Session 117's leftover: the selection box's path OUTLINE trace now
  mirrors with the flip. Wrapped just the `bezierPath` stroke in `drawNodeSelection`
  in a flip CTM about the frame centre (inside the existing rotation block, so it's
  flip-then-rotate like the renderer). Box/handles untouched (symmetric).

- **2026-06-24 — Session 117 (path-point editing is flip-aware):**
  Resolved Session 116's limitation: anchors now track a flipped path. Made the
  node-local ↔ view conversions apply the flip (a mirror within the frame about its
  centre, BEFORE rotation — matching the renderer): `nodeLocalToView` mirrors the
  local point, `viewToNodeLocal` un-mirrors it. Since drawing the anchors/handles
  (`drawPathPoints`), hit-testing (`hitTestPathPoint`), pen hover/remove
  (`penHover`), and dragging (`pathPointDrag`/`pathPointGroupDrag`) all funnel
  through those two functions, every point operation now lines up with the flipped
  shape. Also un-flipped `addPenPoint`'s direct local calc so an added anchor lands
  under the cursor on a flipped path.
  MINOR remaining: the selection-box's faint path OUTLINE trace still draws unflipped
  (the anchors/handles/box are correct); cosmetic, separate CTM, left for later.

- **2026-06-24 — Session 116 (add-point on complex shapes + flip + resize-flip):**
  • **Add-point** had the same multi-contour gap as remove: it only searched/inserted
    into `ps.points` (first contour). `addPenPoint` now finds the nearest segment
    across EVERY contour (`editContours`, `contourClosed`) and inserts into the right
    one via `writeEditContours`.
  • **Flip Horizontal / Vertical**: new `flipH`/`flipV` flags on `Node`, applied at
    draw time about the frame centre (like rotation) so it works uniformly for
    images, text, paths, and groups — rendered on canvas + raster/PDF + SVG export
    (`scale(±1)` / `transform`). Actions `flipHorizontalAction`/`flipVerticalAction`
    toggle each selected node; wired into the **Arrange** menu, right-click, and
    `validateMenuItem`.
  • **Resize-past-flip**: dragging a handle PAST the opposite edge now mirrors the
    object (un-rotated case). The `.resize` drag captures `resizeFlipBaseline` at
    start and XORs a per-axis "crossed the anchor" test into the flip flags.
  LIMITATION: editing path points (node tool) on a FLIPPED path shows anchors in
  unflipped positions (flip is a render transform, not baked into geometry) — fine
  for the common image/shape flip; bake-on-flip for paths is a later refinement.

- **2026-06-24 — Session 115 (remove-point on complex shapes + closer zoom):**
  • **Remove-point now works on multi-contour paths** (outlined text, SVG subpaths —
    the "more complex shapes" where it silently did nothing). `penHover` was gated to
    `!isMultiContour`; it now scans EVERY contour via `ps.editContours` and returns a
    `PointAddress(contour, index)`. `removePenPoint` takes that address, removes from
    the right contour via `writeEditContours`, drops a contour that falls below 2
    points, and collapses the whole node only when nothing usable remains.
  • **Closer zoom**: max zoom 64× → **256×** (6400% → 25600%) for pixel/anchor work.

- **2026-06-24 — Session 114 (pen tool: visible anchors + Adobe-style deselect):**
  Builds on Session 113's `penHover` scoping fix.
  • **Anchors visible under the pen tool**: when the pen is active but NOT mid-draw,
    the SELECTED path's anchors and the path UNDER THE CURSOR now draw their points
    (in the canvas draw block, guarded by `app.tool == .pen, penNodeID == nil`), and
    `mouseMoved` now redraws under the pen so the hovered vector's anchors light up
    live. The owner couldn't see where points were to add/remove — the hit-tests were
    fine (Session 113), just invisible.
  • **Node-tool deselect like Adobe**: clicking the path BODY (no drag) DESELECTS the
    points instead of requiring a click outside the whole bounding box. New
    `pointGroupFromBody` flag (set true in `nodeToolMouseDown` step 2, false on an
    anchor grab); mouseUp's `.pathPointGroup` case does `setSelectedPoints([])` when
    `!didEdit && pointGroupFromBody`. Dragging the body still moves the selection;
    empty-space click still deselects.
  REMAINING: confirm add/remove on rotated / deeply-nested paths now that anchors are
  visible; if still off, trace `penHover → hitPath → addPenPoint/removePenPoint`.

- **2026-06-24 — Session 113 (fix: pen-tool "+"/"−" cursor stuck on, add-point broken):**
  Owner reported, right after Session 111's pen delete-point feature: "add point
  is not working, and the add point cursor seems to be on all the time." Root
  cause: `hitTestPenRemovablePoint` (added in Session 111) scanned **every**
  single-contour path's **every** anchor across the whole document on every
  cursor move/click, with no z-order or locality awareness — unlike every other
  hit-test in the file (`hitPath`/`nodeHit`), which always stops at the topmost
  node actually under the cursor. On any document with more than a couple of
  detailed paths, anchors belonging to shapes elsewhere on the canvas could
  fall within the fixed 12pt `handleGrab` radius of the cursor almost anywhere,
  so the "−" remove-check (checked first) or the pre-existing "+" add-check
  would key off the wrong, unrelated node — intercepting clicks that should
  have added a point to whatever was actually under the cursor, and making one
  of the two badge cursors read as "always on."
  Fixed by replacing `hitTestPenRemovablePoint`'s flat whole-document scan with
  a new `penHover(atViewPoint:)` that reuses `hitPath(atDoc:).last` — the exact
  same topmost-hit scoping every other tool already relies on — and only checks
  *that* node's anchors for a `handleGrab` match. `hitPath`'s segment-distance
  test already catches thin/unfilled open paths (an anchor is always
  distance-0 from its own segment), so the original worry that motivated the
  flat scan didn't hold up. `desiredCursor`'s `.pen` case and `penMouseDown`'s
  inactive-session branch both now call `penHover` once and branch on
  `removableIndex`/`leafID` instead of running two separate, differently-scoped
  hit-tests.
  Not yet built/run in Xcode — next session should confirm: pen tool over a
  busy canvas (multiple paths) only shows "+"/"−" when actually hovering the
  relevant shape/anchor, and clicking a shape's body away from any anchor adds
  a point to *that* shape again.

- **2026-06-24 — Session 112 (fix: outlined-text bounding box goes stale once points move outside it):**
  Owner reported that after dragging an outlined-text path's points outside its
  original box, (a) the box itself never grew to match, and (b) grabbing the
  shape's body to drag the whole point-selection as a group stopped working.
  Same root cause for both: `normalizePath()` (CanvasView.swift) deliberately
  early-returned for multi-contour (outlined-text) paths, leaving `node.frame`
  stale after an edit. `nodeHit`'s multi-contour fast-path is
  `frame.contains(docPoint)` — a stale, too-small frame means clicks on points
  now outside it no longer register as "on the shape," which is exactly what
  `nodeToolMouseDown`'s case 2 (grab-body-to-drag-selection) depends on.
  Fixed by generalizing `normalizePath` to rebase **every** contour (via
  `ps.editContours` / `writeEditContours`, not just `ps.points`), with the new
  bbox computed from anchors **and** control handles, not anchors alone — a
  bezier curve never leaves the convex hull of its anchor+handle points, so
  this guarantees the recomputed frame always encloses the actual curve.
  Re-checked the original worry behind the old skip (re-framing "would clip
  the glyph's curves"): confirmed via `drawDocument`/`drawNode` that nothing
  clips a path to its own `node.frame` — only artboards clip — so a frame that
  grows or shrinks here can't visually clip anything. No behavior change for
  ordinary single-contour paths (same anchor-rebasing math, now also
  considering handles, which only makes that box more accurate).
  Not yet built/run in Xcode — next session should confirm: Edit Points on an
  outlined-text glyph, drag a point outside the original box, confirm the box
  grows to match and the shape can still be grabbed by its body to drag the
  whole selection.

- **2026-06-24 — Session 111 (feature: delete points, not just whole elements):**
  Two related point-deletion gaps, both in `CanvasView.swift`:
  1. **Node tool (Edit Points):** pressing Delete with points selected used to
     delete the entire element. Added `deleteSelectedPoints()` — removes only
     the selected `PointAddress`es from the edited path's `editContours`
     (mirrors `rotateSelectedPoints`'s selection source/commit pattern), drops
     any contour that's emptied out (e.g. a fully-deleted hole in an outlined
     glyph), writes back via `ps.writeEditContours(cs)`, commits, clears the
     point selection. `deleteSelection()` now checks
     `app.tool == .node && !selectedPointAddresses.isEmpty` first and routes
     there instead of the whole-node path — so the Delete key, Edit menu, and
     right-click menu all pick this up for free with no separate dispatch.
  2. **Pen tool:** added a true "remove point" mode, mirroring the existing
     "add point" affordance. `hitTestPenRemovablePoint` finds an anchor
     directly under the cursor (any single-contour path, top-most first,
     including inside groups) when no pen session is active. The hover cursor
     now shows a "−" badge over a hit anchor (checked *before* the existing
     "+"/`.dragCopy` body-hover check, so a point sitting on its own path's
     fill still reads as removable), and clicking calls `removePenPoint`,
     which deletes just that anchor — or, if the path collapses below 2
     points, removes the whole node via `removeNested` (correct for paths
     nested in a group), same convention `finishPen` already uses for a lone
     pen click. Scoped to single-contour paths only for this pass — outlined-
     text/compound paths aren't pen-editable yet, matching the existing
     "add point" feature's scope.
     **Placeholder cursor:** AppKit has no stock "minus badge" cursor and no
     formal artwork has been supplied for one, so `removePointCursor` draws a
     small black-fill/white-halo minus badge over the system arrow in code
     (`CanvasView.swift`, near `desiredCursor`). This matches the project's
     black+white cursor styling but is NOT designer artwork — swap it for a
     real `NSCursor(image:hotSpot:)` per docs/DESIGN-ASSETS.md §5/§9 (vector
     art + explicit hotspot, dropped in `design-assets/cursors/`) whenever
     that's wanted.
  Not yet built/run in Xcode — next session should confirm: Edit Points →
  select a few points → Delete only removes those; Pen tool → hover an
  existing anchor (shows "−"), click removes it; clicking a point until <2
  remain removes the whole path, matching a lone pen click's behavior.

- **2026-06-24 — Session 110 (fix: V-tool resize not scaling multi-contour paths):**
  Owner reported the regular resize handles (V/select tool) were "just resizing
  the bounding box" instead of the actual vector. Root cause: in
  `CanvasNSView`'s `.resize` drag handler (CanvasView.swift), the live-drag
  path-scaling code only scaled `PathShape.points`. That's correct for simple
  pen-drawn single-contour paths, but multi-contour paths — outlined text
  (Convert to Outlines) and any compound/boolean shape — render from
  `PathShape.contours` via `renderContours` (which prefers `contours` over
  `points` when present, see `Document.swift`). So for those shapes the frame
  resized but the rendered geometry didn't move at all. Fixed by scaling both
  `ps.points` and, when present, every sub-array of `ps.contours`, using the
  same per-point scale closure — matching the pattern `SelectionTransform.
  scaleInternal` already used correctly for multi-node/group resize and the
  Inspector's numeric W/H fields (which were unaffected by this bug; only the
  live canvas-handle drag path was broken). One-line-of-reasoning fix, no new
  state or API surface.
  Not yet built/run in Xcode — next session should confirm by resizing an
  outlined-text shape and a compound path via the corner handles.

- **2026-06-24 — Session 109 (Edit Points: multi-point selection, marquee, group-drag, selection rotation):**
  Owner reported the node/Edit-Points tool had regressed (selected points no
  longer highlighted, marquee no longer multi-selected) and asked for two new
  abilities (grab-anywhere-in-selection to move it; rotate the selection about
  its own center). Investigation showed multi-point selection never existed in
  this codebase — only single-anchor drag and uniform anchor rendering did — so
  this was new functionality, not a revert. Built as one coherent system across
  three files:
  • **AppState.swift** — new "Point-selection channel," mirroring the existing
    `applyTextStyle` pattern: `selectedPointCount`, `pointSelectionRotation`,
    and `@ObservationIgnored applyPointRotation: ((Double) -> Void)?`.
  • **CanvasView.swift** — new `PointAddress: Hashable` (contour, index) pairs
    with `PathPointTarget.anchor`; `selectedPointAddresses: Set<PointAddress>`
    + `lastEditedPathID` state; two new `DragMode` cases (`pathPointGroup`,
    `pointMarquee`); rewrote `nodeToolMouseDown` to take a `shift` flag and
    handle anchor-hit (toggle on shift / select+drag otherwise), shape-body-hit
    with an existing selection (group-drags the whole selection), different-
    path-hit (switches edited path), and empty/own-body-with-no-hit (starts a
    point marquee); added `setSelectedPoints` (keeps the Inspector channel in
    sync), `syncPointSelectionIfNeeded` (clears a stale selection when the
    edited path or tool changes — called from `CanvasView.updateNSView`),
    `beginPathPointGroupDrag`/`pathPointGroupDrag` (rigid group move),
    `finishPointMarquee` (box-select by view-space hit test), and
    `rotateSelectedPoints(by:)` (rotates selected anchors+handles about their
    own bbox center, reusing the existing private `rotatePoint` helper).
    `drawPathPoints` now takes a `selected: Set<PointAddress>` and fills
    selected anchors solid (white otherwise) — the missing highlight. Marquee
    rubber-band rendering extended to cover `.pointMarquee` too.
  • **MainWindow.swift** — `pointRotationBinding` (a delta-dispatching dial,
    not a stored value — same shape as `nodeRotationBinding` but sends through
    `applyPointRotation`) and a new "N points selected" + R° field at the top
    of `pathControls()`, shown only when `app.tool == .node && selectedPointCount > 0`.
  Not yet built/run in Xcode — next session should confirm it compiles and
  test all four behaviors (highlight, marquee, group-drag, rotate) before
  considering this closed.

- **2026-06-24 — Session 108 (fix: Convert to Outlines silently failing for some fonts/box sizes):**
  Root cause: `TextContent.outlineGlyphs(in:)` (Typography.swift) handed
  `CTFramesetterCreateFrame` a path sized to the text node's STORED frame height —
  but CoreText returns ZERO lines if that height is shorter than one line at the
  font's actual natural line height. Canvas drawing never hit this because that
  draw path doesn't go through the strict framesetter, so a manually-resized box
  (or just a font with a taller em-square) could draw fine on-screen yet outline
  to nothing with no error. Whether the bug showed up depended entirely on the
  gap between the box's stored height and the chosen font's line height — hence
  "works for one font, not another." Fix: `outlineGlyphs` now floors the layout
  height at `measuredSize(boxWidth:)`'s natural height before building the path.
  Safe because CoreText always starts the first line at the TOP of the rect, so
  any extra room only pads unused space below — existing glyph placement/position
  is unaffected. Diagnosed via temporary `print` instrumentation at every silent
  guard in `convertSelectedTextToShapes` (CanvasView.swift) + `outlineGlyphs`;
  removed once the failing guard (CTFrameGetLines → 0 lines) was confirmed from
  the Xcode console.
  FOLLOW-UP (same session): the first fix (floor height at TextKit's
  `measuredSize`) wasn't generous enough — still failed on the same font until
  the box was resized larger, because TextKit and CoreText measure line height
  independently and can disagree, especially for fonts with unusual ascent/
  descent. Made the floor much more generous (2× the measured floor + a flat
  400pt pad) instead of trusting TextKit's number exactly. Also added
  `NSSound.beep()` on every early-return in `convertSelectedTextToShapes` (matching
  the existing beep-on-failure convention from `exportSelectedArtboard`/
  `exportAllArtboards`) so any FUTURE edge case is felt, not silent — per the
  owner's explicit ask that "nothing happens, no error" must never recur here.

- **2026-06-20 — Session 107 (window/panel sizing + canvas centering):**
  • **Right dock default width** 300 → **332** so the full align/distribute row fits
    without clipping. Added a load-time **migration** (`AppState.loadLayout`) that
    bumps a saved right column narrower than the default — so existing layouts get
    the wider panel automatically (anyone who set it wider keeps theirs).
  • **Default window size** 1500 × 950 (`.defaultSize` on the DocumentGroup) so a
    new document opens roomy instead of at the 900 × 600 minimum.
  • **Canvas centering**: `fitContent` now centers within the VISIBLE drawing area
    (inset by the top/left ruler strips), so the artboard reads as centered instead
    of nudged down-right.

- **2026-06-20 — Session 106 (multi-select editing + inspector polish):**
  • **Multi-select style editing** (the headline): with 2+ layers selected the
    inspector now shows **Type** (font + size), **Fill**, and **Stroke** (color +
    width) sections that apply to EVERY selected layer at once — text font/size hit
    all text layers (re-measuring auto boxes), fill/stroke hit shapes/lines and a
    frame's auto-padding background, and a Fill on text sets its colour.
    (`multiStyleControls` + `mutateAllSelected` in MainWindow.swift.)
  • **Inspector polish**: removed the "Double-click the text…" instruction line
    (no other panel has one); gave the Type / Align / Effects section headers
    `.padding(.top, 4)` so they're not glued to their dividers.
  • **Text box stays selected** after committing an inline edit (Esc / click-out),
    so it can be grabbed and moved immediately — including for auto-layout reordering.
  DEFERRED (from the same request): double-clicking the EDGE of a text box (vs its
  glyphs) to select-not-edit — finicky hit-testing, its own pass. The Esc-then-grab
  flow covers the main need for now.

- **2026-06-20 — Session 105 (delete component, drop-line, gotcha note):**
  • **Delete Component** added to the Components-panel right-click menu (destructive);
    removes the source AND every instance of it (recurses groups + other sources),
    one undo step. (`ComponentRow.deleteComponent` in PanelDock.swift.)
  • **Layers drop-line** made consistent: a `Capsule` inset 6pt, offset ±1 so it
    straddles the row boundary (so "after row N" and "before row N+1" render at the
    same y). Deeper SwiftUI drag glitchiness (drops occasionally not registering)
    remains — durable fix is an AppKit-backed reorder, logged as a follow-up.
  • **Gotcha note** added to CLAUDE.md (shared-target membership + the Xcode-agent
    reflow-stub trap) so a future session catches it immediately.
  KNOWN REMAINING / candidate next features (from a roadmap re-audit): per-child
  hug/fill/fixed sizing in auto-layout (nav-bar items that should fill), drag-reorder
  drop-gap feedback, layer masks + boolean ops + outline-stroke, gradient text fill,
  zoom-to-selection, PNG scale/transparent-bg export options, markdown text, custom
  font import, multi-window polish (reorder sections, named workspace presets).
  Interface polish (panel vertical alignment, section spacing) pending owner specifics.

- **2026-06-20 — Session 104b (the stub kept coming back — Xcode agent):**
  The `resolvedChildren` reflow stub was being re-introduced by the **Xcode 26.3
  agent** auto-fixing the build error (it replaced `AutoLayoutEngine.reflowed(...)`
  with `let laid = resolved` + a TODO each time). So adding the file to EXPThumbnail
  made the build green only because the call was *still stubbed* → no re-hug.
  Now that `AutoLayoutEngine.swift` is a member of BOTH targets, restored the real
  call (and made `laid` genuinely mutated so there's no warning to tempt another
  auto-edit). ⚠️ If override re-hug ever breaks again, FIRST check this line in
  `Document.resolvedChildren` hasn't been reverted to `let laid = resolved`.

- **2026-06-20 — Session 104 (ROOT CAUSE: resolvedChildren reflow was stubbed out):**
  The real reason instance overrides never re-hugged: `Document.resolvedChildren`
  had its `AutoLayoutEngine.reflowed(...)` call replaced with `let laid = resolved`
  (comment: "reflow happens here when AutoLayoutEngine is available") — almost
  certainly to make the **EXPThumbnail** extension target compile, since
  `Document.swift` is a member of that target but **`AutoLayoutEngine.swift` is not**.
  With reflow removed, the live instance only got the override (text changed) but the
  frame never re-hugged; **Detach** still worked because its `commitNodes` reflows the
  baked nodes afterward — which is exactly the symptom reported.
  • RESTORED the `AutoLayoutEngine.reflowed` call in `resolvedChildren`.
  • ⚠️ REQUIRED XCODE STEP: add **`Model/AutoLayoutEngine.swift`** to the
    **EXPThumbnail** target membership (File Inspector ▸ Target Membership), same as
    Document/Paint/Typography/ExportRenderer already are — otherwise the extension
    target won't build. (If it had been added when AutoLayoutEngine landed, this
    stub would never have happened.)

- **2026-06-20 — Session 103 (override commit button, fill override, scroll):**
  • **Inspector scrolls**: the selection details are now inside a `ScrollView`
    (title + zoom stay pinned), so tall inspectors (auto layout + auto padding +
    effects + align) no longer hide controls until you resize the window.
  • **Text override = explicit commit**: instance text overrides moved to a local
    draft with a ✓ button (and Return) — `InstanceTextRow`. The model + re-hug now
    fire ONCE per edit instead of on every keystroke (lighter, and the resize
    reliably registers on commit). New `commitTextOverride` / `resetOverride`.
  • **Frame fill override**: a button's background (its auto-padding fill, which
    isn't a child layer) is now overridable per instance — `overridableChildren`
    surfaces groups that have an auto-padding fill, and a `.fill` override on a group
    targets `autoPadding.fill` (`applyingOverrides`). So you can recolor a button
    instance even though the rectangle was absorbed into the frame.
  • Re-confirmed `ExpDocument.model` is `@Published` (setModel repaints), so the
    earlier "doesn't register" was the per-keystroke churn + the fixed-box measure
    gate (Session 102), both now addressed.

- **2026-06-20 — Session 102 (fix: overridden label didn't re-measure):**
  Root cause of "auto padding doesn't follow a component override": the text
  re-measure in `applyingOverrides` was gated to `box == .auto`, but a button label
  is usually a FIXED box, so the override changed the string without resizing the
  text node — leaving the auto-padding frame hugging the ORIGINAL dimensions. Now an
  overridden label ALWAYS re-measures to hug a single line (grows width), regardless
  of box mode, so the surrounding frame re-hugs the new text. This is why detach
  "snapped it into place" (detach's commit reflow ran on the baked nodes) while the
  live instance didn't.

- **2026-06-20 — Session 101 (component rename + instance frame sync):**
  • **Rename components** in the Components panel: double-click a row (or right-click
    ▸ Rename) to edit the name inline; Enter/blur commits ("Rename Component", undoable),
    Esc cancels. Single click still opens the source editor (`ComponentRow` in
    PanelDock.swift).
  • **Instance frame sync**: `updateSelectedInstance` now sets the instance's stored
    frame to its `resolvedSize` after an override, so the selection box / hit area /
    export bounds track the re-hugged size.
  • OPEN ITEM — auto padding on an INSTANCE: render + detach both go through the same
    `resolvedChildren`, so they should match; couldn't repro the divergence from the
    code. Need a repro detail: does a FRESH instance (no override) show the padded
    background, or only break after a text override? Is the background visible at all
    on the instance? (If text overrides show live but padding doesn't re-hug, the
    source text box is probably `.fixed`, not `.auto`, so it isn't re-measured.)

- **2026-06-20 — Session 100 (Auto Layout/Padding flows through components):**
  Instances now reflow auto-layout/padding for their own overrides — override a
  button component's text and the instance re-hugs, just like the source.
  • `ComponentInstance.applyingOverrides(to:)` now **recurses into groups** (so a
    text nested inside a button frame actually receives its override — previously
    only top-level source children did) and **re-measures** an overridden auto-size
    text node so the frame around it can hug it. Nested instance-hidden layers are
    dropped during resolve.
  • New `Document.resolvedChildren(of:)` / `resolvedSize(of:)`: apply overrides +
    visibility, run `AutoLayoutEngine.reflowed`, normalise to (0,0). This is the
    single source of truth for what an instance shows.
  • Canvas render, raster/PDF + SVG export, selection box, hit-testing, and
    **Detach** all route through `resolvedChildren`/`resolvedSize`, so an instance
    draws, selects, exports, and detaches at its true re-hugged size.
  NOTE: resolve runs per draw/hit (reflow + text measure); fine for now, can cache
  if instance-heavy files feel slow. Build a button as a GROUP with Auto Padding,
  THEN Create Component, so the frame travels into the source.

- **2026-06-20 — Session 99 (fix: inspector toggle didn't absorb background):**
  The Auto Padding **inspector switch** turned the trait on with a bare
  `AutoPadding()` and never absorbed the enclosing background rectangle (only the
  ⌥⌘P menu path did), so the rectangle stayed a child and padding hugged it instead
  of the text. Moved `enableAutoPadding` / `backgroundChildIndex` / `backgroundStyle`
  into `AutoLayoutEngine` (shared) and pointed BOTH the canvas action and the
  inspector toggle at it. Now flipping the switch absorbs the background → fill shows
  on the frame, padding hugs the text. (Re-toggle Auto Padding off/on for any button
  built before this fix.)

- **2026-06-20 — Session 98 (Auto Padding = CSS box model: padding + margin):**
  Reworked Auto Padding into the full CSS box model:
  `content → PADDING → background box (fill/corner/stroke) → MARGIN → frame edge`.
    – **Padding** is the gap from the content to the background-box edge; the
      background grows with it.
    – **Margin** is transparent space OUTSIDE the background (the old "outside the
      whole element" behaviour, now its own control).
  • Model: `AutoPadding` gains `margin{Top,Right,Bottom,Left}` (+ `marginW/H`).
  • Engine: `padBlock` frame = content + padding + margin (content anchored);
    `stack` total inset per side = margin + padding.
  • Render (canvas + raster/PDF + SVG): the background is drawn at the **padding box**
    = frame inset by the margin (not the full frame).
  • Overlay: two bands now — **teal** padding (background → content) and **orange**
    margin (frame → background) — both update live.
  • Inspector: Auto Padding shows a **Padding** row and a **Margin** row, then
    Fill / Corner / Stroke.
  NOTE: the content box is the text NODE's frame (its measured line box). If you want
  padding measured from the tighter glyph ink later, that's a future refinement.

- **2026-06-20 — Session 97 (Auto Padding hugs the CONTENT, not the group):**
  Padding was wrapping the whole group because the background rectangle was still
  being counted as content (absorb unreliable) and/or padding was inherited from the
  rectangle's empty space. Now: a more robust **background detector**
  (`backgroundChildIndex`) picks the largest filled child that encloses the rest
  (10% tolerance for descenders/anti-aliasing) and absorbs it as the frame
  background, so only the TEXT remains as content. Padding starts at the defaults
  and the frame hugs the text — the background is the frame itself, so it follows the
  padding exactly. Content stays anchored in place on activation (no position jump);
  the background resizes to hug. Reverted Session 96's gap-inheritance (that kept the
  old oversized look).

- **2026-06-20 — Session 96 (Auto Padding polish: overlay, no-jump, fit):**
  • **Padding overlay**: a selected auto-padding frame now shades the padding band
    (teal, dashed inner edge) so you can see the padding and watch it change live as
    you edit the values (`drawNodeSelection`).
  • **No jump on activate**: enabling Auto Padding on a text-over-rectangle now reads
    the padding straight off the background's gaps (left/top/right/bottom), so the
    frame keeps its exact size — and `padBlock` shifts the frame ORIGIN so content
    stays put in document space as padding changes (frame grows outward, not the
    content shoved over).
  • **Selection box** for a frame uses its stored (padded) frame instead of the
    content union, so the box + background + overlay all line up.
  (Background fill already tracks the frame size; the earlier "not expanding" was a
  rectangle left as a child when absorb didn't fire — the gap-based absorb is more
  reliable now.)

- **2026-06-20 — Session 95 (split Auto Layout / Auto Padding + reorder):**
  Reworked the feature into **two independent frame traits** a group can carry
  (either, both, or neither), per the owner's mental model:
    – **Auto Layout** = STACKING only (direction, gap vs space-between, cross-axis
      alignment). Items are ordered by on-canvas position, so dragging one past
      another reorders the stack.
    – **Auto Padding** = HUG + per-side padding + the frame **background**
      (fill / corner / stroke) — the button / tag / card surface. On its own it pads
      around the children's current arrangement; combined with Auto Layout it insets
      the stack. The enclosing-background absorb (rect-behind-text → frame fill) now
      lives here.
  • **Model** (`Document.swift`): `AutoLayout` slimmed to direction/distribution/
    gap/primary/cross; new `AutoPadding` struct (4 paddings + fill/corner/stroke);
    `Node.autoPadding` added next to `autoLayout` (both optional, defaulting Codable).
    ⚠️ MIGRATION: frames made in Sessions 93–94 stored padding/background ON
    autoLayout — those fields are dropped on load. Re-apply **Auto Padding** to old
    test frames (buttons especially). New files are clean.
  • **Engine** (`AutoLayoutEngine.swift`): `stack()` (padding sourced from
    autoPadding), `padBlock()` (pad around the content bounding box, arrangement
    preserved), and the combined path. Still bottom-up + idempotent.
  • **Reorder**: drag-to-reorder works on drop (position-sort). New **Move Item
    Forward / Backward** nudges a selected item one slot along its stack
    (⌥⌘] / ⌥⌘[), via right-click too.
  • **Command coverage**: `toggleAutoLayoutAction` (⌥⌘A) and `toggleAutoPaddingAction`
    (⌥⌘P) — @objc actions, Object-menu items, right-click items, validateMenuItem
    (titles flip Add/Remove). Render (canvas + raster/PDF + SVG) and full-rect
    hit-testing now read the background from `autoPadding`.
  • **Inspector**: two separate sections — **Auto Layout** (direction / gap /
    align) and **Auto Padding** (T·R·B·L padding + Fill + Corner + Stroke), each
    with its own enable switch.
  BUTTON RECIPE now: text over a filled rectangle → select both → **⌥⌘P** (the rect
  becomes the frame fill, text hugged with padding). Nav bar: select the items →
  **⌥⌘A** to stack; add **⌥⌘P** to pad + back the bar.
  REMAINING / NEXT: drag-reorder drop-gap feedback; per-child hug/fill/fixed sizing;
  a faint frame outline on canvas; inspector arrows for nudge.

- **2026-06-20 — Session 94 (Auto Layout fixes: order + frame backgrounds):**
  Fixed two issues from first testing.
  • **Items reordered to array/z-order** (lines between menu items jumped to the
    end): the engine now orders flow children by their **current on-canvas position**
    along the axis (ties keep array order), so layout matches the visual arrangement
    — and dragging an item past a neighbour now reorders the flow for free.
  • **Button background became a side-by-side item**: frames now have their own
    **background** (`AutoLayout.fill` + `cornerRadius` + `stroke`/`strokeWidth`),
    drawn behind the children (canvas + raster/PDF + SVG export). When you add auto
    layout to a selection where one filled shape **encloses** the others (text over a
    rectangle), that shape is **absorbed** into the frame's fill and dropped as a
    child — so the rectangle becomes the button surface and the text sits on it with
    padding. A filled/stroked frame is also now **hit-testable across its whole rect**
    (click the padding to select it). Inspector gained a **Frame** group: Fill
    (PaintWell), Corner, and Stroke + width.
  PROPER BUTTON RECIPE now: text over a filled rectangle → select both → ⌥⌘A. Or:
  select just the text → ⌥⌘A → set a Frame fill. Either hugs the text with padding.

- **2026-06-20 — Session 93 (Auto Layout frames — Figma-style, v1):**
  Groups can now be turned into **auto-layout frames**: a container that positions
  its children along an axis with padding + spacing and **hugs** them, reflowing
  siblings whenever anything changes (the button/tab/nav-bar case the owner asked
  for). Scope chosen: direction (H/V), 4-side padding, spacing (fixed gap *or*
  space-between), cross-axis alignment; frame hugs contents. Per-child hug/fill/
  fixed sizing deferred.
  • **Model** (`Document.swift`): new `AutoLayout` struct (direction, distribution
    `.packed`/`.spaceBetween`, gap, 4 paddings, primary + cross `Align`) with a
    defaulting Codable. Added `Node.autoLayout: AutoLayout?` (nil = plain group) —
    init param + CodingKey + `decodeIfPresent`, so old files load unchanged.
  • **Engine** (`Model/AutoLayoutEngine.swift`): pure, idempotent `reflowed(_:)`
    that walks the tree **bottom-up** (nested frames size before their parents),
    lays out each frame's visible children in LOCAL space, and sets the frame size
    (packed hugs both axes; space-between keeps the user's along-axis size and
    distributes; cross axis always hugs).
  • **Triggers**: reflow runs at the three commit funnels so every edit path ripples
    — canvas `commitNodes`, canvas `updateNode` (text-edit commit), and inspector
    `commitScoped`. No per-feature wiring needed.
  • **Command coverage** (`CanvasView` + App + context menu): `toggleAutoLayoutAction:`
    — a single selected group flips its frame on/off; any other selection is grouped
    first then framed (Figma-style). Wired as an @objc action, **Object ▸ Auto
    Layout (⌥⌘A)** (⌥⌘A chosen over Figma's ⇧A so it can't eat a capital "A" while
    typing), a right-click item, and `validateMenuItem` (title flips Add/Remove).
  • **Inspector** (`MainWindow.swift`): an **Auto Layout** section on group selection
    — enable switch, direction segmented (→ / ↓), Gap vs Space-Between with a gap
    field, four padding fields (T/R/B/L), and a cross-axis align control whose labels
    track the direction (Top/Center/Bottom for a row, Left/Center/Right for a column).
  BUILD WATCH-POINTS: add **`AutoLayoutEngine.swift`** to the app target (new file).
  `Node` gained an init param (`autoLayout:` before `content:`, defaulted) — existing
  `Node(name:frame:content:)` call sites are unaffected. Managed children snap back
  if dragged (expected for v1 — drag-to-reorder is a later pass).
  REMAINING / NEXT: per-child hug/fill/fixed sizing; drag-to-reorder inside a frame;
  a faint frame outline + badge on canvas; primary-axis alignment UI for fixed-width
  frames; nested-frame resize handles.

- **2026-06-20 — Session 92 (SVG import as editable vector layers):**
  • New **`Model/SVGImporter.swift`** — a Foundation + CoreGraphics DOM parser
    (`XMLDocument`) that turns an SVG document into a single editable **group Node**
    (children in group-local coords, frame at the origin), so an imported SVG is a
    real layer tree — not a flattened raster. Scope built per the owner's choice
    ("subset + gradients/text"):
      – Elements: `<g>`/`<svg>`/`<a>` → nested groups; `<path>` (full `d` parser:
        M/L/H/V/C/S/Q/T/A + relative, arcs→béziers, multi-subpath via `contours`);
        `<rect>` (corner radius), `<circle>`/`<ellipse>`, `<line>`,
        `<polyline>`/`<polygon>`, `<text>` (position/size/family/fill, one run).
      – **Transforms** (`translate/scale/rotate/matrix/skewX/skewY`, including the
        transform list) are baked into geometry. Axis-aligned rect/ellipse stay as
        native Rectangle/Ellipse shapes; rotated/skewed ones fall back to a Path so
        nothing is distorted.
      – **Fills/strokes**: solid colors (hex #rgb/#rrggbb/#rrggbbaa, rgb()/rgba(),
        named), `fill-opacity`/`stroke-opacity`/`opacity`, presentation attrs **and**
        inline `style="…"` (style wins). `url(#id)` fills resolve to
        `<linearGradient>`/`<radialGradient>` → our angle-based `GradientFill`
        (objectBoundingBox; linear angle from x1,y1→x2,y2; stops via stop-color /
        stop-opacity / style).
      – **viewBox** maps to the declared width/height so 1 user unit ≈ 1 pt.
  • **Wiring** (`Canvas/CanvasView.swift`): `looksLikeSVG`, `svgData(from:)`
    (file URL `.svg`, raw SVG pasteboard data, or pasted `<svg…>` markup),
    `placeSVG(_:at:)` → imports the group centred at the drop/viewport point as one
    undo step ("Import SVG"), **falling back to raster** if parsing fails so a drop
    never just disappears. Hooked into **drag-drop** (registered `UTType.svg` +
    `.string` drag types, `canDrop`, `performDragOperation` prefers vector),
    **paste**, and **File ▸ Place Image…** (NSOpenPanel now allows `.svg`; routes
    SVG → `placeSVG`, else → `placeImageData`).
  • Each imported element becomes its own editable layer (move/resize/rotate, edit
    fill/stroke, edit path points, regroup) — verified the group renderer offsets
    children by the group origin, so the whole import moves as a unit and re-localizes
    cleanly.
  BUILD WATCH-POINTS: `SVGImporter.swift` must be added to the **app target** (new
  file). No `NodeContent` switches changed (importer only constructs nodes), so no
  exhaustiveness fallout expected. Round-trip self-check: SVG→layers→SVG-export
  should look the same for the supported subset.
  REMAINING / NEXT: `<use>`/symbols, clip paths/masks, dash patterns, multi-run
  `<tspan>` text, percentage/`em` units, CSS `<style>` selectors (only inline style +
  presentation attrs today); named workspace presets; multi-window panel polish.

- **2026-06-16 — Session 91 (raster image layers + thumbnail extension):**
  • **Images**: new `NodeContent.image(ImageContent)` (bytes stored base64 in the
    .design JSON → self-contained) + `naturalSize`. Threaded `.image` through every
    content switch (drawNodeContent with a flipped CGImage draw + decode cache,
    silhouette, isBoxResizable, SelectionTransform, layer icon, export). Input:
    **File ▸ Place Image…** (⇧⌘P, NSOpenPanel), **paste** an image from the
    clipboard, and **drag-drop** image files onto the canvas (registerForDraggedTypes
    + performDragOperation), each creating an image node sized-to-fit at the drop
    point (one undo step). Export: PNG/PDF draw the image; SVG embeds a base64 PNG
    data URI `<image>`. Images get the generic frame/opacity/blend/effects controls;
    resize/rotate/group all work. (SVG-as-vector import still deferred — SVG files
    rasterize via NSImage if droppable.)
  • **QuickLook thumbnail for .design**: wrote `ThumbnailExtension/ThumbnailProvider.swift`
    (decodes Document, renders the first artboard via `ExportRenderer.pngData`).
    REQUIRES a one-time Xcode step the owner must do: add a Thumbnail Extension
    target, set its `QLSupportedContentTypes = [tapps.exp-design.designfile]`, use
    this provider, and add the model + ExportRenderer files to the target's
    membership. Steps given in chat.
  REMAINING / NEXT: SVG vector import; named workspace presets; multi-window
  refinements (de-emphasise inapplicable panels, drag-tear-out gesture); panel
  styling polish.

- **2026-06-16 — Session 90 (file extension RESOLVED + layer blend modes):**
  • File open finally works: the saga was (1) LaunchServices hadn't registered
    the dev build, then (2) a sticky LS cache on the old type id/extension. Fixed
    by a FRESH type id (`tapps.exp-design.designfile`) + extension **`.design`**,
    plus `lsregister -f <built app>`. Verified the built Info.plist merges
    correctly. Old `.exp` files still open via the Open panel for migration.
  • **Layer blend modes** (Photoshop-style): new `BlendMode` enum (normal …
    luminosity) on `Node` (`blendMode`, tolerant-decoded default normal) mapping
    to `CGBlendMode` + CSS `mix-blend-mode`. Canvas + PNG/PDF export apply it via
    the node's transparency-layer composite (set blend before `beginTransparencyLayer`,
    which resets to normal inside and composites with it); SVG export emits
    `style="mix-blend-mode:…"` on the node's `<g>`. Inspector got a **Blend** picker
    next to opacity (single selection), routed through `mutateScopedNode`. Works on
    any node incl. groups (the group's layer blends as a unit).
  NEXT (deferred): raster image layers (place/paste/drag PNG/JPG/GIF), then SVG;
  QuickLook thumbnail extension for `.design`.

- **2026-06-16 — Session 89 (file extension → ".design"; LS-cache lesson):**
  Owner's testing clarified the real story: `.exp` actually DOES work once the
  app's type is registered — the original "nothing happens" was just
  LaunchServices not having registered the build yet. The catch is LS **caches**
  the registration, so changing the extension (to `.expd` last session) didn't
  take — a new Save still offered the cached `.exp`. Per owner preference, set the
  extension to **`.design`** (Info.plist `UTTypeTagSpecification` → `design`; UTI
  id unchanged; `.exp` kept in `readableContentTypes` via `legacyExp` for opening
  old files). KEY: an extension change only applies after LS re-registers — Clean
  Build Folder + run, or `lsregister -f <app>` / nuke DerivedData. NEXT: QuickLook
  thumbnail extension for `.design`.

- **2026-06-16 — Session 88 (can't open files → ".exp" extension collision):**
  Root cause (from Get Info: Kind "Symbol Export", opens with Xcode): **macOS
  already owns the `.exp` extension** as the developer "Symbol Export" (linker
  exports) type, so our app's exported UTI can't claim it — `.exp` files resolve
  to the system type, never match `readableContentTypes`, and the app silently
  ignores them (Finder AND the in-app Open panel). Fix: switched the document
  extension to **`.expd`** (Info.plist `UTTypeTagSpecification` exp → expd; the
  UTI identifier `tapps.exp-design.document` is unchanged, so new saves are
  `.expd` and associate/open correctly). To migrate, the Open panel still lists
  old `.exp` files via `UTType.legacyExp` (the system type for `.exp`) added to
  `readableContentTypes`; they decode as the same JSON, then Save As writes
  `.expd`. (Needs a clean build so LaunchServices registers the new type.) NEXT:
  QuickLook **thumbnail extension** for `.expd` (chosen) — new Xcode target.

- **2026-06-16 — Session 87 (text "jumps right" while editing):** Root cause: the
  inline editor forced the auto-box NSTextView to a 220pt minimum width, while the
  canvas draws text in a container the width of the node's frame. For a text node
  narrower than 220 with centre/right alignment, the editor centred the text in
  the wider container → it shifted sideways during editing, snapping back on
  commit (the user's short system-font sample surfaced it). Fix: size the editor
  to the actual box width for existing nodes (`max(base.width, isNew ? 220 : 1)`),
  keeping the typing-room minimum only for brand-new empty nodes — so the editor's
  container matches the canvas and alignment renders identically.

- **2026-06-16 — Session 86 (bug-fix batch from real use):**
  1. **Component overrides** — the override rows only iterated the source's
     TOP-LEVEL children, so a component whose content is grouped showed the
     "Overrides" title and nothing else. `instanceControls` now recurses into
     groups (`overridableChildren`) to list every text/fill leaf.
  2. **Double-click rename** in the Layers panel — re-added (`.onTapGesture(count:2)`
     on the row name → `beginRename`), alongside right-click + the Inspector field.
  3. **Layers drop-line math** — `LayerDropDelegate` used a fixed 24pt row height,
     so the insertion line landed inconsistently on taller rows. Now measures the
     actual row height (GeometryReader) and uses it for the before/after/into
     thresholds.
  4. **Text editing in groups** — was gated to top-level nodes, AND the editor was
     positioned with the node's group-LOCAL frame (so it appeared offset from the
     box — likely the "jumps outside the box" symptom), AND commit wrote back with
     a top-level-only `firstIndex` (so a nested edit would be lost). Fixed: allow
     editing nested text (when no ancestor is rotated), position the NSTextView at
     the ABSOLUTE frame (`nodeOffset`), write back via recursive `updateNode`, and
     skip drawing the edited node at any depth (no double-draw). NOTE: if the
     "jumps outside the box" still happens for a TOP-LEVEL text node, need a repro
     (box type / alignment / zoom) — top-level positioning was already absolute.

- **2026-06-16 — Session 85 (shared panels across documents):** Fixed a 2nd
  document spawning a 2nd set of floating panels. The tray arrangement + active
  context moved out of per-document `AppState` into a new global
  **`PanelHub.shared`** (@Observable): `trays` (persisted app-wide at
  `exp.trays.v1`), the tray mutation methods, and weak `activeApp`/`activeDocument`
  + `activeUndo`. `PanelWindowManager` is now global (windows keyed by tray id)
  with a single `reconcile()` entry point — shows the trays when the active
  document is Multi-Window, hides them otherwise. `TrayWindowView` binds to
  `hub.activeApp/activeDocument`, so switching document windows **re-points the
  same panels** at the new document (content re-renders; no second set). The undo
  manager is vended dynamically from `hub.activeUndo`. `MainWindow` claims the
  panels via `@Environment(\.controlActiveState)` (on appear / becoming key) and
  reconciles on mode + `PanelHub.trays` changes. `AppState` keeps per-window
  things (single-window docks, workspace mode) and now delegates
  `isPanelShown`/`togglePanel`/`ensurePanelTray` to the hub for the multi case.
  Note: per-document mode still applies — switching to a Single-Window document
  hides the shared panels; back to a Multi-Window document shows them again.

- **2026-06-16 — Session 84 (Window menu redesign + tray-close fix):**
  • **Bug:** closing a tray via its ✕ left the tray in the model, so its panels
    couldn't be reopened. Now `TrayWindowDelegate.windowWillClose` →
    `PanelWindowManager.trayWindowClosed` removes the tray from the model on a
    USER close (a `programmaticClose` flag distinguishes our own mode-switch/merge
    closes, which keep the model so toggling back restores).
  • **"Untitled" windows:** tray windows now set a `title` and
    `isExcludedFromWindowsMenu = true`, so they no longer clutter the system list.
  • **Panels menu → Window menu:** dropped the custom "Panels" menu; appended to
    the system Window menu via `CommandGroup(after: .windowList)`, so the document
    window stays in its own (auto) section. New `WindowMenuItems` (driven by a
    `WindowMenuModel` published through `@FocusedValue` from MainWindow + each tray
    window) renders: a **panels section** (icon + name, checkmark when visible,
    click = reveal/focus, NEVER closes — closing is the panel's ✕; disabled in
    single-window) and a **single-window dock section** (Show/Hide left/right with
    a flipping label; disabled in multi-window). Reveal uses a Toggle whose setter
    always reveals (so the checkmark reflects state but a click can't close).
  • Dropped the old "Reset Panel Layout" menu item (can re-add later).
  Risk note: `@FocusedValue` from the manually-hosted tray windows may not always
  feed the scene's command focus; MainWindow covers the common case, and if a
  tray window is key and the menu greys out, that's the cause — fix would be an
  app-level active-document holder. Toggling/reveal actions use captured closures
  so they fire regardless once the value is present.

- **2026-06-16 — Session 83 (tray polish + Panels menu reflects state):** Two
  follow-ups on the tray model. (1) The tray **grab bar now only appears when a
  tray has >1 panel** — a lone-panel tray moves via its (transparent) native
  title bar, so there's no redundant second header. (2) The **Panels menu now
  reflects + toggles the actually-shown panels in BOTH modes**: `togglePanel` is
  mode-aware (tray membership in Multi-Window, dock membership in Single-Window),
  `isPanelShown` reports per-mode visibility, and `validateMenuItem` sets each
  item's checkmark (Layers/Properties/Components + the dock toggles show ✓ when
  shown). Note: menu checkmarks rely on the AppKit validateMenuItem path through
  SwiftUI commands — toggling is solid regardless; if a checkmark ever doesn't
  render we'd switch those items to FocusedValue-bound Toggles. Owner notes
  panels/groups/tabs styling polish is wanted "eventually" — parked, fine for the
  current feature/panel count.

- **2026-06-16 — Session 82 (multi-window → TRAY model; replaces snapping):**
  Reworked multi-window per owner feedback. Separate-window snapping/grouped-move
  (Session 80) was choppy because it synced several NSWindows every drag tick; it
  is replaced by a **tray** model: panels combine into ONE window (a tray) with a
  **grab bar** on top — dragging the bar moves the whole unit smoothly (native,
  single window). New `PanelTray` (panels + per-panel collapsed + frame) lives in
  `AppState.trays` (Codable, persisted alongside the rest of the layout).
  `PanelWindowManager` now maps trays→windows (`syncTrays`: open new, close gone),
  records each window's frame back via `setTrayFrame`, and **removes the
  full-screen/zoom button**. `TrayWindowView` renders the grab bar + stacked
  `PanelSection`s. Interactions: drag a panel **header** onto a tray to
  merge/reorder (horizontal insertion line, cross-window via SwiftUI DnD with the
  dragged id shared through `AppState.trayDraggingPanel`); **click a header** to
  collapse/expand its body (Adobe-style); a header **pop-out button** tears a panel
  into its own tray. MainWindow seeds trays on first multi entry, syncs on
  `app.trays` change, restores on launch.
  DEFERRED (told owner): side-by-side docking inside one tray (vertical line /
  multi-column — currently vertical stacking only); the pure drag-header-OUT tear
  gesture (pop-out button stands in, since SwiftUI DnD can't catch a drop on empty
  space); single-window dock still collapses via its chevron.

- **2026-06-16 — Session 81 (panel window snapping + grouped move):** Floating
  panel windows now **snap together** and **move as a unit**. While dragging a
  panel, its edges magnetize (12pt) to nearby panel windows' edges (flush docking
  or alignment); once windows are flush they form a **cluster**, and dragging any
  one drags the whole connected cluster. Implemented in `PanelWindowManager`:
  `windowMoved` computes the docked cluster from live frames, translates the
  others by the same delta, then applies an edge-snap to non-cluster neighbours;
  `moveWindows` does programmatic neighbour moves behind a re-entrancy guard.
  `PanelWindowDelegate` (was PanelUndoDelegate) forwards `windowDidMove` /
  `windowDidResize` via `MainActor.assumeIsolated`; `liveFrames` + `appPrefixForKey`
  track open windows per document. Snapping during a live OS drag can be slightly
  jittery near thresholds — tune `snapDistance`/`flushTolerance` after testing.

- **2026-06-16 — Session 80 (remember floating panel window frames):** Floating
  panel windows now keep their size + position across single⇄multi toggles (and
  launches). `PanelWindowManager` records each window's `frame` on close
  (`closePanels` runs on toggle-to-single and on document-window close), keyed by
  panel (global, `exp.panelFrames.v1`), and restores it on open instead of the
  staggered default. First-time-only windows still stagger. This sets up the
  intended model for named workspaces later: **picking a saved workspace = reset
  to that preset; toggling/opening = restore your last live state.** Avoided a
  delegate/concurrency detour by capturing frames in the @MainActor manager at
  close time rather than via window move/resize callbacks (good enough — captures
  the last state on every toggle and on quit).

- **2026-06-16 — Session 79 (layout persistence + multi-window toggle polish):**
  Two small wins. (1) Disabled the left/right dock toggle buttons + their
  Panels-menu items in Multi-Window mode (no docks there) — buttons via
  `.disabled(workspaceMode == .multiWindow)`, menu via `validateMenuItem`.
  (2) **Layout now persists between launches:** `AppState` saves a `PersistedLayout`
  (workspace arrangement incl. collapse/weights/**column widths**, workspace mode,
  dock visibility) to UserDefaults on change (property `didSet`s, guarded by a
  `restoringLayout` flag) and restores it in `init()`. Real column widths are
  captured as the splitter is dragged (`DockColumnView` reports `geo.size.width`
  → `AppState.setColumnWidth`). If the saved mode was Multi-Window, `MainWindow`
  re-floats the panels on `.onAppear` (deferred a tick). `WorkspaceMode` is now
  Codable. It's an app-wide workspace preference, separate from document data.
  NEXT (13d remainder): multiple **named** workspace presets + a picker. Plus the
  outstanding 13c refinements (live single-panel open/close in multi mode,
  de-emphasis, tear-out/re-dock).

- **2026-06-16 — Session 78 (multi-window mode, first pass):** The Multi-Window
  workspace mode now does something real: switching to it (top-right mode switch)
  **floats every layout panel into its own macOS window** that can be dragged to a
  second monitor — the multi-monitor payoff. New `UI/PanelWindow.swift`
  (`PanelWindowManager`): hosts each panel via `panelContent` in an `NSWindow`,
  injects the SAME `AppState` + document and vends the doc's undo manager through
  a window delegate; staggered placement. `MainWindow` hides its docks in
  multi-window mode (canvas fills) and drives open/close via
  `.onChange(of: app.workspaceMode)`, plus `closePanels` on `.onDisappear`.
  `AppState.layoutPanels` enumerates the panels to float. Because AppState is
  shared, the floating **Properties** window tracks the main canvas selection live
  and its edits land on the document's undo stack. Default workspace floats
  Layers · Properties · Components.
  NEXT (tracked in 13c): live open/close when toggling a single panel in multi
  mode (today it syncs on mode-switch only); de-emphasise inapplicable panels;
  drag-to-re-dock / tear-out. Then **13d persistence/workspaces**. Build note: new
  file `PanelWindow.swift` — ensure it's in the target if not auto-synced.

- **2026-06-16 — Session 77 (panel reorder + Panels menu → single-window mode
  done):** Drag a panel **heading** to reorder it within a column or move it to
  the other column — insertion line shows where it lands, the dragged section
  dims. Built with the Layers-panel drop-delegate pattern (closure does the move
  so there's no actor-isolation snag); `AppState.moveGroup(_:toSide:before:)`
  handles remove-from-any-column + insert. New **Panels menu**: Show/Hide
  Layers · Properties · Components, Show/Hide Left Dock (⌥⌘\) · Right Dock (⌘\),
  Reset Panel Layout — dispatched to the focused canvas (`togglePanel*` /
  `toggleLeft|RightDock` / `resetPanelLayout` @objc actions) → `AppState.togglePanel`
  / `resetWorkspace`. With this, **single-window mode is feature-complete**
  (tabbed-when-needed headings, collapse/expand, resize, reorder, contextual
  hide, show/hide + reset). NEXT per the plan: **13c multi-window mode** (panels
  as separate NSWindows for multi-monitor), then **13d persistence/workspaces**.

- **2026-06-16 — Session 76 (multi-selection + group resize/rotate):** Closed the
  long-standing block: you can now resize AND rotate a multi-selection or a
  single group — on the canvas and in the Inspector. New `Model/SelectionTransform.swift`
  holds the shared, pure math (so canvas + inspector agree): `scaled(node, about:
  sx:sy:)` (recursively scales group children + path points + line endpoints),
  `rotated(node, aboutDoc:deg:)` (orbits each node's centre + adds the delta to
  its own rotation — works for every shape incl. lines), `visualBounds` (rotation-
  aware AABB) + `unionBounds`. Canvas: new `.resizeSelection` / `.rotateSelection`
  drag modes draw a unified 8-handle box + rotate knob over the selection bounds
  whenever >1 node OR a single group is selected (a lone non-group node keeps the
  existing single-node path). Free drag = non-uniform; **Shift = proportional**
  (reuses `proportionalFrame`); rotate snaps to 15° with Shift; transforms read
  from a start-of-gesture baseline snapshot so there's no drift; one undo step per
  gesture. Inspector: group W/H now scales children (was frame-only); a
  multi-selection shows X/Y/W/H acting on the selection's bounding box (move all /
  scale-about-top-left). Group rotation in the Inspector already worked (it sets
  `group.rotation`, which the renderer applies to children).
  KNOWN GAPS (noted, not blocking): numeric **rotation field for a *multi*-selection**
  isn't added (needs a stored selection angle) — use the canvas knob; resizing a
  selection that contains already-rotated items scales in screen axes (shear-ish,
  like most tools) rather than per-item local axes; nested-CHILD direct handles
  remain move-only (separate backlog item).

- **2026-06-16 — Session 75 (single-window polish + system line + mode scaffold):**
  Reframed Phase 13 into **two workspace modes** (single-window default vs.
  multi-window/Photoshop later) — see the Phase 13 decision block. This session:
  • **Top-right system line** (`TopSystemControls` in MainWindow toolbar): moved
    the zoom cluster out of the Inspector into a one-line, always-visible group
    with the dock show/hide toggles + a workspace-mode switch (`AppState.workspaceMode`).
    Removed the old far-left sidebar toggle; New Artboard stays centered.
  • **Single-window polish:** `Workspace.default` is now one panel per group (no
    combined tabs — tabs parked for multi-window). Rewrote `DockColumnView` with an
    **explicit-height model** (GeometryReader + `columnMetrics`): groups pack from
    the top, collapsed = header-only, expanded share leftover by `weight` — fixes
    the "collapsed header flung to the bottom" bug. **Animated** collapse/expand
    (Reduce-Motion aware; content stays mounted + `.clipped()` so it slides).
    **Draggable dividers** resize adjacent expanded groups (`PanelGroup.weight` +
    `AppState.adjustGroupHeights`). Default widths bumped to 264/300 so content
    doesn't start clipped.
  • **Removed dock panels' internal titles** (Layers/Inspector) — group heading is
    the only title now; source-editor window keeps its own via new
    `showsTitle`/`showsZoom` flags on LayersPanel/RightPanel (default true).
  • **Contextual whole-panel visibility** (`isApplicable`): in single mode,
    Components hides until a component exists; Color reserved/hidden. Multi mode
    will show all (de-emphasized) — not built yet.
  NEXT: panel-section **reorder** (drag heading) in single mode; then 13c
  multi-window (separate NSWindows for multi-monitor) + Window menu.

- **2026-06-16 — Session 74 notes (13a testing → next-session punch list):** Tabs
  look good. Owner feedback to address next session (logged in Phase 13 as 13a.1 +
  a promoted 13c):
  1. **Default widths too narrow** — right dock starts clipping the left edge of
     panel content on every launch; owner has to widen it each time. Give docks
     sane default/ideal widths (and/or persist width). Never start clipped.
  2. **Collapse direction is wrong** — collapsing a group flings its header to the
     bottom of the column. Wanted: header **stays put**, space collapses **upward**,
     header position stable (no jumping). Rework the height model accordingly.
  3. **Animate** collapse/expand + resize (slight, non-jarring; respect Reduce
     Motion → instant).
  4. **Remove the panels' own internal header titles** now that the tab shows the
     name (quick space-saving polish).
  5. **Independent/floating windows needed EARLY** — the main motivation is moving
     panels to a **second monitor** to see everything at once. So real separate
     NSWindows is promoted from "later/optional" to a near-term goal: single-window
     is the default, "float all panels" is a workspace option. (Panels are already
     environment-hosted, so reuse the SourceEditorWindow hosting pattern.)

- **2026-06-16 — Session 74 (Phase 13a — dock foundation):** Started the
  Photoshop-style dockable-panel system. Decision: **in-window** float/dock
  first (panels stay environment-hosted, so true separate windows can come later
  without a rewrite); dock manages **Layers + Properties** now plus reserved
  **Color** and a real **Components** panel. New `UI/PanelDock.swift`: the layout
  model (`PanelID`, `PanelGroup`, `DockColumn`, `Workspace.default`) and the
  rendering views (`DockColumnView`, `PanelGroupView`, `PanelTab`, `panelContent`
  router, `ComponentsPanel`, `ReservedPanel`). `AppState` gained `workspace` +
  `dockGroups`/`setActivePanel`/`toggleGroupCollapsed`/`resetWorkspace`.
  MainWindow now renders both dock columns from the model (left = Layers; right =
  Properties/Color tabs above Components), gated by the existing show-left/right
  toggles; column width via the HSplitView. Delivers **tabbed groups** + **collapse
  /expand** + width resize. Components list opens the same source-editor window the
  canvas double-click uses and auto-populates from `model.sources`. NEXT (13b):
  drag-to-rearrange tabs/groups + Window-menu panel show/hide; then 13c float,
  13d saveable/persisted workspaces.

- **2026-06-11 — Session 73 (polygon tool + tool-icon swaps):** Swapped the Edit-Points
  icon → `beziercurve` and Pen → `point.topleft.down.to.point.bottomright.filled.curvepath`.
  New **Polygon** tool/shape: `PolygonShape` (sides clamped 3–25, fill/stroke/strokeWidth)
  + `NodeContent.polygon`; vertices inscribed point-up in the frame so it resizes like
  rect/ellipse. Drawn by dragging (default 3 = triangle; `AppState.polygonSides` remembers
  the last count), shortcut **G**, in the tools strip's shapes group (icon `triangle`).
  Rendered on canvas + PNG/PDF + SVG (`<polygon>`); supports rotation, opacity, effects
  (silhouette), snapping, convert-to-path, pen add-point, and nesting — all the shape
  machinery. Inspector shows the standard fill/stroke + a **Sides** field/stepper (3–25)
  that also updates the tool default. _Tested: build pending; new `.polygon` case threaded
  through every NodeContent switch (render/export/hit/convert/icons)._

- **2026-06-11 — Session 72 (UI polish round 1: align row + tools strip):** Owner started
  the visual-polish phase (focus: panel layout + tools strip; icon swaps deferred — owner
  will supply exact SF Symbol names). Inspector **Align** section redesigned: the
  Selection/Artboard scope is now a labeled "Relative to" **segmented** control (distinct
  shape from the icon buttons) and **Distribute** is its own clearly-labeled row — fixes
  the mis-click between the scope dropdown and the distribute buttons. **Tools strip**:
  grouped into selection · shapes · make with hairline dividers, added a hover highlight,
  firmer active state (semibold glyph + accent fill), and a separator hairline against the
  canvas. _Broad inspector section-spacing unification deferred (do incrementally to avoid
  blind visual regressions)._

- **2026-06-11 — Session 71 (⌘G crash fix):** Session 70's `group()` used
  `reorderInParents`, which visits EVERY array holding a selected id — including the
  group it had just created (whose children are those ids) — so it regrouped endlessly
  → stack overflow / crash. Rewrote `group()` to act on the one target array directly:
  top-level selection groups in `currentNodes`; a same-parent-group selection groups via
  `mutateNested(parentID)` on that group's children; mixed parents pull to a top-level
  group. No re-descent, no recursion.

- **2026-06-11 — Session 70 (group/ungroup + pen-add inside groups):** `group()` now
  works at any level: selection sharing one parent is grouped IN PLACE there (via
  `reorderInParents` + `parentGroupID`), a selection spanning parents is pulled to a
  top-level group (absolute frames). `ungroup()` recursively dissolves a selected group
  anywhere in the tree, rebasing children into the parent's space; `selectionHasGroup`
  resolves nested. So ⌘G / ⇧⌘G work inside and outside groups. Pen "add point" now
  targets the DEEPEST shape under the cursor (so it hits shapes nested in a group),
  converts it to a path if needed, and inserts the anchor using chain-aware local coords
  (`docToParentLocal` + node rotation); the "+" cursor lights up over nested shapes too.

- **2026-06-11 — Session 69 (right-click + convert on nested):** Right-clicking a layer
  inside a group no longer jumps focus to the parent group. `menu(for:)` now targets the
  selected node when it's under the cursor (via `hitPath`), keeping a drilled-in child
  active; falls back to top-level only when nothing relevant is selected. Also made the
  conversions work on nested items: `convertSelectionToPaths` converts each selected
  shape in place via `mutateNested`; `convertSelectedTextToShapes` replaces the text node
  in its parent array via `inParentArray` (the outline is already built in the text's
  parent-local space); and `selectionConvertibleToPath` now resolves nested nodes. So
  Convert to Path / Convert to Outlines work on shapes already inside a group.

- **2026-06-11 — Session 68 (nested line selection + point editing):** Two consistency
  fixes. (1) Line selection now maps endpoints through the node's own rotation AND
  ancestor-group rotations (`nodeLocalToView`) so a nested/rotated line's highlight sits
  on the line, matching shapes. (2) The path point editor works on paths inside groups:
  `drawPathPoints`/`hitTestPathPoint` map anchors via `nodeLocalToView`, `pathPointDrag`
  inverts with `viewToNodeLocal` (new `docToParentLocal` inverse), and the node tool now
  selects the DEEPEST element under the cursor so you can grab a nested path directly.
  Added `nodeLocalToView`/`viewToNodeLocal`/`docToParentLocal` helpers.

- **2026-06-11 — Session 67 (rotated-group selection box):** The selection outline for a
  child of a rotated group was axis-aligned at the un-rotated location. Now
  `drawNodeSelection` detects rotated ancestors (`ancestorGroups`) and draws a
  transformed quad — the node's frame corners (with its own rotation) mapped through each
  ancestor group's rotation via `parentLocalToDoc` — so the box sits on the shape.

- **2026-06-11 — Session 66 (drag inside rotated group):** Dragging a child within a
  rotated group now moves along the group's rotated axes, not the screen axes. The
  `.nodes` drag converts the document-space delta into each node's parent space via
  `ancestorRotation(of:)` (sum of ancestor group rotations) + `rotateVector(_:by:)`.
  Resolves the follow-up logged in Session 65.

- **2026-06-11 — Session 65 (rotated-group hit-path fix):** Clicking/drilling into a
  ROTATED group missed its children — `hitPath` (the select/drill walk) passed the raw
  cursor down without undoing each group's rotation. Now it inverse-rotates the point
  about each rotated group's center while descending (mirroring `nodeHit`/`drawNode`),
  so children of rotated groups select where they actually appear. _Known follow-up:
  dragging a child WITHIN a rotated group still applies the move in doc space, not the
  group's rotated local space — logged for later._

- **2026-06-11 — Session 64 (nested layer select + group box):** Two fixes. (1) Clicking
  a layer INSIDE a group in the Layers panel now selects just that layer — manual
  `DisclosureGroup` children don't reliably feed `List(selection:)`, so nested rows get
  an explicit select-on-tap (`NestedTapSelect`; top-level rows keep native List
  selection for Shift/⌘ multi-select). (2) A group's on-canvas selection box now draws
  around the live union of its descendants (`groupContentBounds`) instead of the stored
  group frame, so it updates immediately when the group's footprint changes (e.g. a
  layer dragged into it via the panel) — matching the hit area, which was already correct.

- **2026-06-11 — Session 63 (Layers drag-into-group / component):** Replaced the Layers
  panel's native `onMove` with a location-aware `LayerDropDelegate`: top/bottom edge of a
  row = reorder (before/after, drawn with an accent insertion line), middle of a group OR
  component-instance row = drop INTO it (accent fill highlight). `handleDrop` recursively
  extracts the dragged node and re-inserts it — into a group's children (at the back =
  display bottom), as a sibling before/after a target, or (onto an instance) into that
  component's shared **source** — preserving absolute position via parent-offset math, and
  blocking a group from being dropped into its own subtree. New model helpers: `parentOffset`,
  `parentNodeID`, `extract`, `insertIntoGroup`, `insertSibling`, `moveIntoSource`. Works in
  the component source editor too (scope-aware). _Refinement: dropping among an expanded
  group's children shows the child's line but not a simultaneous parent-group highlight yet._

- **2026-06-11 — Session 62 (universal edit ops for nested):** Made the edit
  operations work on nested children, however deep, in both document and component-
  source scopes. New recursive helpers `inParentArray` (mutate the array that
  directly holds a node) and `reorderInParents` (transform every parent array that
  holds a selection). `duplicateSelectedInPlace` now clones each selected node right
  after itself inside its own parent (fresh ids via `cloned`), so duplicate (⌘D) and
  option-drag work nested (removed the old top-level guard). `collectSelectedNodes`
  gathers nested selections with absolute frames so copy/cut/paste position correctly.
  `nudgeOrder`/`reorderSelection` (bring/send) reorder within each selection's parent
  group. Delete was already nested-aware (`removeNested`); rotate/opacity/etc. via the
  Inspector were made recursive in Session 61. _Still top-level only: align/distribute
  (logged to backlog)._ Next: Layers-panel drag INTO a group/component.

- **2026-06-11 — Session 61 (select inside groups):** Drill into groups. Canvas:
  `node(_:)`/`updateNode` are now recursive (search/mutate into groups), plus
  `nodeOffset`, `isTopLevelNode`, `hitPath`, `mutateNested`, `removeNested`.
  **Double-click** drills one level deeper along the cursor's hit path (repeat to go
  deeper); **⌘-click** selects the deepest leaf directly; single-clicking a
  drilled-in element keeps it so you can drag it. Selection drawing, `selectedNode
  Origins`, and delete are offset/nesting aware; resize/rotate handles are suppressed
  for nested (move-only) so handle math stays correct. Inspector: `selectedNode`
  resolves nested, and all node-edit commits (position/size/name/rotation/opacity,
  text, shape, path, instance, effects) route through a recursive `mutateScopedNode`,
  so editing a nested child works. Known gaps logged to the refinement backlog
  (nested inline text-edit positioning, nested resize handles, node-tool overlay).

- **2026-06-11 — Session 60 (full menu bar + command-coverage convention):** Owner asked
  to build all the menus AND make it a permanent rule. Added the **Command-coverage rule**
  to CLAUDE.md (every action wired 5 ways in one change: canvas @objc action, menu item +
  shortcut, right-click where contextual, `validateMenuItem`, Inspector control if it has
  params). Restructured `.commands` into File / Edit / Object / Type / Arrange / View
  (Window is system). New canvas actions `selectAll(_:)` (top-level visible/unlocked nodes)
  + `deselectAllAction(_:)` with validation; Edit gained Duplicate ⌘D + Deselect All ⇧⌘A
  (Select All ⌘A rides the system Edit item → `selectAll:`). Right-click gained an
  "Align & Distribute" submenu for 2+ selections. Also wrote **docs/DESIGN-ASSETS.md**
  (icon/cursor/color/button formats, sizes, naming, `design-assets/` handoff manifest) and
  linked it from CLAUDE.md's read-first list, ahead of the panel/icon refinement phase.

- **2026-06-11 — Session 59 (grids):** Both requested kinds. Uniform square grid is a
  session workspace pref (AppState `showGrid`/`gridSize`/`gridSubdivisions`), drawn
  globally with minor+major lines (`drawUniformGrid`), settings in the no-selection
  Inspector, ⌘' toggle. Per-artboard layout grids persist on `Artboard.layoutGrids`
  (`LayoutGrid`: columns/rows with count·gutter·margin, or baseline spacing; +color
  +visible), drawn clipped per board (`drawLayoutGrids`), edited in a new artboard
  "Layout Grids" Inspector section (add menu, per-grid kind/visible/color + numeric
  fields, remove). `snapToGrid` (⇧⌘') extends `snapNodeOffset` with the uniform minor
  lines + layout column/row/baseline edges; ⌘ still disables snapping. Phase 11 done.

- **2026-06-11 — Session 58 (rulers + guides):** Photoshop-style. Rulers draw as top/left
  chrome strips (`drawRulers`/`drawRulerTicks`, nice 1·2·5×10ⁿ steps, pointer marker).
  `Document.guides: [Guide]` (axis + position, persisted with a backward-compatible
  Document decoder). Drag from a ruler creates a guide, drag a guide moves it, drop on a
  ruler deletes it — a new `.guide` DragMode handled in mouseDown/Dragged/Up via
  `beginGuideDrag`/`updateGuideDrag`/`finishGuideDrag`, each one undo step through the
  existing gesture-undo path. `snapNodeOffset` snaps a dragged selection's edges/centers
  to guides + the owning artboard's edges/center (⌘ disables). AppState toggles
  `showRulers`/`showGuides`/`guidesLocked`; View menu adds Show/Hide Rulers (⌘R),
  Show/Hide Guides (⌘;), Lock Guides (⌥⌘;), Clear Guides. Document-scope only (source
  editor unchanged). Completes Phase 11 except the optional grid overlay.

- **2026-06-11 — Session 57 (⌥-hover spacing measurements):** Figma-style measurement
  overlay. `optionHeld` tracked in `mouseMoved`/`flagsChanged`; while held with a
  selection (and not dragging), `drawMeasurements` shows red measure lines + point
  labels: H/V gaps between the selection box and the hovered shape, or the four
  distances to the artboard edges when hovering empty space. Works in document and
  source scopes. Also logged a refinement-backlog note to separate the Align-to
  dropdown from the distribute buttons (owner mis-clicked).

- **2026-06-11 — Session 56 (align & distribute):** Phase 11 kickoff. `AppState.alignTarget`
  (Selection | Artboard) drives the reference rect. `CanvasNSView` gained `align(_:)` (six
  edges/centers) and `distribute(horizontal:)` (equal-gap spacing, extremes pinned, 3+),
  each one undo step on the scoped node list. Reference = selection union, or — in Artboard
  mode — the board owning the selection (single-item align works there too). UI three ways:
  an Inspector "Align" row (six align buttons + two distribute + an Align-to picker, shown
  for any selection, distribute disabled <3, align disabled for a lone item in Selection
  mode), an Arrange-menu block, and `validateMenuItem` gating. Owner chose the Illustrator-
  style toggle over Figma-auto. Next in Phase 11: ⌥-hover spacing measurements, guides.

- **2026-06-11 — Session 55 (outline winding + hit-test):** Two font-dependent bugs in
  convert-to-outlines. (1) Letters showed gaps where contours overlap (an 'e' bar, grunge
  faces) — caused by **even-odd** fill subtracting overlaps. Switched multi-contour paths
  to **nonzero** winding (the rule fonts are designed for) on canvas, PNG/PDF, and SVG
  (dropped `fill-rule="evenodd"`). (2) Only a tiny piece of a glyph was clickable — path
  hit-testing only checked the first contour. Multi-contour paths now hit-test against
  their tight bounding box, so a letter is grabbable anywhere. (3) Point editing was
  first-contour-only — refactored the Edit-Points subsystem to be contour-aware:
  `PathPointTarget` carries a `(contour, index)` address; new `PathShape.editContours`
  / `editPoint` / `mutatePoint` / `contourClosed` helpers route reads & writes to the
  right contour (mirroring `points` to the first). `hitTestPathPoint`, `drawPathPoints`,
  `pathPointDrag`, and the corner/curve toggle now cover every contour; `normalizePath`
  skips multi-contour glyphs (keeps the conversion box). So all sub-shapes of a glyph —
  the inside of an 'o', every piece of a grunge face — are now editable.

- **2026-06-11 — Session 54 (outline refinements):** Owner feedback on convert-to-
  outlines: (1) bounds should hug the ink, not the text frame; (2) only the first
  letter was selectable; (3) want one shape per letter, auto-grouped + ungroupable.
  Rebuilt the outliner as `outlineGlyphs(in:)` returning ONE `GlyphOutline` per glyph
  (character, color, tight `boundingBoxOfPath`, box-relative contours). Convert now
  makes one path node per glyph at its tight box and auto-groups them with the same
  convention as `group()` (union frame + children offset by -union.origin), so each
  letter selects independently and Ungroup splits them. Single glyph → lone node.

- **2026-06-11 — Session 53 (convert text → shapes + CSS shadow sign, checkpoint 3 —
  batch complete):** (1) Shadow Y now matches CSS — negated the CG shadow height in
  the flipped context so +Y reads as *down* (SVG `feOffset` already was). (2)
  Convert-to-outlines: new `PathShape.contours` (optional multi-subpath, even-odd
  fill, backward-compatible decoder) + `renderContours`/`isMultiContour`; canvas
  `bezierPath`, export `nsPath`, and SVG `svgPathData` all honor it (SVG adds
  `fill-rule="evenodd"`). `TextContent.outlineContours(in:)` uses Core Text to glyph-
  outline the laid-out, case-applied text grouped by run color → flipped to local
  y-down → `[PathPoint]` contours (quads promoted to cubics). `convertSelectedText
  ToShapes` replaces the text node with one path (or a group per color), carrying
  rotation/opacity/effects; right-click + Format ▸ ⇧⌘O. This completes the
  typography + effects batch (opacity, case, shadows, outlines).
- **2026-06-11 — Session 52 (drop + inner shadow, checkpoint 2):** New shared
  `EffectsRender` (Color/EffectsRender.swift) with a `Silhouette` helper. Drop shadow
  = stamp the shape outline (or the node's own content for text/lines/groups) into a
  CG-shadowed transparency layer, then draw the real node on top; inner shadow = clip
  to the shape and cast the color inward. Wired into the canvas (`drawNode` split into
  effect passes + `drawNodeContent`), raster export (`drawExportNode` split likewise),
  and SVG (`svgEffectsFilter` → `<filter>`). Inspector gained an "Effects" section
  (add Drop/Inner, per-effect enable/type/color/X/Y/Blur/Spread, remove) for any node
  type. `numericStepping` gained a `max:` clamp. Next: convert text → shapes (last).

- **2026-06-11 — Session 51 (typography + effects batch, checkpoint 1):** Owner asked
  for the rest of typography + basic effects; doing it in order (opacity → case →
  shadows → text-to-shapes), checkpointing between. **Model foundation (all four):**
  `Node` gained `opacity` + `effects` with a custom decoder (also hardens the old
  `rotation` default); new `Effect` type (drop/inner shadow, CSS box-shadow geometry);
  `TextContent.textCase` (CSS text-transform). **Shipped this checkpoint:** (1) Layer
  opacity — model + grouped-transparency render on canvas/PNG/PDF + SVG `opacity` +
  Inspector 0–100%. (2) Case transforms — non-destructive, display-only via
  `displayStrings()`/`attributedString(applyCase:)`, editor edits originals, Inspector
  picker. Next: drop/inner shadow, then convert-text-to-shapes.

- **2026-06-11 — Session 51 (fresh-eyes text commit fix):** Revisited the text
  bug loop from first principles. The "Undo brings the size change back" symptom
  points to a stale focus-loss commit overwriting a newer Inspector/edit state.
  Tightened the split in two places: (1) Inspector font/size/color setters now
  route off the live `app.applyTextStyle` hook directly, instead of trusting
  `app.textSelection` as the "are we editing?" flag (that published style can be
  nil/stale during first-responder churn). (2) `commitTextEditing()` now first
  makes the `NSTextView` first responder again, while the hook is still installed,
  so a pending Inspector text-field value (e.g. Size) commits into the editor
  before the editor snapshot is read. Also guarded deferred selection-style
  publishes so an async selection update cannot resurrect `app.textSelection`
  after the editor has been torn down. For the edit↔view metric jump, switched
  committed canvas text drawing from `NSAttributedString.draw(in:)` to a small
  TextKit (`NSTextStorage`/`NSLayoutManager`/`NSTextContainer`) draw path with
  zero line-fragment padding, closer to the live `NSTextView`. Deliberately did
  **not** reintroduce the Session-44/45 custom-bounds `NSTextView` crash path.
  Verified with `xcodebuild -project "EXP [design].xcodeproj" -scheme "EXP [design]"
  -configuration Debug -destination "platform=macOS" -derivedDataPath
  /private/tmp/exp-design-derived build` → **BUILD SUCCEEDED**. Watch in-app:
  partial selection size change should persist on direct click-out; any remaining
  metric jump is expected to be smaller at 100% but may still need the future
  NSScrollView/magnification editor approach for non-100% zoom.

- **2026-06-11 — Session 50 (synchronous Inspector→editor apply):** The Session-48/49
  fixes didn't take — changes still only stuck if you collapsed the selection first,
  and the *"Publishing changes from within view updates"* warnings persisted. Root
  problem was the **indirection itself**: the Inspector set `app.textStyleOp`, and the
  canvas applied it later on a deferred tick keyed off `updateNSView`. That tick was
  racing the commit and depending on view-update timing. Replaced the whole channel
  with a direct synchronous hook: `AppState.applyTextStyle: ((TextStyleOp)->Void)?`
  (`@ObservationIgnored`), installed by `beginEditingText`, torn down in
  `commitTextEditing`. Inspector control handlers now call `app.applyTextStyle?(op)`
  and the editor is mutated **immediately**, in the same user-event turn — no async,
  no `updateNSView` dependency, no commit race. Combined with the Session-49
  `editorSelectedRange` (targets the real selection even after the Inspector steals
  focus), a size/color/bold change made on a selection now persists on a direct
  click-out. Removed the deferred-apply block from `updateNSView` and the dead
  commit-time flush. _Unrelated, still open: the launch-time state-restoration error
  ("symbol export list" UTType) — autosave trying to reopen a doc; benign but noisy._

- **2026-06-11 — Session 49 (the real "changes lost on click-out" fix):** Inspector
  style changes (size/color/bold/italic/underline) made on a *selection* were lost
  unless you first re-clicked into the editor to collapse the selection. Root cause:
  clicking an Inspector control resigns the `NSTextView`'s first responder, which
  **collapses its live `selectedRange()` to a caret**. The style op (applied on a
  deferred tick / at commit) then read that collapsed range → wrote *typing
  attributes* instead of the selected characters → commit rebuilt the model from an
  unchanged editor → change gone. Fix: remember the last *focused* selection
  (`editorSelectedRange`, updated in `textViewDidChangeSelection` only while the
  editor is first responder) and target it via `effectiveEditorRange()` in
  `applyTextStyleOp`, `applyFontTrait`, `toggleUnderlineText`, and
  `publishTextSelection`; the op also re-asserts that range with `setSelectedRange`
  so the change is visible and the highlight persists. No more need to deselect
  first.

- **2026-06-11 — Session 48 (rich-text fixes):** Three follow-ups. (1) Residual
  *"Publishing changes from within view updates"* — `publishTextSelection()` (called
  from AppKit's `textViewDidChangeSelection`, which can fire during the window's
  layout pass) now writes `app.textSelection` on the next runloop tick via a new
  `setTextSelection(_:)` async helper instead of inline. (2) *"Picker: the selection
  '' / 'Zapfino' is invalid"* warnings — replaced the weight/face `Picker` (which
  reconciles + writes back a missing tag) with a `Menu` of Buttons calling
  `applyFontName`; no selection binding, no write-back. (3) Line-height / alignment /
  letter-spacing only applied **after** the box was deselected — added a `.paragraph`
  `TextStyleOp` case. Extracted `TextContent.paragraphStyle(scale:)` so the canvas can
  re-apply the model's paragraph style to the live `NSTextView` while editing;
  `updateTextContent` fires `.paragraph` whenever `isEditingText`. _Still open: the
  slight edit↔view metric jump at non-100% zoom (scaled-font editor vs CTM render);
  case transforms + convert-to-shapes._

- **2026-06-11 — Session 47 (fix):** Selection size change leaked to the whole node
  on click-out. Cause: the style op is applied on a deferred tick (crash fix). If you
  clicked out before that tick, `commitTextEditing` ran first (`editingNodeID` nil),
  then the queued op took the **whole-node** model path + registered its own undo
  step (hence ⌘Z revealed the correct partial edit). Fix: `commitTextEditing` now
  flushes any pending `textStyleOp` into the editor selection first, then clears it,
  so the queued apply no-ops. Both orderings now apply only to the selection.

- **2026-06-11 — Session 46 (REAL crash fix):** Crash log showed endless
  *"Publishing changes from within view updates"* → infinite Update-Constraints pass
  → `NSGenericException`. Cause: `CanvasView.updateNSView` applied `app.textStyleOp`
  **inline during the SwiftUI update**, and `applyTextStyleOp` publishes
  `app.textSelection`. The op wasn't cleared until an async hop, so each re-render
  re-applied it → publish → invalidate → loop. Fix: defer the apply to
  `DispatchQueue.main.async` AND clear `textStyleOp` first (so a re-entrant update
  can't re-schedule). Also guarded the weight/face `Picker` to only show when its
  selection matches a real face (kills the "selection 'Zapfino' is invalid" /
  empty-tag warnings + their layout churn). (The Session-45 bounds-editor revert was
  a red herring — kept on the safe scaled-font path anyway.) Side note: the
  "symbol export list" state-restoration error is a benign `.exp` UTType clash with a
  system dev type — cleanup later (LSHandlerRank/Owner). **No compiler in chat.**

- **2026-06-11 — Session 45 (crash revert):** App froze+crashed — reverted the
  Session-44 **scaled-bounds NSTextView** (a custom-`bounds` text view outside an
  NSScrollView can send TextKit into a layout loop / assertion). The fixed/paragraph
  editor is back on the proven **scaled-font** path (`textEditScale = zoom`). Also
  removed the per-`updateNSView` commit-poll (mutating the document inside the
  SwiftUI update cycle is reentrancy-prone). Kept the safe Session-44 wins:
  selection-level font size (commit-on-blur removed) and line-height units. Net:
  the edit↔view line-height jump is back to "slight" (the supported fix later is an
  NSTextView in an NSScrollView with `magnification = zoom`, not a bounds hack).
  (Couldn't read the user's crash log from here — project-folder access only.)

- **2026-06-11 — Session 44 (text fixes + line-height units):** (1) **Independent
  font size on a selection now works** — the editor was committing on focus loss, so
  clicking the size field ended editing and dropped the selection. Removed
  commit-on-`textDidEndEditing`; the editor now keeps its selection while you use the
  Inspector and commits on real triggers (canvas click outside, or selection moving
  to another node via `commitTextEditingIfSelectionChanged`). (2) **Line-height
  units** (CSS-style): `LineHeightUnit` = auto / × (unitless, scales with text) / px
  / em, applied in the paragraph style with scale; Inspector unit picker + value.
  (3) **Double-click line-height jump**: the fixed/paragraph editor now lays out at
  TRUE size and scales the VIEW (frame vs bounds) so its wrapping + line metrics
  match the canvas render exactly (`textEditScale` tracks the editor's font scale:
  1 for fixed, zoom for auto). **No compiler in chat.** Watch: the scaled-bounds
  NSTextView for fixed boxes (cursor/caret placement, overflow clipping), and that
  size/font ops still divide by the right scale on commit.

- **2026-06-11 — Session 43:** **Rich text Build 2 (paragraph) + zoom-stable text.**
  Fixed the zoom "hopping": text now lays out at TRUE size and the canvas scales the
  *drawing* (CTM translate+scale, draw in local doc-size rect), so wrap points and
  line height are identical at every zoom (and `draw(in:)` clips a fixed box = the
  crop). Paragraph features: **Auto/Text-box toggle** + **drag-to-create** a fixed
  box with the text tool (`.drawTextBox` drag mode; click = auto, drag = fixed);
  auto hugs, fixed keeps its user size (no height auto-grow → can overflow). Added a
  **red "+" overflow badge** at the box bottom-right when content exceeds a fixed
  box. Added inspector **alignment (L/C/R), line height, letter spacing** (paragraph
  style already in `attributedString`). Selection font-size already works via the
  Session-42 channel. **No compiler in chat.** Remaining Build 2: case transforms +
  convert-to-shapes. Watch: drawTextBox click-vs-drag threshold, fixed-box overflow
  measure, and the CTM text scaling composing with node rotation.

- **2026-06-11 — Session 42 (rich-text fixes):** Fixed the inspector-vs-editor split.
  Font family / face / size / color edited the *model* while the live editor owned
  the text, so they didn't show and were overwritten on commit (only the B/I/U
  buttons worked, since they edit the editor). Added a **style channel**:
  `AppState.textStyleOp` (Inspector → editor selection or whole node, applied in
  `updateNSView`) and `AppState.textSelection` (canvas publishes the selection's
  style on every selection/text change). Inspector controls now read/write the
  selection while editing and the node otherwise; **"Multiple"/Mixed reflects the
  actual selection**, and B/I/U buttons show active state. Fixed **system-font
  styles dropping on commit** (`nsFont` rebuilds bold/italic from the stored name
  when `NSFont(name:)` can't reload a system variant). Double-click now **places
  the caret at the click point** (was jumping to the end), and the editor gets a
  line of slack + a measure pad so the **last line no longer clips**. **No compiler
  in chat.** Watch: the op channel clear (async, no loop), selection summary on
  empty selection (typing attributes), and caret placement before layout.

- **2026-06-11 — Session 41 (fix):** **Paragraph text width was lost on font change.**
  Auto boxes re-measure to a tight single line, so changing the font collapsed a
  resized (wrapped) box back to one line. Pulled the fixed-width box forward from
  Build 2: resizing a text box now sets `box = .fixed`; `measuredSize(boxWidth:)`
  keeps the width and grows height for fixed boxes (auto still hugs); the inline
  editor wraps to the box width; commit preserves it. Explicit line/paragraph
  toggle + drag-to-create remain for Build 2.

- **2026-06-11 — Session 40:** **Rich text — Build 1 (foundation + B/I/U).** Replaced
  plain-string `TextContent` with **styled runs** (`TextRun`) + paragraph props
  (align/lineHeight/tracking/box); backward-compatible Codable (old text → one run).
  New NSAttributedString bridge in `Typography.swift` (`attributedString(scale:)` +
  `init(attributed:…)` rebuilding runs, dividing zoomed sizes back out). Threaded
  through canvas draw, the **rich** inline `NSTextView` (selection works; commit →
  runs), text measuring, PNG/PDF export, and SVG (`<tspan>` per run). **Bold/Italic/
  Underline** via a new **Format menu (⌘B/⌘I/⌘U)** + inspector buttons — selection
  while editing (mutate textStorage), else whole node (toggle all runs via
  NSFontManager traits). Removed the inspector text field (item 1); whole-text
  typeface/size/color show **"Multiple"** when runs differ. **Build 2 next**:
  line/paragraph box + drag, cropped indicator, alignment/line-height/letter-spacing,
  case transforms, selection font-size, convert-to-shapes. **No compiler in chat.**
  Watch: legacy decode (old `.exp` text), attributed↔runs round-trip (esp. system
  vs named faces + size un-scaling), and ⌘B reaching the field editor while editing.

- **2026-06-11 — Session 39:** **Phase 9 — Typography.** `TextContent.fontName`
  (PostScript face; empty = system; defaulted → old files load). New
  `UI/Typography.swift`: `FontCatalog` (cached families/faces via NSFontManager) +
  `TextContent.resolvedFont(scale:)`, `measuredSize()`, `familyName`. Inspector
  text controls gained a **typeface menu** (each family rendered in its own face)
  and a **weight/style Picker**. Routed the resolved font through canvas text draw,
  the inline NSTextView editor, text box measuring (replaced the old system-font-
  only `measureText`/`textSize`), PNG/PDF export, and SVG (`font-family` +
  bold/italic from symbolic traits). **No compiler in chat.** Watch: font menu
  build with many families (cached static), face Picker tag matching the stored
  PostScript name, and measured box sizing with non-system fonts.

- **2026-06-10 — Session 38 (fix):** **Paths resizable/rotatable on canvas + bounds
  toggle.** Root cause of both reported bugs: paths drew only their outline and
  returned early in `drawNodeSelection`, so they had no box, handles, or rotate
  knob — making ⇧⌘B look broken (nothing to toggle when a path was selected) and
  leaving paths only editable via the Inspector. Fix: `isBoxResizable` now includes
  `.path`; the path case draws its outline AND falls through to the box + 8 handles
  + rotate knob. Added **path resize**: a `resizePathBaseline` captured at grab,
  scaled to the new frame (points + bézier handles) so dragging a corner scales the
  path (works rotated too via the existing world-anchor correction). `showSelection
  Bounds` still gates only the thin box outline; handles/knob always show.

- **2026-06-10 — Session 37 (fix):** **Rotated path/point editing.** Pen add-point,
  point drag, bezier-handle drag, anchor hit-testing, and the anchor overlay all
  converted the cursor to path-local space without undoing the node's rotation, so
  points landed at the unrotated location. Added `docToLocal`/`localToDoc` (inverse/
  forward rotation about the node center) and routed every path-edit conversion
  through them. Also fixed `normalizePath`: re-basing the bbox moves the rotation
  pivot, so it now shifts the frame by `(R−I)(Δcenter)` to keep a rotated path
  visually put after edits.

- **2026-06-10 — Session 36:** **Gradient overrides + Rotation.** (1) Component fill
  **overrides now carry gradients**: `InstanceOverride.Value.fill` → `Paint`,
  override UI uses `PaintWell` (legacy solid overrides decode unchanged via Paint's
  RGBAColor path). (2) **Rotation** (Phase 8.5): new `Node.rotation` (deg, CW about
  center, defaulted so old files load). Rendered via CTM rotate on canvas + export,
  and `<g transform="rotate cx cy">` in SVG. Interactions: `nodeHit` inverse-rotates
  the cursor; `drawNodeSelection` draws the box/handles/path-outline inside the
  rotation and adds a **rotate knob** above top-center; new `.rotate` drag sets the
  angle from the cursor (Shift snaps 15°); **rotated resize** transforms the cursor
  to local space and re-pins the opposite corner in world space (`anchorPoint` +
  correction). Inspector gained an **R°** field (stepping). Works in the source
  editor too (shared scope-aware RightPanel + canvas). **No compiler in chat.**
  Watch: rotation sign/flip convention (CTM vs hit-test vs knob angle), rotated
  resize anchor math, and that the knob hit-target tracks the rotated position.

- **2026-06-10 — Session 35:** **Phase 8 build 2 — gradients.** New `Paint` enum
  (`Model/Paint.swift`: `.solid | .gradient`, `GradientFill` = linear/radial +
  multi-stop + angle) now backs rectangle/ellipse/path fills and `Artboard.background`.
  **Backward-compatible Codable**: a solid encodes as a bare `RGBAColor` so existing
  `.exp` files load unchanged; only gradients add a tagged object. Shared
  **`PaintRender`** (CoreGraphics) draws solid+gradient identically on the canvas and
  in the export NSView (so PNG/PDF match); **SVG** gained `<defs>` with
  linear/radial gradients in objectBoundingBox units. New **gradient editor**
  (`Color/PaintEditor.swift`: `PaintWell` + `PaintEditor` + `GradientBar`) — Solid/
  Linear/Radial segmented, stop bar (drag-add/move, select, delete, min 2), stop
  color+position, angle for linear — wired into shape & path fills + artboard bg
  wells. Instance fill overrides pass `representativeColor` (stay solid). Text fill
  stays solid (gradient text + on-canvas handles deferred). **No compiler in chat.**
  Watch: (1) Paint legacy decode (`try? RGBAColor(from:)` path), (2) gradient clip/
  geometry on canvas vs export vs SVG angle, (3) the stop-bar drag add/move gesture,
  (4) the solid↔gradient mode conversion seeding.

- **2026-06-10 — Session 34 (fix):** Component fill overrides now recognize
  **pen-made paths** — added a `.path` case to `ComponentInstance.applyingOverrides`
  (so a path child's fill override actually renders) and to the instance override
  list in the Inspector (a fill `ColorWell` per path child, like rect/ellipse).

- **2026-06-10 — Session 33:** **Inspector in the source-component editor.** Made
  `RightPanel` scope-aware (`scope: CanvasScope`): reads `scopedNodes` (document
  nodes vs a source's children) and writes through one `commitScoped` funnel; all
  eight edit paths (dims, rename, text, line, instance, corner, shape fill/stroke,
  path) now route through it, and `ownerOffset`/`selectedArtboard` no-op in source
  scope. Added `RightPanel(scope: .source(id))` as a third column in the source
  editor window (widened to 880×520, min 760) — so the custom color wells + all
  styling now work on component-source children, updating every instance live.
  **No compiler in chat.** Watch: source-window undo routing through the shared
  manager, and that selecting a source child shows/edits its styling correctly.

- **2026-06-10 — Session 32:** **Phase 8 build 1 — custom color picker + formats +
  OKLCH + artboard background.** New `Color/ColorMath.swift` (sRGB ↔ HSB/HSL/CIE-LCH/
  OKLCH + HEX, lenient parsers/formatters) and `Color/ColorPopover.swift`
  (`ColorWell` swatch button → popover with SV field, hue/alpha sliders, eyedropper
  via `NSColorSampler`, and a format-selector + editable/copyable code field for
  HEX/RGB/HSL/LCH/OKLCH). Replaced **every** SwiftUI `ColorPicker` in the Inspector
  (text/line/shape fill+stroke, path fill+stroke, instance fill overrides) with
  `ColorWell`; bindings are now `Binding<RGBAColor>` (no lossy Color round-trip).
  Added **`Artboard.background`** (backward-compatible decoder, default white),
  rendered on the canvas and in PNG/PDF/SVG export, with a "Background" well in the
  Inspector. Model stays sRGB; OKLCH/LCH authoring converts to gamut-clamped sRGB.
  **Gradients = build 2 (next).** **No compiler in chat.** Watch: color-space round
  trips (esp. OKLCH/LCH parse), popover open not registering a spurious undo (push
  only on user edit), swatch alpha checkerboard, and per-drag undo volume (known).

- **2026-06-10 — Session 31:** **Phase 7 — Inspector & input polish.** (1) Reusable
  `NumericStepping` view modifier: ↑/↓ ±1, ⇧ ±10, ⌥ ±0.1, hold-to-accelerate
  (grows every 5 repeats); attached to all numeric inspector fields + zoom %.
  (2) Inspector **layer rename** field (synced to Layers via the shared model);
  `dimensions()` title now optional. (3) **Zoom cluster** in the RightPanel —
  editable %, preset menu (Fit/Actual/25–400), log slider, ± buttons — plus View-
  menu shortcuts ⌘+/⌘-/⌘0 (Actual)/⌘1 (Fit). Centered-zoom math lives in
  `AppState.zoomTo` using `viewportSize` reported by `CanvasNSView.layout()`;
  canvas `zoomInAction`/`zoomOutAction`/`zoomActualAction` selectors. **No compiler
  in chat.** Watch: ⌘+ shortcut resolution, the `onKeyPress(phases:)` repeat
  acceleration, and that inspector zoom edits keep the view centered.

- **2026-06-10 — Session 30 (planning):** Organized the owner's big polish list
  into **Phases 7–16** (see "Polish roadmap" above). Order = value/effort: 7
  Inspector/input polish (universal stepping, inspector rename, zoom cluster) →
  8 Color & gradients (inline popover, HEX/RGB/HSL/LCH/OKLCH, gradients, artboard
  bg) → 9 Typography (font preview) → 10 Effects (shadows, opacity; blend modes
  lower-pri) → 11 Layout/align/guides → 12 Command-coverage & full menu bar →
  13 Workspace & dockable panels (LARGE; absorbed the old "V2 panels" + settings/
  saved views) → 14 Images (low-pri) → 15 Auto-layout/padding (BIG) → 16 Masks/
  outline-stroke/type-to-shapes (BIG). Folded the stray "Future styling" stub into
  8/9/10. No code this session — next: build, starting with Phase 7.

- **2026-06-10 — Session 29:** **Notes editor upgrade.** Replaced the single-field
  notes input with an `NSTextView`-backed `NotesEditor` (+ `NotesTextView`): real
  multi-line editing — Return inserts line breaks, Tab/Shift-Tab indent/outdent
  (4 spaces), and bullet lines (`•`, `-`, `*`) auto-continue on Return (an empty
  bullet ends the list); leading indentation carries to the next line. Editor
  auto-grows to fit (reports `usedRect` height up to a cap, then scrolls) and the
  panel still resizes via the grip. Storage stays a plain `String` so it's
  Markdown-ready. Panel **size now persists per board across close/open**
  (`AppState.notesPanelSize`, keyed by id). The PDF notes page already renders the
  newlines/tabs/bullets as literal text. **No compiler in chat.** Watch: NSTextView
  first-responder focus on open, content-height reporting loop (guarded by a 0.5pt
  threshold), and Tab being captured by the editor rather than moving focus.

- **2026-06-10 — Session 28:** **Notes fixes.** (1) Notes toggle button was "way
  off" + appeared to drift on zoom: the overlay's `ZStack` was being centered by
  the bare `.overlay`, so its (0,0) sat at the canvas center, not top-left. Wrapped
  the overlay in a `GeometryReader` (+ fill frame, + `.overlay(alignment:.topLeading)`)
  so content origin = canvas top-left; `doc*zoom+pan` now matches the canvas at all
  zooms. (2) Removed the second "Notes" starter artboard — `Document.starter` is now
  a single "Artboard 1" (393×852) at the origin; the initial fit centers it.

- **2026-06-10 — Session 27:** **Phase 6 — Structured notes & handoff.** Notes now
  live on `Artboard.notes` (backward-compatible decoder; memberwise init keeps the
  `notes:` default) so they move/duplicate/delete with the board automatically.
  New **`ArtboardNotesOverlay`** (SwiftUI, layered over the canvas via `.overlay`,
  positioned with the same `docPoint*zoom+pan` transform): a small toggle button
  sits just left of each board's name label — **muted when empty, accent-bordered
  when it has content** (no notification badge) — and opens an editable panel that
  **expands down-and-to-the-left** (off the board), is **manually resizable** (a
  bottom-left grip) and **auto-grows** with the text (`TextField(axis:.vertical)`).
  Open/closed state is ephemeral (`AppState.openNotesArtboardIDs`); panel size is
  local `@State` keyed by board id. Export gained an **"Include notes"** checkbox
  (PDF only, both panels): renders a Letter "Notes — <board>" page after each board
  that has notes, merged via PDFKit (`NotesRenderView`, `notesPDFData`,
  `pdfData(includeNotes:)`, `multiPagePDFData(includeNotes:)`). **No compiler in
  chat.** Watch: (1) **overlay hit-testing pass-through** — confirm clicks in empty
  overlay areas still reach the canvas (top risk); (2) notes button/panel position
  tracking pan/zoom; (3) the resize grip base-size capture; (4) notes edits are
  per-keystroke undo (known, matches other text fields).

- **2026-06-10 — Session 26:** **Artboard refinements.** (1) **Rename** boards:
  Inspector name field, double-click label → inline `NSTextField` editor (commits
  on Return / focus loss), right-click ▸ Rename. (2) **Marquee fully enclosing**
  boards selects the boards (partial still selects items). (3) **Rearrange mode**:
  with 2+ boards selected, dragging inside any selected board moves the whole set
  + contents (gated to the select tool). (4) **Copy/paste artboards** via ⌘C/⌘V +
  context menu (boards + owned shapes, new ids); richer clipboard (`NodeClipboard`
  / `ArtboardClipboard`). (5) **Artboard-aware shape paste**: shapes paste onto the
  focused board at the same position relative to it, or centered when they don't
  fit. validateMenuItem + context menu updated for boards. **No compiler in chat.**
  Watch: inline-rename field commit/focus timing, paste reposition math (fit vs
  center), copy branch (boards-vs-nodes selection), and the rearrange-drag gate.

- **2026-06-10 — Session 25:** **Export options + Phase 5.5 artboard improvements.**
  Export round 2: format **popup** in the Save panel for a single board, and the
  all-artboards folder panel got a **format popup (PNG/PDF/SVG/All) + "Combine PDF
  pages into one file"** checkbox; multi-page PDF merges per-board single-page PDFs
  via **PDFKit** (`ExportPanels.swift`, `ExportRenderer.multiPagePDFData`). Then a
  cohesive artboard batch: (1) **size presets** (split New-Artboard menu, `Artboard
  Preset`); (2) **artboard resize** (8 handles, Shift = proportional; frame-only,
  wall re-derives ownership); (3) **multi-select boards** (`AppState.selected
  ArtboardIDs` Set + single-select wrapper; Shift-click labels; outline + Inspector
  count); (4) **multi-move** (drag/arrows/delete act on all selected boards + their
  owned shapes, Shift axis-lock); (5) **Option-drag duplicates** boards + contents
  (one undo). **Export Selected** now does 1 board → save panel, 2+ → folder+format
  +combine. **Notes feature deferred to Phase 6** with a full design spec recorded
  above (notes live on the Artboard, a left-of-name toggle button, expand down-left,
  auto-grow, "include notes" on export). **No compiler in chat.** Watch: the
  `selectedArtboardID` compatibility wrapper at the ~25 call sites, artboard handle
  hit/resize math, option-duplicate undo (restores baseline = removes copies), and
  the export-panel accessory enabling/disabling the combine checkbox.

- **2026-06-03 — Session 24:** **Pen/path refinements.** (1) Layers **Rename**
  now focuses + select-all (type to replace; Esc cancels) via `@FocusState` +
  `selectAll:` to the field editor. (2) **Pen adds points to existing geometry**:
  with no active pen path, clicking an existing path/shape/line inserts a corner
  anchor on the nearest segment (basic shapes auto-convert to a path first); the
  cursor shows the "+" (dragCopy) badge when hovering addable geometry. Once a
  path is in progress, clicks continue it as before. (3) Right-click an anchor →
  **Make Curved / Make Corner** (adds symmetric tangent handles or strips them).
  (4) **Bounding box rework**: selected paths now trace their actual outline (no
  misleading square); box shapes' outline is gated behind `AppState.showSelection
  Bounds`, toggled via **View ▸ Toggle Selection Bounds (⇧⌘B)** (a Settings panel
  will own it later). **No compiler in chat.** Watch: rename select-all timing,
  pen add-point insert index, and the anchor right-click menu. **Owner: build &
  report.** Next: **Phase 5 — Export.**

- **2026-06-03 — Session 23:** **Vector paths + Pen tool (build 2 of the batch).**
  New `NodeContent.path(PathShape)` — anchors (`PathPoint`: point + optional
  bezier `controlIn`/`controlOut`, nil = corner), `closed`, fill/stroke/width;
  anchors stored LOCAL like LineShape, frame = anchor bbox (`normalizePath`
  re-bases, absolute-invariant). **Pen tool** (P): click = corner, click-drag =
  symmetric handles in one motion, click first anchor (≥2 pts) = close; the path
  builds live in the model, Return/Esc/tool-switch finishes (one undo). **Edit
  Points** tool (A, direct-selection): drag anchors (handles follow) + bezier
  handles; anchor/handle overlay drawn for the selected path (and the in-progress
  pen path). **Convert to Path** (right-click) turns rect→4 corners, ellipse→4
  kappa-bezier anchors, line→2 anchors. Path rendering via NSBezierPath (cubic;
  missing handle = straight). Inspector: path fill (when closed), stroke
  color/width, closed toggle. Path hit-testing = point-in-polygon (closed) or
  distance-to-polyline (open). **HUGE unverified batch — no compiler in chat.**
  Likely snag spots: pen handle math / normalize, the new `DragMode` cases
  (`penHandle`/`pathPoint`), exhaustive `NodeContent` switches, and the
  `RightPanel` same-file `private` access in the path-controls extension.
  **Owner: build & report** — and this is the last thing before **Phase 5 —
  Export**. Deferred: add/remove anchors, line stroke in overrides.

- **2026-06-03 — Session 22:** **Shape styling (build 1 of the styling+vector
  batch).** Rectangle/ellipse gained **stroke** (`stroke` + `strokeWidth`, where
  0 = no stroke) — rendered (fill then stroke on the same path) and editable in
  the Inspector; rect **corner radius** now has a field; **fill color pickers**
  added for rect/ellipse. One shared `updateShape` path edits fill/stroke/width
  for both via a tiny `ShapeStyle` helper. Added **backward-compatible decoders**
  for RectangleShape/EllipseShape (decodeIfPresent) so files made since the last
  format change still open. Owner asked for the whole styling+vector list "in one
  pass," but with no compiler in chat I'm shipping it in TWO back-to-back builds
  to keep it debuggable: **this build = styling**; **next build = Pen tool +
  editable Path + point editing + Convert to Path + path inspector**, then Phase
  5 (export). **Owner: build & report.**

- **2026-06-03 — Session 21:** **Bounded overrides → Phase 4 COMPLETE.**
  Per-instance **text + color overrides** (`InstanceOverride`, was already in the
  model). Added `ComponentInstance.applyingOverrides(to:)` + `textOverride`/
  `fillOverride` helpers; rendering and Detach now bake overrides in. **Inspector
  UI:** select an instance → an "Overrides" section lists the source's text
  layers (editable multi-line text fields) and rect/ellipse layers (color
  pickers), each with a reset-to-source button (drops the override → re-inherits).
  Overrides target top-level source layers for now (nested layers + line stroke =
  later). So components now do real variations: same source, different copy/colors
  per instance, plus per-instance layer visibility. **Phase 4 done; next is Phase
  5 — Export (PNG/PDF/SVG).** **Owner: build & report.** Watch: ColorPicker ⇄
  RGBAColor round-trip and the text-field override binding.

- **2026-06-03 — Session 20:** **Per-instance visibility is now a true override.**
  The old `hiddenLayerIDs` (could only hide, gated by the source's `isVisible`)
  is replaced by `ComponentInstance.layerVisibility: [LayerVisibilityOverride]`
  ({layerID, isVisible}). Effective visibility = the override if present, else
  the source layer's own `isVisible` — so an instance can **show a layer that's
  hidden in the source** and vice-versa. Toggling that matches the source default
  drops the override (re-inherits, follows future source edits). Render, the
  panel rows, and detach all use `inst.isLayerVisible(_:sourceDefault:)`.
  **HEADS-UP: old `.exp` files with component instances that had `hiddenLayerIDs`
  won't decode** (field renamed) — make fresh ones. **Owner: build & report.**
  **Phase 4 remaining: bounded text/color overrides.**

- **2026-06-03 — Session 19:** **Layers tree (expand/collapse) + Group menu fix +
  visibility-sync bug.** (1) Fixed the per-instance row eye icon: now reflects
  EFFECTIVE visibility (`!child.isVisible || hiddenLayerIDs.contains`), so a
  source layer hidden by default reads as hidden on the instance too. (2)
  **Expand/collapse** in the Layers panel via a recursive `LayerOutlineRow` +
  `DisclosureGroup`: group rows reveal their children; instance rows reveal the
  source's layers with the per-instance eye toggles (replaces the old
  on-selection "Component ·" section — now inline). Edits recurse the tree
  (`updateNodeTree`/`findNode`) so nested group layers toggle/rename correctly.
  Nested drag-reorder still deferred (top-level reorder unchanged). (3) **⌘G /
  ⇧⌘G now actually group/ungroup** — the problem was ⌘G = system "Find Next"
  eating the key before the canvas. Added an **Arrange menu** (App `.commands`)
  that routes ⌘G/⇧⌘G (+ bring/send order, Create/Detach Component) through the
  responder chain via `NSApp.sendAction`, and removed the text-find command group.
  **No compiler in chat — sizable Layers rewrite + new menu.** Watch: DisclosureGroup
  inside List(selection:)+onMove behavior, and whether ⌘G now triggers Group
  (vs Find). **Owner: build & report.** **Phase 4 remaining: bounded overrides.**

- **2026-06-03 — Session 18:** **Reorder shortcuts + per-instance visibility.**
  Wired ⌘[ / ⌘] (send backward / bring forward, one step, keeps multi-selection
  grouped) and ⇧⌘[ / ⇧⌘] (to back / to front); added Bring Forward / Send
  Backward to the right-click menu. **Per-instance layer visibility** (Phase 4
  box ✓): select a single instance and the Layers panel shows a "Component ·
  <name>" section listing the source's layers, each with an eye toggle that
  writes THIS instance's `hiddenLayerIDs` — hide a layer in one instance without
  touching the source or other instances; reflected live in render. Rows are
  non-selectable (`.selectionDisabled`). Only top-level source layers for now.
  **Phase 4 remaining: bounded overrides (text/color).** **Owner: build &
  report.**

- **2026-06-03 — Session 17:** **Fixed Layers drag "dead spots" + clunky
  selection.** Root cause: the custom per-row `.onTapGesture(count:1/2)` (our
  hand-rolled select + double-click rename) was fighting the List's drag-reorder,
  so dragging from over a row's text didn't initiate and rename felt off.
  Switched the Layers list to **native `List(selection:)`** (crisp click,
  Shift-range, ⌘-toggle, and drag-from-anywhere reorder all free) and moved
  **Rename to the row's right-click context menu**. Removed the custom
  `handleClick`/anchor selection path. Net: smoother reorder + selection. Trades:
  toggle is ⌘-click (was Option), rename is right-click → Rename (was
  double-click) — easy to revisit. Selection still two-way with the canvas via
  AppState. **Owner: build & report.** **Next:** per-instance visibility +
  overrides, and the ⌘[ / ⌘] reorder shortcuts.

- **2026-06-03 — Session 16:** **Detach Component** (the inverse of Create).
  ⇧⌘K or right-click → Detach Component replaces selected instance(s) with fresh,
  independent copies of the source's children at the instance's position; the
  source stays in the library for any other instances. Per-instance hidden
  layers carry over (copy `isVisible = false`). Works in both windows (scoped via
  `currentNodes`/`commitNodes`). NB: overrides aren't baked in on detach yet,
  since overrides aren't applied in rendering yet — revisit when overrides land.
  **Owner: build & report.** **Next:** per-instance visibility toggles +
  overrides.

- **2026-06-03 — Session 15:** **Source editor gets a Layers panel + window
  polish.** Generalized `LayersPanel` with a `scope`: in `.source` it shows a
  single flat group of the source's children (show/hide, lock, double-click
  rename, drag-reorder, selection synced to that window's AppState); `.document`
  unchanged. Added it to the source-editor window (tools · layers · canvas) and
  made the window layout fill (maxWidth/Height ∞, min 560×320) so the canvas
  pans/zooms like the main one rather than feeling pinned. The canvas pan/zoom
  is the same code as the main window (two-finger scroll both axes, pinch,
  space-drag, ⌘±, ⌘0 fit). **Backlog added:** (1) layer-reorder refinement +
  shortcuts ⌘[ / ⌘] (down/up) and ⇧⌘[ / ⇧⌘] (to back/front); (2) confirm
  horizontal-pan parity in the source window (owner saw vertical-only — if it
  persists it's likely the NSHostingController scroll path, to investigate).
  **No compiler in chat.** **Owner: build & report** — especially whether the
  source window now pans both axes and the Layers panel feels useful. **Next:**
  per-instance visibility toggles + bounded overrides (the variations/states
  groundwork), then the reorder shortcuts.

- **2026-06-03 — Session 14:** **Components round 2 — the source editor edits for
  real.** Big architectural move: the canvas is now **scope-parameterized**
  (`CanvasScope = .document | .source(UUID)`). All node access goes through
  `currentNodes` / `withNodes` / `commitNodes`, so the SAME `CanvasNSView` drives
  both the main window (document's top-level nodes + artboards) and the source
  editor (a source's `children`). Artboards/wall-clipping apply only in document
  scope; source scope draws a white source-bounds frame and fits to the source
  size. **Model:** `ComponentSource` now holds `{ size, children }` directly
  (was a `root` group node) — much cleaner for scoped editing. The source-editor
  window now hosts a live `CanvasView(scope:.source)` + its own ToolsStrip +
  own AppState; it shares the document's UndoManager via a window delegate
  (`windowWillReturnUndoManager`) so ⌘Z + Save behave. Edit a source → all
  instances update live (both windows observe the one document). **Deferred to
  next round:** an Inspector inside the source window (so stroke/font/color edits
  work there — currently only via canvas gestures + inline text), source-bounds
  auto-grow, then per-instance visibility toggles + overrides. **HEADS-UP: old
  `.exp` files with saved components won't open** (ComponentSource shape changed;
  fresh files fine). **No compiler in chat — large refactor (~25 call sites
  rescoped).** Watch: source-scope edits writing to the right array, undo across
  the two windows, and instance live-update. **Owner: build & report.**

- **2026-06-03 — Session 13:** **Phase 4 begins — components round 1.**
  **Create Component** (⌘K + right-click): wraps the selection into a
  `ComponentSource` (root group, children stored source-local) and drops an
  `.instance` node where the selection was. **Instances render** by resolving the
  source and drawing its root recursively at the instance's origin (honors
  `hiddenLayerIDs`); duplicate / copy-paste yields more true instances of the one
  source (clone keeps `sourceID`). Instances move/select like any node; box-resize
  is gated off for them (move-only) for now. **Source-editor window scaffolded**
  (`UI/SourceEditorWindow.swift`): double-click an instance (or right-click →
  Edit Component) opens a SEPARATE, movable, resizable NSWindow that shares the
  same ExpDocument, with a placeholder tools column + a live read-only SwiftUI
  `Canvas` preview of the source. It's AppKit-windowed (not a SwiftUI Window
  scene) specifically so it can share the document object → future edits will
  propagate to all instances and share undo. **Round 2:** wire real editing
  inside that window (its own canvas + tools), which needs the main canvas
  generalized to operate on an arbitrary node list (a source's children). Round
  3+: per-instance visibility toggles + bounded overrides (model already carries
  `hiddenLayerIDs` + `overrides`). **No compiler in chat.** Watch: the auxiliary
  NSWindow lifecycle (retained in `SourceEditorWindowManager`), instance render
  offset math, and clone preserving `sourceID`. **Owner: build & report.**

- **2026-06-03 — Session 12:** **Line tool + grouping.** Added
  `NodeContent.line(LineShape)` (endpoints stored node-local, frame kept as the
  tight bbox so moving moves the line; min-1pt so it can still be owned/clipped).
  **Line tool** (L): drag to draw, bare click = default 100pt line; renders as a
  stroked segment (round caps) clipped to its owner; hit-tested by distance to
  the segment; single-line selection shows **2 endpoint handles** to edit each
  end (re-bbox on drag); Inspector gets stroke **width** + **color**.
  **Group/ungroup:** ⌘G groups selected top-level nodes (children → group-local,
  frame = union), ⇧⌘G ungroups (children → doc coords, in place); both in the
  right-click menu with validation. Groups render via **recursive drawNode with
  an offset**, select/move/clip as a single unit, and hit-test only when over a
  child's real geometry. `nodeHit` recurses; box resize handles now gated to
  rect/ellipse/text only (lines use endpoint handles, groups none yet). This
  finishes the Phase 3 primitives box; pen/bézier path is explicitly a later
  subsystem. **Deferred:** nested group rows in the Layers panel, group
  box-resize. **No compiler in chat — biggish batch.** Watch: line endpoint
  drag math + bbox normalization, group/ungroup coordinate round-trips, and
  recursive group rendering offsets. **Owner: build & report.** **Next: Phase 4
  — components** (the reference-based subsystem).

- **2026-06-03 — Session 11:** **Text tool.** New `Tool.text` (T shortcut,
  i-beam cursor) in the tools strip. Click with the Text tool places a text node
  and immediately enters **inline editing** via an `NSTextView` overlay
  positioned over the node (transparent, matches font/color) — real cursor,
  selection, IME. Double-click an existing text shape to re-edit. Commit on
  click-away / scroll / zoom (one undo step: "Add Text" / "Edit Text");
  a brand-new node left empty is silently dropped. The node being edited is
  skipped in the canvas draw so only the overlay shows. On commit the box
  auto-measures to fit the text. **Inspector** (single text shape): editable
  text string, font **Size**, and **Color** (SwiftUI `ColorPicker` ⇄ `RGBAColor`
  via an sRGB bridge in the UI layer); size/string changes re-measure the box.
  Also logged the Layers Shift-click "clunky" feel in a new Refinement backlog.
  **No compiler in chat.** Watch: `NSTextView` overlay focus/commit cycle
  (delegate `textDidEndEditing` + the re-entrancy guard), and text rendering vs
  the editor's font at non-100% zoom. **Owner: build & report.** **Next:**
  line/path tool + group/ungroup, then **Phase 4 — components**.

- **2026-06-03 — Session 10:** **Layers panel** (`UI/LayersPanel.swift`), replaced
  the LeftPanel placeholder. A grouped `List`: one section per artboard (shapes it
  geometrically owns) plus a "Wall" section, **front-of-stack at top**. Each row
  has eye (visibility) + lock toggles, a type icon, and **double-click to
  rename**. **Drag-to-reorder** within a group, translated back to the document's
  global back-to-front z-order so other groups stay put. **Selection is two-way
  bound** to `app.selectedNodeIDs` — select in the panel ⇄ select on the canvas.
  Every edit (show/hide, lock, rename, reorder) is one undo step. Locked shapes
  already skip canvas hit-testing; hidden shapes already skip drawing, so both
  toggles "just work." **Still pending for the box:** group/ungroup folders.
  **No compiler in chat.** Watch: `List` multi-select + `.onMove` behavior on
  macOS, and double-click rename vs row selection. **Owner: build & report.**
  **Next:** Phase 3 remainder — text + line tools (and group/ungroup), then
  Phase 4 (components).

- **2026-06-03 — Session 9:** **The "wall" + geometric membership.** Shapes can
  now live outside artboards, on the canvas backdrop ("wall"). **Model refactor
  (formatVersion → 2):** shapes moved out of `Artboard.layers` into a single
  document-coordinate list `Document.nodes`; `Artboard` is now just id/name/
  frame. Ownership is **derived, not stored**: `Document.owningArtboard(of:)`
  returns the artboard covering >50% of a shape (else nil = wall). Rendering
  clips each shape to its live owner, so a shape **crops the instant >half of it
  crosses into a frame** and un-crops when it leaves — the snap-to-frame behavior
  you wanted (vs Figma). Dragging an artboard by its label carries the shapes it
  currently owns (drag + keyboard-nudge). You can now also **draw shapes on the
  wall**. Inspector shows X/Y **artboard-relative when a shape is owned**, else
  document coords; editing converts back. All prior interactions (multi-select,
  marquee, copy/paste, duplicate, option-drag, shift-constraints, resize, menu)
  rebuilt onto the single list. **HEADS-UP: old `.exp` test files won't open**
  (format changed; make fresh ones). **No compiler in chat** — large refactor,
  watch for any missed coordinate conversions. **Owner: build & report.**
  **Next: finish Phase 3** — line/path + text tools, then the Layers panel.

- **2026-06-03 — Session 8:** **Big interaction-polish batch (one cycle).**
  Selection is now **multi**: `AppState.selectedNodeIDs: Set<UUID>` (+
  `singleSelectedNodeID` convenience). Added **shift-click** to add/remove from
  selection and **marquee drag-select** on empty space (Shift = add). Move,
  nudge, delete, and the halos all act on the whole selection; resize handles
  show only for a single shape. **Clipboard:** responder `copy/cut/paste/delete`
  (so the standard Edit menu + ⌘C/X/V/⌫ work) via a custom pasteboard type
  (nodes as JSON, fresh UUIDs on paste, +10/+10 offset). **⌘D duplicate** and
  **Option-drag duplicate** (clone in place, drag the copy). **Shift
  constraints:** axis-locked move + aspect-preserving resize (anchored at the
  opposite corner/edge). **Cursors:** crosshair for shape tools, hand for
  space-pan, dragCopy when Option-hovering a shape, resize cursors over edge
  handles. **Inspector:** ↑/↓ bump a field by 1 (Shift = 10) to match the
  canvas; multi-selection shows a count. **Right-click menu skeleton**
  (`menu(for:)`): on a shape → Cut/Copy/Duplicate/Delete/Bring-to-Front/
  Send-to-Back; empty artboard → Paste/Select All; backdrop → Paste/Fit; with
  `validateMenuItem` enable/disable. Z-order (front/back) actually works now.
  **Behavior change you'll notice:** artboards now move by **dragging their name
  label** (dragging an artboard's empty interior starts a marquee instead).
  Did NOT add constrained draw (you opted out). **This is the largest unverified
  batch yet — no compiler in chat.** Likely snag spots: responder-action
  selectors (`selectAll(_:)` etc.) under the MainActor-default setting,
  `.onKeyPress` on the TextField, and the marquee/duplicate edge cases.
  **Owner: build & report** — paste any errors. **Next: finish Phase 3** —
  line/path + text tools, then the Layers panel.

- **2026-06-03 — Session 7:** **Inspector is now two-way.** X/Y/W/H are editable
  `TextField`s bound to the selected shape (or artboard); committing a value
  (Return / focus-out) writes back through `ExpDocument.setModel`, so the canvas
  moves/resizes and it's one undo step. Width/height clamped to ≥1pt; positions
  may be negative. Read path unchanged (fields still reflect drag/resize live).
  Built a small reusable `DimField`. **Owner: build & report.** Watch: does
  editing W/H resize from the top-left anchor as expected; does committing feel
  right (Return/Tab/click-away). **Couldn't compile here.** **Next: finish
  Phase 3** — line/path + text tools, then the Layers panel.

- **2026-06-03 — Session 6:** **Phase 3 underway — it draws now.** Added a fixed
  left **tools strip** (`UI/ToolsStrip.swift`) with Select / Rectangle / Ellipse
  (shortcuts V / R / O, Esc → Select), pinned outside the HSplitView per the
  v2 layout plan. AppState gained `tool` + `selectedNodeID` (both view state).
  Rewrote `Canvas/CanvasView.swift` around a single `DragMode` enum so exactly
  one thing happens per gesture: **draw** (drag a rect/ellipse into the artboard
  under the cursor; bare click = default 100×100; tool snaps back to Select after
  one shape), **move** (drag a selected shape), **resize** (8 handles, normalized
  so dragging past the far edge flips rather than going negative), plus the
  existing artboard move/select. Shapes render clipped to their artboard, in
  artboard-local coords; selection chrome (accent outline + handles) draws on top
  in view space so it's a constant size at any zoom. Every gesture is one undo
  step. Arrow-nudge + Delete now act on the selected shape if there is one, else
  the artboard. Inspector shows the selected shape's name + X/Y/W/H (artboard-
  relative). Added a `RGBAColor → NSColor` bridge in the UI layer (model stays
  UI-free). New default shapes are light grey so they read on the white artboard.
  **Couldn't compile here (no Swift toolchain) — careful hand-review.** Watch:
  hit-testing/selection feel, resize handle grab size, draw-into-artboard
  behavior when starting outside an artboard (currently ignored). **Owner:
  build & report.** **Next:** finish Phase 3 — line/path + text tools, then the
  **Layers panel** (order, visibility, lock, groups).

- **2026-06-03 — Session 5 (fix):** Save failed at runtime with "unable to save
  using this document type" — the exported `.exp` UTI wasn't registered because
  the `Info.plist` wasn't wired into the build (I'd left that as an optional
  manual step). Fixed directly: added `INFOPLIST_FILE = "Info.plist"` to both
  build configs (Info.plist lives at the project root, beside the .xcodeproj,
  kept out of the synchronized source folder so it isn't double-copied as a
  resource). Note: the build itself compiled fine — the MainActor-default vs
  ReferenceFileDocument concurrency worry did NOT materialize. `FileWrapper`
  initializer corrected to `regularFileWithContents:` during the build loop.
  After a clean build, Save/Open `.exp` should work and Finder should associate
  the type.

- **2026-06-03 — Session 5:** **Phase 2 COMPLETE — the document system.** Added
  `Model/ExpDocument.swift`, a `ReferenceFileDocument` wrapping `Document`;
  read/write is just `Document` ⇄ pretty-printed JSON (`.exp`). App scene is now
  a `DocumentGroup`, so New / Open / Save / Duplicate / Rename / Revert and
  multi-window all come for free. **Architecture shift:** the design data now
  lives in `ExpDocument.model` (the file); `AppState` was slimmed to pure view
  state (camera, selection, panel layout — none saved). The canvas takes both;
  all artboard edits route through `ExpDocument.setModel`, an undo-aware funnel
  that powers ⌘Z and (crucially for ReferenceFileDocument) marks the doc dirty
  so Save actually fires. Drag = one undo step; nudge/create/delete each
  register. **Project changes I made directly:** flipped the sandbox setting
  `ENABLE_USER_SELECTED_FILES` to `readwrite` (Debug+Release) — required or Save
  fails under the sandbox.
  **TWO MANUAL STEPS for you (optional, for Finder `.exp` association):**
    1. Target → Build Settings → search "Info.plist File" (`INFOPLIST_FILE`) →
       set to `Info.plist` (it's at the project root, beside the .xcodeproj).
    2. Leave "Generate Info.plist File" = Yes; Xcode merges. Then a clean build
       registers the `.exp` type with Finder.
  Skipping these is fine — New/Open/Save still work in-app without them.
  **Likely first-build snag to watch:** the project sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so `ExpDocument` is MainActor by
  default; if `ReferenceFileDocument` conformance complains about isolation on
  `snapshot`/`fileWrapper`/`init(configuration:)`, paste the exact error and
  I'll add the right `nonisolated` annotations. (Couldn't compile here — no
  Swift toolchain in chat.) **Owner: build & report.** **Next: Phase 3 —
  primitives & layers** (draw rectangle/ellipse/line/text inside artboards,
  selection/move/resize of nodes, the Layers panel).

- **2026-06-03 — Session 4:** **Phase 2 — document model (2 of 3 boxes).** Built
  the real model in `Model/Document.swift`: `Document → Artboards → Layers →
  Nodes`, all value-type + `Codable` + UI-free (imports only Foundation/
  CoreGraphics, so it can render, export, or be tested headless). It's
  **reference-based from day one** — a `Node` can be `.instance(ComponentInstance)`
  holding a `sourceID` (+ bounded `overrides` + per-layer `hiddenLayerIDs`)
  pointing at a document-level `ComponentSource`; instances reference, never
  copy. Added `RGBAColor` (Codable color → also makes SVG/CSS export trivial
  later). **Migration:** split persisted data from session state — `Document`
  is the file, `AppState` keeps camera/selection/panel layout (which won't be
  saved). Moved `Artboard` into the model (now carries `layers: [Node]`),
  repointed all canvas rendering/hit-testing/move/nudge/create/delete at
  `app.document.artboards`. Rendering behavior is unchanged (artboards still
  draw as frames; node drawing is Phase 3), so this was a low-risk swap of the
  data layer underneath. No disk I/O yet — but the model is Codable-ready and
  the file approach is **locked to native DocumentGroup + ReferenceFileDocument
  (JSON `.exp`)**. NB: couldn't compile here (no Swift toolchain in chat), so
  this is a careful hand-review — watch the build for Codable synthesis on the
  `NodeContent`/`InstanceOverride.Value` enums and CG-geometry Codable.
  **Owner: build & report.** **Next:** finish Phase 2 — adopt DocumentGroup /
  ReferenceFileDocument so New/Open/Save work; then Phase 3 primitives & layers.

- **2026-06-03 — Session 3 (cont.):** **Phase 1 complete.** Closed the two
  remaining boxes. Added the camera *inverse* transform (`viewToDoc`) and
  artboard **hit-testing**; click selects the artboard under the cursor (accent
  halo, respects system accent + increase-contrast), clicking empty space
  deselects. **Move:** drag a selected artboard (tracks cursor 1:1 in doc space
  at any zoom); arrow keys nudge 1pt, Shift+arrow 10pt. **Create/delete:** New
  Artboard toolbar button (⇧⌘N) adds one to the right of existing content;
  Delete/⌫ removes the selected one. **Tab / ⇧Tab** cycle selection (keyboard-only
  canvas navigation). Selection lives in AppState; the Inspector now shows the
  selected artboard's name + X/Y/W/H, proving selection round-trips AppKit→state→
  SwiftUI. Accessibility: full keyboard operability for select/move/create/delete,
  semantic + accent colors throughout. **Owner: build & report.** Watch for:
  ⇧⌘N not firing if the canvas isn't first responder; drag feel; whether Tab
  steals focus anywhere. **Next: Phase 2 — the document model** (Document →
  Artboards → Layers → Nodes, reference-based for components, instant-open file
  format).

- **2026-06-03 — Session 3:** Started Phase 1 (the canvas). Built the founding
  shared **AppState** (`Model/AppState.swift`) as an `@Observable @MainActor`
  class holding panel visibility, the camera (`zoom` + `panOffset`), and a
  minimal `Artboard` model — the single source of truth panels read/write,
  which both the v2 floating-panel plan and the component system need.
  Replaced the placeholder canvas with a real **AppKit-backed `NSView`**
  (`Canvas/CanvasView.swift`) wrapped in `NSViewRepresentable`, drawing
  artboards via Core Graphics. Full macOS-native **pan/zoom**: trackpad
  two-finger scroll pans, pinch zooms (toward cursor), space-bar+drag = hand
  tool, ⌘+ / ⌘− zoom, ⌘0 fits content. Artboards drawn in view space so the
  shadow + 1px border stay crisp at any zoom; artboard stays white per the
  locked exception. MainWindow now owns AppState via `@State` and injects it
  with `.environment`; the Inspector shows a live zoom % to prove the
  AppKit→AppState→SwiftUI round-trip. Semantic colors throughout (light/dark +
  increase-contrast); VoiceOver label on the canvas; keyboard-operable zoom.
  **Owner: build & report.** Watch for: pan direction feel (scroll sign),
  pinch sensitivity, whether ⌘+/-/0 fight any menu shortcuts. **Next:** finish
  Phase 1 — artboard *create* UI + mouse hit-testing/selection (Phase 3 overlap),
  then Phase 2 document model.

- **(date) — Session 2:** Phase 0 complete — three-pane editor shell runs
  (HSplitView, toolbar panel toggles, placeholder artboard). Confirmed Xcode
  26.3 / Swift 6.2. Added two founding notes: (1) follow system light/dark via
  semantic colors, artboard stays white on purpose; (2) FLOATING/DETACHABLE
  panels for multi-monitor as a locked principle — v1 keeps docked layout but
  every panel is written self-contained & state-driven so v2 can pop them into
  their own windows without a rewrite. Next step: Phase 1 — set up shared
  app-state object, then build the real AppKit-backed canvas with smooth
  pan/zoom.

- **(date) — Session 1:** Scoped v1, locked architecture decisions, created
  this roadmap. Next step: Phase 0 — stand up the Xcode project and get an
  empty window running, confirm Swift/Xcode versions.
