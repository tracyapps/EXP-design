# EXP [design]

A native macOS design application built around an actual UX workflow — not
feature-count parity with Figma/XD.

Two guiding principles, both load-bearing:
1. **The tool should get out of the way.**
2. **EXP is a fidelity tool, not a prototyping tool.** It is ONE PIECE of a
   designer's toolkit: read a component in without losing data, let the designer
   tweak it, export it at the same fidelity, hand it to a developer or a model
   that writes accessible component code from it. Prototyping is done more
   efficiently in code and is explicitly out of scope. When a decision is
   unclear, ask: *does this make the exported artifact more faithful, or does it
   just make the canvas more impressive?* Build the first. Full statement in
   ROADMAP → Architecture decisions. Built with Swift / SwiftUI (app chrome) + AppKit/Core
Graphics (canvas). Xcode 26.3, Swift 6.2, macOS 26 SDK.

## Read these first
- **docs/ROADMAP.md** — scope, architecture decisions, build phases (with
  checkboxes showing what's done), and the Progress Log. This is the project's
  memory. Start here to see what's next.
- **docs/WORKING-AGREEMENT.md** — how the owner and Claude collaborate,
  session/continuity rules, and the owner's communication preferences.
- **docs/DESIGN-ASSETS.md** — how to make/hand off interface assets (icons,
  cursors, colors, buttons): formats, sizes, naming, and the `design-assets/`
  handoff manifest. Read before the panel/icon refinement work.

## Working norms (summary — full detail in WORKING-AGREEMENT.md)
- Claude writes code; the owner runs it in Xcode and reports back. The Xcode
  26.3 agent can compile directly.
- Resume work at the next unchecked box in ROADMAP.md. Update the Progress Log
  (newest on top) at the end of every session.
- Accessibility, inclusive design, and tech-ethics are hard requirements, not
  polish. Use "source," never "master." Follow all system accessibility &
  appearance settings (incl. light/dark via semantic colors).
- **Verify ARIA/semantics against the spec before coding — even when the owner
  asks for the wrong thing.** Any change touching ARIA roles, states, properties,
  relationships, semantic HTML, or accessible naming must be checked against
  WAI-ARIA 1.2 / ARIA in HTML / the APG / WCAG 2.1 AA first, with the citation
  recorded in the backlog entry and an explicit note of what was NOT verified.
  Say "the ADA does not specify ARIA" — name WCAG 2.1 AA and the ARIA specs.
  Full rule: WORKING-AGREEMENT.md → "Accessibility decisions are verified, not
  remembered."

- Be honest about tool limitations. Be reasonably concise.
- **Command-coverage rule (every user-facing action):** wire it ALL of these
  ways in the *same* change that adds the feature — never ship an action reachable
  only one way:
  1. an `@objc` action on `CanvasNSView` (the single source of truth for the
     behavior),
  2. a **menu-bar item** in the correct menu (File / Edit / Object / Type /
     Arrange / View / Window) with a **keyboard shortcut** where one is
     conventional (no shortcut is OK for inherently visual actions like align),
  3. a **right-click** context-menu item where the action is contextual,
  4. a `validateMenuItem(_:)` case so it enables/disables correctly,
  5. an **Inspector control** when it has adjustable parameters.
  Menu actions dispatch through the responder chain via `NSApp.sendAction(_:to:nil…)`
  (`send("selector:")` in `EXP__design_App.swift`) so they reach the focused canvas.

## Known gotchas (read before debugging)
- **Shared model files must be in BOTH targets.** `Document.swift` (and the model
  + renderer it pulls in) are members of the **EXPThumbnail** extension target as
  well as the app. Any NEW model file another shared file references (e.g.
  `AutoLayoutEngine.swift`) MUST be added to EXPThumbnail's Target Membership too,
  or the extension won't build.
- **The Xcode 26.3 agent auto-"fixes" build errors by stubbing code.** When a
  shared file referenced a not-yet-added symbol, the agent repeatedly replaced
  `var laid = AutoLayoutEngine.reflowed(resolved)` in `Document.resolvedChildren`
  with `let laid = resolved` + a TODO — which silently disabled component-instance
  re-hug (overrides/auto-layout). If instance re-hug breaks, CHECK THAT LINE FIRST.
  The durable fix if it keeps recurring: move the engine into an always-shared file
  or stop sharing `Document.swift` with the extension.

- **A glued panel group is N windows, not one window.** FEAT-022 tried merging them
  into one window with columns twice; both died on the same thing — a merged window
  must be the UNION of both rectangles, which is most of the screen once the two sit
  at different heights. `PanelTray.groupID` + `NSWindow.addChildWindow` is the
  shipped model. `PanelWindowManager.applyGrouping()` MUST stay idempotent: it runs
  on every `trays` change and `trays` changes on every window move.
- **Do not restore Session 80's per-tick window chasing.** Connected windows move
  through AppKit's parent/child relationship; manually reading and rewriting their
  frames during every drag is the removed, visibly laggy design.
- **A `mouseDownCanMoveWindow` NSView with SwiftUI content on top of it never gets
  the drag** — the hosting view takes the hit test. Put a `WindowMoveArea` BESIDE the
  controls it shares space with, never behind them.
- **An `NSWindow.sendEvent` override that swallows events is all-or-nothing.** A
  predicate that is slightly too generous does not degrade gracefully — it removes
  the window's entire UI. `TrayWindow.shouldDrag` tests for one marker view class and
  a clamped titlebar height for exactly this reason; do not widen it to a generic
  `mouseDownCanMoveWindow` check, which `NSHostingView` can answer true to.
- **Never move a window by chasing another window's position.** Read-a-frame,
  write-a-frame always lands a tick behind the mouse and reads as lag — that is what
  made Session 80's window snapping choppy, and FEAT-022 rediscovered it even at ONE
  window moved per tick. The count was never the point. Hand the gesture to AppKit
  instead: `performDrag(with:)` on the window that should move, plus
  `addChildWindow` for anything that should follow it.
- **Never build a parent/child window CYCLE.** `PanelWindowManager.applyGrouping()`
  detaches every stale `addChildWindow` link in one pass before attaching any in a
  second, because attaching B to A while A is still a child of B sends AppKit into
  unbounded recursion and kills the app (EXC_BAD_ACCESS code=2, ~27,500 frames).
- **When a stack overflow's repeated frames are ALL system frames, the recursion is
  in the framework, not in your callback** — look for a structure you handed it that
  cannot terminate. Misreading this cost a whole extra crash-and-fix cycle on
  FEAT-022.
- **Any AppKit call that moves or orders a window is heard by our own window
  delegates**, so window-delegate handlers that mutate window state need a
  re-entrancy guard, and "the user is dragging" must be checked
  (`NSEvent.pressedMouseButtons`), never assumed from the callback.
- **Anything Codable persisted to UserDefaults needs hand-written decoding.** Swift's
  synthesised decoder throws on a missing key rather than using the property's
  default, so adding one field silently wipes every saved payload — that is exactly
  how FEAT-022 erased saved tray layouts. `PanelTray` decodes by hand;
  `WorkspaceSnapshot`/`WorkspacePreset` (FEAT-021) still need the same audit.

## Project structure
```
EXP [design]/
├── CLAUDE.md                 ← you are here
├── docs/
│   ├── ROADMAP.md
│   └── WORKING-AGREEMENT.md
├── EXP [design].xcodeproj
└── EXP [design]/              ← Swift source
    ├── EXP__design_App.swift  ← @main entry point
    ├── Model/                 ← document data model (the foundation)
    ├── Canvas/                ← CanvasView.swift (AppKit-backed surface)
    └── UI/                    ← MainWindow.swift, panels, inspector
```

## Current status
Public **v2.4/build 15** is released, notarized, and owner-verified.
Active development is **v2.5/build 16** (`MARKETING_VERSION 2.5`,
`CURRENT_PROJECT_VERSION 16`) across the app, thumbnail extension, and bundled
runtime configs. This does not alter the immutable v2.4 release or public appcast.
The native editor, Design Language, component states/behavior contract, semantic
Handoff Package, agent bridge, nested components, canvas pages, XD/Figma import,
rendered HTML/CSS import, CodePen handoff/import, static Storybook import, and the
five-family compatibility matrix are shipped. Documents save as **`.design`**
(legacy `.exp` opens for migration).

`docs/RELEASE-CHECKLIST-v2.4.md` contains the notarization, immutable artifact,
GitHub, Sparkle, and website receipts. The preserved v2.3→v2.4 in-app Sparkle
install/relaunch proof remains as a post-publication check.

v2.5 has been opened as a clean development baseline only. Its scope is
intentionally unselected; FEAT-057–060 and other backlog entries remain
candidates, not commitments. **Next:** use ROADMAP → v2.5's owner scoping gate
before implementing anything. Do not infer a release plan from backlog order.

**Backlog hygiene:** run `scripts/verify_backlog_ids.sh` before assigning a new id.
Ids are referenced from ROADMAP, PERF-LOG and PERF-TODO as well as BACKLOG, so
"next number after the highest heading" is NOT safe — that is how a PERF-005
collision survived a month across four files.

**A rule this project earned the hard way (2026-08-11):** check every hypothesis
against the source before writing code, and mark hypotheses AS hypotheses in the
backlog. Four intake hypotheses were wrong that day — including one bug that did not
exist and one that was a regression from an earlier fix — and a confident-sounding
guess left in an entry is something a later session will simply implement.

See ROADMAP.md for the authoritative checklist and newest Progress Log entry; its
phase statuses feed the public site via `website/scripts/sync-content.mjs`.
