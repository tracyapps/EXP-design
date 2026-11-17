# Design Language — master plan (v2.9 → Pro two-way sync)

Written November 16, 2026 from the owner's direction that day. This is the
**agent-ready plan** for the Design Language track. It extends, and does not
replace, `DESIGN-LANGUAGE-v2.9.md` (the owner's spacing interaction brief, which
stays authoritative for select/link/update/detach behavior) and
`COMPONENT-SYNC-v2.8.md` (library/component sync contract).

Status words used here: **DECIDED** = owner said it. **RECOMMENDED** = this
plan's default, to build on unless the owner changes it. **OPEN** = needs the
owner before the slice that depends on it. Nothing below is shipped unless a
ROADMAP checkbox says so.

## 0. How any agent uses this file

1. Read `CLAUDE.md`, then ROADMAP → "v2.9", then this file's §3 (rules) and the
   one slice in §6 you are about to build. Read the "Seams" list in §2 for that
   slice and **open those files before writing code**; line numbers drift.
2. One document-mutating slice at a time. Build it, run its check script, build
   BOTH schemes (`EXP [design]` and `EXPThumbnail`), write the owner checklist,
   then stop for owner acceptance (ROADMAP sequencing rule).
3. Every user-facing action follows the Command-coverage rule in `CLAUDE.md`.
4. Anything touching ARIA/semantics/accessible names is verified against
   WAI-ARIA 1.2 / APG / WCAG 2.1 AA first, citation in the BACKLOG entry.
5. Hypotheses in this file are marked as such. Check them against source.
6. Update ROADMAP checkboxes + Progress Log at the end of the session.

## 1. What the owner asked for (November 16)

- v2.9 focuses on the design language: work out the interfaces and how tokens
  such as spacing are integrated.
- An **auto-generated visual guide of all tokens** that updates live, exports to
  a **reference page** and a **shareable link**, and includes **copyable code**
  so it serves designers and developers.
- Research other design-language systems; plan how EXP supports **simple and
  complex** design-language imports and management.
- Direction of travel: **full two-way integration** for Pro design teams, so
  **every token type must be supported and editable inside EXP**.

## 1a. Owner decisions (November 16, evening) — these override §9

1. **Mode scope — DECIDED.** One overall document mode, and every artboard has
   its own selector **beside the notes icon** so it sits in the same place
   however long the artboard name is. Model built: `DLModeSet.activeModeID`
   (document) and `Artboard.modeOverrides` (per board).
2. **Token field — DECIDED: option A** ("for sure"): a token button inside the
   number field's trailing edge, the token name on a chip, edges that share a
   token collapsed into one chip. Reference:
   `../mockups/design-language-v2.9/token-field-options.html` (menu contents,
   small/large behavior and the linked/missing/unlinked states are accepted
   as drawn: "everything else looks good").
   **Mode selector position — DECIDED: after the notes icon**, because notes
   expand to the left, so a selector on the right stays clear of an open
   notes panel.
3. **v2.9 size — DECIDED.** Spacing + modes + links + guide ship together. The
   release after is expected to focus on two-way component governance.
4. **Sharing — DECIDED: offer both** the exported file and a hosted link, and
   explore an **"Export to…"** menu of destinations (§7a).
5. **Units — DECIDED: rigid and flexible.** Tokens may be px/rem and also em,
   viewport units, `calc()`, `min()`, `max()`, `clamp()`. Built: `DLLength`.
   Replaces the earlier "relative units cannot bind" rule (§4.1).
6. **Vocabulary — DECIDED: the most universal terms.** token, group, alias,
   mode (DTCG/industry words). Existing "categories" stay as they are: they are
   cross-cutting labels, which is a different thing from a token's group path.
7. **Links — DECIDED.** The by-value gap is to be fixed for **colors and
   typography together**: layers link to saved colors, gradients and type
   styles by identity (slice S5).

## 2. Where EXP is today (verified in source, November 16)

| Area | Today | File |
| --- | --- | --- |
| Colors, gradients | `DesignAsset` (value = `Paint`), categories, notes, tags | `Model/Document.swift` → `DesignLanguage` |
| Type styles | `TypeStyle` (everything except color) | same |
| Library tokens | `LibraryTokenSnapshot` inside a `CodeBridgeManifest` resource; types: color, dimension, duration, fontFamily, fontWeight, number, shadow, expression, unknown; modes `base/light/dark`; aliases kept. Colors are adopted as assets; **everything else is read-only** | `Model/LibraryTokenSync.swift` |
| Layer ↔ color link | **None by identity.** A layer stores a `Paint` value; the picker finds a saved color by value match (`firstAsset(matching:)`). Editing a saved color does not update layers | `Document.swift`, `Color/PaintEditor.swift` |
| Layer ↔ type style link | None by identity (value match in export only) | `Color/DesignLanguageIO.swift` |
| Spacing fields | `AutoLayout.gap`, `AutoPadding.padding*/margin*` as plain `CGFloat` | `Document.swift`; UI in `UI/MainWindow.swift` (`alGapBinding`, `apPadBinding`, `EXPEdgeField`) |
| Import/export | DTCG (colors, gradients, typography), CSS, SCSS, palette text, Sketch palette | `Color/DesignLanguageIO.swift` |
| DL surfaces | Panel, Settings editor, transfer sheet, saved-color editor | `UI/DesignLanguagePanel.swift`, `UI/DesignLanguageSettings.swift`, `UI/DesignLanguageTransfer.swift`, `UI/DLSavedColorEditor.swift` |

Consequences that shape the plan:

- "Color modes that apply predictably to linked colors" (FEAT-088) needs a real
  layer→color link first. That link does not exist yet.
- Spacing tokens (FEAT-089) need a first-class editable non-color token. The
  only non-color tokens today are read-only library rows.
- So both features need the same two foundations: **an editable token model**
  and **a binding model**. Build those once (§4), then both features and the
  guide sit on top.

## 3. Architecture rules (load-bearing; do not relitigate per slice)

- **R1 — Materialized value + binding.** A bound property keeps its resolved
  value in the existing field (`gap = 16`) and records the link separately.
  Rendering, reflow, thumbnails, exporters and older app versions keep reading
  the plain value. A binding is metadata plus one propagation pass. This is why
  a missing or deleted token can never break artwork: the last value is already
  there. (Same shape as Figma's `boundVariables`.)
- **R2 — Bind by stable identity.** Token `UUID` inside the document; library
  tokens also carry their external ID (`css:--space-md`, `dtcg:space.md`).
  Renames never break links.
- **R3 — One propagation function.** `Document.applyTokenBindings()` is pure and
  idempotent: for every binding, resolve token → value in the active mode →
  write the field if different. A token edit, a mode switch and a library
  refresh all call it inside the SAME model transaction, followed by the
  existing reflow, so each is one undo step.
- **R4 — Bindings live on the node** in `Node.tokenBindings: [String: UUID]`,
  keyed by documented property paths (§4.3). They copy/paste, duplicate and
  nest with the node. Unknown keys are preserved, never dropped.
- **R5 — Type vs role.** A token has a DTCG **type** (what the value is) and an
  EXP **role** (what it is for). "Spacing" is a role of a `dimension`, like
  radius or border width. Pickers filter by role (Figma calls this scoping).
- **R6 — Never flatten, never invent.** Aliases stay aliases. Values EXP cannot
  represent (`clamp()`, `color-mix()`, `%`, `vw`) are preserved verbatim, shown
  as not bindable, and exported unchanged. Carried over from FEAT-082.
- **R7 — Tolerant, hand-written Codable** for every new type; unknown enum
  values decode to a preserved raw case. New shared types go in
  `Document.swift` (member of both targets) unless a new file is added to BOTH
  targets in the same change.
- **R8 — No schema bump for additive fields.** v2.8 shows its newer-version
  warning for build-20 files. If an older build re-saves, links are lost but
  every value survives (R1). Record this in release notes; do not claim more.
- **R9 — One renderer for the guide.** The in-app guide and the exported page
  are the same HTML template fed the same JSON, and copyable code comes from the
  same formatter the file exports use. What the designer sees is what ships.
- **R10 — Free vs Pro** (owner, October 22): every token type, editing, modes,
  imports, the guide and its export are free. Pro is collaboration: history,
  branches/PRs, review, roles, governed sites.

## 4. Target model

### 4.1 Tokens

Keep `DesignAsset` and `TypeStyle` exactly as they are (no migration risk).
Add editable generic tokens beside them, and one read-only **unified view** so
the guide, pickers and exporters see a single list.

```
DesignLanguage
  categories   [DLCategory]        existing
  assets       [DesignAsset]       existing: color + gradient tokens (+ modeValues, §4.2)
  typeStyles   [TypeStyle]         existing: typography tokens
  tokens       [DLToken]           NEW: every other token type
  modeSets     [DLModeSet]         NEW (§4.2)
  settings     DLSettings          NEW: remBase (default 16)

DLToken
  id UUID · name · group path ("space/inset") · categoryID?
  type   DLTokenType     dimension, number, duration, fontFamily, fontWeight,
                         cubicBezier, strokeStyle, border, shadow, transition,
                         string, boolean (+ preserved unknown raw)
  role   DLTokenRole     spacing, sizing, radius, borderWidth, opacity, zIndex,
                         breakpoint, fontSize, lineHeight, letterSpacing,
                         duration, easing, elevation, generic
  value  DLTokenValue    literal, or alias(UUID), or raw(String) preserved
  modeValues [modeID: DLTokenValue]   sparse; missing = base value
  notes · deprecated (Bool/reason) · externalID? · extensions (preserved)
```

Unit resolution to canvas points (**DECIDED November 16, built as `DLLength`**):
every token resolves in a `DLResolveContext` — the active modes plus the sizes
relative units measure against.

| Authored | Resolves against | Notes |
| --- | --- | --- |
| `px`, `pt`, `pc`, `in`, `cm`, `mm`, `q`, unitless | nothing | fixed |
| `rem` | `settings.remBase` (default 16) | |
| `em` | context `emBase`, else the rem base | EXP groups have no font size to inherit; text-bound surfaces (FEAT-093) should pass the layer's font size |
| `vw`, `vh`, `vmin`, `vmax` (+ s/l/d and `vi`/`vb`) | the layer's **artboard** size | the same token can be 16 on a phone board and 30 on a desktop board; no artboard (wall, component source) = does not resolve |
| `%` | context `percentBase` | no v2.9 surface defines one yet, so `%` does not resolve |
| `calc()`, `min()`, `max()`, `clamp()` | evaluated, nesting allowed | like-with-like addition, as CSS requires |
| `minmax()`, `var()`, `fr`, `ch`, `fit-content()`, anything else | — | preserved verbatim, shown disabled with the reason in words |

A value that cannot be measured where the layer sits never changes the field:
the layer keeps its last number (R1). The authored text is always what exports.
**Call-site duty for S3/S4:** resizing an artboard, moving a layer to another
artboard, and switching a mode must each call `applyTokenBindings()` in the same
transaction. **Limit:** a viewport-relative token inside a component source
does not resolve, because one source serves placements on different boards.

### 4.2 Modes

- `DLModeSet { id, name, modes: [DLMode{id,name}], defaultModeID }`. v2.9 ships
  the UI for **one** set (seeded "Color scheme": Light, Dark on first use, both
  renameable, more modes addable). The model is an array so a second axis
  (density, brand) later needs no migration. This matches DTCG resolver
  "modifiers/contexts" and Figma "collections/modes" closely enough to import
  and export both.
- Values are sparse per mode with fallback to base, so a token defined once is
  valid in every mode.
- Active mode (**RECOMMENDED, OPEN-1**): a document default plus an optional
  per-artboard override, so light and dark artboards can sit side by side and
  export correctly. Document modes are independent of the app's own appearance.
- Imported `dark` values already preserved by FEAT-082 become real mode values
  on first open of the mode UI, as one explicit, undoable "Adopt library modes".

### 4.3 Bindings

`Node.tokenBindings` keys (string constants in one enum, `TokenBindingKey`):

| Key | Field | Token | Release |
| --- | --- | --- | --- |
| `autoLayout.gap` | `AutoLayout.gap` (packed only) | dimension/spacing | v2.9 |
| `autoPadding.paddingTop/Right/Bottom/Left` | `AutoPadding` | dimension/spacing | v2.9 |
| `autoPadding.marginTop/Right/Bottom/Left` | `AutoPadding` | dimension/spacing | v2.9 |
| `fill`, `stroke`, `autoPadding.fill`, `autoPadding.stroke` | `Paint` | color/gradient asset | v2.9 (needed for modes) |
| `cornerRadius` (+ per corner), `strokeWidth`, `opacity`, `width`, `height` | numeric | dimension/number by role | next |
| `effects` | `[Effect]` | shadow | next |
| `text.style` | `TextContent` | typography (`TypeStyle`) | next |
| gradient stops, text run color, artboard background, layout grid | — | — | later, after survey |

Link/detach behavior is exactly the table in `DESIGN-LANGUAGE-v2.9.md`.
Additions this plan settles (**RECOMMENDED**):

- **Delete a token that is in use:** confirm with the use count; on confirm,
  remove the token and its bindings in one undo step; values stay.
- **Binding to a token that no longer exists** (external edit, refresh): value
  stays, the selector shows "Missing token" with Relink… and Clear. Named in
  text and icon, not color alone.
- **Existing documents are never auto-linked.** An explicit Design Language ▸
  "Link Matching Colors…" previews exact value matches and links on confirm.
- **Seam to audit before S3:** any code that rebuilds a `Node` from scratch
  with `Node(…)` instead of copying and mutating (group/ungroup, boolean ops,
  paste, importers, `ComponentStateEditing.capture`) silently drops
  `tokenBindings`. List the sites and decide per site: carry, or drop on purpose.
- **HYPOTHESIS to verify before S3:** component instance overrides and
  `ComponentState` diffs may need a rule for a bound field that an override
  changes (expected: the override detaches that field in that instance only).
  Read `Document.resolvedChildren` and the override model first.

## 5. Interfaces to work out (owner is the designer here)

Proposed starting points. Each is **OPEN** until the owner reacts; mockups in
`../mockups/` before code, per "design the interface first, don't tack on".

1. **Token field (OPEN-2).** Keep the number field. Add a small token button at
   its trailing edge (menu of tokens for that role, None, Manage…). When linked,
   show the token name as a chip under/inside the field with the resolved value
   still visible. For the four-edge padding/margin group, one "all sides" token
   control plus per-edge buttons, mirroring the existing unified/per-side
   editing. VoiceOver name: "Top padding, 16, linked to Space Medium".
2. **Design Language panel.** Add sections after Colors/Gradients/Type: Spacing,
   then (later) Sizing, Radius, Borders, Shadows, Motion, Other. Spacing rows
   show a proportional bar + name + value + use count. Same create/rename/
   delete/reorder/category actions as colors; Settings editor gets parity.
3. **Mode control.** A mode switcher in the panel header (shows which mode the
   swatches display and edit) and an artboard-level "Mode" control in the
   Inspector. Saved-color editor gains one value per mode with a clear
   "same as Light" state.
4. **Guide window** (§7): toolbar with mode switcher, search, code-format
   picker, Export…, Share….
5. **Import review.** One sheet for every source: what was found, counts by
   type, what maps, what is preserved read-only and why, name collisions.
   Extends the FEAT-082 preview.

## 6. Slices

v2.9 (**RECOMMENDED scope, OPEN-3**: S1–S7; S7 can move to v2.10 if the
release gets long). Each is one owner-verified step.

| # | ID | Slice | Mutates documents | Check |
| --- | --- | --- | --- | --- |
| S1 | FEAT-090a | Token + binding model, resolver, propagation; no UI | model only, additive | `verify_design_tokens.sh` |
| S2 | FEAT-089a | Spacing tokens in the DL panel + Settings editor | yes | checklist |
| S3 | FEAT-089b | Token fields on gap/padding/margin; link, detach, missing, delete | yes | script + checklist |
| S4 | FEAT-088a | Mode sets, per-mode color values, adopt library modes, active mode | yes | script + checklist |
| S5 | FEAT-088b | Color, gradient AND type-style links by identity; Link Matching Styles; mode switch repaints | yes | script + checklist |
| S6 | FEAT-091a | Guide: data builder + template + live in-app window | no | script + AT pass |
| S7 | FEAT-091b | Guide export (single HTML) + copyable code + token file downloads | no | script + checklist |

After v2.9, in dependency order:

- **FEAT-090b — full type coverage, editable:** radius, sizing, border width,
  opacity, z-index, breakpoints, duration, easing, font family/weight, shadow,
  border, transition, string, boolean. Each type = editor row + guide section +
  export + binding surface where one exists.
- **FEAT-093 — bindings beyond spacing** (table in §4.3) and type-style links.
- **FEAT-094 — aliases, tiers and structure:** create/edit aliases in EXP,
  nested groups, primitive → semantic → component tiers as a convention the UI
  understands (tier filter, "semantic tokens must alias" lint as advice, not a
  wall), scopes/roles editing, deprecation with replacement pointer.
- **FEAT-095 — import adapters** (§8).
- **FEAT-096 — standards-complete export** (§8).
- **FEAT-092 — share link** for the guide (hosted; own consent/privacy gate).
- **FEAT-083–085, 087** — component contracts, changesets, refresh, Storybook
  args (existing queue). Components then appear in the guide.
- **FEAT-086 — Pro:** two-way sync with history, branches/PRs, review, roles,
  and the governed design-language site (versions side by side, public and
  role-based views). The guide (S6/S7) is that site's free single-file seed.

### S1 detail — FEAT-090a (no UI)

- Add to `Document.swift`: `DLToken`, `DLTokenType`, `DLTokenRole`,
  `DLTokenValue`, `DLDimension`, `DLModeSet`, `DLMode`, `DLSettings`;
  `DesignLanguage.tokens/modeSets/settings` with tolerant decode and
  encode-only-when-non-empty; `Node.tokenBindings` (same rule).
- Add `TokenBindingKey`, `DesignLanguage.resolvedNumber(_:modeID:)` (alias
  chain with cycle guard, unit rule §4.1), and
  `Document.applyTokenBindings()` → returns whether anything changed; walks top
  level nodes, nested groups and component sources.
- Mutations: add/rename/setValue/remove token (remove also strips bindings).
- `scripts/DesignTokensCheck.swift` + `scripts/verify_design_tokens.sh`
  (pattern: `verify_library_token_sync.sh`). Must prove: old file decodes and
  re-encodes byte-compatible in shape (no new keys when unused); round trip
  with tokens/bindings; Medium 16→20 updates gap and padding; detach leaves the
  number; rename keeps the link; delete strips links and keeps values; alias
  chain and cycle; rem resolution; unsupported unit refuses to resolve; missing
  token leaves value untouched; idempotence (second pass changes nothing).
- Acceptance: script passes, both schemes build, existing verify scripts pass,
  a v2.8 document opens visually unchanged and saves without new keys.
- **Built November 16.** As built: `Node.tokenBindings` is an OPTIONAL
  dictionary (nil when empty) so the synthesized `Node` encoder omits it;
  `DesignLanguage` gained a hand-written `encode(to:)`; token values use a
  one-key object on disk and unknown shapes ride through as `.preserved`.
  `Document.setTokenValue(_:to:modeID:activeModeID:)` and
  `Document.removeToken(_:)` are the transaction-level entry points S2/S3 call.
  Nothing in the app calls any of this yet: there is no UI and no behavior
  change. Receipt: Progress Log, November 16.
- **Extended the same evening (owner decisions 1 and 5):** `DLLength`
  (flexible CSS lengths), `DLResolveContext`, `DLModeSet.activeModeID`,
  `Artboard.modeOverrides`, and `applyTokenBindings()` now resolves each layer
  in its own artboard's modes and size. `applyTokenBindings(modeID:)` no longer
  exists. The check script is at 20 checks.

### S2 — FEAT-089a: OWNER-VERIFIED November 17 (S1 with it)

Follow-ups from that review, built November 17 and awaiting the owner's check:
blank-state **Add New** menu in the panel; a Spacing group in Settings ▸
Design Language (`DLSpacingSettingsGroup`, so "Settings-editor parity" below is
now built); the app "Design Tokens" settings pane removed, with Accent moved to
General and Text box trim to Canvas. Note: the text-box-trim preference is read
only by its own diagram today; it changes nothing else.

### S2 as built — FEAT-089a (November 16)

- `Canvas/CanvasTokenActions.swift`: `newSpacingTokenAction:`,
  `editSpacingTokenAction:`, `deleteSpacingTokenAction:` (one name + value
  sheet; delete confirms with the use count when anything is linked).
- `UI/DesignLanguageSpacing.swift`: `DLSpacingSection` in the panel after Type
  Styles — true-size bar, name, authored value · resolved number, use count.
  Rows are buttons (click or Return edits); context menu Edit / Copy Name /
  Copy Value / Delete. Use counts come from one document walk and are not
  recomputed while a mouse button is down.
- Object ▸ Frame ▸ New Spacing Token…; the panel's empty state has the same
  button. Model: `DLTokenValue.parsingLength`, `authoredText`,
  `Document.tokenUseCounts()`.
- Not built: Settings-editor parity, reordering, categories/groups on tokens,
  duplicate. Not verified by a person: layout at narrow panel widths, larger
  text, VoiceOver reading, light/dark. Tokens cannot be linked to anything
  until S3, so every use count reads "unused" for now.

**S2 owner verification**
1. Design Language panel → **Spacing** → **+**. Create "md" = `16`. A row
   appears with a 16-point bar and "16px".
2. Create "fluid" = `clamp(1rem, 2vw, 2rem)` and "em" = `1.5em`. "em" shows
   `1.5em · 24`; "fluid" shows the expression with a grey bar (no artboard to
   measure against in the panel).
3. Click the "md" row, change the value to `1rem`, Save: row reads `1rem · 16`.
   Undo and Redo restore each state.
4. Right-click a row → Delete: it goes without a prompt (nothing linked yet).
   Undo brings it back.
5. Object ▸ Frame ▸ New Spacing Token… opens the same sheet with the panel
   closed or focused elsewhere.
6. New empty document: the panel's empty state offers New Spacing Token….
7. Save, close, reopen: tokens are unchanged. A document with no tokens saves
   exactly as before.
8. Tab through the sheet and the rows with the keyboard; with VoiceOver a row
   reads name, "spacing token", value, resolved number and uses.

### S3 — FEAT-089b: OWNER-VERIFIED November 17

Follow-up built the same day, awaiting the owner's check: **commit-time
reconcile.** `ExpDocument.setModel` and `registerUndo(restoring:)` (the two
funnels every edit ends in) call `Document.reconcileTokenBindings(after:)`.
A linked field that no longer matches its token is re-resolved when its number
is unchanged since the previous state (the context moved: artboard resized,
layer moved boards, mode switched) and is DETACHED when the number itself was
changed (scaled, set by an agent, any path that isn't the Inspector). Undo and
redo are exempt. Free when the document has no tokens; otherwise two tree walks
per commit. During a live drag the value settles at mouse-up, not per event.
This closes the first "known gap" below.

### S3 as built — FEAT-089b (November 17)

- `UI/InspectorControls.swift`: `EXPTokenButton` (menu at the field's trailing
  edge; glyph is … unlinked, link when linked, warning triangle when the token
  is missing), `EXPTokenChip`, and `EXPEdgeField(token:)`.
- `UI/MainWindow.swift` → "Spacing tokens on gap / padding / margin":
  `spacingTokenChoices()` (built once per control group), `setSpacingToken`,
  `commitSpacingNumber` (detach on a different number; unchanged or
  rounded-display commits keep the link), `spacingChips`.
- The button appears only when the document has spacing tokens or the field is
  already linked, so documents without tokens look exactly as before.
- Tokens resolve for the selected layer's artboard (modes + size).
- **Differences from the mockup:** the button sits beside the field rather than
  inside its border; the menu is a native menu, so there is no filter field for
  large design languages yet (groups show as menu sections).
- **Known gaps (not built):** resizing an artboard, moving a layer to another
  artboard, and switching modes do not yet re-resolve linked fields (a token
  edit does); multi-selection; the `Node(…)` rebuild audit; whether a link set
  while editing a component STATE survives `ComponentStateEditing.capture`;
  copy/paste across documents carries a link to a token the other document
  doesn't have (it will show as Missing).

**S3 owner verification**
1. With spacing tokens "sm" = 8 and "md" = 16: select a group with Auto Layout
   (Gap mode). A small … button sits beside the Gap field. Choose md: the field
   reads 16, the button becomes a link glyph, a chip names the token.
2. Add Auto Padding; link Top and Bottom padding to sm: one chip "T, B · sm".
3. Edit md to 20 (panel or Settings): the gap becomes 20 and the layout reflows.
   Undo restores value and layout in one step.
4. Type 18 in the Gap field: the chip disappears, the button returns to …;
   padding stays linked. Edit md again: the gap stays 18.
5. Click into a linked field and press Return or Tab without changing it: the
   link stays. Escape mid-edit: the link stays.
6. Choose None on a linked field: the number stays, the link clears.
7. Delete "sm" (confirm dialog names 2 linked properties): padding keeps 8, no
   chips. Undo: links return.
8. A token "fluid" = `clamp(1rem, 2vw, 2rem)`: on a layer inside an artboard it
   is selectable and shows its resolved number; on a wall layer it is listed
   disabled with "can't be measured here".
9. Save, close, reopen: links, chips and values are unchanged.
10. A document with no spacing tokens: the Inspector looks exactly as in v2.8.
11. VoiceOver on a linked field: "Top padding, linked to sm"; on the button:
    "Top padding token: sm". Check the narrow Inspector width and larger text.

## 7. The Design Language Guide (FEAT-091/092)

**What it is:** a generated, always-current reference of every token in the
document. It is documentation, not a canvas artifact, so it is HTML.

- **Pipeline (R9):** `GuideBuilder` (pure Swift: `Document` → JSON) →
  one bundled template (plain semantic HTML + CSS + a small vanilla script; no
  framework, no network requests, no tracking) → shown in a `WKWebView` window
  and written to disk on export. The template is ordinary HTML/CSS the owner can
  restyle directly.
- **Live:** the window observes the document; on change it rebuilds JSON off the
  per-keystroke path (debounced; `ExpDocument.model` is `@Published`, so never
  rebuild per event — see `PERF-HANDOFF.md`) and calls the page's `update(json)`. Scroll
  position and open sections persist.
- **Sections:** overview (name, modes, counts, source libraries + revisions) ·
  colors by category with every mode side by side and WCAG contrast against
  paired colors (reuse `ContrastMath`) · gradients · typography specimens ·
  spacing scale · sizing · radius · borders · shadows · motion · other ·
  preserved/unsupported tokens with the reason · (later) components.
- **Every token row:** name, group, value per mode, alias chain ("→ blue/600"),
  role, notes, deprecated state, use count in this document, and **copy
  buttons**: CSS `var(--space-md)`, SCSS `$space-md`, DTCG reference
  `{space.md}`, raw value. A page-level format picker sets the default.
  Whole-set downloads: `tokens.css`, `_tokens.scss`, `tokens.json` (+
  `tokens.resolver.json` when modes exist). Names come from the same code the
  file exporters use (`DesignLanguageIO.libraryVariableName` / `slug`).
- **Export:** File ▸ Export ▸ Design Language Guide… → one self-contained
  `.html` (data inlined, works offline and from any static host), with a print
  stylesheet for PDF.
- **Sharing — DECIDED November 16: both.** The exported file and a hosted
  link are both offered, plus the destinations in §7a.
- **Share link (FEAT-092):** uploads that same file to an
  unlisted EXP-hosted URL. Requires its own gate like every hosted feature
  here: explicit consent naming exactly what is uploaded, revoke/delete,
  expiry choice, no analytics on viewers, account requirement stated up front.
  "Live" for a shared link means re-publishing to the same URL; it is not a
  live socket. Until then the exported file is the shareable thing.
- **Accessibility requirements (verify against spec before coding, record
  citations in FEAT-091):** headings and landmarks; data in real tables with
  header cells; color never the only carrier (name + value text always shown);
  contrast results as text; copy confirmation exposed as a status message
  (WCAG 2.1 SC 4.1.3 — confirm the correct role/pattern in ARIA 1.2 before
  coding); full keyboard operation with visible focus; mode switcher using a
  native control; motion demos only on request and honoring reduced motion;
  page itself meets AA contrast in both of its own themes; reflows at 320 CSS px.

## 7a. "Export to…" destinations (FEAT-097, research November 16)

One menu, many destinations, all fed by the same two artifacts: the guide
(single HTML) and the token files (DTCG JSON, CSS, SCSS). Ordered by how much
is already true in the codebase.

| Destination | How | Status |
| --- | --- | --- |
| File / folder | write the guide + token files | S7 |
| **CodePen** | prefill by form POST of `html`/`css`/`js` JSON; EXP already ships `Export/CodePenPrefillExporter.swift` with a review-then-send launch page. Reuse it: guide page as a Pen, or one token group as a live playground | small slice after S7 |
| **Any static host** (GitHub Pages, Netlify, Vercel, Cloudflare Pages, own server) | the single file needs no build. "Export into a repo folder" lets the team's existing deploy publish it | S7 covers the file; per-host deploy buttons are NOT researched |
| **Git repository** | write tokens + guide into a chosen folder as a normal change the team commits or opens as a PR; shares the `.expsync/changes` idea | pairs with FEAT-084; Pro adds review |
| **Token pipelines** (Tokens Studio, Style Dictionary) | hand them standard token files | FEAT-096 gives the files; direct sync NOT researched |
| **Documentation platforms** (zeroheight, Supernova, Knapsack) | they document systems from Figma, tokens and code; the realistic first step is token-file import on their side | per-vendor import/API support NOT verified — check each vendor's docs before promising |
| **Storybook** | a generated tokens docs page for teams whose docs live there | NOT researched |
| **EXP-hosted link** | FEAT-092 | own consent/privacy gate |
| Team wikis (Notion, Confluence) | paste or embed the hosted link | NOT researched |

Rules: every destination shows exactly what will leave the machine before
anything is sent (the CodePen launcher is the model); nothing uploads without an
explicit action; a destination that needs an account says so first.

## 8. Imports and exports: simple to complex

Research summary (sources at the end). What real systems contain that EXP must
be able to hold:

- **DTCG Format 2025.10** (first stable version): types color, dimension
  (px/rem), fontFamily, fontWeight, duration (ms/s), cubicBezier, number,
  strokeStyle, border, transition, shadow, gradient, typography; aliases by
  `{path}` and JSON Pointer `$ref`; groups with `$type` inheritance, `$extends`,
  `$root`, `$deprecated`, `$description`, `$extensions` (must be preserved).
  Color values are objects (`colorSpace`, `components`, `alpha`, `hex`).
- **DTCG Resolver 2025.10:** `sets`, `modifiers` (each with named `contexts`
  and a `default`), `resolutionOrder`. This is the standard way to express
  light/dark × brand × density without a combinatorial file explosion.
- **Figma variables:** color, number, string, boolean; collections with modes;
  aliases; scoping; extended collections (inherit + override, for brands).
  Figma imports/exports DTCG with `com.figma.*` extensions.
- **Tiering in mature systems** (Material 3 reference/system/component;
  Spectrum, Carbon and others): primitive → semantic → component, where the
  semantic layer is what changes per mode.
- **Common non-standard inputs:** Tokens Studio JSON (sets + `$themes`), Style
  Dictionary source files, Tailwind `@theme` CSS variables, plain CSS custom
  properties, WordPress `theme.json`.

Import ladder (each rung works without the ones above it):

| Level | Source | Status |
| --- | --- | --- |
| 1 Simple | pasted palette / hex list / single CSS file | shipped |
| 2 | CSS custom properties incl. mode selectors, `theme.json`, Tailwind `@theme` | shipped via FEAT-082 parser (Tailwind: verify) |
| 3 | DTCG single file, all types | colors/gradients/type shipped; other types → FEAT-090b/095 |
| 4 | DTCG multi-file + `resolver.json` (sets, modifiers → mode sets) | FEAT-095 |
| 5 | Figma variables (DTCG export with `com.figma` extensions; REST later), Tokens Studio, Style Dictionary | FEAT-095 |
| 6 Complex | library with tokens + components + `.expsync/` mapping, refresh, changesets | FEAT-083–085 |
| 7 Pro | two-way sync with review/merge | FEAT-086 |

Rules for every importer: one review sheet (§5.5); stable IDs so re-import
updates rather than duplicates; designer edits kept and reported; anything
unmapped is preserved and listed; `$extensions` round-trip untouched.

Export targets (FEAT-096): DTCG 2025.10 with every type and the color-object
form, plus `resolver.json` when modes exist; CSS custom properties with modes
(`:root` + mode selectors, optional `prefers-color-scheme`); SCSS variables and
maps; the guide. Each export states what it could not express.

## 9. Open questions for the owner

**All answered November 16 — see §1a.** The original list is kept for the record.

- **OPEN-1 Mode scope:** document default + per-artboard override (recommended),
  or document-wide only for v2.9?
- **OPEN-2 Token field presentation:** trailing token button + name chip
  (recommended) vs a separate dropdown row under each field. Mock both.
- **OPEN-3 v2.9 size:** spacing + modes + guide with export (recommended), or
  ship spacing + modes as v2.9 and the guide as v2.10?
- **OPEN-4 Share link:** EXP-hosted unlisted page behind the account gate
  (recommended, later) vs export-only with "host it anywhere".
- **OPEN-5 rem base:** per-document setting, default 16 (recommended).
- **OPEN-6 Naming in the UI:** "tokens" and "modes" (recommended; matches DTCG
  and what developers say) with existing "categories" kept for grouping.

## 10. Not verified / honest limits

- The instance-override interaction with bindings (§4.3 hypothesis).
- Tailwind `@theme` through the existing CSS parser is expected, not tested.
- DTCG gradient/typography shapes and the Color module were taken from the
  spec's structure; re-read those sections when building FEAT-096.
- No ARIA pattern for the guide is verified yet; that happens in S6.
- Hosted sharing has no design beyond the gate list above.

## Sources

- DTCG Format Module 2025.10 — https://www.designtokens.org/tr/2025.10/format/
- DTCG Resolver Module 2025.10 — https://www.designtokens.org/TR/2025.10/resolver/
- Figma: variables, collections and modes — https://help.figma.com/hc/en-us/articles/14506821864087
- Figma: modes for variables / DTCG import-export — https://help.figma.com/hc/en-us/articles/15343816063383
- Figma REST variable types (extended collections) — https://developers.figma.com/docs/rest-api/variables-types
- Adobe Spectrum design tokens (tiers) — https://spectrum.adobe.com/page/design-tokens
- Terrazzo resolver guide — https://terrazzo.app/docs/guides/resolvers/
