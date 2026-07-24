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
Public **v2.0.1/build 11** is released. Development is on **v2.1/build 12**.
The core native editor, component states/behavior contract, semantic Handoff
Package, agent-bridge spine, and the v2.0.1 stabilization fixes are shipped.

Current v2.1 work is **Chunk I — nested components + semantic containment**.
Completed and owner-verified on 2026-07-24: nested component placement from all
surfaces, cycle-safe source dependencies, separate instance/source naming,
recursive Layers disclosure, per-level component-state controls with stable
nested instance paths, state-local outline color/alpha/width/position, group
background outline position, role-aware Relationships placement, and the
default-width Components/Layers density pass. Debug app + Quick Look/helper,
focused graph/state checks, and semantic handoff checks pass.

**Next:** finish Chunk I closure—dependent-source deletion choices and the
remaining nested override/public-prop/layout/detach/export/Quick Look/semantic
containment acceptance matrix—then begin the XD/Figma shared importer pipeline.
See ROADMAP.md for the authoritative checklist and newest Progress Log entry.
