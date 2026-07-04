# EXP [design]

A native macOS design application built around an actual UX workflow — not
feature-count parity with Figma/XD. Guiding principle: **the tool should get
out of the way.** Built with Swift / SwiftUI (app chrome) + AppKit/Core
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

## Project structure
```
EXP [design]/
├── CLAUDE.md                 ← you are here
├── docs/
│   ├── ROADMAP.md
│   └── WORKING-AGREEMENT.md
├── EXP [design].xcodeproj
└── EXP/                       ← Swift source
    ├── EXPApp.swift           ← @main entry point (loads MainWindow)
    ├── Model/                 ← document data model (the foundation)
    ├── Canvas/                ← CanvasView.swift (AppKit-backed surface)
    └── UI/                    ← MainWindow.swift, panels, inspector
```

## Current status
Core editor is shipped and in tester hands (public download page at
expdesign.app/download). Phases 0–7, 8.5, 9, 11, and 13 are ✅ DONE; Phases 8
(color/gradients) and 10 (effects) are ✅ DONE with refinements planned; 9.5
(rich text) is IN PROGRESS with one open editor bug. Documents save as
**`.design`** (legacy `.exp` opens for migration). Recent work: canvas
performance (blit/mip caching), BUG/PERF triage in docs/BACKLOG.md, and the
tester download page. See ROADMAP.md for the authoritative checklist; phase
statuses there feed the public site via `website/scripts/sync-content.mjs`.
