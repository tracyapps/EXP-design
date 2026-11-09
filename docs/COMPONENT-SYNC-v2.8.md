# Component & token sync — v2.8 plan

Owner-selected native v2.8 scope, October 22, 2026; file/format/preview decisions
October 23. Backlog: FEAT-082 → FEAT-087.
**November 9 release disposition:** FEAT-082 token import and the saved-color/
gradient editing follow-ups are built and owner-accepted. The owner requests
shipping that tested slice with the crash fixes now. FEAT-083 has a read-only CEM
reader; document-mutating component contracts, FEAT-084 changesets, FEAT-085 full
revision refresh and FEAT-087 remain future work. The original broader plan below
is retained as a plan, not a claim about shipped capabilities.

Companion docs: Start's
`starttheme/app/public/wp-content/themes/start-2/docs/planning/EXP-INTEGRATION.md`
(the exchange contract this plan implements on the EXP side) and the existing E3 item in
ROADMAP → v2.3 ("provenance-bound code handoff/write-back"), which this plan supersedes
for web components.

## The idea, in one paragraph

Code is the source of truth. A component library (starting with Start + Web Awesome)
syncs **into** EXP as real components and named tokens, a designer changes the design,
and those changes go **back** to the code as a reviewable change. Not as a screenshot,
and not as a regenerated file that overwrites hand-written work. Later, Pro adds the
git-style layer on top: history, branches, pull requests, review and approval, merge
tools and team roles. This was one of EXP's founding reasons: closing the gap between
design teams and engineering teams.

## Owner decisions (October 22, 2026)

1. **v2.8 scope:** tokens + components imported *as components*, with design changes
   exported as a reviewable changeset. No live running component in v2.8. The canvas
   shows a faithful static representation, labeled as static.
2. **Free vs Pro:** nothing a solo designer would use goes behind a paywall.
   - **Free (everyone):** import a library's components and tokens with their real names,
     keep component identity, edit, export a changeset, refresh from a newer library
     revision, and **conflict detection** that refuses to overwrite code.
   - **Pro (agencies/companies):** version history, branches, pull requests, commit
     messages, review/approve/merge, merge-conflict *resolution* tools, rollback, team
     members and permission levels, audit trail.
3. **Generic contract, Start is the first adapter.** Built on public formats that any
   web-component library can produce. Start + Web Awesome Pro is the first tested
   fixture, not a hard-coded special case.
4. Token names come into the **Design Language** natively (universal). Token
   *version/change management* follows the same Pro line as components.

Fits the existing principle (`exp-fidelity-not-prototyping`): component states and
variants are *described handoff data*, never a playback engine.

## Inputs: point EXP at a library, EXP does the work

Owner decision, October 23: the user points EXP at a library (folder, published
Storybook build, package) and it works with **no changes to the library or its tools**.
All discovery, mapping and preview work happens on the EXP side. Per-library settings,
when needed, are made inside EXP and saved as plain JSON, not a plugin the library
has to install.

### What EXP reads, auto-detected in this order

| Source (already in many libraries) | Standard | What EXP gets from it |
| --- | --- | --- |
| `custom-elements.json` | [Custom Elements Manifest](https://github.com/webcomponents/custom-elements-manifest) 1.0.0 | Tags, typed attributes/props + defaults, variants (string-literal unions), slots, events, CSS parts, CSS custom properties, CSS states |
| Token files | [DTCG 2025.10](https://www.designtokens.org/tr/2025.10/format/) | Token paths, types, values, aliases, modes |
| Compiled CSS custom properties, WordPress `theme.json` | (fallback when no token file) | Token names/values and light/dark overrides. EXP already parses CSS variables (`DesignLanguageIO.parseVariables`) |
| The library's built JS/CSS | — | EXP renders each component × variant × state **itself** in its existing sandboxed WebKit capture to get visuals. No fixtures required from the library |
| Published static Storybook build | Storybook `index.json` + `iframe.html` (import already ships) | Alternate visual source; stories as named variants. Reading args/argTypes is FEAT-087 |
| `.expsync/` folder, if present | EXP-owned, open, documented (below) | Saved mapping that overrides auto-detection |

**Verified today:** Web Awesome Pro 3.14.0 ships `dist/custom-elements.json`
(schema 1.0.0, 90 elements). `wa-details` lists 9 attributes, 4 slots, 4 events,
6 CSS parts, 3 CSS custom properties and 1 CSS state, with variants as unions
(`appearance: 'filled' | 'outlined' | 'filled-outlined' | 'plain'`).

**Honest limit:** "works with anything" holds for libraries that *describe themselves*.
Web components with a Custom Elements Manifest, and token files or CSS variables,
cover a large share. React/Vue libraries without a manifest have no standard prop
description outside TypeScript types or Storybook argTypes; that is the FEAT-087
adapter, not v2.8. EXP says which sources it found and which it didn't, and never
invents props.

**The one thing EXP can't safely infer: what may be written back.** Default rule:
writable = tokens from token files/CSS variables, plus CSS custom properties and parts
the manifest documents. Anything else needs a one-time confirmation in EXP's library
settings. That confirmation lives in `.expsync/`, so the library still doesn't change.

### The `.expsync/` folder (decided October 23)

Works like `.git` or `.storybook`: a plain folder committed alongside the library's
code that holds everything linking it to EXP. Every file inside is ordinary `.json`,
so any tool, diff viewer or git host can read it. No custom extension needed for
in-repo use.

```
my-library/
  custom-elements.json        ← the library's own, untouched
  tokens/…                    ← the library's own, untouched
  .expsync/
    expsync.json              ← format version, library ID, sources found, stable IDs
    mapping.json              ← writable vocabulary, token ↔ component bindings,
                                 variant names, optional platform mapping
                                 (wa-details ↔ start/disclosure)
    changes/
      2026-10-23-accent-color.json   ← a changeset (FEAT-084)
```

- Optional: with no `.expsync/`, EXP still imports read-only and offers to create one.
- A changeset is a normal file in a normal folder, so **git itself provides
  versioning**. A changeset can become a commit and a pull request on GitHub or
  Bitbucket. That informs FEAT-086: Pro may lean on the team's existing git host rather
  than inventing a parallel history system (owner decision pending).
- When something must travel *outside* a repo (emailing a changeset to a developer),
  a single-file bundle with a readable extension can be added later (candidate:
  `.expsync`, as a zipped `.expsync/`). Not needed for v2.8.

### Public format (decided October 23)

The `.expsync/` format is **published openly**: documented schema, version number,
labeled *draft* until the Start round trip proves it. Adoption doesn't depend on it,
because EXP builds the mapping itself, but publishing means no lock-in (anyone can
read their own mapping without EXP), library maintainers can review or hand-edit what
EXP writes, and other tools may read it. Changing a draft format stays allowed; the
version number says which one a file uses.

## What EXP already has vs. what's missing

| Area | Exists | Gap for v2.8 |
| --- | --- | --- |
| Provenance | `CodeBridgeManifest` (connector, source, resources, bindings with `observedProperties`/`writableProperties`, baseline) | A `component-library` connector; bindings for tokens and component contracts |
| Tokens | `DesignLanguage`: colors, gradients, type styles. Generic DTCG import/export in `DesignLanguageIO` | Stable external IDs/paths, aliases, modes, dimension/shadow/etc. kinds, preserved unsupported tokens, source names kept for CSS output |
| Components | `ComponentSource`: children, ARIA role, named states as override diffs; nested instances | A **component contract**: typed props, variants, slots, parts, CSS custom props, events (read-only) |
| Static appearance | Rendered HTML/CSS + Storybook static import, WebKit capture | Mapping captured variants/states onto one component source instead of separate artboards |
| Write-back | None (deferred by design) | Changeset export + baseline comparison |

Rule from the Start handoff doc: reuse these structures through an adapter. Do not build
a second, disconnected component system.

## Slices (do in order, owner-verify each before the next)

### FEAT-082: Library tokens in the Design Language (free)
- Import DTCG tokens with stable ID + path (`color.accent`, `space.md`), type, alias
  target, per-mode values (light/dark/system) and origin library/revision.
- The Design Language panel and inspector show the **source token name**. CSS export
  keeps it (`--color-accent`), not a freshly slugged name.
- New token kinds as needed for Start's real set: dimension (spacing, radius), shadow,
  duration, font family/weight. Anything EXP can't represent stays in a preserved block,
  visibly marked **read-only / not editable**, and is never flattened (aliases stay aliases).
- Applying a library token to a layer binds by token ID, so a renamed token stays bound.
- Acceptance: Start's `tokens.css`/`theme.json` set round-trips through import → save →
  reopen with IDs, aliases and dark mode intact. Unsupported values survive untouched.

#### FEAT-082 build notes (October 23, 2026) — built, awaiting owner verification

- Code: `EXP [design]/Model/LibraryTokenSync.swift` (scanner, CSS/theme.json/DTCG
  parsers, alias resolver, adoption, cached read-back); File ▸ **Import Library
  Tokens…** and the Design Language panel's Import/Export menu
  (`CanvasView.importLibraryTokensAction`); panel shows token names, a dark-mode
  corner chip, "alias" marking and a collapsible list of non-color tokens with
  lock icons for read-only values. CSS export uses the exact source variable name
  via a `token:--name` asset tag (`DesignLanguageIO.libraryVariableName`, which
  rejects anything but identifier characters).
- **Older-version save risk: resolved without a schema bump.** The typed snapshot is
  JSON inside a `CodeBridgeResource.preservedData`; token ↔ asset links are plain
  `CodeBridgeBinding`s. `Document.swift` is unchanged since the v2.7 tag, so v2.7
  decodes and re-saves all of it. The selected source files' exact bytes are kept
  too (≤ 4 MB per library) as the FEAT-084 write-back baseline.
- Adoption rules: colors (including aliases, resolved) become Design Language
  assets in a category named after the library; everything else stays with the
  library and is listed read-only. `color-mix()`/`clamp()` etc. are preserved
  verbatim, never flattened. Re-import updates by token ID; designer edits and
  deletions are kept and reported.
- Source selection: DTCG files → CSS custom properties on `:root`/mode selectors →
  theme.json (only when it's the sole source). `node_modules`, `.git`, `vendor`
  are never read; `dist`/`build` only when nothing else exists; symlinks are not
  followed; 400 files / 2 MB per file / 2,000 tokens caps.
- Evidence: `scripts/verify_library_token_sync.sh` — 17 checks pass, including the
  real Start 2.0 theme (27 tokens: 10 colors, 17 others, 12 read-only) and a
  v2.7-field-only reopen. App and EXPThumbnail Debug builds succeed;
  `verify_svg_token_bridge.sh` still passes.
- **Newer-version warning (owner request, Oct 23).** Every save now records the
  writing app (`writtenBy`: version, build, schema). On open, if the file has a
  newer schema, a newer build, or top-level data this build doesn't know, EXP shows
  an Adobe-style warning and offers **Keep a Copy of the Original…**, which writes
  the untouched original bytes (not a re-save). v2.7 and earlier can't show it:
  they predate it. They also don't need it for FEAT-082 data, which v2.7 keeps.
  From v2.8 on, older-version users are warned about anything later versions add.
- Not done in this slice: editing non-color tokens, editing a dark-mode value in
  EXP, writing `.expsync/` into the library, scanning off the main thread (fine
  at the caps above; revisit if large libraries feel slow).

**Owner verification (FEAT-082):**
1. New document → File ▸ Import Library Tokens… → choose the `start-2` theme folder.
   The preview says 27 tokens / 10 colors and names `assets/src/css/tokens.css`.
2. Design Language panel: a **Start 2.0** category with 10 swatches; switch to list
   view and check `color-bg` reads `--color-bg · #F8F6F1 · dark #111820 · alias`;
   swatches with a dark value show a small dark corner chip.
3. Expand **Start 2.0 tokens**: spacing/font/shadow rows with exact names; lock on
   `--color-border`, `--space-section`, `--shadow-soft`.
4. Export ▸ CSS: `--color-accent`, `--color-accent-strong` keep their names.
5. Change `color-accent` in EXP, import the same folder again: the preview says
   your edit to `--color-accent` is kept. Undo works for both imports.
6. Save, close, reopen: everything above is unchanged.
7. VoiceOver on a token row reads name, kind, value and "read-only".
8. Newer-version warning: duplicate a saved `.design`, change its `"schemaVersion"`
   to `7` in a text editor, open it. The warning appears once; **Keep a Copy of the
   Original…** saves an identical file (compare with `cmp`); **Continue** opens it.

### FEAT-083: Components import as components (free)
- Each CEM element the user selects becomes one EXP `ComponentSource` with a
  **contract**: props (typed), variants (from union types or explicit mapping), slots,
  documented parts and CSS custom properties. Events are listed for handoff only.
- EXP renders each variant/state from the library's built files in its sandboxed
  WebKit capture (or reads a static Storybook build). Base = default variant. Other
  variants/states become EXP named states (override diffs), reusing the state model.
- Instances expose props/variants in the inspector. Slot content is editable text/nodes.
- Canvas and inspector say plainly: **"Static representation of `wa-details` from
  Start Components 0.1.0. Behavior runs in code."**
- ARIA role and semantics come from the rendered component's real markup, via the existing
  rendered-import path. Spec-check against WAI-ARIA 1.2 / APG per WORKING-AGREEMENT
  when the contract editor UI is built.
- **Groundwork built Oct 23 (read-only, no document changes):**
  `Model/ComponentManifestReader.swift` reads `custom-elements.json` (found via
  package.json `customElements` or common paths) into contracts: attribute props +
  public fields, kinds (boolean/string/number/enumeration/other), variant axes from
  string-literal unions (ignoring `undefined`/`null`), slots, events, parts, CSS
  custom properties and states. `scripts/verify_component_manifest.sh` passes on a
  synthetic manifest and on Web Awesome Pro 3.14.0 (90 elements; `wa-details`:
  16 props, axes appearance×4 and icon-placement×2, 4 slots, 6 parts, 3 CSS props).
  Creating EXP components from contracts starts after FEAT-082 verification.
- Acceptance: disclosure + service card + contact callout from Start import with all
  variants; instances switch variants; save/reopen preserves contracts and bindings.

### FEAT-084: Changeset out (free)
- Compare the current document against the import baseline. Only the **editable
  vocabulary** counts: token values, documented component CSS custom properties, part
  styles through documented parts, registered variant definitions.
- Export a small JSON changeset tied to the original library revision. Each change has a
  target ID, operation, expected old value/hash, proposed value and a compatibility note.
  Edits outside the vocabulary are listed as **"needs a developer"** items, never
  silently dropped and never guessed into code.
- The changeset is written to `.expsync/changes/`. A library with a build engine
  (Start: plan → review → apply, regenerating CSS/`theme.json`/guide, tracked in Start
  Workbench roadmap §7) applies it automatically; any other library gets a readable
  file a developer applies by hand, or that EXP applies itself for token files/CSS
  variables it can edit safely.
- Free conflict *detection*: a stale or concurrently changed target is refused with a
  clear reason. Resolving conflicts in a UI is Pro (FEAT-086).
- Acceptance: color/spacing/variant edit → changeset → Start applies → WordPress
  frontend/editor/guide match → re-import shows no repeated changes.

### FEAT-085: Refresh from library (free)
- Re-import a newer library revision into an existing document. Updated contracts and
  tokens flow in; the designer's local design edits stay; deleted or renamed-ID items are
  shown for an explicit decision. Same baseline/current/proposed table Start uses.

### FEAT-086: Pro collaboration layer (planned; not v2.8)
- History of accepted changesets (= commits with messages), branches, pull requests,
  review/approve/merge, merge-conflict resolution, rollback, audit trail.
- Roles, from least to most: **viewer** (read only) → **contributor** (read + submit a
  change) → **reviewer** (approve) → **maintainer** (merge, roll back) → **admin** (people
  and permissions).
- **Owner direction, Oct 24: an all-in-one component library + governance site.**
  The fixture comparison page (`spike/component-libraries/compare.html`: two
  versions running live side by side, source and line diff underneath) is the
  seed of the Pro version-compare view. Expand it into a site with a **public
  view** (published components, live previews, usage docs) and **permissioned
  views** by role (submit a change, review/approve, merge, roll back), showing any
  two versions of a component the same way.
- Depends on: Pro offer gate (RELEASE-CHECKLIST-v2.7 → "Pro offer gate"), native
  accounts (FEAT-080) and a hosted or git-provider backend decision. v2.8 designs the
  changeset format so it can later become a commit/PR payload unchanged.

### FEAT-087: Storybook args/argTypes adapter (after FEAT-085)
- Read variants/props from a static Storybook build's args/argTypes so React/Vue/Svelte
  libraries without a Custom Elements Manifest import as components too. Separate
  slice; previously deferred as "full argTypes ingestion."

### Later (v2.9+ candidates)
- Live running component preview: the Start doc's "second slice", a WKWebView
  runtime/interaction-mode spike with locked-down resource trust.

## Model and file-format notes

- Expect a document schema bump (6 → 7). Decode stays tolerant with empty defaults.
- **Known risk:** older EXP decoders ignore unknown fields. If a v2.8 file is opened and
  saved by v2.7, token IDs and component contracts are lost. Decide in FEAT-082 whether
  v2.8 files warn on older-version save, store bridge data in a separately versioned
  block, or both.
- Credentials and Pro vendor source never go inside a `.design` file or a changeset.
  Reference locally installed packages; show "unavailable on this Mac" when missing.
- Nothing in an imported package runs code in v2.8. Fixtures are captured through the
  existing import trust rules.

## Not in v2.8

Live component execution; arbitrary PHP/JS rewriting; structural template edits; event
handler editing; multi-user anything; hosted sync; any Pro feature; automatic writes to a
git branch.

## Round-trip fixture library (built Oct 24)

`spike/component-libraries/`: Button (simple), Card (composite, with Button
children) and Accordion (complex, parent + item children) written seven ways:
HTML + CSS, vanilla Web Components, Lit, React, Vue, Svelte and Angular. Each has a
`working/` copy for EXP and a never-edited `control/`. `npm run serve` opens the
comparison page; `npm run verify | reset | rebuild` work from the command line.
Every format and copy renders in Chromium in light and dark, with the accordion's
APG roles/relationships and Enter toggling checked automatically (84 renders, no
failures). The FEAT-082 token check reads 27 tokens / 13 colors from a fixture;
the manifest reader reads 4 elements from the Web Components and Lit manifests.
Screen readers not tested. Details: `spike/component-libraries/README.md`.

## Verification fixtures (shared with Start)

From the Start handoff doc: semantic tokens with aliases/modes; service card,
disclosure and a nested pattern; one unsupported extension; renamed labels with stable
IDs; changed/deleted tokens; locally modified code; stale export revision; missing
dependency; denied remote asset; malformed/oversized package; an older `.design` opened
and saved by supported EXP versions. Each fixture records expected preservation,
editability and conflict outcome.

Done for v2.8 = a real design change survives **Start → EXP → changeset → Start apply →
WordPress frontend/editor/guide → EXP again** with no lost edits and no changed behavior.

## Decisions log

- **Oct 22:** scope, free/Pro line, generic contract (see top).
- **Oct 23, files:** `.expsync/` folder of plain `.json`, committed with the library;
  single-file bundle extension deferred.
- **Oct 23, format:** published openly, versioned, labeled draft.
- **Oct 23, previews:** EXP discovers sources and renders previews itself; libraries
  need no changes. Per-library settings live in `.expsync/`.
- **Oct 23, first test set:** disclosure (states/styles), button (variants/sizes),
  service card (slots + nested button), contact callout (token-heavy). Button and
  service card blocks are Start-side work (Workbench roadmap §3).

## Still open

- Whether FEAT-086 (Pro) builds on the team's git host (GitHub/Bitbucket permissions,
  PRs) or its own backend. Decide with the Pro offer gate.
