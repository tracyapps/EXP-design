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

The **v2.2 primary scope is Chunk E — code/component import**. E0/E1 rendered
HTML/CSS, E2 local/static Storybook, and the E2c modern compatibility matrix are
complete and owner-accepted. The measured matrix covers GitLab Vue + webpack,
CZI React + Vite, Dell modern Angular + webpack, Brave Leo Svelte + Vite, and
Kintone light-DOM Web Components + Vite. The same framework-neutral rendered-DOM
seam preserves editable paint/text/SVG geometry, accessibility semantics,
Storybook story/args receipts, and explicit fidelity limits across all five.

**Next:** finish the v2.2 release audit and prepare build 13 for broader testing
and release. FEAT-008 is explicitly deferred from build 13 and is the first-priority
v2.3 discovery/design item, pending the owner's font-filter mockups and testing.
Semantic component/state reconstruction is logged as a v2.4+ research candidate;
older Angular/AngularJS and open-shadow-root evidence are non-gating follow-ups.
Unrestricted URL import, repository build execution, full argTypes ingestion, and
code write-back remain explicitly deferred pending evidence.
Agent capability packs, Figma OAuth/Keychain/Variables, and agent write-back remain
explicit non-gating follow-ups.
See ROADMAP.md for the authoritative checklist and newest Progress Log entry.
