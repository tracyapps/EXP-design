# Sanaa — an optional design assistant on the EXP canvas

*Proposal + chunked implementation plan. Drafted 2026-08-25 from owner direction;
researched against pen.dev and the shipped EXP v2.3 agent bridge.*

**Status: PLANNED, NOT STARTED.** Backlog ids FEAT-048 … FEAT-053 (assigned via
`scripts/verify_backlog_ids.sh` on 2026-08-25). Do NOT begin FEAT-048 until the
owner's Xcode verification pass on the current v2.4 slice (BUG-049…052, FEAT-047,
FEAT-027) is complete — the "no stacked document-mutating slices" rule applies.

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
- **No LLM inside EXP.** Sanaa follows the architecture decision already on the
  roadmap: *agents reach in; EXP never reaches out. No vendor API keys, no fake
  usage bars.* Sanaa is a character, a consent system, and a set of write tools
  on the **existing** agent bridge — the designer's own agent (Claude Code,
  Claude Desktop, Codex, any MCP client, any plan including free) does the
  thinking. §2 explains why this also wins on ease-of-setup.
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
   attacks directly (detect installed agents, one-click setup, packaged
   Claude Desktop extension). pen.dev made the same call.
2. **Physically draws on the canvas like pen.dev:** the drawing IS write-back.
   Edits arrive as tool calls; EXP applies them through the normal undo funnel
   and animates them (FEAT-049). Identical mechanism to pen.dev's desktop app.

**The honest seam (v1):** the designer types/pastes prompts in their agent's
own UI, not in EXP. EXP composes excellent prompts for them (FEAT-050,
one click, ids included). A future in-EXP prompt box via MCP *sampling* is
logged as research in §7 — client support for sampling is uneven
(HYPOTHESIS; verify against the MCP spec and real clients before promising).

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

1. **Handoff panel ▸ Agent ▸ "Allow local agent access"** — exists today
   (read-only bridge). Unchanged.
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
designer's own agent (Claude Code / Desktop / Codex / any MCP client)
        │  stdio                                    ── the "brain"; EXP ships no LLM
   exp-mcp helper (bundled, unchanged)
        │  current-user Unix socket (0600, container path — unchanged)
   AgentSocketServer (unchanged)
        │
   AgentMCPRouter ── read tools (6, shipped) ───────────── unchanged
        │        └─ apply_edits (FEAT-048, gated on §4 switches)
        │                │ validate → decode fragments → placement check
        │                ▼
        │        ExpDocument.setModel(_:undoManager:actionName:)   ← the ONLY write path
        │                │ one call = one undo step "Sanaa: <summary>"
        ▼                ▼
   SanaaActivityController (FEAT-049) → activity feed, canvas highlights,
                                        VoiceOver announcements, avatar (FEAT-052)
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

### FEAT-049 — Presence: activity feed, canvas highlights, announcements

*~2 sessions. Depends on FEAT-048.*

**Goal.** When Sanaa draws, the designer *sees* it happen and can review it —
this is what makes it feel like pen.dev rather than spooky mutation.

**Files.** New `UI/SanaaActivityController.swift` (`@MainActor @Observable`,
app target only) + `UI/SanaaPanelSection.swift` or extension of
`HandoffPanel`; `Canvas/CanvasView.swift` (highlight overlay);
`EXP__design_App.swift` (menu items); `Export/AgentBridge.swift` (one call
into the controller after a successful batch).

**Behavior.**

- Every applied batch records: client name, timestamp, summary, affected ids,
  page. **In-memory, session-scoped** — deliberately NOT persisted (avoids the
  UserDefaults/Codable trap and keeps documents clean).
- Activity feed lists batches ("Sanaa (via Claude Code): 3 variations —
  2:41 PM") with two actions: **Select Sanaa's changes** and **Go there**
  (scroll/zoom to the affected artboards; reuse the Reveal/zoom-to-fit paths).
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

**Testing.** Drive `apply_edits` batches from the socket script while watching:
feed order (newest top), highlight on the right nodes, reduced-motion variant
(System Settings ▸ Accessibility ▸ Display ▸ Reduce motion), VoiceOver
announcement text, menu enablement with/without recorded batches, multi-window
(source editor focused) dispatch, and that disabling Sanaa mid-session clears
the feed and menu items without a relaunch.

---

### FEAT-050 — "Ask Sanaa": prompt starters with placement dialogs

*~1–2 sessions. Depends on FEAT-048 (ids in prompts are only useful if the
agent can act) and pairs with FEAT-049.*

**Goal.** One click turns a selection into a great agent prompt, with the §3
placement question answered by the designer up front.

**Behavior.**

- Right-click on a selection (and Object menu): **Ask Sanaa ▸**
  - *Complete this…* → sheet asks: work directly on this artboard, or on a
    duplicate beside it? (radio, default duplicate — the safe choice)
  - *Draw variations…* → sheet asks: how many (default 3), same page or new
    page? (default new page)
  - *Do repetitive work…* → free-text "what should Sanaa repeat/apply?", notes
    it requires in-place consent.
- Output: a composed prompt on the clipboard (existing `copy` pattern from
  HandoffPanel), e.g.:

  > Using the exp-design MCP server: call get_selection, then get_artboard on
  > the parents, to see what I'm working on. Create 3 VARIATIONS as new
  > artboards via apply_edits with placement kind "newPage" (name the page
  > "Sanaa — <topic> variations"). Use only node ids as references. Keep the
  > document's Design Language tokens (get_tokens) for colors and type.

- The sheet's confirm button reads **"Copy prompt for my agent"** — the seam
  is explicit, never implied to be magic. If no agent is connected, the sheet
  says so and links to setup (FEAT-051).
- Full command coverage per the standing rule (all five wirings; the sheet IS
  the parameter surface, so no separate inspector control is needed — same
  reasoning as align).

**Testing.** Each starter with 0/1/many selected nodes and artboard-only
selections (enablement matrix); paste each prompt into Claude Code against a
scratch document and verify the resulting `apply_edits` batches respect the
chosen placement; VoiceOver labels/hints on the sheets; Escape/Return
behavior; keyboard-only run-through.

---

### FEAT-051 — Setup assistant: Sanaa for non-technical designers

*~1–2 sessions + research spike. Independent of 049/050; needs 048 only to be
worth advertising.*

**Goal.** The owner's criterion #1: someone who has never touched a terminal
can connect an agent.

**Behavior.**

- A guided "Set up Sanaa" flow (from Settings ▸ Sanaa and the Handoff Agent
  section): ① pick your agent → ② one-click or copy-paste setup → ③ "say
  hello" verification (agent calls get_orientation; EXP shows the green
  Connected state it already tracks).
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

**Goal.** Any agent, cold, behaves like a good studio assistant. This slots
into the already-roadmapped (deferred) "agent capability packs" item.

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
- **In-EXP prompt box via MCP sampling** (EXP asks the *connected client* for
  a completion, so prompts could be typed inside EXP with no API keys) —
  research item. HYPOTHESIS: client support for sampling is too uneven to
  build on today. Verify against the MCP spec + Claude Code/Desktop behavior
  before scoping.
- **Multiple simultaneous named agents with cursors** (pen.dev's six-agent
  swarm) — out of scope; the bridge technically accepts multiple clients
  already, and the activity feed names each, which is enough.
- **Sanaa initiating work unprompted** — never. Sanaa only ever acts on a
  tool call from the agent the designer invoked.

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

## 9. Effort summary

| Chunk | What | Est. sessions |
|---|---|---|
| FEAT-048 | apply_edits + consent + settings | 2–3 |
| FEAT-049 | activity feed + highlights + announcements | 2 |
| FEAT-050 | Ask Sanaa starters + placement dialogs | 1–2 |
| FEAT-051 | setup assistant (+ packaging research) | 1–2 |
| FEAT-052 | avatar/character (+ owner asset time) | 1–2 |
| FEAT-053 | capability pack | 1 |
| **Total** | | **8–12** |

A minimal lovable Sanaa (048 + 049 + 050) is roughly **5–7 sessions**; 051–053
turn it from a feature into a companion.
