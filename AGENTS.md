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
Public **v2.3/build 14** is released and owner-verified.
Active development is **v2.4/build 15** (`MARKETING_VERSION 2.4`,
`CURRENT_PROJECT_VERSION 15`) across the app and thumbnail-extension configs.
The core native editor, component states/behavior contract, semantic Handoff
Package, agent-bridge spine, nested components, canvas pages, editable XD/Figma
import, unified Handoff/panel IA, editable rendered HTML/CSS import, CodePen
handoff/import, and static Storybook import are shipped.

`docs/RELEASE-CHECKLIST-v2.3.md` contains the completed notarization, GitHub,
Sparkle, website, and v2.2→v2.3 update receipts. The remaining lower-priority
Wave 7 vector/effect queue is explicitly deferred to v2.4.

**v2.4 scope, set by the owner 2026-08-25:** ship BOTH the deferred vector/tool
queue and Sanaa, with **Sanaa as the headline**. Waves and gates live in
ROADMAP → v2.4 and `docs/RELEASE-CHECKLIST-v2.4.md` §A.
Wave A (BUG-049, BUG-050, BUG-051, BUG-052, FEAT-047, FEAT-027) is committed at
`a803df0` and awaiting the owner's Xcode verification pass.
Wave B is Sanaa's core (FEAT-048 → 049 → 050; read `docs/SANAA-PLAN.md` first).
Wave C is the vector queue (FEAT-025 leads, then 029, 028, 031, 030, BUG-048,
BUG-034 Stage 2). Wave D is Sanaa's companion chunks (FEAT-051/052/053).
**Sequencing rule:** never start a document-mutating slice while another one
awaits owner verification.
Semantic component/state reconstruction is logged as a v2.4+ research candidate;
older Angular/AngularJS and open-shadow-root evidence are non-gating follow-ups.
Unrestricted URL import, repository build execution, full argTypes ingestion, and
code write-back remain explicitly deferred pending evidence.
Agent capability packs, Figma OAuth/Keychain/Variables, and agent write-back remain
explicit non-gating follow-ups.
See ROADMAP.md for the authoritative checklist and newest Progress Log entry.
