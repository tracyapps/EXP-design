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

## v1.6.1 — released (2026-07-21)

Build 9, `MARKETING_VERSION 1.6.1`. Close confirmed defects after v1.6, led by
the long-standing rich-text commit bug, plus the small owner-approved vector
workflow additions needed to make custom cursors directly in EXP.

Public release completed 2026-07-21: Direct Distribution, notarization,
stapling, final signature/entitlement verification, exact Sparkle archive and
appcast, GitHub release, and website publication are complete. v1.6.1 is the
one-time manual-install updater baseline; the first automatic install/relaunch
proof remains a gate for the next published build.

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
- [x] **OWNER DISTRIBUTION VERIFY:** Direct Distribution repeated those checks
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
- [x] **External distribution:** Direct Distribution, notarize, staple, verify the signed
      app's entitlements/signatures, create the exact Sparkle zip/appcast, publish
      the GitHub release and website. COMPLETED 2026-07-21.
- [x] **Updater baseline:** manually install public v1.6.1, confirm About shows
      1.6.1/build 9, run `scripts/verify_installed_update_baseline.sh`, and preserve
      that installed copy for v2.0's prompt → install → relaunch proof. OWNER
      VERIFIED 2026-07-21: removed post-install `com.apple.FinderInfo` metadata;
      strict deep signature validation and Gatekeeper's Notarized Developer ID
      assessment pass; script reports “Installed update baseline is clean.”

---

## v2.0 — released (2026-07-22)

Interop & Handoff, build 10. Planning record: `docs/V2-INTEROP-PLAN.md`.

Owner-set focus (2026-07-14): make EXP the design tool that lets go — hand
work to dev teams, LLM agents, IDEs, or CodePen, and read work back in.
Export/handoff is the spine (decided 2026-07-14); notes + ARIA roles travel
with the design. Full chunk breakdown, risks, and release mapping live in
**docs/V2-INTEROP-PLAN.md**. Summary:

- [x] **SVG import stabilization — stylesheet class colors:** SVGs that store
      presentation data in `<style>` rules (for example Illustrator-style
      `.cls-N { fill: … }`) now resolve simple element/id/class selectors with
      correct presentation-attribute → stylesheet specificity/source-order →
      inline-style precedence. The shared resolution also covers strokes,
      opacity, fonts, gradient stops, and class-applied filters. Headless proof:
      `1813-bowtie.svg` imports as 418 native nodes with all 133 distinct source
      colors preserved; a focused cascade fixture also passes.
- [x] **OWNER VERIFIED 2026-07-21 — SVG class colors:** rebuilt and re-imported
      `1813-bowtie.svg`; its colored native layers now visually match the source
      rather than importing as black. Owner reports the issue is fully fixed.
- [x] **Chunk A — Schema + Handoff Package** (documented/versioned design.json
      schema, package writer, manifest, README.llm.md) — v1.5
- [x] **Chunk C — W3C DTCG design-tokens import/export** (Design Language ↔
      tokens.json, standard stable 2025.10) — v1.5
- [x] **Chunk B — Semantic HTML/CSS export** (ARIA roles → real elements,
      tokens → custom properties, notes → comments; the v2.0 headline demo).
      Include the same bridge in standalone SVG export: when a fill/stroke exactly
      matches a Design Language color, emit/use its CSS custom property while
      retaining a standalone-safe fallback. Do not lose token identity during the
      broader import/export codec work.
  - [x] **B0 — Contract + golden fixture:** document the deterministic role →
        element mapping, DOM-id/data-exp-id rules, escaping, artboard ownership,
        and fidelity fallbacks; add one representative export fixture that covers
        notes, tokens, free-positioned layers, auto-layout, a categorized component,
        a state, and an ARIA relationship. DONE 2026-07-21: added the written
        semantic contract, executable mappings/identity/escaping helpers, and a
        headless fixture verifier covering all 40 curated roles, duplicate-safe
        instance IDs, selectors, hostile-text escaping, and document round-trip.
  - [x] **B1 — First vertical package slice:** extend the existing
        `HandoffPackageWriter` to add `html/styles.css` plus one HTML file per
        artboard, list/hash those files in `manifest.json`, and orient readers to
        them in `README.llm.md`. Start with an honest absolute-position baseline;
        every emitted layer keeps its stable `data-exp-id` reference. DONE
        2026-07-21: packages now include deterministic standalone artboard pages
        and shared CSS, resolved component visuals with instance-qualified ids,
        safe notes/strings, addressable hidden layers, reading-order rules, and
        explicit wall-node omission counts. The golden package verifier checks
        every entry's byte count and SHA-256 digest.
  - [x] **B2 — Semantic component contract:** resolve instances and their active
        state; emit role-appropriate elements/ARIA, accessible names, typed
        relationships, conventional pseudo-classes, and custom `data-state`
        selectors. Do not generate or store JavaScript. DONE 2026-07-21: native
        and explicit-ARIA hosts, instance-qualified accessible names and typed
        relationships, conventional/disabled/custom state selectors, active
        state attributes, and structured missing-data requirements now ship in
        the Handoff Package. No scripts or inline event handlers are generated.
  - [x] **B3 — Layout + Design Language fidelity:** map auto-layout groups to
        flexbox, type styles to classes, exact matching paints to CSS custom
        properties with standalone fallbacks, and carry the same token identity
        into standalone SVG export. DONE 2026-07-22: managed stacks now emit
        flex direction/distribution/gap/alignment and fixed flex items; exact
        paints/type styles reuse deterministic Design Language CSS identities;
        and standalone SVG fill/stroke attributes use the identical color-token
        lookup with literal fallbacks and alpha applied exactly once.
  - [x] **B4 — Semantic closure + accessibility/fidelity verification:** close
        the content-level semantic gaps exposed by the first real exports, then
        validate generated markup, keyboard/VoiceOver reading order, light/dark
        and increased-contrast behavior, visual fidelity in a browser,
        deterministic output, and honest manifest reporting for every fallback
        or unsupported effect.
    - [x] **B4a — Text content roles (do not overload Type Style categories):**
          give text layers an independent semantic intent, initially **Plain
          text / Paragraph / Heading 1–6**. A visual type style remains reusable
          presentation; a content role controls native export (`<p>`, `<h1>`…
          `<h6>`). Prefer native headings over `role="heading"`; if a component
          is categorized Heading, resolve its level from explicit content data
          or report `headingLevel`—never infer hierarchy from font size/name.
          Inspector authoring, tolerant document decode, component/source
          behavior, instance needs, and HTML/package round-trip coverage belong
          in this slice. Keep lists/labels/quotes/code as later discovery rather
          than inventing a broad content ontology now. DONE 2026-07-22: text
          layers now store a tolerant, independently authored content role;
          Inspector, Type menu, and context menu expose it; plain text emits a
          safe `<span>`, Paragraph and Heading 1–6 emit native tags; and Heading
          components resolve `aria-level` from an unambiguous authored descendant
          without duplicating a nested heading. Package fixtures cover native
          tags, component inheritance, tolerant decode, and document round-trip.
    - [x] **B4b — Verification + fidelity reporting:** deterministic golden
          comparison, standards-valid markup, browser visual comparison,
          keyboard/VoiceOver reading order, light/dark/increased-contrast checks,
          broken relationships, and structured reporting for every unsupported
          semantic or visual fallback. DONE 2026-07-22: fixed-input exports now
          compare byte-for-byte and against reviewed SHA-256 goldens; all 40
          curated roles pass through the real exporter; broken relationships and
          every enabled unsupported-effect occurrence produce categorized,
          instance-qualified fidelity issues. Native Button descendants keep a
          valid phrasing content model, List/List Item use flow-safe ARIA hosts
          until nested semantics exist, and pages declare honest `lang="und"`.
          Firefox/WebKit accessibility-tree, keyboard-focus, light/dark,
          increased-contrast, geometry, overflow, console, and visual checks
          pass; W3C Nu reports no errors. Full app + Quick Look build passes.
- [x] **Chunk D — Figma import** (REST API path first; .fig best-effort later) — v2.1
  - [x] **D1 sanctioned REST first slice:** File ▸ Import Figma File accepts a
        normal Figma URL or file key plus a personal access token scoped to
        `file_content:read`; the token stays memory-only and is sent only to
        `api.figma.com`. The cancellable client fetches `GET /v1/files/:key` with
        vector paths plus image-fill resources. Every Figma canvas becomes an EXP
        page tab; top-level frames become artboards; editable frames/groups,
        rectangles, ellipses, polygons, lines, vectors, rich text, gradients,
        shadows/blur, images, auto layout, named paint/type styles, and local
        component sources/instances map through one report and one undo step.
        A deterministic two-page fixture, existing XD/page/semantic suites, and
        the full signed Debug app/Quick Look/helper build pass on 2026-07-28.
  - [x] **D2 live API + visual acceptance:** owner-import representative small,
        multi-page, component-heavy, image-heavy, and large files; verify page/tab
        names, cancel, one-step undo, save/reopen, report-on-demand, and exact
        editable geometry. Close mixed text, image crop/container, masks/clips,
        component properties/variants/remote sources, advanced auto-layout sizing,
        unsupported node/effect types, rate-limit/error UX, and performance findings
        from those real responses. DONE 2026-07-28: the owner accepted the live
        REST importer as a solid first implementation after repeated side-by-side
        checks and editable cleanup. Advanced Figma constructs that cannot yet map
        exactly remain honest report items rather than silent fidelity claims;
        extreme-document performance stays in its planned dedicated phase.
    - [x] **D2a first live-file fidelity correction:** Figma TEXT-node fills now
          supply base run color instead of silently falling back to black;
          `size` is reconstructed inside the already-rotated absolute bounding box
          so line/vector/icon rotation is applied once; open vector geometry stays
          open; Figma dash arrays map to editable Solid/Dash/Dot stroke patterns;
          and a group containing Figma mask siblings becomes an active EXP mask
          group. Stroke patterns are authorable on lines, paths, shape borders,
          group backgrounds, and multi-selection, remain state/instance-aware,
          save compatibly, and render through canvas, PDF/PNG, SVG, and semantic
          HTML/CSS. Owner visually accepted the corrected re-import on 2026-07-28.
    - [x] **D2b absolute children in auto layout:** Figma
          `layoutPositioning: ABSOLUTE` now survives as an editable node trait and
          frame surfaces never consume a stack slot. Auto layout keeps absolute
          artwork in its authored coordinates, preserves the imported outer frame,
          and arranges only participating children. A narrow geometry/spacing
          compatibility inference repairs already-saved imports whose enclosing
          `Background` was previously counted as item zero (the button-content and
          color-swatch shift). The focused fixture covers new and legacy imports;
          owner visually confirmed the correction on 2026-07-28.
  - [ ] **D3 auth/tokens follow-up (deferred; not a v2.1 gate):** decide whether repeated imports merit an
        explicit Keychain opt-in or full OAuth. Keep memory-only PAT entry as the
        privacy-safe baseline. Figma's reusable Variables endpoint is Enterprise-
        restricted; import bound rendered values now and add variable-to-Design-
        Language mapping only when an eligible fixture/account can prove it.
- [ ] **Chunk E — Code/Storybook/HTML-CSS import** — v2.2
- [ ] **Chunk F — Agent Bridge** (EXP as a LOCAL MCP server the designer's own
      agent connects to; opt-in, OFF by default; stdio helper + Unix socket;
      no vendor API keys, no fake usage bars) — F1 spine dark in v2.0 →
      F2 **Handoff panel** in v2.1 (named 2026-07-17: one panel for exports,
      packages, AND the agent section; PNG/PDF/SVG surface there too, with
      File ▸ Export menus kept per command-coverage rule) → F3 write-back v2.3+
  - [x] **F1 — dark read-only spine (v2.0):** hidden-default-gated current-user
        Unix socket, bundled `Contents/Helpers/exp-mcp` stdio relay, MCP
        initialize/tools/resources handling, and the six planned read-only tools.
        DONE 2026-07-22; full signed app/helper build, unavailable-app behavior,
        real front-document artboard/node/selection/token reads, dual orientation
        access, multi-megabyte framing, permissions, and clean shutdown passed.
  - [x] **F2 — Handoff panel + visible opt-in/setup (v2.1).**
    - [x] **Implementation:** one dockable/floating Handoff panel now owns
          Export (current/selected and all artboards), Package (Handoff Package,
          standalone semantic HTML, and DTCG tokens), and Agent. Agent access
          remains off by default; enabling starts the existing current-user local
          socket immediately, reports ready/connected/error state and client name,
          labels the contract read-only, supplies Claude Code/Claude Desktop/
          generic stdio setup snippets, and offers a connected-selection prompt.
          File-menu export paths remain additive. The universal signed Debug app,
          helper/entitlement/security matrix, importer/page/nested-component/
          semantic HTML/package suites, and deterministic package goldens pass
          2026-07-28.
    - [x] **Owner acceptance:** visually exercise the panel docked and detached,
          resize/collapse it, export each artifact, connect a shipping MCP client,
          verify live identity/read-only/off behavior, and check keyboard order,
          VoiceOver, light/dark, increased contrast, and reduced transparency.
          OWNER VERIFIED 2026-07-28: the complete panel/appearance/assistive-
          technology matrix passed; Claude Code connected through the generated
          user-scope setup, exposed all six read-only tools, returned live document
          and changing-selection data, reported client identity in EXP, and cleanly
          returned to ready/off states on disconnect and disable.
    - [ ] **Agent capability packs / skills (deferred; not a v2.1 gate):** after
          the F1 tool contract has
          survived real-client compatibility testing, publish one canonical EXP
          usage guide plus thin host-specific packages for Codex, Claude, and
          other worthwhile MCP clients. Each teaches summaries-first use of the
          six tools, ids as reference currency, read-only/privacy boundaries,
          and graceful no-app behavior; include the EXP name/logo/icon wherever
          that host renders skill/plugin branding. Keep raw generic MCP setup
          fully supported—the skill improves recognition and guidance but must
          never be required to connect. Version/test each wrapper against the
          shared contract so agent-specific instructions cannot silently drift.
  - [ ] **F3 — separately consented, undo-safe write-back (v2.3+).** Built as
        FEAT-048 (`apply_edits`) on 2026-08-25 under the Sanaa name; the box stays
        unchecked because no runtime verification has been run
        (`scripts/verify_sanaa_write_gate.sh`).
- [x] **Panel IA + tool-discoverability pass** — v2.1, coordinated with F2 so
      the new Handoff panel joins an intentional system rather than becoming one
      more destination. Inventory every shipped command and reorganize docked/
      floating panels by workflow; give Pathfinder/vector operations, alignment/
      distribution, component states + semantics, Design Language, and export/
      handoff controls clear homes and appropriate selection-aware states. Preserve
      menu, context-menu, and keyboard paths (a panel is never the only path),
      remove stale/duplicate placements, and verify resizing, collapse/detach,
      keyboard traversal, VoiceOver order, and system appearance/contrast.
      IMPLEMENTED 2026-07-28: Handoff is a first-class PanelID in default docks,
      fresh floating trays, persisted-layout migration, and Window menu routing;
      selection-aware Vector controls now expose Convert to Path, Outline Stroke,
      and all four Pathfinder operations directly in Properties. Existing visible
      Align/Distribute, component state/semantic, Components, Design Language,
      File/Object/Arrange/context-menu, and keyboard routes were retained. Owner
      visual/assistive-technology acceptance passed 2026-07-28; owner also
      accepted the compact neutral Handoff action style as consistent with the
      other panels.
- [x] **Chunk G — XD import** (.xd = frozen ZIP-of-JSON; rides the same
      InteropCodec pipeline; proves importers before Figma) — v2.1
  - [x] **Shared codec + offline first slice:** bounded/cancellable ZIP reader,
        AGC scene-tree mapping, native File-menu import, one-step undo, progress,
        and a visible/copyable fidelity report. Real-corpus structural check
        passes all 11 owner-supplied packages (644 artboards) on 2026-07-28.
  - [x] **Core editable mapping:** artboards, groups, primitive/vector paths,
        rich text runs, opacity/visibility/blend/rotation, solid/gradient paint,
        strokes/corners, lazily embedded raster/pattern resources, named document
        colors/gradients, and prototype links as artboard notes. Approximations
        and unsupported content are reported.
  - [x] **Visual-fidelity closure:** owner visually accepted representative XD
        imports on 2026-07-28 as looking correct and remaining editable as
        expected. Image resources, line/group geometry, text bounds/overflow and
        tracking, placement visibility/collision, quiet success UX, and on-demand
        reports were closed against the supplied corpus. XD-only constructs that
        cannot be reconstructed are honestly approximated or flattened into
        editable EXP content and remain visible in the Import Report. The corpus
        contains no character-style library fixture, so that unproven optional
        mapping is recorded rather than blocking the rescue importer.
- [x] **Chunk I — Nested components + semantic containment** — v2.1 model gate
      before component-preserving Figma/XD import: cycle-safe source dependencies,
      instance-path overrides/ids, recursive authoring/detach/export, and
      context-aware ARIA child-role recommendations (List → List Item, etc.).
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

### v2.0 release gates — complete 2026-07-22

- [x] **Implementation closure:** Chunk B/B4 and the dark F1 spine are complete;
      deterministic package/browser/standards checks, direct helper↔app MCP
      contract checks, signed Debug/Release builds, and the universal local
      Release archive pass.
- [x] **Owner real-document acceptance:** export a Handoff Package from a normal
      working document; inspect its README/manifest, open representative HTML in
      the browser, and confirm the intended notes/roles/type content survive.
      PASS 2026-07-22: the owner's 5.7 MB v2 working document
      exported successfully with valid manifest bytes/SHA-256 and one complete
      semantic page; owner completed the browser/VoiceOver/intent acceptance.
- [x] **Real MCP-client compatibility smoke:** point at least one shipping MCP
      client (plus a second client or MCP Inspector if practical) at the bundled
      `Contents/Helpers/exp-mcp` from the release candidate. Verify initialize,
      discovery, resource reading, every read-only tool, front-document switching,
      app-not-running/access-off errors, and no response to notifications.
      PASS 2026-07-22: the shipping Codex client discovered the server and called
      all six tools successfully against the signed archived app; direct live
      checks covered document retargeting, unavailable/default-off behavior,
      response-free notifications, socket permissions, and clean shutdown.
- [x] **Production archive/helper security:** archive with Developer ID; confirm
      the app and nested `exp-mcp` are universal and correctly signed, strict deep
      codesign passes, the app carries sandbox + network client/server + Sparkle
      exceptions, the helper carries no sandbox/network entitlement, the socket
      is container-local at 0600/current UID, and the default-off app creates no
      listener. Repeat a live bridge smoke from the exported/notarized app because
      distribution signing and Gatekeeper can expose behavior a Debug build does not.
      PASS 2026-07-22: the Developer ID/notarized app and zip round-trip are
      universal and pass helper/app strict signatures, entitlement isolation,
      Gatekeeper, staple, default-off behavior, and a live production bridge smoke.
- [x] **Release communication + packaging:** finalize `RELEASE-NOTES-v2.0.md`,
      verify version 2.0/build 10 and production website content, then Direct
      Distribution → notarize → staple → strict signature/Gatekeeper verification
      → metadata-clean exact Sparkle zip/appcast → GitHub release + site deploy.
      PASS 2026-07-22: exact 27,922,074-byte zip published with SHA-256
      `3abbd5a1b1e67fb49859e503f3c3d8b4c5536c65b9b18497738bf4023192ca92`;
      signed appcast, release notes, GitHub Release, site, and ARIA guide are live.
- [x] **First complete Sparkle install proof:** from the preserved public v1.6.1
      baseline, discover v2.0, download, install, relaunch, and confirm About shows
      2.0/build 10. Exercise the update dialog with VoiceOver and increased contrast;
      rerun the installed-baseline/security checks on the updated app.
      OWNER PASS 2026-07-22: v1.6.1 discovered v2.0, installed it, relaunched
      successfully, and all final checklist/public verification passed.

### Post-v2.0 priority lane — Help-recording findings (2026-07-23)

- [x] **P1 — BUG-006: keep component-state typography and opacity local to the
      active state.** Fixed in v2.0.1 before publishing the component-states Help
      page. This was first because a state edit previously mutated the shared
      source and could silently change Default, sibling states, and every instance.
      The bounded state/instance override model, rendering, editing capture,
      handoff, undo, and tolerant document decoding were extended together. Full
      repro and acceptance criteria are in `docs/BACKLOG.md`.
- [x] **P2 — BUG-005: Shift-constrain new Pen handles to axis/45-degree
      increments.** Fixed in v2.0.1 by reusing the constraint behavior already
      present for editing an existing handle. This was second because free-drag
      remained usable and the defect did not mutate unrelated document content.
      Full repro and acceptance criteria are in `docs/BACKLOG.md`.
- [x] **Help follow-up after the fixes:** Help draft 03 now reflects the fixed
      behavior and the reordered Type panel. All eighteen clean demonstrations,
      including Pen curves and component states, are ready to record without
      workarounds; site integration still waits for the edited clip set.

---

## v2.0.1 — released (2026-07-23)

Build 11, `MARKETING_VERSION 2.0.1`. A narrow bug-fix lane after v2.0, closing
two defects found while recording the Help walkthroughs so the blocked
demonstrations can be rerecorded. Release notes: `RELEASE-NOTES-v2.0.1.md`;
follow the v1.6.1-style copy/paste release path with 2.0.1/build 11.

- [x] **BUG-006 — component-state typography/opacity leak (P1).** Non-default
      state edits (text color/face/size/alignment/line-height/tracking/case and
      layer/group opacity) must affect only that state; Default and siblings stay
      byte-for-byte unchanged; instances render the chosen state; semantic handoff
      preserves the differences; one coherent undo step; tolerant schema-v2 decode.
- [x] **BUG-005 — Shift-constrain a new Pen curve handle (P2).** Shift during a
      new anchor's handle drag snaps to axis/45-degree increments, mirroring the
      existing `pathPointDrag` branches; the opposite handle stays mirrored; one
      path draw remains one undo step.
- [x] **Owner verification + release.** Both fixes and the Type-panel ordering
      polish are pushed on `main`; v2.0.1/build 11 is tagged and released.

---

## v2.1 — released (2026-07-29)

Build 12, `MARKETING_VERSION 2.1`. The release order is deliberate: finish the
Chunk I nested-component model gate first, then build XD/Figma import against a
component structure that can round-trip without hidden flattening. F2 Handoff
and the coordinated panel/tool-discoverability pass remain in this release.

- [x] **Chunk I slice 1 — nested placement + graph safety.** Component instances
      can be placed while editing another source from drag/drop, Object menu,
      canvas context menu, or the Components panel. Every path uses the same
      dependency graph and rejects direct/indirect cycles before mutation;
      Layers shows nested source identity and can open the referenced source.
      A focused headless graph check and the full signed Debug app/Quick Look
      build pass.
- [x] **Chunk I slice 2 — nested Layers authoring + state-safe outlines.** Instance
      layer names are independent from source component names; component rows show
      both identities in a compact two-line treatment and reserve source renaming
      for an explicit context-menu action. Layers expands nested component trees
      recursively and exposes Default/named state pickers at every component level;
      placed-parent choices persist as stable instance-ID paths instead of mutating
      the source. Component states now capture outline color/alpha, width, and
      inside/middle/outside position, including auto-padding group backgrounds.
      Relationships moved to the inspector bottom and appear only for role-relevant
      kinds (while preserving access to already-authored relationships). Owner
      verified the recursive hierarchy and compact default-width Layers/Components
      presentation on 2026-07-24. State-local layer blend modes joined the same
      bounded appearance-diff path on 2026-07-27 (BUG-015).
- [x] **Chunk I closure.** Dependent-source deletion is owner-verified after
      BUG-014's double-offset fix (see Phase 4.1); stable instance paths, nested overrides/public props/states/layout/detach/
      export/Quick Look, semantic containment guidance, and the full acceptance
      matrix below are complete. Focused graph/relationship/semantic/package/SVG
      suites and the full signed Debug app + Quick Look/helper build passed on
      2026-07-27; the owner passed the complete end-to-end matrix on 2026-07-28.
- [x] **Chunk G XD import.** Shared importer/report pipeline and offline XD
      rescue are implemented and owner-accepted across representative real files.
- [x] **Chunk D Figma import.** The sanctioned REST importer maps Figma pages to
      EXP canvas tabs and passed owner live-file visual/editability acceptance on
      2026-07-28. OAuth/Keychain and Enterprise Variables remain deferred choices,
      not v2.1 first-implementation gates.
- [x] **Canvas pages acceptance.** Browser-tab-like canvas pages are now the
      document boundary for large imports and future Figma page mapping. Verify
      tab add/rename/deep-duplicate/reorder/delete + undo; independent camera,
      guides, Layers, and selection per page; move/duplicate-to-page from both
      context and Edit menus for single/multiple layers, a nested child, and
      single/multiple artboards with their owned content; save/reopen and legacy
      one-page migration. Component sources and Design Language stay shared.
- [x] **F2 + panel IA.** The visible Handoff surface, coordinated command/tool-
      discoverability pass, complete owner UI/assistive-technology matrix, and a
      live Claude Code MCP connection using all six read-only tools passed on
      2026-07-28. Host-specific capability packs remain an optional deferred
      enhancement, not a v2.1 release gate.
- [x] **Release story + documentation.** `RELEASE-NOTES-v2.1.md`, the exact
      build-12 release checklist, refreshed public feature architecture/copy,
      current tester-feature feed, and component/import-handoff asset briefs are
      aligned with the owner-accepted scope. Existing multi-window and contrast
      stories remain; Design Language copy now reflects colors, gradients, type
      styles, categories, and token/CSS/JSON handoff. Final Design Language and
      optional replacement feature graphics can land without changing the story.
- [x] **Final release gate.** Run the complete v2.1 Release build/script matrix,
      repeat the condensed owner smoke test, archive/notarize, byte-verify the
      shipping zip, generate/publish Sparkle metadata, prove the public
      v2.0.1 → v2.1 install/relaunch path, and only then announce. Exact commands:
      `docs/RELEASE-CHECKLIST-v2.1.md`. COMPLETE 2026-07-29: v2.1/build 12 is
      tagged and public; the signed appcast and release-notes page are checked in,
      and the owner confirms the release shipped.

---

## v2.2 — released (2026-08-05)

Build 13, `MARKETING_VERSION 2.2`. Primary scope is **Chunk E — code/component
import**: reconstruct editable EXP documents from rendered HTML/CSS first, then
layer Storybook ingestion on the proven browser-to-EXP mapping. Reuse the semantic
HTML contract in reverse, resolve layout and computed styles in a browser engine,
and preserve the import pipeline's visible fidelity reporting; do not imply
arbitrary source-code or pixel-perfect round-tripping.

- [x] **E0 — rendered-HTML import contract + technical spike. COMPLETE 2026-08-01.**
      Contract written and owner-accepted, spike run to completion, the trust model
      proven and its limits documented with filenames. Define the
      supported input boundary, browser-engine isolation, DOM/computed-style
      payload, resource/privacy rules, cancellation/size limits, semantic-role
      reverse mapping, and fidelity-report categories. Prove one bounded local
      HTML/CSS fixture end to end before committing to the full importer surface.
  - [x] **Contract drafted (2026-07-29):** `docs/HTML-IMPORT-CONTRACT.md` records
        all seven required sections, a two-pass source-trust model with its Import
        Session UI, the GitHub/Storybook auth boundary, and the bounded spike design.
        Owner decisions captured: local file/folder AND URL input (no pasted
        fragments, no authenticated pages); subresources blocked by default with
        trust granted per ORIGIN, expandable to individual resources; trust stored
        per document, opt-in, with no app-wide allowlist; adjusting an import
        re-renders and REPLACES with an explicit warning (deliberate v2.2 starting
        position — surgical placeholder-fill recorded as a post-testing follow-up);
        viewport chosen from the existing `ArtboardPreset` widths. Four §8
        reverse-mapping rows are verified against ARIA in HTML / HTML-AAM with
        citations; the remaining ~40 rows, `aria-*` state mapping, and `<a href>`
        are recorded as UNVERIFIED and explicitly block E1. Four open questions
        (Q1 folder shape, Q2 duplicate-URL sessions, Q3 default preset, Q4 manifest
        overflow) need owner answers.
  - [x] **Owner acceptance of the contract (2026-08-01).** Q1–Q4 answered and the
        input/privacy boundary confirmed. Q1: folder import puts one artboard per
        file on ONE canvas page. Q2: re-importing a URL that already has a session
        offers to adjust it and defaults to adjust, with "Import as new" still
        available. Q4: exceeding the 2,000-entry manifest cap degrades to
        same-origin-only with the overflow reported, rather than refusing the import.
        **Q3 was superseded by a better answer:** the viewport control is a
        MULTI-SELECT, so one import can produce phone/tablet/desktop artboards
        together (Desktop 1440 the sole pre-selection). That reshapes the contract
        rather than setting a default — discovery now runs per viewport with a UNION
        manifest, trust stays session-wide, the report splits categories 1–5 per
        viewport, and folder × viewport is a matrix. Written up in
        `HTML-IMPORT-CONTRACT.md` §1.1 with the knock-ons in §§3, 4, 5, 7, 9, 10.
  - [x] **Spike. COMPLETE 2026-08-01** — five runs, owner-run in full. Fixture 3's
        criteria are all settled and the trust model is proven; fixtures 1–2's
        geometry, text-run and role criteria are **deliberately deferred to E1**
        (owner decision, 2026-08-01), because they need the mapper that IS E1's
        substance and a spike does not de-risk a thing by building it. Original note
        follows. IN PROGRESS, first run done 2026-08-01. Fixture 3 PASSES every
        criterion testable without an importer — pass-1 purity confirmed against the
        fixture's own server log, and the iterative-trust case reproduces (4 origins
        / 6 resources → 5 / 8 once origin A was trusted). Recorder verdict: ship the
        DOM walk + request instrumentation, treat PerformanceObserver as a pass-2
        cross-check only. One contract change fell out — §4.1, iterative trust is the
        NORMAL path, because a blocked or cross-origin stylesheet hides every resource
        it references. Remaining: rerun fixture 3 with the harness fixes to prove the
        union manifest, and fixtures 1–2's geometry/text/role criteria stay untickable
        until a mapper exists. Three fixtures: (1) EXP's own exported semantic HTML, chosen
        because `data-exp-id` gives ground truth for round-trip accuracy;
        (2) a hand-written non-EXP page, proving the importer is not merely
        self-consistent with its own exporter; (3) a multi-origin page with a
        third-party script and webfont, which is the only one that exercises the
        trust flow — including the check that pass 1 fetches the document and
        NOTHING else, and that allowing a script surfaces new manifest entries.
        Fixture 2 now also carries a width media query and imports at TWO viewports,
        so the multi-viewport matrix and union manifest are proven on the fixture
        whose expected result is known by construction. Run the §10 pass criteria.
- [x] **E1 — editable HTML/CSS import. COMPLETE 2026-08-05.** Map rendered boxes, text, images,
      paint, borders, effects, stacking, and supported layout into native EXP
      pages/artboards/nodes through `InteropCodec`, with one undo step and an
      honest on-demand Import Report for every approximation or omission.
      **Carries forward from E0:** ship recorders `D` + `I` with `P` or `R` as
      corroboration (never both); implement §4.1–§4.3 (iterative trust as the normal
      path, declared-vs-requested attribution per viewport, one named Sources row per
      unreadable stylesheet); keep the server-log cross-check in the test suite; use
      measured content height, never `scrollHeight`. **Adjust offers replace-in-place
      OR import-as-new-artboard** (§5), so sessions track generations rather than one
      set of ids and each generation is labelled with the viewport/trust that produced
      it. **Every loss row carries a repair action** (§5.1) — copy URL / copy all,
      supply a local file (with a "Choose file…" button, never drag-only), open the
      source in the user's own browser, paste stylesheet text — and any import
      containing hand-supplied assets or CSS declares that in the report. **§8 element mapping is DONE (2026-08-01):** ~70 rows
      verified against HTML-AAM 1.0 (W3C WD 29 July 2026) with per-row citations,
      including all 23 `input` states, tables, lists, and `select`. Four new rules
      came out of it (§8 rules 6–9). BUG-018 is fixed and owner-verified. **Remaining
      a11y work before/inside E1:** `aria-*` state mapping (needs WAI-ARIA 1.2 role
      definitions, not HTML-AAM) and what to do when an explicit `role` contradicts
      its host element (needs ARIA in HTML's role prohibitions). Fixtures 1–2's geometry/text/role criteria in §10 become
      checkable as soon as the mapper exists and are E1's first proof.
  - [x] **E1a — production snapshot seam + first pure mapper slice (2026-08-03).**
        `RenderedHTMLImporter.swift` now defines the fixed, Codable browser payload,
        the read-only DOM/computed-style extraction script, and a browser-neutral
        mapper through `InteropImportResult`. Multiple viewport snapshots become
        independent editable artboards using viewport width × measured content
        height; DOM nesting, browser-measured text rect unions, solid/linear-gradient
        paint, uniform/per-corner radius, inside borders, first box shadow, opacity,
        blend mode, responsive context notes, and `data-exp-id` identity are retained.
        Unsupported image bytes, transforms, filters, and authored ARIA data are
        reported rather than guessed; ARIA reconstruction deliberately waits for the
        remaining WAI-ARIA/ARIA-in-HTML verification above. The deterministic
        `verify_rendered_html_importer.sh` fixture proves phone + desktop geometry
        and editable styling. Full Debug app build, Figma fixture, 11-file XD corpus,
        semantic HTML contract, and deterministic package suites pass.
  - [x] **E1b — local-file browser-to-import vertical slice (2026-08-03).** Put the
        production extraction script behind a per-import non-persistent `WKWebView`,
        enforce the deadline/cancellation/payload limits, and feed fixture 2's real
        local HTML/CSS render into E1a (Phone + Desktop) with one document mutation.
        Keep this first UI narrow: local file + its scoped directory, same-origin
        resources only. Then layer the iterative remote-origin Sources/session UI on
        the proven capture-to-map path instead of coupling both unknowns at once.
        Implemented with a folder-scoped entry-file picker so the release sandbox
        can actually read relative CSS/images/fonts; a custom `exp-local` scheme
        preserves a same-origin CSSOM while blocking network/file URLs and resolving
        symlinks before the folder-boundary check. The real WKWebView fixture proves
        Phone/Desktop media-query divergence, editable text/paint/shadows, embedded
        local raster/inline-SVG assets, single-layer CSS image backgrounds, source
        receipt, cancellation, import-wide caps, and symlink confinement. The File
        menu flow inserts all viewport artboards in one undoable mutation. **Owner
        visual acceptance complete (2026-08-03): owner approved both the hand-written
        fixture and a real Chrome-saved website/package import after text, SVG,
        animation-state, and local-resource refinements.**
  - [x] **E1b SVG preservation policy + native path (2026-08-03).** Local and
        inline SVG assets now enter `SVGImporter` as original sanitized markup,
        not browser PNG previews. Common SVG logo/texture structure remains native:
        paths and primitives, gradients, transforms, `symbol`/`use`, repeating CSS
        SVG backgrounds, and mask clipping. Standalone `feGaussianBlur` maps to a
        new editable **Layer Blur** effect rendered on canvas and PNG/PDF export and
        round-tripped to SVG. Unknown filter primitives retain the editable geometry
        and are named in the Import Report. Architecture decision: add native EXP
        effects as real imports require them; raster fallback is the explicit last
        resort. General 4×5 `feColorMatrix` is the first named follow-up, not falsely
        reported as supported before its native effect exists.
  - [x] **E1b fidelity-gap inventory (planning, 2026-08-03).**
        `docs/WEB-SVG-FIDELITY-INVENTORY.md` records the visually meaningful CSS,
        SVG structure, paint, typography, transform, and filter capabilities that
        EXP cannot author yet. It separates humane native concepts from low-level
        filter-graph storage and prioritizes Color Adjust/`feColorMatrix`, general
        component transfer, morphology, displacement, SVG pattern paint, layered
        fills, clip/mask round-trip, gradient/stroke fidelity, CSS filter mapping,
        and performant backdrop blur. Add import telemetry before reordering the
        list from real usage.
  - [x] **E1 semantic-role/state cleanup (2026-08-03).** WAI-ARIA 1.2 and the
        current ARIA-in-HTML host table now govern the mapper instead of an
        unsupported-semantics placeholder. Native and conforming explicit roles
        map into tolerant `NodeSemantics`; authored `aria-*` values stay structured
        and non-executable rather than becoming invented visual states. Prohibited
        host-role combinations retain the authored token, fall back to the verified
        implicit role, and report the conflict. Mixed rich text also retains inline
        `href` on the styled run and semantic export reconstructs the anchor.
  - [ ] **E1c — controlled rendered-source sessions; owner decision 2026-08-03.**
        Arbitrary URL import is explicitly **deferred** and is not a v2.2 gate. A
        good local folder/package import covers that smaller use case with one
        deliberate download/export step and avoids turning EXP into a browser.
        **E1c-a** remains the bounded path for user-selected local/static artifacts
        and explicitly published component-system renders (including hosted
        Storybook and a future CodePen deployment) with receipts,
        replace/import-as-new generations, and same-origin defaults. **E1c-b** is a
        post-v2.2 reconsideration of arbitrary public URLs and the full two-pass
        growing trust manifest only if connector evidence justifies it.
        Authenticated pages, persistent login/cookies, form submission, downloads,
        general crawling, and unrestricted navigation remain outside the boundary.
- [x] **E2 — Storybook import. COMPLETE 2026-08-05.** Ingest a static/local Storybook build only
      after E1 is stable; create per-story artboards and preserve story metadata
      such as args as structured notes. Prefer the published/static Storybook
      contract (`index.json` metadata + isolated `iframe.html` story renders), which
      works across React, Vue 3, Angular, Web Components, Svelte and other supported
      integrations. Render to DOM first—never pretend a framework AST directly
      describes pixels. Do not run dependencies/build scripts from an untrusted
      remote repository inside the app process.
  - [x] **E2 static-build first slice (2026-08-03).** File ▸ Import Storybook
        Build… accepts a selected folder containing the published `index.json` +
        `iframe.html` artifacts, skips docs entries, and renders each
        `?id=…&viewMode=story` at the selected viewport(s) through a non-persistent,
        external-network-blocked WebKit seam. Because production Storybook uses ES
        modules, its selected folder is served briefly through a tokenized,
        ephemeral IPv4-loopback origin; all other HTTP/file requests remain blocked,
        path traversal remains impossible, and the listener ends with the import.
        Capture waits for Storybook's rendered-main state and laid-out story root,
        failing explicit runtime/no-preview/timeout states rather than creating
        empty one-pixel artboards. Story/viewport artboards retain
        title, name, id, tags and importPath. `CodeBridgeManifest` stores the index
        digest/entry receipt, consumed resources, story behavior-contract slots,
        and receipt-only DOM bindings. No package manager, framework compiler, or
        Storybook build runs. The importer discovers the complete catalog without
        rendering it, then presents a searchable story picker (title, name, id,
        tags and source path) for up to 100 stories per import; a small 1–20 story
        slice is recommended while validating an unfamiliar library.
  - [x] **E2 live GitLab corpus hardening (2026-08-03).** A representative
        eight-story slice now covers controls, badges, tabs, an accordion, a
        table, a chart, an illustration, and a play-function-opened modal.
        Storybook readiness remains stable through interaction phases; hidden
        preparation/docs shells no longer consume the DOM budget; zero-box
        portal mounts inherit the union of their visible positioned descendants;
        fixed overlays extend the artboard to their visible viewport; and
        same-folder external SVG `<use>` sprites are safely inlined with
        namespaced IDs so paths, gradients, and filters reach the native editable
        SVG importer. The corpus produces eight non-empty artboards, retains the
        modal content and three clipped accessibility labels correctly, and maps
        six SVGs editably with no SVG raster fallback. Deterministic WebKit tests
        cover the portal/sprite boundary without depending on the owner's fixture.
  - [x] **E2a — hidden Interop Provenance Layer / `CodeBridgeManifest`. v2.2
        foundation COMPLETE 2026-08-05.** Add a
        versioned, tolerant-decoding structured section inside `.design`, separate
        from user-facing Notes and ordinary canvas nodes. It records connector and
        source identity; repository/branch/commit/package paths; Storybook story ids,
        args and build identity; CodePen Pen/version/config identity; framework,
        runtime, build-tool and package-manager metadata; file/resource hashes;
        EXP-node ↔ external-id/source-span/token/DOM bindings with confidence;
        behavior contracts (props, events, states, relationships and ARIA);
        ownership/fidelity boundaries; and opaque source/config/JS passthrough that
        EXP preserves but never executes. Store no credentials or secrets in the
        document—service tokens belong in Keychain. Preserve the import baseline so
        future sync is a three-way comparison (imported base vs current EXP vs
        current code), not a blind overwrite. This foundation lands before any
        connector claims safe round-trip or write-back.
    - [x] **Schema + local-HTML receipt slice (2026-08-03).** Document schema 4
          now persists tolerant-decoding connector/source/runtime fields, resource
          receipts, SHA-256 hashes, bounded opaque source bytes, node/artboard
          bindings, behavior-contract slots, ownership/confidence, explicit writable
          properties, and the import baseline. The local WebKit importer records only
          resources it actually consumed, retains up to 8 MB of HTML/CSS/JS/config/
          text-SVG source without interpreting it as canvas behavior, and binds each
          imported viewport/DOM element. Every rendered binding starts receipt-only
          with no writable properties. Credentials and absolute local paths are not
          stored. Import + bridge insertion remains one undoable mutation.
    - [x] **Storybook runtime/project metadata slice (2026-08-03).** When a
          published static build includes Storybook's optional `project.json`,
          retain and hash it, then map its framework/renderer/builder,
          Storybook version, language, and package-manager identity into the
          structured source receipt. After each isolated story completes,
          capture its normalized `initialArgs` as bounded JSON-safe data on the
          story behavior contract (functions, DOM objects, cycles, excessive
          depth/count, and payloads over 64 KB are omitted). These values remain
          source-owned receipts with no executable behavior or writable-property
          claim. Synthetic and live GitLab fixtures verify the path.
  - [x] **E2b — CodePen 2.0 handoff connector, export-first. COMPLETE 2026-08-03.** First ship
        **EXP → new CodePen Pen** through CodePen's supported POST-to-Prefill contract
        using semantic HTML/CSS/JS output. Record that Prefill currently carries one
        HTML, CSS and JS payload rather than the full 2.0 filesystem. Add
        **CodePen-exported ZIP → EXP** through the local importer: render the last
        successful browser-ready `dist/` artifact while retaining `src/`,
        `.codepen/pen.config.json`, Blocks/processors, paths and hashes in the bridge
        manifest. A generated 2.0-ready ZIP can follow for multi-file handoff.
        CodePen's public deployed `*.codepen.app` pages may later use E1c-a's narrow
        published-source path. Do **not** promise update-in-place sync until CodePen
        offers an authenticated file read/write API; editable embeds are an excellent
        user workflow, not a programmatic source-sync contract.
    - [x] **EXP → new CodePen first slice implemented (2026-08-03).** File and
          Handoff expose “Send Current Artboard to CodePen…”. It generates only the
          chosen artboard's semantic HTML/CSS, removes the package-relative stylesheet
          link, enforces a 4 MB prefill boundary, and opens an accessible local review
          page that discloses the transfer before its user-activated POST to CodePen's
          documented 2.0-prefill endpoint. No credentials or background upload.
          Opaque imported JavaScript remains preserved in the bridge but is not sent
          until an explicit behavior/DOM contract makes that honest.
    - [x] **Owner live CodePen confirmation (2026-08-03 — Tapps approved).** From Xcode, send one representative
          artboard, press the local review page's Send button, and confirm CodePen 2.0
          accepts the payload and reproduces the semantic HTML/CSS. Then polish any
          endpoint/editor-mode mismatch before calling export-first complete. First
          live attempt reached the endpoint but returned its plain “Something Went
          Wrong” response. EXP now submits only CodePen's current documented Prefill
          fields (removing deprecated `editors`/`tags` and invalid `neither` option
          sentinels), sends the documented HTML body fragment instead of a nested
          standalone document, and preserves the local review page by opening the
          result in a new tab. A second owner attempt proved the transitional
          `/cpe/pen/define/` route itself now returns CodePen's internal-error page
          after the site-wide 2.0 launch; EXP now targets `/pen/define`, which creates
          a live Prefill session. The owner confirmed the corrected flow is smooth and
          the representative SVG artboard reaches CodePen successfully.
    - [x] **CodePen 2.0 exported-ZIP first slice implemented (2026-08-03).** File
          exposes **Import CodePen Export…** for a local ZIP. A bounded reader
          rejects traversal, absolute/platform paths, symlinks, encryption, ZIP64,
          unsupported compression, ambiguous roots, missing `dist/index.html` or
          missing sibling `src/`, and per-file/package expansion limits. It handles
          the normal title/slug wrapper folder, materializes fresh data files in a
          private temporary directory, renders only `dist/index.html`, then removes
          that directory. No package manager, compiler, Block, or build script runs.
          Browser-ready `dist` JavaScript may run only in the existing short-lived,
          non-persistent, network-blocked WebKit render; authored `src` scripts remain
          opaque and unexecuted. The full package inventory carries relative paths,
          roles, byte counts, SHA-256 hashes, and up to 8 MB prioritized text source,
          including `.codepen/pen.config.json` and other processor configuration.
          `CodeBridgeManifest` records the archive digest, CodePen Compiler identity,
          last-successful-dist boundary, and receipt-only bindings. A deterministic
          wrapped-package fixture proves phone/desktop import, native editable SVG,
          config/Block preservation, no private temp path retention, and traversal
          rejection. Existing WebKit/pure HTML, semantic package, SVG/token, 11-file
          XD corpus, and unsigned Debug build pass.
    - [x] **Owner live CodePen ZIP confirmation (2026-08-03).** Export the owner-approved Pen from
          CodePen 2.0, use **File ▸ Import CodePen Export…**, and compare at one or two
          viewports. The first live package proved the current wrapper + `src/` +
          `dist/` shape (with no `.codepen/pen.config.json`) is accepted, and exposed
          BUG-019: offscreen WebKit sampled its entrance animations at opacity 0.
          The final-state capture fix passes against all 26 live `.section` groups;
          the owner rebuilt and confirmed the sections are visible. Layers-panel
          numeric opacity was also owner-verified. E2b's local ZIP import gate is
          complete; the first static Storybook slice is next after BUG-021 polish.
  - [x] **E2c — phased framework-generation compatibility matrix. COMPLETE
        2026-08-05.** Modern,
        currently supported Storybook integrations come first, but enterprise reach
        must not silently mean “latest framework only.” Build a measured fixture
        corpus spanning React/JSX, Vue SFC, modern Angular, Svelte and standards-based
        Web Components, then representative older Angular generations and AngularJS
        artifacts where statistically useful. The rendered-DOM/local-artifact seam
        should remain framework-agnostic even when an old stack cannot run a current
        Storybook. Record tested framework + build-tool version bands and degrade to
        visual/local-package import with preserved opaque behavior rather than
        claiming framework-aware write-back. Legacy support rolls out in phases and
        is explicit non-gating compatibility work, not excluded scope.
    - [x] **Second real build + first measured matrix row (2026-08-04).** The
          published CZI Science Design System `gh-pages` artifact at deployment
          commit `af4f1a7` adds React + Vite + TypeScript / Storybook 10.5.2 to the
          existing GitLab Vue + webpack 5 / Storybook 7.6.24 evidence. Its 202-story
          index-v5 catalog and eight-story representative corpus pass through the
          same local static-artifact seam at both Phone and Web 1280: 16 non-empty
          viewport artboards, 130 painted text layers, four editable SVGs, 180
          semantic roles, 82 retained ARIA attributes, and bounded initial args
          for every selected story. Measured generation
          differences are now compatibility rules: terminal runtime phase
          `completed` **or** `finished`; a bounded visible-descendant union for
          populated zero-box Storybook roots; and top-level `storybookVersion` as
          the builder-version fallback when modern `project.json` omits a separate
          builder package entry. Owner visual evidence added three fidelity rules:
          selected Storybook height is the minimum artboard height, transparent
          preview bodies retain the browser's white canvas, and painting/generated
          pseudo-elements plus wider installed fallback-font metrics must survive.
          `docs/STORYBOOK-COMPATIBILITY-MATRIX.md` records the exact fixture
          contracts, counts, limits, reproduction command, and remaining framework
          rows. **Owner visual acceptance completed 2026-08-04:** after viewport,
          generated-content, fallback-font leading, percentage-radius, and capsule
          renderer/path corrections, Tapps confirmed the final CZI re-import fixed.
          The modern Angular row is now unblocked; repository builds and URL trust
          did not expand.
    - [x] **Third real build — modern Angular / Storybook 8 (2026-08-04).**
          Dell Design System's versioned Angular v3.0.1 deployment adds Angular 17
          (publicly documented as compatible with Angular 17–20), TypeScript,
          `@storybook/angular`, webpack 5, and Storybook 8.6.18. Its index-v5
          catalog contains 46 stories + 113 docs. A representative Accordion,
          Button, Metrics Card, Modal, Switch, and Sign-in corpus passes
          through the framework-neutral static-artifact seam at Phone and Web 1280:
          12/12 opaque viewport artboards, 52 painted editable text layers, six
          editable SVG-mask carets, 32 semantic roles, 32 retained ARIA attributes,
          two hidden accessibility
          labels, and bounded initial args for every selected story. Owner review
          added framework-neutral overflow-clipping, transformed pseudo-element,
          and safe deploy-root asset compatibility; no Angular-specific importer
          branch was required. Because the
          source repository is not public, reproducibility is pinned to the public
          v3.0.1 URL and exact `index.json`/`project.json` SHA-256 receipts; the new
          fetch script downloads only published static output and runs no build.
          `docs/STORYBOOK-COMPATIBILITY-MATRIX.md` records the contracts, measured
          limits, and reproduction command. **Owner visual acceptance completed
          2026-08-04:** after the clipping, root-asset, pseudo-transform, and
          data-SVG mask corrections, Tapps accepted the final Dell re-import.
          Svelte + Vite is the next measured row.
    - [x] **Fourth real build — Svelte 5 / Vite 6 / Storybook 8 (2026-08-04).**
          Brave's public Leo (Nala) deployment at main commit `b949916` adds
          Svelte 5.55.7, Svelte CSF v4, Vite 6.4.3, TypeScript, and Storybook
          8.6.18. Its index-v5 catalog contains 104 stories + 31 docs. Alert,
          Button, Checkbox, Dialog, Input, SegmentedControl, Tabs, and Toggle pass
          through the framework-neutral static-artifact seam at Phone and Web
          1280: 16/16 opaque viewport artboards, 32 painted text layers, 18
          editable SVG masks, 28 semantic roles, 14 retained ARIA attributes,
          two editable shadows,
          bounded initial args for every story, and zero native text overflow.
          The live runtime settles at `finished`, proving terminal phase cannot
          be inferred from Storybook major alone: Dell's Storybook 8 settles at
          `completed`. Leo's internally uneven project versions are retained as
          published provenance rather than normalized. The new bounded fetcher
          downloads only same-origin static output, pins catalog/project SHA-256
          receipts, and runs no build. No Svelte-specific importer branch was
          required. **Owner visual acceptance completed 2026-08-04:** after the
          file-backed SVG-mask correction, Tapps accepted the final Leo re-import.
          Standards-based Web Components + Vite followed as the final measured
          modern E2c row.
    - [x] **Fifth real build — Web Components / Vite / Storybook 10 (owner visual
          acceptance completed 2026-08-05).** Kintone UI
          Component's public generated `gh-pages` branch at commit `77c9855` adds
          `@storybook/web-components-vite`, TypeScript, pnpm, and Storybook 10.3.5.
          Its index-v5 catalog contains 106 stories and no docs entries. Button,
          Checkbox, Dialog, Dropdown, Readonly Table, Switch, Tabs, and Text pass
          through the framework-neutral static-artifact seam at Phone and Web 1280:
          16/16 opaque viewport artboards, 113 painted editable text layers, 18
          editable SVGs, 134 semantic roles, 78 retained ARIA attributes, six
          editable shadows, bounded initial args for every story, and zero native
          text overflow. The runtime settles at `finished`. A bounded fetcher clones
          only the already-built deployment branch, pins its commit and exact
          catalog/project receipts, and runs no package or build command. Kintone's
          Lit base deliberately renders into its custom-element hosts as light DOM;
          EXP retains those `kuc-*` hosts as editable groups with no framework-
          specific mapper. Record the honest boundary: this real row does not
          exercise or claim shadow-root/slot traversal. **Owner visual acceptance
          completed 2026-08-05:** Tapps accepted all 16 imported artboards with only
          the already-expected absence of editable component states. The modern
          matrix is closed; older Angular/AngularJS and a future real open-shadow-root
          fixture remain explicit non-gating compatibility work.
- [x] **Supporting v2.2 polish scope closed 2026-08-05.** FEAT-008 was explicitly
      moved to first-priority v2.3 discovery so the owner's additional font-filter
      ideas can be mocked up and tested rather than rushed into build 13. Other open
      backlog items remain candidates, not implicit v2.2 release gates.
- [x] **v2.2 final release gate. COMPLETE 2026-08-05.** The build-13 source and
      public feature story were frozen; the deterministic importer/regression
      matrix, website, and Release build passed; owner acceptance, signed archive,
      notarization, immutable zip, Sparkle/GitHub/website publication, and the
      v2.1 → v2.2 local update/relaunch proof completed. Exact historical path:
      `docs/RELEASE-CHECKLIST-v2.2.md`.

Figma OAuth/Keychain/Variables, host-specific agent capability packs, and agent
write-back remain separately scoped follow-ups; shipping v2.2 did not silently
promote them into release gates.

---

## v2.4 — "Sanaa, and a vector toolset that grows up" (in development)

Active development identity: **2.4 / build 15** across the main app and thumbnail
extension, in both Debug and Release configurations. This is not a public-release
claim; v2.3/build 14 remains the current signed, notarized Sparkle release.

**Owner scope decision, 2026-08-25:** v2.4 ships BOTH the deferred vector/tool
queue and Sanaa, with **Sanaa as the headline**. This is deliberately a large
release — honestly estimated at 16–22 working sessions — and the sequencing rule
below exists so it never becomes one long unverifiable window.

**Sequencing rule (unchanged, and it governs this whole release):** nothing
document-mutating starts while another mutating slice awaits the owner's
verification. Waves alternate; each wave ends at a verification gate.

### Wave A — carry-in slice (code complete 2026-08-24, awaiting owner verification)

Reprioritized by the owner on 2026-08-24 from direct editing friction found in
production use. Committed on 2026-08-25 as `a803df0`; the unsigned Debug build is
green. These stay unchecked until the owner runs the Xcode acceptance pass.

- [ ] BUG-049: every keyboard/Inspector point edit refits the path frame so bounds,
  hit-testing, paint bounds, and drop shadows follow moved anchors.
- [ ] BUG-050 + FEAT-047: Layers selection immediately owns keyboard nudge, and the
  visible persistent Auto-select control provides Photoshop-style selected-layer
  canvas movement for objects under other layers.
- [ ] BUG-051: floating trays behave as active-app palettes, returning above ordinary
  windows on every display for both canvas-click and Command-Tab activation while
  hiding cleanly when EXP is inactive.
- [ ] BUG-052: Reveal in Layers and Expand/Collapse All use the live docked/floating
  Layers surface after mode, collapse, and document changes; Reveal also makes hidden
  or inactive panel content visible before expanding ancestors and scrolling.
- [ ] FEAT-027: Convert to Outlines, Convert to Path, and Outline Stroke recurse
  through selected groups/mixed selections, preserve hierarchy/contracts, and commit
  as one undo step. Fill/Stroke recursion was already present and is included in the
  owner regression pass. The prior backlog idea for a visible partial-success summary
  remains separately unfinished.

### Wave B — Sanaa, the minimal lovable core (the headline)

The optional, default-off design assistant on the EXISTING agent bridge:
pen.dev-style "look at the canvas and draw," with the designer's own MCP agent
reaching in — **no LLM and no API keys in EXP**. Full design, placement rules,
switches, and per-chunk agent instructions: **`docs/SANAA-PLAN.md`**.

- [ ] FEAT-048 — `apply_edits`: consented, undo-safe write-back (the F3 spine).
  Code complete 2026-08-25 and building clean; **no runtime verification has been
  run** — run `scripts/verify_sanaa_write_gate.sh` before checking this.
- [ ] FEAT-049 — presence: activity feed, canvas highlights, VoiceOver announcements. ~2 sessions.
- [ ] FEAT-050 — "Ask Sanaa" prompt starters with placement dialogs. ~1–2 sessions.

Intended order is 048 → 049 → 050. 048 is the only chunk in this wave that mutates
documents; 049 and 050 sit on top of it.

### Wave C — the vector toolset grows up, and one fidelity bug that outranks it

- [ ] **BUG-053 (P1) — raster export silently drops the `noise` and `dissolve`
  effects.** Found in the owner's production use 2026-08-25. `drawExportNode`
  implements three of the six `Effect.Kind` cases; `EffectsRender.drawNoise` has a
  single call site in the whole app and it is the canvas. The canvas and the SVG
  exporter agree; the raster exporter is the odd one out, so PNG, JPG, and PDF
  quietly omit two effect kinds. **This is the export silently not matching the
  design — it outranks everything else in this wave and arguably leads the
  release.**
- [ ] **BUG-054 (P2) — effect blur radii live in three different spaces across the
  two render paths**, including a performance clamp applied in device space that
  makes an export depend on the zoom the document happened to be at. Found while
  tracing BUG-053; a real divergence, but not the one the owner reported.


The queue the owner explicitly deferred from v2.3 on 2026-08-21, plus the one
import bug logged alongside it. FEAT-025 leads because it is the P1 and because it
removes a daily "the app feels broken" moment.

- [ ] FEAT-025 (P1) — direct-select moves whole objects when no points are selected.
  NOT a fix for BUG-028; that stays its own entry.
- [ ] FEAT-029 — pencil tool (freehand fitted to bezier points; expose the fidelity
  control — Schneider curve fitting, `Graphics Gems` 1990).
- [ ] FEAT-028 — outline (stroke) on live, still-editable text. **Research gate
  CLOSED 2026-08-25:** the two mechanisms are not alternatives, they compose —
  HTML/CSS emits `-webkit-text-stroke-*` at 2× width plus `paint-order: stroke fill`,
  SVG emits `stroke`/`stroke-width`/`paint-order="stroke"` on the live `<text>`.
  Support, alignment, and the ~6%-of-traffic caveat are recorded in BACKLOG.
- [ ] FEAT-031 — line end options (square / arrow / round), settable per point.
- [ ] FEAT-030 (P3) — "balanced" (symmetric) curve handle mode. Confirm with the owner
  which of the three anchor modes is actually missing before building.
- [ ] BUG-048 — placed SVG `stroke-dasharray` imports as the wrong stroke pattern.
- [ ] BUG-034 Stage 2 — implement spread for arbitrary silhouettes so canvas stops
  diverging from SVG export. Stage 1 (disclosure) is already owner-verified.

### Wave D — Sanaa becomes a companion

Order is free; none of these mutate documents.

- [ ] FEAT-051 — guided setup assistant for non-technical designers. **Research gate
  CLOSED 2026-08-25:** DXT is now `.mcpb` (CLI `@anthropic-ai/mcpb`); Claude Desktop
  ships Node, so `exp-mcp` should be ported from Swift for the bundle — a bare Mach-O
  cannot be notarization-stapled. **Blocked on one untested question:** whether a
  helper launched by Claude Desktop can reach EXP's socket inside its sandbox
  container at all, given macOS TCC protection on other apps' data. A five-minute
  probe bundle answers it; if the answer is no, this chunk becomes "make the
  copy-paste setup excellent" instead. Details in BACKLOG.
- [ ] FEAT-052 (P3) — the Sanaa avatar/character (owner-designed assets).
- [ ] FEAT-053 (P3) — capability pack / agent etiquette guide (`exp://sanaa/guide`).

### Wave E — release

- [ ] `docs/RELEASE-CHECKLIST-v2.4.md` completed end to end.

**Explicitly NOT in v2.4:** FEAT-033 (multi-point gradient on the object) stays a
research item behind its unanswered SVG/import round-trip questions; FEAT-034's
remaining Design Language surfaces, FEAT-009, FEAT-019, and the PERF queue ride
along only if a wave finishes early. Semantic component/state reconstruction
remains a v2.4+ research candidate, not a commitment.

---

## v2.3 — released (2026-08-21)

Build 14, `MARKETING_VERSION 2.3`. The release began as the whole logged backlog,
then closed at the owner-approved release boundary on 2026-08-21 after Waves 1–6
and the completed Wave 7 gradient/line work passed acceptance. The remaining
lower-priority vector/effect queue is explicitly deferred to v2.4 rather than
holding back a large, owner-verified quality release.

**Because it is one release, the internal SEQUENCE is what keeps it honest.**
Work the waves in order. Wave 1 is cross-cutting canvas/event-handling repair, and
several later items (FEAT-025 point-tool behavior, FEAT-026 point transform box,
FEAT-032 on-canvas gradient handles, FEAT-029 pencil) build directly on the input
and selection layers Wave 1 fixes. Building them first means building on sand and
re-testing everything twice.

**Wave 1 — input & event handling — ✅ COMPLETE (owner-verified 2026-08-11).**
BUG-024 first-click swallowed (`acceptsFirstMouse`), BUG-025 Option-drag duplicate
timing, BUG-026 gradient stop hit target, BUG-027 point-vs-handle tolerance,
BUG-028 tool-switch shortcut ignored, BUG-037 Shift-constrain on creation (closes
BUG-005 if the shared fix covers it). These five bugs are ~40% of the owner's list
by count and close to all of the daily friction; BUG-024 and BUG-025 are the two
to test first because both have cheap, specific hypotheses recorded.

**Wave 2 — text, layers, effects — ✅ COMPLETE, fully owner-verified 2026-08-19.**
Owner-verified: BUG-032, BUG-033, BUG-040, **BUG-030** (multi-drag, including
one-undo restore), **FEAT-024(a)**, **BUG-034 Stage 1** (spread disclosure — the
owner also confirmed the export half by finding `feMorphology radius` in the SVG),
and **FEAT-043** (line-height unit conversion + unit-aware arrow stepping, logged
from feedback during the same verification pass). BUG-031 closed as working as
designed. **BUG-029 got no code on purpose** — source reading found no defect; the
entry holds the correction and four discriminating questions instead. BUG-039
remains a watch item. Wave 3 is next. **BUG-029 is the one item that did
NOT get code, deliberately** — source reading found no defect to fix (the on-canvas
editor is a stock `NSTextView` with only `cancelOperation:` intercepted, and neither
global key route touches arrows), so the backlog entry now carries the correction and
the four discriminating questions to put to the owner instead of a speculative fix.
BUG-039 remains a watch item. Wave 3 can start once the owner has exercised the
three fixes above — BUG-030 is document-mutating and should not stack unverified.

**BUG-034 unblocked 2026-08-11, and it grew a P1 half.** The owner confirmed the
failing case is a drop shadow on TEXT, so it is not a regression against Phase 10.
But source reading found a genuine **canvas ≠ export divergence**: `EffectsRender
.Silhouette.path(spread:)` handles only rect/rounded-rect/ellipse and its own
comment states arbitrary paths ignore spread, while `ExportRenderer` emits
`<feMorphology operator="dilate|erode">` for ANY node type whenever spread is
non-zero. So spread on text shows nothing on canvas and IS applied in SVG export.
By the project's own fidelity test that outranks the missing-feature framing.
**Owner decision 2026-08-11, after pushback:** the owner initially proposed removing
spread entirely for consistency. Checking the importers showed why that was the wrong
fix — `RenderedHTMLImporter` parses CSS `box-shadow`'s fourth value, `FigmaImporter`
reads Figma's native shadow spread, and `SVGImporter` reconstructs it from
`feMorphology`. Deleting the field would not remove spread from the world; it would
make EXP silently drop it on import from all three, which is a direct hit on job #1
("read a component in accurately, losing no important data"). Stacking shadows is
also not a substitute — spread grows the silhouette BEFORE the blur, so a hard
sticker edge at blur 0 cannot be stacked, and stacking does nothing for imported
content. Resolution: consistency by ADDING, not removing. `Effect.spread` stays and
keeps round-tripping. Split accordingly: **Stage 1 in Wave 2** — a disclosure-only
change (say where spread is not yet previewed; alter no stored values, suppress no
`feMorphology`). **Stage 2 in Wave 7, now committed** — implement real spread by
dilating the alpha mask rather than offsetting glyph geometry. The trap to verify first: `feMorphology` uses a BOX structuring
element, not a circle, so a "nicer" circular dilation on canvas would re-introduce
the divergence in a subtler form. Also confirm whether raster export follows the
canvas or the SVG path, and whether inner shadows share the gap.

**Wave 3 — selection & bounds — ✅ COMPLETE, owner-verified 2026-08-19.** BUG-036(b)
whole-pixel snapping SHIPPED as its own `Snap to whole pixels` preference (owner
decision: not folded into Snap to Grid, because grid snapping also carries
layout-grid and guide snapping). **BUG-035 is FIXED** — the unified selection
transform now runs in the deepest COMMON ANCESTOR's local space instead of document
space, which is what restores handles to a group inside a group and to any
multi-selection inside a transformed group. BUG-036(a) ink bounds is IMPLEMENTED on top of it —
the selection outline, its handles and the resize math all work at ink bounds and
inset back to geometry before writing. FEAT-026's point-selection transform box was
built on this same box and owner-verified. BUG-035 missing resize/rotate handles inside
groups (confirm first whether this is the already-logged Refinement-backlog
"Nested-selection edge cases" item from Session 61 or a second bug), BUG-036
bounds excluding outside strokes + whole-pixel resize, then FEAT-026 point-selection
transform box built on the same box BUG-035 lands.

**Wave 4 — workspaces (the owner's #1 ask) — ✅ COMPLETE, owner-verified
2026-08-21.** FEAT-021 named workspace presets (Session 83) and FEAT-022 panel
side-by-side docking + pop-apart (Session 84). Cheaper than it looks: Session 79
already persists the full arrangement to `exp.workspaceLayout.v1` and `AppState
.trays` is already the model, so presets are that payload keyed by name. Do NOT
rebuild free-window magnetism — Session 80 tried it, it was choppy, and Session 82
replaced it with the tray model on purpose. This is Phase 13d and Phase 13c
deferrals (a)/(b).

**Wave 5 — type & font picker — ✅ COMPLETE, owner-verified 2026-08-21.** FEAT-008:
the owner delivered the
mockup/spec pass on 2026-08-11 (type-to-jump plus a hideable left filter rail
carrying category filters, document-scoped Fonts Used, and app-level Recent). Five
open questions were resolved 2026-08-21, then the first owner UI pass replaced the
two-group/faceted prototype with a single mutually-exclusive icon rail so scope and
category can never both be active. The header now owns Filters + its show/hide switch
and a real live Search aligned to the font names. Cached macOS font-trait categories
retain an honest Other bucket. After the owner approved this as much cleaner, the
popover also became active-display-aware: 62% of usable screen height, bounded to
480–780 points. FEAT-046 adds persistent font/size/color memory for the next text
node. The owner verified both follow-ups as much better and confirmed the final
accessibility/appearance pass green. FEAT-028 outline-on-live-text is deferred to
v2.4 with the remaining lower-priority vector work.

**Wave 6 — inspector, hierarchy & tooltips (decide the panel ONCE) — ✅ COMPLETE,
owner-verified 2026-08-21.** FEAT-010 now includes an
app-wide Compact / Standard / Large interface-type preference, visible Horizontal /
Vertical flip actions, and adaptive full-name effect fields. FEAT-035 applies one
measured high-contrast dropdown boundary (4.82:1 minimum across the recorded base
surfaces). FEAT-036 replaces Case with a named, arrow-key segmented icon control.
FEAT-023 moves Duplicate and destructive Remove into a separated actions menu and
adds context/menu-bar routes. FEAT-037's committed control inventory and shared rich
tips cover hover, focus, hoverability, persistence, and Escape dismissal; FEAT-038
adds persisted Full / Standard / Minimal visible copy without changing accessible
names or full hints. The Align-to and Distribute rows remain visibly separated. The
owner verified the visual, keyboard, VoiceOver, appearance, tooltip handoff, and
collapsed-effect behavior; the complete owner test run is green.

**Wave 7 — completed line/gradient work accepted; remaining queue deferred to
v2.4 by owner decision 2026-08-21.** FEAT-031 line caps/markers, FEAT-032
on-canvas linear-gradient geometry, and FEAT-045 selected-stop + Inspector-angle
synchronization are complete and owner-verified. The deferred queue is BUG-034 Stage 2 (alpha-mask dilation
matching `feMorphology`'s box kernel, separable running-max for speed, radius in
document points so it survives zoom, plus a golden fixture for text shadow spread),
FEAT-027 create-outlines on mixed selections, FEAT-029 pencil, FEAT-030 balanced
handles, FEAT-025 point tool moves whole objects, FEAT-028 live-text outlines, and
the remaining FEAT-034 Add-to-Design-Language surfaces. None is a v2.3 release gate.

**Explicitly NOT in v2.3 — research and parking lot.** FEAT-033 advanced freeform
gradient (no SVG/CSS equivalent exists; Illustrator rasterizes it — settle the
export contract before any UI, per the fidelity test), FEAT-039 EPS import (the
native macOS path appears to have been removed and the alternatives carry AGPL/GPL
licensing decisions that are the owner's to make — deliver a verified written
finding first), FEAT-040 data import, FEAT-041 auto-trace. None of these are
release gates; three of them start with a question rather than a design.

**Accessibility items in this release that require spec verification before code,
per WORKING-AGREEMENT → "Accessibility decisions are verified, not remembered":**
FEAT-037/FEAT-038 tooltips against WCAG 2.1 AA §1.4.13 Content on Hover or Focus
(and the standing rule that a tooltip is never an accessible name), FEAT-035
against §1.4.11 Non-text Contrast (3:1, measured and recorded, not eyeballed),
FEAT-036 against §1.4.1 Use of Color, BUG-026 against the target-size criteria, and
FEAT-008's rail against the APG pattern it adopts. Record citations in the backlog
entries and state what was NOT verified.

- [x] **FEAT-008 discovery input received 2026-08-11.** The owner's font-filter
      mockup/spec pass arrived as part of the backlog dump, closing the discovery
      gate that opened v2.3. The shipped scroll-to-current behavior stays; the
      confirmed set is type-to-jump plus a hideable filter rail carrying categories,
      Fonts Used (document-scoped), and Recent (app-level). A separate always-visible
      search field is now optional rather than assumed. This established the
      interaction/accessibility contract gate resolved by the implementation below.
- [x] **FEAT-008 implementation fully owner-verified 2026-08-21.**
      One list now supports live Search, persisted Recent, document-scoped Fonts
      Used, and one collapsible icon filter rail. All scope/category choices are one
      exclusive set, avoiding the empty-result facet trap the owner's first run made
      visible. Icon buttons have counts, hover/tooltips, arrow-key traversal, and a
      native radio-group VoiceOver representation. AppKit family classes drive cached
      categories and unknown metadata stays in Other. Full app, thumbnail, and helper
      Debug build passed. The owner verified appearance, height, filtering,
      text-tool interaction, keyboard navigation, and the live VoiceOver contract.
- [x] **FEAT-046 text-tool style memory owner-verified 2026-08-21.** The next
      point-text or dragged text box inherits the last
      concrete PostScript face, exact size, and color used while editing. The
      app-wide default persists across documents and relaunches; mixed selections
      preserve prior concrete components, and an unavailable saved face falls back
      to System. Full Debug build passed.
- [ ] **v2.3 backlog intake logged 2026-08-11 — BUG-024…BUG-037 and
      FEAT-021…FEAT-041** (35 owner-reported items) are written up in
      `docs/BACKLOG.md` with repro, hypothesis, and acceptance for each. FEAT-008
      and FEAT-010 were updated in place rather than duplicated. Work them in the
      wave order above.

- [ ] **E3 — provenance-bound code handoff/write-back (post-E2; separate scope).**
      A rendered DOM cannot identify which JSX/template/CSS/token expression should
      be rewritten. Start only where identity is explicit: `data-exp-id`, Storybook
      story id + args/argTypes, design-token names, source maps or an opt-in source
      manifest. First output is a reviewable patch/Handoff Package or GitHub branch +
      draft PR, never an automatic write to a source branch. Framework adapters for
      React/JSX, Vue SFC, modern Angular templates, Svelte, and Web Components are
      independent later work; older Angular/AngularJS adapters are phased from the
      E2c evidence rather than categorically excluded. Preserve unowned or unsupported
      source and interactive JavaScript byte-for-byte, apply only high-confidence
      bound edits, and surface three-way conflicts. Begin with safer patches—tokens,
      CSS custom properties, Storybook args, bound text/media/visibility/variant/style
      values—before structural JSX/template transforms. URL capture alone does not
      provide any of this identity.
- [ ] **Future research — semantic component/state reconstruction (v2.4+ candidate;
      not a v2.2 or v2.3 release gate).** Investigate translating related rendered
      stories and DOM states into actual EXP component definitions, nested component
      instances, and editable state override diffs. An accordion, for example, could
      expose its authored collapsed and expanded forms as named EXP states without
      turning EXP into an interaction-playback or prototyping engine. Use explicit
      evidence—Storybook stories/args/play receipts, stable source identity, framework
      metadata, and ARIA roles, states, and relationships such as `aria-expanded`,
      `aria-controls`, `aria-selected`, and `aria-checked`—rather than inventing
      variants or exercising arbitrary interactions. Existing ARIA preservation,
      component states, nested components, and provenance receipts provide useful
      foundations, but ARIA alone cannot recover source component ownership,
      conditional rendering, event wiring, transitions, or a safe inverse code edit.
      Plan this as its own research phase covering state pairing/deduplication,
      confidence and conflict handling, accessibility-preserving visual editing, and
      provenance-bound framework export adapters. Commit it to a release only after
      the evidence establishes a reversible, honest contract.

---

## Architecture decisions

- **EXP is a fidelity tool, not a prototyping tool.** Owner statement 2026-07-24,
  recorded because it settles a whole class of future arguments: *"i never set out
  to make EXP a prototyping tool... i don't think design tools should focus on
  prototyping since it's done much more efficiently in code."* EXP is ONE PIECE of
  a designer's toolkit. The job, in order:
  1. **Read a component in accurately, losing no important data.**
  2. **Export it back out at the same fidelity.**
  3. Let the designer make real design tweaks in between.
  4. Hand the result to a developer — or to a model that writes accessible
     component code from it — with the semantics intact.
  What this rules IN: anything that improves what survives a round trip. Semantic
  export, the Handoff Package, notes, ARIA roles and relationships, component
  states AS DESCRIBED VARIANTS, importer fidelity reports.
  What this rules OUT: interaction wiring, state machines, transitions, click-through
  playback, anything whose value is "watch it behave." If a feature's payoff is a
  simulation rather than an artifact someone downstream can use, it does not belong.
  Practical test when a decision is unclear: **does this make the exported artifact
  more faithful, or does it just make the canvas more impressive?** Build the first.
  This also decides structure questions. When two ways of modelling the same design
  exist, prefer the one that ROUND-TRIPS statically over the one that only makes
  sense while the tool is running it — e.g. three tabpanels with visibility
  toggling (what the DOM actually contains, exports as-is) over one panel whose
  identity changes with an active state (only meaningful inside EXP).
  Component states are HANDOFF DATA describing variants, never a playback engine.
  That distinction is the one most likely to erode; hold it.


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

#### Phase 4.1 — Nested component composition + semantic context (v2.1 / Chunk I)

Make components genuinely composable: a component source may contain instances
of other component sources as first-class children. Some recursive resolution
machinery already exists, but this phase owns the complete authoring and data
contract rather than treating nested instances as an incidental render case.

- [x] Let the Components panel, Object menu, context menu, and source editor place
      a component instance inside another component source. Show the nested source
      boundary/name in Layers and make Edit Component step into the correct source.
- [x] Add a source-dependency graph and reject direct or indirect cycles
      (`A → A`, `A → B → A`) before mutation. Deleting a referenced source must
      identify dependents and resolve them without losing work.
      **DONE; OWNER VERIFIED 2026-07-27** — the owner
      confirmed that deleting a source still appeared to remove every canvas use.
      BUG-014 found that the preserving flatten did exist, but it offset each child
      by the instance origin before putting it in a group that applied the same
      origin again. The work was present but drawn elsewhere. Children now remain
      source-local; the focused check asserts the composed canvas position so it
      cannot bless the same mistake again. The owner confirmed deletion now keeps
      every placed use visible and in position. NOT a Chunk I blocker:
      the delete is undoable and the model work below does not depend on it, so
      import and instance-path work proceeds ahead of this. Implementation: the shared graph, placement/move guards, and focused cycle
      tests shipped first. Dependent-source deletion is now closed by
      `Document.deletingComponentSource(_:)` — deleting a source deletes the
      SOURCE, not the work: every instance of it becomes an ordinary group of
      exactly what it was drawing, on the canvas, inside groups, and inside other
      sources. The owner chose this single behavior over a flatten/remove prompt
      so a destructive branch can never be picked by accident. Instances keep
      their node id, name, frame, opacity, rotation, effects, blend mode, flips,
      mask flags, relationships, and lock state; components nested below the
      deleted one survive as live instances carrying the state they displayed;
      flattened subtrees are re-identified so two uses never share ids; and
      `nestedStateOverrides` paths that ran through the dissolved instance
      re-root onto the surviving nested instance instead of being dropped.
- [x] Replace ambiguous raw descendant ids with stable **instance paths** for
      nested overrides, visibility, accessible-name sources, relationships, DOM
      ids, and import reports. Two uses of the same nested source must never share
      override identity or emitted ids.
      DESIGN SETTLED 2026-07-24 — see BACKLOG **FEAT-012** for the decision and the
      five-chunk plan (I-a path type → I-b anchored storage + migration → I-c
      authoring UI → I-d export → I-e checks). The rule: **a relationship lives at
      the nearest node containing BOTH of its ends, and addresses each end by
      instance path.** Chunk I-d is what actually closes THIS box, because
      `SemanticHTMLIdentity.nodeDOMID(_:instanceID:)` currently carries a single
      instance id and therefore collides at nesting depth 2+.
- [x] Define nested override inheritance deliberately: parent instances may expose
      selected public props from nested children; source edits flow through unless
      overridden; reset returns to the nearest source value.
      DESIGN SETTLED 2026-07-24 — see BACKLOG **FEAT-017** for the decision and the
      five-chunk plan (J-a type+storage → J-b resolution → J-c inspector →
      J-d export/handoff → J-e checks). Follows the `NestedInstanceStateOverride`
      precedent already in the model: path-addressed, stored on the OUTERMOST placed
      instance, reusing `InstanceOverride.Value` unchanged. States, auto-layout,
      bounds, clipping, thumbnails, duplicate/copy-paste, detach, SVG, semantic
      HTML, Handoff Package, and Quick Look all resolve the same tree.
- [x] Add **context-aware ARIA role authoring** from semantic containment. A parent
      List recommends/filters children toward List Item; Tab List → Tab; Menu /
      Menu Bar → Menu Item variants; Radio Group → Radio; List Box → Option;
      Tree → Tree Item; Table/Grid → Row and Cell/Header roles. Show a concise
      explanation and warn on invalid ownership without silently changing an
      authored role or inventing `aria-owns`.
      DONE 2026-07-24 (needs owner build + run): added the seven roles the rule
      set needed — Tree, Tree Item, Grid, Table Row, Table Cell, Column Header,
      Row Header — with friendly labels, blurbs, categories, and semantic-HTML
      mappings. `AriaRole.expectedChildRoles` / `requiredParentRoles` hold the
      ownership rules; `Document.containmentAdvice(forChildRole:inParentRole:)`
      advises a child from where it sits and `containmentAdvice(forSource:)`
      advises the container. Deliberately quiet by design: a parent with no
      ownership expectation, a correctly authored child, a legal-but-unrelated
      child (a decorative Group inside a List), and an empty container all
      produce NOTHING. The only warning is the case a screen reader genuinely
      mis-announces — a child whose role requires a container this parent is not.
      `radio` carries no required parent on purpose, so a lone radio is
      recommended into a Radio Group but never flagged as an error. Nothing is
      ever auto-applied and no `aria-owns` is invented.
- [x] Semantic export uses the same resolved nesting: native containment where
      possible, instance-qualified relationships, deterministic reading order,
      and structured fidelity issues for incompatible or ambiguous ownership.
- [x] Acceptance: nest one reusable component twice inside a parent, override each
      independently, edit both source levels, save/reopen, detach/export/import,
      and receive correct role recommendations with no cycles, duplicate ids,
      cross-instance override leakage, or hidden flattening. OWNER PASS 2026-07-28.

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
  - [x] **Side-by-side docking (glued columns)** ✓ Session 84 (FEAT-022) — closes
        deferral (a). A tray can hold N **columns**; connecting two tray windows
        MERGES them into one window with two columns rather than syncing two
        windows, so dragging the group and ⌘` are correct by construction. Drag a
        tray near another's facing edge → vertical insertion line; PAUSE for the
        system spring-loading delay (`com.apple.springing.delay`) → the line arms;
        release → glued. A narrow glue strip spans the shared height, carries the
        unlink button at its middle, drags the group from its body, and puts the
        column splitter in a hot zone at each of its edges. A shorter column's
        leftover area is transparent but a dead zone (owner's call — click-through
        would need a global mouse-moved monitor).
  - [ ] DEFERRED: (b) pure **drag-the-header-OUT** tear gesture (today tear-out is
        the pop-out button — drop-outside isn't catchable via SwiftUI DnD);
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
appearance setting honored; no regression in keyboard/VoiceOver. Keep the live
status blocks in `AGENTS.md` and `CLAUDE.md` synchronized when a release lane or
major phase changes. **STATUS SYNCED 2026-07-29 for v2.2/build 13.**

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
- [x] **SEMANTIC BOUNDARY (decision 2026-07-22):** do not use a Type Style
      category to mean `<h1>`…`<h6>`. Categories organize reusable visual
      treatments; heading level belongs to the individual text layer's content
      intent so meaning survives restyling and one style can be used at more than
      one level. Implementation is v2.0 B4a / Phase 19b.
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
- [x] Add lightweight **text content roles**, initially Plain text / Paragraph /
      Heading 1–6, as metadata independent from Type Styles. Export Paragraph as
      `<p>` and headings as native `<h1>`…`<h6>`; never guess a level from visual
      size, weight, layer name, or style category. This is the content-design
      counterpart to component roles. DONE 2026-07-22 in v2.0 B4a.
- [ ] Add **context-aware child-role recommendations** with v2.1 nested components
      (Chunk I): use the authored semantic parent to narrow or recommend valid
      owned roles, such as List → List Item and Tab List → Tab. Keep the designer
      in control: warn and explain; never silently rewrite a role based on visuals.
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

#### 19d — Focused in-app ARIA reference (IN PROGRESS; v2.0 foundation)

Embed the owner's searchable ARIA-role reference web app as a focused learning
surface extending the short role blurbs already shown in EXP. This is an
authoring aid, not preview/prototyping and not a general-purpose browser; its
schedule follows the companion documentation reaching a usable published state.

- [x] House the completed static guide under the existing website at
      `/aria-roles/` and expose it from the site's Learn menu. The production
      website build includes the complete exported directory. DONE 2026-07-22.
- [x] Help ▸ **ARIA Roles Guide** opens the full searchable reference in a
      resizable 1100×820 default window. Preserve the existing concise inline
      role blurbs for fast/offline use. DONE 2026-07-22.
- [ ] Add **Learn about this role…** beside role/category authoring once the
      guide's role deep-link contract is exercised in-app.
- [x] Use a dedicated `WKWebView` window or panel with no address bar and an
      allowlisted first-party documentation origin. Navigation outside that
      origin opens in the user's default browser; never accept arbitrary URLs,
      inject credentials, or expose document data to page scripts. DONE 2026-07-22.
- [x] Make network state explicit: loading progress,
      accessible failure/offline state, Retry, and Open in Browser. Do not imply
      the remote documentation is bundled or available offline. Failure copy
      identifies `expdesign.app`; no browser toolbar is added. DONE 2026-07-22.
- [ ] Accessibility/privacy acceptance: complete keyboard navigation and focus
      return to the invoking role control; VoiceOver names/status; page zoom;
      Reduce Motion/appearance compatibility owned by the reference site; no
      third-party tracking requirement or persistent session needed for lookup.
      The current export still loads React/Babel and Phosphor assets from unpkg;
      converting those to first-party/offline assets is a separate hardening task.
- [x] Keep URL/deep-link configuration out of the document schema. The focused
      window allowlists `https://expdesign.app/aria-roles/`. DONE 2026-07-22.


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
- [x] **Align/distribute on nested selections** — recursively resolves selected
      children, aligns siblings in their shared parent-local space, and lifts
      mixed-parent / Align-to-Artboard bounds into document space with inverse-
      transformed write-back through rotated or flipped ancestors. Closed during
      Figma D2 live cleanup on 2026-07-28.
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

- **2026-08-25 (pencil, second round — two fitting defects fixed, the reported
  failure NOT reproduced).** The owner drew with the tool and reported three things:
  the preview shows straight lines, sharp corners come out rounded, and one node
  "went way beyond where i drew," drawing a large loop.

  Two real defects were found and fixed in `CurveFitting`. Schneider's algorithm
  assumes smooth data, so at a genuine corner it averages the incoming and outgoing
  directions into a tangent that describes neither and nearly cancels — corners are
  now detected FIRST (3-sample direction window, 55°, minimum arm length so tremor
  does not register) and each run between them is fitted independently, meeting at an
  anchor whose two handles were fitted separately, which is the definition of a
  corner. And the least-squares solve is unbounded, which is precisely how a control
  point ends up far outside the stroke drawing a loop; handles are now clamped to
  1.5× the chord, well above what real curvature needs.

  **Neither fix is claimed to fix what the owner saw.** A standalone port of the
  fitter was run against synthetic zigzags, clean and with ±0.8pt noise and 60% speed
  variation, at four tolerances. Worst deviation stayed under 3pt and no handle
  escaped the drawn bounds by more than 3.3pt — nothing resembling the screenshot.
  The failure has not been demonstrated, so it stays open.

  The next step is deliberately data, not a third hypothesis: a `.design` file stores
  every `PathPoint`, so one saved bad stroke says whether an ANCHOR landed outside the
  stroke — impossible by construction, since every anchor is an input sample, which
  would mean the SAMPLES are wrong — or a HANDLE did, which is a fitting problem the
  clamp now bounds. Those have completely different fixes.

  Lag: the O(n) per-sample re-base of every point to a moving frame origin was
  removed; the origin only moves when the stroke extends past its own left or top
  edge, so the common case appends one point. Still unmeasured. Testing Mode's perf
  HUD is the instrument, not more guessing.

- **2026-08-25 (pencil lag — two defects in the live stroke path, fixed).** The
  owner drew with the new tool and reported lag. Neither cause was in the curve
  fitting; both were in how the in-progress stroke talked to the canvas, and both
  were mistakes of using the wrong existing funnel rather than missing machinery.

  `applyPencilPoints` called `updateNode` on every captured sample. That is the
  semantic-change funnel and it runs a full-page auto-layout reflow — its own
  comment states the rule: "live drags use withNodes directly and reflow on
  mouse-up." And `.pencilStroke` was missing from `activeDragNodeIDs()`, so
  `drawDragBlit` refused the gesture and every sample re-rendered the entire scene
  instead of compositing the stroke over the static snapshots the drag machinery
  already maintains. A pencil stroke is a node drag like any other; it now says so
  in the one place that decides.

  A third cost was considered and left alone: the O(n) point-array rebuild per
  sample. For a few hundred samples that is tens of microseconds against a page
  reflow and a full scene render, so it stays simple, with the incremental-bbox fix
  written down in case profiling ever disagrees.

  Both schemes still build clean. The fix is reasoned, not measured — if it still
  lags, Testing Mode's perf HUD names the frame cost directly, which beats another
  round of guessing.

- **2026-08-25 (FEAT-025 owner-verified; FEAT-029 pencil tool built, unverified).**
  The owner confirmed direct-select object movement — "feels natural, exactly what i
  expect to happen" — including the flagged change where pressing a different
  object now selects and drags in one gesture. Recorded as a real receipt, with a
  note that the wider regression list was not separately walked so a later session
  cannot read the sign-off as broader than it was. That is the first Wave C item
  closed.

  The pencil then landed. `Model/CurveFitting.swift` is Schneider's 1990 algorithm
  as the entry asked for by name: chord-length parameterisation, a least-squares
  solve for the two control points with endpoints and tangents fixed,
  Newton-Raphson reparameterisation when the fit is close, recursive splitting when
  it is not. Pure geometry, app-target only, testable without the app.

  One deviation from the paper is called out at the code site rather than buried:
  Schneider's `iterationError = error * error` is unit-ambiguous, because `error` is
  already being compared against a squared distance, so squaring it again means
  something different at every scale. This reparameterises when the fit is within 4×
  the tolerance in real distance. That is a judgement call, not a value from the
  paper, and it is labelled as one.

  Two defensive limits both fail LOOSE rather than wrong — a recursion ceiling that
  accepts the current fit instead of splitting forever, and a singular least-squares
  solve that falls back to Schneider's own one-third-chord heuristic instead of
  emitting inverted handles. That is the same principle BUG-053 was filed for:
  degrade visibly, never silently produce a different picture.

  The interaction decisions worth arguing with: samples are captured in DOCUMENT
  space so zoom changes only sampling density, never the drawing; the live preview
  is the raw polyline, replaced by the fitted curve on release; the node frame is
  refitted every tick because `nodeHit` uses it as a bounding-box reject and a stale
  frame makes ink unclickable mid-stroke; and the stroke closes by proximity — 12
  view points, minimum 8 samples — which is the freehand convention but is the most
  likely thing to feel wrong. Both numbers are one constant each.

  Fidelity is exposed properly rather than left a hidden default: Settings ▸ Canvas
  ▸ Pencil, a 0.5–10pt slider labelled Accurate ↔ Smooth, with a footnote saying
  which direction is which, because the word "fidelity" tells a designer nothing on
  its own. Full command coverage: tool, strip button, `N`, `@objc` action, menu item
  through `sendCanvasAction`.

  The accessibility requirement in the entry — a freehand tool cannot be the only
  way to do anything — is met structurally, not by promise: the pencil emits the
  same `PathShape` the pen does, so the keyboard-operable point tools, Inspector,
  export, and Convert to Outlines all already work on it. Pressure and tilt stay
  out, as the entry scoped them.

  Both schemes build clean, zero errors, no warnings in the new file or any edited
  range. No stroke has ever been drawn with this tool; the fitted output has never
  been looked at.

- **2026-08-25 (Wave C opened — FEAT-025 direct-select object move, code complete,
  unverified).** The owner asked for vector tools next, so the first thing today
  that adds to their verification queue. `nodeToolMouseDown`'s press-target ladder
  gains a third rung: anchor or handle wins, then a point selection on the object
  under the cursor, then — new — the object's body moves the whole object. Reaching
  the third rung is itself the proof that a point edit was not being asked for, so
  no extra "is anything selected" test was needed.

  The implementation is deliberately small because `beginSelectedNodeDrag` already
  existed and its own comment says it is shared "so Option-drag, nested movement,
  smart guides, and one-step undo remain one implementation." FEAT-025 became a
  third caller rather than a second copy. It also means a plain click still costs
  nothing: `.nodes` in `mouseUp` registers undo only `if didEdit`.

  One judgement call worth the owner's eyes: pressing a DIFFERENT object's body used
  to only switch which object the tool addressed, needing a second press to move it.
  It now switches and drags in the same gesture — Illustrator's model, and the
  removal of exactly the friction this entry was filed about, but a real change to
  existing behaviour and the most likely thing to feel wrong. Reverting it is one
  `if`.

  Two things deliberately not claimed. The entry's hypothesis also describes
  segment dragging; EXP has no segment hit-test and this did not add one, so a press
  on a bare segment falls through to the object move and segment editing stays
  unbuilt. And this is still not a fix for BUG-028 — the warning is written at the
  call site so a later reader cannot mistake one for the other.

  Debug build succeeds, zero errors, 46 warnings all pre-existing and none in the
  edited range. No pointer interaction has been exercised.

- **2026-08-25 (FEAT-051 research gate closed — and it found a possible blocker).**
  Chosen deliberately as the next piece of work because it is research: the owner is
  short on testing time, Wave A and FEAT-048 are already awaiting verification, and
  research adds nothing to that queue.

  Three findings. DXT has been renamed — `.dxt` files are now `.mcpb`, built with
  `@anthropic-ai/mcpb` (`init`/`validate`/`pack`/`sign`/`verify`/`unsign`/`info`),
  installed by double-click, drag-and-drop, or Settings ▸ Extensions. Signing is
  PKCS#7 and self-signing is supported, but the docs do not say whether signing is
  required to install, so no promise about a frictionless install should be written
  until that is seen on a real machine.

  Second: Claude Desktop ships a Node runtime, and the format strongly recommends
  Node for exactly that reason. `exp-mcp` is a ~4 KB Swift stdio↔socket relay with
  no design logic, so porting it to Node for the bundle is both easy and load-bearing
  — a bare Mach-O binary **cannot** have a notarization ticket stapled to it
  (stapling supports `.app`, `.dmg`, `.pkg` only), so a Swift helper unpacked from a
  downloaded `.mcpb` would ride on an online Gatekeeper check. The Swift helper stays
  for the already-verified Claude Code path.

  Third, and the reason this chunk is not simply "ready": it may be blocked outright.
  EXP's socket lives inside its sandbox container, and `AgentBridgeLocation` notes
  the sandbox permits AF_UNIX bind only there, so it cannot be relocated. This
  session hit the matching wall firsthand — a shell running under project automation
  was denied even `ls` on that container path, because macOS protects other apps'
  data behind TCC. Claude Code works today because the terminal has that grant; a
  child of Claude Desktop inherits Claude Desktop's, and whether that suffices is
  unknown. The entry carries a five-minute probe bundle — a `.mcpb` that does nothing
  but `stat` the socket — to be run before any FEAT-051 code. If the answer is no,
  the chunk becomes "make the copy-paste setup excellent," which is a smaller and
  more honest feature than the one currently described.

- **2026-08-25 (export fidelity fixtures written; BUG-053/054 parked by owner
  decision).** The owner is short on testing time and chose to keep v2.4 moving
  rather than stop for this, with the fix folded in later if the release allows. So
  the investigation was written down in the form it will actually be needed:
  `docs/EXPORT-FIDELITY-TEST-FIXTURES.md` is deliberately self-contained — a
  30-second refresher on what is broken, exact artboard sizes, layer positions and
  effect values to build, which exports to take, and a table of what each outcome
  means. Reading the backlog, this log, or the original diagnosis is not required to
  run it. Fixture A (~15 min) settles the reported bug; Fixture B (~15 min) is
  optional and covers BUG-054. Both entries and the v2.4 release checklist now point
  at it rather than restating the recipe in three places.

  It says plainly that a failed prediction is a good result — the diagnosis was
  already wrong once today — and it lists what the fixtures do NOT cover:
  `backgroundBlur`, stacked effects on one layer, effects inside groups or component
  instances, and effects combined with a non-normal layer blend mode. Those are
  plausible further divergences and remain untested.

- **2026-08-25 (BUG-053 re-diagnosed — the first answer was wrong, and the owner's
  observation is what corrected it).** An earlier entry today named a device-space
  blur clamp as the cause of the owner's export divergence. That was wrong. It fit
  the measurements, which is exactly why it was persuasive: light concentrated from
  the periphery into the core is equally consistent with a smaller blur radius and
  with a dropped full-artboard glow layer, and the measurement alone cannot tell
  them apart.

  The owner's own testing did. They reported that a blue layer carrying a `noise`
  (feTurbulence) effect "is not registering as color dodge," and that a hard-edged
  dark rectangle appeared matching no layer they could find. Reading for that
  specific failure instead of for a general one found it in three greps:
  `Effect.Kind` has six cases; `ExportRenderView.drawExportNode` handles three;
  and `EffectsRender.drawNoise` has exactly ONE call site in the entire app —
  `CanvasView.swift:5906`, the canvas. **PNG, JPG, and PDF export silently omit
  `noise` and `dissolve`.** The canvas renders them and the SVG exporter renders
  them, so the raster exporter is the sole dissenter — while `svgFilter`'s comment
  cheerfully claims its primitive order "mirrors the raster render exactly."

  That explains the whole picture, not just the noisy layer: a full-artboard
  color-dodge noise layer lifts the entire backdrop, so dropping it collapses the
  periphery while the core bloom survives. And the unexplained dark rectangle is
  the same bug from the other side — a layer whose `dissolve` should eat most of
  its pixels renders as the solid geometry underneath.

  The blur-space findings were split out as BUG-054 rather than deleted: they are
  real, but they now carry no confirmed symptom, and the entry says so explicitly
  so a later session does not re-credit them with this evidence. Both entries carry
  fixture tests whose predicted results confirm or kill the reading before code is
  written; neither has been run, and nothing was fixed.

  The structural lesson is the same in both: `drawExportNode` and the canvas draw
  path are separate implementations kept in sync by comment. Two effect kinds
  already fell through that gap. Adding two branches to the copy leaves the third
  free to follow.

- **2026-08-25 (BUG-053 logged and diagnosed — a performance guard is changing the
  picture).** The owner brought two side-by-side comparisons: layered low-opacity
  light-leak graphics whose PNG export does not match the canvas. Rather than guess
  between the usual suspects, the difference was measured
  (`scripts/measure_export_divergence.py`; the screenshots stay untracked on disk
  under `docs/evidence/BUG-053/`, per the repo's screenshots-are-local rule).
  Binning export values by canvas value gives spreads of ±24 to ±100, which rules
  out a colour-space, profile, or gamma cause outright — the mapping is spatial,
  not per-value. The radial luminance profile then names it: the export is 2.31×
  the canvas at the bloom centre, crosses 1.0 near radius 50, and sits at 0.34–0.57×
  beyond radius 60. Same light, smaller radius, by a factor of 2–3.

  Reading the code with that number in hand found the mechanism.
  `EffectsRender.maxShadowBlurPx = 200` is a performance guard applied in DEVICE
  space, and the canvas passes `scale: app.zoom` while export passes `scale: 1`.
  The surviving model-space blur is therefore `min(blur, 200/zoom)` on canvas and
  `min(blur, 200)` in export — identical at 100% zoom, divergent everywhere else.
  Authoring a wide bloom while zoomed out, which is how you work on a large
  artboard, is enough to trigger it, and ~45% zoom predicts the ~2.2× that was
  measured.

  Two more defects surfaced in the same family and were logged rather than folded
  in: `drawLayerBlur` multiplies a model-point blur by the backing scale but not by
  zoom while its bounds are view-space, so the canvas is self-consistent only at
  100%; and its size guards fail OPEN to drawing the content with no blur at all,
  silently, which is the likeliest reason soft glints exported as hard specks.
  Nothing was fixed — the entry carries a four-rect fixture whose predicted results
  will confirm or kill the reading before any code is written.

  Also recorded: the owner accepted FEAT-028's live-text stroke limitations, on the
  grounds that Convert to Outlines is the full-control escape hatch. That is a
  decision, not a deferral — it reframes live-text stroke as the convenient path
  rather than the complete one.

- **2026-08-25 (v2.4 scope set, then FEAT-048 built — code complete, NOTHING
  verified at runtime).** The owner chose the v2.4 shape: ship BOTH the deferred
  vector/tool queue and Sanaa, with Sanaa as the headline. The ROADMAP v2.4 section
  is now five waves with a verification gate between each — the answer to "how do
  you ship a 16–22 session release without one long unverifiable window" — and
  `docs/RELEASE-CHECKLIST-v2.4.md` carries per-wave owner acceptance gates plus the
  standing accessibility checks. Wave A stayed the owner's committed carry-in slice.

  FEAT-048, the Sanaa write-back spine, then landed. One tool, `apply_edits`, on the
  existing bridge: typed ops (createPage/createArtboard/duplicateArtboard/
  insertNodes/replaceNode/removeNodes), node fragments validated by decoding the
  real `Codable` model rather than hand-parsed, a 200-op cap, and one `setModel`
  producing one undo step named "Sanaa: <summary>". Gates: both Sanaa switches
  (default off, plain Bool defaults), plus a session-scoped per-document consent
  for anything that touches content that already exists. The tool is not even
  advertised in `tools/list` while Sanaa is off.

  Two decisions came out of writing it rather than planning it. Consent is asked
  **after** a dry run against a copy of the document, so a batch that was always
  going to fail cannot put a permission sheet in front of the designer. And the
  committed value is **rebuilt after** consent returns, because the sheet is
  asynchronous — committing the pre-sheet value would silently discard whatever the
  designer drew while it was up. `$last` / `$<op index>` references let an agent
  fill an artboard it just asked EXP to create, and double as the consent test: an
  `insertNodes` whose target is a real UUID is by definition in-place.

  **Verification status, stated plainly: none.** Debug builds are green for both
  the `EXP [design]` and `EXPThumbnail` schemes, the new file is app-target only
  against the synchronized-group exception set, and `git diff --check` is clean.
  That is the entire claim. No socket call was made, no gate was exercised, the
  consent sheet has never been drawn on screen, and no VoiceOver or
  light/dark/contrast pass has been run — this session could reach neither a
  running EXP nor its sandbox container. `scripts/verify_sanaa_write_gate.sh` runs
  the whole SANAA-PLAN §6 test-2 matrix in one command and has never been run.
  FEAT-049 must not start until it passes.

- **2026-08-25 (Sanaa planned: pen.dev research → FEAT-048…053 + docs/SANAA-PLAN.md).**
  Owner side-quest: explore pen.dev and scope a VERY optional pen.dev-style
  canvas assistant ("Sanaa," Swahili: work of art). Research finding: pen.dev's
  canvas app ships no LLM and no API keys — the user's own coding agent (Claude
  Code/Cursor/Codex) connects over MCP and draws via tools; that is exactly
  EXP's shipped F1/F2 architecture plus the still-unbuilt F3 write-back. Plan:
  Sanaa = F3 (`apply_edits`, one transactional consent-gated tool, one undo
  step per batch through `setModel`) + a presence layer (activity feed, canvas
  highlights, VoiceOver announcements) + "Ask Sanaa" prompt starters + a
  non-technical setup assistant + an optional avatar + an agent etiquette
  pack. Everything defaults OFF behind Settings ▸ Sanaa; agents reach in, EXP
  never reaches out. Owner placement decisions recorded (complete-this asks
  in-place vs duplicate-beside; variations are new artboards, same-or-new page
  is the designer's choice). Ids assigned via `verify_backlog_ids.sh`
  (FEAT-048…053, clean). Full design + per-chunk instructions and test
  scripts: `docs/SANAA-PLAN.md`. No code started — the current v2.4 slice
  stays the only in-flight mutating work pending the owner's Xcode pass.

- **2026-08-24 (Multi-Window Layers command bridge — BUG-052 fixed, needs owner
  verification).** After confirming floating-layer keyboard movement, the owner
  found Reveal in Layers no longer reached the floating panel. The failure shared a
  connection with Expand/Collapse All: `AppState` stored ignored closures installed
  by a particular `LayersPanel`, including a captured `ScrollViewProxy`. Replacing a
  dock with a tray, collapsing/reopening its section, or switching the active document
  could leave those commands aimed at a dead SwiftUI view with no state change to
  wake the live one.

  Both callbacks are now one observable, sequenced Layers-panel command request.
  Exactly one mounted Layers surface consumes it; a request issued while Reveal is
  creating or uncollapsing the panel remains pending for that new view's `onAppear`.
  Reveal now explicitly creates/activates/expands the docked panel or creates/
  uncollapses its floating tray before expanding ancestor rows and scrolling. The
  source editor consumes the same command route. Normal canvas selection keeps the
  performance decision from PERF round 8—expand ancestors when necessary, but never
  auto-scroll. Debug build succeeds; backlog-id and diff checks are green. Owner
  verification remains for hidden/collapsed/inactive tabs, mode/document switches,
  and Expand/Collapse All in docked, floating, and source Layers.

- **2026-08-24 (Multi-Window verification follow-up — BUG-050 completed across the
  window boundary; BUG-051 added and fixed, needs owner verification).** The owner
  confirmed immediate Layers-to-arrow nudge was repaired in Single-Window mode but
  still failed with floating trays. Source tracing found the precise missing half:
  `focusCanvasAction` assigned first responder inside the document window, but the
  Layers tray remained AppKit's key window, so the next arrow was still delivered to
  the tray. A Layers row selection now makes the document key before focusing its
  canvas. This preserves the one existing nudge implementation and avoids a second
  global arrow-key monitor that could collide with text fields or list navigation.

  The same two-monitor pass exposed BUG-051: tray windows were ordinary-level peers,
  so clicking an EXP document did not restore panels covered on another display even
  though Command-Tab happened to reorder the app's windows. Trays are now real
  active-app floating palettes: they stay above ordinary windows on every display
  while EXP is active and hide on deactivation, then AppKit restores them together
  for either activation route. Debug build succeeds and `git diff --check` is clean;
  the actual cross-monitor ordering, field focus, and glue behavior need
  the owner's Xcode/two-display pass.

- **2026-08-24 (v2.4 development cycle identity opened).** Advanced all four
  Xcode app/thumbnail Debug+Release configurations from public v2.3/build 14 to
  `MARKETING_VERSION 2.4` / `CURRENT_PROJECT_VERSION 15` using the repository's
  versioning helper. About, feedback, diagnostics, Handoff package metadata, and
  the agent bridge all read these generated bundle values, so development builds
  now identify themselves consistently as 2.4 (15). Historical v2.3 release notes,
  checklist receipts, appcast metadata, and public update artifacts remain frozen
  at 2.3 (14). Unsigned Debug build and built-bundle plist verification are green.

- **2026-08-24 (v2.4 owner-prioritized point bounds, buried-layer control, and
  recursive group operations — code complete, needs owner verification).** The owner
  supplied a production screenshot showing a multi-point keyboard move extending
  path ink far beyond its unchanged selection box: the stale node frame was both the
  hit-test fast reject and the basis of the effect paint bounds, explaining the
  unclickable geometry and clipped drop shadow as one bug (BUG-049). The shared path
  normalizer now runs inside every keyboard/Inspector point mutation before its one
  commit, matching the already-correct pointer close-out without adding a second undo.

  Layers pointer selection now explicitly returns first-responder ownership to that
  document's canvas, fixing immediate arrow/Shift-arrow movement (BUG-050). A new
  persistent `Auto-select` checkbox is kept visible in the Layers header and mirrored
  in View and Canvas Settings (FEAT-047). Default ON preserves direct topmost canvas
  selection. OFF leaves the Layers-panel selection authoritative and tests that
  selected geometry independently of z-order, so a buried selection can use the
  standard drag/Option-copy/snap/undo path through layers above it.

  FEAT-027 was promoted from the deferred queue at the owner's request. Convert to
  Outlines, Convert to Path, and Outline Stroke now recurse through selected group
  subtrees and mixed selections, skip ineligible descendants, preserve hierarchy and
  stored layer contracts, expose correct menu/context/Inspector enablement, and use
  one undo commit. Fill/Stroke was confirmed already recursive. The earlier backlog
  proposal for a visible partial-success summary is still open rather than being
  silently claimed. `xcodebuild` Debug for macOS with signing disabled succeeds;
  existing Swift concurrency/deprecation warnings remain, with no new compile error.

- **2026-08-21 (v2.3 released — GitHub, Sparkle, website, and update path
  verified).** v2.3/build 14 is public at tag `v2.3` with the headline
  “A faster, calmer everyday canvas.” The exported Developer ID app is universal
  (`arm64` + `x86_64`), notarized, stapled, Gatekeeper-accepted, and strict-signature
  clean across the app, thumbnail extension, helper, and Sparkle framework. The
  immutable shipping ZIP and the asset downloaded back from GitHub are byte-for-byte
  identical: SHA-256
  `b898ded3c6ba2926aaf6ef62deeecd8eba1d04eeb7a0d3c74514c47755aad36b`.

  PUBLIC/UPDATE PROOF: the production appcast serves 2.3/build 14 with the signed
  GitHub enclosure and live HTML notes. A preserved notarized v2.2/build 13 install
  found 2.3 through Check for Updates, exposed the notes through the accessibility
  tree, downloaded, installed, and relaunched successfully. About reports 2.3 (14),
  and the installed app again passes the complete release-candidate check. Local
  agent access remains off. A copied schema-3 v2.2 document opened in v2.3 and saved
  as schema 5 while preserving its page, artboard ID/name/frame, nodes, and sources.
  The release boundary remains the owner-accepted Waves 1–6 plus completed Wave 7
  line/gradient work; the explicitly deferred low-priority queue moves to v2.4.

- **2026-08-21 (v2.3 feature complete — owner acceptance green; release gate
  opened).** The owner verified the final gradient synchronization, font-picker
  VoiceOver behavior, shared Inspector polish, all tooltip verbosity/hover/focus/
  dismissal behavior, and the compact effect disclosures. Their complete test run
  is green. Waves 1–6 and the completed Wave 7 line/gradient work are accepted.
  The remaining lower-priority Wave 7 queue—BUG-034 Stage 2, FEAT-025, FEAT-027,
  FEAT-028, FEAT-029, FEAT-030, and the unfinished FEAT-034 surfaces—is explicitly
  deferred to v2.4. v2.3/build 14 is feature complete and moves to the signed,
  notarized GitHub/Sparkle/website release path in
  `docs/RELEASE-CHECKLIST-v2.3.md`.

  RELEASE PREFLIGHT: project metadata is 2.3 (14); backlog-ID, Sparkle, website,
  nested-component, relationship, page, XD, Figma, semantic HTML/Handoff, SVG-token,
  CodePen, rendered-HTML/WebKit, and Storybook checks pass. The Handoff and rendered-
  import tests had two stale schema-4 expectations; baseline/current artifact review
  proved schema 5 was the only semantic-package difference, so their reviewed receipts
  now follow the v2.3 schema. An isolated unsigned Release build succeeded for arm64
  and x86_64 across the app, thumbnail extension, helper, and Sparkle dependency.

- **2026-08-21 (Wave 6 owner-pass follow-up — tooltip handoff + collapsible effects;
  owner-verified).** The first owner pass found that a hoverable effect-field
  tooltip could physically cover the field above it. Because the child panel received
  the pointer first, that underlying control could not announce itself as the next
  target and the bubble stayed open. The shared presenter now registers every rich-tip
  control in window-content coordinates and resolves those bounds against the current
  screen position. When the pointer reaches a different registered control—even one
  underneath the tooltip panel—the old bubble closes immediately. The ordinary bridge
  delay and hoverable behavior remain when the bubble is not covering a control, so
  the WCAG 2.1 SC 1.4.13 contract is retained rather than fixing access by making the
  bubble click-through.

  Effect rows now have independent disclosure controls. A collapsed row retains the
  enable checkbox, effect-type picker, a truncated live summary of the important
  values, and the separated actions menu; clicking the summary expands the full
  editor. New/duplicated effects start expanded. Disclosure is Inspector-only state,
  so it does not alter document data, export, or undo history. The controls have
  dynamic effect-specific accessible names and explicit Expanded/Collapsed values.
  VERIFIED: full Debug build and owner acceptance. Moving directly between shadow
  fields dismisses the prior tip in time; non-control tooltip copy remains hoverable;
  shadow, blur, noise, and dissolve rows collapse/expand and retain working enable,
  type, summary, and actions controls in the one-line state.

- **2026-08-21 (Wave 4 owner-verified; gradient sync + Wave 6 implementation
  completed, subsequently owner-verified).** The owner verified FEAT-021 workspace
  presets and FEAT-022 glue/pop-apart. Wave 4 is complete.

  FEAT-045's remaining split state is closed in code: the canvas and Inspector now
  share one selected gradient-stop ID, the canvas gives the selected stop a visible
  ring, and changing the Inspector angle rotates endpoint-based gradient geometry
  about its existing midpoint while preserving line length. This fixes the concrete
  report that the angle value changed without changing the object.

  The FEAT-008 accessibility contract now has four-direction radio traversal, stable
  full names/counts, and state/result announcements. Wave 6 was implemented as one
  shared pass: scalable interface type in Settings; consistent measurable dropdown
  boundaries; icon Case segments with arrow keys; effect Duplicate/Remove separation
  plus context and Edit-menu routes; clearer Flip and shadow controls; and one rich
  tooltip presenter with Full / Standard / Minimal visible detail, focus support,
  pointer hoverability, Option reveal, and Escape dismissal. The control inventory,
  measured ratios, official criteria, and unverified experiential checks are recorded
  in `docs/ACCESSIBILITY-CONTROL-AUDIT.md`.

  VERIFIED: `git diff --check`, backlog-ID verification, and a full Debug build for
  the app, thumbnail extension, helper, and Sparkle dependency. The owner subsequently
  verified gradient angle/selected-stop sync, Case keys/state, effect actions, every
  tooltip level/interaction, all three interface type sizes, VoiceOver, keyboard,
  light/dark, and Increase Contrast. There is no automated test action configured
  for the scheme (`xcodebuild test` exits 66 before running tests); the owner reports
  their configured tests green. The remaining Wave 7 queue is deferred to v2.4.

- **2026-08-21 (FEAT-008 adaptive height + FEAT-046 text memory owner-verified).**
  The owner confirmed the taller, active-display-aware font picker and remembered
  font/size/color behavior are both much better and verified. FEAT-046 is done;
  FEAT-008's functional/UI contract is done, with only the dedicated live VoiceOver
  pass retained as an accessibility release check. The remaining v2.3 work is now
  the earlier verification queue plus the unbuilt Wave 6/7 backlog, not more font
  picker iteration.

- **2026-08-21 (FEAT-008 adaptive picker height + FEAT-046 text-tool memory;
  needs owner verification).** The owner approved the revised font picker as much
  cleaner, then identified the remaining large-monitor mismatch: a fixed 356-point
  list still forced needless scrolling. The popover now opens at 62% of the active
  display's usable height, with a 480-point floor and 780-point ceiling. The active
  window's screen is used, so moving work between a laptop and large external
  monitor changes the next opening appropriately without adding a manual size
  preference.

  New text no longer resets to System 16 pt black. `RememberedTextStyle` persists
  the last concrete PostScript face, exact size, and color at app scope; point text
  and dragged text boxes share one creation helper. Inline caret/selection changes,
  Inspector font/size/color edits, whole-text formatting, and saved Type Style
  application all feed the same memory. Mixed rich-text selections only update
  unambiguous components, and a face removed from the Mac falls back to System at
  creation instead of writing a broken font reference. VERIFIED: `git diff --check`
  and a full Debug build for app + thumbnail + helper succeed. NEEDS OWNER
  VERIFICATION: height on both small/large displays, point/box inheritance, mixed
  rich text, another document, and persistence after relaunch.

- **2026-08-21 (FEAT-008 owner-mockup UI revision — exclusive icon filters +
  live Search; needs owner verification).** The owner's first run showed that the
  two stacked radio groups were both visually unusable in a narrow rail and too easy
  to combine into zero results. The revised picker treats All Fonts, Fonts Used,
  Recent, and every font category as peer views in ONE exclusive filter set. Choosing
  one always replaces the previous filter; no disabling/intersection explanation is
  needed. This matches the single-choice pattern in Apple's Segmented Controls HIG
  and the W3C APG radio-group contract.

  The rail is now icon-only toggle buttons with count badges, semantic accent
  selection, hover states, full-name tooltips, and type-rendered S/M/ALL glyphs where
  they communicate more clearly than a generic symbol. VoiceOver receives a native
  radio-group representation with full names/counts; keyboard focus stays on the
  selected filter and Up/Down moves and selects within the group. The leading header
  cell now says Filters and owns the nearby show/hide switch. Its trailing cell is a
  real live Search field (not "type to jump" help copy), with its text aligned to the
  font-name column below and a clear action. Search results update immediately and
  result-count announcements are debounced.

  The owner does not need to export the rough vector icons for this pass: stable SF
  Symbols plus type-rendered glyphs cover the set without adding an asset pipeline.
  VERIFIED: full Debug build succeeded for app + thumbnail + helper. NEEDS OWNER
  VERIFICATION: visual proportions, icon legibility/meaning, hover + tooltip timing,
  Search alignment and filtering, filter count/selection behavior, rail show/hide,
  Up/Down traversal, and VoiceOver names/checked state/result announcements.

- **2026-08-21 (FEAT-008 font-picker navigation implemented; needs owner
  verification).** The v2.3 opening priority is now a complete testable slice.
  The existing previewed list and scroll-to-current behavior remain; a collapsible
  left rail adds one scope radio group (All / Fonts Used / Recent) and one category
  radio group whose choice filters within that scope. The hidden state keeps any
  active filter named in the header. Scope, category, and rail visibility persist.

  Fonts Used is document-scoped and walks all pages, reusable sources,
  state/instance typography overrides, and saved type styles only when the popover
  opens. Recent is an app-level, deduped 12-family MRU. Type-to-jump uses a timed,
  case/diacritic-insensitive prefix and visible feedback; the global tool-letter
  monitor yields while the picker owns typing, preventing A/F/T/etc. from changing
  tools. Every empty path explains itself and filter changes post a polite result-
  count announcement.

  Categories use cached `NSFontDescriptor.SymbolicTraits`: serif classes, sans,
  monospace, scripts/Handwriting, ornamentals/Display, and symbolic; unknown or
  missing metadata stays visible in Other. The rail uses native radio-group pickers
  after verification against the W3C APG Radio Group pattern and Apple's SwiftUI
  radio-group documentation; citations and the complete contract are recorded under
  FEAT-008 in BACKLOG.md. VERIFIED: full Debug build succeeded for the app,
  thumbnail extension, and helper. NEEDS OWNER VERIFICATION: visual sizing with the
  installed font library, type-to-jump, filter intersections/persistence, empty
  Recent, MRU order across relaunch, rail collapse with an active filter, keyboard
  traversal/arrow behavior, and VoiceOver names/focus/result announcements.

- **2026-08-21 (FEAT-031 owner-verified; browser SVG is authoritative; BUG-048
  logged separately).** The owner verified corrected arrow placement on both ends
  and reported that the SVG export renders cleanly in a browser. FEAT-031 is done.

  The same file does expose downstream compatibility differences: macOS
  Preview/Quick Look shows small transform variance, and Illustrator/Affinity do
  not reconstruct the nested transforms and SVG marker geometry faithfully. Source
  inspection found ordinary nested `<g transform>` values plus the intentional SVG
  2 marker contract; the browser matches the authored canvas. This is therefore
  recorded as a non-gating consumer-renderer/import note, not an EXP geometry
  failure and not a reason to reopen the feature.

  A separate issue surfaced during the same matrix: placed SVG
  `stroke-dasharray` is not reconstructed correctly. That one is an EXP defect and
  is now BUG-048. Source inspection already locates the gap — `SVGImporter.Style`
  has no dash/pattern field and the cascade never resolves `stroke-dasharray` — but
  no fix was folded into this verification pass. Next release work returns to the
  roadmap; BUG-048 remains independently schedulable.

- **2026-08-21 (FEAT-031 visual correction — arrow base now owns the endpoint).**
  The owner's first canvas check caught the arrowheads pointing inward from their
  authored endpoints: the initial triangle placed its point at the endpoint and
  its flat base four stroke widths inside the line. The shared Core Graphics
  builder now places the flat base centre exactly on the endpoint and projects the
  point four stroke widths outward. That one correction covers canvas, PNG, and
  PDF for both line ends and curved open-path ends. The SVG marker was reversed to
  the same base-at-`refX=0` geometry, with `auto-start-reverse` still handling the
  start side. VERIFIED: full Debug build succeeded for the app, thumbnail extension,
  and helper; `git diff --check` clean. NEEDS OWNER VERIFICATION: visually confirm
  the base sits on both endpoint handles before continuing with export comparisons.

- **2026-08-21 (FEAT-031 — line caps and independent endpoint arrows implemented;
  needs owner verification).** The final v2.3 model decision is now code. `LineShape`
  and open `PathShape` carry one whole-stroke `StrokeLineCap` (Flat / Round / Square)
  and independent `startMarker` / `endMarker` slots (None / Arrow). Their tolerant
  decoders default missing values to Round + None, so the public schema can move to
  5 without changing legacy artwork.

  The canvas and PNG/PDF exporter use one 4×-stroke-width triangular marker builder;
  open Bézier paths derive marker direction from their endpoint handles. SVG writes
  native `stroke-linecap`, `marker-start`, and `marker-end`, with `markerUnits` set
  to `strokeWidth` and `auto-start-reverse`; EXP's SVG importer restores that native
  model and approximates third-party path/polygon markers as arrows. Supported Figma
  stroke-cap/arrow values map into the same fields. Convert to Path preserves cap,
  pattern, and both markers, while painted bounds and viewport culling include the
  arrow ink.

  The Stroke inspector exposes keyboard-operable, explicitly labelled cap, Start
  marker, and End marker controls. In Edit Points, choosing a line endpoint or an
  open-path first/last anchor narrows the marker row to that selected endpoint; caps
  stay whole-stroke, matching the format contract. VERIFIED: full Debug build
  succeeded for the app, Quick Look thumbnail extension, and helper; `git diff
  --check` and backlog-id verification clean. NEEDS OWNER VERIFICATION: compare
  Flat / Round / Square on a thick line; set Start and End arrows independently;
  repeat on a curved open path; select each endpoint with Edit Points and change its
  marker; save/reopen; export PNG, PDF, and SVG and visually compare; re-import the
  SVG; and spot-check keyboard + VoiceOver labels.

- **2026-08-21 (BUG-047 owner-verified; FEAT-031 started).** The owner confirmed
  artboard-bound snapping works as intended, so BUG-047 is closed. Work continues
  with FEAT-031. The model decision is now made from the SVG 2 contract: butt,
  round, and square remain one whole-stroke cap property; arrowheads are independent
  start/end markers whose geometry scales in stroke-width units. That preserves a
  faithful SVG handoff instead of inventing a per-end cap concept the format cannot
  represent.

- **2026-08-21 (BUG-047 — artboard-bound snapping completed from both sides).** A
  tester asked for a subtle default snap to artboard bounds. The feature nominally
  existed since Phase 11, so this started as a source check rather than a second
  implementation. The gap was precise: `snapNodeOffset` only considered the board
  returned by `owningArtboard(of:)`; a layer approaching from the wall has no owner
  until it overlaps more than 50%, and at the useful flush-OUTSIDE position its
  overlap is zero. It therefore could snap after entering a board but not while
  approaching one.

  Nearby artboards now contribute edges and centres whenever they touch the moving
  selection or fall within the existing 6-screen-point threshold. The candidate
  probe is two-dimensional, so an artboard far away on screen cannot pull a layer
  merely because one x/y coordinate happens to match. When Smart Guides are enabled,
  the existing dashed line spans the matched board bound; no new preference or chrome
  was added. The moving box now goes through the same visual-bounds path as Align, so
  nested, rotated and flipped selections use what is actually visible rather than a
  parent-local stored frame.

  The pass also caught a real BUG-036(b) regression in the same gate: turning OFF
  `Snap to Whole Pixels` was being treated as `bypassSnap`, disabling ruler, grid,
  layout-grid, element and artboard snapping too even though the UI and backlog call
  them separate features. `mouseDragged` now distinguishes ⌘ (bypass everything for
  this gesture) from the pixel preference (only round to whole points).

  VERIFIED: full Debug app build succeeded; `git diff --check` clean; backlog ids
  checked. OWNER VERIFIED 2026-08-21.

- **2026-08-20 (FEAT-022, third cut — the one-window model was abandoned, and the
  owner picked the replacement).** Two cuts had merged glued panels into a single
  window with columns. The owner's second round killed it: *"the dead space is not
  going to work. because it's NOT just the narrow space between the panels, but it is
  removing access to the ENTIRETY of my screen."* Plus stranded traffic lights, plus
  only the top bar dragging.

  **Three complaints, one fault.** A merged window has to be the UNION of both
  rectangles. Two panels at different heights therefore produce a bounding box
  covering most of the screen — a huge transparent region that swallows clicks meant
  for what is behind it, one set of window buttons floating in empty space attached
  to no panel, and no drag handle anywhere near an actual panel. Chasing the symptoms
  would have meant three separate hacks against a container that was wrong.

  **The replacement: `NSWindow.addChildWindow`.** A glued group is N separate windows
  sharing a `PanelTray.groupID`. Each keeps its own size, position and close button;
  macOS moves and orders them together. No union rectangle, so no dead area to make
  click-through and nothing realigned on connect. `TrayColumn` and the whole column
  layer were deleted rather than left lying around.

  **Why this is not Session 80 coming back, stated precisely.** Session 80 moved N
  windows from our code every drag tick. Here the window server does it, and the only
  per-drag work is ONE re-parent at `windowWillMove`: the window the user grabbed is
  promoted to its group's parent so the rest follow it. `applyGrouping()` is
  idempotent because it runs on every `trays` change and `trays` changes on every
  recorded move — in steady state it must touch nothing, or we would have rebuilt the
  exact failure by accident.

  **A SwiftUI/AppKit trap worth remembering:** a `mouseDownCanMoveWindow` NSView with
  SwiftUI content drawn ON TOP of it never gets the drag — the hosting view takes the
  hit test. That is why the seam did nothing while the unlink button sitting on it
  worked fine. Move areas now sit as SIBLINGS of the controls they share space with.

  Also fixed: every tray window has a grab bar now, even a single-panel one (it used
  to appear only at 2+ panels, leaving a lone panel with no handle but the empty
  titlebar).

  **The header-drag conflict, resolved by the owner the same day:** item 6 wants any
  panel header to drag the group, but a header drag already means "move this panel to
  another tray". Their call — *"the smaller 'panel header' for moving is fine"* — so
  the grab bar and the seam move the group and the header keeps moving the panel.

  **Then it crashed, I misdiagnosed it, and it crashed again — the second read is
  the one worth carrying forward.** EXC_BAD_ACCESS code=2 at a stack address: a
  ~27,500-frame stack overflow. The trace showed `windowWillMove` →
  `promoteToGroupParent` → `applyGrouping` → `addChildWindow`, and I read it as our
  own mutual recursion (`addChildWindow` orders the window it adopts, posting its
  `willMove`). Guards went in. It crashed in the same place. **The tell I had
  skipped: the thousands of repeated frames contained none of ours.** Our recursion
  would have shown our frames.

  The real cause was a parent/child CYCLE. `applyGrouping` detached and attached in
  one pass over an unordered dictionary, so when the parent role swapped it could
  attach B to A while A was still a child of B — and AppKit recurses forever trying
  to order a cycle. Two passes now: every stale link goes before any new one is made.

  **The mid-drag re-parent was also deleted, because it was the wrong idea rather
  than a buggy one.** Handing the parent role to whichever window was grabbed meant
  re-parenting live windows during a drag, which is what made the cycle reachable at
  all. The parent is now stable for the life of the group, and a follower redirects
  its own drag: `WindowMoveArea` reports `mouseDownCanMoveWindow` only when this
  window is the one that should move, and otherwise takes the mouse and moves the
  parent itself. Still one window moved per tick.

  Rules earned: any AppKit call that moves or orders a window is heard by our own
  window delegates; and **when a stack overflow's repeated frames are all system
  frames, the recursion is in the framework — look for a structure you handed it
  that cannot terminate.**

  **Owner tested it: connecting, group-move and chaining a third panel onto a pair
  all work** (*"line, pause, snapping. no resizing or weird location jumping. A+"*).
  Two follow-ups fixed the same day.

  **Only the group's parent carried the others**, and fixing it took two goes — the
  first of which walked straight back into Session 80.

  Why the obvious fix fails: have the follower's grab bar move the parent instead of
  itself. These windows are `fullSizeContentView`, so the top strip belongs to the
  TITLEBAR and a drag there never reaches any view of ours.

  Why the second-obvious fix fails: let the follower drag itself, read its movement
  as a delta, apply it to the parent, let AppKit carry the rest. That is one window
  moved per tick — and it was still awful. Owner: *"the dragging is super laggy... the
  panels don't always move at the same pace, so if i stop before one has caught up, it
  leaves an empty space."* **The count of windows was never the point.** Session 80
  was slow because the group was animated by our code one tick behind the mouse, and
  so was this. Anything that reads a position and then writes another position
  inherits that lag no matter how few windows it touches.

  What works: `performDrag(with:)`. `TrayWindow.sendEvent` catches a left-mouse-down
  in a follower's drag regions and hands the gesture to AppKit's own window-drag loop
  running on the PARENT. The follower never moves under its own power — it moves
  because it is a child window. Zero code per tick, identical to dragging any macOS
  window by its titlebar. Intercepting in `sendEvent` instead of a view is what makes
  it cover the titlebar strip as well as our own move areas.

  **Resizing a glued window tore a gap or overlapped its neighbour.** `trayDidResize`
  slides the rest of the group by the change at whichever edge moved. Two guards keep
  the three handlers from feeding each other: a move that comes with a size change is
  not a drag, and the reflow's own window moves are not the user dragging.

  VERIFIED: builds clean. NEEDS OWNER VERIFICATION.

- **2026-08-20 (FEAT-022 rebuilt after first use — two blockers, one of them a design
  mistake, plus a silent data-loss bug found on the way).** Owner tried it and it was
  broken in the most visible way possible: *"connecting a panel/group of panels turns
  the other one into the exact same thing."*

  **Cause: duplicate column ids.** `allColumns` synthesises column 0 with
  `id: tray.id` — deliberately, so single-column trays keep working — and gluing
  DEMOTES a whole tray into a column. The merged tray therefore held two columns with
  the same UUID. `ForEach(id:)` rendered one twice, and every column-keyed hub lookup
  resolved to column 0. `PanelHub.uniqued(_:trayID:)` now runs inside `rebuilt`, so
  the invariant is enforced at the single point every write passes through instead of
  at each call site.

  **The second report was a DESIGN mistake of mine, and worth writing down as one.**
  Session 84 top-aligned the two windows on connect and left a comment arguing that
  item 2 ("vertical alignment does not matter") was about the GESTURE, not about
  refusing to tidy the result. The owner: *"connecting two panels does not honor the
  individual heights or position where they currently are."* Item 4 already settled
  it — the glue spans "the height the two panels actually SHARE", which is only a
  meaningful sentence if they may sit at different heights. `TrayColumn` gained
  `topFraction`; the merged window is now the vertical UNION of the two rects, each
  column keeps its exact on-screen rectangle, and the strip spans the INTERSECTION of
  the two spans rather than the shorter height. A spec sentence that only makes sense
  under one reading IS the decision; do not reason around it.

  **Found while fixing those, and worse than either: `PanelTray` used synthesised
  `Codable`.** Swift's synthesised decoder does NOT fall back to a `var`'s default for
  a missing key — it throws. So the first launch after Session 84 hit
  `keyNotFound(extraColumns)` on every saved tray, `loadTrays()` swallowed the error,
  and the entire saved panel arrangement reverted to the seeded default with nothing
  logged. Both `PanelTray` and `TrayColumn` now decode by hand with `decodeIfPresent`.
  **Rule: any Codable persisted to UserDefaults here needs hand-written decoding the
  moment a field is added to it** — the FEAT-021 preset payload is the next one to
  audit against this.

  VERIFIED: builds clean. NEEDS OWNER RE-VERIFICATION — chiefly that two panels of
  different heights at different vertical positions connect without moving, and that
  each column shows its own panels.

- **2026-08-20 (FEAT-022 — panels glue side by side. Wave 4 complete).** The owner
  arrived with a finished 11-point design, which unstuck an entry that had been
  circling for weeks.

  **The whole implementation hangs off refusing to take item 6 literally.** "Dragging
  the glue moves the entire group" implemented as N windows moved together IS what
  Session 80 shipped and Session 82 deleted for being choppy — it syncs N windows every
  drag tick. So connecting MERGES the two trays into ONE window with two columns.
  Every item then falls out of the window instead of being simulated across windows:
  moving the group is a native window drag (6); ⌘` sees one window because there is one
  (11); the glue strip and its unlink button are a divider view, so re-spanning and
  re-centring on resize are ordinary layout (5, 9); the column splitter is a splitter
  (7); and vertical stacking inside a column is the existing tray code, untouched (8).

  That last one is not luck. `TrayColumn` was added such that **column 0 IS the tray's
  own `panels`/`collapsed`**, so every operation written before columns existed still
  runs unchanged on an unglued tray, and old `exp.trays.v1` payloads decode as
  one-column trays with no migration.

  **Dwell is the system's, read not guessed.** The owner estimated ~1s and asked for a
  proven standard instead. macOS has one for exactly this gesture class — hold a drag
  over a target to make it act — in spring-loading: `com.apple.springing.delay`, 0.5s
  on their machine. Reading the preference rather than hardcoding means someone who
  lengthened it for motor reasons gets this gesture at their own pace, and someone who
  turned springing off gets no dwell gesture at all and still reaches the same result
  through the pop-out button and the drag-a-header-into-a-tray route.

  **The item-3 "blink" is a state change, not a flash.** A looping flash is a
  vestibular and photosensitivity hazard. Armed reads as 2pt/55% → a 6pt rounded bar at
  full opacity, no animation, no repeat — which is also why Reduce Motion needs no
  special case here.

  **The one open detail was decided by the owner, on their own condition.** Item 4's
  leftover area below a shorter column: transparent-and-click-through matches their
  sketch but needs a global mouse-moved monitor to hit-test, and this app has an
  input-to-frame budget. Their instruction was conditional — do the cursor-tracking
  hack IF it costs nothing, otherwise take the dead spot. It costs something. So the
  area is genuinely transparent (`isOpaque = false`, nothing drawn) but clicks land on
  it. No global monitor was added; the connect gesture's own end-of-drag detection is a
  30 Hz timer that exists only while two panels are near each other, reading
  `NSEvent.pressedMouseButtons`, because a native window drag runs an event loop a
  local monitor cannot be relied on to see.

  Unlink is not a second mechanism: `tearOutPanel` on a glued column's last panel
  routes to `unglue`, so the pop-out button Session 82 shipped is the unlink control.

  VERIFIED: app target builds clean. NEEDS OWNER VERIFICATION: connect from both
  sides; whether the pause threshold feels right; the **glue strip width**, which item
  7 explicitly flagged for tuning and which is one constant
  (`GlueMetric.stripWidth`, 14pt); column resize and column height-drag; unlink from a
  2- and a 3-column group; ⌘` seeing one window; and a glued arrangement surviving a
  FEAT-021 preset save/restore.

  Next: **FEAT-031** — lines / arrows / dots, and the caps-vs-markers model decision,
  the last unmade model call in v2.3.

- **2026-08-19 (workspace mode made app-wide — FEAT-021 follow-up).** Owner spotted it
  immediately: two documents open, switch one to Multi-Window, and the other stayed
  single — while still showing the checkmark on the saved preset. The checkmark was
  not the bug (presets are app-wide and should be); the MODE was, because it lived per
  document window.

  It genuinely has to be app-wide. Multi-Window has ONE shared set of floating panels
  pointed at the frontmost document, so a window left in single mode would show docked
  panels while the shared trays simultaneously claimed to serve it. The VALUE still
  lives per window — each keeps its own dock arrangement, which is correct — but the
  CHOICE now propagates: `PanelHub` keeps a weak registry of every open document's
  state, pushes a mode change to the others, and a guard flag breaks the loop each
  `didSet` would otherwise start. A document opened while the app is already in
  Multi-Window joins in that mode rather than appearing with docks.

  Owner's framing of the trade is the right one and worth keeping: single-window mode
  legitimately shows one set of panels per document window, and that difference
  between the two modes is expected rather than a wart to design away.

  VERIFIED: builds clean, `git diff --check` clean. NEEDS OWNER VERIFICATION: two
  documents open, switch modes, confirm both windows follow — including a document
  opened AFTER the switch.

- **2026-08-19 (FEAT-021 — named workspace presets. Wave 4 opened and its headline
  item shipped).** Owner jumped the queue for this deliberately: it is their #1 ask.

  **The roadmap's "cheaper than it looks" note was half right, and the missing half
  was the entire point.** Session 79 persists the docks, mode and dock visibility —
  but that is per-document `AppState`. The floating trays, and crucially their window
  FRAMES, live app-wide on `PanelHub` in a different store. A preset built from the
  first alone would have restored panel ORDER and left every window where it was,
  which is the opposite of "sick of resizing the panels back to my other monitors."
  `WorkspaceSnapshot` captures both halves.

  Both decisions the entry asked to be made deliberately were made: **switching does
  NOT auto-save the outgoing preset** (explicit Update; Photoshop's rule and the less
  surprising one), and **a preset whose monitor is gone gets clamped onto an attached
  screen** — requiring a real 80pt overlap so the grab bar is catchable, because macOS
  will otherwise strand a window with no way back.

  One thing that had to be built rather than reused: `PanelWindowManager` only ever
  OPENED and CLOSED tray windows, since in normal use frames flow the other way (the
  window moves, the delegate records it). Restoring a preset is the one case needing
  the reverse, so `applyTrayFrames()` is an explicit call rather than making reconcile
  fight the user's dragging. Command coverage is one shared `WorkspacePresetMenuItems`
  view used by both Window ▸ Workspace and the toolbar control, so the two routes
  cannot drift.

  VERIFIED: app target builds clean, `git diff --check` clean. NEEDS OWNER
  VERIFICATION, and the multi-monitor checks are the ones that matter: save a preset,
  rearrange, switch back, confirm panels return to the right SCREENS; switch between
  two presets; apply a preset for a monitor that is unplugged and confirm every window
  is still reachable; confirm presets survive relaunch; confirm rearranging after a
  switch does not quietly change the saved preset.

  **FEAT-022 (side-by-side docking within a tray) is NOT started** — it is the other
  half of Wave 4 and a genuinely bigger UI change. Next: lines / arrows / dots
  (FEAT-031's caps-vs-markers model decision). _[Superseded the same night — the
  owner delivered the FEAT-022 design and it shipped in Session 84, below.]_

- **2026-08-19 (FEAT-045 final tweak — Copy Color → Add Color to Design Language).**
  Owner, after using the menu: copying a hex only to paste it into the library was a
  step that did not need to exist. The stop menu now sends the colour straight to the
  document's Design Language, using the same `save` + `remember` pair the picker's own
  Save button uses (with `provenance: "gradient stop"`), so a colour added from the
  canvas is indistinguishable from one added anywhere else. **This also partly
  delivers FEAT-034** for this surface. It incidentally settles the Copy-Stop /
  Copy-Color redundancy noted last entry — by deletion rather than by choosing.

  Everything else in FEAT-045 is owner-confirmed. VERIFIED: builds clean,
  `git diff --check` clean.

- **2026-08-19 (FEAT-045 owner-verified, then revised twice on use).** Owner confirmed
  adding, copying and editing stops all work, and asked for two changes that turned out
  to be one idea: **paste should put the stop where the pointer is**, and — their own
  catch — that only works if the BARE LINE is right-clickable, since otherwise the
  empty stretches have nowhere to paste into. Both shipped: the line's menu is Add Stop
  Here / Paste Stop Here, a stop's menu keeps Edit / Copy Color / Copy Stop / Paste
  Stop Here / Delete Stop, and the two end knobs deliberately get no menu because they
  are not stops.

  Loose end logged rather than quietly resolved: paste no longer uses the position
  stored by Copy Stop, so Copy Stop and Copy Color now mean nearly the same thing and
  one is probably redundant. Worth deciding after real use rather than guessing now.

  VERIFIED: app target builds clean, `git diff --check` clean. NEEDS OWNER
  VERIFICATION: right-click an empty stretch of line (including where it crosses a hole
  in the shape) and paste; paste onto an existing stop and confirm it recolours rather
  than duplicating.

- **2026-08-19 (FEAT-045 — gradient stops editable on the canvas).** Owner asked
  whether click-to-add-a-stop would collide with shape points. It does not — anchors
  are node-tool only, the gradient line is select-tool only — but it DOES collide with
  dragging the shape, since a click inside a filled shape picks it up and the line runs
  through the middle of it. Owner's call: **the line wins, and the cursor carries the
  discoverability** (crosshair over the line, open hand over a knob).

  The requirement worth remembering came next: the line has to be clickable along its
  whole length *"even when there is technically nothing underneath it"* — across a hole
  in the shape or past the ink entirely — and clicking it must never deselect what you
  are editing. That reframes the line as CHROME for the selected object rather than
  part of it, which is why the hit-test is purely geometric, runs before ordinary
  picking, and returns early.

  Shipped: click the line to add a stop (in the colour already showing there, so adding
  is visually a no-op until you move or recolour it — and the same gesture continues
  as a drag, so click-and-drag places one in a single motion); click a knob to open
  that stop's editor as a popover anchored to the knob, wrapping the existing
  `ColorPopover` so the eyedropper, code field, contrast strip and "add to Design
  Language" all come along; right-click for Edit Stop…, Copy Color, Copy Stop, Paste
  Stop and Delete Stop, with Delete refused below three stops.

  `AppState.selectedGradientStopID` is the shared idea of "the" stop — it had to be
  lifted out of `PaintEditor`, where it was `@State` private to the picker. Same shape
  as BUG-038: state hidden inside a view that the thing needing it cannot see.

  **Two things deliberately NOT shipped, and logged rather than glossed:** the
  inspector's gradient bar still keeps its own selection, so panel and canvas can
  disagree about which stop is selected (wiring it means threading a binding through
  `PaintWell`, which is also used where `AppState` is not in the environment); and
  Delete/Backspace does not delete a stop, because that key currently deletes the
  SHAPE and silently changing what it destroys based on an invisible sub-selection is
  how people lose work. Copy/paste carries colour AND position at the owner's explicit
  choice, against my recommendation — recorded so a later session does not "fix" it.

  VERIFIED: app target builds clean, `git diff --check` clean, id checked with
  `scripts/verify_backlog_ids.sh`. NEEDS OWNER VERIFICATION: the cursor over the line;
  clicking the line where it crosses a HOLE in the shape (must add a stop, must not
  deselect); click-and-drag adding in one motion; the popover's eyedropper writing to
  the right stop; Delete Stop refusing at two stops; one undo per action.

- **2026-08-19 (FEAT-032 COMPLETE — on-canvas gradient handles).** Owner verified the
  export half ("export looks the same") and asked for the UI. Selecting a shape with a
  linear gradient now draws its gradient line: a knob at each end, one knob per stop
  along the line filled with that stop's own colour, white over a dark halo so it
  stays legible on any fill.

  Everything the handles author was already expressible, which is the payoff from
  doing the model first — dragging an end changes direction AND extent because the
  model stores a line, not an angle, and `settingLine` refreshes `angle` on every tick
  so the inspector's numeric field stays live and correct as you drag. That is also
  how the entry's accessibility requirement is met: the numeric route is not a
  fallback, it is the same value.

  Two details worth keeping. Shift-snapping and stop projection are BOTH done in the
  node's LOCAL POINT space rather than unit space: on a non-square shape those are not
  the same direction, so unit-space maths would snap to a different real angle on every
  aspect ratio and slide stops to the wrong place. And the line maps through
  `nodeLocalToView` / `viewToNodeLocal`, the same route the FEAT-026 point box uses, so
  rotation, flip and ancestor transforms come for free instead of gaining a second
  coordinate story.

  VERIFIED: app target builds clean, `git diff --check` clean. NEEDS OWNER
  VERIFICATION: drag both ends on a NON-SQUARE shape (the aspect cases above), drag a
  stop, Shift-drag for 15° snapping, check the inspector angle tracks live, confirm one
  undo restores a whole drag, and try it on a shape inside a rotated/flipped group.

- **2026-08-19 (FEAT-032 model + export landed; FEAT-033 unblocked by an owner
  decision).** Owner verified FEAT-026 and chose gradients next.

  **FEAT-033 no longer starts from an unanswered question.** Its blocker was that
  freeform gradients have no SVG/CSS equivalent — Illustrator rasterizes them, which
  by this project's own test made the feature suspect. The owner found the CSS
  "mesh gradient" technique (csshero.org/mesher): a solid background colour plus a
  stack of `radial-gradient(at X% Y%, hsla(…) 0px, transparent 50%)` layers. That is
  the "approximate with layered radial gradients" option the entry listed, promoted
  from a candidate to the chosen direction — and it means the fill exports as REAL
  CSS rather than a raster. Scheduled to **v2.4** by the owner. Three things still to
  verify before any UI, recorded in the entry: the SVG half, canvas performance with
  N stacked radials, and whether the layer stack can be read back IN as one editable
  fill (the harder half).

  **FEAT-032 — the model decision the entry demanded, made and implemented.**
  `GradientFill` now carries an optional `start`/`end` LINE in unit space; `nil`
  keeps the old angle behaviour, so existing documents are untouched. `angle` is kept
  in sync with the line, which is what preserves the entry's accessibility
  requirement — the numeric field stays a full, truthful route — as a property of the
  model rather than something the UI has to remember.

  **The entry said to check what SVG export emits. It was wrong, and had been.**
  `svgGradientDef` built the gradient line inside a unit SQUARE while the canvas uses
  CSS's aspect-aware construction, so on any non-square shape at any angle other than
  0/90 the exported SVG and the canvas quietly disagreed. Both now derive from one
  `unitLinearPoints(in:)`. CSS keeps the line too: `linear-gradient` cannot say
  "start 30% in", but the two lines are parallel, so projecting one onto the other
  turns offset and length into stop percentages (legal outside 0–100%) — exact, and
  byte-for-byte unchanged when there is no explicit line. `SVGImporter` also stopped
  collapsing x1/y1/x2/y2 to an angle, which had been normalising every imported
  gradient to a centred full-width sweep.

  VERIFIED: app + EXPThumbnail build clean, `git diff --check` clean. NEEDS OWNER
  VERIFICATION: export a NON-SQUARE shape with a 45° gradient to SVG and compare with
  the canvas — that is the divergence above, and it should now match; re-import an SVG
  whose gradient has a partial line; and confirm an existing document with gradients
  opens looking exactly as before.

  **START NEXT SESSION: the on-canvas gradient handles** — now purely a UI problem,
  on a model that can already express what the handles will author.

- **2026-08-19 (FEAT-026 built — Wave 3 code-complete).** Owner picked closing out
  Wave 3 while the transform-box code was fresh, which was the cheap-now choice: the
  entry had said "Blocked by BUG-035 — build on the same box," and that box was
  written the same day.

  Selecting 2+ points with the node tool now gets a transform box with eight handles
  and the usual outside-corner rotate region. The whole thing lives in the path's
  NODE-LOCAL space — the space `PathPoint.point` already uses — and maps through the
  existing `nodeLocalToView` / `viewToNodeLocal`. That is what makes it work inside
  groups and inside rotated/flipped ancestors without one new coordinate case.

  Both design questions the entry left open are now settled: control handles always
  travel with their selected anchor (already the convention in move/rotate/nudge, now
  written down), and a handle cannot be transformed on its own because `PointAddress`
  names anchors only — the data model answers it. Two details worth keeping: the box
  is PADDED outward, because a tight box puts its corner handle exactly on the extreme
  anchor and makes that anchor ungrabbable — which is also what makes it safe to
  hit-test the box before the anchors; and it is drawn DASHED so a point selection
  cannot be mistaken for an object selection.

  VERIFIED: app target builds clean, no new warnings, `git diff --check` clean.
  NEEDS OWNER VERIFICATION: two points on a straight line (the degenerate axis), a
  selection spanning two contours of an outlined glyph, rotation inside a flipped
  group turning the right way, and one undo restoring a whole gesture.

  **START NEXT SESSION:** owner verifies FEAT-026, then Wave 4 (workspaces — the
  owner's #1 ask, blocked by nothing) or the two Wave 7 MODEL decisions (FEAT-032
  gradient endpoints, FEAT-031 caps vs markers), which are the only remaining items
  that get materially more expensive the later they land.

- **2026-08-19 (owner verification sweep — BUG-036(a), BUG-041, BUG-042, FEAT-044 all
  closed).** Owner confirmed the ink selection bounds, the flipped-group bounds fix,
  align/distribute inside transformed groups, and flip buttons for a multi-selection.
  All marked DONE. **Wave 3 is now one item from complete: FEAT-026**, which its own
  entry records as "Blocked by BUG-035 — build on the same box." That block is lifted,
  and the box it should build on (common-ancestor space, ink bounds, one hit-test
  path) was written today, so it is at its cheapest right now.

  Dependency state of the rest of v2.3, for whoever picks it up: **nothing blocks
  Waves 4, 5 or 6.** Inside Wave 6, FEAT-038 is blocked by FEAT-037. Inside Wave 7,
  two items carry MODEL changes that get more expensive the later they land, because
  they touch the stored format and therefore save/open round trips, SVG+CSS export and
  four importers: FEAT-032 (`GradientFill` must store two endpoints instead of an
  angle) and FEAT-031 (line CAPS must be separated from arrow MARKERS). Those are the
  only real sequencing hazards left in the release. Note also that today's FEAT-044
  added a Flip row to the multi-selection inspector — one more row for Wave 6's
  single-pass panel rework to account for.

- **2026-08-19 (BUG-041 verified; BUG-042 + FEAT-044 found and fixed — the flip thread
  keeps paying out).** Owner confirmed the bounds fix, then found the next two things
  the same tangle was hiding.

  **BUG-042 — align/distribute inside a transformed group.** Owner: aligning several
  layers inside a flipped/rotated group clusters them somewhere meaningless, and
  *"ungrouping flips everything back and then alignment works"* — the giveaway, since
  ungrouping bakes the ancestor transform into the children. Root cause was a
  DELIBERATE decision that turns out to be wrong: `align()` used parent-local space
  for siblings, with a comment explicitly defending it "even if that group is
  rotated." The math in that space was correct — which is exactly why it survived.
  What was wrong is what the command MEANS: "Align Left" names a direction the user
  can see and its button draws a vertical bar, so inside a flipped group it did the
  literal opposite of what it showed. An affordance-honesty bug, not a geometry bug.
  Fixed by adding `selectionAncestorsAreTransformed()` to the existing `documentSpace`
  condition in both align and distribute — reusing the mixed-parent/artboard route
  that already inverse-transforms each movement on write-back, rather than adding a
  second path. Trade-off recorded in the entry so it can be reversed on evidence:
  inside a 30° group, Align Left now gives a screen-vertical line, not a group-axis
  one.

  **FEAT-044 — flip for a multi-selection.** The capability already existed:
  `flipSelection(horizontal:)` loops the whole selection in one undo step and
  `validateMenuItem` enabled it, so the Object and right-click menus worked. Only the
  INSPECTOR was missing it, which made the panel imply flipping is a single-layer
  action. Extracted `flipControls(multiple:)` and added it to the multi-selection
  inspector; single keeps the panel's scoped mutation (needed inside a component-source
  editor), multi routes through `sendCanvasAction` per the dispatch rule so there is
  still only one implementation. Worth remembering as a command-coverage lesson: the
  missing route is usually the one people actually look at.

  VERIFIED: app target builds clean, `git diff --check` clean, ids checked with
  `scripts/verify_backlog_ids.sh`. NEEDS OWNER VERIFICATION: align/distribute inside a
  flipped group and inside a rotated group; alignment OUTSIDE any transformed group
  unchanged; flip buttons on a multi-selection acting as one undo step, including in a
  source-editor window.

- **2026-08-19 (BUG-036(a) outline confirmed; BUG-041 found and fixed — flips were
  missing from the bounds math).** Owner confirmed the ink outline works, then caught
  something else with screenshots: selecting the OUTER group drew a box the right size
  in visibly the wrong PLACE, while either inner group drew a correct one. Their read
  was *"either I didn't notice this before... or this is new."*

  **It was not new and not the ink change** — checked before touching anything.
  `visualBounds` and `paintedBounds` are structurally identical apart from the stroke
  outset, so on unstroked art they return the same rect; the ink change cannot move a
  box. What changed is VISIBILITY: BUG-035 started drawing unified boxes for
  selections that previously drew none.

  Root cause: **neither bounds function handled `flipH`/`flipV`** — both only applied
  rotation. The renderer disagrees; `parentLocalToDoc` mirrors a group's children about
  the group's stored frame centre and then rotates. When a group's content union is not
  centred on that frame — normal once anything inside has moved — omitting the mirror
  shifts the bounds by twice the gap between the two centres. Right size, wrong place.
  `drawNodeSelection` already carried its own hand-rolled mirror for the per-node hint,
  which is exactly why the inner groups looked right and the outer one did not, and a
  good sign the fix belonged in the shared math. Fixed with one
  `mirrored(_:forFlipsOf:frame:)` applied in both functions after the union and before
  the rotation, matching the renderer's flip-then-rotate order.

  **Quietly also fixes align/distribute and the inspector's outer-dimension readout for
  flipped groups**, since both read these functions — worth verifying rather than
  assuming. Logged as BUG-041 (id checked with `scripts/verify_backlog_ids.sh`).
  VERIFIED: app target builds clean, `git diff --check` clean.

- **2026-08-19 (BUG-035 owner-verified; BUG-036(a) implemented — Wave 3 down to
  FEAT-026).** Owner ran their five-case matrix: all three previously-failing
  selections now show handles, and the two that already worked did not regress.
  BUG-035 DONE. They also spotted that the edge-resize CURSOR can look flipped deep
  inside repeatedly rotated/flipped groups and **explicitly chose not to log it** —
  nothing broken, rare arrangement, they will report it if it ever costs them
  function. Noted in one line in the entry only so a later session does not rediscover
  it and spend time uninvited.

  **BUG-036(a) — ink bounds, implemented as decided.** Pleasant surprise: most of the
  groundwork already existed, because `SelectionTransform.paintedBounds` and
  `strokeOutset` were written for the inspector's outer-dimension display. Added
  `unionPaintedBounds` and an `InkInsets` value (per EDGE, since a group's widest
  stroke may be on one side only) with `outset`/`inset` helpers. The accent outline
  and all eight handles — single node, nested node under a transformed ancestor, and
  the unified box — now draw at ink bounds, and all three hit-tests use the same rect,
  so grabbing a handle is never offset by the stroke width.

  The part worth remembering: **the resize math runs in INK terms and insets back to
  geometry before writing.** That is what lets the box track the cursor exactly while
  the model keeps geometry, and it works because the insets are constant for a drag —
  resizing does not change stroke width. Whole-pixel snapping is applied to the
  GEOMETRY rather than the ink, since "whole pixel" should mean the stored frame is
  whole and a stroke width may legitimately be fractional. Auto-padding bands,
  instance chrome, the path outline trace, align/distribute, export and the
  inspector's W/H all stay on geometry deliberately — they describe layout or the
  authored artifact, not paint. With no stroke every inset is zero and each path is
  byte-for-byte the old geometry math.

  VERIFIED: both targets build clean, `git diff --check` clean. NEEDS OWNER
  VERIFICATION: put a fat OUTSIDE stroke on a shape and confirm the box hugs the
  painted edge and that dragging a handle keeps it under the cursor; check a centre
  stroke; check an inside stroke changes nothing; confirm a plain unstroked shape
  resizes exactly as before. Known imprecision, recorded rather than hidden: a node
  with ASYMMETRIC insets that is ALSO rotated pivots about the ink centre rather than
  the geometry centre, so its anchored corner can drift by a fraction of the stroke
  width; uniform strokes are exact.

  **START NEXT SESSION: FEAT-026** — the point-selection transform box, built on the
  box that now exists (common-ancestor space, ink bounds, handles and hit-tests all in
  one place).

- **2026-08-19 (BUG-036(b) verified + menu state fixed; BUG-035 FIXED).** Owner
  confirmed pixel snapping works — the earlier "not responding" was an outlined-stroke
  path whose fractional numbers predated any drag — and confirmed the fix again by
  resizing. They also reported a real defect in the same change: **the menu commands
  had no checked state**, so a toggle command gave no clue what pressing it would do.
  That applied to Snap to Grid too. Both are now SwiftUI `Toggle`s, which draw a
  checkmark and, unlike a `Button`, carry a real checked state for VoiceOver; they read
  the persisted preference (a Commands scene cannot see the focused window's AppState,
  and every synced toggle writes through to UserDefaults) and still WRITE through the
  responder chain. "Show / Hide Grid" was deliberately left alone — `showGrid` is
  session state with no preference for a checkmark to read.

  **BUG-035 — fixed, and the owner's five-case matrix is now the acceptance
  checklist.** They supplied it with screenshots: one element inside a group ✓, the
  whole outer group ✓, a group inside a group ✗, multiple layers inside a group ✗,
  multiple groups inside a group ✗. That matched the source reading exactly. The fix:
  the unified selection transform now works in the deepest COMMON ANCESTOR's local
  space rather than document space (new `SelectionSpace` replacing
  `selectionTransformNodesDoc`). Inside a rotated group everything is axis-aligned
  again relative to that group, so one honest box exists and the write-back cannot
  shear. It COLLAPSES to document space whenever the shared ancestors are a pure
  translation, so every case that already worked takes the identical path — that is the
  regression guard for the two passing rows. It still refuses, visibly, when a rotated
  group sits between the common space and a selected node, because no single
  axis-aligned box is honest about that selection.

  Drawing, hit-testing and both write-backs moved into the space together, which is
  precisely why this was worth one focused pass: handles are now computed in the space
  and mapped to view, so they are hit where they are drawn; the space chain is captured
  at drag start so the math cannot change space mid-gesture; and rotation measures BOTH
  angles in the space rather than in view space, since a flipped ancestor would
  otherwise reverse the direction of the turn. The dead view-space `selectionAngle` was
  deleted. `selectionSpace` runs on every mouse-move through the hit-tests, so it walks
  with one mutable ancestor stack and copies a chain only for genuinely selected nodes.

  VERIFIED: full Debug build succeeded, no new warnings, `git diff --check` clean.
  NEEDS OWNER VERIFICATION: re-run the five-case matrix — the two previously-WORKING
  rows first, since that is where regression risk lives — then check that a handle drag
  inside a rotated group produces the geometry the handle implies, that rotating a
  multi-selection turns the right way, and that undo is one step.

  **STILL OPEN in Wave 3: BUG-036(a)** — ink bounds. Decided (ink for the visible box,
  geometry for align/export); it now sits on top of a much better foundation, since the
  box, its handles and the resize write-back already share one space. Next after that:
  FEAT-026, which was always meant to be built on this box.

- **2026-08-19 (Wave 3 opened — BUG-036(b) shipped; BUG-035 + BUG-036(a) diagnosed
  and paired).** Three decisions taken with the owner, then one fix built.

  **BUG-035 — diagnosis confirmed, and the entry's own question answered.** It is
  only PARTLY the Session 61 Refinement item, and that item is out of date: nested
  LEAF nodes were fixed at some point (`drawTransformedSelectionBox` maps handles
  through rotated/flipped chains, and `hitTestHandle` says so in its comment). Two
  gaps remain, neither about depth: `isBoxResizable` is a TYPE test that excludes
  group/instance/line, and `selectionTransformNodesDoc` refuses to engage when any
  ancestor is rotated or flipped — because it lifts frames into DOCUMENT space, and a
  doc-space non-uniform scale cannot be written back through a rotated ancestor
  without shearing. A group inside a rotated group therefore falls through to the
  type test and draws a bare outline. Owner restated the requirement behaviourally:
  *"if a group is selected inside a group, the bounds of that group. or multiple
  layers, ensure the resize and rotate handles surround all that are selected."*
  The fix written into the entry is to run the unified transform in the deepest
  COMMON ANCESTOR's local space — which `SelectionTransform`'s own doc comment
  already anticipates ("the caller chooses the shared coordinate space") — and it is
  bit-for-bit today's behaviour when nothing above the selection is transformed.
  Instances are logged as a SEPARATE question, since an instance has no size of its
  own in the model and making one handle-resizable means inventing a size override.

  **BUG-036(b) — SHIPPED.** Cause was one line: `bypassSnap` was ⌘-only, so
  whole-pixel rounding ran on every drag and had never been connected to Snap to
  Grid. Owner chose a SEPARATE `Snap to whole pixels` preference rather than reusing
  the grid toggle, since grid snapping also pulls to layout-grid columns and guides.
  Shipped as `AppState.pixelSnap` (persisted, default ON) gating that single line, so
  all twelve snap sites obey it at once, with full command coverage: an `@objc`
  action, a View-menu item on ⌥⌘' beside Snap to Grid, the Grid panel toggle, and a
  Settings default. ⌘ still bypasses for one drag.

  **BUG-036(a) — decided, not built.** Owner chose ink bounds for the visible box and
  geometry for align/distribute/export. Held back on purpose: the box and its handles
  must move together, so the resize write-back has to inset by a constant stroke
  outset — the same code BUG-035 rewrites. Pairing them avoids two conflicting edits
  to the most delicate geometry in the app.

  VERIFIED: both targets build clean, no new warnings in any touched file,
  `git diff --check` clean. NEEDS OWNER VERIFICATION: turn Snap to whole pixels off
  and confirm move/resize/draw run through fractional values and the inspector shows
  them; turn it on and confirm nothing changed from before; ⌥⌘' toggles it; ⌘ during
  a drag still bypasses either way.

  **START NEXT SESSION: BUG-035 + BUG-036(a) as ONE pass**, in the common-ancestor
  space described in the BUG-035 entry, with the stroke outset applied to the drawn
  box, its handles and the resize inset together.

- **2026-08-19 (Wave 2 CLOSED — every shipped item owner-verified).** Owner confirmed
  BUG-034 Stage 1: the disclosure note appears on a text node with a non-zero spread,
  and — unprompted — they went and found `feMorphology radius` in the SVG export,
  confirming both sides of the divergence in one pass. That is the whole argument for
  Stage 1 in miniature: the value was always going into the export, and until now the
  canvas said nothing about it. FEAT-043 confirmed in the same message. Wave 2 is
  closed with BUG-029 deliberately uncoded (see its entry) and BUG-039 still a watch
  item. **START NEXT SESSION: Wave 3 — selection & bounds.** BUG-035 first, and its
  first task is not a fix: confirm whether it is the already-logged Session 61
  "nested-selection edge cases" Refinement item or a genuinely second bug. Then
  BUG-036 (bounds excluding outside strokes + whole-pixel resize), then FEAT-026
  (point-selection transform box) built on the same box BUG-035 lands.

- **2026-08-19 (BUG-030 + FEAT-024 owner-verified; FEAT-043 logged and shipped from
  the same session).** Owner confirmed the Layers multi-selection drag, explicitly
  including one undo putting everything back, and confirmed select-all-on-entry. Both
  DONE. Working in the type inspector immediately afterwards produced a new item.

  **FEAT-043 — the line-height unit selector changed the unit and left the number.**
  Owner: 64px switched to × stayed "64", which with TextKit's `lineHeightMultiple` is
  a line box thousands of points tall. Fixed by CONVERTING: two new helpers on
  `TextContent` in `UI/Typography.swift` (`renderedLineHeightPoints` and
  `lineHeightValue(for:in:)`) sit next to `paragraphStyle(scale:)`, the code that
  defines what each unit means, so the two cannot drift; the binding reads points,
  sets the unit, writes the converted value back rounded to 3 decimals. The detail
  worth remembering: **`.multiple` divides by the font's NATURAL line height, not by
  the font size** — `NSParagraphStyle.lineHeightMultiple` multiplies the natural line
  height while CSS's unitless `line-height` multiplies the font size, and this app
  lays out through TextKit, so TextKit's definition is the one to invert. Switching TO
  Auto stays the deliberate exception, since Auto IS a value (the font's own line
  height); the authored number is preserved so switching back off Auto lands on
  exactly what Auto was drawing.

  Same entry, second half: arrow-key stepping is now unit-aware — 0.1 for × and em,
  1 for px, keeping the app-wide Shift 10× / Option 0.1× relationship. A multiplier
  lives between roughly 0.8 and 2, so whole-number steps were useless there.

  VERIFIED: full Debug builds of both the app target and EXPThumbnail succeeded
  (`Typography.swift` is shared), no new warnings in either touched file,
  `git diff --check` clean, `scripts/verify_backlog_ids.sh` run before claiming
  FEAT-043. NEEDS OWNER VERIFICATION: 64px → × → em → px round trip on large type
  with the text not moving; arrow/Shift/Option steps in each unit; and the still-open
  BUG-034 Stage 1 spread note.

- **2026-08-19 (Wave 2 finished on the code side — BUG-030, FEAT-024(a), BUG-034
  Stage 1; BUG-029 deliberately left uncoded).** Owner asked to close out Wave 2 in
  one session and settled the one decision the BUG-030 entry had reserved: a
  mixed-parent multi-selection **reparents to the drop target's parent** (Finder /
  Illustrator) rather than being refused.

  **BUG-030 — Layers multi-drag.** `handleDrop` moves a RUN of nodes now, not one.
  New `dragSet(startingAt:)` expands a drag on a selected row to the whole selection
  (a drag on an unselected row replaces the selection instead), prunes any node whose
  ancestor is also selected, and returns model order. The run is inserted with a
  single `insert(contentsOf:)` — simpler than the per-node chaining the entry
  proposed and immune to the model/display inversion that reverses node-at-a-time
  insertion. One `commitNodes`, one undo step, selection restored afterwards. Three
  sibling bugs fell out of the same shape and were fixed with it: `attach` recentres
  the run as ONE block on its union bounds (per-node centring would pile a
  multi-selection at the artboard midpoint), the artboard-section-header drop honours
  the selection, and a drop into a component instance takes the whole run
  all-or-nothing through the already-array-shaped `canInsert`. The drop delegate now
  visibly refuses a destination row that is part of the moving selection; dropping
  onto a descendant of a moving group is still refused silently, which is
  pre-existing and is recorded in the entry rather than left to be rediscovered.

  **BUG-029 — the hypothesis was wrong, and that is the finding.** The entry said the
  editor reimplements key handling. It does not: `beginEditingText` builds a stock
  `NSTextView`, and the delegate intercepts only `cancelOperation:`. No `move*`
  override exists in the project, no menu item binds an arrow key, `ToolShortcuts`'s
  monitor declines modified keys and non-letters, and `NumericStepping` is scoped to
  inspector fields. Writing key handling here would have replaced working AppKit
  behaviour with a hand-rolled version and broken alternative input methods and
  remapped bindings — the exact failure the original entry warned about. The entry now
  carries the correction plus four discriminating questions for the owner (does typing
  a letter insert or switch tools; does the BOX nudge on arrow; single line or
  multiple; non-default layout or remapper active). This is the project's
  check-the-hypothesis rule paying for itself a second time.

  **FEAT-024(a).** Entering a canvas text node's edit mode now selects its full
  contents; the dead `at viewPoint:` parameter was removed rather than left unused. A
  further click inside the live editor still places a caret, so precise edits are
  unharmed. The opening selection is announced with an explicit
  `.selectedTextChanged` accessibility post, since the range is set as part of taking
  focus — NOT yet verified with VoiceOver running.

  **BUG-034 Stage 1 — disclosure only, nothing stored or exported changed.** Added
  `EffectsRender.previewsSpread(_:)` next to `Silhouette.path(spread:)` so the UI's
  claim cannot drift from the renderer; the Spread field's detail text now states
  where spread is and is not previewed and that export still applies it; and an
  `info.circle` note appears under the row only when a non-zero spread sits on a node
  whose canvas preview ignores it. Text carries the message, not colour (WCAG 2.1 AA
  §1.4.1); the note reuses the existing tertiary caption token and that token's
  contrast was NOT re-measured.

  **VERIFIED:** full Debug builds of BOTH the app target and EXPThumbnail succeeded
  (`EffectsRender.swift` is shared with the extension), no new warnings in any touched
  file, `git diff --check` clean. **NEEDS OWNER VERIFICATION:** drag a non-contiguous
  Layers multi-selection and check it lands contiguous and in order; drag a selection
  spanning a group and the wall and check nothing jumps position; one undo restores
  the whole move; drag several rows onto an artboard section header; double-click a
  text node and confirm the contents come up selected and a further click still
  places a caret; put a non-zero spread on a text node and confirm the note appears.

  **START NEXT SESSION:** owner verification of the three fixes above, then the
  BUG-029 questions, then **Wave 3 — selection & bounds** (BUG-035 handles inside
  groups, first confirming whether it is the Session 61 nested-selection item or a
  second bug; BUG-036 bounds excluding outside strokes; then FEAT-026 built on the
  same box).

- **2026-08-16 (BUG-033 + BUG-040 owner-verified; next-session handoff).** Owner
  confirmed both fixes: Unlock is now reachable by right-clicking the locked object
  directly on the wall, and the reported PNG no longer cycles blurry/sharp or drives
  excessive idle CPU. BUG-033 and BUG-040 are DONE.

  **START NEXT SESSION: BUG-030 — drag a Layers multi-selection as one ordered,
  undoable block.** Begin by locking the entry's four behavior decisions before
  editing `handleDrop`: dragging a selected row moves the full selection; dragging an
  unselected row replaces the selection and moves only that row; preserve relative
  visual order despite the model/list inversion; and define/refuse ambiguous mixed-
  parent or nested selections visibly. Then restructure the drop into one mutation
  and one undo step. This is the largest remaining Wave 2 daily-friction bug and was
  deliberately reserved for a fresh session.

- **2026-08-16 (BUG-033 canvas coverage + BUG-040 idle PNG decode loop fixed).**
  Owner clarified the missing Unlock was on a locked item directly on the canvas,
  not its Layers row. The context menu already had Unlock, but ordinary hit-testing
  correctly excluded locked nodes, making the command unreachable from the wall.
  Added a context-only lock-aware hit path: a locked object now offers Reveal in
  Layers + Unlock while normal clicks still pass through it; locked groups do not
  expose their children through the lock. The same report uncovered BUG-040: a PNG
  cycled blurry/sharp at rest while EXP used excessive CPU. Root cause was an exact
  mip being evicted from `NSCache`, falling back to 256px, asynchronously decoding,
  redrawing, and being evicted again in a self-sustaining loop. The latest full
  render now strongly retains the exact/fallback mips it uses, prunes them when no
  longer visible, and clamps bucket requests to the source PNG's pixel size so 4K/8K
  keys cannot duplicate one smaller bitmap. VERIFIED: full Debug app build succeeded;
  `git diff --check` passed. NEEDS OWNER VERIFICATION: right-click a locked canvas
  item; then leave the reported PNG visible and confirm it stays sharp and Activity
  Monitor CPU settles.

- **2026-08-16 (owner verification sweep — BUG-032, FEAT-004, and FEAT-020
  closed).** Owner confirmed that grouping no longer jumps to the top of the layer
  stack, 1% zoom-out works, and contextual Select All Artboards followed by Clean Up
  works well. Marked all three done. The same build also visually confirms FEAT-010's
  first Noise/Dissolve precision-field slice works much better; the broader inspector
  responsiveness/hierarchy item remains in progress. No source changes in this pass.

- **2026-08-16 (FEAT-010 first slice — precision fields use the panel width).**
  Owner supplied a screenshot of the Noise/Dissolve Advanced row and asked for labels
  above multi-column fields so precision values remain readable. Confirmed the exact
  cause in `MainWindow.swift`: Frequency/Octaves/Seed inherited the shadow row's fixed
  40pt fields, and Frequency formatted only two decimals. Rebuilt that Advanced area
  as two flexible columns with full labels above, monospaced digits, a three-decimal
  Frequency display, minimum 0.001, and precision-aware arrow stepping (0.01 normally,
  0.001 with Option). The reusable stepping modifier now accepts a base step; all
  existing call sites retain their old defaults. VoiceOver keeps one full field label
  rather than reading the new visible label twice. VERIFIED: full Debug app build with
  `xcodebuild` succeeded and `git diff --check` passed. NOT verified: the owner has not
  yet inspected the layout at default/narrow/wide panel widths or with VoiceOver and
  appearance variants. FEAT-010 remains open; this is its first concrete slice, not
  the broader inspector/hierarchy pass.

- **2026-08-11 (SESSION CLOSE — v2.3 intake + Wave 1 complete + Wave 2 started).**
  Whole-session summary, written so the next session can resume cold.

  **Shipped and owner-verified (7):** BUG-025 Option-drag latched at mouseDown;
  BUG-026 gradient end-stop markers drawn outside the gesture hit-rect; BUG-027 anchor
  owning its whole grab radius; BUG-028 tool letters unreachable from panel focus
  (Tools menu + central `ToolShortcuts` monitor); BUG-037 Shift not constraining new
  shapes/frames; BUG-038 opacity digits swallowing characters typed into layer names.
  BUG-024 closed as a duplicate of BUG-025; BUG-031 closed as working-as-designed.

  **Written, awaiting owner build (2):** BUG-032 group z-position on creation;
  BUG-033 Lock/Unlock in the Layers context menu.

  **Backlog state:** 35 owner-reported items logged at intake as BUG-024…BUG-037 and
  FEAT-021…FEAT-041, plus BUG-038 and BUG-039 found during the work. FEAT-008 and
  FEAT-010 updated in place. `scripts/verify_backlog_ids.sh` added after a PERF-005
  collision was found live across four files; PERF-005/006 renumbered by first claim.

  **What this session should be remembered for, beyond the fixes.** Every hypothesis
  written at intake was checked against source before any code was written, and that
  step repeatedly paid: BUG-024 had no bug at all (`acceptsFirstMouse` was already
  correct), BUG-026 was hit-rect geometry rather than a tolerance value, BUG-033's menu
  entry had simply never existed, BUG-031 was correct behaviour, and BUG-038 was a
  regression from BUG-020's own fix that nobody had connected to the symptom. Four
  hypotheses were wrong. None shipped. The durable lesson, recorded in BUG-024:
  after-the-fact symptom reports are good at locating the FILE and unreliable at
  identifying the CAUSE, so log the observation and mark the hypothesis AS a hypothesis
  — a confident-sounding guess in a backlog entry is something a later session will
  implement.

  **RESUME HERE, in this order:**
  1. **Owner builds BUG-032 + BUG-033** and reports. Group should keep its top-most
     member's z-position; right-clicking a locked layer should offer an enabled Unlock.
  2. **BUG-030 — Layers multi-selection drag.** The biggest remaining Wave 2 item and
     the one the owner called "pretty big." Deliberately not started at the tail of a
     long session: `handleDrop` is the panel's most intricate function (parent-offset
     conversion, artboard attachment, drop-into-group vs drop-into-source, and
     `insertSibling`'s `afterInModel:` inversion). Four design decisions are already
     written into the entry — settle those first, then restructure to accumulate into
     one `nodes` array and commit once. Start fresh, with room.
  3. **BUG-029 — confirm before coding.** The owner said "all the editing key bugs are
     fixed," but NO BUG-029 code was ever written, so either something else masked it
     or the specific behaviours were never re-tested. Check each explicitly on canvas
     text: up/down to line start/end, Shift+arrow by character, Option+arrow by word,
     Command+arrow by line/document, and the Shift-extended forms. Close it or fix it —
     do not leave it ambiguous.
  4. **BUG-039 — watch only.** Capture the one discriminating observation in the entry
     (canvas new order + panel old order = stale view; both old = dropped mutation).
     No fix before that exists.
  5. Then the rest of Wave 2: BUG-034 Stage 1 (spread DISCLOSURE only — alter no stored
     values, suppress no `feMorphology`), FEAT-024.

  NOT verified anywhere in this session: no Swift was compiled or run by Claude. Every
  fix was owner-built and owner-confirmed, per WORKING-AGREEMENT.

- **2026-08-11 (BUG-031 closed as working-as-designed; BUG-039 opened as a watch
  item).** Owner ran the discriminating test and confirmed the per-parent z-order
  scoping is right: *"something outside a group would just skip over the group;
  something in the group goes within that group. Exactly what it should be doing."*
  BUG-031 is CLOSED. Deliberately did NOT build the feedback affordance that was
  proposed for it — once the scoping was understood the owner had no complaint, so
  adding a notice would have solved a problem that turned out not to exist.
  Spun the one loose thread into **BUG-039** rather than letting it go: a text layer
  briefly refused to reorder, then started working again. Logged precisely because "it
  fixed itself" is the signature of a STALENESS bug — transient misbehaviour that
  resolves untouched usually means the model was right and something downstream had not
  caught up. Leading hypothesis is a stale Layers panel rather than a dropped mutation,
  which fits the earlier SwiftUI panel-performance findings and the `resolveGeneration`
  invalidation invariants, and fits the owner's suspicion about deep nesting. Recorded
  ONE discriminating observation for next time — does the CANVAS show the new order
  while the panel shows the old? — because the two answers lead to opposite files, and
  explicitly instructed against guessing a fix before that observation exists.
  **NEXT:** owner watches for BUG-039 and builds BUG-032/033. Remaining Wave 2:
  BUG-030 as its own focused pass (the `handleDrop` restructure), BUG-034 Stage 1
  (spread disclosure), FEAT-024 (select-all on entry), and BUG-029, which still needs
  its specific behaviours confirmed since no BUG-029 code was ever written.

- **2026-08-11 (BUG-031 re-investigated: not a logic bug, and my tab hypothesis was
  wrong).** Owner tested and reported that ⇧⌘[ and ⇧⌘] BOTH work on a multi-selection,
  which kills the macOS-window-tabbing hypothesis outright and also means the original
  BUG-031 symptom does not reproduce. What they hit instead was intermittent: stepping
  down stopped working, stepping up worked, and after reselecting "only one moved."
  Their own guess — that it cannot jump over a group in bulk — pointed at the right
  function. Read `reorderInParents` (`CanvasView.swift:2883`): it applies the reorder
  to EVERY parent array containing a selected node, independently — top level, and
  each group's children. Deliberate, and matches Illustrator, where z-order is scoped
  to the containing group. But the Layers panel presents one flat-looking list, so the
  scoping is invisible, and it produces exactly the two reported effects: a selection
  spanning a group boundary moves per-parent (so only some rows appear to shift), and a
  selection already at the back makes Send Backward a correct no-op that is
  indistinguishable from a dead key. Traced `nudgeOrder`'s swap loops by hand for
  contiguous, non-contiguous and already-at-extreme selections in both directions —
  correct in every case. So the fix is almost certainly FEEDBACK, not logic; moving a
  selection across parent boundaries would mean reparenting layers on a ⌘[ press, which
  is worse than the confusion. Did NOT code anything: a verbal recount cannot separate
  "per-parent scoping" from "already at the extreme," so a discriminating test is
  recorded in the entry for the owner to run first, and the feedback design is a
  decision to make deliberately rather than guess.
  Third wrong hypothesis of the session, all three caught by reading source or by owner
  testing rather than by shipping. Worth noting the pattern in this backlog: symptoms
  reported after the fact are consistently better at locating the FILE than at
  identifying the CAUSE.
  **NEXT:** owner runs the three-part BUG-031 test, and builds BUG-032/033 from the
  previous entry. BUG-030 still awaits its own focused pass. BUG-029 still needs
  explicit confirmation of its specific behaviours before being closed.

- **2026-08-11 (Wave 2 opened: BUG-032 and BUG-033 fixed; BUG-030 and BUG-031
  investigated and deliberately not coded).** Took the layers cluster.
  **BUG-032 fixed:** `group()` ended both branches in `append`, and later-in-array is
  higher z, so a new group always jumped to the top. It now inserts at the z-position
  of its top-most member. The cross-parent branch is partial by design — it anchors
  only on a top-most TOP-LEVEL selected node and keeps the old append when every
  selected node is nested; recorded in the entry rather than left to be discovered.
  **BUG-033 fixed, and the entry's hypothesis was wrong:** `contextMenuEntries` had no
  lock item at all — not a disabled one, none — so this was never about a menu built
  from an "is editable" test. Added Lock/Unlock reusing the row's `onToggleLock`,
  always enabled including on locked rows. Multi-selection and a menu-bar equivalent
  are NOT done and are flagged for the Wave 6 menu pass.
  **BUG-031: the entry's hypothesis is wrong and the cause is probably not our code.**
  `reorderSelection(toFront:)` already moves the selection as an ordered block. The
  asymmetry the owner reported — plain ⌘[/⌘] work, ⇧⌘[/⇧⌘] do not — cannot be
  explained by anything in the reorder path, but IS explained by macOS claiming ⇧⌘[
  and ⇧⌘] as Show Previous/Next Tab, which `DocumentGroup` opts into automatically.
  Left uncoded pending verification, because if that is right the fix is a product
  decision (disable automatic window tabbing for everyone, or move EXP's shortcut),
  not a bug fix.
  **BUG-030 investigated, fix deliberately deferred.** Confirmed the cause — `.onDrag`
  carries one id and `handleDrop` moves exactly one node. Did NOT restructure it:
  `handleDrop` is the panel's most intricate function (parent-offset conversion,
  artboard attachment, drop-into-group vs drop-into-source, and `insertSibling`'s
  `afterInModel:` inversion where visual order is the reverse of model order). Making
  it move N nodes as one undoable block is a real restructure of document-mutating
  code that cannot be compiled or run here, and the owner already flagged it as
  "pretty big." Recorded the four design decisions to settle first rather than
  guessing at them.
  NOT verified: nothing compiled or run.
  **NEXT:** owner builds BUG-032/033, and checks the Window menu for "Show Next Tab"
  with ⇧⌘] to confirm or kill the BUG-031 hypothesis. Then BUG-030 as its own focused
  pass. Still open in Wave 2: BUG-029 (text caret/selection keys) — owner said on
  2026-08-11 that "all the editing key bugs are fixed", but no BUG-029 code was ever
  touched, so its specific behaviours need explicit confirmation before it is closed.

- **2026-08-11 (WAVE 1 COMPLETE — six bugs fixed and owner-verified, one closed as a
  duplicate).** Owner confirmed the tool shortcuts and, crucially, could no longer
  reproduce the original complaint at all: *"I can't seem to get close to that feeling
  of the tools not responding. So I think we got it."* Wave 1 closes.
  Shipped and verified: **BUG-025** (Option latched at mouseDown → deferred and
  sampled live), **BUG-026** (gradient end-stop markers drawn half outside the
  gesture's hit rect; also width-relative tolerance and grab-teleport),
  **BUG-027** (anchor owned its whole 12pt radius → arbitration with a 3pt bias),
  **BUG-037** (`.draw`/`.drawArtboard` never consulted Shift), **BUG-038** (regression
  found mid-wave: BUG-020's opacity digits swallowed numbers typed into layer names),
  **BUG-028** (tool letters unreachable from panel focus → Tools menu + one central
  `ToolShortcuts` monitor). **BUG-024 closed as a DUPLICATE of BUG-025.**
  Two process notes worth carrying forward, both from getting things wrong:
  1. **BUG-024 should never have been a separate entry.** One owner report was split
     into two bugs on the strength of a guessed cause, and the guess was wrong about
     both the split and the mechanism (`acceptsFirstMouse` was already correct at
     `CanvasView.swift:149`). Worse, the guess was written into the backlog in the
     register of a finding, where a later session could have implemented it. Log the
     observation; mark the hypothesis as a hypothesis.
  2. **Three of the six root causes were NOT what the entry predicted** — BUG-026 was
     a hit-rect geometry bug rather than a tolerance value, BUG-024 had no bug at all,
     and BUG-038 was a regression from a previous fix that nobody had connected to the
     symptom. Reading the source before writing code caught all three. That step is
     load-bearing, not ceremony.
  NOT verified: nothing in this wave was compiled or run by Claude; every fix was
  owner-built and owner-confirmed, per WORKING-AGREEMENT.
  **NEXT:** Wave 2 — BUG-030/031/032/033 (layers panel) taken as one pass together
  with the BUG-038 focus-boundary audit of `onDeleteCommand`/`onMoveCommand`, since
  that is the same file; then BUG-029 (text caret/selection keys) with FEAT-024
  (select-all on entry); then BUG-034 Stage 1 (spread disclosure, alters no stored
  values).

- **2026-08-11 (BUG-038 verified; BUG-028 closed out — Wave 1 complete pending
  builds).** Owner confirmed the rename fix — *"numbered layers, objects. Opacity
  still works."* BUG-038 is DONE. Finished BUG-028's remaining half with the approach
  that bug had just settled on evidence. Both earlier candidates were disqualified:
  menu key equivalents cannot ask whether the user is typing, because the main menu is
  offered equivalents before the event reaches the first responder; and per-panel
  `.onKeyPress` is the route BUG-020 took, which is exactly what produced BUG-038.
  Implemented the third option — `ToolShortcuts`, one local `NSEvent` key monitor in
  `MainWindow.swift`, installed from `EXP__design_App.init()` before any view renders.
  It declines on ⌘/⌃/⌥, declines while `isTypingInTextField()`, and declines when the
  first responder is the canvas, so the existing canvas-focus path is untouched and
  this can only ADD the missing routes. ⇧A keeps the Artboard alias; unanswered events
  pass through rather than being eaten. Accepted one wart deliberately and recorded
  why: with Settings or the ARIA guide key, a tool letter still reaches the document
  via `sendCanvasAction`'s main-window fallback. A "key window must host a canvas"
  guard would close it but would also break floating panel trays — the very case
  BUG-028 is about — so the fallback stays.
  **Wave 1 is now complete pending owner builds**, except BUG-024, which is waiting on
  a repro that does not involve Option-drag and should be closed as a duplicate of
  BUG-025 if none appears.
  NOT verified: nothing compiled or run.
  **NEXT:** owner builds and tests tool letters from Layers focus, from a floating
  tray, and confirms typing still works everywhere. Then Wave 2 opens: BUG-029 (text
  caret/selection keys) with FEAT-024 (select-all on entry), BUG-030/031/032/033
  (layers panel), and BUG-034 Stage 1 (spread disclosure only). The
  focus-boundary audit from BUG-038 — Layers `onDeleteCommand` and `onMoveCommand` —
  should be folded into the Wave 2 layers work.

- **2026-08-11 (BUG-038 found and fixed — and it settles BUG-028 on evidence).**
  While the tool-shortcut hazard was being explained, the owner recalled a bug they had
  hit: *"I couldn't add a number in a layer or object name"* — typing a digit while
  renaming changed the layer's OPACITY instead of entering the character, so layers
  could not be named "Button 2". Root cause confirmed: BUG-020's own fix. That fix
  handled opacity digits at the Layers focus boundary with `.onKeyPress` on the List,
  returning `.handled` for every unmodified digit — but the rename field's `editing`
  flag is `@State` inside the ROW (`LayersPanel.swift:1486`) while the handler sits on
  the CONTAINER (`:231`), so the container could not know a field was open. A
  focus-boundary shortcut that forgot text entry is also a focus state. Fixed with a
  shared `isTypingInTextField()` in `MainWindow.swift`, which asks AppKit for the key
  window's real first responder and checks the FIELD EDITOR as well as `NSTextField` —
  AppKit installs a shared `NSTextView` field editor rather than making the field
  itself first responder, so the naive check would have missed the actual case.
  **This retires the open BUG-028 question.** It is precisely the failure mode
  predicted for unmodified key equivalents, except already shipped and in the owner's
  hands, which makes the concern empirical rather than theoretical. It also
  DISQUALIFIES the per-panel option that was on the table: BUG-020 took that route and
  produced this regression. Whatever fixes the tool letters must use the same
  first-responder guard, and one central local key monitor is now the clear choice
  over repeating the pattern per panel.
  NOT audited: the other focus-boundary handlers in the Layers panel
  (`onDeleteCommand`, `onMoveCommand`) may carry the same assumption. `NumericStepping`
  was checked and is safe — arrow keys only. Logged as follow-up in the entry.
  NOT verified: nothing compiled or run.
  **NEXT:** owner builds and confirms renaming with digits, plus the Tools menu. Then
  the tool-letter monitor using `isTypingInTextField()`, and the remaining
  focus-boundary audit.

- **2026-08-11 (Wave 1: BUG-026/027/037 verified; BUG-028 half-fixed, half is an
  owner decision).** Owner built and confirmed all three — *"much smoother. Shift draw
  is great. Gradient fixed, and curve handle, perfect."* BUG-026, BUG-027 and BUG-037
  are DONE.
  **BUG-028 root cause confirmed:** tool letters are handled in
  `CanvasNSView.keyDown` (`CanvasView.swift:6419`), which only runs when the canvas
  holds focus, so with focus in a panel or floating tray the key never arrives — the
  same responder-chain boundary as BUG-016 and BUG-020. Fixed the REACHABILITY half:
  a new `Tools` menu plus ten `@objc` tool actions routed through `sendCanvasAction`,
  so any tool can be selected from any focus location. That is what the
  command-coverage rule wanted regardless, and the tools strip is no longer the only
  route. No `validateMenuItem` cases were added because a tool is never unavailable;
  recorded as a decision so it does not read as an oversight.
  **Deliberately did NOT finish the shortcut half.** The obvious move — put the letter
  key equivalents on the new menu items — is probably actively harmful: the main menu
  is offered key equivalents BEFORE the event reaches the window's first responder, so
  an unmodified letter would likely fire while the user is typing and swallow the
  character. Handling them in `keyDown` is exactly why typing works today, and that
  correct behaviour is also what made BUG-028 possible. The precise AppKit arbitration
  between a plain-letter menu equivalent and an active field editor was NOT verified,
  and the failure mode if it is wrong is "no letter can be typed anywhere," which is
  far worse than the bug. Logged the safer alternative for evaluation: one local
  `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` that handles tool letters only
  when the first responder is not a text-editing view. Raised to the owner rather than
  chosen unilaterally.
  NOT verified: nothing compiled or run.
  **NEXT:** owner builds and confirms the Tools menu, and decides the shortcut
  approach. Then Wave 1 closes pending a non-Option-drag repro for BUG-024, and Wave 2
  opens (BUG-029 text keys, BUG-030/031/032/033 layers, BUG-034 Stage 1, FEAT-024).

- **2026-08-11 (Wave 1 continued: BUG-025 verified; BUG-026, BUG-027, BUG-037
  fixed).** Owner built and confirmed the Option-drag fix — *"feels much smoother and
  less picky, exactly what I'm expecting to happen"* — so BUG-025 is DONE. Continued
  through Wave 1; all three of the next fixes had their root cause confirmed in source
  first, and one of them was not what the entry predicted.
  **BUG-026 (gradient stops) was not a tolerance problem.** In `PaintEditor.GradientBar`,
  markers were centred at `position * w` and offset by -7, so the stops at 0.0 and 1.0 —
  which every gradient has by default — hung HALF OUTSIDE the bar. The gesture's
  `.contentShape(Rectangle())` limits hit-testing to that rect, so the overhanging half
  was visible but not clickable: clicking the outer half of an end stop did nothing,
  clicking inward worked. That is exactly "active slightly off-centre of the actual
  circle." Two further bugs sat in the same lines: tolerance was 0.05 in NORMALISED
  units, so grab difficulty silently tracked panel width, and `setPosition` ran on the
  first `onChanged`, teleporting a stop under the cursor when grabbed off-centre. Fixed
  by insetting the track by the marker radius, expressing tolerance in points (12pt =
  a 24pt target per WCAG 2.2 §2.5.8, visual size unchanged at 14pt), and recording a
  grab offset for relative dragging. **NOT fixed and explicitly left open:** keyboard
  cannot reach or select individual stops, so the control is still not keyboard
  operable — logged in the entry rather than quietly folded into "done."
  **BUG-027 (point tolerance):** `hitTestPathPoint` returned the instant any anchor
  fell inside the 12pt grab radius, before the handle loop ran, so the anchor owned
  that radius outright. Replaced the early return with an arbitration — anchor wins
  when `anchorDist <= handleDist + 3pt`, converted by zoom like `grab` — which keeps
  the original intent (a collapsed handle must not steal the anchor's click) while
  making a nearby handle reachable at 100%.
  **BUG-037 (Shift constrain):** confirmed the `.draw` and `.drawArtboard` cases never
  consulted `shift`. Added a shared `squared(from:to:)` applied before the pixel snap,
  sampled live so Shift works mid-draw. BUG-005 (Shift on a new Pen curve handle) was
  NOT covered — separate code path, left alone rather than guessed at.
  NOT verified: nothing compiled or run; no Swift compiler in this environment.
  **NEXT:** owner builds and tests all three. Remaining Wave 1: BUG-028 (tool-switch
  shortcut — the keyDown handler is present and correct at `CanvasView.swift:6419`, so
  this is the responder-chain boundary from BUG-016/BUG-020 and the durable fix is
  menu-bar items with key equivalents per the command-coverage rule), plus a
  non-Option-drag repro for BUG-024.

- **2026-08-11 (Wave 1 opened: BUG-025 fixed; BUG-024's hypothesis disproven).**
  Started v2.3 Wave 1. **Checked the source before writing code, and the BUG-024
  hypothesis was wrong** — `CanvasView.swift:149` already overrides
  `acceptsFirstMouse(for:)` to true, `:148` already returns true from
  `acceptsFirstResponder`, and `mouseDown` already calls
  `window?.makeFirstResponder(self)` with a comment saying it exists so a click
  reclaims keyboard ownership from a panel. All three obvious causes were already
  handled, so the "missing acceptsFirstMouse" theory recorded at intake is dead and is
  marked DISPROVEN in the entry so it does not get re-filed. Re-reading the owner's
  report, the entire "only happens the second time" paragraph is actually about
  Option-drag, which suggests BUG-024 may have been over-read from a single report
  describing one bug; it now needs a repro that does NOT involve Option-drag before
  any more work, and should be closed as a duplicate if none exists.
  **BUG-025 root cause confirmed and fixed.** `mouseDown` read the Option flag ONCE
  and duplicated immediately, before any drag threshold. macOS delivers `flagsChanged`
  and `mouseDown` as separate events, so pressing Option and the button at nearly the
  same instant gives a nondeterministic order — press Option a hair late and you get a
  move. Exactly the owner's "sometimes I must hit the key and mouse down slightly
  staggered." The same line caused a second bug: a plain Option-CLICK with no movement
  minted a copy and registered an undo step. Fix defers the decision out of `mouseDown`
  and re-samples the modifier live in `mouseDragged`'s `.nodes` case, so Option works
  pressed before, during, or after mouse-down and releasing it mid-drag reverts to a
  move. New `setDragCopy(_:startDoc:)` flips by rewinding to `dragBaseline` and
  re-applying rather than unpicking the copies — the baseline is the model as of
  mouseDown, so it survives whatever else the drag touched — and runs only on modifier
  change, never per tick. Undo verified by reading the path: registered once at mouseUp
  from `dragBaseline`, `withNodes` mutates live without registering, so N flips still
  yield one step. NOT verified: nothing was compiled or run — no Swift compiler in this
  environment, per WORKING-AGREEMENT. **NEXT:** owner builds and tests Option-drag
  (before / during / after mouse-down, release mid-drag, plain Option-click, nested
  children, undo count), then reports back. Remaining Wave 1: BUG-026, BUG-027,
  BUG-028, BUG-037, plus a BUG-024 repro.

- **2026-08-11 (PERF-005 id collision resolved; guard script added).** Owner spotted
  that two different entries both carried PERF-005 and noted the giveaway — *"if it's
  duplicated, my gut says I've noticed it several times."* Correct: the ambiguity was
  live in FOUR files, not just BACKLOG. Resolved by first claim, checked against the
  Progress Log dates: the ruler-redraw entry was filed 2026-07-02 (Session 162d) and
  KEEPS PERF-005; the instCache-counters entry was filed 2026-07-09 (v1.2.1 kickoff),
  duplicated the id a week later, and becomes **PERF-006**. They were NOT combined as
  the owner offered — one is instrumentation verification and the other a ruler
  invalidation fix, different subsystems, different priorities. Updated every
  counters-side reference: `BACKLOG.md` heading + the FEAT cross-reference, `PERF-TODO
  .md` T5, and two Progress Log pointers here; the ruler-side references in
  `PERF-LOG.md` (×5), `PERF-TODO.md` T3, and this log are correct as-is and were left
  alone. Historical entries were annotated rather than silently rewritten. Also
  reordered the Performance section ascending (001→006) so a future duplicate is
  visible at a glance. **Root cause of the collision, now guarded:** ids are
  referenced from ROADMAP, PERF-LOG, and PERF-TODO as well as BACKLOG, so an id can be
  TAKEN without ever appearing as a `### ` heading — "next number after the highest
  heading" was never a safe rule. Added `scripts/verify_backlog_ids.sh`, which fails on
  duplicate headings and prints the next free id per prefix scanned across all of
  `docs/`, and added the rule as step 3 of BACKLOG's "How agents should use this."
  Current next-free: BUG-038, FEAT-042, PERF-007, INFRA-004.
  **NEXT:** unchanged — Wave 1, starting with BUG-024 and BUG-025.

- **2026-08-11 (spread: owner proposed removing it; pushed back; Stage 2 committed).**
  Owner's follow-up call on BUG-034 was to delete spread outright — *"if 'spread'
  wasn't there, I probably wouldn't miss it... I'd rather remove it for all instead of
  feeling like something is missing because it's inconsistent"* — with FEAT-023
  Duplicate plus stacked shadows as the substitute. The consistency instinct was
  right and the premise was wrong, so this was pushed back on with source evidence
  rather than logged as asked. Three importers already read spread:
  `RenderedHTMLImporter.swift:2112` parses CSS `box-shadow`'s FOURTH value,
  `FigmaImporter.swift:786` reads Figma's native shadow spread, and
  `SVGImporter.swift:615` reconstructs it from `feMorphology` including erode. The
  owner does not control whether spread enters their documents — it arrives from
  imports — so deleting `Effect.spread` would not remove spread, it would make EXP
  silently DROP it on import from all three sources. That is job #1 of the
  Architecture decisions failing ("read a component in accurately, losing no
  important data"), and it outweighs the annoyance of an inert control. Also recorded
  why stacked shadows are not equivalent: spread grows the silhouette BEFORE the
  blur, so the hard sticker/outline edge at blur 0 is unreproducible by stacking at
  any count, and stacking helps imported content not at all. **Owner reconsidered and
  chose to keep the model field and implement Stage 2**, achieving the consistency
  they wanted by adding rather than removing. Stage 1 accordingly narrowed to a
  DISCLOSURE-ONLY change in Wave 2 — state where spread is not yet previewed on
  canvas, alter no stored values, suppress no `feMorphology` emission, because both
  would destroy imported data Stage 2 is about to render correctly. No migration is
  needed since nothing is being removed. Added a second golden fixture requirement:
  a CSS `box-shadow` with a non-zero fourth value imported and re-exported unchanged,
  since the import round-trip is the reason the field survives at all.
  **NEXT:** unchanged — Wave 1, starting with BUG-024 and BUG-025.

- **2026-08-11 (BUG-034 unblocked — and it is a canvas/export fidelity bug, not a
  missing feature).** Owner confirmed the failing case was a drop shadow on TEXT, so
  Phase 10's documented limitation applies and it is not a regression. Reading the
  source, however, showed the two halves of the app disagree:
  `Color/EffectsRender.swift` → `Silhouette.path(spread:)` supports only rect,
  rounded-rect, and ellipse (its comment: *"Arbitrary custom paths ignore spread"*),
  and content-based casters like text go through `ctx.setShadow`, which has no
  spread concept — so the canvas renders spread as zero. But
  `Export/ExportRenderer.swift` emits `<feMorphology operator="dilate|erode">` for
  ANY node type whenever spread is non-zero, so SVG export renders the spread the
  canvas ignored. Set a spread on text, see nothing, export, and it is there. That is
  the round-trip infidelity this tool exists to prevent, so the P1 half is the
  DIVERGENCE, not the missing capability. Split into Stage 1 (Wave 2 — make both
  sides agree, stop showing a dead control, and decide explicitly what happens to
  existing documents already carrying a non-zero text spread) and Stage 2 (Wave 7 —
  implement it properly). Recorded the implementation approach and its main trap:
  dilate the ALPHA MASK rather than offsetting glyph outlines (Minkowski offsetting
  of glyphs is hard and unnecessary since text already casts from painted content),
  and use the same BOX structuring element `feMorphology` specifies — a circular or
  threshold-of-blur dilation would look better in isolation and silently re-create
  the divergence. Flagged for verification: the exact feMorphology rx/ry and edge
  semantics against the SVG spec, whether PNG/PDF raster export follows the canvas or
  the SVG path, and whether inner shadows share the gap (`drawInnerShadow`'s `hole`
  is described as the clip shrunk by spread, so probably yes). Noted the separable
  running-max (van Herk / Gil-Werman) algorithm to keep large radii interactive, the
  existing noise/dissolve async tile pattern as the caching precedent if needed, and
  that the radius must be in document points so the shadow does not change shape with
  zoom. **NEXT:** unchanged — Wave 1, starting with BUG-024 and BUG-025.

- **2026-08-11 (v2.3 backlog intake + release-shape decision; 35 items logged).**
  Owner delivered a long-accumulated list of bugs and improvements and asked whether
  it warranted a bug release before the next version or fitted inside it. Triaged the
  list into 11 clusters and recommended a split — a fast interaction/stability release
  first (the "second click" cluster is ~40% of the items and nearly all of the daily
  friction, and it is cross-cutting canvas event handling), with workspaces riding
  along because Session 79 persistence already did the hard half. **The owner chose a
  single release instead: v2.3 carries everything.** Trade stated and accepted —
  fewer cycles, longer wait, bug fixes interleaved with feature code. Mitigated by
  rewriting the v2.3 roadmap section as seven ORDERED WAVES so the input and
  selection layers are repaired before FEAT-025/026/029/032 build on them.
  Logged BUG-024…BUG-037 and FEAT-021…FEAT-041 in `docs/BACKLOG.md`, each with
  repro, hypothesis, and acceptance. Updated FEAT-008 and FEAT-010 in place rather
  than duplicating them. **FEAT-008's discovery gate is closed** — the owner's
  description (type-to-jump plus a hideable left rail carrying category filters,
  document-scoped Fonts Used, and app-level Recent) is the mockup pass v2.3 was
  waiting on; five open questions are recorded, chiefly that macOS exposes no
  reliable handwriting/display font classification so categories will be partly
  heuristic. Recorded specific hypotheses worth testing first: BUG-024 is very likely
  a missing `acceptsFirstMouse(for:)` override, which would fire on every trip from a
  floating tray back to the canvas, and BUG-025 looks like the Option modifier being
  latched at `mouseDown` instead of sampled through `flagsChanged`. Pushed back on
  four items rather than logging them as asked: BUG-034 shadow spread may be the
  limitation Phase 10 already documents ("exact for rect/ellipse; ignored for
  arbitrary closed paths") rather than a regression — **blocked pending the owner
  naming the node type**; FEAT-025 must not be treated as the fix for BUG-028, since
  making the wrong mode less painful would hide a live event-routing bug; FEAT-033
  freeform gradients have no SVG/CSS equivalent and Illustrator rasterizes them, so
  the export contract must be settled before any editor is built; FEAT-039 EPS import
  appears to have lost its native macOS path and the alternatives carry AGPL/GPL
  licensing consequences that are the owner's decision — a verified written finding
  comes before any commitment, and the macOS specifics were recorded as
  needing verification rather than as settled fact. Flagged five items requiring spec
  verification before code per WORKING-AGREEMENT: tooltips against WCAG 2.1 AA
  §1.4.13, dropdown borders against §1.4.11 (3:1, measured), the case icon control
  against §1.4.1, BUG-026's hit target against the target-size criteria, and the
  FEAT-008 rail against its APG pattern. **NEXT:** owner answers the BUG-034 node-type
  question, then Wave 1 begins with BUG-024 and BUG-025 — both cheap to test and
  both likely responsible for the "only works the second time" feel across the whole
  app.

- **2026-08-05 (v2.2 shipped; v2.3/build 14 development opened).** Owner
  completed the final Release-build acceptance and locally verified the
  v2.1 → v2.2 update. The signed v2.2/build 13 appcast entry, release-notes page,
  Git tag, and release commits are present, so the historical v2.2 final gate is
  closed. Advanced every Xcode configuration to `MARKETING_VERSION 2.3` /
  `CURRENT_PROJECT_VERSION 14`, opened an explicit v2.3 roadmap section, and
  synchronized `AGENTS.md` / `CLAUDE.md` with the new handoff. The only committed
  opening scope is evidence-first FEAT-008 discovery; code/component write-back
  and semantic state reconstruction remain recorded non-gating research lanes.
  **NEXT:** when work resumes, review the owner's font-filter mockups and usability
  evidence, decide which of Fonts Used, Recent Fonts, type-to-jump, and search
  form one coherent accessible control, then write the keyboard/VoiceOver/state
  contract before implementation.

- **2026-08-05 (v2.2/build 13 local release gate green; owner shipping steps
  remain).** Closed E1, E2, and the v2.2 `CodeBridgeManifest` foundation after
  the accepted HTML/CSS, CodePen, and five-framework static Storybook work.
  Added `RELEASE-NOTES-v2.2.md`, the exact
  `docs/RELEASE-CHECKLIST-v2.2.md` path, and updated the public website's
  import/handoff diagram and tester feature feed with local HTML/CSS, static
  Storybook, CodePen package import, and CodePen Prefill export. The complete
  deterministic component/page/XD/Figma/semantic/SVG/CodePen/rendered-HTML/
  WebKit/Storybook suite passes; the four still-present public React, Angular,
  Svelte, and Web Components corpora also re-pass their measured acceptance
  counts. The owner-supplied private GitLab/Vue fixture was not still present to
  rerun, so its earlier accepted pinned receipt remains the evidence for that
  row. Sparkle's 2.2/13 preflight, the production website build, `git diff
  --check`, and an isolated unsigned universal Release build all pass. One
  reviewed Handoff-package golden changed only because v2.2 changed the packaged
  `design.json` bytes/hash; semantic HTML, CSS, README, fidelity rows, and the
  package entry set stayed byte-identical. Existing Swift concurrency,
  deprecation, and unused-value warnings remain non-blocking cleanup; no warning
  was promoted into an error. **NEXT:** owner runs checklist §3 against the
  Release app, reviews/stages only intended source, then follows §§5–12 for the
  signed archive, notarization, immutable zip, Sparkle/GitHub/website publication,
  and the public v2.1 → v2.2 update/relaunch proof before announcement.

- **2026-08-05 (FEAT-008 moved to first-priority v2.3 discovery).** Owner chose
  not to squeeze the remaining font-picker filters into the v2.2 closeout. More
  filter ideas need a design mockup and usability testing to establish whether the
  combined control works and whether every proposed mechanism belongs. The shipped
  scroll-to-current picker remains unchanged; Fonts Used, Recent Fonts,
  type-to-jump, and search are now a candidate set to evaluate as one list-navigation
  system, not a pre-approved implementation checklist. FEAT-008 is promoted from P2
  to the first product-design priority for v2.3 and removed from the build-13 gate.
  **NEXT:** finish the v2.2 release audit and prepare build 13 for broader testing
  and shipment; open v2.3 with the owner's FEAT-008 mockup/research pass.

- **2026-08-05 (E2c modern compatibility matrix complete).** Owner visually
  accepted the Kintone Web Components/Vite corpus on its first import: all 16
  Phone/Web artboards looked correct, with only the expected current limitation
  that rendered stories are editable nodes rather than reconstructed EXP component
  states. This closes E2c across the measured Vue + webpack, React + Vite, modern
  Angular + webpack, Svelte + Vite, and light-DOM Web Components + Vite builds.
  Broader real-world tester feedback is welcome and will drive bounded bug fixes;
  it does not reopen the compatibility matrix by default. Semantic component/state
  reconstruction remains the separately logged v2.4+ research candidate, while
  older Angular/AngularJS and open-shadow-root evidence remain non-gating follow-ups.
  **NEXT:** audit the remaining v2.2 polish/release checklist, decide whether the
  already-scoped FEAT-008 font-picker work fits without destabilizing the release,
  then prepare build 13 for broader testing and shipment.

- **2026-08-04 (E2c Web Components + Vite automated matrix row).** Selected
  Kintone UI Component's public generated `gh-pages` deployment at commit
  `77c9855` as the final modern-framework fixture: Web Components renderer, Vite,
  TypeScript, pnpm, Storybook 10.3.5, and an index-v5 catalog with 106 stories and
  no docs. Added a commit/receipt-pinned, size-bounded static-artifact fetcher; it
  runs no package install or build. The eight-story Phone/Web corpus passes 16/16
  opaque artboards with 113 painted text layers, 18 editable SVGs, 134 semantic
  roles, 78 retained ARIA attributes, six editable shadows, bounded initial args,
  and zero native text overflow. The runtime settles at `finished`; no Web-
  Components-specific mapper was added. Kintone deliberately uses light-DOM
  custom elements, so shadow-root/slot traversal remains explicitly unmeasured
  and non-gating rather than silently claimed. The combined React + Angular +
  Svelte + Web Components corpus, deterministic rendered mapper, real WebKit
  fixture, and unsigned Debug app build all pass. **NEXT:** owner imports the
  prepared Kintone fixture and reviews the 16 artboards. If approved, close the
  modern E2c matrix and proceed to v2.2 importer/release cleanup; older
  Angular/AngularJS and a real open-shadow-root fixture remain non-gating
  compatibility work.

- **2026-08-04 (Svelte visual acceptance + future state reconstruction logged).**
  Owner accepted the corrected Brave Leo Svelte/Vite import after the file-backed
  SVG-mask pass, closing that compatibility row at 16/16 artboards and 18 editable
  icon masks. Logged semantic component/state reconstruction as an explicit v2.4+
  research candidate: related authored states such as collapsed/expanded accordion
  forms may eventually become real EXP component states and nested instances, while
  interaction playback remains out of scope. ARIA roles, states, and relationships
  are valuable evidence, but cannot alone establish component boundaries, behavior,
  or reversible source edits. This does not expand the v2.2 gate. **NEXT:** complete
  the basic E2c matrix with a standards-based Web Components + Vite published build,
  then close the importer scope and proceed to v2.2 release preparation.

- **2026-08-04 (E2c Leo file-backed CSS mask correction).** Owner review found
  Leo's icons imported as solid squares. Live inspection confirmed each icon is
  a same-origin SVG mask such as `/icons/close.svg`; EXP supported bounded inline
  data-SVG masks but intentionally left file-backed masks as their underlying
  fill box. The generic capture now records a single resolved mask URL, loads it
  only from the user-selected local package, sanitizes script/`foreignObject`/
  event/external-reference content, applies the element's computed paint, and
  imports the silhouette as editable native SVG geometry. The loopback server's
  root-relative compatibility alias now admits existing nested files while the
  standardized selected-directory prefix still rejects traversal/outside access.
  Leo's fetcher includes the six dynamically named corpus icons that Vite chunks
  cannot expose as literal URLs. Deterministic local-mask coverage passes, and
  the full Leo corpus remains 16/16 artboards with 32 painted text layers while
  replacing 18 square boxes with 18 editable SVG masks. **NEXT:** owner refreshes
  the fixture/rebuilds and re-imports the same eight stories for visual approval.

- **2026-08-04 (E2c Svelte + Vite automated matrix row).** Owner accepted the
  corrected Dell Angular corpus, closing its visual gate. Selected Brave Leo's
  public Nala deployment at main commit `b949916` as the next real fixture:
  Svelte 5.55.7, Svelte CSF v4, Vite 6.4.3, TypeScript, Storybook 8.6.18, and a
  v5 catalog with 104 stories + 31 docs. Added a receipt-pinned, size-bounded,
  same-origin static-artifact fetcher; its corrected corpus mirror contains 154
  published resources (4,523,555 bytes) without cloning source, installing
  packages, or executing a build. The eight-story Phone/Web corpus passes 16/16
  opaque artboards with 32
  painted text layers, 18 editable SVG masks, 28 semantic roles, 14 retained
  ARIA attributes, two editable shadows, bounded initial args, and zero native
  text overflow. Live inspection records terminal phase `finished`; no
  Svelte-specific mapper was
  added. The full synthetic + Svelte regression passes. **NEXT:** owner imports
  the prepared Leo fixture and reviews the 16 artboards; if approved, continue
  E2c with standards-based Web Components + Vite.

- **2026-08-04 (E2c Dell accordion caret / CSS data-SVG mask correction).** Owner
  re-import confirmed the clipping, root-asset, and switch corrections, then exposed
  one remaining accordion mismatch: each `span::after` was a solid 20×20 box. Live
  computed-style inspection showed this was not an icon font; Dell paints a dark
  background through an inline base64 SVG `mask-image`. EXP retained the background
  but discarded the mask. Pseudo extraction now boundedly decodes data-SVG masks
  (≤256 KiB), rejects malformed/external/script/`foreignObject` content, applies the
  resolved background color, and passes sanitized markup through the existing native
  SVG importer. The generic mapper now accepts a captured visual asset on generated
  elements, while unsupported/non-data masks receive an explicit Import Report item
  and keep the prior box fallback. Deterministic Storybook coverage proves a masked
  caret becomes an editable vector; the focused and full Dell passes prove all six
  Phone/Web carets survive. Dell remains 12/12 artboards with 52 painted text layers,
  now adding six editable SVG masks; the full CZI pass is unchanged geometrically and
  now honestly reports its 12 unsupported non-data masks. Synthetic Storybook,
  rendered mapper, real WebKit, full Dell, and full CZI checks pass. **NEXT:** owner
  rebuilds and confirms the Dell accordion carets visually; if approved, continue
  E2c with Svelte + Vite.

- **2026-08-04 (E2c Dell Angular owner-review correction — clipping, root asset,
  pseudo transform).** The owner's first Dell import exposed three independent
  browser-paint mismatches. Collapsed accordion bodies still had DOM client rects
  beneath zero-height overflow-hidden ancestors, so EXP resurrected unpainted copy;
  extraction now intersects descendants with every clipping ancestor before mapping.
  Dell's versioned preview also requests deploy-root `/dds-icons.svg`; the pinned
  fetcher had omitted it and EXP's loopback 404 body became editable `404 Not Found`
  text. The fetcher now includes the sprite, while the ephemeral server admits only
  an existing root-level selected-catalog file through this compatibility alias;
  nested/token/path-traversal and remote-resource boundaries stay closed. Finally,
  pseudo-elements have no DOM box API and the reconstructed switch thumb ignored
  its `translateY(-50%)`; EXP now applies the computed transform matrix around its
  resolved origin, centering the 20×20 thumb in the 40×24 control while continuing
  to report the transform as non-editable. Deterministic Storybook coverage now
  proves root-asset loading and fully clipped subtree rejection; Dell-specific
  checks prove the three headings survive, body copy/404 do not, and the thumb stays
  inside its switch. The corrected Dell corpus passes 12/12 artboards with 52
  painted text layers, 32 roles, 32 ARIA attributes, and two hidden accessibility
  labels. The stricter paint rule also removes fully clipped CZI sprite/scroll DOM;
  its pass is now 130 painted text, four SVG, seven shadows, 180 roles, and 82 ARIA
  attributes. Synthetic Storybook, rendered mapper, real WebKit, Dell, and full CZI
  regressions pass; the refreshed static fetcher includes the 447,536-byte SVG;
  `git diff --check` and the unsigned Debug app + thumbnail + helper build pass. The
  pasted Xcode log contains only existing WebKit/system sandbox noise; the canvas
  404 was the real missing sprite request. **NEXT:** owner rebuilds and re-imports
  the Dell corpus for visual confirmation. If approved, continue E2c with Svelte +
  Vite, then standards-based Web Components + Vite.

- **2026-08-04 (E2c modern Angular / Storybook 8 matrix row).** Selected Dell
  Design System Angular v3.0.1 over the initially viable Carbon candidate because
  Dell provides a genuinely newer runtime contract: Angular 17 (compatible 17–20),
  Storybook 8.6.18, webpack 5, TypeScript, index v5, and a stable versioned public
  artifact. The six-story control/content/data/overlay/layout corpus renders 12/12
  Phone + Web 1280 artboards through the existing framework-neutral seam with 70
  unclipped text layers, 38 semantic roles, 38 retained ARIA attributes, two hidden
  accessibility labels, and initial args for every story. No importer code changed.
  Added an opt-in pinned regression and static-artifact fetcher; it checks exact
  catalog/project hashes and never clones source, installs dependencies, or runs a
  build. Default, Dell Angular, and full CZI corpus checks pass; `git diff --check`
  and the unsigned Debug app/thumbnail/helper build pass. **NEXT:** owner imports
  the six Dell stories at Phone + Web 1280 for visual acceptance. If approved, add
  a real published Svelte + Vite build; Web Components + Vite follows before
  non-gating legacy Angular/AngularJS evidence.

- **2026-08-04 (CZI React/Vite visual acceptance complete).** Owner rebuilt,
  re-imported, and confirmed the final live InputToggle capsule fix. This closes
  the visual gate for E2c's Storybook 10.5.2 / React + Vite row: viewport/backdrop,
  generated flex content, fallback-font line boxes, percentage radii, and live
  rectangle/converted-path parity are approved. **NEXT:** add one real published
  modern Angular Storybook artifact as the third measured matrix build. First
  record its exact Storybook, Angular, builder, index, and runtime contracts; then
  run a small representative control/content/overlay/data corpus at Phone + Web
  before changing the framework-neutral importer. Only evidence from that artifact
  may justify compatibility code. Svelte and standards-based Web Components follow.

- **2026-08-04 (E2c capsule radius renderer/path parity).** The owner's next
  visual comparison found a highly diagnostic mismatch: the imported 62 × 24
  InputToggle outline looked like a stretched oval, then snapped into the correct
  capsule immediately after Object ▸ Path ▸ Convert to Path. The source value is
  legitimately `border-radius: 20px`. Convert to Path already applied CSS's
  adjacent-radius overlap rule and reduced the rendered radius to the box's legal
  12px maximum; the uniform live-rectangle path bypassed that normalization and
  passed 20px directly to AppKit, whose oversized rounded-rect behavior produced
  the awkward oval.

  Uniform and per-corner rectangles now share `CornerRadii.path` for canvas and
  raster/PDF drawing. Shadow, mask, hit/silhouette, and SVG paths use the same
  normalized effective radii, including stroke-aligned SVG copies. The model keeps
  the editable authored 20px value while every renderer paints the same 12px
  capsule Convert to Path produces. The public CZI regression now asserts both the
  16 × 16 / 50% thumb's 8px circle and the 62 × 24 outer box's normalized 12px
  capsule. Pure rendered-HTML mapping, the complete React/Vite Storybook corpus,
  `git diff --check`, and the unsigned Debug app/thumbnail build pass. **NEXT:**
  owner re-imports InputToggle once more and confirms the live rectangle is already
  identical to its converted path; if approved, advance E2c to modern Angular.

- **2026-08-04 (E2c CSS fixed-leading semantics + percentage-radius correction).**
  The owner's fourth CZI comparison isolated the remaining visual mismatch cleanly.
  The selected 16px Button label truthfully carried WebKit's computed `26px`
  line-height, but TextKit bottom-anchored the native baseline inside that fixed
  box; changing the Inspector to `1.3×` only appeared to fix it by substituting a
  shorter line box. EXP now preserves the authored px/em value and centers its
  extra leading around the resolved native font box at paint time. Measurement,
  selection geometry, and HTML export keep the original line-height. Existing
  saved documents decode to the legacy baseline behavior, while new/imported text
  opts into the corrected CSS behavior, avoiding an unannounced typography shift.

  `Auto` is now semantically honest end to end: CSS `line-height: normal` imports
  as Auto, and the Inspector help explains that Auto uses the installed font's
  native metrics. The hidden 1.3 value is only the seed revealed if Auto is changed
  to the × unit; it is not applied while Auto is selected. For the system fallback
  at 16px, AppKit's native line fragment is about 18px (roughly 1.125×), which
  explains why Auto looked much closer to 1 than 1.3 in the screenshot.

  The square toggle thumb was a separate mapper bug, not a fundamental shape
  limit: the main CSS surface path accepted px radii but dropped `50%`. Percentage
  corner radii now resolve against the smaller box dimension, so CZI's 16 × 16
  thumb imports as an editable 8px-radius circle. The synthetic mapper and complete
  public React/Vite corpus pass, including the real thumb-radius assertion, all 190
  finite text boxes, and the focused Tablet controls; the unsigned Debug app and
  Quick Look build also pass. Remaining honest typography limit: Inter is not
  installed, so source-webfont glyph shapes/widths still use the reported system
  fallback even though their line boxes now align. **NEXT:** owner re-imports the
  CZI Button/ButtonGroup/InputToggle examples and visually checks fixed px leading
  plus the circular thumb. If approved, advance E2c to a modern Angular artifact.

- **2026-08-04 (E2c control line-box correction + authored mobile chart overflow).**
  The owner's third comparison showed the reconstructed toggle intact but control
  text still vertically low, and the StackedBarChart default visibly cropped at
  Phone. Saved geometry isolated both. WebKit's `Range` puts Button's 14px `Label`
  ink at y=24 inside a CSS line box beginning at y=20; EXP had started a fresh
  24px TextKit line box at that ink y, shifting the native glyphs down. Direct text
  translation now splits the missing CSS leading above and below the browser ink
  union. At Tablet, the imported Label line box is y=20…45 inside the y=16…48
  button—centers differ by 0.5px—and ContentCard's multiline box likewise begins
  at its real line-box top while preserving 24px line-height and zero overflow.

  The chart is not a missed mobile media query. Its published default story
  explicitly supplies `width: "360px"`; at the 393px viewport, Storybook centers a
  61px intrinsic wrapper whose fixed 360px child overflows it, producing browser-
  measured content 133px beyond the right edge before EXP maps anything. Import
  remains source-faithful instead of inventing a responsive rewrite. The mapper
  now emits an exact **Viewport overflow** report row naming the overflow side and
  distance, and the regression asserts both that row and the retained 360px
  initial-args provenance. Focused chart Phone/Web, Button/ContentCard/InputToggle
  Tablet, pure mapper, and real WKWebView checks pass. **NEXT:** owner re-imports
  Button/ContentCard/InputToggle to confirm vertical rhythm; treat the chart crop
  as published-source behavior unless a responsive story is selected or the
  source component is changed.

- **2026-08-04 (E2c Tablet visual correction — flex pseudo geometry, CSS outline, multiline fallback layout).**
  The owner's second acceptance screenshot showed the viewport/backdrop fixes
  working, then exposed two narrower failures. The newly saved document proved
  InputToggle's generated `Off` text existed but occupied the switch origin under
  its thumb, while the 62 × 24 pill had no visible outline. The published component
  source confirmed `Off` is a static `::after` flex item and the pill is authored
  with CSS `outline`, not border or shadow. The ContentCard paragraph retained its
  authored 14px font / 24px line-height / five browser lines, but unavailable Inter
  fell back to a wider native system face that wrapped into an excluded sixth line.
  The full Xcode log again contained WebKit sandbox/service diagnostics and no
  importer exception.

  Static pseudo-elements in flex containers now derive their painted position from
  already-laid-out in-flow siblings, flex direction, resolved margins, and cross-axis
  alignment. CSS outline color/style/width/offset enter the snapshot; a lone outline
  maps to an editable outside EXP stroke, while border+outline and nonzero offset
  reductions are reported honestly. Imported text retains the authored CSS
  line-height. Before finalizing its finite frame, the mapper now asks native
  TextKit how the resolved installed font lays out: a multiline box receives only a
  small bounded width correction when that preserves the browser line count, or
  grows in height when it cannot, so no character is silently clipped.

  The public Storybook check now adds the exact owner-evidence subset—ContentCard +
  InputToggle at Tablet 834 × 1194—and asserts the 24px paragraph line-height, zero
  excluded native characters, `Off` to the right of the thumb, and a 62 × 24 outside
  outline. The strengthened Tablet subset, Phone/Web corpus, pure mapper, real
  WKWebView suite, and unsigned Debug app build pass. **NEXT:** owner re-imports
  ContentCard/InputToggle at Tablet and visually confirms the paragraph has no red
  overflow badge and the complete toggle pill/label is visible before E2c advances.

- **2026-08-04 (E2c visual-acceptance correction — viewport, backdrop, pseudo text, native overflow).**
  Owner screenshots of the first CZI import correctly rejected the non-empty-node
  test as insufficient. The saved `.design` file proved the button's real
  1280 × 800 Storybook root was retained inside a wrongly measured 1280 × 32
  artboard; most other preview bodies also shrink-wrapped their component, and
  transparent body backgrounds exposed EXP's dark workspace instead of the
  browser's white canvas. The pasted Xcode log contained OS/WebKit sandbox noise
  but no importer failure.

  Rendered DOM height now includes the recursive visible captured-tree bottom,
  while the Storybook boundary independently treats each requested render height
  as the minimum artboard and restores the browser's opaque white default canvas.
  The general extractor now retains `::before`/`::after` when they paint generated
  text, a background, border, or shadow; this restores the CZI InputToggle's `Off`
  label and inset outline. Single-line EXP text boxes widen only when native
  fallback-font metrics exceed WebKit's source-webfont ink bounds, preserving
  wrapped browser lines while eliminating the screenshot's red overflow badges.

  The strengthened public-corpus regression imports all eight stories at Phone
  393 × 852 and Web 1280 × 800, asserts an opaque backdrop, verifies generated
  `Off` text, and runs each of 190 text layers through a canvas-equivalent finite
  TextKit container. It passes with 16 artboards, zero text overflows, 42 editable
  SVGs, 12 editable shadows, 240 semantic roles, and 120 retained ARIA attributes.
  All non-table boards equal the requested viewport; the table honestly expands
  to its taller rendered content. Synthetic Storybook pseudo-content, pure mapper,
  real WKWebView, full public corpus, and unsigned Debug app build pass.
  **NEXT:** owner deletes/re-imports the CZI selection at Phone + Web 1280 and
  visually confirms the corrected white full-height boards, toggle, table, and
  text. Only then advance to the first modern Angular matrix row.

- **2026-08-04 (E2c begins — real React + Vite / Storybook 10 matrix row).**
  Added the second real published static build requested by the session checkpoint:
  CZI Science Design System's 16 MB `gh-pages` artifact at deployment commit
  `af4f1a7`, with Storybook 10.5.2, React + Vite + TypeScript, index v5, 202
  stories, and published `project.json`. No repository dependency or build command
  ran. Its eight-story representative corpus covers accordion, button, dialog,
  toggle, table, tabs, heatmap, and stacked bar chart. All eight render as non-empty
  1440 px artboards, retaining 94 text layers, 21 editable SVGs, 120 semantic roles,
  60 structured ARIA attributes, and bounded initial args for every selected story;
  no SVG raster fallback occurs.

  The real artifact exposed three generation-contract differences. Storybook 10's
  successful terminal runtime phase is `finished`, not Storybook 7's `completed`;
  EXP now accepts both while still rejecting failure phases. Its populated
  `#storybook-root` can be 1408 × 0 while visible descendants have real geometry;
  readiness now falls back to a bounded 5,000-element visible-descendant union only
  for a populated zero-box root, so empty/hidden renders still fail. Finally,
  modern `project.json` names the Vite builder without listing a separate builder
  package version; provenance now falls back to the explicit top-level Storybook
  version (10.5.2) instead of incorrectly storing index schema 5.

  Added `docs/STORYBOOK-COMPATIBILITY-MATRIX.md` with both measured builds, exact
  contracts/counts, honest mapper limits, reproduction steps, and remaining rows.
  The CZI corpus explicitly reports its font substitutions, measured-box transform
  fallback, unsupported CSS backgrounds, reduced per-side border, and unsupported
  native `rowgroup` role rather than mislabelling them as React/Vite failures.
  Deterministic Storybook, real WKWebView, the full public corpus, `git diff --check`,
  and unsigned Debug app build pass. **NEXT:** owner imports the eight CZI stories
  from `/tmp/exp-sci-storybook.9t6v7T` at Desktop 1440 and compares them with the
  [published Storybook](https://chanzuckerberg.github.io/sci-components/). If
  visually approved, add the first modern Angular published build as E2c's next
  measured row; URL trust, repository builds, full argTypes, and write-back remain
  deferred.

- **2026-08-04 (session checkpoint — owner happy with first Storybook implementation).**
  The owner considers the current local/static Storybook import a strong v2.2
  baseline; further refinement is expected from broader real-world libraries but
  is not blocking this checkpoint. Verified today: searchable selection from the
  530-story GitLab UI catalog; eight representative non-empty artboards spanning
  controls, tabs/accordion, data display, charts, editable SVG media, and a
  play-function-opened modal; hidden accessibility text retained without painting;
  fixed/portal geometry; six editable SVGs with no raster SVG fallback; optional
  `project.json` framework/build/package-manager provenance; and bounded JSON-safe
  initial story args. Synthetic Storybook, live GitLab corpus, pure mapper, real
  WebKit portal/sprite, saved-Chrome-page, and unsigned Debug app-build checks pass.
  Known honest limitations remain: unavailable web fonts use a reported installed
  fallback; unsupported CSS/SVG effects stay disclosed; imports capture rendered
  states rather than recreating framework behavior; selection is capped at 100
  stories per import; unrestricted URL import and code write-back remain deferred.
  **START HERE NEXT SESSION:** begin E2c with a second *real published static build*,
  preferably a modern React + Vite Storybook to contrast the current Vue + webpack
  5 / Storybook 7.6.24 fixture. Record its index/project/runtime versions, run the
  same small representative corpus, and turn every difference into either a
  compatibility assertion or an honestly reported limit. Create the compatibility
  matrix from measured results before adding Angular/legacy generations. Do not
  expand network trust, execute repository builds, add write-back, or ingest full
  argTypes/controls until that second fixture supplies evidence they are needed.

- **2026-08-03 (E2 representative Storybook corpus — portals + SVG sprites).**
  Expanded the live GitLab UI proof from accordion/tabs to eight stories spanning
  controls, overlays, data display, charts, and SVG media. The modal initially
  exposed two translation gaps: its Storybook play function completed correctly,
  but the dialog lived under a zero-size body portal and its fixed overlay extended
  beyond normal-flow document height. The rendered snapshot now skips truly hidden
  Storybook preparation shells, derives layoutless wrapper geometry from visible
  children, and includes visible fixed bounds in artboard height. The modal imports
  at 1440 × 1024 with title, copy, and actions. GitLab's illustration then exposed
  external local `<use href="sprite.svg#…">`; the capture now resolves only
  same-folder references, copies and ID-namespaces the target symbol (including
  internal paint/filter references), and keeps it on the native SVG path. Full live
  corpus: 8 artboards, 52 text layers, 6 editable SVGs, zero raster SVG fallbacks.
  Synthetic Storybook, pure mapper, real WebKit portal/sprite, and saved-Chrome-page
  checks pass. GitLab Sans/Mono remains an honestly reported installed-font fallback,
  not a mapper defect. The follow-on E2a slice also retains optional `project.json`
  framework/builder/renderer/Storybook/package-manager identity and bounded
  JSON-safe runtime `initialArgs` per story contract, without granting write-back.
  **NEXT:** add a second Storybook generation/framework fixture for the E2c
  compatibility matrix, then decide whether controls/argTypes add enough value
  beyond initial args to justify their much larger payload.

- **2026-08-03 (BUG-023 owner-verified).**
  Owner rebuilt and reimported `base/tabs / With Counter Badges`; the hidden
  screen-reader labels no longer spill across the visible tabs, and the resulting
  Storybook import looks solid. BUG-023 is closed. The live GitLab Storybook path
  now has owner-verified catalog selection, ES-module runtime rendering, editable
  artboard creation, and accessibility-only text handling. **NEXT:** continue E2
  live-corpus refinement with a small representative mix of controls, overlays,
  media/SVG, and data-display stories; separate genuine mapper defects from the
  already disclosed installed-font fallback before broadening the framework and
  Storybook-version compatibility matrix.

- **2026-08-03 (BUG-023 — Storybook screen-reader text spill).**
  The owner's `base/tabs / With Counter Badges` screenshot provided a clean
  geometry diagnostic: the apparent duplicate/overlapping labels were GitLab's
  meaningful `.gl-sr-only` spans (`42 issues`, `15 open issues`, `1 closed issue`).
  Chrome lays each out as an absolute 1 × 1 px box with both axes overflow-hidden
  and a zero clip; EXP retained the text but ordinary groups do not clip children,
  so the full accessibility labels painted across adjacent tabs. The HTML mapper
  now recognizes this conservative rendered signature (absolute/fixed, ≤2 × 2,
  both axes hidden/clip, non-empty text), keeps the source text and hierarchy as a
  named hidden EXP layer, and reports the exact accessibility preservation instead
  of deleting it. The exact live tabs story asserts all three labels remain hidden;
  the synthetic Storybook fixture covers the same behavior. Live GitLab Storybook,
  pure mapper, real WebKit, and unsigned Debug build checks pass. The fixture also
  confirms the remaining likely typography variance is a separately reported font
  fallback: the browser loads `GitLab Sans` from local WOFF2, while EXP currently
  supports installed fonts only; custom/embedded font import remains the existing
  Phase 9 follow-up rather than being silently treated as exact. **NEXT:** owner
  reimports this tabs story to verify the overlap is gone, then identify any
  remaining non-font geometry mismatch from a screenshot.

- **2026-08-03 (BUG-022 — live Storybook runtime capture).**
  The first selected GitLab stories imported as empty one-pixel artboards because
  WebKit loaded `iframe.html` but did not execute Storybook's ES-module/webpack
  runtime on EXP's custom URL scheme; the generic 1 px fallback then disguised the
  failed render, while uncapped media-query Notes amplified the noise. Storybook
  now receives a temporary GET/HEAD-only HTTP origin bound to `127.0.0.1`, scoped
  by an unguessable route token to the selected folder and allowed by WebKit only
  for that exact prefix; every other network/file request stays blocked and the
  listener is torn down after import. A Storybook-specific readiness gate waits for
  `sb-show-main` plus a populated, laid-out story root and reports runtime,
  no-preview, timeout, or empty-layout failures instead of creating artboards.
  Artboard Notes cap displayed media-query matches at 20. The owner's exact GitLab
  index-v4 build now passes end to end for `base-accordion--default`: one 1440 px
  editable artboard over 100 px tall with Item 1/Item 2 text. Synthetic Storybook,
  real-WebKit HTML, live GitLab runtime, and unsigned Debug build checks pass.
  **NEXT:** owner reimports a small visual slice and reports mapping fidelity; then
  refine from those components and broaden the framework/version fixture matrix.

- **2026-08-03 (E2 live GitLab corpus — scalable story selection).**
  The owner's production build of GitLab UI proved Storybook index v4 with 649
  entries (530 stories plus 119 docs entries). Replaced the whole-catalog 100-story
  rejection with a metadata-only discovery pass and searchable selection sheet;
  EXP now skips docs, lets the designer find stories by title/name/id/tag/source
  path, and imports any chosen slice up to the existing 100-story safety limit.
  Selection is retained while filtering, Select Visible is bounded, and the Import
  action stays disabled until at least one story is selected. The static-package
  regression check and unsigned Debug app build pass. **NEXT:** owner imports a
  small slice from the GitLab corpus and validates visual results/provenance; refine
  from that live evidence before broadening the framework/version fixture matrix.

- **2026-08-03 (E1 semantics closed; first static Storybook slice).**
  Closed E1's two remaining accessibility decisions against WAI-ARIA 1.2 and the
  current ARIA-in-HTML host table. Imported nodes now persist tolerant structured
  semantics: native/conforming roles map to EXP roles, authored `aria-*` values
  remain source-owned data rather than invented component variants, and prohibited
  explicit roles are retained for repair while the verified implicit host role is
  used and the conflict is reported. Inline rich-text links retain `href` on the
  run and semantic HTML reconstructs the anchor without re-splitting the box.

  Began E2 with File ▸ Import Storybook Build…. A local static build's published
  `index.json` discovers stories and `iframe.html?id=…&viewMode=story` renders them
  through the proven isolated WebKit mapper at selected viewports. Artboards and
  the hidden bridge retain story ids/titles/names/tags/import paths, index-entry
  receipts, resource hashes, and receipt-only DOM bindings; EXP runs no build tools.
  Deterministic pure semantic, real-WebKit, semantic package, and two-story static
  Storybook checks pass. **NEXT:** owner tries a real static Storybook folder. Then
  add story selection (rather than always importing up to the 100-story cap) and
  broaden the framework/Storybook version fixture matrix from live evidence.

- **2026-08-03 (BUG-021 owner-approved; tangent closed).**
  Owner verified the full artboard-membership behavior and gave Tapps approval:
  cropped/sliver groups remain attached, full separation returns them to Wall,
  resized descendants and mask crop bounds register, and explicit Layers drops are
  usable. BUG-021 is done. This also closes the remaining owner-visual gate on E1b
  local HTML/package import and formally completes E2b's CodePen export + ZIP-import
  connector. **NEXT:** return to the main v2.2 line. Finish E1's bounded semantic
  cleanup—verified `aria-*` state import plus explicit-role/host conflict handling—
  then start E2's first static Storybook slice (`index.json` discovery + isolated
  `iframe.html` story render ingestion) on the proven local WebKit mapper. E1c-b
  arbitrary URL import remains deliberately deferred and is not a gate.

- **2026-08-03 (BUG-021 — artboard membership hysteresis + visible bounds).**
  Owner confirmed the CodePen animation/opacity fixes, completing the live ZIP gate,
  then exposed a deeper wall/artboard frustration: membership was recomputed from a
  top-level node's stored frame with the same >50% threshold in both directions.
  Resizing descendants could therefore eject an intentionally cropped group, and a
  mask did not reduce the geometry used by ownership. EXP now persists top-level
  `artboardID` within v2.2 schema 4 and applies a deliberate hysteresis contract:
  Wall → board still requires >50%, while board → Wall requires zero remaining
  visible overlap. Unmanaged groups use current descendant geometry; masks use the
  mask-shape/content intersection; soft effects do not influence ownership.

  Canvas rendering/carry/delete, Layers grouping and section/row drops, semantic/SVG/raster
  export, Handoff/agent reads, duplication, group/mask/ungroup, and save/open now use
  the node-aware resolver. A wall row dropped on an artboard header (including an
  empty board), or beside/inside one of its layers, explicitly attaches: existing
  partial overlap stays in place, while zero overlap centers it. The model regression
  proves exact 50%
  remains Wall, >50% enters, a 1-point attached sliver remains, zero overlap exits,
  resized descendants replace stale group bounds, mask crop bounds register, and the
  assignment round-trips. Canvas-pages, semantic/CodePen package, rendered HTML,
  all 11 XD packages (644 artboards / 84,208 layers), and unsigned Debug build pass.
  BUG-021 is `needs-verify`. **NEXT:** owner verifies sliver drag, full detach,
  child-resize stability, mask crop, Layers Wall → artboard header/row behavior, and
  save/open; then begin static Storybook `index.json` + isolated story rendering.

- **2026-08-03 (live CodePen ZIP refinement: animation state + Layers opacity).**
  The owner's exported `pure-css-glassmorphism-liquid-glass-ui-kit.zip` used the
  supported wrapper/`src`/`dist` package shape and imported successfully, but exposed
  two real defects. First, its `.section` elements use delayed finite entrance
  animations from opacity 0; offscreen WebKit could throttle those at the first
  keyframe, so every imported section group was invisible. Rendered capture now
  advances finite Web Animations to their stable end state immediately before DOM
  measurement. Infinite animations are paused at the current sample and disclosed
  as an approximation in the Import Report. The real-package regression now finds
  all 26 `section.section` groups at opacity 1.0, and the deterministic fixture also
  covers a delayed opacity entrance animation at Phone + Desktop.

  Second, selecting a group in Layers left the SwiftUI List as first responder, so
  its digit events never reached the canvas opacity shortcut. Layers now owns the
  same unmodified `0`…`9` shortcut at that focus boundary, with canvas and panel both
  using one recursive opacity mutation and one undo step. CodePen package, live ZIP,
  real-WebKit, pure HTML, and unsigned Debug build checks pass. BUG-019 and BUG-020
  are `needs-verify`. **NEXT:** owner rebuilds, re-imports the same ZIP to confirm its
  sections are visible, then selects a top-level/nested group in Layers and verifies
  `4` → 40%, `0` → 100%, plus Undo. If green, complete the live ZIP gate and
  begin static Storybook `index.json` + isolated story-render ingestion.

- **2026-08-03 (CodePen 2.0 ZIP import first slice).**
  Implemented **File ▸ Import CodePen Export…** through a new bounded ZIP/package
  boundary and the existing editable rendered-HTML mapper. EXP recognizes one
  wrapped or flat `dist/index.html` plus sibling `src/`, renders the last successful
  build at the selected browser viewports, preserves native SVG, and inventories the
  entire package into `CodeBridgeManifest` with relative paths, roles, sizes,
  SHA-256 hashes, prioritized bounded source/config bytes, archive digest, and
  receipt-only bindings. `.codepen/pen.config.json` and processor config remain
  opaque and lossless; no npm/compiler/Block/build command is run. Browser-ready
  `dist` JavaScript is explicitly limited to the non-persistent, network-blocked
  render, while authored `src` scripts are never executed. The extractor refuses
  traversal/absolute paths, symlinks, encrypted/ZIP64/unsupported compression,
  ambiguous package roots, and expansion-limit violations, and deletes its private
  temporary materialization after capture. Also corrected nested local HTML entry
  resolution and stopped absolute local paths from entering artboard Notes.

  The deterministic CodePen fixture passes at Phone + Desktop with editable SVG and
  preserved Sass/TypeScript/Block configuration. Existing real-WebKit and pure HTML
  mapper checks, semantic HTML/CodePen Prefill, SVG/token, the 11-file XD corpus
  (644 artboards / 84,208 layers), and an unsigned Debug app build all pass.
  **NEXT:** owner exports the approved live Pen and confirms its real 2.0 ZIP, then
  begin static Storybook `index.json` + isolated story-render ingestion.

- **2026-08-03 (CodePen export-first owner-approved).**
  Owner rebuilt and confirmed the corrected `/pen/define` flow successfully creates
  the new Pen from a representative SVG artboard, with the local disclosure step and
  new-tab handoff working smoothly. Marked live confirmation complete — “Tapps
  approved.” **NEXT:** implement CodePen 2.0 exported-ZIP detection/import through
  the existing local rendered-HTML seam, preserving `dist/`, `src/`, configuration,
  Blocks/processors, paths, and hashes in `CodeBridgeManifest`; then move into the
  first static Storybook ingestion slice.

- **2026-08-03 (CodePen live-Prefill compatibility correction).**
  Investigated the first owner-run export, which reached CodePen but received its
  plain **Something Went Wrong** response. The accompanying Chrome
  `Could not establish connection` console line originated in an injected extension
  iframe, not EXP or the submitted Pen. Re-checked CodePen's current Prefill contract:
  EXP had carried forward deprecated `editors`/`tags` fields and unsupported
  `css_starter: neither` / `css_prefix: neither` sentinels. A second owner attempt
  isolated the remaining failure to CodePen's transitional `/cpe/pen/define/` route:
  after the July 23 site-wide 2.0 launch it returns an internal error, while the
  contract's announced successor `/pen/define` creates the Prefill session. EXP now
  uses that live endpoint and supplies the documented HTML-editor body fragment
  rather than nesting a complete document. The review form opens CodePen in a new
  tab so the disclosure/retry page remains available. The semantic-package check
  locks the exact field set, fragment shape, and form target. **NEXT:** rebuild and
  owner-retest the one-SVG artboard, then visually verify the resulting Pen.

- **2026-08-03 (E2a bridge foundation + first CodePen 2.0 export slice).**
  Added the hidden, versioned `CodeBridgeManifest` to document schema 4 with tolerant
  missing-field decoding. It can retain connector/source/repository/framework/build
  identity, resource paths and SHA-256 receipts, bounded opaque bytes, EXP node or
  artboard bindings, behavior-contract payloads, confidence/ownership and explicit
  writable-property boundaries, plus a future three-way-sync baseline. Existing
  documents decode with an empty bridge collection; a malformed optional bridge
  receipt cannot brick the artwork. The bridge is saved inside `.design` but remains
  absent from the canvas and Notes.

  Wired real local HTML imports into that model. Each viewport and mapped DOM element
  gets a source binding; anonymous DOM paths are lower confidence than authored
  `data-exp-id`; and all bindings are receipt-only until a source connector explicitly
  grants write authority. The folder-scoped WebKit handler now records only resources
  actually consumed, hashes each one, and retains up to 8 MB of HTML/CSS/JS/config/
  text-SVG source byte-for-byte. Binary assets retain digest receipts and continue
  through native image/vector nodes. No absolute local path or credential is stored,
  and bridge insertion shares the import's one undo step. The live fixture now proves
  opaque JavaScript preservation in addition to HTML/CSS/SVG.

  Implemented the first user-visible CodePen 2.0 connector. File and Handoff now offer
  **Send Current Artboard to CodePen…**; the exporter creates one bounded semantic
  HTML/CSS Prefill payload and an accessible local browser review page. Nothing is
  transmitted until the person presses **Send to CodePen** there. The connector uses
  no token, cannot update an existing Pen, and sends no preserved JavaScript because
  the current reconstructed DOM has no behavior-binding proof. Pure Prefill/escaping/
  selected-artboard tests pass, as do the real WebKit bridge fixture, XD 11-file
  corpus, Figma, canvas-page migration, SVG/token, semantic Handoff goldens, and two
  unsigned Debug app builds. The reviewed Handoff golden changed only for document
  schema 4's marker/bytes/hash. **NEXT:** owner performs the live CodePen POST and
  visual comparison; fix any current 2.0 endpoint/editor mismatch, then implement
  exported-ZIP import or begin static Storybook ingestion.

- **2026-08-03 (connector scope decided + CodePen 2.0/provenance architecture).**
  Owner confirmed that unrestricted arbitrary-URL import is deferred: a deliberate
  local download/export step is sufficient, while component-library systems have
  higher value and a more defensible boundary. E1c now makes that a decision rather
  than a pending recommendation. E2 now includes three explicit tracks: a hidden,
  versioned `CodeBridgeManifest` that preserves source identity, node/source
  bindings, behavior contracts, opaque JS/config and a three-way merge baseline; an
  export-first CodePen 2.0 connector; and a phased framework-generation fixture
  matrix that keeps older Angular and AngularJS enterprise artifacts in view without
  making every historical adapter a v2.2 gate. Secrets remain in Keychain, opaque JS
  is preserved but never run by the canvas, and future write-back changes only
  explicit high-confidence bindings with reviewable conflicts.

  Re-checked CodePen's July 2026 2.0 contracts and corrected the earlier shorthand.
  There is still no general authenticated REST/GraphQL file CRUD API, so true
  update-in-place sync cannot be promised. There **is** a supported POST-to-Prefill
  path for EXP to create a new Pen; 2.0 also adds a real filesystem, versioning,
  deployments, and ZIP exports containing `src/` plus the last successful `dist/`
  build. Roadmap boundary: ship semantic HTML/CSS/JS → new Pen first; import a
  user-exported ZIP through the safe local path while retaining source/config in the
  bridge manifest; consider generated multi-file ZIP and narrow deployed-Pen import
  later. Editable embeds remain a strong human handoff workflow, not programmatic
  source synchronization.

- **2026-08-03 (v2.2 web/SVG fidelity audit + connector scope recommendation).**
  Added `docs/WEB-SVG-FIDELITY-INVENTORY.md`: a native-first inventory of missing
  effects, filter primitives, paint servers, masks/clips, gradients, strokes,
  typography, transforms, and CSS appearance, separated into P0/P1/P2 rather than
  one undifferentiated “support the web” list. P0 starts with Color Adjust/general
  `feColorMatrix`, component transfer, morphology, displacement, an ordered advanced
  filter pipeline, SVG pattern paint, layered fills, clip/mask round-trip, gradient
  and stroke fidelity, multiple shadows/CSS filters, and performant backdrop blur.
  Added telemetry tasks so real missing pixels/area and user fixtures—not raw CSS
  property frequency—decide implementation order.

  Honest connector recommendation recorded in E1c/E2/E3: **defer unrestricted
  arbitrary-URL import as a v2.2 gate**; do local/static Storybook next, then a narrow
  public-static/hosted-Storybook URL mode if that proves the shared value. The existing
  non-persistent WebKit/resource-receipt/trust/session work transfers to hosted
  rendered sources, but the dynamic authenticated-web tail does not solve component
  identity or source write-back. Write-back is separately gated on provenance
  (`data-exp-id`, story ids/args, tokens, source manifests/maps) and begins as a
  reviewable patch or GitHub branch/draft PR—not inferred edits to anonymous
  JSX/templates. Storybook's current official framework support and publishing APIs,
  GitHub's permission/content APIs, and CodePen's documented no-traditional-API
  boundary were checked for this decision.

- **2026-08-03 (E1b editable SVG preservation + Layer Blur) — SVGs stay vectors.**
  Reworked the HTML capture/import seam so trusted local `<img src="*.svg">`, inline
  SVG, data-URI SVG, and single local/data SVG CSS backgrounds send sanitized source
  markup into the existing native SVG importer instead of accepting WebKit's PNG
  snapshot. Added bounded `symbol`/`use` reference reconstruction (including cycle
  protection), native repeat tiling with editable mask clipping, and fresh ids for
  every repeated tile. The real Chrome Complete-page fixture now maps **34 raster
  image nodes, 13 editable SVGs, 6 editable SVG background layers, and zero raster
  CSS backgrounds** across Phone + Desktop.

  The saved site includes standalone SVG Gaussian filters, so EXP now has an editable
  **Layer Blur** effect: tolerant document decoding, inspector add/edit controls,
  bounded Core Image canvas/raster rendering, viewport/export paint bounds, native
  SVG import, and `<feGaussianBlur>` SVG export. A regression proves softened raster
  pixels as well as SVG round-trip. General `feColorMatrix` remains editable geometry
  plus a specifically named unsupported report row until its 4×5 native effect is
  implemented. Deterministic mapper/WebKit/Chrome-save checks, Figma fixture, all 11
  real XD packages (84,208 layers), SVG token/effect bridge, and full unsigned Debug
  app build pass.

- **2026-08-03 (E1b Chrome Complete-page resources) — local images, SVG, and CSS
  image layers now render instead of placeholders.** Tested the exact Chrome
  “Webpage, Complete” folder at `~/Desktop/downloaded-website-tests` against its
  browser screenshot. The capture now embeds browser-decoded `<img>` pixels (PNG,
  JPEG, and SVG sources) and sanitized inline SVG into the snapshot, including CSS
  percentage corner clipping, so circular pattern thumbnails and portraits remain
  visually shaped and the resulting `.design` file is self-contained. The computed
  style allowlist now carries background repeat/size/position; single `url(...)`
  data-image layers are rasterized at their measured box while the box/text/children
  stay editable. Background-image pseudo-elements are captured as bounded synthetic
  layers, which restores the page's viewport chevron field instead of leaving the
  body purple. Multi-layer CSS backgrounds still produce one explicit unsupported
  row rather than being silently flattened.

  Added `verify_rendered_html_chrome_save.sh`, a production-shaped acceptance check
  that consumes a caller-supplied Chrome-saved HTML file without checking third-party
  content into the repository. Phone 393 + Desktop 1440 map **53 image/SVG nodes,
  including 6 CSS background layers, with zero image placeholders**. Deterministic
  mapper and real WebKit fixture suites pass; the live fixture now asserts four local
  SVG image nodes and no placeholder warnings. Full unsigned Debug app build succeeds.
  **NEXT:** owner re-imports the saved page and compares it visually; then either
  polish a concrete remaining mismatch or proceed to E1c's Sources/session UI.

- **2026-08-03 (E1b mixed inline text overlap) — merged into native rich text.**
  Owner's follow-up screenshot showed the fixture paragraph's `<a>`, direct text,
  `<strong>`, and `<em>` as separate overlapping EXP text boxes. This was not the
  earlier editor-confirm bug: `TextContent` already persists styled runs correctly;
  the browser snapshot had discarded the ordering between an element's text nodes
  and inline child elements, so the mapper could only emit each DOM fragment alone.
  Snapshot v1 now optionally carries each text/element child-node index. For live
  captures, paragraph/heading-family containers whose descendants are inline text
  only—and have no box decoration requiring an independent layer—are reconstructed
  as one fixed EXP text box with DOM-ordered runs and CSS whitespace collapse.

  Link color/underline, installed font fallback, size, bold and italic faces survive
  per run; `<br>` survives inside the same box. Nested block/layout content and
  decorated inline boxes conservatively retain the existing node mapping. Because
  EXP has no substring-level `href` field yet, the link destination is not guessed:
  the visual run is retained and the destination limitation appears in the Import
  Report. The production WKWebView test now asserts exactly one mixed paragraph per
  viewport, exact string order/spacing, distinct link/bold/italic runs, and zero
  TextKit-excluded characters. Mapper, full Debug build, Figma, 11-package XD corpus,
  and both semantic HTML suites pass.

- **2026-08-03 (E1b imported text clipping) — fixed at the translation boundary.**
  Owner's Phone/Desktop screenshot showed red overflow badges and omitted final
  lines across headings, paragraphs, navigation, and footer text. The saved design
  proved the canvas renderer was behaving correctly for the frames it received:
  the importer had stored browser `Range.getClientRects()` ink unions as finite EXP
  text boxes. A five-line 16px/24px paragraph therefore arrived as 114pt instead of
  its five full 24pt line boxes (120pt), and a single 24px/36px heading arrived at
  the exact boundary TextKit can reject. The importer now retains measured origins,
  expands only the final missing CSS line-box tail plus a 1pt vertical engine
  tolerance, and carries a bounded 2pt horizontal tolerance for measured WebKit vs
  CoreText differences (observed maximum 1.77pt in fixture 2).

  The other reflow source was the fixture's intentional unavailable primary font:
  computed style retained `"Definitely Not Installed", Helvetica, ...`, but EXP
  kept the first name and fell back to SF while WebKit had advanced to Helvetica.
  HTML import now walks the CSS family list to the first installed face, applies
  requested bold/italic traits, and records the substitution in the fidelity
  report. Native/authored EXP text rendering and clipping were not loosened.
  `verify_rendered_html_webkit.sh` now runs every imported fixture text node through
  a canvas-equivalent finite TextKit layout and fails if any non-whitespace character
  is excluded; Phone + Desktop pass with zero clipped nodes. Deterministic mapper,
  full Debug build, Figma, 11-package XD corpus, and both semantic HTML suites pass.

- **2026-08-03 (E1b viewport dialog no-op) — Xcode exception identified and
  fixed.** After the folder chooser, `HTMLViewportSelectionController` activated
  a width constraint between its summary label and stack view before adding the
  label to that stack. AppKit raised `NSGenericException` for anchors with no
  common ancestor, caught it at the File-menu action boundary, and left the user
  with no dialog or visible failure; the “Animating backwards in time” messages
  were incidental animation fallout. The label is now inserted before the
  constraint is activated. The unsigned Debug build and real WKWebView fixture
  suite pass.

- **2026-08-03 (E1b folder chooser no-op) — reproduced in the native UI and
  fixed.** Navigating into the fixture directory and pressing Choose Folder
  dismissed `NSOpenPanel`, but AppKit supplied the directory as `directoryURL`
  with no selected-item `url`. The importer treated that valid state as a silent
  cancellation, so the viewport chooser never appeared. Source selection now
  falls back to the panel's visible directory, explicitly scopes the directory
  while enumerating it, recognizes `.html`/`.htm` by extension when Uniform Type
  metadata is unavailable, and shows an actionable error if neither URL exists.
  The unsigned Debug app rebuild and real WKWebView fixture suite pass.

- **2026-08-03 (E1b local HTML/CSS vertical slice) — implemented and ready for
  owner visual acceptance.** Added the production `RenderedHTMLWebKitCapture` and
  connected File ▸ Import HTML/CSS… to E1a's pure mapper. The flow now asks for
  the containing folder (the actual App Sandbox permission boundary), selects an
  HTML entry file when needed, offers the five Mobile/Web artboard presets with
  Desktop 1440 as the sole default, renders each selected viewport in a short-lived
  non-persistent WKWebView, and inserts the resulting editable artboards beside the
  active page in one `Import HTML/CSS` undo step. Progress and cancel use the shared
  `InteropContext`; failures leave the document untouched; fidelity limits remain
  available through Show Last Import Report.

  Local resources are served through a same-origin `exp-local` scheme so external
  stylesheets remain CSSOM-inspectable without granting `file://` or network reads.
  The handler resolves symlinks and standardizes paths before enforcing the selected
  folder boundary. Remote HTTP(S)/file resources are blocked, navigation away is
  cancelled and reported, storage is non-persistent, rendering has a 10-second
  deadline and settle window, and the 15,000-node / 64 MB caps now apply to the
  whole multi-viewport import rather than resetting per viewport. Real WebKit also
  exposed two assumptions that were corrected instead of hidden: CoreGraphics CGRect
  Codable expects the nested pair shape, and public WKWebView does not let EXP pin
  backing DPR to 1. Geometry remains CSS px → EXP pt; actual DPR is recorded and its
  resolution-dependent resource risk is reported.

  `verify_rendered_html_webkit.sh` now runs the handwritten fixture through the
  exact production browser/capture/mapper path at Phone 393 and Desktop 1440. It
  proves responsive stacking vs columns, media-query notes, editable measured text,
  gradient and shadow mapping, cancellation, import-wide truncation reporting, the
  local Sources receipt, and rejection of a symlinked stylesheet escaping the trusted
  folder. The deterministic mapper check and unsigned Debug app build pass, as do
  the Figma fixture, all 11 XD packages (644 artboards / 84,208 layers), semantic
  HTML contract, and deterministic semantic package suites. **Current honest limits:**
  local image bytes still become visible placeholders, transforms/filters remain
  measured-box approximations, and ARIA reconstruction remains deferred to the
  already-required official-spec verification. **NEXT:** owner-test the File menu
  flow/visual result/one-step Undo; then E1c adds the iterative remote-origin
  Sources/import-session UI on this proven seam.

- **2026-08-03 (E1 dev kickoff) — the browser payload now has an executable native
  destination.** E0 was already complete despite `AGENTS.md`'s stale “Next: E0”
  line, so work resumed at the actual next unchecked box: E1. Added
  `Model/RenderedHTMLImporter.swift` with three deliberately separated parts:
  (1) a fixed Codable snapshot contract for viewport/document/DOM rects, direct-text
  rect unions, allowlisted computed styles, authored attributes, and `data-exp-id`;
  (2) a read-only extraction script that measures the already-rendered DOM without
  fetching or mutating anything; and (3) a pure snapshot → `InteropImportResult`
  mapper. That seam matters: browser/security behavior can be tested independently
  from EXP geometry, and fixture payloads can exercise the same production mapper
  deterministically.

  The first mapper slice creates one page with one static artboard per viewport,
  using measured content height rather than `scrollHeight`; preserves DOM groups,
  browser-measured text boxes and heading/paragraph content roles; maps solid and
  linear-gradient backgrounds, borders, radii, first box shadow, opacity, and blend
  mode; carries render-height/media-query facts into artboard notes; and reuses valid
  EXP UUIDs from `data-exp-id`. Image bytes, CSS transforms/filters, and ARIA
  reconstruction are visibly reported, not silently guessed. The last item is
  intentional: the remaining explicit-role/state decisions still require the
  official-spec verification already named in E1, so this geometry slice does not
  smuggle them in by memory.

  Added `scripts/RenderedHTMLImporterCheck.swift` and
  `verify_rendered_html_importer.sh`; the two-viewport handwritten-style fixture
  passes geometry, text, gradient-angle reversal, inside border, radius, shadow,
  notes, and extraction-metadata escaping. The full unsigned Debug app build passes,
  as do the Figma importer fixture, all 11 real XD packages (644 artboards / 84,208
  layers), semantic HTML contract suite, and deterministic semantic package suite.
  **NEXT:** E1b — put the extraction behind a non-persistent, cancellable local-file
  WKWebView and prove fixture 2 end to end at Phone + Desktop before adding the
  remote-origin Sources/session UI.

- **2026-08-01 (component text-override paragraph alignment) — fixed.** Text
  overrides preserved the source paragraph's center/right alignment value, but the
  resolver always replaced the node frame with the string's auto-width measurement.
  With no remaining horizontal space, centered text looked left-aligned. Text-content
  overrides now measure through the text box mode everywhere: auto-width labels still
  hug (and auto-layout components can re-hug), while fixed boxes retain their authored
  width and visibly honor center/right alignment. Component-state editing, runtime
  instances, and semantic HTML resolution now agree. Full Debug macOS build succeeds;
  **owner visual verification pending.**

- **2026-08-01 (component-state fixed-text geometry + nested-SVG contrast audit) —
  corrected both owner screenshot repros [a11y/components].** Applying a state
  `textStyle` override always re-measured the text node, including paint-only color
  changes, and always used auto-width measurement. A centered fixed text box could
  therefore collapse from its authored width to one glyph; resizing the shared base
  geometry then appeared to do nothing in that state because the preview immediately
  collapsed it again. Text-style overrides now reflow only for metric-affecting
  properties, and any such reflow retains a fixed box's authored width. Runtime and
  semantic-HTML state resolution use the same rule.

  The contrast formula and thresholds were not the fault. The component audit only
  recognized a direct sibling fill, so an imported SVG group containing the actual
  dark/green path fell through to the white fallback: white text falsely scored 1:1
  and black text falsely scored 21:1. It now descends through overlapping container
  groups to the topmost painted child and includes layer opacity. The inspected
  default dark fill (`sRGB 0.045`) now resolves to about 19.63:1 against white.
  Large-text classification is also corrected to 18pt regular / 14pt bold, per
  [WCAG 2.2 SC 1.4.3](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).
  The audit remains deliberately advisory: gradients use a representative stop and
  vector overlap is bounds-based rather than pixel-sampled. Full Debug macOS build
  succeeds; **owner visual verification pending.**

- **2026-08-01 (group stroke state + rotated-group resize regression) — corrected
  both repros from the owner screenshots.** The first stroke-button diagnosis was
  disproved and its `EXPSegmented` refresh workaround was removed. The actual issue
  was the inspector's representative-value getter: `flattenStyleTargets` visits a
  selected group before its children, and a plain group returned hard-coded Solid /
  Center defaults even though the recursive setter correctly updated its stroked
  descendants. Plain containers now defer to the first applicable child; auto-padding
  groups still report their own border.

  The rotated-group screenshot came from two competing transform systems. In the
  inspected `paper&pencil-ui.design` repro, a roughly 1201×172 group contains two
  paths rotated 270°, so the legacy raw-frame box was horizontal while the newer
  child-aware visual box was vertical. A selected group now draws only the
  rotation-aware unified box, and the hidden legacy resize/rotate hit targets are
  disabled whenever that unified transform is active. Full Debug macOS build
  succeeds; **owner visual verification pending.**

- **2026-08-01 (§8 complete) — the element table is verified end to end, and most of a
  real page turns out to have no EXP equivalent [a11y/interop]:** A subagent read the
  live spec — HTML-AAM 1.0, **W3C WD 29 July 2026** — section by section and returned
  ~70 element→role rows verbatim, including all 23 `input` states. `web_fetch`
  truncates the document at §3.5.47 no matter which mirror is used, which is why this
  needed a different approach rather than more attempts.

  **The assumption I shipped is now verified.** §3.5.50: `<header>` scoped to `main`
  or sectioning content → **`sectionheader`**, exactly parallel to `<footer>`. BUG-018
  put `banner` into `needsExplicitRoleWhenNested` on reasoning-by-symmetry with a
  comment naming itself as the line to change if wrong. The reasoning was right, and
  the comment now carries the citation instead of the hedge. §3.5.114 independently
  re-confirms `<section>` → `region` only with an accessible name.

  **Four new rules, each forced by something the spec actually says.**
  (6) **`generic` and `paragraph` are the DEFAULT, not a loss.** Every `<div>` is
  `generic` and every `<p>` is `paragraph`; reporting each under rule 5 would bury the
  Import Report in thousands of rows — the same failure the 2,000-entry manifest cap
  exists to prevent. Rule 5 now applies to NON-generic roles with no EXP equivalent:
  `sectionheader`, `sectionfooter`, `status`, `row`, `cell`, `gridcell`, `rowgroup`,
  `columnheader`, `rowheader`, `combobox`, `article`. (7) **Never infer a role from an
  element name where the spec disagrees** — `<menu>` is `list`, NOT `menu` (§3.5.91);
  an importer that inverted the forward table by name would get this exactly backwards
  on any non-EXP page. (8) **Some roles depend on rendering or ancestry, not markup**,
  and since the importer HAS the rendered tree it must resolve them rather than guess:
  `<select>` splits on how it renders (listbox vs combobox), `<td>`/`<th>` take
  `cell` vs `gridcell` from the ancestor table's role, `<li>` is `generic` outside
  `ol`/`menu`/`ul`, `<summary>` depends on position within `details`. (9) **`alt=""`
  alone does not mean presentational** (§3.5.57) — an empty-alt `<img>` reverts to
  `image` if it has an accessible name from another mechanism.

  **Nine `input` types have no ARIA role at all** — Color, Date, Local Date and Time,
  File Upload, Hidden, Month, Password, Time, Week — computing to non-ARIA tokens like
  `html-input-date`. These are ordinary form controls, so any importer assuming
  `input` always yields an ARIA role is wrong nine ways.

  **The scoping consequence worth sitting with.** Counting what EXP can actually
  represent: `row`, `cell`, `rowgroup`, `columnheader`, `rowheader`, `combobox`,
  `status`, `paragraph`, `article`, `sectionheader`/`sectionfooter` — a real page's
  tables, forms and prose land largely outside EXP's role vocabulary. That is not a
  reason to widen the vocabulary; it is the reason rule 5 exists and why rule 6 had to
  be written before the mapper, or the report would have been unusable on the first
  real page.

  ARIA note per WORKING-AGREEMENT: everything above is cited to a numbered HTML-AAM
  section against a dated Working Draft. NOT verified and still open: `aria-*` state
  mapping (needs WAI-ARIA 1.2 role definitions) and explicit-role-contradicts-host
  (needs ARIA in HTML role prohibitions). Elements outside the current forward table
  (`details`, `fieldset`, `dl`, `label`, `meter`, `svg`, …) were not requested and are
  unchecked.

  NEXT: E1's mapper. The a11y groundwork it depends on is done.

- **2026-08-01 (BUG-018) — nested landmark export fixed, and my own bug report
  corrected [a11y/export]:** DONE — owner ran `verify_semantic_html_package.sh` and
  all seven checks pass, including the new
  `ok: nested landmarks keep their authored role (BUG-018)`. First try, no build
  fixes needed.

  **First, the correction.** The original BUG-018 entry claimed the exporter had no
  landmark ancestry check at all. **That was wrong.** `SemanticHTMLExporter` already
  carried `if (role == .banner || role == .contentinfo), !semanticAncestors.isEmpty`.
  I had grepped for `ancestry`, `landmark`, and `sectioning`; the code says
  `semanticAncestors`, so the search missed it and I reported absence rather than
  saying I could not find it. The backlog entry now leads with the correction, because
  a wrong bug report that quietly becomes a right one teaches the next reader nothing.

  **What was genuinely broken, and is now fixed.** Two things. (1) **`complementary`
  was never escalated.** HTML-AAM §3.5.10: an `<aside>` inside sectioning content
  computes as `complementary` ONLY with an accessible name, `generic` otherwise. So a
  nested EXP `complementary` exported as a bare `<aside>` and lost its role silently,
  with nothing reported. (2) **`!semanticAncestors.isEmpty` was a proxy, not the
  rule.** Only sectioning content and `main` rescope a nested header/footer/aside — an
  EXP `banner` inside a `group`, `toolbar`, or `list` (all `div` hosts) is still scoped
  to `body` and already computes as `banner`, so the old condition emitted a redundant
  `role` attribute that ARIA in HTML calls NOT RECOMMENDED. Added
  `AriaRole.hostRescopesNestedLandmarks` (host tag in `article`/`aside`/`nav`/
  `section`/`main`; `search` and `form` deliberately excluded — landmarks, but not
  sectioning content, so they do not rescope a descendant) and
  `AriaRole.needsExplicitRoleWhenNested` (`banner`, `contentinfo`, `complementary`).

  **Test covers the negative as well as the positive**, because the tightening half of
  this fix is only observable as an ABSENCE. `Fixture.nestedLandmarksDocument()` puts
  the same three landmarks inside a `region` host (`<section>`, rescoping) and the same
  banner inside a `toolbar` host (`<div>`, not rescoping); the check asserts exactly
  ONE explicit role each and exactly two `<header>` hosts. A test that only checked
  "role is present" would pass on the buggy code.

  **Still not verified, and left visible in the code.** `<header>` scoped to sectioning
  content is HTML-AAM §3.5.50, which the truncated spec fetch never reached, so
  `banner` sits in `needsExplicitRoleWhenNested` by the same reasoning as `<footer>`
  §3.5.44 rather than by citation. The doc comment says so and names itself as the one
  line to change if that reasoning is wrong.

  Knock-on for E1: EXP's own exports now state nested landmark roles explicitly, which
  simplifies fixture 1's round trip — §8 rule 1 (read the explicit `role` first) does
  the work, with no ancestry inference needed on the import side for EXP-authored HTML.

  NEXT: owner runs `scripts/verify_semantic_html_package.sh`; then either the remaining
  §8 rows (resume at HTML-AAM §3.5.50) or E1's mapper.

- **2026-08-01 (ARIA verification) — the reverse check found a forward bug, and
  corrected a row we had already marked verified [a11y/export/interop]:** Worked §8
  against HTML-AAM 1.0 ahead of E1's mapper, on the reasoning that verifying rows
  while trying to make a mapper compile is exactly when "verified, not remembered"
  erodes. Two findings justify the order.

  **A row recorded as VERIFIED on 2026-07-29 was wrong.** That session recorded
  "`<footer>` → `contentinfo` … otherwise `generic`." HTML-AAM §3.5.44 maps a
  `<footer>` scoped to `main` or sectioning content to **`sectionfooter`**, not
  `generic`. The wrong version would have had the importer silently produce a plain
  group and discard the semantic; the right version trips rule 5 — report it, never
  approximate — because `sectionfooter` has no EXP equivalent. First time that rule
  does real work. I did NOT fix `<header>` by symmetry even though §3.5.50 is almost
  certainly `sectionheader`: reasoning by symmetry is what produced the original
  error, so it is recorded as unverified.

  **BUG-018, P1: nested landmark roles are silently downgraded on EXPORT.** Checking
  the reverse mapping meant checking what the forward exporter emits, and
  `AriaRole.semanticHTMLMapping` returns `header`/`footer`/`aside` with
  `explicitRole: nil` **unconditionally**. So a nested EXP `banner` exports as a
  nested `<header>` that computes as `sectionheader`, a nested `contentinfo` as
  `sectionfooter`, and an unnamed nested `complementary` as `generic` (§3.5.10 —
  `aside` in sectioning content needs an accessible name). The authored role is lost
  and nothing in the handoff says so. SEMANTIC-HTML-CONTRACT.md claims "B2 performs
  the ancestry check and emits an explicit role only when necessary"; I could not find
  that check — two call sites, no context parameter, no landmark/ancestry logic
  anywhere outside the unrelated `phrasingOnly` branch. Logged with the search I
  actually ran so the next person can disprove it cheaply rather than trust me. **This
  is a shipped-v2.1 accessibility fidelity bug, not just an importer concern.**

  **Progress and honest remainder.** 15 rows verified with per-row HTML-AAM section
  citations (`a` with/without `href`, `article`, both `aside` scopings, `button`,
  `dialog`, `div`, `figure`, both `footer` scopings, `form`, `h1`–`h6`, `header`
  scoped to body, `section`). One of the four open questions is settled: `<a>` without
  `href` → `generic` (§3.5.3). The rest is blocked by a tooling limit rather than a
  judgement — the spec fetch truncated at §3.5.49, so everything alphabetically after
  `header` was not read. Recorded that way specifically, so the next session resumes
  at a known point instead of re-deriving what was covered.

  NEXT: BUG-018 before more rows, because how the exporter resolves nested landmarks
  changes what the reverse table should say.

- **2026-08-01 (post-spike design) — the import report gets hands: repair actions, and
  adjust stops being destructive-only [interop/import/ux]:** Owner asked whether the
  importer could work like a scrape tool they built previously — show the links it
  found, let the user fix by hand what didn't transfer. The answer is yes, and §4.3
  turns it from a convenience into a requirement: a webfont declared in a cross-origin
  stylesheet **cannot be enumerated by any means**, so for that class the manual path
  is not a fallback for weak automation, it is the only path that exists. New §5.1.
  Governing rule, owner's words: **if a fix takes one or two steps, the UI offers it.**
  Actions: copy URL / copy all unresolved; supply a local file onto a placeholder;
  open the source in the user's OWN browser (EXP never fetches it, so the
  credential-free posture is untouched); paste stylesheet text.

  **Pasting CSS needed a boundary, not a shrug.** §1 refuses pasted fragments, so this
  looked like a contradiction. It is not, and the distinction is written down: §1
  refuses a fragment as the ROOT of an import — no `<head>`, no font context, no
  unambiguous root box. §5.1 supplements an import that already has a rendered
  document and a real box tree; the CSS is resolution data, not a document. One
  honesty requirement falls out and is now §9 category 9: an import containing
  hand-supplied assets or CSS **declares that in the report**, because a handoff
  artifact that quietly blends served and hand-edited sources is exactly the silent
  guess §0 refuses.

  **The owner dissolved a collision I had framed as a fork.** Repair actions conflict
  with the 2026-07-29 "adjust re-renders and REPLACES" decision, since repairs are
  edits to imported content and would be destroyed. I offered three ways to resolve
  it; the owner supplied a fourth and better one: **adjust offers replace-in-place OR
  import-as-new-artboard beside the original.** Nothing has to become non-destructive,
  because nothing gets overwritten — the repaired artboard survives by being left
  alone. Cost recorded rather than glossed: repairs are NOT carried forward into the
  new generation, so ten hand-supplied assets means keeping the old artboard or
  re-supplying them. What it buys is that the choice is the designer's and is visible.
  Consequences: the session now records GENERATIONS with the viewport and trust set
  that produced each, each generation labelled so two artboards from one URL are
  distinguishable, undo still one step per adjust. This **supersedes surgical
  placeholder-fill for the manual-repair case** — its main justification — leaving it
  open only as an optimisation for newly-trusted resources.

  Accessibility is specified inline rather than left implied: no repair action is
  drag-only (a "Choose file…" button sits beside every drop target, because drag-only
  is unusable by keyboard and by anyone with a motor impairment), none conveyed by
  colour alone, all labelled in text.

  ARIA note per WORKING-AGREEMENT: nothing verified, nothing claimed; §8 untouched and
  the ~40 unverified rows still block E1.

- **2026-08-01 (fifth run) — confound removed, finding confirmed: E0's trust half is
  closed [interop/import/spike]:** With a real, valid woff2 in place the FontFaceSet
  reports `Fixture Brand — loaded`, the server log still shows `GET /brand.woff2` at
  both viewports, and the manifest still does not contain it. **A font that loads
  perfectly is fetched and never listed.** The parse-failure explanation is eliminated;
  §4.3's qualifier is gone and the finding stands unqualified.

  `R` returned exactly what `P` returned on every run (0 of 6, then 5 of 9), which is
  the expected result for two readouts of the same buffer — so E1 ships ONE of them,
  and the pair existed only to prove the buffer rather than the wiring omits the font.

  **The §10 criterion itself was wrong and has been rewritten.** It said "every
  subresource the server served appears in the manifest," which the platform makes
  impossible — a criterion no implementation could ever satisfy is not a standard, it
  is a promise to eventually lie about. The honest form: every served subresource
  either appears in the manifest OR falls into a class the report names as
  unenumerable. Recorded as a RESOLVED LIMIT rather than a pass, with the automated
  cross-check kept loud so that if the unlisted set ever grows past the known class,
  someone finds out.

  **E0's trust half is done.** Every fixture-3 criterion is settled: pass-1 purity,
  origin grouping including port and punycode, blocked-stays-blocked, the iterative
  case, per-viewport declared-vs-observed attribution, and the enumeration limit.
  Recorder verdict for E1: **`D` + `I`, with `P` or `R` as corroboration.** Three
  contract subsections came out of the spike that no amount of design discussion would
  have produced — §4.1 (iterative trust is normal), §4.2 (declared ≠ requested), §4.3
  (the receipt is incomplete, which is why trust is per origin).

  **Scope fork, resolved same session.** Fixtures 1 and 2's geometry, text-run and role
  criteria cannot be checked without a mapper, and the mapper is E1's substance. Owner
  decision: **E0 closes now; geometry fidelity is proven inside E1.** A spike does not
  de-risk a thing by building it — E0's job was the mechanism, and the mechanism is
  settled. Accepted risk, named rather than glossed: if a browser box tree maps badly
  onto EXP's model, that surfaces further in than it would have with a throwaway mapper
  built first. Fixtures 1–2's §10 criteria become E1's first proof.

  **Second owner decision: the unenumerable-resource limit surfaces as ONE NAMED ROW
  per unreadable stylesheet**, in the Sources pane and the Import Report, located with
  the origin it belongs to — not a standing note on every import (becomes boilerplate
  nobody reads, the exact failure the 2,000-entry cap exists to prevent) and not only
  when something visibly broke (that would couple a privacy-receipt fact to a
  visual-fidelity trigger, so a hidden tracker pixel would go unmentioned). The row
  appears whenever the stylesheet is unreadable, whether or not anything looks wrong.

  ARIA note per WORKING-AGREEMENT: nothing verified, nothing claimed; §8 untouched and
  the ~40 unverified reverse-mapping rows still block E1 regardless of which fork is
  taken.

- **2026-08-01 (fourth run) — the blind spot is WebKit's, not ours; and a confound in
  my own fixture had to be removed before saying so [interop/import/spike]:** The
  diagnostic added last round answered its question. `R` (polled resource timing) and
  `P` (PerformanceObserver) returned **identical** counts — 5 of 9, neither including
  `brand.woff2`. Two independent readouts of the same buffer agreeing means the
  omission is not a wiring bug on our side: the resource-timing buffer does not
  contain the font. `document.fonts` DOES name it, but only as a family
  (`"Fixture Brand"`), never a URL — so it can report that a font was used and never
  which file was fetched. The automated server-log cross-check now prints the finding
  directly: `⚠ FETCHED BUT NEVER LISTED — http://127.0.0.1:8732/brand.woff2`.

  **A confound in the fixture, found before the claim was written down.** The font was
  a placeholder text file that could not parse, and the readout said
  `font-face: Fixture Brand — error`. That leaves a hole in the reasoning: the
  omission might follow from the parse FAILURE rather than from the cross-origin
  declaration, and the contract would have been asserting more than the evidence
  supported. Replaced it with a real, valid woff2 — synthetic, four glyphs, built by
  `spike/html-import/fixture3-multiorigin/make-fixture-font.py`, so no third-party
  typeface is redistributed but the file genuinely parses — and made the `h1` actually
  use it. §4.3 records the finding with an explicit **"pending one confirming run"**
  rather than stating it flat. If the manifest still misses a font that loads cleanly,
  the finding stands unqualified.

  Everything else held on this run: pass-1 purity (one `GET /` per viewport), the
  iterative case, per-viewport declared-vs-observed attribution on `phone-hero.svg`,
  and the unreadable-stylesheet row. `D` and `I` remain the load-bearing recorder pair;
  `P` and `R` are interchangeable corroboration, so E1 ships one of them, not both.

  ARIA note per WORKING-AGREEMENT: nothing verified, nothing claimed; §8 untouched,
  ~40 rows still block E1. NEXT: one `fixture3` run with the valid font — if
  `brand.woff2` is still unlisted, drop the "pending" qualifier from §4.3 and E0's
  trust half is closed.

- **2026-08-01 (third run) — a font was fetched and never listed; trust-per-origin is
  vindicated by the failure [interop/import/spike]:** Per-viewport attribution works —
  `phone-hero.svg` now reads "393×852 declared C · observed P / 1440×1024 declared C ·
  NOT requested here", so §4.2's declared-vs-requested distinction is demonstrated and
  the union-manifest criterion is fully met. But the pass-2 server log, which survived
  for the first time after the `sed` fix, produced the real result.

  **`GET /brand.woff2` was served at both viewports and appears in NO recorder and NO
  manifest row.** A file was fetched over the network and never listed. Being precise
  about what broke, because the distinction is the whole finding: the **security model
  held** — the font came from `:8732`, an origin the user had trusted, so no
  unauthorised byte moved. The **receipt did not**. §9 category 7 calls the Sources
  report "the trust step's receipt, readable after the fact," and a receipt that omits
  a fetched file is not a receipt. Cause is §4.1's: the font is declared inside a
  cross-origin stylesheet whose `cssRules` cannot be read, and `document.fonts` exposes
  a font FAMILY, never the URL it came from. Nothing in the page's readable surface
  ever names it.

  **This retroactively justifies granting trust per ORIGIN rather than per resource.**
  Per-resource trust sounds stricter and more respectful; the spike shows it would be
  **unimplementable as an honest promise**, because you cannot ask someone to approve a
  list of files when files can be fetched that the list can never contain. Origin-level
  is the finest granularity that can be stated truthfully. The owner decided this on
  2026-07-29 for readability reasons — it turns out to have been the only correct
  option available. New §4.3, with three non-optional requirements: the Sources report
  names what it could NOT enumerate; no UI text anywhere claims completeness (a count
  is a count of what was *seen*); and the E1 test suite keeps a server-log cross-check.

  **The methodological point, which generalises past this feature.** Every in-page
  recorder missed the font. It surfaced only because an independent observer — the
  fixture's own web server — was asked what it actually served. Self-reported
  completeness is not evidence. That check is now automated in
  `verify_html_import_spike.sh` (manifest JSON vs server log, both directions) and
  currently FAILS on purpose, so the blind spot cannot regress into silence. Added a
  polled resource-timing recorder (`R`) alongside the observed one and a FontFaceSet
  readout, to separate "our PerformanceObserver missed it" from "WebKit never had it"
  — a diagnostic rather than a theory, since the cause is not yet established.

  ARIA note per WORKING-AGREEMENT: nothing verified, nothing claimed; §8 untouched and
  the ~40 unverified rows still block E1. NEXT: one run to see whether `R` or the
  FontFaceSet names the font at all. Either way E0's trust half is settled — the model
  is sound and its limits are now written down with filenames. E1's mapper is what
  remains, and it is what makes fixtures 1 and 2's geometry/text/role criteria
  checkable at last.

- **2026-08-01 (later) — Union manifest works; the sharper finding is that DECLARED
  and REQUESTED are different facts [interop/import/spike]:** Second fixture-3 run
  with the three harness fixes in.

  **Both open criteria moved.** `phone-hero.svg` appeared once the document's own
  origin was pre-allowed, and the media query is visibly resolving `true` at 393 and
  `false` at 1440 — the multi-viewport render is doing what §1.1 says. Content height
  now reads 442/406 against a viewport-clamped 852/1024, so the `scrollHeight` trap is
  confirmed as real and avoided.

  **But the union manifest didn't prove what it looked like it proved.** The CSSOM
  walk found `phone-hero.svg` at BOTH viewports, because the rule exists in the
  stylesheet at both — while the browser only *requested* it at 393. The manifest was
  unioning recorders and viewports separately, so the pairing was lost and "which
  viewport actually asked for this" was unanswerable. New §4.2. The framing that came
  out of it is worth keeping: **recorders are of two kinds.** `D` and `C` read what
  the page DECLARES; `I` and `P` OBSERVE what it requested. In pass 1 nothing is
  fetched, so everything is declaration-only by definition; in pass 2, a row still
  declaration-only at a viewport is one that viewport never requested. Both failure
  modes are real — under-listing hides something the designer should rule on, and
  over-listing inflates the trust list, which is how a list stops being read at all
  (the same failure the 2,000-entry cap exists to prevent). So rows are listed AND
  attributed. This also earns `C` its place despite catching almost nothing: it can
  see what an unselected viewport WOULD request, so adding a viewport can be warned
  about before the re-render that would discover it.

  **§4.1 confirmed with a concrete missing file.** `brand.css` was trusted, fetched
  and rendered — and its `cssRules` still threw, because it is cross-origin without
  CORS. The webfont it declares, `brand.woff2`, appears **nowhere** in the pass-2
  manifest despite its origin being trusted. A trusted third-party stylesheet can hide
  its subresources completely. That is no longer a predicted risk, it is an observed
  one with a filename.

  **Fixes this round.** Per-viewport recorder attribution (viewport → recorders, kept
  paired). Resource type normalised to one vocabulary — PerformanceObserver's
  `initiatorType` was overwriting the DOM's, so the same file read "style-sheet" in
  pass 1 and "link" in pass 2; §4 calls resource type per row a security detail, so it
  cannot drift between passes. Declaration recorders now win on type, since they know
  which element declared it. BSD `sed` aborted on the pass-2 server log
  (`Assertion failed: (advance > 0)`) and destroyed the ground truth for that pass —
  now stripped to printable ASCII under `LC_ALL=C`, and both raw logs are copied out
  so a crash in the pretty-printer can never eat the evidence again.

  ARIA note per WORKING-AGREEMENT: nothing verified, nothing claimed; §8 untouched and
  the ~40 unverified rows still block E1. NEXT: one more `fixture3` run to confirm the
  DECLARED vs OBSERVED block reads correctly, then E1's mapper — at which point
  fixtures 1 and 2's geometry, text-run and role criteria finally become checkable.

- **2026-08-01 — Spike ran first try; the trust model survives, and CSS blindness
  turns iterative trust into the normal path [interop/import/spike]:** Owner built and
  ran `scripts/verify_html_import_spike.sh`. It compiled and executed on the first
  attempt across all three fixtures.

  **The headline: the two-pass model reproduces.** Fixture 3's pass 1 saw 4 origins /
  6 resources with no trace of origin B (`:8733`). Trusting origin A let `widget.js`
  execute, and pass 2 saw 5 origins / 8 resources including both `:8733` URLs. §4's
  iterative-trust claim is now demonstrated rather than asserted. Pass-1 purity holds
  too, and the proof is external: the fixture's own server log shows exactly one
  `GET /` per viewport and no subresource of any kind. Blocked origins stayed blocked
  through pass 2. The IDN host arrived **already punycode-encoded**, because URL
  parsing performs IDNA — so §4's homograph rule is satisfied by construction rather
  than by remembering to encode, which is a better outcome than the one specified.

  **The finding that changes the contract (§4.1, new).** The CSSOM recorder caught
  ZERO resources, and the reason matters more than the number: **a blocked stylesheet
  has no rules to walk, so everything it references is invisible.** Webfonts,
  `background-image`, `border-image`, `mask-image` — none can appear in pass 1's
  manifest, because the CSS naming them was never fetched. Worse, a stylesheet that IS
  fetched but is cross-origin without CORS is equally unreadable (`cssRules` throws),
  so its resources stay hidden even after its own origin is trusted. Nearly every real
  page uses CSS backgrounds or webfonts, which means **the first trust list is
  structurally incomplete for almost every page** — not occasionally, as §4's original
  caveat implied. Three consequences now binding on E1: the Import Session UI must
  present the list as a starting point rather than an inventory; an unreadable
  stylesheet becomes its own manifest ROW naming what it hides (skipping it silently
  would conceal the resources AND the reason, so the designer could not tell a gap
  existed); and the revisitable session, justified as a convenience, is actually
  load-bearing, because a single-shot dialog cannot express a list that is knowably
  incomplete when shown. This is a UI-honesty problem, not a structural one, so E1
  absorbs it rather than being rescoped.

  **Recorder verdict, measured.** `D` (DOM walk) is load-bearing — 6 of 6 in pass 1,
  7 of 8 in pass 2. `P` (PerformanceObserver) reports NOTHING while blocked (0 of 6 in
  pass 1, 3 of 8 in pass 2), which answers the version-dependence question in the §2
  table: it is a pass-2 cross-check, never a discovery mechanism. `I` (instrumentation)
  caught only 2 of 8 but was the ONLY recorder that saw `config.json`, so it is small
  in count and irreplaceable in kind — script-initiated `fetch`/XHR has no other
  witness. E1 ships D + I with P as corroboration.

  **Three harness bugs found and fixed.** (1) `file://` URLs have no host, so every
  local resource was dropped and fixtures 1 and 2 reported empty manifests — fixed by
  treating the security-scoped DIRECTORY as the unit of trust, which is honest because
  it is exactly what §2's scoped read grants. (2) Pass 2 never pre-allowed the
  document's OWN origin (§4 says it is pre-allowed in the trust step), so the page's
  own stylesheet stayed blocked — which is what silently disabled the CSSOM recorder
  and left the union-manifest criterion untested. (3) An unreadable stylesheet was
  skipped in silence; it now reports itself, which is what turned bug 2 into finding
  §4.1. Also fixed: `grep` treated the pass-2 server log as binary and swallowed the
  ground truth, and fixture 1 was being probed at two web viewports when an EXP export
  is fixed-geometry — that measures the exporter's CSS reflow, not round-trip accuracy,
  so it now runs at one size.

  **A quieter finding with real consequences.** `scrollHeight` floors at the viewport
  height, so a page shorter than its viewport reports the viewport's height. §1.1 says
  the artboard is cut to full DOCUMENT height; using `scrollHeight` would have added
  trailing empty space that never existed in the browser. The probe now reports
  measured content height and the clamped value side by side.

  **Not proven, and deliberately not ticked.** Fixtures 1 and 2 currently show only
  that extraction runs and that layout differs correctly across viewports. Their
  geometry, text-run, and role criteria cannot be checked until a mapper exists — a
  probe that reports a box tree is not an importer that reproduces one. The
  union-manifest criterion needs the rerun. Session persistence and single-undo
  criteria are untestable outside the app.

  ARIA note per WORKING-AGREEMENT: nothing verified, nothing claimed; no §8 rows were
  touched and the ~40 unverified rows still block E1. NEXT: rerun
  `scripts/verify_html_import_spike.sh fixture3` with the fixes and confirm (a) the
  phone-only `background-image` appears attributed to one viewport, and (b) the
  now-readable same-origin stylesheet lights up recorder `C`.

- **2026-08-01 — Spike fixtures and probe harness written; the real finding is that
  WKWebView cannot report subresource requests [interop/import/spike]:** Built the E0
  spike apparatus. **Not yet built or run by the owner — nothing here is proven.**

  **The finding that shaped everything else.** `WKWebView` has no delegate for
  SUBRESOURCE requests — `WKNavigationDelegate` sees navigations only. Pass 1 of the
  trust model has to do two things simultaneously: block everything, and record what
  was attempted. Blocking is solved and is the half carrying the privacy guarantee
  (`WKContentRuleList` blocking every resource-type EXCEPT `document`, which is what
  lets the initial navigation through while nothing else moves). **Recording has no
  clean API at all.** Four candidate mechanisms exist and every one has a blind spot:
  a DOM walk misses runtime-constructed URLs; a CSSOM walk cannot read cross-origin
  stylesheets; patched `fetch`/XHR/`Image` miss markup-declared resources and can be
  defeated by a page that captures the originals first; `PerformanceObserver` may or
  may not report blocked entries depending on WebKit version. So the harness runs
  **all four at once and prints which caught what**, and the run ends with a RECORDER
  COVERAGE block naming every resource caught by exactly one recorder — that recorder
  is then load-bearing and cannot be dropped. This is why §4 already says "requests
  observed during the render window" rather than promising an exhaustive list; the
  wording was written before the mechanism was understood and it turns out to be
  exactly right. Anything the server log shows but no recorder caught is a blind spot
  to NAME in §4, not to quietly tolerate. Contract §2 now carries the mechanism table.

  **Fixtures.** Fixture 1 is generated rather than committed: the runner compiles the
  existing `SemanticHTMLPackageCheck` and exports the golden-fixture document, so
  ground truth via `data-exp-id` costs nothing and needs no app run. Fixture 2 is
  hand-written with exactly ONE media query at 768px, so any difference between the
  393 and 1440 imports traces to one rule — plus a guaranteed font fallback, gradient,
  radius, shadow, mixed bold/italic runs, and prose long enough to wrap differently at
  the two widths, which is how an importer that re-ran line breaking instead of
  measuring gets caught. Fixture 3 runs **three loopback origins on different ports**
  via a small `serve.py`: same host, different port is still a distinct origin, which
  also checks the manifest groups by scheme+host+PORT rather than host alone. Origin B
  (:8733) is reachable only once origin A's `widget.js` is trusted and executes —
  making §4's iterative-trust claim reproducible rather than asserted. If pass 2's
  manifest does not grow, the two-pass model is wrong and E1 gets rescoped. Also in
  there deliberately: a `background-image` inside the phone media query (one resource
  at one viewport only, proving the union manifest), a never-resolving IDN host for
  punycode, and one real remote origin so the manifest is not purely loopback. The
  server's own request log is the ground truth for "pass 1 fetched the document and
  NOTHING else" — an external check, not the harness marking its own homework.

  **Owner scope decision, and it bounds E1.** Responsive behaviour is READ, then
  DISCARDED. Media queries resolve each viewport's layout and nothing more; EXP nodes
  never carry breakpoints, container queries, or fluid rules, and three viewports
  produce three independent static artboards rather than one that reflows. Where a
  media query materially changed a layout, that is Import Report prose and optionally
  artboard NOTES text — description, never mechanism. Owner's rationale: responsive
  behaviour belongs in code, where it is written, tested and shipped; modelling it on
  canvas would be a worse CSS inside a design tool, and would make the export LESS
  faithful because it would have to invent breakpoint syntax nobody asked for. Useful
  side effect for E1: the importer never has to decide which of several competing
  rules wins, because it only ever reads a resolved render.

  **Housekeeping.** `docs/*` is gitignored with an allowlist and
  `HTML-IMPORT-CONTRACT.md` was never added to it, so the E0 deliverable was sitting
  untracked in one working copy. Added. (`WORKING-AGREEMENT.md`, `DESIGN-ASSETS.md`,
  `BACKLOG.md`'s siblings and the PERF docs are still untracked — left alone, since
  that may be deliberate. Worth a decision.) Spike-generated artifacts are ignored;
  the fixtures themselves are tracked. Harness compiles with `-swift-version 5` on
  purpose — throwaway delegate callbacks are not where Swift 6 concurrency
  annotations earn their keep, and shipped E1 code does not get that exemption.

  ARIA note per WORKING-AGREEMENT: **nothing verified this session, nothing claimed.**
  No §8 rows were touched; the ~40 unverified reverse-mapping rows, `aria-*` state
  mapping, `<search>`, and `<a href>` still block E1. NEXT: owner runs
  `scripts/verify_html_import_spike.sh` and reads the output against §10 — this is the
  first code in Chunk E, so expect the build to need a pass or two.

- **2026-08-01 — E0 contract accepted; the viewport answer turned out to be an
  architectural change [interop/import/docs]:** The owner read
  `HTML-IMPORT-CONTRACT.md` and answered the four open questions, unblocking the
  spike. Three were straightforward. The fourth was not, and it is the one worth
  remembering.

  **Q3 was asked as "which viewport preset is the default?" and answered "make it a
  multi-select."** That is not a default-value change. Importing one page at three
  widths means: discovery must run once PER viewport and produce a UNION manifest,
  because a responsive page genuinely requests different resources at different widths
  (`srcset`, `<picture>`, media-queried `@font-face`, `matchMedia`-driven scripts) —
  discovering at one width and rendering at three would hand the designer a trust list
  that is quietly incomplete, which is exactly the failure the two-pass model exists to
  prevent. Each manifest row therefore records WHICH viewports asked for it, while
  trust stays granted per SESSION rather than per viewport: splitting it per width
  would multiply the decisions without making any one of them better informed.
  Downstream, the preview pane becomes per-viewport (keyboard-reachable switcher,
  width labelled in text), report categories 1–5 split per viewport while 6/7 stay
  session-wide, the render deadline is per pass per viewport while node/payload/manifest
  caps stay import-wide, and folder × viewport becomes a matrix — 6 files × 3 widths is
  18 artboards, so the sheet states the count before running. Two smaller calls made
  while writing it up, both reversible by one sentence from the owner: the viewport
  list is filtered to the `Mobile` and `Web` `ArtboardPreset` groups (A4 and Story are
  not browser viewports), and preset HEIGHT is used for the render — so `vh` and height
  media queries resolve against something real — while the artboard is cut to full
  document height, with the report naming the height each viewport resolved against.
  Cap of 5 viewports per import, so "select all" has a known worst case.

  **The other three.** Q1: folder import puts one artboard per file on ONE canvas page
  — side-by-side comparison is the point of importing a folder; a crowded page with a
  large folder is filed as the known cost. Q2: re-importing a URL that already has a
  session defaults to ADJUSTING that session (reuses trust decisions, stops identical
  sessions accumulating) while keeping "Import as new" for the deliberate second
  import. Changing the viewport selection is likewise an adjust — re-render and
  replace, one undo step, same warning; appending only the newly-selected width is
  filed with the surgical-fill follow-up rather than built. Q4: passing the 2,000-entry
  manifest cap degrades to same-origin-only with the unlisted count reported, instead
  of refusing — refusal turns one heavy page into a dead end. The reverse risk is
  named in the contract: a page could exceed the cap precisely to bury a third-party
  origin, which is why overflow BLOCKS third parties rather than waving them through.

  §11 now records decisions instead of questions. ARIA note per WORKING-AGREEMENT:
  **this session touched no §8 rows and verified nothing new** — the ~40 unverified
  reverse-mapping rows, `aria-*` state mapping, `<search>`, and `<a href>` still block
  E1 and remain spec work against WAI-ARIA 1.2 / ARIA in HTML / HTML-AAM. Docs only;
  no code changed, nothing to build. NEXT: the three-fixture spike.

- **2026-07-29 — E0 rendered-HTML import contract drafted, incl. a two-pass source
  trust model [interop/import/docs]:** Wrote `docs/HTML-IMPORT-CONTRACT.md` (394
  lines) as the E0 deliverable: input boundary, WKWebView isolation, DOM/computed-style
  payload allowlist, resource/privacy rules, cancellation/limits, semantic-role reverse
  mapping, fidelity-report categories, and a three-fixture bounded spike.

  **The architectural consequence worth remembering.** The owner asked for a UI that
  shows every source a URL import pulls from, so each can be trusted individually. You
  cannot enumerate a page's sources without rendering it, and rendering is the thing
  being gated — so the import is **two passes**: pass 1 renders with everything blocked
  while RECORDING each attempted request (nothing is fetched, so the page neither
  receives nor sends data), the trust step presents that manifest grouped by origin,
  then pass 2 re-renders with only the allowed origins. Two honesty requirements fall
  out and are written into the contract: the manifest is "requests observed in the
  render window," not exhaustive (lazy loading), and **allowing a script can reveal
  requests pass 1 never saw** — which makes the trust list iterative by nature, and is
  why the revisitable Import Session is load-bearing rather than a convenience.

  **Owner decisions.** Trust granted per ORIGIN (expandable to resources; origin is
  the unit a person can reason about, the file list justifies the choice). Trust stored
  per document, opt-in, deliberately NO app-wide allowlist because a global one becomes
  "allow everything" as it outgrows anyone reading it. Adjusting an import re-renders
  and REPLACES as one undo step behind an explicit warning — owner rationale: a clean
  predictable import is the priority until real use cases exist. Surgical
  placeholder-fill (newly-trusted resources land in boxes already holding their space,
  preserving post-import edits) is recorded in the contract as a follow-up rather than
  discarded, with `data-exp-id` diff/merge noted as a third option and a project in
  its own right. Security specifics pinned down: punycode display so an IDN homograph
  cannot masquerade, resource type per row, status never conveyed by colour alone, and
  "trust" defined precisely as anonymous asset fetch for this import only — never a
  login, since the data store is non-persistent.

  **Auth boundary made explicit.** The owner's motivation is reaching online
  repositories of design code (hosted Storybook, GitHub Pages). Public ones work.
  Private repos and SSO-gated Storybooks are OUT, because storing tokens would undo
  the no-keys posture Chunk F was designed around — and the better path already exists
  in the plan: the designer's own agent has repo access, fetches the build, and hands
  EXP a local file or EXP Source. Same division of labour as the Agent Bridge: EXP
  does not reach out to services, agents and services reach in.

  ARIA note per WORKING-AGREEMENT: four reverse-mapping rows verified against ARIA in
  HTML / HTML-AAM with citations (`header`/`footer` ancestry scoping, `section`
  requiring an accessible name, `h1`–`h6`); the remaining ~40 rows, `aria-*` state
  mapping, `<search>`, and `<a href>` are recorded as NOT verified and explicitly
  block E1. NEXT: owner reads the contract and answers Q1–Q4, then the three-fixture
  spike.

- **2026-07-29 — Artboard notes overhaul, artboard placement commands, and a
  command-dispatch root cause [notes/artboards/chrome/infra]:** A long owner-driven
  session across nine areas; every item below was built, owner-built in Xcode, and
  owner-confirmed working unless noted.

  **Command dispatch (the important one).** `sendCanvasAction` only ever walked the
  responder chain UPWARD from the first responder, so when focus sat in the Layers
  panel or the Inspector — sibling subtrees, never ancestors of `CanvasNSView` — menu
  and panel commands silently did nothing. The menu items still looked ENABLED because
  enablement comes from `.focusedSceneValue(\.editorMenu)`, which is scene-scoped and
  survives focus moves; enablement and dispatch used different mechanisms and could
  disagree. An earlier fix had covered the across-WINDOWS half (floating tray becomes
  key → fall back to `NSApp.mainWindow`); this covers the within-one-window half by
  searching DOWN the key and main windows' view trees breadth-first, and logging
  `[EXP command] no target for <selector>` to DiagnosticLog instead of dropping the
  action with no trace — which is precisely why these were unreproducible. Six other
  raw `NSApp.sendAction(to: nil)` sites now route through it, including `selectAll:`
  fired from inside LayersPanel, which failed by construction rather than
  intermittently. Owner reports the symptom has not recurred; because it was
  intermittent this is not yet a definitive confirmation. Note SwiftUI `CommandMenu`
  buttons bypass AppKit responder validation, so `validateMenuItem` only gates the
  AppKit right-click menus, never menu-bar items.

  **Artboard notes.** Typing no longer touches the model: a local draft commits on a
  ~400ms idle debounce and on end-editing. It previously called `setModel` per
  KEYSTROKE — a full `Document` copy, a `resolveGeneration` bump invalidating the
  canvas instance cache, and one undo entry per character. A typing burst is now one
  "Edit Notes" step (first commit registers the undo, later commits in the session
  skip it, so an interrupted session is still recoverable). Notes buttons are culled
  to `visibleDocumentRect`; boards with notes always keep theirs, empty boards show
  the affordance only above 120pt on-screen width. The panel now pins its TOP-RIGHT
  34pt inside the board's left edge so it grows left into empty canvas instead of
  burying the board, resizes from the left edge / bottom edge / bottom-left corner
  against that pin (`pointerStyle(.frameResize(...))`), defaults to 320×180, reads
  "Notes for <board>", and gets a two-shadow elevation over an opaque fill (no
  material, so Reduce Transparency stays honest). Light formatting — bold, italic,
  one heading level, bullets, checkboxes — is drawn as ATTRIBUTES over the plain
  string via an `NSTextStorageDelegate`, restyled only on the edited paragraph and
  disabled above 20k characters. No rich text, no Markdown library, no renderer, so
  `Artboard.notes` stays a plain `String` and the model, codec, and agent contract are
  untouched. ⌘B/⌘I wrap the selection (Type ▸ Bold/Italic are disabled unless canvas
  text is being edited, so they don't collide) and a right-click Format menu exposes
  Heading/Bullet/Checklist so formatting is not keyboard-only.

  **Artboard placement.** Added an `exp.pref.artboardSpacing` preference (default 160,
  Settings ▸ Canvas) read live by both new-board placement and Clean Up. Align and
  Distribute now route by selection inside the EXISTING `align(_:)` /
  `distribute(horizontal:)` commands rather than shipping a parallel set — the owner's
  framing was that aligning boards is not a different verb from aligning layers.
  `moveArtboards` carries owned child nodes, capturing containment ownership BEFORE
  anything moves and applying one rounded delta to board and children together. Clean
  Up stays its own command (Finder's "Clean Up", not Align): it clusters boards into
  the rows they already roughly form, keeps each row's left-to-right order and the
  set's top-left origin, and re-flows at the spacing preference. Wired through Arrange,
  the artboard context menu, `validateMenuItem`, and a Properties Align section for a
  multi-board selection (scope row omitted for boards — a board has no enclosing board
  to align to).

  **Navigation.** "Zoom to Fit" never zoomed: it set `zoom = 1.0` then only CENTERED,
  so on any document spanning more than a screen at 100% it reliably landed in the gap
  BETWEEN boards. It now fits through `fitViewport(to:)` over boards ∪ loose nodes
  (`contentBounds` unions artboards only, and loose wall artwork is exactly what you're
  hunting when lost), and an empty page lands at the origin rather than adrift. Added
  Center Selection in View (⌘2), which preserves zoom unless the selection cannot fit —
  node bounds via `alignmentItems(documentSpace: true)`, since a nested node's own
  frame is parent-local. Canvas `keyDown` ⌘0/⌘1 had contradicted the View menu and now
  agrees (⌘0 actual, ⌘1 fit, ⌘2 center).

  **Layers + chrome.** Artboard section-header names are real controls: click selects,
  ⌘-click toggles, ⇧-click extends across displayed section order (its own anchor,
  deliberately not `app.selectionAnchorID`, with a fallback to the topmost selected
  board so a canvas selection can still anchor a range), double-click also centers, and
  right-click offers Select / Center / Rename / Duplicate / Copy / Move-or-Duplicate to
  Page / Expand-Collapse / Delete. Gestures are on the NAME only so the List's
  disclosure chevron survives. Selected boards now take the same `rowSelected` highlight
  a selected layer row does — they previously showed nothing, because `activeSectionID`
  resolves through `selectedArtboardID`, the single-selection accessor that is nil
  whenever more than one board is selected. Canvas page tabs rename on double-click
  (`simultaneousGesture`, since a Button consumes plain taps), with a named Rename
  accessibility action.

  **New artboard tool.** `Tool.artboard` (`plus.viewfinder`, alone at the bottom of the
  strip; the New Artboard menu button adopted the same symbol). Click places the same
  375×667 default the menu's primary action uses; drag gives exact bounds. Because node
  ownership is by CONTAINMENT, artwork the new board encloses is adopted on release — no
  move or reparent step, which was the whole point. Shortcut **F** (Figma's Frame key),
  with **⇧A** aliased for Sketch/XD muscle memory; plain A remains Edit Points
  (Illustrator's Direct Selection).

  **Numeric fields.** `numericStepping` lived in a `private extension View` inside
  MainWindow.swift, so every numeric field OUTSIDE that file had no arrow-key stepping
  at all — a visibility wall, not a per-site omission. Made internal; the gradient Angle
  and gradient stop Position fields in PaintEditor.swift are now wired. Gradient angle
  wraps rather than clamps in BOTH directions of its binding, so typing -45 yields 315,
  400 yields 40, and a legacy/imported negative angle displays correctly without
  rewriting the document. Swept bounds for consistency: text-layer stroke width was the
  only stroke field clamped at `min: 1` (now 0, matching the other four), `DimField`
  gained an optional `min` so W/H pass 0 while X/Y stay unbounded, and point rotation
  now wraps like the other two rotation fields (delta still taken pre-wrap, so the turn
  applied is unchanged).

  Filed BUG-017, FEAT-019, FEAT-020, INFRA-003 for the loose ends. NEXT: unchanged —
  E0, the rendered-HTML import contract, proving one bounded local HTML/CSS fixture
  through the browser-to-`InteropCodec` path.

- **2026-07-29 — v2.1 shipped; v2.2/build 13 development opened [release/docs]:**
  Closed the v2.1 final release gate after the owner confirmed shipment; the
  repository already carries the annotated `v2.1` tag plus the public build-12
  Sparkle metadata and release-notes page. Bumped every app and Quick Look build
  configuration to `MARKETING_VERSION 2.2` / `CURRENT_PROJECT_VERSION 13`, opened
  the v2.2 lane around Chunk E code/component import, and synchronized the live
  status docs. NEXT: E0—write the rendered-HTML import contract and prove one
  bounded local HTML/CSS fixture through the browser-to-InteropCodec path before
  expanding into the full importer or Storybook.

- **2026-07-29 — v2.1 website screenshot direction implemented [site]:**
  Replaced the older homepage product capture with the populated v2.1 workspace;
  replaced the component concept diagram with an overlapping real-product pair
  that shows both the nested-component system and a readable editor detail; paired
  the Design Language working panel with its CSS palette-import flow; and added the
  ARIA guide overview/detail pair beneath the existing three plain-language
  accessibility principles. The import + handoff workflow diagram remains in place
  by design, as does the text-led “accessible thinking” story. The near-duplicate
  empty-properties workspace and the more sparsely composed Link-vs-Button image
  were intentionally left unused. Updated the durable asset brief with the chosen
  files and rationale. Responsive layouts and the production Vite build pass.

- **2026-07-29 — Active Layers artboard rail spans expanded component trees [layers/UI]:**
  Screenshot review exposed a visual seam in the active-artboard accent rail:
  ordinary editable rows painted their own rail segment, while the virtual source
  layers disclosed beneath a placed component used a separate row implementation
  with no segment. The rail now belongs to each top-level outline subtree and is
  overlaid once across its complete disclosed height, so groups, component layers,
  and deeper nested component disclosures cannot interrupt it. Concrete rows keep
  a clear layout slot for alignment, and the independent selected-layer bar is
  unchanged. The signed universal Debug app, thumbnail, and bundled helper build
  passes; owner visual verification remains.

- **2026-07-28 — v2.1 release story, website features, and release docs aligned [site]:**
  Reframed the public feature story around the two large release cycles: the
  three-tab overview now leads with the native canvas, understandable nested
  components, and accessibility by intent; dedicated component and import/handoff
  sections explain source/state/override structure and EXP's open-workflow role;
  Design Language copy now includes type styles and standards-based handoff; the
  existing multi-window and contrast stories remain; and a separate accessibility-
  at-the-core section explains plain-language guidance, semantic meaning, and the
  honest testing boundary. Added durable image briefs for the owner's component,
  import/handoff, and refreshed Design Language graphics. Created v2.1/build 12
  release notes plus an exact archive/notarize/Sparkle/GitHub/site/update checklist,
  and synchronized the generated tester feature feed with nested components,
  pages, XD/Figma import, and Handoff. Public accessibility claims were checked
  against WAI-ARIA 1.2 (roles, states, properties, relationships, and names), the
  WAI-ARIA APG's “a role is a promise”/real implementation testing boundary, and
  WCAG 2.1 SC 1.4.3 contrast guidance. This verifies the wording and its refusal
  to claim automatic conformance; it does not re-test a downstream product built
  from exported HTML. NEXT: owner supplies final screenshots as desired, then run
  `docs/RELEASE-CHECKLIST-v2.1.md`.

- **2026-07-28 — F2 Handoff + panel IA owner acceptance complete:**
  Owner passed the remaining docked/detached, resize/collapse, export/package,
  keyboard/VoiceOver, system-appearance/contrast/transparency, and compact action-
  styling checks. The panel-generated user-scope Claude Code setup connected to
  the shipping bundled `exp-mcp` helper; `/mcp` exposed all six read-only tools,
  orientation/artboard/node/token reads returned correctly, changing the EXP
  selection produced fresh selection data, EXP displayed the connected client,
  and disconnect/disable returned through ready to off cleanly. F2 and the panel
  IA pass are closed for v2.1. Agent capability packs remain a separately scoped,
  optional follow-up and are not a release gate.

- **2026-07-28 — Handoff panel action rhythm aligned with the panel system:**
  Owner review found the initial large lime dialog buttons too prominent beside
  EXP's dense dock controls. Handoff export/package/copy actions now use one
  reusable compact panel style shared with Design Language: 24pt height, mini
  medium labels, semantic neutral field/border/hover/pressed tokens, consistent
  full-width rows, and leading action icons. Accent remains reserved for active
  state and connection feedback. Focused Debug app build and `git diff --check`
  pass.

- **2026-07-28 — F2 Handoff + panel/tool IA implementation ready for owner acceptance:**
  Added Handoff as a full dockable/floating/persisted panel with Export, Package,
  and Agent sections. Existing PNG/JPEG/PDF/SVG flows are surfaced without losing
  File-menu access; standalone semantic HTML/CSS and DTCG-token exports join the
  complete `.exph` package. The default-off local agent bridge can now be enabled
  and stopped live, reports readiness/errors/connection count/client identity,
  shows an explicit read-only badge and privacy boundary, provides Claude Code,
  Claude Desktop, generic stdio, and helper-path setup text, and supplies a
  connected-selection prompt affordance. Properties now gives Convert to Path,
  Outline Stroke, and selection-aware Pathfinder a visible home while preserving
  Object/context routes. Figma, all 11 XD packages, canvas pages, nested component
  graph, semantic HTML contract/package, deterministic goldens, `git diff --check`,
  and a signed universal Debug app/helper/Quick Look security matrix pass. Docked/
  detached visual behavior and the keyboard/VoiceOver/system-appearance matrix
  remain explicitly pending owner acceptance before F2/Panel IA are checked off.

- **2026-07-28 — Figma REST first implementation owner acceptance:**
  After live side-by-side review across pages, local components, text, images,
  masks, stroke patterns, rotated lines, nested alignment, buttons, auto-layout
  backgrounds, and color swatches, the owner called the editable Figma importer
  a solid first implementation. D2 live API/visual acceptance is closed. Honest
  report items remain for advanced constructs EXP cannot reconstruct exactly;
  OAuth/Keychain is still an explicit D3 product choice, and extreme-document
  performance remains deferred to its dedicated optimization phase rather than
  being mixed into importer acceptance.

- **2026-07-28 — Figma D2 absolute auto-layout child correction:**
  The owner-provided side-by-side and saved `figma-import-test.design` isolated
  the repeated horizontal offset: an enclosing Background was being counted as
  the first auto-layout item, so every real child moved by exactly the background
  width plus the configured gap. `Node` now persists Figma's absolute-in-layout
  intent; generated frame surfaces and `layoutPositioning: ABSOLUTE` children are
  excluded from stacking while retaining their authored coordinates. When such
  children exist, the imported outer frame remains the minimum layout size. A
  compatibility inference recognizes both enclosing legacy backgrounds and the
  exact already-stacked `Background.max + gap` fingerprint, so reopening the
  current test import can repair the button contents and swatch row without a
  mandatory reimport. The Figma fixture proves generated surfaces, explicit
  absolute children, and legacy repair. Focused Figma, all 11 real XD packages,
  canvas-page isolation, `git diff --check`, and the complete signed Debug app/
  helper/Quick Look build pass. OWNER VERIFIED 2026-07-28: buttons and other
  affected auto-layout content now look substantially better.

- **2026-07-28 — Figma D2 nested alignment + canonical line geometry:**
  Live cleanup exposed two related geometry gaps. Align/distribute still indexed
  only the top-level node array, so selected siblings inside a group passed UI
  validation but were silently skipped. The commands now resolve selections
  recursively, use the shared parent coordinate space for siblings, and use
  document-space visual bounds plus inverse transformed write-back for mixed
  parents and Align-to-Artboard (including rotated/flipped ancestors). Figma
  LINE nodes now normalize to one horizontal editable segment plus their true
  transform rotation; when reusable `size` is absent, vertical bounds become an
  exact vertical line instead of a false diagonal across the stroke's thin
  bounding box. `relativeTransform` is the canonical angle when supplied. The
  fixture proves dotted-line retention, missing-size vertical lines, and matrix
  rotation; focused Figma verification and the full signed Debug app/helper/
  Quick Look build pass. OWNER VERIFIED 2026-07-28: re-imported line geometry
  looks substantially better and distribute now works within the selected group;
  this correction is signed off. Broader Figma D2 acceptance remains open for
  any other live-file inconsistencies.

- **2026-07-28 — Figma D2a live visual-fidelity correction [text/rotation/strokes/masks]:**
  The owner's first side-by-side live import exposed three deterministic mapper
  errors: TEXT paint was read only from TypeStyle even though Figma keeps the base
  paint on the text node; rotated `absoluteBoundingBox` dimensions were treated as
  unrotated dimensions and rotated again; and `strokeDashes` were discarded. Text
  now inherits node fills before rich-run overrides, geometry uses Figma's
  unrotated `size` centered on the returned post-transform box, and vector paths
  preserve open/closed status. Added a backward-compatible semantic StrokePattern
  (`solid`/`dashed`/`dotted`) across lines, paths, rectangle/ellipse/polygon borders,
  auto-padding group backgrounds, component stroke overrides, canvas/raster/SVG/
  semantic HTML export, and accessible single/multi inspector controls. Figma
  dash arrays infer Dash vs Dot, and groups with marked mask siblings now activate
  EXP clipping instead of leaving the mask relationship inert. The focused Figma
  fixture now proves node-level text color, once-only rotation, unrotated size, and
  dotted-line mapping; Figma/XD/page/semantic suites and the complete signed Debug
  app + Quick Look/helper build pass. OWNER NEXT: rebuild, re-import the same Figma
  file into a clean document, and compare the colored text, grid/rules, slightly
  rotated icon, and masked portrait layers; then send the new report/screenshots
  for the next D2 gap.

- **2026-07-28 — Chunk D1 sanctioned Figma REST importer [interop/Figma/pages]:**
  Started Figma import on the accepted shared codec/report and canvas-page model.
  File ▸ Import Figma File now takes a Figma URL/key and a PAT with
  `file_content:read`; privacy copy is explicit, the credential is memory-only,
  never logged, and attached only to `api.figma.com` requests (never signed image
  CDN URLs). The cancellable client handles current file/image endpoints, bounded
  responses, access/not-found/rate-limit errors, path geometry, and image bytes.
  The defensive mapper creates one EXP tab per Figma canvas and editable artboards,
  nested containers, core shapes/vectors/text, gradients, images, effects, stack
  layout, named Design Language paint/type styles, and local component sources/
  placements. Unsupported fidelity is aggregated in the shared on-demand report;
  bound Variables are called out because Figma restricts their read endpoint to
  Enterprise accounts. Import appends uniquely named pages, focuses the first
  result, and is one undo step. A no-network two-page fixture proves pages, geometry,
  images, local components, styles, and URL parsing; XD, pages, semantic package,
  and full signed Debug app/Quick Look/helper checks pass. OWNER NEXT: create/use a
  PAT with `file_content:read`, import one small multi-page file first, then exercise
  the D2 real-file matrix above and send the Import Report for the first fidelity
  gap. Official API contract checked 2026-07-28: `GET /v1/files/:key?geometry=paths`
  is Tier 1; image fills come from `GET /v1/files/:key/images`.

- **2026-07-28 — XD importer owner acceptance complete [Chunk G/import]:**
  Owner confirmed the XD imports look good and remain editable as expected, and
  explicitly accepted closing the XD importer. Chunk G is complete: the shared
  offline codec, bounded package decoding, native editable mapping, large-corpus
  structural proof, visibility/placement behavior, corrected text geometry and
  tracking, embedded images/lines/groups, one-step merge, quiet success UX, and
  report-on-demand workflow are all in place. Known XD-only constructs continue
  to use explicit reportable approximations instead of pretending at exact source
  semantics; the absent character-style fixture remains documented but does not
  block the accepted rescue workflow. NEXT: Chunk D, using the same codec/report
  contract and mapping Figma document pages directly to the accepted canvas tabs.

- **2026-07-28 — Canvas pages owner acceptance complete [pages/tabs]:**
  Owner confirmed the browser-tab page workflow now feels done after the clipped,
  stable fast-pan tab chrome and transfer-focused destination camera follow-ups.
  Page creation/management, independent page cameras/content, single and multiple
  layer/artboard Move/Duplicate to Page paths, and destination reveal are accepted.
  The Canvas pages acceptance gate is closed; this is now the document boundary
  available to XD/Figma import mapping and later large-document performance work.
  NEXT: return to Chunk G visual-fidelity closure, then the sanctioned Figma REST
  importer can map source document pages directly onto this model.

- **2026-07-28 — Cross-page transfers reveal their result [canvas/pages]:**
  Owner confirmed the fast-pan tab isolation is much better and that moving more
  artboards between pages works, but the destination restored an unrelated old
  camera and required hunting across the wall. Move/Duplicate to Page now carries
  the transferred result bounds into the page-switch funnel: one artboard/layer is
  centered at no more than 100%, while a multi-selection zooms out only enough to
  show the complete moved set with padding. That focused camera becomes the page's
  remembered position; ordinary tab switches still restore their prior cameras.
  Page switches also discard any stale pan snapshot before drawing the destination.
  Full Debug app/Quick Look/helper build and focused canvas-page checks pass.
  OWNER NEXT: move one distant artboard, several nearby artboards, and a layer
  selection to an already-visited page; each destination should open directly on
  the transferred work, and switching away/back should return to that view.

- **2026-07-28 — Page-tab chrome isolated from fast-pan canvas [canvas/UI]:**
  Owner's large-document screenshot showed the entire tab strip flickering away
  during wall panning, with artwork temporarily composited through its frame. This
  was not tab-color transparency: the AppKit canvas's oversized pan/zoom halo
  backing could transiently composite above the adjacent SwiftUI tab sibling.
  The native canvas is now explicitly layer-backed and masks drawing to its own
  bounds; the SwiftUI representable is clipped as a second boundary, and the
  opaque tab strip has its own foreground compositing group. Static and fast-pan
  pixels therefore cannot enter page chrome. The full Debug app/Quick Look/helper
  build and focused canvas-page check pass. OWNER NEXT: repeat the 5% fast-pan
  test in `perf-test-2-1.design` and confirm the tabs, labels, background, and
  bottom divider remain completely stable through pan and settle.

- **2026-07-28 — Multi-selection page-transfer retarget fix [canvas/Layers/menus]:**
  Owner found Move to Page acting on only one item from a multi-selection. The
  transfer algorithm already handled multiple roots; the loss happened earlier,
  while an AppKit/SwiftUI contextual menu was tracking and the Layers List could
  retarget the clicked row before the submenu action fired. Canvas, exact-row
  Layers, and Edit-menu transfer requests now carry a snapshot of the complete
  selected layer/artboard id sets. The shared move/duplicate path consumes that
  snapshot, while a context click outside the selection still intentionally
  targets only the clicked row. Full Debug app/Quick Look/helper build and focused
  canvas-page/nested-component checks pass. OWNER NEXT: select three sibling layers
  (including across artboard/Wall sections), move them together from Layers
  right-click, then undo and repeat from Edit and the canvas context menu; repeat
  once with Duplicate to Page and with two selected artboards.

- **2026-07-28 — Browser-style canvas pages + cross-page transfer [canvas/model/import]:**
  Added first-class canvas pages as tabs above the canvas rather than mixing them
  into Layers. Each page owns artboards, wall layers, guides, root relationships,
  and a remembered camera; rendering, hit testing, selection, Layers, inspector,
  notes, export, Quick Look, and the Agent Bridge resolve through the active page,
  while component sources and Design Language remain shared document resources.
  Tabs support add, inline rename, deep duplicate, left/right reorder, and guarded
  delete with undo. Edit-menu and exact-row/canvas context-menu submenus now move
  or duplicate the current single/multiple layer selection—including a selected
  child without its enclosing group—or single/multiple selected artboards with
  their owned content to any other page. Moves preserve identity, duplicates remap
  the full subtree, and internal root relationships follow safely without creating
  invalid cross-page links. Schema/format v3 saves pages explicitly; v1/v2 files
  migrate into one `Page 1`. Focused page migration/deep-copy, nested component,
  relationship, semantic contract/package, and real XD import checks pass; the
  signed Debug app, Quick Look extension, and helper build succeeds. This creates
  the intended boundary for sanctioned Figma page mapping and lets inactive pages
  avoid canvas/Layers work, while deeper large-document performance tuning remains
  its own later phase. OWNER NEXT: run the Canvas pages acceptance matrix above.

- **2026-07-28 — Quiet XD success + report-on-demand + tracking units [import/UX/text]:**
  Owner verified the TextKit overflow/box and temporary-pan cursor fixes, then
  confirmed the imported XD artwork is otherwise visually strong and that the
  automatic success report reads like an error. Successful/approximated imports
  now reveal the artwork without a modal. File > Show Last Import Report preserves
  the complete selectable/copyable diagnostic on demand; an automatic warning is
  reserved for imports with actual unsupported or errored content. Adobe's XD API
  confirms `charSpacing` is stored in thousandths of the font size, so the importer
  now converts it to EXP's absolute-point tracking (`-20` at 20pt → `-0.4pt`) rather
  than exaggerating it to `-20pt`. The keyboard-shortcuts corpus regression now
  asserts negative tracking survives but remains normalized below 5pt; the full
  11-package corpus and Debug app/helper/Quick Look build pass. OWNER NEXT:
  confirm a clean XD import has no popup, inspect the report from File on demand,
  and spot-check one previously over-tight negative-tracking label.

- **2026-07-28 — Text overflow truth + temporary-pan cursor recovery [text/canvas/XD]:**
  Owner screenshot exposed hundreds of false red overset badges on imported XD
  point text and a Select cursor visually stuck as Pan. Text sizing had two
  competing models: auto bounds forced a `1.3 × font-size` minimum and wrapped
  bounds added three bottom points, while canvas drawing used TextKit. Removed
  those artificial pads. Fixed-box overflow now reuses the exact cached TextKit
  container that draws the layer and shows `+` only when non-whitespace characters
  were actually excluded—not for font leading, descender space, or trailing blank
  lines. XD mapping now preserves `positioned` as auto text, uses exact stored
  area-text width/height, and keeps auto-height text width while estimating only
  its missing height. Temporary Space-pan now observes key-up anywhere in EXP and
  clears on app deactivation, covering focus changes that previously stranded the
  hand cursor while Select was active. A 120-point TextKit probe confirms all
  glyphs fit a 156-point imported line box; focused XD corpus check and the full
  Debug app/helper/Quick Look build pass. OWNER NEXT: reimport
  `keyboardshortcuts.xd` (the badge cloud should be gone), verify a genuinely
  clipped fixed text box still gets one badge, compare auto-box bottom bounds,
  and release Space after moving focus to a panel/window to confirm cursor recovery.

- **2026-07-28 — XD import visibility/report follow-up [import/canvas]:**
  The owner confirmed `keyboardshortcuts.xd` decoded but appeared not to open.
  The report was a successful import; imported boards were intentionally placed
  beside existing work but the viewport stayed on the old location. Import now
  selects and fits the first imported artboard immediately, including ruler-aware
  centering and camera persistence. The completion dialog now explicitly says
  the import succeeded and that fidelity details are informational rather than a
  failure. Follow-up inspection confirmed the three source artboards do not
  overlap, but found that collision spacing ignored XD pasteboard layers (58 in
  `keyboardshortcuts.xd`); placement bounds now include every imported and existing
  wall layer, preventing repeated imports from colliding with off-board content.
  Debug app/helper/Quick Look build succeeds. OWNER NEXT: reimport
  `keyboardshortcuts.xd` and confirm its first artboard is visible after dismissing
  the report; Undo should still remove the whole import in one step.

- **2026-07-28 — Chunk G XD importer first slice + real corpus proof [interop/import]:**
  Added the shared `InteropCodec` read/write/cancellation/progress/report contract
  and the first offline Adobe XD codec. File > Import Adobe XD decodes the frozen
  ZIP/AGC package away from the main thread, offers cancellable native progress,
  places imported artboards to the right of existing work in one undo step, merges
  Design Language assets by value, and always presents a selectable/copyable
  Import Report. The mapper preserves editable artboards/groups, primitive and SVG
  vector geometry, rich text runs, core appearance, document-library colors and
  gradients (including authored names), embedded image resources, and prototype
  links as notes; repeated fidelity findings aggregate with occurrence counts.
  Line-only AGC geometry is derived from its endpoints, and repeated placements
  share lazily decoded image bytes instead of reinflating the resource. The ZIP reader bounds entry
  count/size and rejects encryption, ZIP64, unsupported compression, CRC/size
  corruption, and unusable artwork. A headless corpus runner decoded all 11 owner-
  supplied packages—644 artboards and 82,096 recursively counted layers—with
  finite native geometry; the full Debug app/helper/Quick Look build succeeds.
  Current reports intentionally call out image crop/container clipping, masks/
  effects, approximated text geometry/transforms, and component groups flattened
  without source/state identity. No character-style library assets exist in this
  corpus, so that mapping remains unproven rather than being claimed complete.
  OWNER NEXT: visually compare `UX-suppliment-slides.xd` first, then a richer file;
  verify progress/cancel, one-step undo, report copy, and save/reopen. NEXT CODE:
  close the reported image-crop/mask/component/text fidelity gaps before Figma REST.

- **2026-07-28 — Chunk I owner acceptance complete [nested components/semantics/export]:**
  Owner ran the remaining end-to-end matrix and confirmed every case passes: two
  placements keep independent nested overrides; source edits inherit correctly and
  reset returns to the nearest source value; duplicate and detach stay independent;
  save/reopen and Quick Look preserve the resolved result; Handoff export keeps
  unique nested ids, instance-qualified relationships, and advertised Component
  Props; semantic-containment recommendations remain correct without rewriting
  authored roles. Chunk I — nested components + semantic containment — is closed.
  NEXT: Chunk G/D, beginning with the shared importer/report pipeline and offline
  XD rescue before the sanctioned Figma REST path.

- **2026-07-27 — Chunk I headless/build closure + semantic golden repair [model/export/tests]:**
  Resumed after a one-off, non-reproducible beachball; the captured process was in
  a 100% CPU SwiftUI layout loop, but the exact build and large-document stress
  cases did not reproduce it, so no speculative production change was made. The
  Chunk I verification sweep then found two real test gaps: the nested semantic
  resolver check could not compile because its target helper was file-private, and
  the deterministic Handoff fixture still authored relationships through the
  retired legacy node array. Exposed the resolver to the module, migrated the
  fixture to canonical source/root anchors, and fixed root-anchored fidelity issues
  so they name the relationship subject rather than an arbitrary first artboard
  layer. Reviewed the complete golden diff: HTML/CSS and relationship output remain
  byte-for-byte stable; the intended changes are anchored data in `design.json`
  and the new README Component Props section. Anchored relationships, nested graph,
  semantic contract/package, and SVG suites pass; the full signed Debug app,
  Quick Look extension, and bundled helper build succeeds with existing warnings.
  Official WAI-ARIA 1.2/APG checks reconfirmed the existing relationship semantics;
  this pass changed diagnostics and test storage, not ARIA behavior.
  OWNER NEXT: run the short end-to-end Chunk I matrix—two placements with distinct
  nested overrides; source-edit inheritance + reset; duplicate and detach; save/
  reopen + Quick Look; Handoff export with unique nested ids, relationships, and
  Component Props; then confirm containment recommendations on the same document.

- **2026-07-27 — BUG-016 + FEAT-018 owner-verified and closed [layers/components]:**
  Owner confirmed the corrected exact-row layer context menu, nested child-only
  duplication, layer copy/paste, and independent Duplicate Component workflow all
  look and behave correctly. BUG-016 and FEAT-018 are now closed.

- **2026-07-27 — BUG-016 nested context-menu + clipboard UTI follow-up [layers/plist]:**
  Owner reported the first layer-duplication pass still failed and supplied a log
  repeating that `tapps.exp-design.nodes` was not exported. The missing Info.plist
  declaration was real and is now fixed (`public.json` conformance); the processed
  Debug app plist contains both the document and layer clipboard types. A live UI
  reproduction found the deeper nested-row failure: the shared model correctly
  inserted a child inside its group, but SwiftUI hoisted context menus from the
  recursively rendered child rows to the enclosing native List cell, so clicking
  the child still ran the GROUP row's command. Layer rows now use a pointer-only,
  exact-row AppKit context-menu surface; the SwiftUI menu remains for keyboard and
  accessibility invocation. In a fresh isolated Debug app, two rectangles were
  grouped, the first child was right-clicked, and Duplicate produced one unchanged
  group containing three rectangles with the new child selected. Command-C/V also
  produced a new layer. The Components-row Duplicate Component path was also run
  live and opened `Component 1 copy` in its source editor. Focused graph checks
  and the full unsigned Debug app + Quick Look/helper build pass; built plist
  verification confirms the UTI export.
  OWNER NEXT: repeat child Duplicate and Layers-focused Command-C/V in the normal
  Xcode run, where the console should no longer repeat the custom-type warning.

- **2026-07-27 — BUG-016 layer clipboard focus + FEAT-018 component-source duplication [layers/components/model]:**
  Owner found that selecting a Layers row left Command-C / Command-V inert and
  asked for Duplicate on every layer's right-click menu. Root cause was focus, not
  serialization: the canvas already owns a working JSON clipboard, but the focused
  SwiftUI List is outside its responder chain — the same gap Layers already worked
  around for Delete and arrow nudging. Layers now registers native Copy/Paste
  commands backed by that exact payload, routes Paste through the canvas placement
  engine, and exposes Copy + Duplicate on every editable row. Canvas clicks also
  reclaim keyboard focus from the last-used panel. Duplicate is recursive,
  selection-aware, and undoable. After the owner's clarification, the sibling-
  insertion rule also moved into the shared model path: duplicating a layer nested
  in a group inserts only that layer beside its original inside the same group; the
  enclosing group is not duplicated. A focused regression proves the containment
  and the ancestor+child no-double-copy case. The shared clone path freshens
  relationship ids and remaps both anchored and legacy targets.

  Added the deliberately separate **Duplicate Component** command to Components
  list/grid rows, instance context menus, and Object ▸ Component. It creates and
  opens a NEW source (`Name copy`, then `copy 2`) rather than placing another
  instance. All source-local layer/state/relationship identities and targets are
  remapped; nested references to other sources stay live; existing instances stay
  attached to the original. The focused graph check covers the full remap and copy
  naming, and passes. Full unsigned Debug build of app + Quick Look/helper succeeds
  with existing warnings only. OWNER NEXT: verify layer Duplicate and Copy/Paste
  from both canvas and focused Layers list, including a nested layer and source
  editor; then duplicate a stateful/nested component, edit the copy, and confirm the
  original plus existing instances do not change.

- **2026-07-27 — sixth-test handoff package audit [export/handoff]:**
  Audited the owner's fresh `sixth-test.exph` directly. All seven manifest hashes
  match; the package contains 3 artboards, 9 components, 974 design nodes, and 3
  semantic HTML pages. Every emitted DOM id is unique per page and all seven ARIA
  id references resolve. Nested tab-label overrides remain independent across two
  placements, depth-3 instance paths produce distinct DOM ids, and BUG-015's Hover
  override reaches CSS as `mix-blend-mode: color-dodge` while the source base stays
  Normal. The fidelity report is also doing its job: it reports the deliberately
  incomplete tab semantics (missing selected state/controls/name), orphaned
  relationships, unexpected target roles, and the three-tabs/one-panel advisory
  instead of inventing values or silently dropping data. Cross-checked the tab
  expectations against the W3C WAI-ARIA APG tabs pattern. One acceptance gap remains
  in this fixture: no layer has a public Text or Fill prop enabled, so the README's
  positive public-prop advertisement path is present but not actually exercised.

- **2026-07-27 — BUG-014 and BUG-015 owner-verified [components/state]:**
  Owner confirmed both fixes in the app. Deleting a component source now preserves
  its placed uses as in-position ordinary groups instead of apparently removing
  them, closing the dependent-source deletion portion of Chunk I. Layer blend-mode
  changes now remain specific to Default/Hover/Pressed rather than leaking through
  the shared component base. Both backlog entries are done; the source-dependency
  graph/deletion roadmap box is checked.

- **2026-07-27 — v2.1 bug verification sweep + two state/component fixes [components/state/export]:**
  Owner verified BUG-007, BUG-008, BUG-009, BUG-010, BUG-011, BUG-012, and
  BUG-013, plus the font picker's blank-row/scroll-to-current fix. Their backlog
  statuses are now done. Dependent-source deletion was the exception: deleting a
  source still appeared to remove every placed use. BUG-014 found the preserving
  model work was present, but `flattened` converted source-local children to
  document coordinates while retaining the instance frame; group rendering then
  added that frame again. The layers were drawn at twice their intended offset,
  often off-canvas. Children now stay local to the replacement group, and the
  focused regression asserts the composed document coordinate instead of blessing
  the bad pre-offset frame. Owner also found BUG-015: changing a layer Blend Mode
  while editing a component state leaked into Default and every sibling state.
  Blend mode now joins opacity/fill/type/outline in `InstanceOverride.Value`;
  capture keeps the base pristine, state/instance resolution reapplies it, JSON
  round-trips it, and semantic HTML's parallel resolver carries it into
  `mix-blend-mode`. `verify_nested_component_graph.sh` passes all graph, deletion,
  layout, state, containment, and round-trip checks. Full unsigned Debug build of
  app + Quick Look/helper succeeds with existing warnings only. OWNER NEXT: verify
  source deletion does not move any use, including one nested in another source;
  verify Default/Hover/Pressed can hold different layer blend modes through
  save/reopen and a placed instance.

- **2026-07-24 — Font picker: blank rows above the selection on first open [inspector]:**
  Owner reported the rows ABOVE the selected font showing as empty space until a
  real scroll brought them in. Cause is the `LazyVStack`: it only builds the rows it
  believes are visible, and the `onAppear` scroll ran BEFORE the popover had been
  laid out, so the container had no meaningful size and the surrounding rows were
  never built. Fixed by scrolling twice — once immediately, then again on the next
  main-queue turn, after layout, when the visible window is actually known. The
  second call has a comment explaining itself, because a duplicated-looking line is
  exactly what a future reader would tidy away and silently reintroduce the bug.
  Kept the `LazyVStack` rather than switching to `VStack`: a few hundred rows each
  rendering in a CUSTOM FACE is real work, and this panel is where PERF rounds 8
  and 10 found the ~6.2s hangs. Trading a laziness bug for a known performance
  hazard would have been the wrong direction.
  Owner feedback worth recording as a design decision rather than a compliment: the
  shorter popover "scrolls better with more control" than the old full-length menu,
  so the fixed 320pt height stays deliberate rather than arbitrary.
  Logged two more FEAT-008 ideas from the owner for v2.2 — type-to-jump and a
  search field — noting that with "Fonts used" and "Recent fonts" that makes FOUR
  filters over ONE list, not four controls.

- **2026-07-24 — FEAT-008(a): the font picker opens on the font you are using [inspector]:**
  Owner asked whether the typeface work was a future version or could ride along.
  It was logged for v2.2, but the entry had already noted (a) as independent and
  cheap, so it came forward on its own while (b) "Fonts used" and (c) "Recent
  fonts" stay with the panel pass — v2.1 is already carrying two model gates and
  did not need more surface area.
  The obvious implementation was a SwiftUI `Picker`, which gives scroll-to-selection
  and a checkmark for nothing. Rejected after looking at what the control is FOR:
  the existing menus render every family set in its own face, Picker menu items do
  not reliably honour a custom font, and quietly losing the previews to gain free
  scrolling would have been a bad trade in a design tool. `UI/FontFamilyPicker.swift`
  is a popover + `ScrollViewReader` instead, which keeps the previews and scrolls to
  the applied face on open. One shared view now replaces both call sites, so the
  single-text and multi-selection pickers cannot drift apart the way the two
  copies could.
  Small decisions recorded because they are the difference between "works" and
  "feels right": it scrolls with a `.center` anchor rather than `.top`, since
  picking a sibling face is the usual next move and you want the neighbours
  visible; the checkmark column is reserved whether ticked or not, so names stay
  aligned and the list does not jitter as the selection moves; a multi-selection
  shows a fixed label and ticks nothing, which is honest about there being no
  single value rather than picking one arbitrarily; and the System row is keyed on
  an EMPTY family to match the model's meaning of `fontName == ""` instead of
  inventing a family literally named System.
  It is also the home for the rest of FEAT-008 — "Fonts used" and "Recent fonts"
  are filters over this list, not another control.
  NEEDS OWNER BUILD. `UI/FontFamilyPicker.swift` is a NEW file and must be added to
  the app target (app only — the thumbnail extension has no inspector).

- **2026-07-24 — FEAT-017 chunk J-e: the acceptance matrix; nested overrides complete [scripts]:**
  DETACH turned out to need no code. It bakes `resolvedChildren`, which J-b already
  covers, so a nested override survives into the detached tree by construction —
  and the nested components below stay live instances carrying what they displayed,
  matching how source deletion already behaves. Verified rather than assumed, with
  the check kept as a regression guard, because "it works for free" is the kind of
  claim that stops being true silently.
  Four acceptance checks: a duplicate starts identical and then diverges without
  touching the original — both halves matter, since copying must preserve
  appearance AND editing must not leak; detach bakes the resolved value rather than
  snapping back to source; deleting a component source leaves no override holding
  an unusable path; and the whole DOCUMENT round-trips through save and reopen,
  which is the file the owner actually keeps rather than the single instance J-a
  covered.
  `AnchoredRelationshipCheck` now runs 17 cases spanning FEAT-012 (anchored
  relationships), FEAT-016 (the advisory table) and FEAT-017 (nested overrides).
  All five J chunks are written. Between them, the two big Chunk I model gates are
  closed: a relationship can cross a component boundary and resolve per placement,
  and a component's nested content can be varied per placement — which is what the
  owner originally could not do and what pushed them toward forking components.
  NEEDS OWNER BUILD + RUN.

- **2026-07-24 — FEAT-017 chunk J-d: nested overrides reach the export [export/handoff]:**
  Checked what already worked before changing anything, which was worth doing: SVG,
  PDF, and the canvas needed NO change at all, because they route through
  `resolvedChildren` and J-b had already covered them.
  Semantic HTML was the exception, and for an instructive reason.
  `semanticHTMLResolvedChildren` is a PARALLEL resolver — it deliberately keeps
  hidden layers so it can emit `hidden`, which is precisely why it does not call
  `resolvedChildren` — and it therefore missed J-b's push-down in complete silence.
  The canvas showed the overridden label; the exported HTML showed the source's.
  For a fidelity tool that divergence is the worst possible bug, because both halves
  look right on their own. Same call added, same position, before the reflow.
  The duplication is the hazard rather than the logic, so
  `checkSemanticResolverSeesNestedOverrides` now fails loudly if the two resolvers
  ever drift again — the check exists because I only found this by reading, not
  because anything reported it.
  `publicProps` is now advertised. It had been on `Node` for a long time and
  appeared NOWHERE in the handoff package, so a reader — a developer, or the model
  the owner wants writing component code — had to infer a component's API by
  reading the raw model tree, which is exactly the guessing a handoff exists to
  prevent. The README gains a "Component Props" section listing every field marked
  public, including those on layers inside nested components, addressed by the same
  path shape used everywhere else in this work (groups add no step: structure, not
  identity). Its stored meaning is preserved rather than quietly repurposed into
  permissions — false keeps an override EXP-local, true declares it part of the
  public contract, and this reports that declaration without gating anything.
  `verify_anchored_relationships.sh` now also compiles ColorMath, DesignLanguageIO
  and the exporter so the new check can run headlessly.
  NEEDS OWNER BUILD + RUN. Worth re-exporting the tabs file: two placements with
  different labels should now produce two pages whose text actually differs, and the
  README should list any public props.
  NEXT: J-e — the acceptance matrix (duplicate, detach, delete-source, save/reopen,
  Quick Look) and the remaining checks.

- **2026-07-24 — Override fields now show what the canvas shows [inspector]:**
  Owner: *"the default text in there [should] match what is shown in the canvas."*
  Right, and the panel was wrong twice over. It read values from the RAW source
  tree, so it missed both the overrides a nested instance already carries inside its
  parent source — a tab bar setting its three tabs to "one", "two", "three" — and
  any active STATE. The field said one thing while the canvas said another, which
  for a fidelity tool is the wrong way round.
  Rows now display the RESOLVED node. That fixes the flat case too, which had the
  same state-related mismatch and nobody had noticed.
  `hasOverride` still comes from the STORED entry, on purpose: "what does this show"
  and "has this been changed HERE" are genuinely different questions, and answering
  both from the resolved value would have made the reset button appear whenever a
  parent source had customised something — offering to reset a change the designer
  never made at this level.
  Resolution runs ONCE per body evaluation, keyed by distinct PATH so each nested
  component resolves once rather than once per leaf. Doing it inside `overrideRow`
  would have been the obvious shape and the wrong one: a computed resolve inside a
  `ForEach` is exactly what caused the ~6.2s inspector hangs in PERF rounds 8 and
  10. The comment says so at the point where someone would be tempted to move it.
  NEEDS OWNER BUILD.
  NEXT: J-d — export and handoff.

- **2026-07-24 — FEAT-017 chunk J-c: nested layers appear in the Overrides panel [inspector]:**
  Owner reported an "Overrides" header with nothing under it. Checked before
  assuming a regression, and it was not one: `overridableChildren` recursed into
  groups but stopped dead at `.instance`, so a component whose children are all
  components — a tab bar made of tab components — had no overridable leaves to show.
  Nothing was broken. There was simply no ADDRESS for a layer one level down, which
  is the whole reason FEAT-017 exists; J-a and J-b built the address and the
  resolution, and this chunk is where it becomes reachable.
  `overridableTargets` replaces the old helper, returning
  `(instancePath, node, componentName)` and descending into nested components as
  well as groups. Rows group under the nested LAYER's name rather than the source's:
  three tabs from one component are told apart by "one", "two", "three", not by the
  component they all share, and grouping by source would have produced one
  indistinguishable pile. Order follows first appearance so the blocks match the
  component's own layer order instead of an alphabetical shuffle.
  The flat case keeps its existing bindings entirely untouched — only a nested
  target routes through `nestedOverrides` — so nothing that already worked changes
  shape, and the diff stays reviewable. Reset remains the absence of an entry, which
  J-b's precedence rule already makes fall back to the nearest source value.
  Also fixed the smaller thing the owner actually complained about: when there is
  genuinely nothing to override, the section now says so rather than rendering a
  heading over empty space. A header with nothing under it reads as a bug even when
  the answer is "there is nothing here," and that is worth one line of copy.
  NEEDS OWNER BUILD. This is the one to try on the real file: place the tab bar
  twice, give each placement different tab labels, confirm the source is untouched
  and the two placements stay independent.
  NEXT: J-d — export and handoff, so those overrides reach the HTML and `publicProps`
  advertises which nested fields are real props.

- **2026-07-24 — FEAT-017 chunk J-b: nested overrides resolve [model]:**
  The load-bearing chunk, and it turned out small — which is the point of having
  put the type in first. `pushingNestedOverrides(_:into:)` hands each nested
  instance the overrides addressed to it, inside `resolvedLayout` and BEFORE the
  reflow. That ordering is the whole trap: a re-hug has to measure the OVERRIDDEN
  content, not the source's original, which is precisely what BUG-007 got wrong in
  the sizing path.
  It works one level only, on purpose. A path `[a]` becomes an ordinary override on
  `a`; `[a, b]` becomes a nested override on `a` with the head stripped, and `a`
  then resolves through the same function — so arbitrary depth falls out of
  recursion that already existed rather than needing its own walk. Overrides are
  appended LAST, so the outer placement beats whatever the source baked in, which is
  what "override" has to mean AND makes reset free: drop the entry and the nearest
  source value returns. There is no separate reset mechanism to keep in sync.
  Groups are descended but never named, same rule as relationship endpoints, so
  rearranging a layout group cannot break an override. An empty path matches nothing
  by construction, because no node id equals nil — J-a's `isAddressable` contract
  holding structurally rather than through a filter someone could later delete.
  CHECKED RATHER THAN ASSUMED: the instance cache needs no change.
  `instanceResolveCache` keys on top-level instance node ids, which are unique, and
  nested instances already fall through to a fresh resolve — the existing comment
  says why. Nested overrides live on the top-level instance, so the key is already
  right, and override edits happen outside a drag where the normal
  `resolveGeneration` clear runs. Worth recording that this was verified, since
  "add a cache key" would have been a plausible and entirely unnecessary change.
  Three checks added, all on the shape the owner actually wanted and could not
  build: a nested override reaching a layer two components down, the OTHER placement
  staying untouched, reset falling back to the source, and two layers of grouping
  not blocking the push-down.
  NEEDS OWNER BUILD. Nested overrides now affect drawing and export, but nothing
  authors one yet — J-c adds the UI, so until then the feature is reachable only
  from the checks.
  NEXT: chunk J-c — the inspector, mirroring the participants pattern from
  FEAT-012's I-c that worked well: a block per nested child, reached from an
  ancestor rather than by selecting something unselectable.

- **2026-07-24 — FEAT-017 chunk J-a: nested override storage [model]:**
  `NestedInstanceOverride` is `instancePath` + `targetNodeID` + an
  `InstanceOverride.Value` reused UNCHANGED, stored as
  `ComponentInstance.nestedOverrides` on the outermost placed instance. Reusing the
  existing value vocabulary matters more than it sounds: text, fill, textStyle,
  opacity, stroke, and componentState all keep working with every consumer that
  already understands them, so J-b has to teach the model where to look and nothing
  else. Tolerant decode, so pre-v2.1 files open unaffected. Storage only — nothing
  resolves it yet, which is the same property that made FEAT-012's I-a safe to land
  ahead of a build.
  `isAddressable` exists so the empty-path case is an explicit question rather than
  a silent filter: an empty path would address the instance's own children, which
  plain `overrides` already covers, and J-b must not quietly guess at it.
  CORRECTED a claim the design made yesterday, by checking instead of assuming. The
  plan said duplication AND flatten must remap these paths. Duplication does NOT:
  `instancePath` names nested instance nodes living inside the SOURCE, and cloning a
  placed node never renames source-internal ids — which is exactly why
  `nestedStateOverrides` has always survived cloning untouched. Flatten DOES, since
  dissolving a source re-identifies the resolved children a path runs through, so
  the repair went into `repairingStatePaths` beside the state repair already there,
  `targetNodeID` included. The backlog now says this precisely, because a wrong
  hazard note is worse than no note — it sends the next person to patch code that
  was already correct.
  Three checks added: JSON round-trip, a legacy instance with no key decoding to
  empty, and the empty-path rule.
  NEEDS OWNER BUILD. Run `scripts/verify_anchored_relationships.sh`; it now covers
  FEAT-012, the FEAT-016 advisory table, and J-a.
  NEXT: chunk J-b — resolution. The load-bearing one: every draw, hit-test,
  thumbnail, SVG, semantic HTML, Handoff, and Quick Look path already funnels
  through `resolvedChildren`, so getting it right there makes the rest follow.

- **2026-07-24 — FEAT-016 advisory checks written; FEAT-017 nested overrides designed [export/docs]:**
  FEAT-016 closes the gap the owner's own export exposed: every requirement passed,
  yet the tabpanel was named by a layer inside ITSELF and three tabs shared one
  panel, and the package said nothing about either. `SemanticHTMLFidelityIssue`
  gains an `.advisory` category, kept deliberately separate from
  `.semanticRequirement` — a reader must be able to tell "a rule was broken" from
  "this is legal but probably not what you meant," and flattening the two makes a
  report either alarmist or ignorable. The Handoff README names all three.
  `AriaRole.expectedRelationshipTargetRoles(for:)` holds the pairings and holds only
  pairings with a citation in the doc comment — two today, both quoted from the
  WAI-APG Tabs pattern. Everything else returns empty ON PURPOSE, because an
  advisory that fires on correct work is worse than no advisory at all, and the new
  `checkAdvisoryTableIsNarrow` asserts emptiness for `describedby`, `tablist`, and
  `button` so nobody quietly adds a pairing that merely feels right. The
  shared-panel advisory says plainly that nothing is invalid, since no prohibition
  was found — the entry records that as NOT VERIFIED rather than implying it.
  Then designed FEAT-017, the last big Chunk I model item and the one the owner has
  hit again and again: they cannot vary a nested component's content per placement,
  which is what pushed them toward forking components instead of reusing one.
  Root cause is the same shape FEAT-012 already solved — `InstanceOverride`
  addresses a BARE node id, so a nested instance's children are unreachable. The
  design follows a precedent ALREADY in the model rather than inventing one:
  `NestedInstanceStateOverride` is path-addressed and stored on the outermost placed
  instance, and nested overrides are that idea applied to values, reusing
  `InstanceOverride.Value` unchanged so no new vocabulary appears.
  One thing settled explicitly to stop it being re-litigated: `publicProps` is NOT a
  permission gate. Its own doc says false keeps an override local and true
  ADVERTISES it in the public contract, so every field stays overridable at any
  depth and publicProps keeps deciding only what handoff advertises.
  Also carried forward from FEAT-012's scars: duplication and flatten MUST remap
  nested override paths through the id map, exactly as BUG-010 required for
  relationships. That is written into J-a's notes and J-e's checks because it is
  precisely the kind of thing that gets forgotten twice.
  NEEDS OWNER BUILD for FEAT-016. FEAT-017 is design only; nothing built.
  NEXT: FEAT-017 chunk J-a.

- **2026-07-24 — FEAT-012 complete through I-e; headless checks green [verification]:**
  `verify_anchored_relationships.sh` prints "all checks passed". All six invariants
  hold: groups transparent to paths, duplicate independence (the BUG-010 regression
  guard), delete precision, ungroup hoisting, depth-2 DOM id uniqueness with
  depth-1 output unchanged, and migration lossless AND idempotent. Because the
  script compiles Paint + Document + AutoLayoutEngine + SemanticHTMLContract
  headlessly, this also confirms the model layer builds — the cheapest signal
  available on this side of the split, where there is no Swift toolchain.
  All five chunks I-a…I-e are written. What anchored relationships were FOR is now
  demonstrated on the owner's own file: a tab nested inside a placed component
  controlling a sibling component, exported with correct, non-colliding,
  chain-composed ids.
  STILL NEEDS AN APP BUILD to confirm in practice: BUG-012 (orphaned relationships
  now reported instead of vanishing), BUG-013 (selecting the group that holds both
  ends now yields an anchor), and the ungroup/delete repair.

- **2026-07-24 — FEAT-012 chunk I-e: anchors survive ungroup and delete, with checks [model/canvas/scripts]:**
  The repair half was the urgent part and the reason this chunk jumped the queue.
  `ungroup()` replaced a group node with its children and took its
  `anchoredRelationships` with it — authored semantics destroyed by an ordinary
  edit, silently. Same failure mode as BUG-012, a different door, and ungrouping is
  not an exotic action.
  Entries now HOIST to whatever still contains both ends: the enclosing group if
  there is one, otherwise the scope root through a new
  `commitNodes(appendingRootAnchors:)` so the whole edit stays ONE undo step rather
  than splitting into two. No endpoint needs rewriting, because a path names
  component instances only and never groups — which also means GROUPING needs no
  repair whatsoever. That is a real dividend of the path design rather than luck,
  so it now has a check guarding it.
  Explicit DELETE drops relationships naming the removed subtree at either end,
  collected across the whole subtree so deleting a group clears links to layers
  inside it too. Keyed to a specific id set on purpose, NOT "prune anything that
  does not currently resolve" — a tree can be briefly unresolvable mid-edit and a
  general sweep would quietly eat real work, which is the exact thing this line of
  work exists to prevent. Dropping on an explicit delete is not that: the designer
  removed the layer, and one undo restores the layer and its links together.
  Added `scripts/AnchoredRelationshipCheck.swift` and
  `verify_anchored_relationships.sh`, following the existing headless-check pattern.
  Six cases, each tied to something that actually went wrong or would be
  catastrophic if it regressed: groups transparent to paths, duplicate independence
  (BUG-010), delete precision, ungroup hoisting, depth-2 id uniqueness WITH depth-1
  output unchanged, and migration being both lossless and idempotent.
  KNOWN GAPS, recorded rather than papered over: dragging a node OUT of its anchor's
  subtree still strands the link — it now reports as orphaned instead of vanishing,
  which is the half that matters — and an orphaned entry is still invisible in the
  UI, findable only by reading the file.
  NEEDS OWNER BUILD + RUN, along with BUG-012 and BUG-013. Run
  `scripts/verify_anchored_relationships.sh` first; it should print all checks
  passed before the app is worth launching.

- **2026-07-24 — Cross-component relationships confirmed working in a real export [export/verification]:**
  Owner's second test (`tab-test3.exph`) wraps the tab bar and the panel in ONE
  component, and the exported `second-page` HTML settles several open questions at
  once. All three tabs carry `aria-controls` resolving EXACTLY to the panel's id,
  so anchored storage, participant authoring, and I-d's export path work end to end
  on real data — cross-component links are no longer theoretical.
  Better: the ids are `exp-<wrapper>-<tabrow>-<tab>` — THREE chain segments. That
  is chunk I-d's collision fix proving itself on a real file. Before it, a tab
  nested two levels deep minted a single-instance id, and two placements of the
  wrapper would have produced duplicate DOM ids for their tabs.
  The owner's remaining confusions both have answers rather than bugs behind them:
  - "In a group it did not work, in a component it did." That is BUG-013, already
    fixed but AFTER this build — `relationshipAnchor` asked for the selection's
    ENCLOSING group, so selecting the group that held both ends looked for that
    group's parent and found nothing. Worth re-testing after a rebuild.
  - "Only one panel to choose from." Correct, and structural: the three "panels"
    are three hidden text layers inside ONE tabpanel component, revealed by
    component states. There is genuinely only one roled panel to point at.
  - 282 `aria-hidden` attributes are all `<svg class="exp-path-svg" aria-hidden="true"
    focusable="false">` on decorative path art (the logo). That is CORRECT practice,
    not a defect — decorative SVG should be hidden from assistive technology and
    removed from the tab sequence. Recorded so it is not "fixed" later by mistake.
  Logged FEAT-016 from what the export did NOT say. Every requirement passed, yet
  the panel is labelled by a text layer inside ITSELF rather than by a tab, and all
  three tabs control the same panel — both things a reviewer would flag and neither
  mentioned anywhere in the package, because EXP asks only whether a relationship
  RESOLVES, never whether it points at the right KIND of thing. Under the fidelity
  principle that matters more than it looks: this package goes to a developer or a
  model that writes component code from it, so a link pointing at a
  plausible-but-wrong element yields plausible-but-wrong code with no warning. The
  entry cites the APG for the tabpanel case and explicitly marks the shared-panel
  case as NOT verified against any prohibition, so nobody upgrades advice into an
  error without evidence.

- **2026-07-24 — Read a real export; found silent relationship loss and a dead-end anchor [export/inspector]:**
  Owner exported a tabs file and reported the roles present but the relationships
  missing, assuming cross-component links still were not possible. Reading the
  actual `.exph` package told a different and more useful story.
  What WORKS, confirmed end to end: the `tab-content` source's component-root
  relationship (subject naming the source itself) resolved and emitted correctly as
  `aria-labelledby` on the `<section role="tabpanel">`, with a chain-composed id.
  So anchored storage, source-anchor resolution, and I-d's export path are all
  functioning on real data.
  What was BROKEN: the `tabs` source held three authored relationships whose
  subject was node `658A38F8…`, which exists nowhere — not in the document, not in
  the export. They produced no attribute, no fidelity issue, and no trace. The
  exporter validated only the TARGET against `availableDOMIDs`; a subject that
  resolved to a DOM id nothing would ever emit simply went unclaimed. Filed and
  fixed as BUG-012, raising an `orphanedRelationship` issue instead. P1 despite
  being narrow, because silent loss is the one failure mode a FIDELITY tool cannot
  have — under today's principle, anything that cannot be represented must be
  reported, never quietly discarded.
  Also fixed, BUG-013: `relationshipAnchor` asked for the selection's ENCLOSING
  group, so selecting the very group holding the tab bar and the panel looked for
  that group's parent, found none, and produced no anchor — a dead end with nothing
  on screen to explain it. A selected group is now the anchor itself; groups carry
  no role, are never participants, and selecting a container is exactly the request
  to work inside it. This also corrects an earlier claim in the backlog that
  selecting the enclosing group showed every participant — true only when that
  group happened to be nested inside another one.
  DIAGNOSIS, not a code bug: the reason the panel was never in the picker is that
  the owner was authoring inside the TABS COMPONENT EDITOR, where the anchor is the
  source and the panel is out of scope by construction. A tab's link to its panel
  crosses the component boundary, so it can only be authored from OUTSIDE — select
  the tab row on the canvas, where each nested tab appears as its own participant.
  That is the second time this has bitten; it is a discoverability problem, now
  recorded against the panel-IA work rather than treated as a one-off.
  Noted, not changed: the tabpanel is currently labelled by a layer INSIDE itself
  rather than by its tab. Valid markup, but the APG pairs a panel with its tab.
  The owner's call, not the tool's, so it stays advisory.
  NEEDS OWNER BUILD + RUN.

- **2026-07-24 — FEAT-012 chunk I-d: export reads anchors, and DOM ids carry the whole instance chain [export]:**
  Under the fidelity principle recorded earlier today this is the point of the whole
  chunk plan, not its last step — the exported artifact is the product.
  `nodeDOMID(_:chain:)` now composes an id from the entire instance chain, outermost
  first, instead of a single instance id that COLLIDED at nesting depth 2: two
  placements of the same component inside a third minted identical ids for their
  children. Depth-1 output is unchanged, so existing exports keep their ids and only
  the previously-broken cases move. `render`, `collectDOMIDs`, and BOTH CSS emitters
  carry the chain now. The CSS half is easy to overlook and matters as much: a
  selector minted from a single instance id stops matching its element at depth 2,
  which would have been a silent styling bug rather than a loud one. That closes the
  roadmap's "replace ambiguous raw descendant ids with stable instance paths" box.
  Relationships are now read from ANCHORS. `anchoredAttributes(...)` resolves one
  anchor's entries into attributes keyed by the DOM id of the element that must
  CARRY each one — relationships are stored on the anchor but belong on the subject,
  so that translation is the whole job — and `render` hands the map down for
  descendants to look themselves up in. Anchors encountered on the way: the document
  root, any group holding entries, and every component source (whose entries include
  the component's OWN links, where the subject names the source and stands for the
  element hosting this instance). Both ends resolve against the current instance's
  copies, so two placements can never cross-link.
  Deliberately reading ONLY the anchored form: emitting both would let a stale
  legacy entry resurrect an attribute the designer had deleted. Nothing is lost,
  since migration writes an anchored twin at decode — and the now-dead legacy
  `relationshipAttributes` was deleted rather than left sitting there, so there is
  exactly one read path instead of two that can disagree.
  The BUG-008 conformance rule moved to the point of EMISSION, which is the only
  place the host's role is known: `aria-labelledby` on a roleless element is dropped
  with a `prohibitedRelationship` issue, while `aria-controls` and `aria-describedby`
  are emitted, because they are global and valid there. The comment says not to
  collapse those into one rule.
  NEEDS OWNER BUILD + RUN. This is the first build where the tabs work should reach
  the HTML: export the artboard and check each tab carries `aria-controls` pointing
  at its panel, each panel carries `aria-labelledby` pointing at its tab, and a
  duplicated group's two copies use distinct, non-colliding ids.
  NEXT: chunk I-e — headless checks for depth-2 ids, duplicate independence, anchor
  repair on regroup/ungroup/delete (deferred out of I-b), and unresolved-endpoint
  reporting.

- **2026-07-24 — Guiding principle recorded: EXP is a fidelity tool, not a prototyping tool [docs/direction]:**
  Owner, unprompted and worth quoting: *"i never set out to make EXP a prototyping
  tool... i don't think design tools should focus on prototyping since it's done
  much more efficiently in code."* EXP is ONE PIECE of a designer's toolkit — read a
  component in without losing data, let the designer tweak it, export at the same
  fidelity, hand it to a developer or to a model that writes accessible component
  code from it. Added to CLAUDE.md as the second guiding principle and stated in
  full under ROADMAP → Architecture decisions, because it settles a whole class of
  future arguments rather than one decision.
  The test it gives: does this make the exported ARTIFACT more faithful, or does it
  just make the canvas more impressive? Build the first. It rules in semantic
  export, the Handoff Package, notes, roles and relationships, importer fidelity
  reports, and component states AS DESCRIBED VARIANTS. It rules out interaction
  wiring, state machines, transitions, and click-through playback.
  It also decides structure questions, which is where it earns its keep: when two
  models of the same design exist, prefer the one that ROUND-TRIPS STATICALLY over
  the one that only makes sense while EXP is running it. That independently
  confirms the tabs conclusion reached from the APG an hour earlier — three
  tabpanels with visibility toggling, not one panel whose identity changes with an
  active state — which is a good sign the principle is real rather than a slogan.
  Consequences taken immediately: FEAT-013 re-scoped (per-state relationships are
  HANDOFF DATA about variants, which is in scope; they are not a playback engine,
  which is not) and BUG-011 filed at P3 explicitly BECAUSE it is a verification
  convenience that does not touch the exported artifact. Component states being
  handoff data and never a playback engine is flagged as the distinction most
  likely to erode.
  Owner also called the tabs file what it is: a test case, not a goal — "the most
  important part is to accurately be able to read in a tab component, and not lose
  any important data, to be able to export it out with the same fidelity."
  So the acceptance bar for the whole FEAT-012 line moves from "can you author it"
  to "does it survive the round trip."
  NEXT: chunk I-d — export. Under this principle it is no longer the last step of
  the chunk plan, it is the point of it.

- **2026-07-24 — FEAT-012 chunk I-c: relationships are authored against the anchor, not the selection [inspector/model]:**
  The inspector used to author "the selected node's relationships." It now authors
  the ANCHOR's, and shows a block per PARTICIPANT — anything roled the selection can
  reach: the selection itself, the component root in source scope, and every roled
  component nested inside the selection. That last part is the whole point of the
  chunk: it makes ONE TAB inside a placed Tab Bar authorable even though it cannot
  be selected on the canvas or in Layers, which is exactly what was blocking the
  owner's tabs file.
  `relationshipEndpoints` builds the pickable ends. Groups stay transparent — a path
  never names one, so a link survives regrouping — and component instances
  contribute themselves plus ONLY their roled descendants. That restriction is
  deliberate rather than a shortcut: an unroled layer inside a component is that
  component's private business, and linking to one from outside couples two
  components at a level that breaks the moment either is edited, whereas a
  component's roled parts are its public semantic surface and the only thing ARIA
  has any use for from out here. It also keeps the list short, which the
  neighborhood rule exists to protect. A target that no longer resolves stays
  SELECTABLE as "Missing layer" rather than quietly reverting to None, so a broken
  link can be seen and fixed instead of disappearing.
  `Document.hasRelationshipParticipant(in:)` now backs the Object-menu item, the
  canvas context menu, and the inspector. All three had been carrying their own
  copy of "can this thing carry a relationship," which is precisely the arrangement
  that lets a menu item and a panel disagree; there is one answer now.
  Caught while writing: `let kinds = kinds(for:authored:)` inside `allParticipants`
  would have shadowed the method with a local array, and the compiler would have
  tried to call the array as a function. Renamed, with the reason in a comment so
  it does not come back.
  NOT YET, and worth knowing before testing: export still reads the legacy
  `Node.relationships`, so links authored this way persist and round-trip but do
  NOT appear in exported HTML until chunk I-d. Verify I-c on authoring and
  persistence — including placing the same group twice and confirming the two
  copies do not share targets.
  NEEDS OWNER BUILD + RUN.
  NEXT: chunk I-d — resolve endpoint paths to emitted DOM ids and switch the
  exporter's read path over, which also closes the roadmap's stable-instance-paths
  box since `nodeDOMID` still carries a single instance id.

- **2026-07-24 — Layers: nested expansion hoisted out of private state; inner layers open their component [chrome/layers]:**
  Two owner reports, and the first one had a cause worth writing down. Expanding a
  component "sometimes" left a stale row height — a scrollbar that corrected itself
  once you scrolled. `InstanceLayerRow` kept its disclosure in a private
  `@State var expanded`, and every layer inside a component lives in ONE `List`
  row, so a nested row expanding changed the outer row's height without `List`
  ever being told to re-measure its cached value. The private state also explains
  the "sometimes": expansion reset whenever SwiftUI recycled a row. Hoisted it to
  `LayersPanel.expandedNested`, keyed by a per-PLACEMENT path rather than a node id
  — the same source child appears under every placement of its component, so an
  id-keyed set would have expanded them all together. The key is a NEW
  `rowKeyPath`, deliberately not the existing `instancePath`: that one addresses
  nested component instances for state overrides, and overloading it would have
  quietly changed which layer a state selection applied to. Logged as BUG-009 with
  the remaining fix written down (explicit row heights, or flattening so every
  visible layer is its own List row) plus a warning not to reach for it first,
  since this panel is where PERF rounds 8 and 10 found ~6.2s hangs from per-row
  computed properties.
  Second: a layer name inside a component did nothing on click while the eye and
  the state picker beside it both worked, so the row read as half-broken rather
  than as read-only. Those layers genuinely cannot be selected there — they belong
  to the source, not the document, and exist once per placement — so the honest
  affordance is to go where they CAN be edited. Owner's call, and the right one:
  double-click opens that component. A nested component row opens itself, since
  that row's identity is the nested component and its badge and context menu
  already say so; any other layer opens the component it lives in. Wired three ways
  rather than one, per the command-coverage rule: double-click, a context-menu item
  naming the component (both appear on a nested row — edit the nested thing, or the
  thing it sits in), and a VoiceOver `accessibilityAction`, because a double-click
  is pointer-only and would otherwise leave the row announcing something it could
  not do. The tooltip now says what double-click will open.
  NEEDS OWNER BUILD + RUN.

- **2026-07-24 — FEAT-012 chunk I-b: anchored storage + a non-destructive migration [model]:**
  `AnchoredRelationship` is kind + subject endpoint + target endpoint, stored on
  the ANCHOR rather than the subject. Three anchor stores, because three things can
  contain both ends: a group `Node`, a `ComponentSource`, and the `Document` root.
  Authoring will never produce the document-root case — the neighborhood rule
  requires a group — but MIGRATION can, so the case exists instead of quietly
  dropping a legacy link. A subject is allowed to name the anchor ITSELF, which is
  how a component's own relationships fall out with no special case in the data:
  the element carrying the role is the one hosting the instance, so it IS the
  anchor, and only `endpointNamesAnchor(_:anchorID:)` has to know that.
  The migration runs at decode and is deliberately ADDITIVE — `Node.relationships`
  and `a11y.rootRelationships` are left intact and still encoded. That matters more
  than it looks: four passes are now written and none has been compiled, so a wrong
  migration that CLEARED the legacy arrays would destroy a document the first time
  it was saved. As written, the old data is still there to recover from, and since
  nothing reads the anchored form until chunk I-d, a mistake cannot change what the
  app draws or exports either. It is idempotent, with dedupe on
  (kind, subject, target) rather than on `id` — `id` is freshly minted each run and
  would have defeated the check, which is the kind of bug that only shows up as
  slow duplication across many open/save cycles.
  `nearestCommonAncestorGroup` considers GROUPS only. Component instances are
  opaque here on purpose: a legacy relationship could only ever address a sibling,
  so it never crossed an instance boundary, and treating instances as containers
  would invent nesting the stored data does not have.
  Caught while writing: the first version passed `sources[i].children` as both a
  read argument and an `inout` argument in the same call — overlapping access Swift
  would have rejected. The helpers are now static and work on local copies written
  back at the end.
  DEFERRED within I-b, on purpose: anchor REPAIR on move, regroup, ungroup, and
  delete. Nothing reads anchors until I-d, so a stale anchor cannot affect anything
  yet, and repair is far easier to write against the authoring UI I-c adds than
  against nothing.
  NEEDS OWNER BUILD + RUN. Four passes are now stacked unbuilt (BUG-008/FEAT-011,
  document-scope authoring, I-a, I-b). Worth building before I-c, since I-c is the
  first chunk that changes what the designer can actually do.
  NEXT: chunk I-c — authoring UI that can select a subject nested inside a placed
  component, which is what finally makes the tabs pattern testable.

- **2026-07-24 — FEAT-012 chunk I-a: relationship endpoints become paths [model]:**
  First chunk of the anchored-relationship plan, written to be INVISIBLE at
  runtime so it can be verified before anything moves. `RelationshipEndpoint` is
  an `instanceChain` (outermost first) plus a non-optional `nodeID`, rather than a
  bare `[UUID]` path — an endpoint cannot then be malformed, and no accessor has to
  invent a value for the empty case. `NodeRelationship` stores one; `targetID`
  survives as a get/set accessor, so every existing call site in MainWindow, the
  exporter, and the flatten path compiles and behaves exactly as before. Writing
  through `targetID` resets the chain, which is deliberate — a raw id cannot
  express one — and the comment says so rather than leaving it to be discovered.
  Decode takes either form; encode writes BOTH, so a v2.1 file still opens in a
  v2.0 build and degrades to sibling behavior instead of failing to decode the
  whole document. `Document.resolveEndpoint(_:in:)` walks a path, stepping into
  component instances through `resolvedChildren` (the same tree the canvas draws)
  and treating plain GROUPS as transparent — a path never names a group, so a link
  survives someone regrouping — capped at the same depth the dependency walker
  uses so a damaged or legacy document terminates rather than recursing.
  NEEDS OWNER BUILD + RUN, along with the two earlier passes. Nothing is compiled
  on this side. Because I-a is runtime-invisible, the useful check is simply that
  existing relationships still behave as before and old files open unchanged.
  NEXT: chunk I-b — anchored storage plus migration of existing node-stored
  relationships onto their common ancestor.

- **2026-07-24 — Anchored relationships designed; the obvious fix was the wrong one [model/a11y/docs]:**
  Owner reported the tab and panel still not seeing each other and asked to expand
  the neighborhood "just a bit." Checked before building, and the request was the
  wrong fix — recorded that way so nobody re-derives it. Their structure is a Tab
  Bar component (role `tablist`) whose children are Tab components (role `tab`),
  sitting in an artboard group beside a Tab Panel component. Verified against the
  WAI-APG Tabs pattern: that nesting is CORRECT ("each element that serves as a tab
  has role `tab` and is contained within the element with role `tablist`"), and the
  link ARIA wants is individual tab to individual panel, never tablist to panel.
  So the targets were not hidden by a narrow picker. Relationships are stored ON
  THE SUBJECT NODE, the subject here lives inside the Tab Bar SOURCE, and anything
  in a source applies to every placement of it — so all placements would point at
  one panel. The link must vary per PLACEMENT and therefore cannot live there.
  Widening the picker would only have let them author a link that cannot export.
  Also checked and rejected FIRST: roles on plain groups. `Node` has no `a11y` at
  all, so only component instances can carry a role, which is an EXP artifact
  rather than an ARIA one — but it would NOT have helped this case, because their
  roles were already on components and correctly placed. Logged as FEAT-014 on its
  own merits instead of shipped as a fix for something it does not fix.
  Owner delegated the mechanism ("just find the most stable and scaleable method"),
  so: **a relationship lives at the nearest node that contains BOTH of its ends,
  and addresses each end by instance path rather than raw id.** The anchor for
  their file is the artboard group; the tab end is `[TabBarInstance, TabOne]`.
  Place the group twice and each copy resolves to its own ids — no cross-placement
  leak, no duplicate DOM ids. It also collapses the neighborhood rule into the same
  concept rather than keeping it as a separate constraint: the neighborhood IS the
  anchor's subtree. And it is not new surface area — it is the stable-instance-path
  work Chunk I already owed, reached from the front door, so the Phase 4.1 box now
  points at FEAT-012's five chunks (I-a path type, I-b anchored storage +
  migration, I-c authoring UI, I-d export, I-e checks). I-d is the one that closes
  the box, since `nodeDOMID` carries a single instance id today and collides at
  depth 2+.
  Owner also confirmed their panel's two hidden text areas are component STATES,
  not three panels. That is coherent, and it means the panel's `aria-labelledby`
  has to name whichever tab is active — a relationship that belongs in the state
  diff. Logged as FEAT-013, WITH its open question left open on purpose: whether
  several tabs sharing one `tabpanel` conforms at all is NOT resolved. The APG
  describes a 1:1 pairing and does not address the shared case, and that answer
  decides whether FEAT-013 is the right fix or whether the tool should be advising
  a different structure. Deliberately not assumed either way.
  Nothing was built this pass — design record only, by agreement.
  NEXT: FEAT-012 chunk I-a (the path type), which is designed to be invisible at
  runtime so it can be verified safely before anything moves.

- **2026-07-24 — Relationships work on the canvas, scoped to a group [inspector/model]:**
  Owner read the first BUG-008 pass and caught what it could not do: a tab and the
  panel it opens are two PLACED instances, and relationship authoring only rendered
  inside a component source — so there was literally nothing to test. The component
  root can only ever point at layers inside its own source (targets resolve
  per-instance; that is structural, not a limitation to lift), so this needed the
  document-scope half.
  Relationships now render on the canvas for any layer with a role of its own, and
  the neighborhood rule is settled: targets come from the nearest enclosing GROUP,
  with NO fallback to the artboard. The owner chose the strict version and the
  reasoning is worth keeping — an artboard fallback quietly reintroduces the
  long-dropdown problem the rule exists to prevent, and makes the rule change
  depending on context, while "things you connect live in a group together" holds
  everywhere. It also describes how they already design: "I put them in groups
  already because I don't want to accidentally move the tab titles away from the
  tab content." A constraint that matches the existing habit is not a constraint.
  An ungrouped selection gets an instruction naming ⌘G rather than an empty picker,
  because a blank dropdown teaches nothing; anything already authored is kept,
  still exports, and the note says so instead of implying it was dropped. Targets
  walk into groups but NOT into component instances — a layer inside another
  component is not addressable from outside, since the id an outside reference
  would need is minted per instance at export, so offering it would author a link
  the exporter could not resolve. Each target is annotated with its role
  ("Panel One — Tab Panel") so picking the right one is not guesswork.
  `relationshipBinding` is now scope-agnostic through `mutateScopedNode`, so one
  control authors both cases and the undo step lands in the right tree. Menu
  validation was rewritten in BOTH `MainWindow` and `CanvasView` around a shared
  "does this LAYER have a role of its own" test, and stays enabled for an ungrouped
  selection on purpose — a greyed-out item explains nothing, the panel explains the
  rule. Export needs no change: `collectDOMIDs` already registers every top-level
  node, so a sibling target resolves at document scope.
  NEEDS OWNER BUILD + RUN, same as the first pass — nothing here is compiled.
  NEXT: build both passes together and run the BUG-008 acceptance list.

- **2026-07-24 — BUG-008 + FEAT-011: relationships now follow the layer's OWN role, in plain language [model/inspector/export/a11y]:**
  Verified first, per the standing rule — and the verification overturned a
  premise this entry had been carrying. The backlog assumed `aria-controls` was
  NOT global and planned to enforce a supported-roles list. It IS global (MDN:
  "The global `aria-controls` property…", Associated roles: "Used in ALL roles"),
  and so is `aria-describedby` ("Used in all roles. Usable in all HTML elements as
  well"), which carries no role prohibition at all. There is no list to enforce.
  That splits BUG-008 into two problems that had been treated as one, and the fix
  now keeps them apart on purpose. `aria-labelledby` on a roleless layer is a
  CONFORMANCE violation — `generic` is nameless and prohibits naming — so it is
  suppressed in the UI and dropped at export with a `prohibitedRelationship`
  fidelity issue. `aria-controls` and `aria-describedby` on a roleless layer are
  spec-VALID and merely pointless, because a generic element is exposed to
  accessibility APIs only "so that assistive technologies can gather certain
  properties such as layout and bounds" — there is no named thing for them to
  attach to. So those are a QUALITY default (not offered, never invented) and the
  UI copy is careful not to call them invalid, because that would be telling the
  designer something untrue. The `isProhibitedWithoutRole` doc comment says all of
  this at the point of use so the three kinds do not get "tidied" into one rule.
  The actual defect: `availableRelationshipKinds` read the enclosing SOURCE's role
  and offered its kinds on every layer inside it. ARIA roles do not inherit, so
  that had no basis in the spec — and it is why a decorative rectangle in a Tab
  Panel was offered Labelled By. Layers are now driven by
  `effectiveExportRole(of:)`: a component instance carries its source's role,
  every other layer has none and is offered nothing new. Already-authored kinds
  still render so a role change can never strand data that needs removing.
  Fixing that exposed the modeling gap the last session logged: the element that
  carries the role hosts the INSTANCE, so there was no conformant place to author
  a component's own relationships at all. Owner chose the component-root option
  over authoring on a placed instance, so `A11ySemantics.rootRelationships` lives
  on the SOURCE and is part of the component contract — every instance emits it,
  two uses cannot drift apart, and targets resolve per-instance at export so they
  can never cross-link to each other's layers. The Relationships section now reads
  "This component" (always, when the role offers kinds) and "This layer" (only
  when that layer has a role of its own), which also means the section stops
  looking identical on every layer the way the group Font control did.
  FEAT-011 rode along as sequenced: `friendlyLabel(for:)` / `friendlyHelp(for:)`
  make the plain-language phrase primary ("Named by its tab", "Opens this panel",
  "Helper or error text") with the literal `aria-*` name in the hover tip and the
  VoiceOver hint. Owner chose help-tip-only over always-visible secondary text,
  which also avoids making FEAT-010's cramped default panel width worse. `label`
  survives for undo action names and diagnostics only, and now says so.
  Also handled, because adding root relationships would otherwise have quietly
  broken it: `Document.flattened` carries root `controls`/`describedby` onto the
  group that replaces a deleted source's instance, retargeted through the existing
  id map, and drops root naming — invalid on a roleless group. Menu validation
  updated in BOTH `MainWindow` and `CanvasView` so the Object ▸ Relationships…
  item and the panel can never disagree about whether there is anything to edit.
  RECORDED AS NOT VERIFIED, so it is not mistaken for settled: WAI-ARIA 1.2 §6.5
  "Global States and Properties" was not read verbatim (the W3C fetch truncated),
  so the globality claims rest on MDN citing the spec; no screen-reader behavior
  was tested; and the FEAT-011 wording was checked against the WAI-APG only for
  tab/tabpanel and dialog naming — the generic phrasings are content-design
  judgment, not verified spec claims.
  NEEDS OWNER BUILD + RUN. Nothing here has been compiled; there is no Swift
  toolchain on this side. No headless check was added for the new cases yet.
  NEXT: build and run the BUG-008 acceptance list, then stable instance paths.

- **2026-07-24 — ARIA verification made a standing rule; relationship scope decided [docs]:**
  Three owner decisions captured so none of them has to be re-derived later.
  (1) **Verification is now a standing norm, not a one-off.** New
  WORKING-AGREEMENT section "Accessibility decisions are verified, not
  remembered," pointed at from CLAUDE.md's working norms and from a banner above
  the ARIA cluster in BACKLOG. It says the quiet part explicitly, in the owner's
  words: the rule holds *"even if I ask for the wrong thing by accident,"* so
  Claude must push back with a citation when a request contradicts the spec
  rather than implementing it. It also requires stating what was NOT verified,
  and naming standards precisely (WCAG 2.1 AA / WAI-ARIA 1.2 / ARIA in HTML —
  never "ADA compliant," since the ADA does not specify ARIA).
  (2) **Relationship targets are scoped to a neighborhood, not the document.**
  Owner's instinct, recorded as a design constraint on BUG-008: once a component
  can reference something outside itself, the picker must be limited to the
  enclosing artboard or group. A document with hundreds of components would
  otherwise produce novel-length dropdowns — unusable generally, and genuinely
  hostile by keyboard or screen reader. It also happens to match the DOM: these
  are id references resolved within a document, and the exporter ALREADY raises
  an `unresolvedRelationship` issue when a target falls outside the exported
  artboard, so artboard-scoping the picker just stops people authoring links the
  export would reject. The scope rule must land in the same change that opens
  targets up, since `relationshipTargets` is currently confined to the source's
  own children and the problem does not exist until then.
  (3) **FEAT-011 (plain-language relationship UI) ships WITH the component
  classification work**, not after it — recorded as part of that work's
  definition of done. Same views are already being rewritten to fix WHEN each
  kind is offered, so rewording WHAT it says costs almost nothing then, versus
  touching them twice and shipping an interim release where the offers are
  correct but still unreadable to most designers.

- **2026-07-24 — Group font control removed; ARIA relationship offers verified against the spec [inspector/a11y]:**
  Dropped the Type section from the single-group inspector. Its font menu label is
  a hardcoded "Font" (it has no single value to display for a mixed selection), so
  on one group it read as a control that never responded to anything. Changing a
  typeface is an edit you make on the text layers. Multi-shape selections keep it,
  where a fixed label is honest about mixed values.
  Then verified the relationship question against WAI-ARIA 1.2 / MDN rather than
  answering from memory, because the owner asked for exactness. Findings, all
  recorded in BUG-008: ARIA roles do NOT inherit — nothing cascades to descendants
  — so deriving a layer's relationship kinds from its CONTAINER's role has no
  basis in the spec. Worse, an unroled group or rectangle exports as a `<div>`
  whose implicit role is `generic`, and `generic` explicitly PROHIBITS
  `aria-labelledby` and `aria-label`; the attribute is invalid there, not merely
  noisy. None of EXP's curated roles are in the naming-prohibited list, so the
  problem is exclusively the no-role case. And `tabpanel` + `aria-labelledby` is
  correct and expected — the WAI-APG tabs pattern names the panel by its tab, and
  `SemanticHTMLContract` already requires it — so that offer stays.
  Verifying also surfaced the real modeling gap: the exporter puts
  `source.a11y.role` on the element hosting the INSTANCE, so every layer inside a
  source is an unroled div, while `relationshipControls` renders only in `.source`
  scope. The kinds are therefore offered exactly where they are invalid, and there
  is currently no conformant place to author a component's OWN relationships,
  because the element carrying the role is the instance and it is not selectable
  from inside the component. Logged rather than half-wired: this is a model
  decision, not a UI tweak. Also logged FEAT-011 to translate the relationship UI
  out of ARIA vocabulary — the owner's point that "labelled by" reads as
  form-field language, and that Described By is hard to hold onto even with a11y
  training, is a content-design problem worth solving properly with role-aware
  phrasing while keeping the emitted attributes identical.
  Standards-language note carried into the backlog: the ADA does not specify ARIA;
  the applicable standards are WCAG 2.1 AA (DOJ Title II rule, Section 508,
  EN 301 549) plus WAI-ARIA 1.2 and ARIA in HTML. Docs and UI copy should say
  those, not "ADA compliant."
  STILL TO VERIFY before implementing BUG-008: the supported-roles list for
  `aria-controls` (not a global property) and whether `aria-describedby` carries
  any role prohibition — only `aria-labelledby`'s list was confirmed.

- **2026-07-24 — Auto-padding groups no longer show duplicate Fill/Stroke sections [inspector]:**
  Owner spotted repeated sections on the component edit screen: an auto-padding
  group already carries its own background, corner, stroke, and stroke position
  in the Auto Padding section, then a separate Fill section and Stroke section
  appear underneath it. Reading the code, they were worse than redundant. The
  single-group branch calls `multiStyleControls()`, whose Fill/Stroke sections
  are gated on `nodeHasFill`/`nodeHasStroke` — which for a `.group` return
  `autoPadding != nil` — and whose bindings write `autoPadding.fill` /
  `.stroke` / `.strokeWidth`. But `mutateAllSelected` runs through
  `mutateStyleTargets`, which recurses, so that second "Fill" also repainted
  EVERY layer inside the group. One control, identical in appearance to the one
  above it, silently doing something much broader. Both paint sections are now
  suppressed for a single group that has auto padding
  (`multiStyleControls(includeFillAndStroke:)`). Type stays — it has no
  counterpart above and bulk-styling contained text is the point of it — and
  plain groups without auto padding keep both sections, since there is nothing to
  duplicate there and the recursive apply is the only way to paint their
  contents. Trade recorded: with auto padding ON you can no longer bulk-recolor
  children from the group row; select the children (or turn padding off) instead.
  If that proves annoying the alternative is to keep the sections but exclude the
  group itself from the targets and relabel them "…all layers inside".
  Also logged, not built: FEAT-009 per-corner radius for auto groups (the
  `CornerRadii` / `effectiveRadii` model and the inspector "Advanced" disclosure
  already exist for rectangles, so it is mirroring plus four draw/emit sites —
  the entry lists them) and FEAT-010 the inspector responsiveness + user
  type-size pass the owner asked to sequence as its own polish release.

- **2026-07-24 — BUG-007: auto layout now sizes component instances by what they
  actually resolve to [model/canvas]:** Owner repro — a `tab` component, two
  instances in a 2px auto-layout row — showed text spilling outside the instance
  bounds, gaps that did not measure 2px, and a text override running straight
  over its sibling. Cause: an instance had TWO sizes in the app and nothing
  reconciled them. `AutoLayoutEngine.reflow(_:)` only handles `.group` (recurse)
  and auto-sized `.text` (re-measure); `.instance` hits neither branch and is
  returned untouched, so the stack math used the instance's stored frame from
  whenever it was placed. The engine could not do better — it is a pure
  `[Node] -> [Node]` with no document, so it cannot look up a source. Meanwhile
  every draw, hit-test, and selection path sizes instances with
  `resolvedSize(of:)`, which re-hugs live. The instance therefore DREW at its
  resolved size and was LAID OUT at a stale one, and any override that changed
  the resolved size widened the drawing without moving its siblings.
  Fix keeps the engine pure and gives the ENTRY POINT document context:
  `Document.instanceSized(_:depth:)` walks the tree and assigns each instance its
  resolved bounds (innermost-first, since resolution recurses), and
  `Document.reflowed(_:)` hands the pre-sized tree to `AutoLayoutEngine`. Every
  call site in `Document`, `CanvasView`, `LayersPanel`, `MainWindow`,
  `DesignLanguagePanel`, and the semantic exporter moved onto the document-aware
  form; the pure entry point remains for the thumbnail extension and for the one
  no-document fallback in `updateNode`. `sourceUsesManagedBounds` deliberately
  stays on the pure engine — it asks a structural question whose answer cannot
  change with instance sizes, so resolving there would recurse on every layout
  for no difference in result. Resolution depth is capped at 24 so a damaged or
  legacy document that already contains a cycle terminates instead of recursing
  forever, matching the dependency walker's existing totality guarantee.
  Two component-state editing paths (`MainWindow.scopedNodes`,
  `CanvasView.displayedCurrentNodes`) were reflowing through
  `ComponentStateEditing.applied(reflow: true)`, which has no document and so hit
  the same defect while editing a state. Both now reflow through the document,
  and the `reflow:` parameter was REMOVED rather than left defaulted — a
  document-free reflow is always wrong for instances, so the wrong call should
  not be expressible.
  Headless check now covers the owner's exact shape: the pure engine is kept as
  the regression witness (it still lays out from stale frames), document-aware
  reflow sizes both instances to their resolved bounds and measures the 2px gap
  between them, a nested component's re-hugged width reaches its parent's layout,
  and layout over a cyclic document returns.
  NEEDS OWNER RUN: build + the two-tab repro, and a look at redraw performance on
  a large document — this runs on the draw path and should ride the existing
  `resolveGeneration` instance cache (see PERF-006 about the flat hit/miss
  counters). Also logged FEAT-008: font-picker scroll memory plus "Fonts used"
  and "Recent fonts" filters, penciled for v2.2, with the scroll-to-current half
  callable forward on its own.

- **2026-07-24 — Context-aware ARIA child roles from semantic containment [app]:**
  Chunk I's semantic-containment item. Added the seven roles the rule set
  required (Tree, Tree Item, Grid, Table Row, Table Cell, Column Header, Row
  Header) across every exhaustive switch plus `semanticHTMLMapping`; table parts
  stay on div hosts to match the existing div-based `table`/`grid`, because a
  native `<tr>`/`<td>` outside a native `<table>` is markup the browser silently
  reparents — promoting that whole family is its own change. Ownership rules live
  on `AriaRole` as `expectedChildRoles` and `requiredParentRoles`, with
  `containmentGuidance` producing the plain-language sentence. `Document` gained
  advice from both directions: the child's (given where it sits) and the
  container's (it expects List Items and none of its nested components are one) —
  the authoring-time form of the `listStructure`/`tableStructure` gaps the handoff
  fidelity report already raises, surfaced while it is still cheap to fix.
  The design is deliberately quiet so it never cries wolf: no expectation, a
  correct child, a legal-but-unrelated child, and an empty container all produce
  nothing at all, and the single warning case is a child whose role REQUIRES a
  container this parent is not. `radio` has no required parent on purpose.
  Fixed a blocker found on the way in: `setComponentCategoryAction` ignored the
  menu item's source and always wrote to `categoryTargetSourceID`, so inside a
  source editor you could not categorise a nested child at all — every attempt
  silently re-roled the outer source. Categories now travel on a
  `ComponentCategoryRequest` (source id + role), mirroring
  `ComponentPlacementRequest`, with the legacy token form still resolving for
  older menu builders. The canvas Set Category submenu now leads with the
  explanation and a "Recommended here" group, marks the warning case, keeps the
  complete role list beneath it (a recommendation shortens the path to the right
  answer, it never removes a choice), and carries each role's blurb as a tooltip.
  The source editor's category tip now also carries the container-side advice.
  Extended the headless check with the full containment matrix including the
  silence cases and a guard that recommendations never remove a role.
  NEEDS OWNER RUN: Xcode build + the graph check.
  NEXT: stable instance paths for overrides/DOM ids — the last model gate before
  XD/Figma import. Worth considering after that: now that rows and cells can be
  authored, `table`/`grid` could graduate to native `<table>` markup.

- **2026-07-24 — Dependent-source deletion: delete the source, keep the work [app]:**
  Closed the PARTIAL half of the Chunk I dependency-graph item. Deleting a
  component source previously stripped every instance of it from the canvas AND
  from inside other sources with no warning — silent data loss from a context
  menu, and the same code was duplicated verbatim in the Components grid card and
  the list row. Replaced both with one model API,
  `Document.deletingComponentSource(_:)`, which flattens rather than strips:
  each instance becomes an ordinary group of its `resolvedChildren` — the same
  resolution the canvas draws and Detach Component bakes — so the flatten is
  visually a no-op. The instance node KEEPS its id and every layer property, so
  visibility overrides, relationships, and Layers selection/expansion keep
  working; flattened children are re-identified per use so two uses of one source
  can never share node identity; and a parent instance's `nestedStateOverrides`
  path that ran through the dissolved instance re-roots onto the surviving nested
  instance rather than being orphaned (a selection FOR the dissolved instance is
  dropped, since a plain group has no states). Added `sourcesDepending(on:)` and
  `instanceCount(of:)` as the one place anything asks what a deletion would
  touch. Command coverage per the working agreement: the behavior lives in
  `deleteComponentSourceAction(_:)` on `CanvasNSView`; both Components-panel rows
  now route through it via `sendCanvasAction` exactly like component placement;
  the canvas context menu gained a Delete Component item; the Object menu gained
  a destructive item; and `validateMenuItem` names the source in the title
  (Delete Component "Card") so it can never be misread as deleting the selected
  layer. Deleting a source that is open in a source editor now closes that
  window instead of leaving it editing something the document no longer has.
  Extended `scripts/NestedComponentGraphCheck.swift` with the flatten matrix:
  dependents/counts before deletion, flatten on the canvas + inside a group +
  inside another source, identity and frame preservation, nested instances
  surviving as instances, document-wide id uniqueness, and state-path re-rooting.
  OWNER REPORT 2026-07-24: deleting from the Components panel still removed
  every instance. Only one deletion path exists in the source after this change,
  so this is either a stale build or the flatten resolving to empty groups —
  undetermined. The owner's call, recorded deliberately: this is NOT a blocker
  (the delete is undoable, Detach exists as a pre-emptive escape hatch, and no
  model work depends on it), so it is parked rather than chased. STILL NEEDS:
  Xcode build + the graph check, then a real-document pass.
  NEXT: stable instance paths for overrides/DOM ids, then the rest of the Chunk I
  closure matrix.

- **2026-07-24 — Nested-panel owner pass + continuity-doc synchronization [app/docs]:**
  Owner verified the revised default-width Layers and Components panels: source
  pills expose useful text, virtual component groups disclose past the first
  level, nested menu-item components remain state-addressable, and Components
  list hierarchy/usage density reads correctly. Marked the Chunk I slice owner-
  verified and synchronized live status/next-step language in `AGENTS.md`,
  `CLAUDE.md`, this roadmap, and `V2-INTEROP-PLAN.md`. Historical v1.5/v1.6
  release/schema references remain unchanged because they document shipped
  milestones rather than current status. NEXT: dependent-source deletion choices
  and the remaining Chunk I acceptance matrix, then XD/Figma import.

- **2026-07-24 — Screenshot-driven Layers recursion + Components list density [app]:**
  Followed the owner's default-width panel captures. Removed the repeated component
  glyph from source-name pills and tightened their inset so substantially more of
  the source name remains visible. Replaced native `DisclosureGroup` inside virtual
  instance rows with EXP's explicit chevron/expanded-stack pattern; groups and
  component instances now disclose recursively with predictable indentation rather
  than stopping at the first source layer. Reworked Components list rows around the
  correct hierarchy: prominent name first; dimensions/layer count, state, and ARIA
  category beneath as metadata; redundant identical component icons removed; usage
  remains actionable on the right, with the single-instance case reduced to one
  compact count button and paging arrows reserved for multiple instances. All
  controls retain help and VoiceOver labels. Full Debug app/thumbnail/helper build
  succeeds. OWNER PASS 2026-07-24: verified at the default panel widths. NEXT:
  the remaining Chunk I closure matrix.

- **2026-07-24 — Nested Layers identity/state pass + state outline parity [app]:**
  Separated placed-instance names from source component names: new placements use
  the neutral `Instance` default, Layers shows the instance name above an accent
  source tag, double-click renames only the instance, and source renaming is an
  intentional `Rename Component…` context action. Expanded component rows now
  recurse through groups and nested sources and provide a compact Default/named
  state menu at every component level. Choices made inside a placed parent are
  stored as stable nested-instance ID paths and resolve at arbitrary depth without
  changing the shared source. Extended state diffs to capture/apply/export complete
  outline appearance (color including alpha, width, alignment) and added group-
  background outline position to the Auto Padding inspector and canvas/raster/SVG
  renderers. Relationships now sit at the inspector bottom and are role-aware,
  while existing authored data remains reachable after a role change. Expanded
  `verify_nested_component_graph.sh` covers outline capture/application plus a
  two-level nested-state resolution and JSON round-trip. Full Debug app/thumbnail/
  helper build, semantic contract/package, SVG token bridge, and graph checks pass;
  the package golden changed only because `design.json` now writes the new default
  outline-position field. NEXT: dependent-source deletion and the remaining Chunk I
  acceptance matrix before XD import.

- **2026-07-24 — v2.1 opened; nested-component placement + cycle-safe graph [app]:**
  Corrected the release sequence: code/Storybook/HTML-CSS import remains v2.2;
  v2.1 starts with Chunk I so XD/Figma import can preserve composed components.
  Bumped the project to 2.1/build 12. Added one shared source-dependency graph
  (`parent → nested source`) that finds references inside groups, answers
  transitive dependencies with a visited set, and rejects both self-nesting and
  indirect cycles before mutation. Component placement now funnels through the
  active canvas from the Components panel, Object ▸ Component ▸ Place Instance,
  canvas context menus, and drag/drop; Layers drag-into-source uses the same
  guard. Nested component rows use the live source name/accent identity and offer
  Edit Component directly, including virtual rows under a placed instance.
  Added `scripts/verify_nested_component_graph.sh`: direct, grouped, transitive,
  move-into-source, and malformed-cycle checks pass. Full signed Debug app +
  EXPThumbnail + bundled helper build succeeds with existing warnings only.
  NEXT: finish the unchecked Chunk I deletion/instance-path/override/export
  contract before starting the XD importer pipeline.

- **2026-07-23 — Help draft 03 Text/Shapes/Paths clip set integrated [site]:**
  Reviewed twelve clean silent clips from the owner's third recording batch and
  integrated all of them locally: five Text guides, two basic Shape guides, and
  five Vector Path guides through Convert to Path. Added two searchable Help
  articles—Create and format text, and Draw and edit vector paths—and extended
  the existing Create and transform shapes article rather than publishing a
  redundant second shapes page. The owner's added Pen add/remove-points clip is
  now its own focused section; broader multi-point selection and corner/smooth
  conversion are deferred until they have dedicated footage. Generated 1920px
  H.264 web copies and poster images while preserving the full-resolution source
  edits outside the site. The library now contains twelve searchable tutorials
  and thirty-six visual guides; all related-article and media references validate,
  and the production Vite build passes. Six button/component clips remain queued
  for the next recording round. Work is local only; no deployment was performed.

- **2026-07-23 — Help draft 03 synchronized with v2.0.1 fixes and Type-panel order [site/app]:**
  Updated the text tutorial and recording directions to follow the polished
  inspector sequence: Font, optional Weight, Size, Color; text-box and paragraph
  controls; then a divider-separated semantic Content picker below Case. Reframed
  Content explicitly as HTML-handoff context independent of visual styling.
  Confirmed the pushed v2.0.1 source contains both fixes, closed BUG-005/BUG-006
  in the backlog and roadmap, and moved the Pen-curves and component-states clips
  from blocked to ready. All eighteen Help draft 03 clips can now be recorded.

- **2026-07-23 — v2.0.1 release path documented; repo hygiene fixed [infra]:**
  Added a complete `## v2.0.1 copy/paste path` to `docs/RELEASE-CHECKLIST.md`
  (steps 0–11, mirroring the hardened v2.0 path at 2.0.1 / build 11: gate, commit,
  archive, Direct Distribution, byte-verified zip, appcast + ROADMAP
  in-progress→released transform, tag/upload/deploy, public verification, and the
  v2.0→v2.0.1 Sparkle install proof). Investigated two stray files flagged in the
  release diff: (1) `EXP [design].xcodeproj/xcuserdata/.../xcschememanagement.plist`
  was tracked because the old `.gitignore` pattern `*.xcuserdata/` never matched the
  real `xcuserdata/` directory — fixed `.gitignore` to ignore `xcuserdata/` +
  `*.xcuserdatad/` and documented a one-time `git rm -r --cached` in checklist step
  0.5; (2) a `.fuse_hidden…` file is a Linux/FUSE artifact from editing
  project.pbxproj over the Dropbox mount (macOS does not create these), now
  gitignored and cleared by step 0.5. Deletes and the stale `.git/index.lock` are
  owner-run on macOS — the Cowork/Dropbox mount blocks unlinks.

- **2026-07-23 — v2.0.1 inspector polish: Type controls labeled + Content moved [app]:**
  In the single-text-selection inspector (`MainWindow.textControls`), the typeface
  menu now has a "Font" label and the weight menu a "Weight" label, and the
  semantic **Content** role picker moved out from directly above the font menu into
  its own `Divider`-separated sub-section below the Case row. Owner reported the
  Content and Font dropdowns were easy to confuse; layout-only change, no behavior
  or binding changes.

- **2026-07-23 — v2.0.1 fixes landed: BUG-006 state-leak + BUG-005 Pen Shift [app]:**
  Closed both blocked-demo defects. **BUG-006 (P1):** extended
  `InstanceOverride.Value` with `.textStyle(TextStyleOverride)` (a bounded,
  all-optional typography bundle — color/face/size/underline/align/line-height +
  unit/tracking/case) and `.opacity(Double)`. `ComponentStateEditing.capture`
  now diffs typography and layer/group opacity into the active state and resets
  the base text node to its pristine content+frame, so a non-default state's
  edits can no longer fall through to the shared source. The new cases are folded
  in by `ComponentStateEditing.apply` (source-editor preview),
  `ComponentInstance.applyingOverrides` (instance + ephemeral-state render), and
  `SemanticHTMLExporter.semanticHTMLResolvedNode` (handoff — the per-state CSS
  emitter re-resolves each state and writes full declarations, so opacity/typography
  flow through automatically). `TextStyleOverride` lives in `Document.swift`, which
  is already a member of both the app and EXPThumbnail targets, so no target-membership
  change was needed. All inspector edits route through the `commitScoped`/`capture`
  funnel, so the fix is exercised for color, face, size, alignment, line-height,
  tracking, case, and opacity. Tolerant schema-v2 decode preserved (synthesized
  Codable omits nil fields / decodes missing keys as nil); one undo step unchanged.
  **BUG-005 (P2):** `penHandleDrag` now takes the live Shift state from
  `mouseDragged` and snaps the dragged handle to axis/45° via `constrainLineEndpoint`
  (mirroring `pathPointDrag`'s control-handle branches); the opposite handle is
  re-derived so it stays mirrored, and pressing/releasing Shift mid-drag toggles the
  snap. Free dragging and one-undo-per-path are unchanged. BACKLOG entries set to
  needs-verify; owner builds in Xcode to confirm both repros from the 2026-07-23
  recording before the two clips are rerecorded and the v2.0.1 release runs.

- **2026-07-23 — v2.0.1 bug-fix lane opened; scaffolding prepped [app]:** Bumped
  the project to `MARKETING_VERSION 2.0.1` / build 11 via
  `scripts/set_release_version.sh`, added `RELEASE-NOTES-v2.0.1.md`, and opened
  the `## v2.0.1 — in progress` cycle above. The lane closes the two verified
  defects from the 2026-07-23 Help recording — P1 BUG-006 (component-state
  typography/opacity edits leaking into the shared source) and P2 BUG-005 (Shift
  ignored while pulling a new Pen handle) — so the two blocked demonstrations can
  be rerecorded. Release artifacts and the git/gh/Xcode steps remain owner-run;
  the v1.6.1 copy/paste path in `docs/RELEASE-CHECKLIST.md` is the model.

- **2026-07-23 — Third Help recording curated; two verified bugs prioritized [site/app]:**
  Locally transcribed and visually reviewed the owner's 42:16
  `a-whole-lotta-stuff-and-bugs.mov` walkthrough. Curated the material into six
  task-oriented Help drafts covering text, basic shapes, vector paths, accessible
  responsive buttons, reusable components, and component states/instance
  navigation, with an eighteen-clip clean rerecording plan in
  `website/content/help/recording-03-text-paths-components.md`. Confirmed two
  defects against the implementation and added complete backlog entries: P1
  BUG-006 (typography and opacity edits leak from an active component state into
  the shared source) and P2 BUG-005 (Shift is ignored while pulling a new Pen
  handle). Added a post-v2.0 priority lane: fix BUG-006 first, BUG-005 second,
  then record the two blocked demonstrations and integrate the tutorial batch.

- **2026-07-23 — Second edited clip set integrated into searchable Help [site]:**
  Published five more task-oriented tutorials locally: creating/transforming
  shapes, guides and spacing measurement, alignment/distribution, layer
  organization, and grouping/nested-group editing. Optimized twelve edited
  source recordings into thirteen silent H.264 visual guides with poster images;
  the longer layer-renaming recording became focused rename and covered-object
  guides. Updated the duplication instructions and clip description to include
  keyboard and menu copy/paste, Option-drag, and aligned Option-Shift-drag.
  Delete and Ungroup remain concise written instructions, so no rerecording is
  needed for those actions. The library now contains ten searchable tutorials
  and twenty-four visual guides. All article relationships and media references
  validate, and the production Vite build passes. Work is local only; no
  deployment was performed. The editorial record and clip map remain in
  `website/content/help/recording-02-shapes-groups-align-layers.md`.

- **2026-07-23 — Searchable Help library built from the first edited clip set [site]:**
  Replaced the `/learn` placeholders with a real task-oriented Help experience:
  five searchable written tutorials (artboards, the wall, canvas navigation,
  document-grid snapping, and artboard layout grids), category filters, related
  articles, per-page contents navigation, and eleven short visual guides. Added
  the owner's follow-up **Center in Canvas** clip to the navigation tutorial and
  indexed both the UI label and the conversational “center on canvas” phrasing.
  Preserved the full-resolution originals outside the site; generated 1920px
  H.264 web copies plus poster images in `website/public/assets/help/`. Clips are
  silent, use native controls, lazy-load, play only while substantially visible,
  pause offscreen, and stay on their poster when Reduce Motion is enabled. The
  production Vite build passes and all article-to-asset references were checked.
  Work is local only; no deployment was performed.

- **2026-07-22 — First Help recording curated into a written-content pilot [site]:**
  Reviewed and locally transcribed the owner's 17:58 canvas/artboard walkthrough,
  then converted the natural long-form demonstration into five task-oriented
  draft pages: artboard management, using the wall, pan/zoom, the document grid,
  and per-artboard layout grids. Added an editorial map, searchable terms, and a
  timestamped micro-clip cut sheet at
  `website/content/help/recording-01-canvas-artboards.md`. Flagged the failed
  Fit to Screen demonstration at 12:05–12:22 as a bug/reproduction lead and
  excluded it from publishable help. Draft content is not yet wired into `/learn`;
  the owner will edit/re-record the short muted loops before the searchable Help
  interface is built.

- **2026-07-22 — v2.0 shipped; first complete Sparkle update proof passed:** Owner
  confirmed the preserved v1.6.1 installation discovered v2.0, downloaded the
  signed update, installed, and relaunched successfully—closing the update path
  that earlier releases could not prove. Independent final checks confirm local
  and remote `main` synchronized at the release-metadata commit; the public,
  non-prerelease GitHub Release serves the exact 27,922,074-byte archive with
  SHA-256 `3abbd5a1b1e67fb49859e503f3c3d8b4c5536c65b9b18497738bf4023192ca92`;
  the live appcast advertises v2.0/build 10 with its EdDSA signature; and the
  asset, HTML notes, site, and ARIA guide all return successfully. A final
  isolated smoke against the Developer ID/notarized v2 app initialized the local
  bridge, discovered all six tools, read a front document, confirmed the 0600
  current-UID socket, and left the owner's already-running installed app
  untouched. All v2.0 release gates are now closed. ✨

- **2026-07-22 — v2.0 release staging hardened after live dry run:** The first
  production pass exposed two workflow—not app—failures. Running `set -euo
  pipefail` directly in the interactive shell closed the Terminal window at the
  first guard failure, and Dropbox repeatedly reattached `com.apple.FinderInfo`
  to five signed nested bundles after `xattr` cleanup. Wrapped every v2 runbook
  block in a subshell so failures return to the prompt, moved signed app/zip and
  accumulated Sparkle staging to non-synced `~/Library/Developer/` folders, and
  taught the verifier to identify Dropbox as the likely metadata source. Copied
  the already-notarized v2 app into clean local staging without extended
  attributes; production verification passes version/build, universal slices,
  entitlements, strict nested signatures, Gatekeeper, and staple both before and
  after zip round-trip. Created the immutable 27 MB v2 zip with SHA-256
  `3abbd5a1b1e67fb49859e503f3c3d8b4c5536c65b9b18497738bf4023192ca92`.
  Also made tag publication resumable: the already-pushed v2.0 tag may be reused
  only when it is the current release-source commit or exactly one metadata
  commit behind HEAD, and its peeled remote commit must match locally. No GitHub
  Release, appcast, or website deployment was performed during this recovery.
  OWNER FOLLOW-UP: Dropbox syncing was paused and the owner asked to retain the
  normal sibling release directories while they repair the ignored-folder rule.
  Cleared the regular exported app again and reran the full production verifier
  successfully, but File Provider metadata returned even with syncing paused.
  Copied the clean local safety zip byte-for-byte back to
  `apps/releases/v2.0/`; its SHA-256 is unchanged. The runbook again uses the
  standard directories for every final artifact, while Step 6 verifies and zips
  from an ephemeral clean app copy so File Provider cannot race the signature
  check. The local clean zip also remains available as a fallback. FINAL RUNBOOK
  FOLLOW-UP: zsh still reported `no matches found` when an older/copied path
  retained the literal `EXP [design]/..` segment. All v2 release/Sparkle paths
  now canonicalize the parent `apps` directory first, yielding a bracket-free
  `/apps/releases/v2.0/...` path even if a quote is lost. Step 8 conditionally
  amends only these reviewed runbook corrections into the still-unpushed local
  metadata commit before enforcing a completely clean tree.

- **2026-07-22 — v2.0 release runbook made fully copy/paste-ready:** Replaced the
  partial v2 release notes in `docs/RELEASE-CHECKLIST.md` with one linear,
  version-specific build 10 path: canonical external artifact locations, complete
  automated gate, owner acceptance, intentional source commit, fresh local Xcode
  archive, Direct Distribution destination, production app/staple/Gatekeeper and
  zip round-trip verification, exact Sparkle generation, automatic release-date
  heading update, release-metadata commit, annotated tag, GitHub upload and byte-
  identity download check, Vercel deployment order, public endpoint checks, and
  the v1.6.1 → v2.0 install/relaunch proof. The asset is now uploaded before
  `main` is pushed, preventing Vercel from briefly serving an appcast whose
  download does not exist yet. Added a narrow cleanup for Xcode's generated
  `exp-mcp` per-user auto-scheme entry so `git add -A` cannot accidentally ship
  that noise. Audited all 31 shell blocks with `bash -n`, exercised the roadmap
  transformation and scheme cleanup on temporary copies, verified every named
  helper is executable, and confirmed the existing public endpoint response
  shape used by the live checks.

- **2026-07-22 — v2.0 release candidate matrix green; human/distribution gates remain:**
  Added public v2.0/build 10 release notes, a copy/paste v2 release path, and a
  reusable `verify_release_candidate.sh` that checks version/build, universal app
  and helper slices, Finder metadata, strict nested signatures, the sandbox/Sparkle
  entitlement boundary, Gatekeeper, and the notarization staple (with a local-
  archive mode for the last two). Semantic HTML contract/package tests, SVG token
  bridge, Sparkle preflight, and production website build all pass. A 5.7 MB owner
  document completed the real-package smoke with valid manifest hashes and one
  full semantic page. Created an Apple Development-signed universal Xcode archive;
  both the app and bundled `exp-mcp` pass strict signature/entitlement inspection.
  The shipping Codex 0.145 client discovered the archived helper and successfully
  called all six read-only tools; live checks also proved protected 0600/current-
  UID socket creation, document retargeting, honest unavailable/default-off errors,
  response-free notifications, and socket removal at shutdown. Added the missing
  graphics-design application category to clear the archive metadata warning.
  Existing Swift 6 migration warnings remain known backlog rather than new v2
  regressions. LEFT FOR OWNER/DISTRIBUTION: subjective browser/VoiceOver handoff
  acceptance, Direct Distribution/Developer ID notarize+staple, exact zip/appcast/
  GitHub/site publication, and the v1.6.1 → v2.0 Sparkle install/relaunch proof.

- **2026-07-22 — v2.0 closure audit + agent skills roadmapped:** Confirmed the
  planned v2.0 feature/spine work is complete; no additional interop chunk belongs
  in this release. Added an explicit remaining release-gate checklist: owner
  real-document handoff acceptance, compatibility through a shipping MCP client,
  production-signed/notarized nested-helper and default-off/socket security,
  release notes/package/appcast/site publication, and the first full v1.6.1 →
  v2.0 Sparkle install/relaunch proof (including VoiceOver/increased contrast).
  Local Release already confirms `exp-mcp` is universal arm64+x86_64. Extended
  Sparkle preflight to require the sandbox server entitlement used solely for the
  container-local Unix socket. Also roadmapped v2.1 agent capability packs: one
  canonical tool-use/privacy guide plus tested Codex/Claude/other host wrappers
  with EXP branding wherever supported; raw MCP remains the non-proprietary base.
  LATER: owner explicitly deferred SCSS to the back burner; it is not a v2.0
  blocker or promised follow-up and returns only if downstream testing reveals a
  concrete need. Verified CSS/custom properties remain the shipping contract.

- **2026-07-22 — F1 Agent Bridge spine complete + v2.1 panel IA logged:** EXP
  now ships dark as a local read-only MCP server when—and only when—the hidden
  `exp.agentBridge.enabled` default is true. The signed app owns a 0600,
  current-UID-verified Unix socket inside its sandbox Application Support
  container; a new real command-line target bundles `exp-mcp` at
  `Contents/Helpers/`, relaying standard newline-delimited MCP stdio without any
  network listener or vendor credentials. The protocol handles initialize,
  ping, tool/resource discovery, the shared README orientation resource, and the
  six intentionally small-surface tools: `get_orientation`, `list_artboards`,
  `get_artboard`, `get_selection`, `get_node`, and `get_tokens`. Responses reuse
  the native Codable document fragments and existing DTCG/README generators;
  front-document/selection context follows PanelHub. The helper returns the
  exact planned unavailable message for every request when EXP/access is off,
  while notifications remain response-free. Signed Debug build passed; live
  helper↔app checks covered all six tools, valid artboard/node round-trips,
  tool/resource orientation equality, error paths, clean socket shutdown, and
  intact multi-megabyte detail framing. The temporary hidden default was removed
  after testing. Also placed the owner-requested v2.1 Panel IA + complete shipped-
  command inventory beside F2, explicitly including Pathfinder/vector tools,
  alignment/distribution, components/semantics, Design Language, and handoff,
  with additive menu/shortcut access and accessibility acceptance criteria.

- **2026-07-22 — v2.0 Chunk B / B4b complete:** Closed semantic HTML/CSS with
  evidence before moving on (the pun survived after all). Fixed-input Handoff
  Packages now compare byte-for-byte and against reviewed HTML/CSS/manifest/
  README SHA-256 goldens; a generated smoke document exercises all 40 curated
  ARIA roles through the real exporter. Broken relationships remain out of the
  DOM and become structured semantic requirements; unsupported effects and the
  other known non-exact visual paths become categorized, instance-qualified
  fallbacks in both manifest and README. Tightened standards behavior with
  phrasing-only native Button descendants, flow-safe List/List Item hosts, honest
  `lang="und"`, visible keyboard focus, and increased-contrast CSS. Firefox and
  WebKit accessibility-tree/focus/appearance/geometry/overflow/console checks,
  visual screenshot review, W3C Nu validation, all headless semantic/SVG suites,
  and the full unsigned Debug app + Quick Look build pass. Chunk B is complete;
  next v2.0 implementation slice is F1, the hidden/off-by-default read-only Agent
  Bridge spine.

- **2026-07-22 — Typography added to Design Language Settings:** Closed the
  settings-screen omission: saved Type Styles now have their own typography
  section with a live face/size preview, concise line-height/tracking/alignment/
  case details, inline rename, shared-category assignment, and undoable delete.
  Empty-state and category copy now describe both paints and typography, and EXP
  JSON/CSS export remains available for a typography-only design language. The
  UI explicitly preserves the semantic boundary: Type Styles are presentation;
  Paragraph and Heading 1–6 remain per-text content roles. Full unsigned Debug
  app + Quick Look build passes. Next active v2.0 work remains B4b verification.

- **2026-07-22 — v2.1 nested components + semantic containment scoped:** Logged
  first-class component composition as Chunk I / Phase 4.1, sequenced before
  component-preserving Figma/XD import. The slice includes cycle-safe source
  dependencies, stable instance-path identity for recursive overrides and DOM ids,
  nested public-prop/state/layout/detach/export behavior, and complete save/import
  coverage. Paired it with context-aware ARIA authoring: semantic parents recommend
  valid child roles (List → List Item, Tab List → Tab, Menu → Menu Item, and the
  other owned-role families) while warnings remain advisory and never silently
  rewrite authored meaning. Next active v2.0 work remains B4b verification.

- **2026-07-22 — ARIA guide integrated + v2.0 B4a text semantics complete:**
  Housed the owner's completed ARIA Roles Designer Guide at the website's new
  `/aria-roles/` static section and linked it from Learn. Added Help ▸ ARIA Roles
  Guide as a focused, resizable `WKWebView` window with no browser toolbar,
  allowlisted first-party navigation, external-link handoff, loading state, and
  accessible retry/open-in-browser failure UI. The guide remains online-only for
  now because its export loads runtime/icon assets from unpkg. Then completed the
  next roadmap slice: text layers now author Plain text, Paragraph, or Heading
  1–6 independently from Type Styles; semantic handoff emits native tags and
  resolves Heading-component `aria-level` without nested duplicate headings.
  Website production build, semantic package suite, tolerant codec coverage,
  and unsigned Debug app/Quick Look build pass. Next: B4b standards, browser,
  VoiceOver/keyboard, appearance, determinism, and fidelity verification.

- **2026-07-22 — Semantic authoring follow-ons placed:** Testing exposed a
  useful distinction between typography as presentation and text as content.
  Locked the boundary: Type Style categories remain visual organization; a new
  per-text content role in v2.0 B4a will carry Paragraph or Heading 1–6 and drive
  native `<p>`/`<h1>`…`<h6>` export without guessing from font size or style
  names. Also planned a focused, allowlisted in-app window for the owner's
  searchable ARIA reference web app as Phase 19d / likely v2.1. It will open
  contextually from role authoring, preserve concise offline blurbs, expose
  network/error state accessibly, send outside links to the default browser,
  and remain documentation-dependent rather than blocking v2.0.

- **2026-07-22 — v2.0 B3 layout + Design Language fidelity complete:** Semantic
  handoff now maps managed horizontal/vertical stacks to real flexbox, including
  packed gap/primary alignment, space-between distribution, cross alignment,
  and managed padding; children become fixed flex items while free-positioned
  artwork keeps its honest absolute geometry. Consolidated deterministic Design
  Language CSS bindings so exact paints emit `var(--token, fallback)` and exact
  whole-text matches emit reusable type-style classes (mixed rich text stays
  explicit). Standalone SVG uses the same lookup for fills/strokes, embeds token
  declarations, and preserves literal fallbacks without double-applying alpha.
  Both semantic headless suites, the new semi-transparent SVG token smoke check,
  and a full unsigned Debug build of the app + Quick Look extension pass. Next:
  B4 accessibility, browser fidelity, determinism, and fallback reporting.

- **2026-07-21 — Real-export vector and gradient fidelity fixed:** The owner's
  browser-versus-canvas screenshot isolated two distinct baseline issues. HTML
  treated every imported path as a background-filled rectangle, turning a
  complex SVG portrait into block art; path nodes now emit their actual inline
  SVG cubic/multi-contour geometry with fill, stroke, alpha, and local gradients.
  CSS also used EXP angles verbatim even though the coordinate conventions
  differ; generated linear gradients now normalize `EXP angle + 90°` (the real
  document's 90° top-to-bottom gradient correctly becomes CSS 180°). Extended
  the golden fixture with curved SVG data and angle checks, smoke-exported the
  owner's real document with 282 artboard-owned inline paths, and confirmed a
  clean Debug build. Playwright screenshot automation was unavailable because
  Google Chrome is not installed; artifact-level verification completed without
  installing new software. Next remains B3 auto-layout and Design Language
  fidelity.

- **2026-07-21 — v2.0 semantic component HTML active:** Finished Chunk B2 and
  incorporated the owner's first real export feedback. Diagnosed the stylesheet
  failure in the actual `test2` package: generated `rgb()` values lacked their
  closing parenthesis, causing browser CSS parsing to fail. Fixed and regression
  tested it. `README.llm.md` now includes each complete artboard note as a
  blockquote rather than only noting its presence. Categorized instances now use
  native HTML or explicit ARIA hosts; accessible-name layers and typed
  relationships resolve through duplicate-safe ids; component states emit
  pseudo-class/disabled/custom selectors; unresolved facts appear as structured
  manifest and README requirements; and no JavaScript is generated. The golden
  package checks, a smoke export of the owner's real 900×1322 document, and the
  full Debug build all pass. Next: B3 auto-layout and Design Language fidelity.

- **2026-07-21 — v2.0 first semantic HTML/CSS package slice complete:** Finished
  Chunk B1. `HandoffPackageWriter` now emits `html/styles.css` and one standalone,
  deterministic HTML file per artboard; lists and hashes them in `manifest.json`;
  and explains entry points/fidelity in `README.llm.md`. The baseline preserves
  absolute geometry, stable `data-exp-id` identity, frontmost-first plain-group
  reading order, visual-axis auto-layout order, resolved component visuals with
  duplicate-safe instance ids, hidden-layer addressability, basic visual styles,
  and safe HTML/CSS strings. Wall-only nodes remain in `design.json` and are
  counted as HTML omissions. Both headless semantic checks and the full Debug
  build pass. Next: B2 component roles, names, relationships, and states.

- **2026-07-21 — v2.0 semantic HTML/CSS contract complete:** Finished Chunk B0.
  Defined all 40 curated ARIA-role mappings with native HTML preference and
  explicit missing-data requirements; stable artboard/node/component identity;
  duplicate-safe instance/source IDs; deterministic filenames; DOM/reading-order,
  state-selector, relationship, notes, and escaping rules. Added an executable
  headless golden-fixture verifier and confirmed a clean Debug build. Next: B1,
  the first document-wide HTML/CSS bundle emitter.

- **2026-07-21 — v1.6.1 installed updater baseline verified:** The baseline
  audit caught `com.apple.FinderInfo` metadata attached post-install to the
  thumbnail extension and nested Sparkle resources/XPC services. Removed only
  that attribute recursively, then reran the complete check: EXP reports
  1.6.1/build 9; the app, thumbnail extension, Sparkle framework, Updater,
  Downloader/Installer XPC services, and Autoupdate all pass strict signature
  validation; Gatekeeper accepts the app as Notarized Developer ID. Preserve
  this installed copy for v2.0's prompt → install → relaunch proof.

- **2026-07-21 — Owner verified SVG stylesheet colors:** Rebuilt and re-imported
  `1813-bowtie.svg`; the native layers now retain their source colors and the
  all-black regression is closed. v2.0 can resume at Chunk B0.

- **2026-07-21 — SVG stylesheet-class color import fixed:** Diagnosed the
  intermittent “all layers black” report using owner-supplied
  `1813-bowtie.svg`. The geometry used `class="cls-N"` while all 133 paints lived
  in a `<style>` block; `SVGImporter` previously read only presentation
  attributes and inline `style`, so intact paths fell back to SVG's initial
  black fill. Added a bounded stylesheet cascade for simple element/id/class
  selectors, with specificity/source-order and inline-style precedence, shared
  across layer styles, gradient stops, and filters. Debug build succeeds. A
  headless import reports 418 native nodes and exactly 133 unique colors; focused
  class/presentation/inline precedence coverage passes. Owner visual drag-in
  verification remains.

- **2026-07-21 — v1.6.1 shipped; v2.0/build 10 opened:** Owner confirmed the
  Developer ID/notarized/stapled release, exact Sparkle archive/appcast, GitHub
  release, website publication, and pushes are complete. Closed the v1.6.1
  release-candidate/distribution gates. The manual installed-baseline check and
  first automatic install/relaunch proof remain explicit owner gates. Opened
  v2.0 as the active cycle and decomposed Chunk B into an executable semantic
  export sequence: contract fixture → first `.exph` HTML/CSS vertical slice →
  component semantics/states → flexbox/token/SVG fidelity → accessibility and
  deterministic-output verification.

- **2026-07-20 — v1.6.1 download-page status cleanup [site]:** Removed the
  resolved rich-text click-out issue from the tester download page and marked
  the three completed v1.6 feature cards as done so they receive the existing
  completed-state label treatment. Production website build passed.

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
  logged PERF-006 (filed that day as PERF-005; renumbered 2026-08-11 because
  the id was already held by the ruler entry) (instCache counters flat at 0 — verify on an instance-heavy
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
