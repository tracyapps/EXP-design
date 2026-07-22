# v2.0 — Interop & Handoff Plan ("the tool that lets go")

**Created:** 2026-07-14 · **Status:** ACTIVE (v2.0/build 10 opened 2026-07-21;
owner-approved direction: export/handoff first) · **Owner intent:** v2.0's headline. Traditional design
software locks the design in; EXP should hand work onward — to a dev team, an
LLM/agent, an IDE, or CodePen — and read work back in. Artboard notes +
ARIA-role components are the multiplier: the *meaning* travels, not just
pixels.

## Principles
1. **Export is the spine.** We define one neutral, versioned interchange
   package first; every importer targets it and every exporter emits from it.
   No pairwise format-to-format code.
2. **Semantics are the differentiator.** EXP nodes already carry ARIA roles
   (Phase 19a) and structured notes (Phase 6). Exports emit semantic HTML and
   agent-readable intent — not the div-soup other tools produce.
3. **Standards over inventions.** Where a real standard exists, use it:
   W3C DTCG design tokens (stable 2025.10, adopted by Figma/Penpot/Sketch/
   Style Dictionary/Tokens Studio), semantic HTML/CSS, SVG. Invent only the
   package manifest.
4. **Fidelity tiers, honestly labeled.** Every import/export declares what
   survived: geometry / styles / text / components / semantics. No silent loss.
5. **Accessibility is load-bearing:** exported HTML must pass the same
   contrast + role checks the app enforces (Phase 18 contrast tooling reuse).

## What we already have (don't rebuild)
- `.design` IS structured JSON (UTType conforms to `.json`) — the interchange
  format is 80% designed; it needs a documented, versioned public schema.
- Structured artboard notes; ARIA-role component categories; Design Language
  (colors, gradients, categories, TYPE STYLES, contrast math); SVG export;
  SVG importer; PDF import design (exp-pdf-import memory / PDFImporter.swift);
  export renderer with full-res image path.

---

## The spine: EXP Handoff Package (`.exph` — working name, a folder/zip)
```
handoff/
├── manifest.json      ← versions, fidelity report, entry points, tool info
├── design.json        ← the documented .design schema (nodes, notes, roles)
├── tokens.json        ← Design Language as W3C DTCG (colors, gradients, type)
├── html/              ← per-artboard semantic HTML + shared CSS (custom props
│                        from tokens; SCSS source optionally alongside)
├── assets/            ← images (full-res), SVGs per vector node on request
└── README.llm.md      ← agent orientation: what this is, how pieces relate,
                         notes index with anchors back into design.json ids
```
Design decisions to hold: stable node ids across exports (diff-able handoffs);
notes attach to node ids; every HTML element gets `data-exp-id` so agents can
round-trip references. There is no true "agent standard" today — the closest
practice is exactly this: JSON + tokens + semantic HTML + a plain-language
README manifest. If one emerges, we add an emitter, not a rearchitecture.

## Chunks

### Chunk A — Schema + package (v2.0 gate #1)
Formalize `design.json` (schema version field, published JSON Schema doc,
migration policy), build the package writer + manifest + README.llm.md
generator, File ▸ Export ▸ Handoff Package… (command-coverage rule applies).
- Risk: LOW. Mostly documentation + serialization we already do.
- Prep shipped in v1.4: add `schemaVersion` to saves so v1.x files
  self-identify before v2.0 readers exist.

### Chunk B — Semantic HTML/CSS export (v2.0 gate #2, the demo-able one)
Per-artboard HTML: ARIA-role components → real elements (`nav`, `button`,
`main`…), auto-layout groups → flexbox, tokens → CSS custom properties,
type styles → classes, notes → adjacent HTML comments + a notes sidebar in a
preview mode. Optional SCSS emission (tokens as `$vars` + maps).
- Carry the same token semantics into standalone SVG: when a fill or stroke
  exactly matches a Design Language color, export/use that CSS custom property
  with a standalone-safe fallback. Preserve the token relationship through the
  shared interop codec so SVG, HTML/CSS, and handoff output do not diverge.
- Risk: MEDIUM. Layout fidelity for free-positioned nodes (absolute pos
  fallback is honest and fine — this is handoff, not a site builder).
- Depends on A (tokens + ids).

#### Chunk B execution order

The implementation extends `HandoffPackageWriter`; it does not introduce a
second package/export path. CSS ships first. SCSS remains a scope choice after
the CSS contract is proven and must not block the initial vertical slice.

- [x] **B0 — Contract + golden fixture.** Write down the deterministic
  `AriaRole` → HTML element mapping, stable DOM-id and `data-exp-id` rules,
  escaping, artboard ownership, reading/paint order, and fidelity fallbacks.
  Create one representative document/export fixture containing artboard notes,
  free-positioned layers, an auto-layout group, reusable colors/type styles, a
  categorized component instance, a conventional/custom state, and at least one
  typed relationship. DONE 2026-07-21: the written contract, executable contract
  helpers, and headless golden-fixture verifier are in place and passing.
- [x] **B1 — First vertical package slice.** Add `html/styles.css` and one
  sanitized-name HTML file per artboard to `.exph`; include byte counts and
  SHA-256 hashes in `manifest.json`, and update `README.llm.md`. Use absolute
  positioning as the truthful baseline. Every output layer carries
  `data-exp-id`; emitted DOM ids derive deterministically from UUIDs so ARIA
  relationships can target them without relying on mutable names. DONE
  2026-07-21: the package emitter and headless package verifier are implemented
  and passing, including resolved-instance identity and wall-node reporting.
- [x] **B2 — Component semantics and states.** Resolve source instances through
  the existing document machinery; emit native elements when the role has an
  unambiguous HTML equivalent and explicit `role` otherwise. Emit accessible
  names and `aria-controls`/`aria-labelledby`/`aria-describedby`; map
  hover/focus/pressed/disabled to appropriate selectors and custom states to
  `data-state`. Do not generate or persist JavaScript. DONE 2026-07-21: semantic
  hosts, relationships, state CSS, active-state attributes, and structured
  missing-data requirements are implemented and package-tested.
- [x] **B3 — Layout and token fidelity.** Convert auto-layout groups to flexbox;
  reuse Design Language CSS custom-property/type-style generation; resolve exact
  paint matches to `var(--token, fallback)`; carry the identical token lookup
  into standalone SVG output so exporters cannot disagree. DONE 2026-07-22:
  managed stacks emit flex direction/distribution/gap/alignment and fixed flex
  items; exact paints and whole-text styles retain reusable CSS identity; and
  standalone SVG fills/strokes share the same color-token lookup with literal
  fallbacks and correct semi-transparent alpha.
- [ ] **B4 — Semantic closure, verification, and fidelity reporting.**
  - [x] **B4a text content intent:** Plain text, Paragraph, and Heading 1–6 are
    independent from reusable Type Styles. Native tags now export without any
    font/name inference; Heading components inherit an unambiguous authored
    level or keep the `headingLevel` requirement. Inspector/menu authoring,
    tolerant decode, component resolution, and package round-trip checks pass.
  - [ ] **B4b verification:** add deterministic golden comparisons and focused
    exporter smoke coverage.
  Validate browser markup, visual output, keyboard/VoiceOver reading order,
  light/dark and increased contrast, safe escaping, broken relationship targets,
  and unsupported effects. Record every fallback honestly in the manifest rather
  than silently dropping semantics or styling.

### Chunk C — DTCG tokens import/export (v2.0 gate #3)
Design Language ↔ `tokens.json` (DTCG 2025.10): colors, gradients, type
styles both directions. Instantly interops with Figma/Penpot/Style
Dictionary/Tokens Studio ecosystems.
- Risk: LOW-MEDIUM. Mapping gradients + type styles to DTCG's modules;
  color spaces (DTCG supports non-sRGB — we're ahead here with P3 work).
- Independent of B; can parallel.

### Chunk D — Figma import (v2.1)
Path 1 (sanctioned): Figma REST API — file JSON in, map nodes → EXP nodes,
variables → Design Language, images via render endpoints. Requires user's
Figma token; network feature (privacy note in UI).
Path 2 (offline): `.fig` parsing — format is private/unstable; open-source
parsers exist (figma-to-json, Evan Wallace's fig-file-parser) but break with
Figma updates. Ship Path 1 first; Path 2 only as "best-effort, labeled".
- Risk: MEDIUM-HIGH (external API surface, rate limits, huge node-type space).
- Fidelity tiers essential: import report listing what didn't map.

### Chunk E — Code/component import (v2.2)
HTML/CSS prototypes → EXP nodes (parse DOM + computed styles → boxes, text,
images; roles read BACK from semantic tags — the inverse of B, reusing its
mapping table). Then Storybook: crawl a static Storybook build, render each
story, import per-story artboards + extract the args table into notes. React
directly = render-to-DOM first (headless), never AST-to-pixels.
- Risk: HIGH (browser-engine dependency for computed styles — likely WKWebView
  snapshot + JS extraction bridge). Prototype early, scope ruthlessly.

### Chunk F — Agent Bridge: EXP as an MCP server (phased; OPT-IN, off by default)
Direction (owner-approved 2026-07-17): EXP never calls AI vendors itself — no
API keys stored, no usage meters (consumer AI plans expose no usage API; any
such bar would be fabricated). Instead EXP **is** an MCP server. The designer's
own agent — Claude Desktop/Code, ChatGPT Desktop, any MCP client, on whatever
plan they already have including free tiers — connects TO EXP. Usage/limits
display in the agent's own UI (always accurate, zero maintenance for us).
Philosophy fit: AI-averse users never see the feature (single opt-in toggle,
OFF by default, nothing else in their face); "fast intern" users bring the
agent they already trust.

**Transport (stability decision):** stdio, not HTTP. Every MCP client supports
stdio; streamable-HTTP support still varies. Ship a tiny CLI helper
(`exp-mcp`, bundled inside EXP.app/Contents/Helpers/). The agent spawns the
helper; the helper relays JSON-RPC to the running app over a local
Unix-domain socket (`~/Library/Application Support/EXP/agent.sock`, 0600,
current user only — nothing listens on the network). If EXP isn't running or
the toggle is off, the helper answers every request with one clear error
string ("EXP is not running, or agent access is disabled in EXP's Handoff
panel") and never hangs.

**Tool-surface rules (so OLDER/SMALLER agent models succeed, not just
frontier ones):**
- Few tools (≤6 in F1); flat scalar arguments only — no nested option objects.
- Every tool description states exactly what is returned and embeds one
  example call + example response.
- Responses are Chunk A shapes verbatim (design.json fragments, notes, roles,
  DTCG tokens); node ids are the only reference currency, matching the
  `data-exp-id` attributes in Chunk B output.
- Summaries first, detail on demand: `list_*` tools return ids + names +
  roles only (small payloads for small context windows); `get_*` tools return
  full detail for ONE id.
- Orientation text (the README.llm.md content) exposed BOTH as an MCP
  resource and via a `get_orientation` tool, because some clients ignore
  resources.

**Phases (back wiring first; nothing user-facing until the spine is proven):**
- **F1 — spine, ships dark (v2.0):** socket listener in the app + `exp-mcp`
  helper + read-only tools: `get_orientation`, `list_artboards`,
  `get_artboard(id)`, `get_selection`, `get_node(id)`, `get_tokens`.
  Enabled only via a hidden `defaults write` flag; exercised by us + testers.
  Risk: LOW-MEDIUM (socket + serialization plumbing; zero new model code).
- **F2 — the Handoff panel (v2.1; name DECIDED 2026-07-17):** ONE panel for
  every way work leaves EXP — not an "AI panel." Sections:
  (1) **Export** — PNG/PDF/SVG for the current selection/artboards. Moving
  these here is ADDITIVE: File ▸ Export menu items + ⇧⌘E remain per the
  command-coverage rule; the panel is a surface, never the only path.
  (2) **Package** — Handoff Package (Chunk A), semantic HTML (B), DTCG
  tokens (C) as they ship.
  (3) **Agent** — if none connected: the opt-in toggle (default OFF) +
  copy-paste setup snippets per agent (Claude Desktop JSON block, Claude
  Code one-liner, generic stdio config) + plain-language privacy copy (the
  socket is local-only; nothing leaves the machine unless YOUR agent sends
  it to its vendor). If connected: client name, read-only badge, and
  send-selection affordance. Users who never enable it just see a clean
  export panel — AI stays invisible unless invited.
  Risk: LOW-MEDIUM (panel plumbing + relocating export UI without
  regressing the existing export panels).
- **F3 — write-back (v2.3+, separate consent):** `apply_changes` (JSON Patch
  against a documented design.json subset), per-session approval prompt in
  EXP, applied as ONE undo group, and an Import-Report-style change summary.
  Reuses Chunk E's HTML→node mapping where applicable. Risk: MEDIUM-HIGH
  (validation, undo integrity, trust UX).
- Depends on Chunk A (stable ids + documented schema). B and C enrich the
  payloads but do not block F1.

### Chunk G — XD import (v2.1, alongside D)
`.xd` is a ZIP: manifest + per-artboard JSON ("agc" artwork trees) +
resources/. Adobe has discontinued XD, so the format is frozen — a stable
target and a genuine "rescue your old files" story. Map artwork tree → EXP
nodes, character styles → type styles, document colors → Design Language;
prototyping/interaction links are recorded into artboard notes (not modeled).
Same `InteropCodec` protocol + Import Report as D/E. No network, no auth —
the right FIRST importer to prove the codec pipeline before Figma's huge API
surface.
- Risk: MEDIUM (undocumented but static; open-source references exist, e.g.
  xd2svg).

### Chunk H — Component states & behavior contract (model work; v1.6, before D/E)
Owner question answered here (2026-07-17): how does interaction data
import/export cleanly? By never storing implementations (no JS in the file) —
EXP stores a three-part **contract**, each part with an exact code mapping:
1. **States (visual):** named states per component definition — hover,
   pressed, focus, disabled, plus custom (open/selected/error…). Modeled as
   override-diffs against the base, the SAME diff structure instances already
   use (proven machinery, one mental model, re-hug engine untouched).
   Export (B): CSS pseudo-classes + `data-state` attributes. Import (E):
   CSS pseudo-classes / Storybook variant args. Figma variants also map here
   (D). Immediate v1.x value with no interop at all: designers can build and
   contrast-check hover/focus states.
2. **Behavior (semantic):** implied by the ARIA role — a `tablist` IS the
   WAI-APG tabs pattern (arrow keys, aria-selected, panel switching); no
   prototyping arrows, nothing to draw. One model addition: typed node
   **relationships** (`controls`, `labelledby`, `describedby`) so "this tab
   shows that panel" is an id→id link, not prose. Export: real ARIA
   attributes; devs/agents regenerate behavior from the public APG pattern.
   Import: read the same attributes back. Artboard/component notes remain the
   free-prose escape hatch for bespoke behavior.
3. **Motion:** DTCG has `duration`, `cubicBezier`, and composite `transition`
   token types — motion tokens ride Chunk C's pipeline; a state may reference
   the transition token used to enter it.
The JS never round-trips — by design. It is regenerated from the contract on
every export, so behavior can't rot inside the design file.

**Model additions:** `states: {name → override-diff}` on component
definitions; `relationships: [{type, targetId}]` on nodes; a "public prop"
flag on overridable fields so codegen emits a props table (Storybook args map
onto it in E). Schema bump + migration (schemaVersion machinery already
shipped in v1.4).

**Components panel redesign rides this chunk:** grid view with thumbnail
previews (existing ROADMAP candidate — mind the EXPThumbnail
target-membership gotcha), a state-preview switcher per component, and — once
E lands — library sync status + per-component Import Reports live here too.
Inspector: state picker + relationship picker (command-coverage rule applies
to all new actions).
- Risk: MEDIUM (model + migration + inspector/panel UI) but ZERO external
  dependencies — ideal v1.x work. Makes B's export dramatically richer and is
  the prerequisite for E's sync; D benefits (variants → states).

### Cross-cutting
- `InteropCodec` protocol (read/write, fidelity report, progress, cancel) so
  importers/exporters are peers; unit corpus of golden files per format.
- Every importer produces a visible **Import Report** (what mapped, what
  didn't, where notes landed) — honesty principle, and it doubles as our
  debugging tool.

## Release mapping
- **v1.4 (patch/minor):** perf fix + `schemaVersion` in saves + first real
  Sparkle update proof from v1.3.
- **v1.5 (prep release):** Chunk A + C. Quietly ships the spine; marketing
  can call it "your design language, everywhere."
- **v1.6 (component contract):** Chunk H — states, relationships, public
  props + the components-panel grid/state-preview redesign. Pure model/UI
  work, no interop deps; everything after it exports/imports richer data.
- **v2.0 (headline):** Chunk B (+ A/C polish) = "Handoff Package". The demo:
  design with notes + roles → one export → open in browser / hand to an agent
  / drop in an IDE, everything labeled and semantic. F1 (agent-bridge spine)
  rides along dark — no UI, hidden flag only.
- **v2.1:** Chunk D (Figma import) + Chunk G (XD import) + F2 (the Handoff
  panel — unified export/package/agent surface). **v2.2:** Chunk E
  (code/Storybook import).
- **v2.3+:** F3 (agent write-back, separate consent + undo-safe).

## Open decisions (owner)
- [x] Package name/extension — DECIDED/SHIPPED (v1.5): inspectable `.exph`
      folder. The single `.design` file remains the native document, not a
      second handoff-package mode.
- [ ] SCSS emission in B: v2.0 or fast-follow?
- [ ] Figma import auth UX (token paste vs OAuth) — privacy stance to write
      down before building.
- [ ] F: helper distribution — is spawn-from-app-bundle path enough for all
      target agents, or also offer an npx-style shim? (verify with Claude
      Desktop + Claude Code first)
- [x] F: user-facing name — DECIDED (owner, 2026-07-17): **Handoff**. One
      panel for everything leaving EXP (exports, packages, agent); with no
      agent connected it is simply the export hub, so AI is never in
      anyone's face. Agent section appears as one collapsed, opt-in section.
- [ ] G: XD prototyping links land in notes only — acceptable, or flag in the
      Import Report too? (Revisit after H: simple trigger→target links could
      map to H relationships instead of prose.)
- [x] H state vocabulary — DECIDED/SHIPPED (v1.6): conventional names first
      plus free-form custom states.
- [x] H state scope — DECIDED/SHIPPED (v1.6): components only; artboard/page
      states are not part of the v1.6 contract.
- [x] v2.0 import gate — DECIDED: Chunk C's shipped DTCG token import is the
      honest “back in” path for v2.0; broader document import begins in v2.1.

## Sources (external claims)
- DTCG stable release + adoption: w3.org/community/design-tokens (2025-10-28
  announcement), designtokens.org/tr/drafts/format/
- Figma REST API + .fig status: developers.figma.com/docs/rest-api/,
  github.com/figma/rest-api-spec, github.com/yagudaev/figma-to-json,
  madebyevan.com/figma/fig-file-parser/
- MCP spec + transports (stdio universal; HTTP support varies by client):
  modelcontextprotocol.io/docs
- XD discontinued / .xd = ZIP of JSON: Adobe XD EOL announcements;
  github.com/L2jLiga/xd2svg (format reference)
- No public usage/limits API for consumer Claude/ChatGPT plans (as of
  2026-07-17): rate-limit headers exist for paid API keys only, per-minute
  not per-week — the reason F shows no usage bars.
