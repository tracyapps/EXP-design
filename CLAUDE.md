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
Public **v2.1/build 12** is released; local development is
**v2.2/build 13**. The native editor, Design Language, component
states/behavior contract, semantic Handoff Package, agent-bridge spine, and
v2.1 nested components, canvas pages, XD/Figma import, and Handoff/panel IA are
shipped. Documents save as **`.design`** (legacy `.exp` opens for migration).

The **v2.2 primary scope is Chunk E — code/component import**. E0/E1 local HTML,
E2 static Storybook import, and CodePen export/ZIP import are working. E2c's first
measured framework/generation matrix now covers two real published artifacts:
GitLab UI on Storybook 7.6.24 / Vue + webpack 5, and CZI Science Design System on
Storybook 10.5.2 / React + Vite. The second corpus passes eight representative
stories after generation-aware runtime-phase, zero-box-root, and project-metadata
compatibility fixes. Its visual-acceptance regression now also covers Phone + Web
1280 viewport minimums, the browser's opaque canvas backdrop, generated pseudo
content, and native text overflow. A focused ContentCard/InputToggle Tablet gate
also covers flex pseudo placement, CSS outline mapping, and multiline fallback
and control line-box layout. Fixed px/em line-height keeps its source value while
centering CSS leading at paint time; CSS `normal` remains font-native Auto, and
percentage corner radii preserve the toggle's circular thumb. Oversized uniform
radii now use the same CSS normalization in live rectangles and converted paths.
Authored fixed-width viewport overflow is retained
and reported rather than silently made responsive; see
`docs/STORYBOOK-COMPATIBILITY-MATRIX.md`.

A third real corpus—Dell Design System Angular v3.0.1, Angular 17 + webpack 5 /
Storybook 8.6.18—passes the same static-artifact seam with 12/12 Phone + Web
artboards, 52 painted text layers, 32 roles, 32 ARIA attributes, and bounded
initial args. Owner review added framework-neutral fixes for fully overflow-clipped
subtrees, transformed pseudo-element bounds, root-level static assets, and editable
data-SVG CSS masks (including all six accordion carets); no
Angular-specific importer branch was added.

**Next:** owner re-imports the corrected six-story Dell Angular corpus at Phone +
Web 1280. If approved, add a real published Svelte + Vite artifact, then Web Components
and non-gating older Angular/AngularJS evidence. Unrestricted URL import,
repository build execution, full argTypes
ingestion, and code write-back remain deferred.
Agent capability packs, Figma OAuth/Keychain/Variables, and agent write-back
remain non-gating. See ROADMAP.md for the authoritative checklist and newest
Progress Log entry; its phase statuses feed the public site via
`website/scripts/sync-content.mjs`.
