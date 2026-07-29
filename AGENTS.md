# EXP [design]

A native macOS design application built around an actual UX workflow — not
feature-count parity with Figma/XD. Guiding principle: **the tool should get
out of the way.** Built with Swift / SwiftUI (app chrome) + AppKit/Core
Graphics (canvas). Xcode 26.3, Swift 6.2, macOS 26 SDK.

## Read these first
- **docs/ROADMAP.md** — scope, architecture decisions, build phases (with
  checkboxes showing what's done), and the Progress Log. This is the project's
  memory. Start here to see what's next.
- **docs/WORKING-AGREEMENT.md** — how the owner and Codex collaborate,
  session/continuity rules, and the owner's communication preferences.

## Working norms (summary — full detail in WORKING-AGREEMENT.md)
- Codex writes code; the owner runs it in Xcode and reports back. The Xcode
  26.3 agent can compile directly.
- Resume work at the next unchecked box in ROADMAP.md. Update the Progress Log
  (newest on top) at the end of every session.
- Accessibility, inclusive design, and tech-ethics are hard requirements, not
  polish. Use "source," never "master." Follow all system accessibility &
  appearance settings (incl. light/dark via semantic colors).
- Be honest about tool limitations. Be reasonably concise.

## Project structure
```
EXP [design]/
├── AGENTS.md                 ← you are here
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
Public **v2.1/build 12** is released. Development is on **v2.2/build 13**.
The core native editor, component states/behavior contract, semantic Handoff
Package, agent-bridge spine, nested components, canvas pages, editable XD/Figma
import, and unified Handoff/panel IA are shipped.

The **v2.2 primary scope is Chunk E — code/component import**: rendered HTML/CSS
to editable EXP nodes first, then Storybook on the proven mapping. Start with the
bounded E0 contract/technical spike in ROADMAP.md; reuse `InteropCodec`, reverse
the semantic HTML mapping where valid, and report every fidelity limit honestly.

**Next:** E0—document the supported rendered-HTML boundary and prove one local
HTML/CSS fixture through the browser-to-import pipeline. Agent capability packs,
Figma OAuth/Keychain/Variables, and agent write-back remain explicit non-gating
follow-ups.
See ROADMAP.md for the authoritative checklist and newest Progress Log entry.
