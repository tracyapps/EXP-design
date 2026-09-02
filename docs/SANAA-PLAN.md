# Sanaa — an optional design assistant on the EXP canvas

*Proposal + chunked implementation plan. Drafted 2026-08-25 from owner direction;
researched against pen.dev and the shipped EXP v2.3 agent bridge.*

**Status: FEAT-048 COMPLETE AND OWNER-VERIFIED. FEAT-049
CANVAS-ONLY RUNTIME ROUTE + APPLIED-BATCH PRESENCE BUILT; OWNER GATES OPEN.** Backlog ids
FEAT-048 … FEAT-053 (assigned via `scripts/verify_backlog_ids.sh` on 2026-08-25).
After repairing two verifier parsing defects and clarifying the switch UI, the
owner reran the full automated matrix successfully on 2026-08-26, then confirmed
the manual MCP approval, per-document consent, applied change, and named one-step
undo/redo path. The final owner pass confirmed a real-client three-artboard batch,
save/reopen, Quick Look, PNG/SVG/Handoff HTML fidelity, appearance, and VoiceOver,
closing FEAT-048. The "no stacked document-mutating slices" rule applies. On
2026-08-26 the owner approved the heavier seamless-chat
direction: Sanaa's panel will send prompts and stream replies in place through a
provider-neutral local runtime. The first Codex app-server proof passed account,
streaming, interrupt, process restart, thread resume, context retention, and
cleanup. The packaged signed helper/client seam and dedicated conditional panel
now provide real Send/stream/Stop/reconnect plus an in-memory transcript. The
isolated EXP-only tool route and batch receipts/highlights/announcements are built
and automated evidence passes; owner end-to-end canvas/AX/Reduce Motion checks,
distribution signing, and the independently gated Claude adapter remain.

---

## 1. What Sanaa is (and is not)

Sanaa (Swahili: *work of art*) is EXP's optional design assistant: a friendly
presence on the canvas that can **look at what's there and draw** — variations,
completions, tedious repetitive work — like pair programming, but for designers.

Hard boundaries, set by the owner on 2026-08-25:

- **Very optional.** Every part of Sanaa is OFF by default behind clear switches
  (§4). A designer who never enables it never sees it. EXP does not become
  "agent central"; many designers are actively resisting forced AI features,
  and EXP respects that.
- **No LLM or vendor API key inside EXP.** The designer's supported local agent
  host still does the thinking. The approved runtime direction adds a local,
  provider-neutral conversation client so EXP can send a prompt and receive the
  host's streamed reply; it does not embed a model or make EXP silently contact a
  provider. The existing MCP bridge remains the only document-tool boundary and
  every write still goes through EXP's consent/undo funnel.
- **Fidelity test still governs.** Sanaa's output is ordinary document content —
  artboards and nodes that round-trip through every exporter. Nothing Sanaa
  does exists only while EXP is running it.

## 2. What we learned from pen.dev

pen.dev ("Pencil") *looks* agent-central, but its canvas app contains **no
built-in LLM and no API keys**. It is free; you "plug in your existing AI
subscription" — i.e. your own coding agent (Claude Code, Cursor, Codex)
connects over MCP and drives the canvas through tools. The wow-moments the
owner liked — "look at the canvas, draw something similar / variations /
complete this" — are the external agent reading canvas state and writing nodes
back while the app renders the edits live (multiple agents show as moving
cursors). The `.pen` file is plain JSON, which is what makes the design
machine-legible.

**EXP already has this skeleton.** F1/F2 shipped a local MCP server (Unix
socket + bundled `exp-mcp` stdio helper) with six read-only tools, owner-
verified with Claude Code connected. `.design` is already pretty-printed JSON.
The roadmap already reserves **F3 — "separately consented, undo-safe
write-back (v2.3+)"**. Sanaa = F3 + a presence layer + onboarding, not a new
AI subsystem.

Answering the owner's two criteria for where the "brain" lives:

1. **Easiest for non-technical people:** an embedded bring-your-own-API-key
   chat is *harder* for non-technical users (create a developer account, manage
   billing, paste secret keys) and reverses a recorded architecture decision.
   The reach-in model's real friction is one-time agent hookup — which FEAT-051
   attacks directly with a guided, copy-first setup flow that never handles
   provider credentials or pretends external canvas access is in-app chat.
   Automatic detection and a packaged Claude Desktop extension remain unshipped
   transport experiments. pen.dev made the same architectural call.
2. **Physically draws on the canvas like pen.dev:** the drawing IS write-back.
   Edits arrive as tool calls; EXP applies them through the normal undo funnel
   and animates them (FEAT-049). Identical mechanism to pen.dev's desktop app.

**The current seam, and the approved replacement:** the dedicated Sanaa panel now
sends prompts and streams replies in place through the signed-in local Codex
runtime; copy remains an honest fallback when that runtime is unavailable. On
2026-08-26 the owner chose this heavier path over clipboard-only chat. MCP
sampling is not the foundation: the 2026-07-28 MCP specification deprecates it,
and Codex does not expose it as a supported client contract. A provider-neutral
local Sanaa Runtime will use each supported host's explicit conversation API.
Primary references: [MCP sampling 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/client/sampling)
and the [Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md).

## 3. Placement rules (owner decision, 2026-08-25)

Where Sanaa's drawings land depends on the ask, and the **designer chooses**:

| Ask | Placement |
|---|---|
| "Complete / finish this" | Ask the designer first: **directly on that artboard** (in-place) or **on a duplicate placed next to it**. |
| "Variations" | Always **new artboards**; designer chooses **same page** or a **new page** (e.g. "Sanaa — Homepage variations"). |
| Repetitive/tedious work on existing content | In-place, but only with the in-place consent (§4) and always one named undo step. |

Enforced in three layers so no single layer has to be perfect:
- The **Ask Sanaa dialogs** (FEAT-050) collect the choice before composing the prompt.
- The **`apply_edits` tool** (FEAT-048) requires an explicit `placement` on ops
  that touch existing artboards, and rejects in-place ops unless in-place
  consent is active.
- The **capability pack** (FEAT-053) teaches agents to ask when placement is unspecified.

## 4. The switches (all OFF by default)

1. **Settings ▸ App ▸ Sanaa ▸ "Allow local agent access"** — the existing
   read-only bridge switch, moved out of Handoff so connection setup, live status,
   connected clients, and permissions have one roomy home. Handoff retains a
   compact status and direct Settings link.
2. **Settings ▸ App ▸ Sanaa ▸ "Enable Sanaa"** — master switch; when off,
   nothing Sanaa-related appears anywhere in the UI (no menu items, no panel
   section, no avatar). This is the "no one will feel like this is being
   thrown at them" switch. New in FEAT-048.
3. **Settings ▸ App ▸ Sanaa ▸ "Allow Sanaa to draw"** — write access, separate
   from read. New in FEAT-048.
4. **Per-document first-draw consent** — the first write to a given document in
   a session shows a sheet: *"<client> wants to draw in '<doc>'. Allow for this
   session / Not now."* New in FEAT-048.
5. **Settings ▸ App ▸ Sanaa ▸ "Show Sanaa's avatar"** — the character is
   separately optional (FEAT-052); the feature works fully without it.

Menu items and panel sections added by Sanaa chunks are only *installed* when
"Enable Sanaa" is on, and get `validateMenuItem` cases like every other command.

## 5. Architecture at a glance

```
Sanaa panel ── prompt / Stop / streamed reply
      │
local Sanaa Runtime (provider-neutral event contract; no model or API key)
      ├─ Codex adapter ── codex app-server (first supported host; spike proven)
      └─ Claude adapter ─ Claude streaming host contract (separate later gate)
                              │
                              │ EXP MCP tool calls
                              ▼
   exp-mcp helper ── current-user Unix socket (0600, unchanged)
                              │
   AgentMCPRouter ── read tools (6, shipped)
                 └─ apply_edits (FEAT-048, gated on §4 switches)
                           │ validate → consent → one setModel call
                           ▼
   SanaaActivityController (FEAT-049) → transcript receipts, highlights,
                                        VoiceOver announcements
```

Design consequences worth naming:

- **One transactional write tool, not many.** `apply_edits` takes an array of
  typed ops and applies them atomically through ONE `setModel` call. That gives
  one undo step per batch for free, keeps validation in one place, and avoids
  cross-call undo-grouping (NSUndoManager grouping across independent socket
  messages is fragile).
- **No model changes required for v1.** "Sanaa's desk" is an ordinary page
  created by convention, not a new model field — so no EXPThumbnail
  target-membership risk and no `.design` schema change. Keep it that way
  unless a chunk proves otherwise.
- **Undo honesty.** NSUndoManager cannot selectively revert a non-top step.
  "Undo" of Sanaa's batch is plain ⌘Z while it's the newest step. The activity
  feed offers **"Select Sanaa's changes"** (selects the affected node ids) for
  anything older — never promise selective rollback in UI copy.
- **Frontmost-document scope** stays, matching the read tools.
- **Canvas-only by default.** A Sanaa-owned conversation must not silently
  inherit a host's general shell/filesystem permissions. The production adapter
  launches a tightly instructed, restricted thread and exposes only the EXP MCP
  tools needed for the session. Any host request outside that allowlist is shown
  and refused; there is no hidden escalation path.

### Runtime transport gate — Codex app-server (approved 2026-08-26)

The bounded developer probe is `scripts/sanaa_runtime_probe.swift`. It starts
the installed `codex app-server` over stdio in an empty temporary directory with
read-only sandboxing, `approvalPolicy=never`, and text-only instructions. It does
not connect to EXP, open a document, or exercise `apply_edits`.

Fresh local evidence with Codex CLI 0.147.0: **7/7 passed** — initialize; signed-in
account present without printing identity; thread start; streamed
`item/agentMessage/delta`; `turn/interrupt` after the first delta; app-server
process restart plus `thread/resume`; earlier context retained; exact probe thread
deleted afterward. This proves the host transport, not production packaging.

Runtime and canvas transport gates:

1. [x] Extract the client into a bundled, separately signed Sanaa Runtime helper
   with a normalized event contract (`userMessage`, `assistantDelta`, `toolRequest`,
   `toolResult`, `approvalRequired`, `completed`, `failed`).
2. [x] Authenticated EXP↔helper IPC and the signed sandbox path pass in Debug.
   The distribution archive/notarization receipt remains a release gate.
3. [ ] Start a Sanaa-owned Codex thread with only the EXP MCP server available; prove
   read tool → streamed reply → consented `apply_edits` → receipt end to end. The
   isolated allowlist and receipt/highlight/announcement implementation are built.
   After the first owner pass exposed `auto` silently rejecting the second read,
   the server now uses `approve` for its exact seven-tool allowlist; packaged and
   signed-sandboxed `list_artboards → get_artboard` regressions pass without a host
   prompt. The owner live write/receipt pass is still required.
4. [x] Packaged tests pass Stop, missing/untrusted host, process loss, resume, context
   retention, exact cleanup, and app/runtime shutdown. Owner UI passes for signed-out,
   reconnect/Stop, retained failed draft, and stale-thread recovery remain separate.
5. [ ] Gate the Claude adapter independently; do not imply host parity from Codex's
   passing result.
6. [x] Treat Codex app-server as a versioned adapter boundary: the local CLI still
   labels it experimental, so negotiate capabilities, fail clearly on an
   unsupported schema, and never let protocol drift become an EXP crash.

## 6. The chunks

Recommended order: **048 → 049 → 050**, then 051/052/053 in any order.
Estimates are working sessions, using this project's usual session size.

---

### FEAT-048 — `apply_edits`: consented, undo-safe write-back (the F3 spine)

*~2–3 sessions. Blocked until the current v2.4 slice passes owner verification.*

**Goal.** The bridge accepts one new tool, `apply_edits`, gated behind the §4
switches, which mutates the frontmost document atomically and undoably.

**Files.** `Export/AgentBridge.swift` (tool def + routing + validation),
`Model/ExpDocument.swift` (nothing new expected — reuse `setModel`),
`UI/SettingsWindow.swift` (new Sanaa settings group + `AppPreferences` keys),
`UI/HandoffPanel.swift` (write status: extend the READ ONLY capsule to show
CAN DRAW when write consent is active). No new files required; if the op
structs get large, a new app-target-only `Export/SanaaEdits.swift` is fine
(it is NOT shared with EXPThumbnail — verify it never gets referenced from a
shared file).

**Op set (v1).**

```jsonc
{ "name": "apply_edits", "arguments": {
    "summary": "3 variations of the pricing card",   // becomes the undo action name
    "ops": [
      { "op": "createPage",      "name": "Sanaa — Pricing variations" },
      { "op": "createArtboard",  "name": "Variation A", "frame": {…},
        "placement": { "kind": "newPage" | "samePage", "afterArtboardId": "…" } },
      { "op": "duplicateArtboard", "id": "…", "placement": { "kind": "besideOriginal" } },
      { "op": "insertNodes",     "artboardId": "…", "nodes": [ /* verbatim design.json fragments */ ] },
      { "op": "replaceNode",     "id": "…", "node": { … } },        // in-place: consent-gated
      { "op": "removeNodes",     "ids": ["…"] }                      // in-place: consent-gated
    ] } }
```

- Node fragments are validated by decoding through the real `Codable` model
  (`Node`, `Artboard`) — never hand-parsed. A fragment that doesn't decode
  fails the WHOLE batch with a precise error; nothing partial is applied.
- `replaceNode` / `removeNodes` / `insertNodes`-into-an-artboard-Sanaa-didn't-
  create are "in-place" ops → rejected unless the per-document consent (§4.4)
  is active. `createPage` / `createArtboard` / `duplicateArtboard` +
  `insertNodes` into artboards created *in the same batch* are always allowed
  once "Allow Sanaa to draw" is on.
- New ids are generated by EXP and returned in the tool result
  (`{"created": {"artboards": [...], "nodes": [...]}}`) so the agent can keep
  referencing its own work.
- Caps: ≤ 200 ops per call, existing 4 MB read-buffer framing already bounds
  payloads; reject with a clear message beyond caps.
- Apply on MainActor (the router already hops there), build the new `Document`
  value, then ONE `setModel(_, undoManager:, actionName: "Sanaa: \(summary)")`.
- The undo action name means Edit ▸ Undo reads "Undo Sanaa: 3 variations…" —
  free, honest reversibility.

**Settings work.** New `AppPreferences` keys (`exp.sanaa.enabled`,
`exp.sanaa.writeEnabled`, later `exp.sanaa.avatar`). These are plain `Bool`
defaults — do NOT introduce a persisted `Codable` settings struct (that is the
FEAT-022 synthesized-decoder trap; if a struct ever becomes necessary, it gets
hand-written decoding like `PanelTray`).

**Explicitly NOT in this chunk:** any UI beyond the settings group and status
capsule; prompts; avatar; activity feed (ship 049 before publicizing).

**Testing (any agent can run these).**

1. *Unit-ish socket test, no Xcode UI needed.* With EXP running, bridge
   enabled, and both Sanaa switches on, pipe JSON-RPC at the socket:

   ```bash
   SOCK=~/Library/Containers/tapps.EXP--design-/Data/Library/Application\ Support/EXP/agent.sock
   printf '%s\n' \
     '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"sanaa-test","version":"0"}}}' \
     '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"apply_edits","arguments":{"summary":"test artboard","ops":[{"op":"createArtboard","name":"Sanaa test","frame":{"x":0,"y":0,"width":320,"height":200},"placement":{"kind":"samePage"}}]}}}' \
     | nc -U "$SOCK"
   ```

   Assert: result lists one created artboard id; the artboard exists; ⌘Z
   removes it in one step named "Sanaa: test artboard".
2. *Gate matrix.* Repeat with (a) `exp.sanaa.enabled` off, (b) write toggle
   off, (c) consent sheet declined, (d) an in-place `replaceNode` without
   consent, (e) a fragment with a bogus field, (f) 201 ops. Every one must
   fail whole with a distinct, accurate error and NO document change.
3. *Real client.* Connect Claude Code (existing setup snippet), ask it to
   "add a 3-artboard mood row on a new page using apply_edits", verify undo,
   save, reopen, thumbnail, and SVG/PNG/Handoff export of Sanaa's artboards
   are indistinguishable from hand-drawn content (the fidelity test).
4. *Owner pass.* Consent sheet copy, keyboard access, VoiceOver on the new
   settings group, light/dark, and that with everything off EXP shows no
   trace of Sanaa.

---

### FEAT-049 — Runtime + presence: real conversation, panel, activity

*~3–5 sessions. Depends on FEAT-048. Start with the non-document-mutating helper
and text stream; do not exercise apply_edits until FEAT-048's manual gate closes.*

**Goal.** The designer types in EXP, sees Sanaa's response stream in the same
panel, can Stop/reconnect, and sees/reviews every approved canvas action. This is
what turns the proven transport and write spine into one coherent experience.

**Files (expected; helper packaging is a gate, not pre-decided).** A new bundled
runtime helper/XPC target with a Codex adapter; app-side
`UI/SanaaRuntimeClient.swift`, `UI/SanaaActivityController.swift`
(`@MainActor @Observable`, app target only), and `UI/SanaaPanel.swift`;
`UI/PanelDock.swift` /
`UI/PanelHub.swift` / `Model/AppState.swift` (conditional panel availability and
layout preservation); `Canvas/CanvasView.swift` (highlight overlay);
`EXP__design_App.swift` (menu items); `Export/AgentBridge.swift` (one call into
the controller after a successful batch, plus an optional non-mutating status
message tool).

**Behavior.**

- Runtime events are provider-neutral: user message, assistant delta, tool
  request/result, approval required, completion, interruption, and failure. The
  SwiftUI panel never parses Codex-specific JSON.
- Codex is the first supported adapter. It reuses an existing signed-in account,
  starts a restricted Sanaa-owned thread, streams deltas, interrupts the exact
  active turn, and resumes by thread id after a helper restart. A missing binary,
  unsupported protocol, signed-out account, or lost process produces a clear
  recoverable state while keeping the composer's text.
- Settings is the one connection surface: it reports the conversation runtime,
  account/plan when supplied, live Codex rate-limit windows and token activity
  when the provider exposes them, the canvas bridge state, and every named MCP
  client currently connected. The Handoff and Sanaa panels jump directly there.
  Account details use Codex app-server's documented `account/read`,
  `account/rateLimits/read`, and `account/usage/read` surfaces; missing optional
  fields stay absent rather than becoming estimated usage.
- The composer owns a small agent picker that appears only when more than one
  **send-capable runtime adapter** is available. Generic MCP canvas clients are
  never listed there because EXP has no truthful outbound prompt channel to them.
- The runtime/helper has no document mutation authority. EXP MCP tool calls come
  back through the existing 0600 socket and the FEAT-048 switches/consent/undo
  path; the helper cannot bypass it.
- Sanaa gets her own first-class `PanelID`, not a subsection of Handoff. The
  panel is available only while the master Sanaa switch is on. With Sanaa off,
  it is absent from the Window menu, dock rendering, and floating trays; hiding
  it must not delete its saved dock/tray placement. Turning Sanaa back on restores
  the designer's prior placement. In single-window mode, first enable may reveal
  it once in the right dock; in multi-window mode, never auto-open a floating
  window, but make it available to add like every other panel. Once enabled, it
  may remain visible while Sanaa is idle or no agent is connected, with an honest
  empty/status state.
- The panel is a session transcript, not just a newest-first feed: chronological
  designer prompts, agent-posted progress/replies, and applied-batch receipts in
  one scrollable history, with a composer anchored at the bottom. Long responses
  scroll inside the panel; do not grow the dock or chase window size. Auto-scroll
  only when the designer is already at the bottom, otherwise show a new-update
  affordance so reading older text is not interrupted.
- Every applied batch records: client name, timestamp, summary, affected ids,
  page. **In-memory, session-scoped** — deliberately NOT persisted (avoids the
  UserDefaults/Codable trap and keeps documents clean). Each receipt offers
  **Select Sanaa's changes** and **Go there** (reuse Reveal/zoom-to-fit paths).
- The supported runtime provides the authoritative streamed reply. A separately
  connected generic MCP client may explicitly post bounded progress/final text
  through a non-mutating bridge tool, but EXP never claims to capture arbitrary
  output from unsupported hosts.
- Canvas highlight: affected nodes pulse once (≈1s fade) on apply. Honor
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` — reduced motion
  gets a static 2s outline, no pulse. Draw in the existing canvas overlay
  pass — do NOT add windows, and never chase window positions (see CLAUDE.md).
- VoiceOver: post an `.announcement` ("Sanaa added 3 artboards on page
  Pricing") per batch. Verify exact AX API usage against Apple documentation
  at implementation time — accessibility decisions are verified, not
  remembered.
- Command coverage for the two user-facing actions (Select Sanaa's changes /
  Go there): `@objc` on `CanvasNSView`, menu-bar items (Object or View menu —
  decide with owner), right-click where contextual, `validateMenuItem`, all
  dispatched via `sendCanvasAction` (never raw `NSApp.sendAction(to: nil)`).

**Prompt boundary.** The packaged Codex adapter now supplies real **Send** with a
streamed reply, Stop, reconnect, and visible failures in this panel. **Copy prompt
for my agent** remains the honest fallback when the supported runtime is missing
or unavailable, not the primary flow. Canvas tools now route only through EXP's
isolated MCP allowlist; the existing master/draw switches, per-document consent,
validation, and named one-step Undo still own every write. The standard multi-window workspace already
provides a floating Sanaa panel; a separate one-off **Pop Out Sanaa** command in
single-window mode is deferred until actual use shows it is needed.

**Testing.** First repeat the probe contract through the packaged helper: account,
stream, Stop, process loss/reconnect/resume, host missing, signed out, unsupported
protocol, helper disabled, app quit, and no shell/filesystem tool exposure. Then,
after FEAT-048's manual gate closes, drive read/apply_edits through that same
thread while watching transcript order and non-disruptive scrolling, highlight
on the right nodes, reduced-motion variant
(System Settings ▸ Accessibility ▸ Display ▸ Reduce motion), VoiceOver
announcement text, menu enablement with/without recorded batches, multi-window
(source editor focused) dispatch, and that disabling Sanaa mid-session clears
the feed and menu items without a relaunch.

---

### FEAT-050 — "Ask Sanaa": prompt starters with placement dialogs

*~1–2 sessions. Depends on FEAT-048 (ids in prompts are only useful if the
agent can act) and pairs with FEAT-049.*

> **Amendment (2026-08-29 — Part II).** The starter set gains **"Critique
> this…"** and **"Design directions…"**, composing facts-first prompts
> (`get_design_facts` + knowledge-module reads) per the §10 critique-framework
> and directions modules. The starters are also REORDERED so critique and
> cleanup lead — *Critique this… / Do repetitive work… / Complete this… /
> Draw variations… / Design directions…* — because narrow, judgment-adjacent
> and tedious work is what designers actually adopt (the same Figma Config
> 2024 audience that cheered Rename Layers vilified Make Designs — DOC, "The
> craft crisis," https://www.doc.cc/articles/craft-crisis). The v2.5 critique
> UI that consumes these prompts is FEAT-056 (§10).

**Goal.** One click turns a selection into a great editable prompt in Sanaa's
panel, with the §3 placement question answered by the designer up front.

**Behavior.**

- Right-click on a selection (and Object menu): **Ask Sanaa ▸**
  - *Complete this…* → sheet asks: work directly on this artboard, or on a
    duplicate beside it? (radio, default duplicate — the safe choice)
  - *Draw variations…* → sheet asks: how many (default 3), same page or new
    page? (default new page)
  - *Do repetitive work…* → free-text "what should Sanaa repeat/apply?", notes
    it requires in-place consent.
- Output: reveal Sanaa's panel and place the composed prompt in its composer for
  review/editing, e.g.:

  > Using the exp-design MCP server: call get_selection, then get_artboard on
  > the parents, to see what I'm working on. Create 3 VARIATIONS as new
  > artboards via apply_edits with placement kind "newPage" (name the page
  > "Sanaa — <topic> variations"). Use only node ids as references. Keep the
  > document's Design Language tokens (get_tokens) for colors and type.

- With a supported, ready runtime the composer action is **Send** and the response
  streams into the same transcript. If the host is missing or signed out, preserve
  the typed text, show the actionable setup state, and offer **Copy prompt for my
  agent** as the fallback rather than discarding the work.
- Full command coverage per the standing rule (all five wirings; the sheet IS
  the parameter surface, so no separate inspector control is needed — same
  reasoning as align).

**Testing.** Each starter with 0/1/many selected nodes and artboard-only
selections (enablement matrix); Send each through the Codex adapter against a
scratch document and verify the resulting `apply_edits` batches respect the
chosen placement; separately test Copy fallback and the Claude adapter when that
gate exists; VoiceOver labels/hints on the sheets; Escape/Return behavior;
keyboard-only run-through.

**Implementation 2026-08-31/09-01.** The three base starters, conditional Object
and canvas-context menus, selection-id capture, native placement sheets, editable
composer handoff/focus, and Debug prompt-contract probe are built. After FEAT-055
closed, the amendment added Critique this… and Design directions… in the required
critique/cleanup/complete/variations/directions order. Both new starters place a
read-only draft directly in the editable composer without auto-sending, require
live-scope confirmation, `get_design_facts` before analysis, and task-specific
guidance modules, and explicitly forbid `apply_edits`. The expanded prompt probe
and fresh universal Debug/Release builds pass. **The amendment's facts/guidance
behavior was owner-verified 2026-09-02 against the real critique mockup: Sanaa
caught every intentionally planted issue, including gradient contrast, and the
owner rated the pass “perfect.”** The owner signed off FEAT-050 in full on
2026-09-02, choosing evidence from broad public testing over further speculative
pre-release edge-case work. FEAT-050 is closed.

---

### FEAT-061 — Compact response cards + full Markdown reader

*~1–2 sessions. NON-mutating. v2.4 Wave D addition (owner, 2026-09-01).
Build before FEAT-056 so every assistant reply—not only critiques—gets the same
small-screen reading contract.*

**Goal.** The Sanaa tray stays conversational and scannable; a long answer becomes
a deliberate reading surface instead of turning the panel into a document viewer.

**Panel contract.** Every assistant reply renders Markdown rather than exposing its
markers. While streaming, show a bounded live preview and unfinished state. When
complete, cap the rendered overview to a small, stable height and provide **Open full
response**. Do not make a second summarization model call: critique/directions prompts
must ask Sanaa for a concise Overview first, and ordinary responses fall back to the
first meaningful rendered lines. Keep the original response available to copy.

**Reader contract.** Open a normal resizable companion window, not a floating palette.
One reply has at most one reader window; opening it again focuses that window. Closing
the reader does not clear the transcript. The reader may update during streaming, but
structured actions are disabled until the reply completes. Session clear/disable
closes or invalidates its readers rather than leaving content that appears current.
Render headings, paragraphs, lists, emphasis, code, and links without executing raw
HTML. Explicit `http`, `https`, and `mailto` links use the system default handler;
reject custom/file schemes. Malformed Markdown falls back to readable selectable text.

**Choice contract.** An option button is structured provider-neutral metadata, not a
guess based on prose such as “Would you like…”. Choosing **Create beside this artboard**
or **Create on a new page** places the complete consequence-bearing sentence in the
composer and returns focus there; it does not auto-send and can never invoke
`apply_edits` directly. No structured metadata means no invented buttons.

**Accessibility/lifecycle.** Opening moves focus to the response title/first heading;
Command-W closes and focus returns to the originating message action. Reader and rail
have one logical keyboard order; VoiceOver gets concise row labels instead of the full
report as one element. Support app type-size, increased contrast, Reduce Transparency,
Reduce Motion, light/dark, copy/select, and narrow/single-window use.

**Testing.** Long, short, malformed, and streaming responses; repeated open; clear and
disable; safe/unsafe links; keyboard-only/VoiceOver focus round-trip; all appearances;
ordinary versus floating windows; no document mutation from open/copy/choice.

**Implementation 2026-09-01.** The reusable vertical slice is built: capped Markdown
overview cards, one normal/resizable live reader per assistant reply, native block and
inline rendering, selectable/copyable source, safe default-browser links, origin-focus
return, and session-disable cleanup. The Debug build and deterministic in-app parser/
link probe pass. FEAT-056's numbered finding rail and node actions now supply the
structured metadata/buttons on top of this reader.

**Owner verification 2026-09-02.** The real report/read/action experience passed or
exceeded every owner test. FEAT-056 now supplies the explicit structured action
metadata and buttons; FEAT-061 is closed.

---

### FEAT-051 — Setup assistant: Sanaa for non-technical designers

*~1–2 sessions + research spike. Independent of 049/050; needs 048 only to be
worth advertising.*

**Built and verified 2026-09-02.** The shipped route is the honest copy-first
fallback: a three-step accessible sheet for Codex, Claude Code, Claude Desktop,
generic MCP clients, and no assistant yet. The real built accessibility tree was
walked through for the three distinct experience branches. `.mcpb` remains a
future transport experiment rather than a v2.4 setup claim.

**Goal.** The owner's criterion #1: someone who has never touched a terminal
can connect an agent.

**Behavior.**

- A guided "Set up Sanaa" flow (from Settings ▸ Sanaa and the panel's empty
  state): ① pick a supported host → ② detect/install or sign in without exposing
  credentials to EXP → ③ send a text-only hello → ④ verify the EXP MCP read tool.
  Generic MCP connection instructions remain available in Settings for advanced
  and unsupported clients, but do not masquerade as in-panel chat support.
- Detection (HYPOTHESIS — verify sandbox file-read reality before promising):
  checking for `/Applications/Claude.app` or the `claude` CLI from a sandboxed
  app may be restricted. If detection is blocked, degrade to "Which of these
  do you have?" buttons. Never fake detection.
- Claude Desktop path (RESEARCH FIRST): package `exp-mcp` as a one-click
  desktop-extension bundle (`.mcpb`/DXT format) so setup is double-click →
  approve. Verify the current packaging format, signing requirements, and
  notarization interaction against Anthropic's current docs at implementation
  time — this plan deliberately records NO version-specific details. If
  packaging proves heavy, ship copy-paste-first and log the extension as a
  follow-up.
- Claude Code path: the existing generated `claude mcp add` one-liner, kept.
- Plain-language copy throughout ("Sanaa uses YOUR AI assistant and its plan.
  EXP never sends your work anywhere itself.") — matching the honest privacy
  sentence already in the Handoff panel.

**Testing.** Fresh macOS user account: follow the flow with only Claude
Desktop installed, then only Claude Code, then neither (the flow must fail
kindly and say exactly what to install). Screen-reader run of the whole flow.
Owner reviews all copy for honesty (no capability inflation).

---

### FEAT-052 — The Sanaa character (avatar)

*~1–2 sessions + asset work with the owner. Depends on 049's controller.*

**Goal.** The cute, Clippy-adjacent face — strictly presentation on top of the
activity layer, and strictly optional (§4.5).

**Scope clarification 2026-09-01:** this is an in-app canvas character, not a
website-only mascot and not a starter/help-document section. Sanaa works fully
without it. **Owner decision 2026-09-01:** defer it from v2.4 with no target
release; retain the concept only as an unplanned future possibility.

**Behavior.**

- Small avatar rendered in the canvas overlay near Sanaa's latest work (or
  docked bottom-corner when idle). States: idle / listening (agent connected)
  / drawing (batch applying) / done (settles after highlight fades).
- Assets follow `docs/DESIGN-ASSETS.md` (formats, sizes, naming, the
  `design-assets/` manifest) — the owner designs Sanaa; implementation
  consumes the manifest. Template-image vs full-color is the owner's call.
- Accessibility: the avatar itself is `accessibilityHidden(true)` decorative —
  every state it conveys is ALSO in the activity feed text and announcements
  (FEAT-049), so hiding it loses nothing. All animation honors Reduce Motion;
  no sound.
- Never a window: it draws inside the canvas view. (Every windowed-companion
  approach in this codebase's history ended in the CLAUDE.md gotcha list.)

**Testing.** State transitions during a scripted batch; avatar toggle off
leaves zero visual trace; Reduce Motion swap; zoom/pan performance with the
avatar animating (Testing Mode frame log — no regressions vs. baseline);
light/dark/increased-contrast rendering.

---

### FEAT-053 — Sanaa capability pack (agent etiquette)

*~1 session. Depends on 048; refine after 050 exists.*

**Built and verified 2026-09-02.** `exp://sanaa/guide` and
`get_sanaa_guide` serve the same bundled guide without requiring an open
document; the packaged Codex adapter reads it before writes. Focused source,
resource, runtime-allowlist, and build gates pass, and the owner's real starter
sessions cover the behavioral scenarios.

**Goal.** Any agent, cold, behaves like a good studio assistant. This slots
into the already-roadmapped (deferred) "agent capability packs" item.

**Scope clarification 2026-09-01:** this is machine-readable guidance supplied
to connected agents through MCP. It is not a visible inspector/help area like
the ARIA-role guidance; such a user-facing Sanaa Help section would be separate
scope.

**Content.**

- A canonical guide served as a new MCP resource (`exp://sanaa/guide`,
  alongside the existing orientation resource) and shipped in the repo:
  summaries-first reads; node ids as the only reference currency; ALWAYS ask
  for placement when the designer didn't specify (§3 table verbatim); small
  batches with honest `summary` strings (they become undo labels); respect
  Design Language tokens; never `removeNodes` outside the explicit ask;
  degrade gracefully when the app is closed or consent is off.
- Thin host wrappers (a Claude skill, etc.) only AFTER the guide has survived
  real-client testing — same sequencing the roadmap already prescribes for
  capability packs, and raw MCP setup must always keep working without them.

**Testing.** Fresh Claude Code session with only the guide + tools: run the
three FEAT-050 scenarios and score against the etiquette list; try a
deliberately vague prompt ("finish this") and verify the agent asks about
placement instead of guessing.

---

## 7. Explicitly deferred / rejected

- **In-app BYO-API-key chat panel** — rejected for v1: reverses the recorded
  reach-in decision, harder for non-technical users, and makes EXP own
  billing/limits/error UX. Revisit only on owner request.
- **MCP sampling as the in-EXP prompt transport** — rejected 2026-08-26. The
  2026-07-28 MCP specification deprecates sampling and tells new implementations
  not to adopt it. Sanaa uses explicit supported host adapters instead.
- **Multiple simultaneous named agents with cursors** (pen.dev's six-agent
  swarm) — out of scope; the bridge technically accepts multiple clients
  already, and the activity feed names each, which is enough.
- **Sanaa initiating work unprompted** — never. Sanaa only ever acts on a
  tool call from the agent the designer invoked.
- **One-click "just make it good" / silent restyling** — rejected. It
  contradicts options-not-prescriptions (every proposal carries alternatives
  + tradeoffs) and bypasses the consent funnel; "make it good" with no dialog
  is exactly the "AI designing for you" framing the trust evidence marks as
  hostile territory. Sanaa answers such a request by asking questions and
  offering directions (FEAT-057), never by unilaterally restyling.
- **Sanaa-initiated critique popups** — rejected; already covered by
  "Sanaa initiating work unprompted" above. Critique exists only when the
  designer asks (FEAT-050 starter / FEAT-056).

## 8. Standing requirements for every chunk

- **Sequencing:** nothing document-mutating lands while another mutating slice
  awaits owner verification.
- **Command coverage** (CLAUDE.md): all five wirings, `sendCanvasAction` only.
- **Accessibility is verified, not remembered:** this feature is macOS app
  chrome, so the checks are VoiceOver labels/hints/order, full keyboard paths,
  light/dark + increased contrast + reduced transparency, and Reduce Motion —
  verified against Apple's accessibility documentation at implementation time.
  The ARIA/WCAG export-contract rule is not triggered (Sanaa changes no export
  semantics); if any chunk ever touches exported semantics, the
  WORKING-AGREEMENT ARIA rule applies in full. NOT verified in this plan:
  exact AX announcement API names, sandbox file-detection limits, and desktop-
  extension packaging details — all marked HYPOTHESIS/RESEARCH above.
- **Backlog hygiene:** ids FEAT-048…053 were assigned after running
  `scripts/verify_backlog_ids.sh` (clean, next-free confirmed 2026-08-25).
  Progress Log entries per session, newest on top.
- **Honest copy:** Sanaa is presented as "your agent, drawing here" — never as
  EXP's own intelligence. Real client names stay visible.
- **Sanaa voice rules bind all Sanaa copy** (Part II/FEAT-054 `voice.md`):
  draft/suggest framing; options with tradeoffs, never a single "best"
  answer; a one-glance checkable "why"; never "perfect/best/optimal"; never
  compliance claims; the designer's vocabulary; invite pushback; concise;
  publish failure modes where they apply.
- **A11y priority even when it is the heavier lift:** when a Sanaa choice
  trades effort against accessibility, accessibility wins, and shortcuts are
  named as shortcuts.
- **Measured facts, not verdicts:** EXP computes; Sanaa interprets. Sanaa-
  facing tool output states measured values + criterion citations; verdict
  language ("non-compliant," "fails ADA") never appears in tool output or
  Sanaa copy.
- **Standards re-verification:** standards citations go stale — re-check
  against w3.org / section508.gov / ada.gov before any standard or deadline
  reaches product copy. (The a11y module's dates were verified 2026-08-29;
  the Title II deadlines are entity-scoped and rulemaking was active.)
- **Knowledge-pack citation discipline:** every standards claim in the pack
  carries a URL and a verified-on date; a module without a current
  verification does not make standards claims.

## 9. Effort summary

| Chunk | What | Est. sessions |
|---|---|---|
| FEAT-048 | apply_edits + consent + settings | 2–3 |
| FEAT-049 | activity feed + highlights + announcements | 2 |
| FEAT-050 | Ask Sanaa starters + placement dialogs | 1–2 |
| FEAT-051 | setup assistant (+ packaging research) | 1–2 |
| FEAT-052 | avatar/character (+ owner asset time) | 1–2 |
| FEAT-053 | capability pack | 1 |
| FEAT-054 | Part II: design knowledge pack (v2.4 Wave D) | 2–3 |
| FEAT-055 | Part II: computed design facts read tool (v2.4 Wave D) | 2 |
| FEAT-050 amdt. | Part II: critique + directions starters (v2.4) | ~½–1 |
| FEAT-061 | compact responses + full Markdown reader (v2.4) | 1–2 |
| FEAT-056 | structured critique report (v2.4) | 2 |
| **Total (v2.4)** | | **15–22** |

v2.5 candidates (NOT in the total; all await owner gates):

| FEAT-057 | Part II (v2.5 candidate): design directions engine | 1–2 |
| FEAT-058 | Part II (v2.5 candidate): cleanup ops / apply_edits v2 | 2–3 |
| FEAT-059 | Part II (v2.5 candidate): a11y guided fixes | 2 |
| FEAT-060 | Part II (v2.5 candidate): design-quality evaluation harness | 2 |

A minimal lovable Sanaa (048 + 049 + 050) is roughly **5–7 sessions**; 051–053
turn it from a feature into a companion. Part II's v2.4 additions (054 + 055 + the 050
amendment + 061 + 056) are ≈ **7–10 sessions** on top of Part I's 8–12; the v2.5
candidates (≈ 9–11 sessions if all are pursued) are scoped in §10 and stay
open in BACKLOG.

---

## 10. Part II — the design knowledge pack

*Drafted 2026-08-29 from owner direction. Part I built the body — the write
spine, the runtime, the panel. Part II gives the designer's own agent the
knowledge and the measured facts EXP can compute, so it becomes genuinely
good at design work — critique and guidance, options for hard UI problems,
tedious cleanup, accessibility grounding, and style awareness — while every
Part I boundary stays exactly as it was: switches OFF by default, the
consent/undo funnel, the fidelity test, and honest copy. Sanaa works WITH the
designer or not at all.*

**New standing principle: measured facts, not verdicts.** EXP computes
(contrast ratios, sizes, spacing); Sanaa interprets. Tool output and Sanaa
copy state measured values with criterion citations; judgment stays with the
designer. Verdict language — "non-compliant," "fails ADA" and cousins — never
appears in tool output or Sanaa's voice (§8).

**Placement.** FEAT-054 + FEAT-055, plus the FEAT-050 amendment (§6), are
v2.4 Wave D additions: non-mutating, ≈ **4–6 sessions** total. FEAT-056–060
are **v2.5 candidates**: scoped here, kept open in BACKLOG, not promised.
Nothing in Part II changes a switch, a gate, or the `apply_edits` funnel.

Canonical build order: **FEAT-054 → FEAT-055 → the FEAT-050 amendment.**
The amended starters compose facts-first prompts against tools that must
already exist. If FEAT-050 (Wave B base) ships before 054/055, its starters
ship with plain prompt composition and gain the facts-first composition when
the amendment lands. 054 and 055 are mutually independent; either may be
built first. v2.5 candidates follow in owner-chosen order.

---

### FEAT-054 — Sanaa Design Knowledge Pack

*~2–3 sessions. v2.4 Wave D addition (2026-08-29). NON-mutating. Builds on the
same MCP-resource seam FEAT-053 uses (`exp://orientation` precedent); either
may land first — if 053 lands first its etiquette guide cross-links voice.md.
Full value arrives with FEAT-055's facts tool, but the pack ships
independently.*

**Goal.** Give any host agent — not just Codex — a versioned, on-demand design
curriculum, so Sanaa's advice is grounded in named, citable design knowledge
instead of whatever the host model defaults to. The pack is content, not
behavior: it teaches observations and tradeoffs; EXP never enforces it, and
nothing in it creates a write path.

**Shape.** Versioned markdown modules shipped as app-bundle resources, served
over MCP as resources `exp://sanaa/knowledge/<module>` plus
`exp://sanaa/knowledge/index`, enumerated in `resources/list` (extend the
existing single-resource seam; no document needs to be open for them).

**RESEARCH GATE (resolved 2026-08-30).** A packaged Codex-adapter thread read
the knowledge resource once, then a focused repeat timed out. The raw MCP
resource route remains for provider-neutral clients, but it is not reliable
enough to be the dedicated runtime's only route. Serve the same modules through a
read tool instead — `get_design_guidance` with call shape
`{ "module": "<name>" }` returning the module body (or the module list when
called with no argument) — added to BOTH the `AgentBridge.toolDefinitions`
list AND the hard-coded `enabled_tools` allowlist in
`sanaa-runtime/CodexAdapter.swift` — the adapter kills the host for any tool
call outside that string. The gate probe extends the existing packaged-runtime
harness (`scripts/verify_sanaa_runtime_packaged.sh` pattern), not a new
mechanism. Implemented and verified 2026-08-31 against the relaunched Debug
app: after the v2 guidance integration, the live socket returned all 24 modules
byte-identically through both the resource and fallback routes, and the packaged
Codex thread called the fallback without an approval boundary while all four
negative trust gates remained green. The owner also accepted the tested guidance
behavior/appearance. One non-Codex MCP-client pass remains.

**Modules (launch set).** Every module: frontmatter (`name` / `version` /
`updated`) + TL;DR-first body, imperative "if-then" rules over prose, and a
pack-level `CHANGELOG.md`. Modules load on demand; only INDEX is read
unprompted.

- `INDEX.md` — module map + when-to-load table + pack version and
  verified-on dates. Small by design (≤ ~1–2k tokens).
- `design-principles.md` — hierarchy, contrast, alignment, proximity,
  whitespace, Gestalt grouping as canvas-checkable observations
  (precondition → observed-deviation check), not essay prose.
- `color.md` — palette construction, harmony schemes as starting recipes,
  semantic roles, lightness-first discipline, and a dark-mode section
  (adjust for contrast on dark surfaces, elevation by lightness, re-map
  semantics rather than invert). Pairs with FEAT-055: the pack never guesses
  a ratio the tool can compute.
- `typography.md` — modular scales, measure/line-height relationships,
  hierarchy through type roles.
- `spacing-layout.md` — 4/8pt spacing systems, grids, density, alignment
  discipline. **Strictly descriptive:** the model has no spacing tokens and
  FEAT-055 does not judge spacing, so this module must not imply
  rule-checking that does not exist.
- `components-states.md` — state completeness (hover/focus/active/disabled/
  error/empty/loading) and form patterns; missing states are the highest-value
  observation a design-stage assistant can make.
- `copy-microcopy.md` — copy as design material: user-side vocabulary, active
  voice, error/empty-state writing, one consistent action verb per flow.
- `styles/<name>.md` — launch set of **6–8 named aesthetics** with concrete
  attribute descriptors: type pairing, palette anchors, spacing density,
  corner/shape language, shadow/texture vocabulary, motion temperament, and
  mandatory "where it works / where it fails." Public taxonomies to draw from:
  uistyleguide.com and DesignerUp's UI-trends field guide. Candidates: swiss/
  international, minimal, editorial, neo-brutalist, glassmorphic, claymorphic,
  corporate-safe, playful. Final launch set is the owner's call.
- `anti-generic.md` — steering rules against generic AI output: the
  documented slop-tells (default font stacks, purple-gradient heroes,
  centered-hero-plus-three-cards) and the current model-default clusters that
  **Anthropic's public `frontend-design` skill** names (named as a public
  source). Includes: plan-before-pixels, divergence on named axes, one
  signature element, subject grounding, structure-is-information, the
  quality floor (real states, visible focus, reduced motion), copy-as-design.
- `critique-framework.md` — the structured critique shape (What works /
  Measured findings / Design observations / Open questions), a severity
  scale with anchors, and the hard rule that critique rides FEAT-055 facts
  first.
- `directions.md` — v2.0's nine-axis style genome, explicit from→to divergence,
  silent candidate enumeration, and sibling check, with rationale + tradeoff
  (the FEAT-057 contract).
- `procedural-tasks.md` — deterministic measure→derive→replicate work for rows,
  repeated structures, and coherent subject-grounded placeholder data.
- `bulk-adjustments.md` — compact/spacious variants derived from observed
  spacing, with hierarchy, target-size, type, and content floors preserved.
- `a11y-applied.md` — measured contrast, target-size, semantic-role, and focus
  workflows; a companion to the standards map rather than a verdict engine.
- `style-profile.md` — current document/session style grounding and honest
  no-memory behavior. Its persistent designer-owned profile/editor/log contract
  remains explicitly future work and is not claimed by v2.4.
- `a11y-foundations.md` — the standards map (below), the design-stage vs
  implementation-stage split, the judgment-required category (alt-text
  quality SC 1.1.1, reading-order meaningfulness SC 1.3.2/2.4.3, 2.5.8
  exception adjudication, contrast over gradients — design-stage yet never
  automatable as verdicts), and the compliance-claim copy rules.
- `voice.md` — Sanaa's own language guide (below). FEAT-053's etiquette
  guide cross-links it.

**a11y-foundations.md contents** (facts verified 2026-08-29 against primary
sources; the module keeps the URLs and its verified-on date):

- Section 508 incorporates **WCAG 2.0 Level AA** by reference; no 508 refresh
  exists as of Aug 2026. https://www.section508.gov/develop/applicability-conformance/
- DOJ ADA Title II web rule: technical standard **WCAG 2.1 Level AA**
  (https://www.ada.gov/resources/2024-03-08-web-rule/). The April 2026 interim
  final rule extended compliance deadlines: entities ≥50,000 population →
  **April 26, 2027**; <50,000 and special district governments → **April 26,
  2028** (https://www.federalregister.gov/documents/2026/04/20/2026-07663/;
  eCFR 28 CFR 35.200). Deadlines are **entity-scoped** (state/local
  governments, not private companies) and **re-verify before citing** —
  rulemaking was active as of the verification date. ADA Title III has no
  binding web technical standard; private-sector WCAG targets are risk-driven.
- **WCAG 2.2** is the current W3C Recommendation (Oct 2023, updated Dec
  2024); it does not deprecate 2.1, and 4.1.1 Parsing is obsoleted in it.
  https://www.w3.org/WAI/standards-guidelines/wcag/
- **EN 301 549 v3.2.1** is the harmonised version (incorporates WCAG 2.1); a
  WCAG-2.2-aligned revision is in development but not harmonised
  (https://digital-strategy.ec.europa.eu/en/policies/latest-changes-accessibility-standard).
  The European Accessibility Act applies from **28 June 2025**
  (EUR-Lex Directive 2019/882: https://eur-lex.europa.eu/eli/dir/2019/882/oj).
- **APCA is advisory-only** — not in WCAG 2.x, not a conformance metric; the
  WCAG 3 contrast algorithm is undetermined
  (https://www.w3.org/TR/wcag-3.0/).
- Automation honesty: design-time/automated checks catch roughly **30–40%**
  of issues per UK GDS/DWP guidance, up to **~57%** in Deque's vendor study —
  never imply complete coverage.
  https://gds-way.digital.cabinet-office.gov.uk/manuals/accessibility.html ·
  https://accessibility-manual.dwp.gov.uk/best-practice/how-to-do-accessibility-testing ·
  https://www.deque.com/automated-accessibility-coverage-report/

**voice.md contents** (distilled from the designer-trust research; binding on
all Sanaa copy per §8). The module must be enforceable, so it ships with
exact strings, not just principles:

- Draft/suggest framing — humble nouns (draft, pass, check, options), never
  design or power nouns. The UI starter names pass by definition — they are
designer-invoked actions ("Critique this…", "Design directions…"), not
  AI-output nouns like "Make Designs" — voice.md records that verdict.
- Options, not prescriptions — always with tradeoffs; never a single
  answer.
- A one-glance, checkable "why" — concrete canvas evidence (values, ids),
  never generic argument.
- Never "perfect/best/optimal" (or magical/delightful/effortless/stunning)
  as quality claims; the ban is scoped to Sanaa's own output voice.
- Claim patterns the voice-lint can grep: banned — "ADA compliant",
  "accessible now", "WCAG compliant" (unscoped); allowed — "<value> vs
  <threshold> per SC x.y.z, this pair" (a scoped threshold statement about
  one measured pair is not a verdict; unscoped pass/fail is).
- A DO / DO-NOT table with ≥8 exact-string pairs, e.g. DO: "here are three
  directions, each with a tradeoff — your call" / DO NOT: "I've improved
  your design"; DO: "this pair reads 4.53:1, above the 4.5:1 minimum in SC
  1.4.3" / DO NOT: "this text passes WCAG".
- The designer's vocabulary; invite pushback; concise; publish failure
  modes where they apply ("reliable for contrast checks; experimental for
  type pairing").
- Never acts unprompted; declines explicitly, with a reason, when out of
  scope.

**baseInstructions changes:** ~3 stable pointer lines only (read the
knowledge index first; load modules on demand; facts before critique). The
pack — not the thread instructions — carries the depth. The persona line is
unchanged.

Knowledge-grounded answers disclose their freshness on the product surface:
"Grounded in EXP's bundled design notes — updated <module date>." Cheap,
checkable, on-register.

**Files (expected).** A bundled resources directory (e.g.
`EXP [design]/Resources/SanaaKnowledge/` — app bundle only, never referenced
from shared model files), `Export/AgentBridge.swift` (resource list/read
extension, or the `get_design_guidance` tool if the gate says so),
`sanaa-runtime/CodexAdapter.swift` (only if the fallback tool path wins the
gate), plus ~3 lines in `canvasThreadParams` baseInstructions. New files
stay app-target-only; verify EXPThumbnail target-membership is not touched
(CLAUDE.md shared-file rule).

**Testing.**

1. *Deterministic, scriptable:* resources/list enumerates the full module
   set; resources/read returns each module byte-identical from the bundle;
   INDEX + every module stay within the token budget (assert on file size at
   gate time); thread instructions grow by ≤ the 3 pointer lines; rerun
   `scripts/verify_sanaa_write_gate.sh` — the pack adds NO write path and the
   gate matrix is unchanged. If the fallback tool won: both-allowlist
   regression through the packaged thread.
2. *Cold-agent behavior tests (fresh thread, no history):* ask for critique →
   the answer cites computed facts and matches voice.md (no verdict words, no
   compliance claims); ask for directions → ≥3 genuinely different directions
   with named axes and rationale; ask "just make it good" → the agent asks
   questions and offers options instead of unilaterally restyling.
3. *Provider-neutral pass:* a Codex thread and one non-Codex MCP client get
   the same bytes and behave equivalently.
4. *Golden-set seed:* the golden documents + prompts authored for these
   tests are FEAT-060's lite seed — keep them owner-adjustable and
   session-safe.

**Gotchas.**

- Token bloat — modules load on demand; INDEX stays small; never concatenate
  the pack into thread instructions.
- Stale advice — every module carries version/updated; standards citations
  re-verify per §8; the a11y module is the most perishable file in the app.
- Over-steering — the pack teaches observation, not rule-enforcement. If
  Sanaa starts lecturing about 8pt grids as law, voice.md and the module
  framing failed.
- Style modules must not become trend-romanticism — concrete attributes over
  vibes; "where it fails" is mandatory per style.
- Knowledge must work for ANY host agent — no host names, no Codex-only
  assumptions in module text.

**NOT verified:** cold-agent behavior, one non-Codex client, owner appearance
review, any Codex-side instruction-length limit (none visible in EXP's code),
or exact tokenizer counts. Guidance v2.0's measured byte budget is 104,855 bytes
for all 25 files (24 served modules plus changelog) and 3,743 bytes for INDEX.

---

### FEAT-055 — Computed design facts read tool (`get_design_facts`)

*~2 sessions. v2.4 Wave D addition (2026-08-29). NON-mutating. Depends on
nothing new: builds on the shipped `Color/ContrastMath.swift` and the existing
read-tool seam.*

**Goal.** One read tool that turns the frontmost document into measured,
citable design facts — contrast pairs, text sizes, target sizes, spacing
inventory, fonts — so Sanaa (and any agent) interprets numbers EXP computed.
Standing principle: **measured facts, not verdicts.** The tool NEVER outputs
"non-compliant"/"fails ADA"-class judgments; it outputs values + criterion
citations + an explicit list of what it could not assess.

**Tool.** `get_design_facts`, scoped by `artboardId` or the current
selection. New read tool → extend `AgentBridge.toolDefinitions` AND the
hard-coded `enabled_tools` string in `sanaa-runtime/CodexAdapter.swift`
(both, or the adapter kills the host for calling it). It follows the read
path: advertised with the read tools, no consent sheet, no Sanaa master-switch
requirement beyond the existing read-tool policy.

**Facts returned.**

- `colorPairs` — per text run: foreground color, resolved backing (walk
  AutoPadding fill → shape fill → artboard `background`, flattening alpha
  over the resolved base via ContrastMath), ratio, and the applicable
  threshold with citation: **4.5:1 / 3:1 for large text per SC 1.4.3**
  (https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).
  Large-text classification (≥18pt regular / ≥14pt bold ≈ 24px / ≈18.67px —
  the same points-at-1× basis as target size) uses font size plus a
  **fontName heuristic for bold** — TextRun has no weight flag — and every
  heuristic classification is labeled as such in the output. Alpha-over-
  transparent pairs are themselves labeled as estimates ("estimated —
  flattened over <base>; WCAG defines no alpha-blending method"), not just
  the base reported; a backing that itself has alpha (stacked translucency)
  and text over image layers route to `notAssessed` with the reason.
- `nonTextContrast` — **3:1 per SC 1.4.11**
  (https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html),
  reported only where determinable (solid component fill against a resolvable
  backing); otherwise the pair lands in `notAssessed` with the reason
  (gradient, image, unresolvable backing).
- `textSizes` — per-run font sizes; flags the smallest text on the board.
- `targetSizes` — frame dimensions of nodes classified interactive via
  `NodeSemantics.role`/`implicitRole`, ComponentSource a11y roles, and
  control relationships. **Classification is a heuristic** (no stored
  "isControl" flag) and labeled as such. Reference: **24×24 CSS px ≈ points
  at 1× per SC 2.5.8**
  (https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html),
  with the standard's five exceptions (spacing / equivalent / inline /
  essential / user-agent control) listed for the agent to consider — the
  tool reports sizes, never pass/fail.
- `spacingInventory` — auto-layout gaps and sibling-frame deltas,
  **descriptive only**. No spacing tokens exist in the model; this tool
  implies no spacing rule-checking.
- `fontInventory` — font names + sizes in use.
- Every response carries `notAssessed: [...]` — what could not be measured
  and why (gradients, alpha over unresolvable backing, rotated text,
  instance internals where resolution failed).

**Behavior.**

- Instance overrides resolve through the existing deterministic model path
  (`applyingOverrides` / `applyingState` + reflow) so facts read true through
  component placements.
- Caps: large artboards return a bounded response (node/pair caps + an
  explicit `truncated` flag), never a silent partial.
- Output = measured values + criterion citations + the heuristics actually
  used. Interpretation lives with the agent and a11y-foundations.md.

**Files (expected).** `Export/AgentBridge.swift` (tool def + routing) plus a
new app-target-only `Export/SanaaFacts.swift` (verify EXPThumbnail
target-membership is not touched before referencing it from any shared
file), `sanaa-runtime/CodexAdapter.swift`
(allowlist string). No model changes.

**Testing.**

1. *Golden fixtures with known ratios:* scratch documents whose expected
   ratios match ContrastMath's unit expectations (4.5:1 and 3:1 boundaries,
   large-text threshold cases); the tool must reproduce them exactly.
   Fixtures are created the same way as the FEAT-048 socket-test scratch
   documents (.design scratch files + scripts), not hand-built JSON blobs.
   The golden set authored here is FEAT-060's lite seed — owner-adjustable
   and session-safe.
2. *Honesty cases:* alpha fills (report the flattening base), gradient fills
   (`notAssessed` + reason), rotated text, oversized artboards (truncation
   flag set, response bounded).
3. *Both-allowlist regression:* the tool is callable through the packaged
   Codex thread and the adapter does not kill the host.
4. *No-write proof:* repeated `get_design_facts` calls leave artboard count
   and document state untouched; the FEAT-048 gate matrix is unchanged.

**Gotchas.**

- Gradients/compositing honesty — WCAG provides no measurement for gradient
  or alpha contrast; report estimates as estimates or notAssessed, never as
  criterion results.
- Rotated/arc text — bounding boxes mislead; skip or flag, don't report a
  confident-looking pair.
- No bold flag — the fontName heuristic will misclassify some names; label
  every inference.
- sRGB/P3 — the model is straight sRGB end to end; facts are sRGB numbers,
  not display-P3 appearance, and the output says so once.
- Perf caps — facts computation walks the tree; cap and truncate rather than
  hang the bridge.
- Never fabricate thresholds — only cited criteria (1.4.3, 1.4.11, 2.5.8)
  appear; no invented "spacing rule," no APCA in tool output.

**NOT verified:** instance-resolution behavior under reflow for pathological
nesting (test at implementation); tool-schema size limits Codex-side (none
observed for existing tools).

**Implementation 2026-09-01.** `Export/SanaaFacts.swift` is a bounded,
app-target-only calculation layer with no AppKit, consent, undo, or mutation
surface. `AgentBridge` advertises/routes it and `CodexAdapter` includes it in the
exact packaged allowlist. The saved-document golden gate covers component
override/reflow, component roles and root control relationships, measurement and
honesty cases, artboard/selection scope, depth/node/response caps, deterministic
encoding, and byte-for-byte no write. Adjacent canvas/semantic/guidance gates and
fresh unsigned Debug/Release builds pass. The earlier pathological-nesting item
is covered by the explicit depth cap. Codex-side schema/response behavior passes
`verify_sanaa_runtime_packaged.sh --facts-read-only`; the direct public-route/
no-write gate is `scripts/verify_sanaa_facts_live.sh`.

**Owner verification 2026-09-01:** the rebuilt-app live/public route, packaged
Codex facts call, and artboard/selection behavior pass. FEAT-055 is closed.

---

### FEAT-056 — Structured critique report (v2.4)

*~2 sessions. NON-mutating. Promoted into v2.4 by the owner 2026-09-01 after
the FEAT-050 amendment's first real critique proved the content but exposed the
plain-text panel's reading cost. Depends on FEAT-055 + FEAT-054 and consumes the
reusable FEAT-061 reader. Golden documents come from the FEAT-060 lite seed
authored with FEAT-054/055 acceptance.*

**Goal.** "Ask Sanaa ▸ Critique this…" produces structured findings the
designer can act on node-by-node — critique as a reviewable artifact, not
chat scrollback.

**Files (expected).** `UI/SanaaPanel.swift` + `UI/SanaaActivityController.swift`
(structured finding rows in the transcript; a new row kind, NOT an applied-
batch receipt — receipts are currently minted only by the apply success path),
reusing the existing Select/Go action infrastructure from FEAT-049.

**Behavior.**

- Findings render in five groups: **What works** / **Measured findings**
  (each cites a `get_design_facts` value + criterion) / **Design
  observations** (judgment, rationale required) / **Open questions** /
  **Couldn't assess** (the `notAssessed` values plus the design-stage
  coverage note from a11y-foundations.md — silent blind spots read as false
  completeness). Design observations never propose canvas fixes for
  implementation-stage criteria (keyboard behavior, focus order/visibility,
  ARIA semantics) — they point at the Handoff export and
  `docs/SEMANTIC-HTML-CONTRACT.md`.
- Each finding gets a stable report-local number in a narrow rail. Primary identity
  is a human label (`3 · Rectangle`, or a meaningful layer name when one exists);
  the full UUID stays hidden but copyable in Details. Aliases are deterministic by
  first occurrence and never used to resolve selection.
- Each finding references full node ids → **Show on canvas** selects/highlights via
  the receipt Select/Go infrastructure without closing the reader. Keyboard focus
  stays in the report and VoiceOver announces the highlighted layer. If the source
  document/page changed or a node was deleted, disable the action and say that the
  original element is unavailable—never fall back to a same-named layer.
- **Explore** puts a scoped follow-up naming the finding and full ids in the composer
  for review; it does not auto-send. A session-only reviewed/bookmarked state may
  mark a finding without implying the canvas issue is fixed.
- Severity scale per critique-framework.md so findings sort and filter.
- Fixes are only ever an opt-in follow-up per finding ("propose fixes?" →
  FEAT-059-style consented batch). Never auto-applied, never bundled with the
  critique itself.

**Testing.** On golden documents, every measured finding traces to a facts
value; the **Couldn't assess** group is present and matches the facts tool's
`notAssessed` list; tapping each finding selects exactly its referenced
nodes; severity sort holds; NO write occurs from critique alone; voice
matches voice.md.

**Gotchas.** Critique without facts is vibes — the flow must call
`get_design_facts` first (critique-framework.md hard-codes this). Never
unprompted (§7). Judgment findings must carry rationale; measured findings
must not smuggle in verdicts.

**Implementation and owner verification 2026-09-02.** The response reader now
consumes bounded structured metadata and renders the numbered finding rail with
deterministic human aliases, per-element and Show-all canvas actions, and
Explore-to-composer without auto-send. The owner tested the real critique report
and reported that it passed with flying colors: the one-click actions were easy,
Show on canvas worked correctly, and the report caught every intentionally planted
issue. FEAT-056 is closed.

---

### FEAT-057 — Design directions engine (v2.5 candidate)

*~1–2 sessions. NON-mutating code — an upgrade of the "Draw variations"
prompt composition. v2.5 candidate. Depends on FEAT-054's styles/directions/
anti-generic modules.*

**Goal.** "Draw variations" grows up: 3–4 DISTINCT directions along named
axes, each with a one-line rationale and tradeoff — not three pixel-shuffles
of the same idea.

**Files (expected).** The FEAT-050 starter surfaces (sheets/composer) only;
no bridge or model changes.

**Behavior.**

- Directions diverge on named axes — layout strategy, density, color
  strategy, type mood — with at least three axes genuinely differing per
  directions.md.
- Each direction: name, one-line rationale, one-line tradeoff.
- Style anchor field: default is the document's own language (tokens +
  existing artboards); optional named aesthetic via `styles/<name>.md`.
- Anti-generic rules from anti-generic.md apply (slop-tell blocklist, one
  signature element, subject grounding).
- Diversity ≠ extremes: divergence is on axes, not garishness; respect the
  document's tokens unless the designer asks to depart from them.

**Testing.** Owner-rubric divergence scoring over golden prompts: are the
directions actually different? does each rationale hold up? Fresh-agent runs
produce axis-divergent directions without relying on the same default cluster
twice.

**Gotchas.** Choice overload — cap at 4. Forced diversity producing garbage —
a direction that fights the brief is worse than two good ones; directions.md
says when to offer fewer. Respect tokens unless asked.

**NOT verified:** the owner's divergence rubric does not exist yet — it is
authored with the owner when this chunk starts.

---

### FEAT-058 — Cleanup & repetitive ops (`apply_edits` v2) (v2.5 candidate)

*~2–3 sessions. MUTATING — the §8 sequencing rule applies in full. v2.5
candidate. Depends on FEAT-048's shipped pipeline.*

**Goal.** The tedious work Sanaa was always meant for: bulk renames, restyles,
and normalization as consented, undoable batches.

**Files (expected).** `Export/SanaaEdits.swift` (new op kinds in the parser,
validation, consent classification, caps), `Export/AgentBridge.swift` (tool
description text), `sanaa-runtime/CodexAdapter.swift` (no change expected —
apply_edits is already allowlisted).

**New op kinds** (inside the existing parse → dry-run → consent → rebuild
pipeline):

- `restyleNodes` — apply a property set to every node matching a predicate.
- `applyToken` — apply a Design Language value to matching nodes. Matching is
  **by value** — no fill↔token links exist in the model; the op sets values
  and does not create links. Stated honestly everywhere it matters.
- `normalizeSpacing` — snap auto-layout gaps/sibling deltas to a stated scale.
- `renameNodes` — rename by rule (pattern/prefix/sequence).

**Safety shape.**

- The consent receipt shows the **exact affected ids + count BEFORE apply** —
  the dry-run pass already exists, so predicates resolve first and the
  designer sees precisely what will change.
- Default predicates are narrow (selection- or artboard-scoped); broad
  predicates (whole page/document) must say so in plain words on the receipt.
- Restyling a component SOURCE hits **every placement** — the receipt warns
  "this changes every use of <component>" when predicates resolve to
  source-owned nodes.
- Instance internals are unreachable for writes today (document-level trees
  only) — bulk ops state that instance contents are skipped, never silently.
- Caps ≤200 ops, one consent, one undo step "Sanaa: <summary>" — unchanged.

**Testing.** Gate-matrix extension (new ops under every switch state);
predicate-safety cases (matches nothing / matches unexpected nodes → receipt
correctness, refusal on ambiguity); source-restyle warning; 201-op cap; undo
label; the dry-run preview and the applied result resolve through the SAME
predicate code path (assert identical id sets).

**Gotchas.** Predicate blast radius — a predicate bug that previews fewer
nodes than it hits is the worst-case defect; the preview must never diverge
from the apply path. Token cascade absent — applyToken sets values, it does
not create live token binding. BUG-010 relationship-remap hazard — ops that
replace/remove nodes must preserve the anchored-relationship remapping
discipline.

**NOT verified:** exact predicate DSL (specified at implementation; default
narrow); interaction of new ops with the 4 MB socket-line cap for very large
matched sets (bounded by the 200-op cap in practice — verify).

---

### FEAT-059 — A11y guided fixes (v2.5 candidate)

*~2 sessions. MUTATING (consented `apply_edits` batches). v2.5 candidate.
Depends on FEAT-055 and FEAT-058's op vocabulary.*

**Goal.** Close the loop: facts → proposed fixes the designer approves. The
designer stays the decision-maker; Sanaa proposes, consent disposes.

**Files (expected).** `Export/SanaaFacts.swift` (suggestion composition from
facts), `Export/SanaaEdits.swift` (batch assembly rides the FEAT-058 op
kinds), `UI/SanaaActivityController.swift` (proposal receipt copy).

**Behavior.**

- From `get_design_facts` findings, compose a proposed apply_edits batch.
  Each contrast proposal presents BOTH alternatives — the computed
  hue/chroma-preserving value from `ContrastMath.suggestForeground` AND the
  nearest token — each with a one-line tradeoff, and when the culprit is a
  token value used widely, propose **"fix the token, not the instance"**
  (edit the Design Language value) instead of repainting instances.
- Target-size and spacing proposals are version-scoped, never verdicts:
  enlarging to ≥24×24 CSS px **supports SC 2.5.8 (WCAG 2.2 AA)** — beyond
  the WCAG 2.0/2.1 baselines US law references — and the tool cannot
  adjudicate the five exceptions (spacing / equivalent / inline / essential /
  user-agent control), so it reports sizes, never pass/fail; ≥44×44 meets
  **SC 2.5.5 (AAA)**; grid/rhythm spacing is common practice — no WCAG
  criterion sets spacing values. Target-size proposals name any applicable
  2.5.8 exception where relevant.
- **Design-stage vs implementation-stage honesty:** canvas fixes cover only
  what a design file can encode (color, size, spacing). Keyboard behavior,
  focus order, and ARIA semantics live in the Handoff export and
  `docs/SEMANTIC-HTML-CONTRACT.md` — Sanaa must NOT claim canvas fixes for
  implementation-stage criteria and must point at the handoff/contract
  instead.
- Claim copy per §8, value-first and judgment-last: "This pair reads 4.53:1
  — above the 4.5:1 minimum in SC 1.4.3 (large-text rules and unmeasurable
  fills excluded; see Couldn't-assess). Apply, or look at the token
  instead?" — never "ADA compliant"/"accessible now"/unscoped "meets WCAG."
  Automated/design-stage checks catch a subset (the module's coverage
  numbers ride along in the proposal). Suggested fills respect the document
  palette — nearest-token or hue-preserving, never arbitrary hex.

**Testing.** Contrast suggestions round-trip through ContrastMath unit
expectations; the token-culprit case proposes the token edit; proposal copy
passes the claim-pattern lint (the allowed scoped pattern only); both
alternatives appear in every contrast proposal; batches pass the FEAT-058
consent/undo gates unchanged.

**Gotchas.** Suggested colors must respect the palette. Large-text thresholds
depend on the bold heuristic — propose, flag, let the designer confirm. Never
claim whole-document compliance; the `notAssessed` list rides along in every
proposal.

**NOT verified:** nearest-token matching behavior for near-miss palettes
(uses the existing value-matching helper; verify its tolerance at
implementation).

---

### FEAT-060 — Design-quality evaluation harness (v2.5 candidate)

*~2 sessions. NON-mutating. v2.5 candidate. The lite version — golden
documents + golden prompts + hand-reviewed transcripts — is folded into
FEAT-054/055 acceptance and ships with them.*

**Goal.** A repeatable way to answer "is Sanaa actually good at design?"
without lying to ourselves about automation.

**Files (expected).** `scripts/verify_sanaa_design_quality.sh` (matching the
repo's verify-script culture), golden documents + prompts under a scratch
fixtures directory (location owner-adjustable), transcripts written to
session-local output, never committed with real designer content.

**Behavior.**

- The runner drives a fresh agent through the golden set and saves full
  transcripts for owner review.
- Automated checks ONLY for deterministic parts: placement respected (§3
  rules), valid facts JSON (schema + criterion citations present, no verdict
  vocabulary), voice-lint on transcripts (banned words, compliance-claim
  patterns).
- **Aesthetic quality stays a human gate.** The research is explicit about
  why: LLM-judge agreement with humans on design quality tops out around
  **~70%** (WebDevJudge; humans agree with each other ~85%), pairwise
  comparison beats absolute scoring, and position/verbosity biases persist.
  A judge, if ever used, may only nominate candidates for the owner — it
  never grades Sanaa.

**Testing.** The script itself: deterministic checks fail correctly on
doctored transcripts (seeded bad transcripts with verdict words, placement
violations, malformed facts JSON).

**Gotchas.** A green verify run means "behaved," not "good" — the script's
output says so in those words. Transcripts contain designer content; keep
them session-local.

**NOT verified:** nothing aesthetic is claimed automated; the voice-lint is
grep-level and deliberately shallow.

---
