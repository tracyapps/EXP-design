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
Public **v2.2/build 13** is released. Development is on **v2.3/build 14**.
The core native editor, component states/behavior contract, semantic Handoff
Package, agent-bridge spine, nested components, canvas pages, editable XD/Figma
import, unified Handoff/panel IA, editable rendered HTML/CSS import, CodePen
handoff/import, and static Storybook import are shipped.

The **v2.3 opening priority is FEAT-008 font-picker discovery**. Review the
owner's font-filter mockups and test the information architecture before coding.
The candidate set is document-scoped Fonts Used, persisted Recent Fonts,
type-to-jump, and search/filtering over one list; none is automatically committed
to implementation without evidence. Set the keyboard, VoiceOver, persistence,
and empty-state contract first, then build the smallest coherent result.

**Next:** begin with the owner's FEAT-008 mockup/research pass when v2.3 work
resumes. Do not start implementation before that evidence is available.
Semantic component/state reconstruction is logged as a v2.4+ research candidate;
older Angular/AngularJS and open-shadow-root evidence are non-gating follow-ups.
Unrestricted URL import, repository build execution, full argTypes ingestion, and
code write-back remain explicitly deferred pending evidence.
Agent capability packs, Figma OAuth/Keychain/Variables, and agent write-back remain
explicit non-gating follow-ups.
See ROADMAP.md for the authoritative checklist and newest Progress Log entry.
