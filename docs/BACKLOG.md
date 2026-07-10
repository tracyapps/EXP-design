# EXP [design] — Backlog & Bug Tracker

A single, structured list of bugs, feature ideas, and performance work — written
so BOTH a human and an AI agent can pick something up cold. It complements
ROADMAP.md (which holds the phase plan + the Progress Log). Use ROADMAP for
"what's the plan / what happened"; use THIS for "what's the queue."

## How agents should use this
1. Pick the top **unclaimed** item at the priority you're asked for (P1 → P3).
2. Read its **Repro/Detail**, **Hypothesis**, and **Acceptance** before touching code.
3. Set `Status: in-progress`, implement, then set `Status: needs-verify` (owner
   builds & confirms) and add a dated **Progress Log** entry to ROADMAP.md.
4. Respect the CLAUDE.md rules (command-coverage, shared-target files, a11y).

## Entry format (copy this)
```
### <ID> — <one-line title>
- Type: bug | feature | perf
- Priority: P1 (soon) | P2 | P3 (someday)
- Area: canvas | inspector | model | color | export | chrome | perf | infra
- Status: open | in-progress | needs-verify | done
- Repro/Detail: <what happens / what's wanted, concrete steps>
- Hypothesis: <suspected cause or approach — optional>
- Acceptance: <how we know it's done>
```

---

## 🐞 Bugs

### BUG-004 — Custom centered document title uses native popup anchor awkwardly
- Type: bug
- Priority: P2
- Area: chrome
- Status: open
- Repro/Detail: The main window draws a custom centered EXP-styled document title,
  but the native macOS rename/location bubble is still anchored to the left-side
  titlebar document controls. The centered "Edited" label can also fail to appear
  even while AppKit's native edited state is active.
- Hypothesis: AppKit's document rename/location popover is tied to private/native
  titlebar controls. The current implementation keeps those controls alive but
  visually transparent, then forwards clicks from the centered title. A robust fix
  may need either a custom rename/move popover that mirrors the native fields, or a
  better public AppKit anchor strategy using a titlebar accessory/custom view.
- Acceptance: only the centered EXP title is visible; edited state appears under it
  in `EXPColor.accent`; clicking the centered title opens rename/location UI near
  the centered title with no leftover native title glyphs or console warnings.

### BUG-003 — Gradient darkens (color shift) during pan/zoom blit
- Type: bug
- Priority: P2
- Area: canvas · color
- Status: done (v1.2 — verified by owner)
- Update (S174): switching the CGGradient space to sRGB did not resolve the darkening,
  so the root cause is elsewhere. Next hypotheses to test: (a) the offscreen backing is
  premultipliedFirst/BGRA and `cg.makeImage()` -> `ctx.draw` round-trips premultiplied
  alpha, darkening a gradient that has a SEMI-TRANSPARENT stop (check whether the
  affected gradient has an alpha<1 stop while the unaffected one is fully opaque);
  (b) the snapshot CGImage is tagged the window/offscreen space (P3) but drawn into a
  window drawRect context of a different space, so ONLY color-managed content shifts;
  (c) possible interaction with the new HSB/HSL/OKLCH authoring — verify the stored
  RGBAColor values are byte-identical before/after editing via the new picker modes;
  (d) instrument by dumping the affected gradient's stop colors + alphas.
- Update (v1.2): pan/zoom snapshots now render into a document-sRGB offscreen
  backing instead of inheriting the window/Display-P3 space. Other offscreen paths
  keep the old window-space default. Needs owner visual verification on the
  saturated semi-transparent gradient repro.
- Update (v1.2 follow-up): owner testing showed the sRGB snapshot still shifted,
  and that during node drags the moved gradient stayed correct while static
  gradients changed. That localizes the issue to bitmap flattening of static
  content. Current fix: visible gradients and enabled drop/inner shadows bypass
  pan/zoom bitmap blit and force true live compositing for drag gestures when any
  non-dragged visible gradient/shadow content is present. Plain content still uses
  the fast snapshot paths.
- Verified (2026-07-06): owner confirmed the gradient/shadow interaction shift is
  fixed.
- Repro/Detail: A saturated gradient on the canvas visibly darkens while panning or
  zooming, then snaps back to the correct color when motion stops. A near-neutral
  gradient elsewhere doesn't show it. (Anti-aliased text also shimmers slightly mid-
  gesture — that's a separate, expected blit artifact; see note.)
- Prior hypothesis: `PaintRender.drawGradient` built the `CGGradient` in
  `CGColorSpaceCreateDeviceRGB()` — an UNMANAGED device space — while its stop colors
  (and every solid fill) are sRGB. During pan/zoom the scene is drawn into the
  color-managed offscreen blit bitmap (window color space, usually Display P3); an
  unmanaged device-RGB gradient color-matches differently there than in the live
  window device context, so only the blit shifts. Live settle render looked correct.
- Fix attempt: keep gradient interpolation in sRGB, render pan/zoom snapshots in
  document sRGB for plain content, and bypass snapshot flattening entirely when
  visible gradient/shadow content would otherwise change color mid-gesture.
- Acceptance: gradient looks identical while moving and stopped; export unchanged.


### BUG-001 — Measurements shown as whole numbers while real values are fractional
- Type: bug
- Priority: P2
- Area: inspector · canvas
- Status: done (Session 161 — inspector DimFields show 0–2 truthful decimals, measure HUD matches, canvas snaps to whole px by default with ⌘ bypass)
- Repro/Detail: With snap-to-grid OFF, position it so auto-layout / free placement
  yields sub-pixel spacing. The on-canvas ⌥-hover measure labels and every inspector
  numeric field show WHOLE numbers, so a real gap of e.g. 12.4 reads as "12". You
  can't see or type sub-pixel values.
- Hypothesis: display-only precision loss. Every numeric `TextField` uses
  `format: .number.precision(.fractionLength(0))` (MainWindow) and the canvas
  measure/ruler labels round via `Int(...)` (`measureLabel`, `drawRulerNumber`).
  The model stores fractional `CGFloat`, so nothing is lost until the user TYPES a
  value (which then commits the rounded whole number).
- Acceptance: fields + measure labels show a sensible precision (e.g. up to 1–2
  fraction digits, trailing-zero-trimmed) and typing a fractional value keeps it.
  Decide a rounding policy (display vs. stored) and apply it consistently.

---

### BUG-002 — "Publishing changes from within view updates" (~40×) — repro: inspector ↑/↓ stepping
- Type: bug
- Priority: P1
- Area: inspector · chrome
- Status: needs-verify (Session 162f — `NumericStepping.onKeyPress` now defers
  the binding write one runloop tick via `DispatchQueue.main.async`, moving the
  model mutation outside SwiftUI's update pass. Step sizes, ⇧/⌥ modifiers,
  key-repeat acceleration, and undo unchanged. IF a warning flood still appears
  at LAUNCH (without touching the inspector), that's a second site — hunt it
  with a symbolic breakpoint on the warning; window restoration writing to
  AppState during body evaluation is the suspect.)
- Repro/Detail: Owner isolated it (2026-07-02): using the KEYBOARD arrows to
  increase/decrease values in inspector fields fires the warning; it also
  floods ~40× at app launch. Session 124-era mystery, now reproducible.
- Hypothesis: `NumericStepping.onKeyPress` (UI/MainWindow.swift) writes the
  bound value SYNCHRONOUSLY inside the key-press handler, which runs during a
  SwiftUI view update — mutating an @Observable/@Published mid-update is the
  textbook trigger. Likely fix: defer the mutation one tick
  (`Task { @MainActor in value = next }` or `DispatchQueue.main.async`),
  keeping ⌥/⇧ step sizes + key-repeat acceleration identical. The launch-time
  flood may be a second site (window restoration / initial layout writing to
  AppState during body evaluation) — verify separately with a breakpoint on
  the warning after the stepper fix lands.
- Acceptance: zero warnings while arrow-stepping any inspector field (incl.
  held-key repeat), zero at launch; stepping behavior unchanged (±1, ⇧±10,
  ⌥±0.1, acceleration); undo granularity unchanged.

## ✨ Features

### FEAT-001 — Color: saved / recent colors + palettes (doc-linked, import/export)
- Type: feature
- Priority: P2
- Area: color · model
- Status: in progress (Session 167) — document model + panel save/pick/recents landed; import/export (FEAT-007/18e) still open
- Repro/Detail: Recent-colors strip and a saved-swatches area in the color popover;
  named colors that live ON the document (so they travel with the file) AND can be
  exported/imported to share between documents. This is the first slice of ROADMAP
  Phase 18's Design Language model: document-local assets, not app chrome tokens.
- Hypothesis: add a document-level `DesignLanguage` or `colorLibrary` with
  `recentPaints` plus named entries (`id`, `name`, `status: candidate/official/
  archived`, `value`, provenance). Backward-compatible decode. Surface a minimal
  save/pick flow in `ColorPopover` first; graduate to the Design Language panel in
  FEAT-006. Generation can reuse `ColorMath` (OKLCH) for perceptually-even ramps.
- Acceptance: pick from recents/saved; save and rename a swatch; mark candidate vs.
  official; export a small JSON from doc A and import into doc B; entries persist in
  the `.design` file.

### FEAT-002 — Color-mode-specific picker behavior
- Type: feature
- Priority: P3
- Area: color
- Status: in progress (Session 166) — HSB/HSL/OKLCH mode-aware controls + sRGB gamut warning landed; wide-gamut ColorValue not pursued
- Repro/Detail: Phase 8 can type/copy HSL/LCH/OKLCH, but the visual editor is still
  essentially HSB/SV + hue/alpha with sRGB storage. Owner wants truly model-aware
  authoring, especially HSL and OKLCH, with honest gamut handling.
- Hypothesis: redesign `ColorPopover` around editing modes. HSB/HSL/OKLCH each get
  controls that match their axes; OKLCH should also drive ramp/adjustment helpers.
  Before adding Display-P3, decide whether the model stays sRGB-with-warnings or
  grows a richer `ColorValue(colorSpace:components:)`.
- Acceptance: switching mode changes the picker's controls, not just its code field;
  OKLCH edits can warn when clamped to sRGB; copied values match the selected mode.

### FEAT-003 — In-app bug/feedback reporter (agent-ingestible)
- Type: feature
- Priority: P2
- Area: infra · chrome
- Status: open
- Repro/Detail: A Help ▸ "Report an Issue / Idea…" that opens a small form (title,
  type: bug/idea, description, optional screenshot) and auto-attaches CONTEXT:
  app version, macOS version, current tool, selection summary, doc stats (artboards/
  nodes/sources), and the last few undo action names. Writes a structured record.
- Hypothesis: capture to a Markdown/JSON file matching THIS backlog's entry format
  (so an agent can drop it straight into Bugs), saved to a chosen folder and/or opened
  as a prefilled GitHub issue / mail draft. Keep the payload PII-free (no doc content,
  just stats) unless the user opts to attach the file.
- Acceptance: one action produces a ready-to-triage entry with reproducible context;
  agents can read the folder and pick items up.

### FEAT-005 — Color contrast checker (WCAG-first, APCA advisory)
- Type: feature
- Priority: P2
- Area: color · inspector · a11y
- Status: in progress (Session 166) — ContrastMath (WCAG 2.x) + picker contrast strip landed; APCA and panel comparisons pending
- Repro/Detail: Designers need to check foreground/background contrast while choosing
  colors, saving library entries, and editing text/fills. This should be part of the
  color workflow, not a separate external chore.
- Hypothesis: add pure `ContrastMath` beside `ColorMath`: WCAG 2.x relative
  luminance/contrast ratio, AA/AAA thresholds for normal text, large text, and
  non-text UI components. Flatten alpha colors over the relevant artboard/background.
  APCA can appear as advisory/exploratory if useful, but not as the primary pass/fail.
- Acceptance: picker/panel can compare two colors, selected text vs. background, and
  library swatch pairs; labels are clear; suggestions can adjust OKLCH lightness to
  reach AA without silently changing the document.

### FEAT-006 — Design Language panel (colors + gradients first)
- Type: feature
- Priority: P2
- Area: color · chrome · model
- Status: in progress (Session 167) — panel live with sections + apply/save/promote/rename/copy; in-place value edit, reveal-uses, and menu-bar command pending
- Repro/Detail: The reserved Color panel should grow into a document-local "Design
  Language" panel, similar in spirit to Components/library panels: saved colors,
  gradients, candidates/maybes, official entries, and later type/spacing/effects.
- Hypothesis: add `PanelID.designLanguage` (or rename the reserved Color panel) using
  the existing host-agnostic panel pattern. Sections: Official Colors, Candidate
  Colors, Gradients, Recents. Actions: apply to selection, rename/edit, promote,
  archive, copy values, import/export, reveal uses.
- Acceptance: panel works docked/floating, reflects the document model live, and lets
  the owner move a candidate color/gradient into the official list.

### FEAT-007 — Palette inspiration/import providers
- Type: feature
- Priority: P3
- Area: color · import
- Status: in progress (Session 169) — import + local generators done (EXP JSON / CSS / paste / OKLCH ramp / harmonies / accessible pair); image extraction + remote providers still open
- Repro/Detail: Owner wants to browse/import palette inspiration from places like
  Adobe Color, Coolors, RandomA11y, and Figma palettes, with an easy way to add
  options to the document as candidates or official entries.
- Hypothesis: build a provider/import framework before any service-specific UI. Local
  providers first: OKLCH ramps, harmonies, accessible pairs, image extraction. Remote
  or web sources should use documented APIs, user-pasted URLs, or exported files only;
  avoid scraping private/undocumented endpoints. Research snapshot lives in ROADMAP
  Phase 18f.
- Acceptance: paste/import a palette representation into the document as candidates;
  local generation produces usable options; each imported option keeps a visible source
  label/provenance.

---

## ⚡ Performance

### PERF-005 — instCacheHit/Miss counters flat at 0 — verify they still track
- Type: perf
- Priority: P3 (someday)
- Area: perf
- Status: open
- Repro/Detail: Both Testing Mode counters read 0 (max 0) across every sample
  in the 2026-07-09 v1.2.1 logs. The doc under test may simply contain no
  component instances — but if the counters are ALSO flat on an
  instance-heavy doc, the instrumentation (or the instance cache itself) has
  silently stopped tracking. Owner is keeping an eye out.
- Hypothesis: Doc had no instances (benign) OR counter increments were lost in
  a refactor (check the instance-cache hit/miss paths against the
  resolveGeneration invariants).
- Acceptance: Testing Mode on an instance-heavy doc shows nonzero hits/misses;
  or confirmed benign and this entry closed with a note.

### PERF-001 — Large / complex document performance (standing epic)
- Type: perf
- Priority: P2 (ongoing)
- Area: perf · canvas · model
- Status: open
- Repro/Detail: Keep interaction smooth (pan/zoom/drag ~60fps, fast open/save) as
  documents grow — many artboards, deep groups, many component instances, heavy paths.
- Hypothesis / levers: profile with Instruments (Time Profiler + Core Animation) on a
  stress doc; known areas — the CPU Core-Graphics canvas redraw, instance re-resolve
  cache (see the `exp-canvas-perf` memory note: culling + `resolveGeneration` invariants),
  background-blur readback (already deferred during gestures), SVG export walk. Possible
  moves: tighter dirty-rect invalidation, cache laid-out instances harder, move blur/
  compositing to a GPU/Metal layer (its own phase, see ROADMAP 16.5).
- Acceptance: a repeatable stress-test doc + before/after frame-time numbers; no
  interaction regressions.

---

### PERF-002 — Blend/opacity fidelity while dragging (conditional true-composite mode)
- Type: perf · feature
- Priority: P2
- Area: canvas · perf
- Status: needs-verify (Session 162 — implemented as the per-gesture TRUE/FAST
  decision in `CanvasNSView.shouldTrueCompositeDrag`: dragged subtree uses a
  non-normal blend mode AND `fullFrameEMA` (always-on rolling full-render cost)
  fits the budget from the user's performance mode → full live render for the
  gesture; else fast blit. The cheaper "re-render only the ABOVE region" middle
  option is NOT built — revisit if TRUE mode's budgets feel too conservative.)
- Repro/Detail: With the Session 161i drag-overlay blit, a shape with a blend
  mode (difference/overlay/…) reads as its plain color against anything baked
  into the ABOVE snapshot layer while it's being moved — it only composites
  truly against content BELOW it, and snaps to the correct look on mouseUp.
  Owner wants design-truth kept while moving when the doc can afford it.
- Hypothesis: conditional fidelity. During a drag, choose per-gesture between
  (a) TRUE mode — full live render every tick (the pre-161i path, correct
  compositing) and (b) FAST mode — the current below/above blit. Pick TRUE
  when the gesture is cheap enough: e.g. recent full-frame cost < ~20ms, or
  visible node count under a threshold, or the dragged node has a non-normal
  blend mode AND the scene is small; else FAST. The measured `frame` perf
  stats already exist to drive the decision. Cheaper middle option worth
  trying first: when ANY dragged node has a non-normal blend mode, re-render
  only the ABOVE layer's intersecting region live instead of blitting it.
- Acceptance: moving a difference/overlay shape over other content keeps its
  true composite on small/medium docs; huge docs degrade gracefully to FAST
  with no beachball; no regression to the 1.5–3.6ms drag frames in FAST mode.

### PERF-003 — Panning refinements (bigger/smarter snapshot)
- Type: perf
- Priority: P3
- Area: canvas · perf
- Status: open (partial — halo size + settle delay are now user-tuned via
  PERF-004; adaptive/directional halo and tiled snapshots still open)
- Repro/Detail: 161j's 25% halo + containment recapture works, but long fast
  pans still hit periodic ~30–80ms recaptures, and the settle render redraws
  everything. Ideas queue: adaptive halo (grow toward pan direction/velocity),
  tile-based snapshot (recapture only newly exposed tiles), reuse the drag
  blit's below/above machinery for partial invalidation.
- Acceptance: flick-panning a huge doc shows no blank edges AND no visible
  hitch; Testing Mode shows recapture cost amortized under one frame.

### PERF-004 — User-facing "Speed ↔ Detail" preference (Photoshop memory dial, humane edition)
- Type: feature
- Priority: P3
- Area: chrome · perf
- Status: needs-verify (Session 162 — Settings ▸ Canvas ▸ Performance:
  EXPSegmented "Speed focus / Balanced / Detail focus", persisted via the
  synced-prefs pattern (`AppState.CanvasPerformanceMode`,
  `exp.pref.performanceMode`). Drives: TRUE-drag budget 0/18/40ms, pan halo
  0.15/0.25/0.40, settle delay 0.12/0.08/0.05s. A11y label + hint on the
  control; plain-language footnote.)
- Repro/Detail: Owner idea: a single friendly setting (Settings ▸ Canvas) —
  a slider or segmented control from "Speed focus" to "Design detail focus" —
  instead of Photoshop's raw memory-% dial. It would set the thresholds used
  by PERF-002's conditional fidelity (and possibly halo size, mip cache
  budget, settle delay). Defaults = current behavior ("balanced").
- Hypothesis: implement AFTER PERF-002 proves out the thresholds; the setting
  is just exposing those constants. Follow the command-coverage rule for any
  user-facing control, and persist via the existing settings store.
- Acceptance: moving the control observably trades drag/pan fidelity against
  frame cost, survives relaunch, is fully keyboard/VoiceOver accessible.

### PERF-005 — Ruler pointer markers force a full canvas redraw per mouse move
- Type: perf
- Priority: P2
- Area: canvas · perf
- Status: open
- Repro/Detail: With rulers shown, `mouseMoved` sets `needsDisplay = true` to
  update the two accent pointer lines — a FULL scene render per mouse twitch.
  On the image-heavy doc (frames ~60–80ms) this reads as constant sluggishness
  even when nothing is being edited (visible in the 162c/d logs as repeated
  frame lines a few per second while idle).
- Hypothesis: the clean fix is a RETAINED last-frame snapshot: let the settle
  render also capture the scene (the machinery exists — capturePanZoomSnapshot),
  keep it while the transform + model are unchanged, and let ruler-marker /
  hover-only updates blit it + redraw rulers/chrome. This generalizes the pan
  blit into "idle repaints are blits," which also covers selection flashes.
  Cheaper stopgap: draw pointer markers in an NSView overlay above the canvas
  so marker moves never touch the canvas at all.
- Acceptance: with rulers on, waving the mouse over a heavy doc produces no
  full renders (Testing Mode shows no frame lines from pointer movement);
  markers still track exactly.

### FEAT-004 — Wider zoom-out range for "the wall is everything" workflows
- Type: feature
- Priority: P2
- Area: canvas
- Status: open
- Repro/Detail: Owner's process spreads branding, color tests, archives, and
  inspiration "miles" apart on the wall and zooms way out for the big picture.
  `AppState.minZoom` is 5% (a pre-original-perf-work constant) — potentially
  too tight for that. Owner suggestion: if a floor is still needed for
  performance, tie it to the Speed↔Detail performance setting.
- Hypothesis: lower `minZoom` to ~1% (0.01) and verify: extreme-zoom-out
  full renders scale with total node count (culling can't help when all is
  visible) but the pan/zoom blit covers gestures; check `rulerStep`,
  `pxSnap` UX (1 screen px = 100 doc px at 1%), and the zoom slider's log
  mapping still feel right. Only add a performance-mode-dependent floor if
  measured frames actually justify one.
- Acceptance: owner can zoom out far enough to see their whole wall on real
  documents without the app feeling broken; zoom slider/field/menu items all
  respect the new range.

## 🛠 Infrastructure

### INFRA-001 — One-command "approve → Roadmap → website" triage sync
- Type: feature (workflow/tooling)
- Priority: P2
- Area: infra
- Status: open
- Repro/Detail: When the owner approves a bug/idea (here, in GitHub Issues, or from
  the in-app reporter), it should be easy to PROMOTE it: move it out of the queue and
  onto the ROADMAP — and have the public roadmap on expdesign.app update automatically.
- Hypothesis / approach:
  1. **Canonical source:** keep a machine-readable roadmap the site can read —
     e.g. `docs/roadmap.json` (or a curated "public" subset) with `{id, title, area,
     status: planned|in-progress|shipped, blurb}`. ROADMAP.md stays the human plan;
     roadmap.json is the feed. (Or generate roadmap.json FROM tagged ROADMAP entries.)
  2. **Promote step:** an agent/skill "promote <ID>" that (a) moves the BACKLOG/issue
     item into ROADMAP.md as a phase/task, (b) appends/updates its entry in
     roadmap.json with `status`, (c) closes the GitHub issue with a "→ roadmap" label,
     (d) adds a ROADMAP Progress Log line.
  3. **Website sync:** if the site is static and reads `roadmap.json` from the repo,
     a push (or the site's build hook) republishes automatically; if the site fetches
     at runtime, point it at the raw file / a small endpoint. NEEDS: confirm the
     site's stack + how it currently sources roadmap/changelog content.
- Acceptance: approving an item + running one command updates ROADMAP.md, roadmap.json,
  and the GitHub issue in sync; the website reflects it on its next deploy with no
  hand-editing.

### INFRA-002 — Point the reporters at the real repo (small setup)
- Type: chore
- Priority: P1 (once the GitHub repo exists)
- Area: infra
- Status: open
- Detail: Set `FeedbackConfig.githubRepo = "owner/repo"` in `UI/Feedback.swift` and
  replace `OWNER/REPO` in `.github/ISSUE_TEMPLATE/config.yml`. Then the in-app "Send
  Feedback" opens a prefilled New Issue instead of the website fallback.

---

## Notes
- When an item ships, set `Status: done`, keep it here for one cycle for reference,
  then prune (or move a short line to ROADMAP's Progress Log).
- Big architectural features still get a real phase in ROADMAP.md; this list is for
  the smaller, pick-up-able queue.
