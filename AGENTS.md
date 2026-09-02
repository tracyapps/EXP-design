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
Public **v2.4/build 15** is released, notarized, and owner-verified.
Active development is **v2.5/build 16** (`MARKETING_VERSION 2.5`,
`CURRENT_PROJECT_VERSION 16`) across the app, thumbnail extension, and bundled
runtime configs. This is a development identity only; the public appcast and
immutable v2.4 artifacts remain 2.4/build 15.
The core native editor, component states/behavior contract, semantic Handoff
Package, agent-bridge spine, nested components, canvas pages, editable XD/Figma
import, unified Handoff/panel IA, editable rendered HTML/CSS import, CodePen
handoff/import, and static Storybook import are shipped.

`docs/RELEASE-CHECKLIST-v2.4.md` contains the notarization, immutable artifact,
GitHub, Sparkle, and website receipts. The only post-publication gate still open
is the preserved v2.3→v2.4 in-app Sparkle install/relaunch proof.

**v2.4 scope, set by the owner 2026-08-25:** ship BOTH the deferred vector/tool
queue and Sanaa, with **Sanaa as the headline**. Waves and gates live in
ROADMAP → v2.4 and `docs/RELEASE-CHECKLIST-v2.4.md` §A.
Wave A (BUG-049, BUG-050, BUG-051, BUG-052, FEAT-047, FEAT-027) is complete and
owner-verified.
Wave B is complete and owner-verified (FEAT-048 → 049 → 050; read
`docs/SANAA-PLAN.md` first).
Wave C's FEAT-025/028/029/030, BUG-048, BUG-053/054, and BUG-057 are owner-verified;
FEAT-030's proposed extra conversion commands were dropped as unnecessary by the
owner's 2026-09-02 acceptance. BUG-034 Stage 2 is
parked indefinitely at the owner's lowest priority with no planned retry.
Wave D is complete: FEAT-051/053/054/055 and the FEAT-050 amendment are built
and verified; FEAT-052 was explicitly deferred.
**Sequencing rule:** never start a document-mutating slice while another one
awaits owner verification.

FEAT-048 and FEAT-049 are owner-verified. FEAT-054 guidance v2.0.0 is integrated
and verified through packaged Codex, the public provider-neutral MCP transport,
and a 2026-09-02 real-mockup critique that caught every planted issue including
gradient contrast. FEAT-055
`get_design_facts` is built and owner-verified 2026-09-01 through its saved-file,
live public-route, packaged Codex, and artboard/selection behavior gates.

FEAT-052's optional in-canvas avatar is deferred from v2.4 with no target release.
The owner's first real critique pass on 2026-09-01 added BUG-058, FEAT-061, and
promoted FEAT-056 into v2.4. The FEAT-050 critique/guidance amendment is
owner-verified 2026-09-02 with rave reviews. FEAT-056's structured report/actions,
FEAT-061's reader experience, and BUG-058/059's overlap fixes are also owner-verified
2026-09-02. All v2.4 feature and source-verification gates are complete;
FEAT-050 is fully owner-signed-off, FEAT-051/053/054 are closed, the semantic
manifest is re-reviewed/rebaselined, release notes exist, and the homepage has
its Sanaa feature story. The signed archive, notarization, immutable zip, Sparkle
metadata, GitHub release, and production deployment are complete. The preserved
v2.3→v2.4 in-app updater proof remains.
Semantic component/state reconstruction is logged as a v2.4+ research candidate;
older Angular/AngularJS and open-shadow-root evidence are non-gating follow-ups.
Unrestricted URL import, repository build execution, full argTypes ingestion, and
code write-back remain explicitly deferred pending evidence.
Agent capability packs, Figma OAuth/Keychain/Variables, and agent write-back remain
explicit non-gating follow-ups.
See ROADMAP.md for the authoritative checklist and newest Progress Log entry.
The v2.5 scope is intentionally unselected. Resume at ROADMAP → v2.5's owner
scoping gate; do not silently promote candidate backlog items into the release.
