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
- Status: open
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
- Status: open
- Repro/Detail: Recent-colors strip and a saved-swatches area in the color popover;
  named palettes that live ON the document (so they travel with the file) AND can be
  exported/imported to share between documents. Bonus: palette generation (harmonies
  / shades from a base color).
- Hypothesis: add a `palettes: [Palette]` (+ `recentColors`) to the document model
  (backward-compatible decode); surface in `ColorPopover`; export/import as a small
  JSON. Generation can reuse `ColorMath` (OKLCH) for perceptually-even ramps.
- Acceptance: pick from recents/saved; save a swatch; export a palette from doc A and
  import into doc B; palettes persist in the `.exp` file.

### FEAT-002 — Color-mode-specific picker behavior
- Type: feature
- Priority: P3
- Area: color
- Status: open
- Repro/Detail: The color picker adapts to the working color mode (e.g. sRGB vs
  Display-P3 vs a future CMYK/print mode) — different sliders/gamut/warnings per mode.
- Hypothesis: a `colorMode` setting; `ColorMath` already does space conversions, so
  extend the popover's format/gamut UI per mode. Low priority, high delight.
- Acceptance: switching mode changes the picker's available spaces + gamut clamping.

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

---

## ⚡ Performance

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
- Status: open
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
- Status: open
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
- Status: open
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
