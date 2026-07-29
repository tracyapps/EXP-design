# EXP [design] — Backlog & Bug Tracker

A single, structured list of bugs, feature ideas, and performance work — written
so BOTH a human and an AI agent can pick something up cold. It complements
ROADMAP.md (which holds the phase plan + the Progress Log). Use ROADMAP for
"what's the plan / what happened"; use THIS for "what's the queue."

## How agents should use this
1. Pick the top **unclaimed** item at the priority you're asked for (P1 → P3).
2. Read its **Repro/Detail**, **Hypothesis**, and **Acceptance** before touching code.
3. Set `Status: in-progress`, implement, then set `Status: needs-verify` (owner
   builds & confirms) and add a dated **Progress Log** entry to ROADMAP.md.
4. Respect the CLAUDE.md rules (command-coverage, shared-target files, a11y).

## Entry format (copy this)
```
### <ID> — <one-line title>
- Type: bug | feature | perf
- Priority: P1 (soon) | P2 | P3 (someday)
- Area: canvas | inspector | model | color | export | chrome | perf | infra
- Status: open | in-progress | needs-verify | done
- Repro/Detail: <what happens / what's wanted, concrete steps>
- Hypothesis: <suspected cause or approach — optional>
- Acceptance: <how we know it's done>
```

---

## 🐞 Bugs

### BUG-016 — Layer copy/paste fails while the Layers list owns focus
- Type: bug
- Priority: P1
- Area: layers · canvas · clipboard
- Status: done (owner verified 2026-07-27).
- Repro/Detail: select a row in Layers and press Command-C / Command-V. The
  selection is valid, but nothing appears to happen. The layer-row context menu
  also lacked the expected Duplicate action even though the canvas menu and
  Command-D already supported it.
- Root cause: the editable canvas implements `copy(_:)` and `paste(_:)`, but a
  focused SwiftUI `List` is not in that sibling view's AppKit responder chain.
  Delete and arrow nudging already had explicit Layers handlers for the same focus
  gap; copy/paste had never received one. A canvas click also selected layers
  without explicitly reclaiming first-responder status from the last-used panel,
  so canvas-side selection could exhibit the same symptom after inspector work.
  The first fix also exposed two integration gaps: the custom clipboard UTI was
  used by SwiftUI without being exported from the app Info.plist, and SwiftUI
  hoisted nested-row context menus to their enclosing native List cell, causing a
  child-row Duplicate click to invoke the group's action.
- Fix: Layers now registers native Copy/Paste command handlers using the canvas's
  existing JSON pasteboard payload, so both keyboard shortcuts and Edit-menu
  commands work while the list is focused. Paste still routes through the canvas's
  one placement engine, and a canvas click now reclaims keyboard focus. Every
  editable layer-row context menu now includes Copy
  and Duplicate; duplication works recursively inside groups, is one undo step,
  selects the copy, and does not double-copy a child when its selected ancestor is
  also selected. Canvas and Layers duplication now share
  `Document.duplicatingNode`, which also gives copied relationships fresh ids and
  remaps both current and legacy targets. Follow-up after owner clarification:
  sibling insertion is also shared in `Document.duplicatingNodes`; its regression
  check proves a selected nested layer is inserted inside the same group, the
  enclosing group count does not change, and ancestor+child selection copies the
  subtree only once. Follow-up fix: `tapps.exp-design.nodes` is now exported as a
  JSON-conforming clipboard type, and pointer context clicks use an exact-row
  AppKit menu surface while the SwiftUI menu remains available to keyboard and
  accessibility users. Live UI verification in the isolated Debug app confirmed
  one group remains and its child count changes from two to three.
- Acceptance: select a top-level layer and a nested group child from Layers; for
  each, verify right-click Duplicate, Command-D, and Command-C then Command-V all
  create one independent copy in the correct scope. Repeat inside a component
  source editor; Undo must remove each copy in one step.

### FEAT-018 — Duplicate a component source as an independent working component
- Type: feature
- Priority: P1
- Area: components · model · canvas
- Status: done (owner verified 2026-07-27).
- Detail: “Create Instance” intentionally makes another use of the SAME source.
  The owner also needs “Duplicate Component” to fork the definition into a new,
  independently editable source.
- Implementation: Components list and grid context menus, an instance's canvas
  context menu, and Object ▸ Component now offer Duplicate Component. The copy is
  inserted beside the original, named `Name copy` / `Name copy 2`, and opened in
  its source editor. Source, child, state, and relationship ids are fresh;
  accessible-name/state/relationship targets are remapped; nested references to
  other components stay live; existing placed instances remain attached to the
  original source. One undo removes the new source. Live UI verification in the
  isolated Debug app confirmed the Components-row command opens an independent
  `Component 1 copy` source in its editor.
- Acceptance: duplicate a component containing states, nested components, public
  props, and relationships. Editing the copy must not change the original or any
  existing instance. Place an instance of the copy and verify its states,
  relationships, nested content, save/reopen, and handoff export remain intact.

### BUG-015 — Component-state blend-mode edits leak into the shared base
- Type: bug
- Priority: P1
- Area: model · components · canvas · export
- Status: done (owner verified 2026-07-27).
- Repro/Detail: while editing a named component state, change a layer's Blend
  Mode. The change appeared in Default and every sibling state instead of staying
  local to the active state, unlike opacity, fill, typography, outline, and
  visibility.
- Root cause: `InstanceOverride.Value` had no blend-mode case, so
  `ComponentStateEditing.capture` treated the edit as an unrecognized base change.
- Fix: blend mode is now a bounded state/instance override. Capture resets the
  shared base, state application restores the selected mode, instance resolution
  carries it through canvas/raster/SVG/Quick Look, and the parallel semantic HTML
  resolver emits the resolved `mix-blend-mode`. The focused check covers base
  isolation, state reapplication, and JSON round-trip.
- Acceptance: give Default, Hover, and Pressed visibly different blend modes;
  switching states changes only the active appearance; save/reopen preserves all
  three; placed instances, detach, SVG, semantic HTML, and Quick Look agree.

### BUG-014 — Deleting a component source moves its flattened instances off-canvas
- Type: bug
- Priority: P1
- Area: model · components · canvas
- Status: done (owner verified 2026-07-27).
- Repro/Detail: deleting a source from Components appeared to remove every placed
  instance from the canvas, despite the v2.1 preserving-flatten implementation.
- Root cause: `resolvedChildren` already returns source-local frames and the
  replacement group keeps the instance frame, but `flattened` also added the
  instance origin to every child. Group rendering then added the same origin a
  second time. The work remained in the model but was drawn at twice its original
  offset, commonly outside the visible canvas. The original headless check asserted
  the incorrect pre-offset child frame, so it blessed the bug.
- Fix: flattened children remain local to their replacement group. The regression
  check now asserts both local child coordinates and their composed document
  coordinates, while retaining the existing identity, nested-state, relationship,
  and no-data-loss checks.
- Acceptance: delete a source placed on the canvas, inside a group, and inside
  another source; every use becomes a plain group without moving or changing
  appearance; nested components remain live; one Undo restores the source and uses.

### BUG-011 — Reveal-target highlights inside the component, not on the canvas
- Type: bug
- Priority: P3
- Area: inspector · canvas
- Status: done (owner verified 2026-07-27). Owner 2026-07-24: the new reveal (crosshair) control
  works, but "since it's locked into it's own component, it only shows the
  highlight in the component and not on the artboard/canvas area."
- Resolution: owner verified the reveal behavior in the current build and could no
  longer reproduce the misplaced highlight. If it recurs, check active source-
  editor scope and off-screen selection before changing the endpoint logic.
- Low priority under the fidelity-not-prototyping principle: this is a
  verification convenience, not something that affects the exported artifact.

### BUG-012 — A relationship whose SUBJECT no longer exists vanishes silently on export
- Type: bug
- Priority: P1
- Area: export · a11y · fidelity
- Status: done (owner verified 2026-07-27).
- Found by inspecting a real export (owner's `five-tabtest.exph`, 2026-07-24).
  The tabs source held THREE authored relationships whose subject was node
  `658A38F8…` — a layer that exists nowhere in the document or the export. All
  three produced no attribute, no fidelity issue, and no trace of any kind. The
  owner reasonably concluded relationships "weren't working"; in fact they had
  been authored against a layer that was later removed, and the exporter dropped
  them without a word.
- Root cause: `anchoredAttributes` validated only the TARGET against
  `availableDOMIDs`. The subject's DOM id was composed and used as a dictionary
  key, and if nothing ever rendered with that id the entry was simply never
  claimed. A missing target was reported; a missing subject was not.
- Fix: the subject is now checked the same way, raising an `orphanedRelationship`
  fidelity issue that says a connection was authored on a layer that no longer
  exists and asks the designer to remove it or restore the layer.
- Why P1 despite being narrow: silent loss is the single failure mode a fidelity
  tool cannot have. Under the fidelity-not-prototyping principle, data that cannot
  be represented must be REPORTED, never discarded quietly.
- FOLLOW-UP, not done: an orphaned relationship is currently invisible in the UI
  too — its subject never appears as a participant, so the entry cannot be seen or
  deleted from the inspector. It can only be found by reading the file. Needs a
  cleanup affordance (an "unresolved connections" disclosure on the anchor, or a
  Handoff-report action that offers to remove them).

### BUG-013 — Selecting the group that holds both ends offers no anchor
- Type: bug
- Priority: P2
- Area: inspector
- Status: done (owner verified 2026-07-27).
- Detail: `relationshipAnchor` asked for the selection's ENCLOSING group. Selecting
  the group that actually holds a tab bar and its panel therefore looked for that
  group's parent, found none, and returned no anchor — a dead end with nothing on
  screen explaining why. Also made an earlier claim in this backlog wrong: that
  "selecting the enclosing group shows every participant" only held when the group
  was itself nested inside another group.
- Fix: a selected GROUP is now the anchor itself. Groups carry no role and are
  therefore never participants, only containers, so this loses nothing and matches
  what selecting a container is for.

### BUG-010 — Duplicating a group carries its relationships over pointing at the ORIGINAL
- Type: bug
- Priority: P1
- Area: model · canvas
- Status: done (owner verified 2026-07-27).
- Repro/Detail: owner 2026-07-24 duplicated an artboard, changed a link on one
  copy, and saw both behave as one.
- Root cause: `CanvasView.cloned(_:)` re-minted node ids recursively but copied
  `Node.anchoredRelationships` VERBATIM. The copy therefore held entries whose
  subject chain and target still named the original's nodes, so the duplicate
  described the original's structure rather than its own. Anchoring was correct;
  it simply was not carried through duplication.
- Fix: `cloned` now builds an old -> new id map (`freshIDs`) and runs the subtree
  through `Document.remappingAnchors(_:map:)`. Ids NOT in the map are left alone
  on purpose — a source child id is stable across every placement and must never
  be renamed, and a link that genuinely points OUTSIDE the copied subtree should
  keep pointing outside it. The same remap was added to `Document.flattened`,
  which already had an id map and had the identical latent bug.
- Known limit, deliberate: each top-level node is cloned with its OWN map, so a
  relationship anchored at the DOCUMENT root spanning two separately-cloned
  top-level nodes would not remap. Authoring cannot produce that case (the
  neighborhood rule requires a group anchor); only migration can. Revisit if the
  document-root anchor ever becomes authorable.
- Acceptance: duplicate a group holding a tab bar and its panel; set a target in
  one copy; the other is unaffected; both export distinct, non-colliding ids
  (the export half lands with FEAT-012 chunk I-d).

### FEAT-017 — Nested overrides: vary a nested component's content per placement
- Type: feature (model)
- Priority: P1 — the last big Chunk I model item, and the one the owner has hit repeatedly
- Area: model · inspector · export · handoff
- Status: done (owner verified 2026-07-28). All five chunks J-a…J-e are written
  and build clean. J-a…J-c were first owner-verified 2026-07-24 — nested content
  can now be varied per placement from the inspector. J-d built 2026-07-24; J-e's
  acceptance checks and the full signed Debug app, Quick Look, and helper build
  passed 2026-07-27. The complete placement/source/reset/duplicate/detach/save/
  Quick Look/export matrix passed 2026-07-28. J-c is the first chunk the
  owner can actually use. J-b makes nested overrides RESOLVE — they now
  affect drawing and export — but there is still no UI to author one, so the
  feature is reachable only from the headless checks until J-c. J-a is storage only and resolves nothing, so it is invisible
  at runtime — the same safety property that made FEAT-012's I-a easy to verify.
- Origin: owner, repeatedly and in their own words — *"i can't add or change tab
  names on an instance... because i can't set overrides in the nested components
  anyway. i only can edit the source, so i would have to duplicate the component."*
  That is the gap that pushed them toward forking components (FEAT-015) instead of
  reusing one, and it is why a single Tab Bar component cannot serve two tab sets.
- Root cause: `InstanceOverride.targetNodeID` is a BARE node id, resolved against
  the instance's own source children. A nested instance's children are one level
  further down, so nothing can address them — the same class of problem FEAT-012
  solved for relationships, and the fix is the same shape.
- PRECEDENT ALREADY IN THE MODEL, and it should be followed rather than reinvented:
  `NestedInstanceStateOverride` already addresses nested instances by
  `instancePath: [UUID]`, stored on the OUTERMOST placed instance, and
  `repairingStatePaths` already re-roots those paths when a source is deleted.
  Nested overrides are the same idea applied to values instead of state selection.
- DECISION: `ComponentInstance.nestedOverrides: [NestedInstanceOverride]`, each
  `(instancePath: [UUID], targetNodeID: UUID, value: InstanceOverride.Value)`,
  stored on the outermost placed instance. Reuse `InstanceOverride.Value`
  unchanged — text, fill, textStyle, opacity, stroke, componentState — so no new
  value vocabulary appears and every existing consumer already understands it.
- `publicProps` is NOT a gate. Its existing doc is explicit: false keeps an override
  local to EXP, true ADVERTISES it as part of the source's public contract. So all
  overridable fields stay overridable at any depth, and `PublicOverrideProps`
  continues to decide only what the handoff advertises. Do not repurpose it into
  permissions — that would break its stated meaning and make the feature feel
  arbitrary.
- Reset returns to the NEAREST source value: drop the nested override and the value
  falls back through the nested source, then the outer source. Same rule the flat
  case already follows, one level deeper.
- CHUNKS, in dependency order, each meant to land and be verified alone:
  - **J-a — type + storage.** `NestedInstanceOverride` with tolerant decode; no UI,
    no resolution. Invisible at runtime, like FEAT-012's I-a, so it can be verified
    safely before anything moves.
  - **J-b — resolution.** `resolvedChildren` applies nested overrides at the right
    depth. THE load-bearing chunk: every draw, hit-test, thumbnail, SVG, semantic
    HTML, Handoff, and Quick Look path already funnels through `resolvedChildren`,
    so getting this right makes the rest follow. Watch the depth cap and the
    instance cache invalidation (`resolveGeneration`).
    DONE (needs owner build): `Document.pushingNestedOverrides(_:into:)` hands each
    nested instance the overrides addressed to it, applied inside `resolvedLayout`
    BEFORE the reflow — ordering that matters, because a re-hug must measure the
    OVERRIDDEN content, which is the same mistake BUG-007 was about.
    Deliberately ONE level: a path `[a]` becomes an ordinary override on `a`, and
    `[a, b]` becomes a nested override on `a` with the head stripped. `a` then
    resolves through the same function, so arbitrary depth falls out of the existing
    recursion instead of needing its own walk. Appended LAST so the outer
    placement's value beats whatever the source baked in — which also makes RESET
    free: drop the entry and the nearest source value returns, no separate
    mechanism. Groups are descended but never named, matching relationship
    endpoints, so rearranging a layout group cannot break an override. An empty path
    matches nothing by construction (no node id equals nil), which is J-a's
    `isAddressable` contract holding without a filter someone could later delete.
    CACHE: checked, no change needed. `instanceResolveCache` keys on TOP-LEVEL
    instance node ids, which are unique, and nested instances already fall through
    to a fresh resolve. Nested overrides live on the top-level instance, so the key
    is already correct, and any override edit happens outside a drag where the
    normal `resolveGeneration` clear runs.
  - **J-c — inspector.** With an instance selected, expose overridable fields for
    nested children. Mirror the PARTICIPANTS pattern from FEAT-012 chunk I-c, which
    the owner reacted well to: a block per nested child, reached from an ancestor
    rather than by selecting the unselectable.
    DONE (needs owner build). Prompted by the owner seeing an "Overrides" header
    with NOTHING under it: `overridableChildren` recursed into groups but stopped
    dead at `.instance`, so a component whose children are all components had no
    overridable leaves to show. Nothing was broken — there was simply no address for
    a layer one level down, which is the entire point of FEAT-017.
    `overridableTargets` replaces it, returning `(instancePath, node, componentName)`
    and descending into nested components as well as groups. Rows are grouped under
    the nested LAYER's name rather than the source's, because two tabs from one
    component are told apart by their layer names, not by the component they share.
    The flat case keeps its existing bindings untouched — only a nested target
    routes through `nestedOverrides` — so nothing that already worked changes shape.
    Reset is still just the absence of an entry.
    Also fixed the honesty bug the owner actually reported: when there is genuinely
    nothing to override, the section now SAYS so instead of rendering a heading over
    empty space, which reads as broken.
    FOLLOW-UP, same day, owner-requested: rows now show the RESOLVED value — what
    the canvas draws — instead of the raw source value. It was wrong twice over: a
    nested instance normally carries its own overrides inside the parent source (a
    tab bar sets its three tabs to "one"/"two"/"three"), and an active STATE can
    change a value too, so the field said one thing while the canvas said another.
    This fixes the flat case as well, which had the same state-related mismatch.
    `hasOverride` still comes from the STORED entry, deliberately: "what does this
    show" and "has this been changed HERE" are different questions and answering
    both from one place would break the reset affordance. Resolution happens ONCE
    per body evaluation keyed by distinct path, never per row — a computed resolve
    inside a `ForEach` is precisely the shape behind the ~6.2s inspector hangs in
    PERF rounds 8 and 10, and the code says so at the point of temptation.
  - **J-d — export + handoff.** Overrides reflected in HTML/SVG; `publicProps`
    advertised per path so codegen knows what is a real prop.
    DONE (needs owner build). SVG/PDF and the canvas needed NO change — they route
    through `resolvedChildren`, so J-b already covered them. Semantic HTML did:
    `semanticHTMLResolvedChildren` is a PARALLEL resolver (it keeps hidden layers
    so it can emit `hidden`, which is why it does not call `resolvedChildren`), and
    it silently missed J-b's push-down entirely. Same call added, same position —
    before the reflow, so a re-hug measures the overridden content. The duplication
    is the real hazard here, not the logic, so `checkSemanticResolverSeesNestedOverrides`
    now fails loudly if the two resolvers ever disagree again.
    `publicProps` is now ADVERTISED. It had existed on `Node` for a long time and
    appeared nowhere in the package, so a reader had to infer a component's API from
    the raw model tree — exactly the guessing a handoff exists to prevent. The
    README gains a "Component Props" section listing every field marked public,
    including ones on layers inside nested components, addressed by the same path
    shape used elsewhere (groups add no step, since they are structure not
    identity). Its stored meaning is preserved rather than repurposed: this reports
    the declaration, it does not gate anything.
  - **J-e — checks + the acceptance matrix.** Two placements diverge independently;
    a source edit flows through to both unless overridden; reset returns the nearest
    source value; duplicate, detach, delete-source, save/reopen, Quick Look.
    DONE (needs owner build). DETACH needed no code at all — it bakes
    `resolvedChildren`, which J-b already covers, so a nested override survives into
    the detached tree by construction. Verified rather than assumed, and the check
    stays as a regression guard.
    Four acceptance checks added: a duplicate starts identical and then diverges
    without touching the original (BOTH halves matter — copying must preserve
    appearance, editing must not leak); detach bakes the resolved value instead of
    snapping back to source; deleting a component SOURCE leaves no override with an
    unusable path; and the whole document round-trips through save/reopen, which is
    the file the owner actually keeps.
    `AnchoredRelationshipCheck` now covers 17 cases across FEAT-012, FEAT-016 and
    FEAT-017.
- HAZARD, CORRECTED while writing J-a. The plan first said "duplication and flatten
  must remap nested override paths." Checking rather than assuming: DUPLICATION does
  NOT need it. `instancePath` names nested instance nodes that live inside the
  SOURCE, and cloning a placed node never renames source-internal ids — the same
  reason `nestedStateOverrides` already survives cloning untouched. FLATTEN does
  need it, because dissolving a source re-identifies the resolved children a path
  runs through. Handled in `repairingStatePaths` alongside the state-selection
  repair it already did, including remapping `targetNodeID`. Stated precisely here
  because a wrong hazard note is worse than none — it sends the next person to
  patch code that was already correct.
- DONE in J-a (needs owner build): `NestedInstanceOverride`
  (`instancePath` + `targetNodeID` + `InstanceOverride.Value`, reused unchanged),
  stored as `ComponentInstance.nestedOverrides` with tolerant decode so pre-v2.1
  files open unaffected. `isAddressable` makes the empty-path case an explicit
  question rather than a silent filter — an empty path would address the instance's
  own children, which `overrides` already covers, so resolution in J-b must not
  guess at it. Checks added to `AnchoredRelationshipCheck`: round-trip through
  JSON, a legacy instance with no key decoding to empty, and the empty-path rule.
- Acceptance: one Tab Bar component placed twice with DIFFERENT tab labels in each;
  editing the tab source updates both except where overridden; reset restores the
  source label; both export correct, independent HTML.

### FEAT-016 — Check the ROLE at the other end of a relationship, not just that it resolves
- Type: feature
- Priority: P2
- Area: export · a11y · handoff
- Status: done (owner verified 2026-07-28). Focused advisory/package checks and
  the real relationship-heavy acceptance pass both succeed.
  `SemanticHTMLFidelityIssue.Category` gains `.advisory`, kept separate from
  `.semanticRequirement` on purpose — a reader must be able to tell "a rule was
  broken" from "this is legal but probably not what you meant," and collapsing them
  makes the report either alarmist or ignorable. The Handoff README names all three
  distinctly.
  `AriaRole.expectedRelationshipTargetRoles(for:)` holds the pairings, and holds
  ONLY pairings with a spec citation in the doc comment. Two entries today: a tab's
  `aria-controls` expects a tabpanel, a tabpanel's `aria-labelledby` expects a tab
  (both quoted from the WAI-APG Tabs pattern). Everything else returns empty,
  because an advisory that fires on correct work is worse than no advisory.
  `anchoredAttributes` resolves BOTH ends to nodes so it can compare roles, raising
  `unexpectedRelationshipTarget`, and separately counts subjects per target to raise
  `sharedRelationshipTarget` when several tabs point at one panel — worded to say
  plainly that nothing is invalid, since no prohibition was found.
  `AnchoredRelationshipCheck` gained `checkAdvisoryTableIsNarrow`, which asserts the
  two verified pairings AND asserts emptiness for `describedby`, `tablist`, and
  `button` — a guard against someone quietly adding a pairing that feels right.
- Origin: reading the owner's `tab-test3.exph`. Every requirement passed and the
  export is valid, yet two things a reviewer would flag went unmentioned, because
  EXP currently only asks "does this relationship RESOLVE," never "does it point at
  the right KIND of thing."
- Case 1 — a `tabpanel` labelled by its own content. The owner's panel carries
  `aria-labelledby` pointing at a text layer INSIDE itself. `SemanticHTMLContract`
  requires `.labelledByRelationship` for `tabpanel`, and one is present, so nothing
  fires. VERIFIED against the APG Tabs pattern
  (https://www.w3.org/WAI/ARIA/apg/patterns/tabs/): "Each element with role
  `tabpanel` has the property `aria-labelledby` referring to its associated `tab`
  element." So the intended target is a `tab`, and pointing elsewhere is worth
  saying out loud — as ADVICE, since it is valid markup, not a violation.
- Case 2 — several tabs sharing one panel. All three of the owner's tabs resolve
  `aria-controls` to the SAME `tabpanel`. The APG describes a 1:1 association
  ("its associated tabpanel"), but does NOT state a prohibition, so this must be
  advisory and phrased as such. NOT VERIFIED: whether any normative text forbids
  it. Do not upgrade this to an error without finding one.
- Shape: extend the fidelity report with an advisory category — distinct from
  `semanticRequirement` (a rule was broken) and `visualFallback` (we approximated)
  — that says "this resolves, but points somewhere unexpected for this role."
  Reuse `AriaRole.expectedChildRoles` thinking: a per-kind, per-role table of what
  the far end is normally expected to BE.
- Why it matters under the fidelity principle: the export goes to a developer or a
  model that writes component code from it. A link pointing at a plausible-but-wrong
  element produces plausible-but-wrong code, and nothing in the current package
  would warn anyone.
- Acceptance: advisories appear in `manifest.fidelity` and the README, clearly
  separated from hard requirements; nothing is auto-corrected; a correct file
  produces none; each advisory cites the pattern it comes from.

### FEAT-015 — "Duplicate as New Component"
- Type: feature
- Priority: P2
- Area: model · components · menu
- Status: LOGGED 2026-07-24, NOT STARTED
- Origin: owner 2026-07-24, while working out how to make a SECOND tab set. There
  is currently no way to fork a component: you can place instances of it and you
  can edit the source, but you cannot say "give me a new component that starts as a
  copy of this one." The only workaround is rebuilding it by hand.
- Why it surfaced now: with nested overrides not yet built, a component's nested
  parts cannot be varied per instance, so a second tab set MUST be a second
  component. That makes the missing action acutely felt — but the need is not
  contingent on that gap. Forking a component to make a variant is ordinary design
  work, and every comparable tool has it.
- Design notes: fresh source id, fresh child ids, name defaulting to "<name> copy",
  and — the part that is easy to get wrong — `anchoredRelationships` and
  `a11y.rootRelationships` must be remapped through the new child id map, exactly
  as BUG-010 required for node duplication. Reuse `Document.remappingAnchors`.
  Nested instances INSIDE the copied source keep pointing at their own sources
  (a fork copies this component, not the whole dependency tree).
- Command coverage: Components panel context menu, Object menu, and the canvas
  context menu when an instance is selected.
- Acceptance: forking a component produces an independent source; editing the fork
  never affects the original or its instances; relationships inside the fork point
  at the fork's own layers; the dependency graph stays acyclic.

### BUG-009 — Expanding a component in Layers leaves a stale row height (scrollbar wrong until you scroll)
- Type: bug
- Priority: P2
- Area: chrome · layers · perf
- Status: done (owner verified 2026-07-27). If it recurs, the
  follow-up is below — do NOT reach for it first.
- Repro/Detail: owner 2026-07-24. Expanding a component in the Layers panel
  "sometimes" does not size to the expanded content — a scrollbar appears, and
  scrolling once corrects it.
- Root cause: `InstanceLayerRow` held its disclosure state in a private
  `@State var expanded`. Every visible layer inside a component lives in ONE
  `List` row (the top-level `LayerOutlineRow`), and `List` on macOS caches each
  row's measured height. A nested row expanding changed the outer row's height
  without the List being told, so the cached height stayed stale until a scroll
  forced re-measurement. The private state also explains the "sometimes":
  expansion silently reset whenever SwiftUI recycled a row.
- Fix: hoisted nested expansion to `LayersPanel.expandedNested`, a
  `Set<[UUID]>` keyed by a per-PLACEMENT row path (`rowKeyPath`), so the change is
  observable from the List row. Path-keyed rather than id-keyed because the same
  source child appears under every placement of its component — a plain node id
  would have expanded them all at once. `rowKeyPath` is deliberately separate from
  the existing `instancePath`, which addresses nested component instances for
  state overrides; overloading it would have quietly changed which layer a state
  selection applied to.
- IF IT RECURS: the remaining fix is to give each List row an explicit height, or
  to flatten the outline so every visible layer is its own List row (which would
  also make nested rows selectable and keyboard-reachable). Both are real
  refactors of a file with a documented performance history — see PERF-LOG rounds
  8 and 10, where per-row computed properties in this panel caused ~6.2s
  main-thread hangs. Any height computation MUST be hoisted out of the row bodies.

### BUG-007 — Auto layout positions component instances by a STALE stored frame, not their resolved size
- Type: bug
- Priority: P1 (soon)
- Area: model · canvas · inspector
- Status: done (owner verified 2026-07-27; fixed via `Document.reflowed(_:)`, which
  pre-sizes instances via `instanceSized(_:depth:)`, all call sites moved, depth
  capped at 24 so a cyclic legacy document still terminates; the two-tab repro
  now passes. Continue watching redraw perf on large documents.)
- Repro/Detail: Owner repro 2026-07-24. Make a component `tab` that is text
  wrapped in a group with auto padding. Place two instances side by side, group
  them, and give the group auto layout with a 2px gap. The gap and the instance
  positions are computed from something that is not the component's visible
  bounds: the drawn text spills outside the instance box, the magenta instance
  outlines are wider than the blue selection boxes and overlap each other, and
  the spacing does not match 2px. Overriding the text on one instance (e.g.
  "tab" → "tab one") makes the misalignment dramatic — the wider text runs
  straight over its sibling.
- Hypothesis: CONFIRMED by reading the code — an instance has two different
  sizes in the app and they are never reconciled.
  `AutoLayoutEngine.reflow(_:)` handles exactly two things: `.group` (recurse)
  and `.text` with `box == .auto` (re-measure). `.instance` hits neither branch
  and is returned untouched, so the stack/padBlock math uses the instance node's
  STORED `frame.size` — whatever it happened to be when the instance was placed.
  The engine cannot do better on its own: it is a pure `[Node] -> [Node]`
  function with no `Document`, so it has no way to look up a source and cannot
  call `resolvedSize(of:)`.
  Meanwhile every DRAW, hit-test, and selection path does exactly that:
  `CanvasView` lines ~1889, ~4478, ~4928, ~5252, ~5428 all size instances with
  `document.model.resolvedSize(of: inst)`, which re-hugs through
  `resolvedLayout(of:)` and therefore tracks overrides and state live. So the
  instance DRAWS at its resolved size and is LAID OUT at its stale frame. Any
  override that changes the resolved size — a longer text override is the
  obvious one — widens the drawing without moving the siblings.
- Proposed fix: give the reflow entry point document context rather than
  teaching the pure engine about sources. Add `Document.reflowed(_:)` that
  first walks the tree and sets each `.instance` node's `frame.size` to
  `resolvedSize(of:)` (recursively, so nested instances size innermost-first),
  then hands the pre-sized tree to `AutoLayoutEngine.reflowed(_:)`. Keep the
  existing pure engine entry point for callers with no document (EXPThumbnail).
  Then move the 17 `AutoLayoutEngine.reflowed(...)` call sites in
  `Document.swift`, `CanvasView.swift`, `LayersPanel.swift`, `MainWindow.swift`,
  and `DesignLanguagePanel.swift` onto the document-aware form.
  Termination is guaranteed by the Chunk I acyclic source graph. Watch PERF:
  this runs on the draw path, so it must ride the existing per-instance resolve
  cache (`ExpDocument.resolveGeneration`) rather than re-resolving per redraw —
  verify `instCacheHit/Miss` actually move (see PERF-005).
- Acceptance: with the owner's two-tab repro, the gap measures exactly 2px, the
  drawn text stays inside the instance bounds, magenta instance outlines match
  the blue selection boxes, and a text override on one instance re-hugs that
  instance AND pushes its sibling over by the same amount. Same behavior inside
  a source editor and on the document canvas. No measurable redraw regression on
  a large document.


### BUG-006 — Component-state typography and opacity leak into every state
- Type: bug
- Priority: P1 (soon)
- Area: model · inspector · canvas · export
- Status: done (v2.0.1 — owner reports fixed and pushed; extended the state-diff vocabulary with
  `.textStyle` (bounded typography) + `.opacity` cases; capture now diffs both
  into the active state and resets the base text node to pristine; apply,
  instance render, and semantic-handoff resolution all fold the new cases;
  both recorded leak repros closed)
- Repro/Detail: Create a component with Default, Hover, and Disabled states. In
  the source editor, activate Disabled, select its text layer, then change a
  typography property such as color, typeface, size, line height, tracking, or
  case; alternatively change the opacity of the text, background, or root group.
  The edit changes the shared component source, so Default and the other states
  change too. The owner reproduced both opacity and text-style leakage in the
  2026-07-23 Help recording at 37:17–38:45. This makes common state designs such
  as muted Disabled labels unsafe to author.
- Hypothesis: `ComponentStateEditing.capture` only records text-content strings,
  shape/group fills, and visibility. `InstanceOverride.Value` has only `.text`
  and `.fill`; every other visual edit intentionally falls through to the shared
  base. Extend the state-diff vocabulary for bounded typography and layer
  opacity, apply it recursively in state/instance resolution, and emit it in
  semantic handoff without turning geometry or relationships into state-local
  data. Preserve tolerant decoding for existing schema-v2 documents.
- Acceptance: changing a text layer's color, typeface/face, size, alignment,
  line-height unit/value, tracking, case, or a selected layer/group's opacity
  while a non-default state is active affects only that state. Default and sibling
  states remain byte-for-byte and visually unchanged; instances render the chosen
  state correctly; semantic HTML/CSS handoff preserves the state differences;
  undo/redo is one coherent step; old documents still open and save safely.

### BUG-005 — Shift does not constrain a new Pen curve handle
- Type: bug
- Priority: P2
- Area: canvas · vector
- Status: done (v2.0.1 — owner reports fixed and pushed; `penHandleDrag` now takes the live Shift state
  and snaps the dragged handle to axis/45° via `constrainLineEndpoint` (mirrors
  `pathPointDrag`); the opposite handle is re-derived so it stays mirrored;
  new-handle drawing now matches existing-handle constraint behavior)
- Repro/Detail: Choose Pen (P), place an anchor, then click-drag a new anchor to
  pull its Bézier handles. Hold Shift during the drag. The handle continues to
  rotate freely instead of snapping to the same axis/45-degree increments used
  when an existing handle is edited. Reproduced in the 2026-07-23 Help recording
  at 13:44–14:13.
- Hypothesis: the `.penHandle` drag branch calls `penHandleDrag` without its
  current Shift state, and `penHandleDrag` never calls `constrainLineEndpoint`.
  The existing `pathPointDrag` control-handle branches already implement the
  expected axis/45-degree constraint and can supply the behavior to mirror.
- Acceptance: while creating a curved Pen anchor, pressing or releasing Shift
  during the drag immediately toggles axis/45-degree snapping; the opposite
  handle stays mirrored; free dragging is unchanged; existing-handle editing
  remains consistent; one path draw remains one undo step.

### BUG-004 — Custom centered document title uses native popup anchor awkwardly
- Type: bug
- Priority: P2
- Area: chrome
- Status: open
- Repro/Detail: The main window draws a custom centered EXP-styled document title,
  but the native macOS rename/location bubble is still anchored to the left-side
  titlebar document controls. The centered "Edited" label can also fail to appear
  even while AppKit's native edited state is active.
- Hypothesis: AppKit's document rename/location popover is tied to private/native
  titlebar controls. The current implementation keeps those controls alive but
  visually transparent, then forwards clicks from the centered title. A robust fix
  may need either a custom rename/move popover that mirrors the native fields, or a
  better public AppKit anchor strategy using a titlebar accessory/custom view.
- Acceptance: only the centered EXP title is visible; edited state appears under it
  in `EXPColor.accent`; clicking the centered title opens rename/location UI near
  the centered title with no leftover native title glyphs or console warnings.

### BUG-003 — Gradient darkens (color shift) during pan/zoom blit
- Type: bug
- Priority: P2
- Area: canvas · color
- Status: done (v1.2 — verified by owner)
- Update (S174): switching the CGGradient space to sRGB did not resolve the darkening,
  so the root cause is elsewhere. Next hypotheses to test: (a) the offscreen backing is
  premultipliedFirst/BGRA and `cg.makeImage()` -> `ctx.draw` round-trips premultiplied
  alpha, darkening a gradient that has a SEMI-TRANSPARENT stop (check whether the
  affected gradient has an alpha<1 stop while the unaffected one is fully opaque);
  (b) the snapshot CGImage is tagged the window/offscreen space (P3) but drawn into a
  window drawRect context of a different space, so ONLY color-managed content shifts;
  (c) possible interaction with the new HSB/HSL/OKLCH authoring — verify the stored
  RGBAColor values are byte-identical before/after editing via the new picker modes;
  (d) instrument by dumping the affected gradient's stop colors + alphas.
- Update (v1.2): pan/zoom snapshots now render into a document-sRGB offscreen
  backing instead of inheriting the window/Display-P3 space. Other offscreen paths
  keep the old window-space default. Needs owner visual verification on the
  saturated semi-transparent gradient repro.
- Update (v1.2 follow-up): owner testing showed the sRGB snapshot still shifted,
  and that during node drags the moved gradient stayed correct while static
  gradients changed. That localizes the issue to bitmap flattening of static
  content. Current fix: visible gradients and enabled drop/inner shadows bypass
  pan/zoom bitmap blit and force true live compositing for drag gestures when any
  non-dragged visible gradient/shadow content is present. Plain content still uses
  the fast snapshot paths.
- Verified (2026-07-06): owner confirmed the gradient/shadow interaction shift is
  fixed.
- Repro/Detail: A saturated gradient on the canvas visibly darkens while panning or
  zooming, then snaps back to the correct color when motion stops. A near-neutral
  gradient elsewhere doesn't show it. (Anti-aliased text also shimmers slightly mid-
  gesture — that's a separate, expected blit artifact; see note.)
- Prior hypothesis: `PaintRender.drawGradient` built the `CGGradient` in
  `CGColorSpaceCreateDeviceRGB()` — an UNMANAGED device space — while its stop colors
  (and every solid fill) are sRGB. During pan/zoom the scene is drawn into the
  color-managed offscreen blit bitmap (window color space, usually Display P3); an
  unmanaged device-RGB gradient color-matches differently there than in the live
  window device context, so only the blit shifts. Live settle render looked correct.
- Fix attempt: keep gradient interpolation in sRGB, render pan/zoom snapshots in
  document sRGB for plain content, and bypass snapshot flattening entirely when
  visible gradient/shadow content would otherwise change color mid-gesture.
- Acceptance: gradient looks identical while moving and stopped; export unchanged.


### BUG-001 — Measurements shown as whole numbers while real values are fractional
- Type: bug
- Priority: P2
- Area: inspector · canvas
- Status: done (Session 161 — inspector DimFields show 0–2 truthful decimals, measure HUD matches, canvas snaps to whole px by default with ⌘ bypass)
- Repro/Detail: With snap-to-grid OFF, position it so auto-layout / free placement
  yields sub-pixel spacing. The on-canvas ⌥-hover measure labels and every inspector
  numeric field show WHOLE numbers, so a real gap of e.g. 12.4 reads as "12". You
  can't see or type sub-pixel values.
- Hypothesis: display-only precision loss. Every numeric `TextField` uses
  `format: .number.precision(.fractionLength(0))` (MainWindow) and the canvas
  measure/ruler labels round via `Int(...)` (`measureLabel`, `drawRulerNumber`).
  The model stores fractional `CGFloat`, so nothing is lost until the user TYPES a
  value (which then commits the rounded whole number).
- Acceptance: fields + measure labels show a sensible precision (e.g. up to 1–2
  fraction digits, trailing-zero-trimmed) and typing a fractional value keeps it.
  Decide a rounding policy (display vs. stored) and apply it consistently.

---

### BUG-002 — "Publishing changes from within view updates" (~40×) — repro: inspector ↑/↓ stepping
- Type: bug
- Priority: P1
- Area: inspector · chrome
- Status: done (2026-07-20 — owner reports the warning has not reappeared after
  the Session 162f deferred stepper writes and later inspector/menu cleanup; keep
  watching normal tester runs, but remove it from public known issues.)
- Repro/Detail: Owner isolated it (2026-07-02): using the KEYBOARD arrows to
  increase/decrease values in inspector fields fires the warning; it also
  floods ~40× at app launch. Session 124-era mystery, now reproducible.
- Hypothesis: `NumericStepping.onKeyPress` (UI/MainWindow.swift) writes the
  bound value SYNCHRONOUSLY inside the key-press handler, which runs during a
  SwiftUI view update — mutating an @Observable/@Published mid-update is the
  textbook trigger. Likely fix: defer the mutation one tick
  (`Task { @MainActor in value = next }` or `DispatchQueue.main.async`),
  keeping ⌥/⇧ step sizes + key-repeat acceleration identical. The launch-time
  flood may be a second site (window restoration / initial layout writing to
  AppState during body evaluation) — verify separately with a breakpoint on
  the warning after the stepper fix lands.
- Acceptance: zero warnings while arrow-stepping any inspector field (incl.
  held-key repeat), zero at launch; stepping behavior unchanged (±1, ⇧±10,
  ⌥±0.1, acceleration); undo granularity unchanged.

## ✨ Features

> **Standing rule for every ARIA / semantics item below (BUG-008, FEAT-011, the
> Chunk I containment work, and anything that follows).** Verify each decision
> against the official documentation — WAI-ARIA 1.2, ARIA in HTML, the ARIA
> Authoring Practices Guide, WCAG 2.1 AA — BEFORE writing code, and record the
> citation in the entry. Owner instruction 2026-07-24: this holds *"even if I ask
> for the wrong thing by accident."* Push back with the source when a request
> contradicts the spec; it has already caught one (removing `aria-labelledby`
> from `tabpanel` would have broken the canonical APG tabs pattern). State
> plainly what was NOT verified. Full text in `docs/WORKING-AGREEMENT.md` →
> "Accessibility decisions are verified, not remembered."

### FEAT-012 — Anchored relationships: endpoints as instance paths, stored at the nearest common ancestor
- Type: feature (model)
- Priority: P1 — blocks BUG-008 acceptance, and everything downstream of Chunk I
- Area: model · inspector · export · handoff · import
- Status: done (owner verified 2026-07-28). All five chunks I-a…I-e are written
  and build clean. I-d was confirmed
  in a real export (`tab-test3.exph`: three `aria-controls` resolving to the panel
  with depth-2 chain ids), and I-c's participant display was owner-verified on
  2026-07-24. On 2026-07-27 the anchored, graph, semantic-contract, deterministic
  package, and SVG suites all passed, followed by the full signed Debug app,
  Quick Look, and helper build. The owner-facing duplicate independence,
  save/reopen, Quick Look, relationship, and export matrix passed 2026-07-28.
- DISCOVERABILITY finding, owner 2026-07-24: they first selected the individual tab
  and saw nothing, because a nested tab is not selectable and the participants only
  appear on an ANCESTOR. Selecting the enclosing group shows every participant
  (`participants(from:)` recurses through groups), and selecting the Tab Bar shows
  it plus its tabs — but neither is signposted. Nothing is broken; the affordance is
  just invisible until someone tells you. Candidates when the F2 / panel-IA pass
  lands: surface the anchor's participants when a NON-roled layer inside the anchor
  is selected, rather than showing only `unroledSelectionNote`; or make the Layers
  row for a nested roled component reveal its relationships. Do NOT solve this by
  making nested layers selectable — they exist once per placement, which is the
  whole reason FEAT-012 exists. Both are deliberately runtime-INVISIBLE: the
  exporter still reads the legacy `Node.relationships`, and the switch-over happens
  in I-d. That is what makes it safe to have written them ahead of a build.
- Origin: owner tried to author the APG tabs pattern and could not. Structure was
  a Tab Bar component (role `tablist`) whose children are Tab components (role
  `tab`), placed in an artboard group beside a Tab Panel component (role
  `tabpanel`). Widening the target picker was the obvious-looking fix and is the
  WRONG one — recorded so nobody tries it again.
- VERIFIED against the WAI-APG Tabs pattern, 2026-07-24
  (https://www.w3.org/WAI/ARIA/apg/patterns/tabs/):
  - "Each element that serves as a tab has role `tab` and is contained within the
    element with role `tablist`." The owner's nesting is CORRECT; do not advise
    restructuring it.
  - "Each element with role `tab` has the property `aria-controls` referring to
    its associated `tabpanel` element", and "each element with role `tabpanel` has
    the property `aria-labelledby` referring to its associated `tab` element." So
    the link is tab-to-panel, individual to individual — never tablist-to-panel.
  NOT VERIFIED: whether a single `tabpanel` shared by several tabs conforms. The
  APG describes a 1:1 pairing and says nothing explicit about the shared case;
  this was NOT resolved and FEAT-013 depends on it. Do not assert either way.
- Root cause: a relationship is stored ON THE SUBJECT NODE. The subject here (a
  tab) lives inside the Tab Bar SOURCE, and anything stored in a source applies to
  every placement of it — so all placements of Tab Bar would point at one panel.
  The link has to vary per PLACEMENT, so it cannot live in the source. This is a
  storage problem, not a picker-scope problem. Widening the neighborhood would
  only let someone author a link that cannot export correctly.
- DECISION (owner delegated the mechanism 2026-07-24: "just find the most stable
  and scaleable method"): **a relationship lives at the nearest node that contains
  BOTH of its ends, and addresses each end by instance PATH rather than raw id.**
  For the owner's file the anchor is the artboard group holding Tab Bar and Tab
  Panel; the tab end is `[TabBarInstance, TabOne]`, the panel end is
  `[TabPanelInstance]`. Place that group twice and each copy resolves to its own
  ids — no cross-placement leak, no duplicate DOM ids.
  Why this over the alternatives:
  - It makes the NEIGHBOURHOOD rule fall out instead of being a separate
    constraint bolted on: the neighborhood IS the anchor's subtree. One concept.
  - It is the same machinery Chunk I already needs for "stable instance paths"
    (nested overrides, visibility, DOM ids, import reports), so it is not new
    surface area — it is the planned surface area, reached from the front door.
  - Roles-on-plain-groups (FEAT-014) was considered FIRST and REJECTED as the fix.
    It would not have helped this case at all: the owner's roles are already on
    components, correctly. Logged separately on its own merits.
- CHUNKS, in dependency order. Each is meant to land and be verified on its own.
  - **I-a — `RelationshipEndpoint` path type.** `[UUID]`, innermost-last. Tolerant
    decode so a legacy single `targetID` becomes a one-element path and behaves
    exactly as today. Resolution + validation helpers on `Document`. NO UI and NO
    behavior change: this chunk should be invisible at runtime, which is what
    makes it safe to verify.
    DONE (needs owner build): `RelationshipEndpoint` (an `instanceChain` outermost
    first + a non-optional `nodeID`, so an endpoint cannot be malformed the way a
    bare `[UUID]` could); `NodeRelationship.target` replaces the stored `targetID`,
    which survives as a get/set accessor so every existing call site compiles and
    behaves identically; decode accepts either form; encode writes BOTH, so a v2.1
    file still opens in a v2.0 build and degrades to sibling behavior instead of
    failing to decode. `Document.resolveEndpoint(_:in:)` walks a path, descending
    through component instances via `resolvedChildren` and treating plain groups as
    transparent — a path never names a group, so links survive regrouping — with
    the same depth cap the dependency walker uses so a damaged document terminates.
  - **I-b — Anchored storage + migration.** Move relationships off the subject node
    onto the anchor. Add the anchor container, decide it by nearest-common-ancestor
    at author time, and migrate existing node-stored relationships (subject and
    target already share a parent today, so every existing one migrates to that
    parent without ambiguity). Repair anchors on move, regroup, ungroup, delete,
    and component-source deletion — the same paths that already repair
    `nestedStateOverrides`.
    DONE (needs owner build): `AnchoredRelationship` (kind + subject endpoint +
    target endpoint). THREE anchor stores, because three things can contain both
    ends — `Node.anchoredRelationships` (groups),
    `ComponentSource.anchoredRelationships`, and `Document.anchoredRelationships`
    as the top-level fallback. Authoring will never create the document-root case
    (the neighborhood rule requires a group), but migration can, so it exists
    rather than silently dropping a legacy link. A subject may name the ANCHOR
    ITSELF, which is how a component's own relationships are expressed — the
    element carrying the role hosts the instance, so it IS the anchor — needing no
    special case in the data, only `endpointNamesAnchor(_:anchorID:)`.
    `migrateRelationshipsToAnchors()` runs at decode and is ADDITIVE: the legacy
    `Node.relationships` and `a11y.rootRelationships` are left intact and still
    encoded, so a wrong migration is recoverable rather than destroying a document
    the first time it is saved. Idempotent, with dedupe on (kind, subject, target)
    and NOT on `id` — `id` is freshly minted each run and would have defeated the
    check, a bug that would only surface as slow duplication over many open/save
    cycles. `nearestCommonAncestorGroup` considers GROUPS only: a legacy
    relationship could only ever address a sibling, so it never crossed an instance
    boundary, and treating instances as containers would invent nesting the stored
    data does not have.
    STILL TO DO in I-b: anchor REPAIR on move, regroup, ungroup, delete, and
    component-source deletion. Deferred on purpose — nothing reads the anchored
    form until I-d, so a stale anchor cannot affect anything yet, and repair is far
    easier to write against the authoring UI I-c adds than against nothing.
  - **I-c — Authoring UI.** The subject picker must now reach INTO nested instances
    (selecting one tab inside Tab Bar), and the target picker likewise, both scoped
    to the anchor's subtree. Keeps FEAT-011 wording and the role annotation already
    shipped. This is where the owner can finally test the tabs pattern.
    DONE (needs owner build): the inspector no longer authors "the selected node's
    relationships" — it authors the ANCHOR's, and lists a block per PARTICIPANT.
    A participant is anything roled that the selection can reach: the selection
    itself, the component root in source scope, and every roled component nested
    inside the selection. That is what makes one tab inside a placed Tab Bar
    authorable even though it cannot be selected — which was the blocking problem.
    `relationshipEndpoints(in:chain:depth:)` builds the pickable ends: groups are
    transparent (a path never names one, so a link survives regrouping), and
    component instances contribute themselves plus ONLY their roled descendants.
    That last rule is deliberate — an unroled layer inside a component is that
    component's private business, and linking to one from outside couples two
    components at a level that breaks the moment either is edited, while a
    component's roled parts are its public semantic surface and the only thing ARIA
    has any use for out here. A target that no longer resolves stays SELECTABLE as
    "Missing layer" instead of silently reverting to None.
    `Document.hasRelationshipParticipant(in:)` now backs the Object-menu item, the
    canvas context menu, AND the inspector, replacing three separate copies of the
    same test — the arrangement that lets a menu and a panel drift apart.
    NOT YET: export still reads the legacy `Node.relationships`, so links authored
    this way persist and round-trip but do NOT appear in exported HTML until I-d.
    Verify I-c on authoring and persistence only.
  - **I-d — Export.** Resolve paths to emitted DOM ids. Note
    `SemanticHTMLIdentity.nodeDOMID(_:instanceID:)` takes ONE instance id, so ids
    collide at nesting depth 2+ — this chunk must widen it to a path and therefore
    CLOSES the roadmap's "replace ambiguous raw descendant ids with stable instance
    paths" item. Handoff Package and Quick Look ride the same resolution.
    DONE (needs owner build): `nodeDOMID(_:chain:)` composes an id from the whole
    instance chain, outermost first. Depth-1 output is UNCHANGED, so existing
    exports keep their ids and only the previously-colliding depth-2+ cases move.
    `render`, `collectDOMIDs`, and BOTH CSS emitters (`append`, `appendState`) now
    carry the chain — the CSS half matters as much as the HTML: a selector minted
    from a single instance id stops matching its element at depth 2, which would
    have been a silent styling bug rather than a loud one.
    Relationships are now READ FROM ANCHORS, not from `Node.relationships`.
    `anchoredAttributes(...)` resolves one anchor's entries into attributes keyed by
    the DOM id of the element that must carry them, and `render` passes that map
    down so a subject simply looks itself up. Anchors encountered: the document root,
    any group holding entries, and every component source. Reading only the anchored
    form is what makes a DELETE actually delete — emitting both would let a stale
    legacy entry resurrect an attribute the designer removed. Nothing is lost,
    because migration writes an anchored twin at decode.
    The BUG-008 prohibition moved to the point of EMISSION, where the host's role is
    known: `aria-labelledby` on a roleless element is dropped with a
    `prohibitedRelationship` issue, while the two GLOBAL properties are emitted.
    The now-dead legacy `relationshipAttributes` was deleted rather than left in
    place, so there is exactly one read path.
    NOT DONE: I-e's headless checks.
  - **I-e — Fidelity + checks.** Headless coverage for: same group placed twice
    resolving independently; anchor repaired on regroup/ungroup/delete; an endpoint
    whose path no longer resolves reported as `unresolvedRelationship` rather than
    silently dropped; no duplicate ids at depth 2.
    DONE (needs owner build): the REPAIR half, which was the urgent part —
    `CanvasView.ungroup` used to replace a group node with its children and take
    its `anchoredRelationships` with it, destroying authored semantics on an
    ordinary edit with no warning. Entries are now HOISTED to whatever still
    contains both ends: the enclosing group, or the scope root via
    `commitNodes(appendingRootAnchors:)` so the whole thing stays ONE undo step.
    Endpoints need no rewriting, because a path names component instances only and
    never groups. GROUPING needs no repair at all for the same reason — a pleasant
    consequence of the path design, now covered by a check so nobody "fixes" it.
    Explicit DELETE drops relationships naming the removed subtree at either end
    (`Document.removingAnchors(referencing:)`), collected over the whole subtree so
    deleting a group also clears links to layers inside it. Deliberately keyed to a
    specific id set rather than "prune anything unresolved" — a mid-edit tree can be
    briefly unresolvable and a general sweep would eat real work.
    `scripts/AnchoredRelationshipCheck.swift` + `verify_anchored_relationships.sh`
    cover: groups transparent to paths, duplicate independence (BUG-010),
    delete precision, ungroup hoisting, depth-2 id uniqueness with depth-1 output
    unchanged, and migration being lossless AND idempotent.
    NOT DONE: MOVE repair (dragging a node out of its anchor's subtree still strands
    the link — it now reports as orphaned rather than vanishing, which is the
    important half), and the UI to see and clear orphaned entries (BUG-012's
    follow-up).
- Acceptance: author `tab → controls → tabpanel` across two sibling components in
  one group; place that group twice; both copies export correct, distinct,
  non-colliding `aria-controls` / `aria-labelledby`; regroup and ungroup without
  losing links; save/reopen; no cross-placement leakage.

### FEAT-013 — Relationships that vary by component state
- Type: feature (model)
- Priority: P3 — NOT needed for the tabs file after all (see resolved question below); depends on FEAT-012
- Area: model · export · handoff · a11y
- Status: LOGGED 2026-07-24, NOT STARTED
- Origin: owner's Tab Panel is ONE `tabpanel` component holding three text areas
  with two hidden — and confirmed the hiding is deliberate: those are component
  STATES, not three separate panels. That is a coherent model, but it means the
  panel's accessible name has to change with the active state: `aria-labelledby`
  should name whichever tab is currently selected.
- Why it fits EXP rather than fighting it: states are already override-diffs
  against the base, and the exporter already emits `data-state` per active state.
  A relationship that lives in the state diff says exactly the right thing in
  handoff — "in state Tab Two, this panel is named by Tab Two" — without EXP ever
  storing behavior or shipping JS. That is the whole thesis of the file format.
- OPEN QUESTION — NOW RESOLVED, 2026-07-24, and the answer is that FEAT-013 is NOT
  the fix for tabs. Verified against the APG Tabs pattern
  (https://www.w3.org/WAI/ARIA/apg/patterns/tabs/): "Each element that CONTAINS THE
  CONTENT PANEL FOR A TAB has role `tabpanel`", and "when the user activates one of
  the other tab elements, the previously displayed tab panel is HIDDEN, the tab
  panel associated with the activated tab BECOMES VISIBLE." So the pattern has one
  panel PER TAB, all present, with visibility toggling between them — which is
  exactly what a real tabs widget renders.
  That reframes the owner's structure rather than blocking it. Their tab panel
  component holds three text areas with two hidden, modelled as three component
  STATES. Semantically those three areas already ARE three tabpanels; the "states"
  are the visibility toggle the pattern describes. The right structure is three
  roled panels (three instances of a Panel component, each with its own text
  override — supported today at the top level), one per tab, 1:1. That exports
  statically with no dynamic attributes and needs nothing from FEAT-013.
  The reason one shared panel does not work is concrete: `aria-labelledby` on the
  panel must name the ACTIVE tab, so with three tabs it would have to change at
  runtime. Not expressible statically, and EXP ships no JS.
- STILL WORTH BUILDING, for a different reason: a relationship that legitimately
  varies by state — a disclosure whose description differs when expanded, an input
  whose helper text becomes an error message. Those are genuinely per-state and
  have no structural workaround. Re-scope this entry to those cases; do NOT justify
  it with tabs.
- Acceptance: a relationship can be authored per state; the base and each state
  round-trip; export emits the base attribute plus per-state guidance; the handoff
  reads as a sentence a developer can implement; nothing is emitted that implies
  EXP is producing behavior.

### FEAT-014 — Let a plain group carry an ARIA role
- Type: feature (model)
- Priority: P2
- Area: model · inspector · export · a11y
- Status: LOGGED 2026-07-24, NOT STARTED
- Detail: `Node` has no `a11y` at all — only `ComponentSource` does. So a role can
  ONLY be carried by a component instance, which is an EXP artifact, not an ARIA
  one: in ARIA any element may carry a role. The practical cost is that a designer
  must componentize a wrapper just to say "this is a list" or "this is a region",
  and every group that is not a component exports as an unroled `<div>` whose
  implicit role is `generic` — which is exactly the population BUG-008 had to
  suppress relationship offers on.
- Explicitly NOT the fix for FEAT-012. It was considered first and rejected: the
  owner's roles were already on components and correctly placed, so this would
  have changed nothing about their blocked case. Recorded here on its own merits.
- Design question to settle first: precedence when an INSTANCE node carries a role
  and its source also does. Options are node-overrides-source, source-wins, or
  forbid the combination. Pick one deliberately and write it down — an ambiguous
  precedence rule here would rot quietly for years.
- Acceptance: a group can be given any curated role; the inspector offers the same
  picker it offers a component; export emits the role on the group element; the
  containment advice and relationship rules treat it exactly like a roled instance;
  old files decode unchanged.

### BUG-008 — Relationship authoring offers ARIA kinds on layers that cannot carry them
- Type: bug
- Priority: P1 (soon)
- Area: model · inspector · export · a11y
- Status: done (owner verified 2026-07-27). Shipped together
  with FEAT-011 as the owner sequenced. What landed:
  - `NodeRelationship.Kind.isProhibitedWithoutRole` — true for `labelledby` ONLY.
    The doc comment spells out why the other two are not the same case, so nobody
    "tidies" the three into one rule later.
  - `A11ySemantics.rootRelationships` — the component's OWN relationships, stored
    on the SOURCE (tolerant decode; absent in every pre-v2.1 file). Owner chose
    the "component root row in the source editor" option over authoring on a
    placed instance, so these are part of the component CONTRACT and two uses
    cannot drift apart.
  - Inspector: `layerRelationshipKinds` now reads the selected layer's OWN
    effective export role (`effectiveExportRole(of:)` — an instance carries its
    source's role, everything else has none), not the enclosing source's. The
    Relationships section splits into "This component" and "This layer"; the
    layer block appears only when that layer has a role of its own or already has
    authored relationships. A note under a roleless layer distinguishes the
    prohibited case from the merely-pointless one.
  - Exporter: `relationshipAttributes(hostRole:authored:)` drops a prohibited
    naming attribute and raises a `prohibitedRelationship` fidelity issue;
    root relationships are emitted on the instance-hosting element, resolved
    per-instance so two uses never cross-link.
  - `Document.flattened` carries root `controls`/`describedby` onto the group
    that replaces a deleted source's instance (retargeted via the existing
    id map) and drops root naming, which is invalid on a roleless group.
  - Menu validation updated in BOTH `MainWindow` and `CanvasView` so the Object ▸
    Relationships… item and the panel can never disagree.
  - Document-scope authoring + the NEIGHBOURHOOD rule (added same day, after the
    owner pointed out that a tab and its panel are two PLACED instances, so
    nothing was testable without it). Relationships now render on the canvas for
    any layer with a role of its own. Targets come from the nearest enclosing
    GROUP and there is NO artboard fallback — owner call: an artboard fallback
    quietly reintroduces the long-list problem and makes the rule change with
    context, whereas "things you connect live in a group together" is one rule
    that always holds, and it is how the owner already works ("I put them in
    groups already because I don't want to accidentally move the tab titles away
    from the tab content"). An ungrouped selection gets an INSTRUCTION naming
    ⌘G, not an empty dropdown; already-authored links are kept and still export,
    and the note says so. Targets walk into groups but NOT into component
    instances, since a layer inside another component is not addressable from
    outside — its id is minted per instance at export. The picker annotates each
    target with its role ("Panel One — Tab Panel") so choosing is not guesswork.
  Real-world acceptance was initially blocked by FEAT-012 because the required
  tab → panel link crosses a component boundary and varies per placement. That
  path is now built, and the owner verified this bug's acceptance behavior on
  2026-07-27. Widening the picker globally remains explicitly not the fix.
- Repro/Detail: Owner report 2026-07-24. Editing a component categorized Tab
  Panel, EVERY layer inside it offers Labelled By and Described By — a decorative
  rectangle, a background group, any text layer.
- VERIFIED against WAI-ARIA 1.2 / MDN — 2026-07-24, EXTENDED 2026-07-24 (2nd session):
  1. ARIA roles do NOT inherit. Each element has its own role, explicit or
     implicit; nothing cascades to descendants. So deriving a layer's available
     relationship kinds from its CONTAINER's role has no basis in the spec.
  2. An unroled group/rectangle exports as `<div>`, whose implicit role is
     `generic`. MDN on the generic role: "Because the generic role is nameless,
     the aria-labelledby and aria-label attributes are prohibited," and
     aria-labelledby lists `generic` among the roles it is NOT supported on. So
     the offer is not merely noisy — the attribute is invalid there. The same
     sentence also prohibits `aria-roledescription` and
     `aria-brailleroledescription` on `generic`; EXP emits neither, so nothing to
     do there. https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Reference/Roles/generic_role
  3. None of EXP's curated roles are in the naming-prohibited list
     (caption, code, deletion, emphasis, generic, insertion, mark, paragraph,
     presentation/none, strong, subscript, suggestion, superscript, term, time),
     so every category EXP offers does support naming. Only the NO-ROLE case is
     the problem.
  4. tabpanel + aria-labelledby is CORRECT and expected — the WAI-APG tabs
     pattern labels the panel by its tab, and `SemanticHTMLContract` already
     lists `.labelledByRelationship` as a requirement for tabpanel. Do not
     remove it.
  5. CORRECTION — `aria-controls` IS global. This entry previously assumed it was
     not, and planned to enforce a supported-roles list. There is no such list to
     enforce. MDN: "The global `aria-controls` property…"; Associated roles:
     "Used in **ALL** roles."
     https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Reference/Attributes/aria-controls
  6. `aria-describedby` IS global and carries NO role prohibition. MDN: "The
     global `aria-describedby` attribute…"; Associated roles: "Used in **all**
     roles. Usable in all HTML elements as well."
     https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Reference/Attributes/aria-describedby
  7. CONSEQUENCE — the three kinds are NOT the same kind of problem, and the fix
     must not flatten them into one rule:
     - `labelledby` on an unroled layer is a CONFORMANCE violation. Authors MUST
       NOT set a prohibited property (WAI-ARIA 1.2 §5.2.5). Suppress the offer and
       never emit the attribute.
     - `describedby` and `controls` on an unroled layer are spec-VALID. They are
       merely pointless: a `generic` element is nameless and, per MDN, is exposed
       to accessibility APIs only "so that assistive technologies can gather
       certain properties such as layout and bounds" — so a description hung on it
       has no named thing to attach to, and `aria-controls` only means anything on
       an element a user can actually operate. Treat these as a QUALITY default
       (do not offer them on unroled layers, do not invent them) rather than as a
       prohibition. UI copy and fidelity issues MUST NOT call them invalid.
  NOT VERIFIED — stated explicitly so it is not mistaken for settled:
  - WAI-ARIA 1.2 §6.5 "Global States and Properties" was NOT read verbatim; the
    W3C TR fetch truncated before that section. The globality claims in 5 and 6
    rest on MDN, which cites https://w3c.github.io/aria/#aria-controls and
    #aria-describedby. Re-read the spec text before relying on this for any
    stricter rule than "do not offer by default."
  - No screen-reader behavior was tested. Whether VoiceOver/NVDA/JAWS actually
    announce a description on a generic div is an implementation question, not a
    spec one; nothing above depends on the answer.
  - MDN's generic-role line "If a global ARIA state and property is set, `generic`
    or `none` will be ignored, and the implicit role of the element will be used"
    was read but NOT resolved. It concerns an EXPLICITLY authored
    `role="generic"`/`role="none"`, and EXP emits neither. Do not build on it.
- Root cause / modeling gap: `availableRelationshipKinds` reads
  `document.model.source(for: sid)?.a11y.role` — the CONTAINER's role — and
  offers those kinds on every node in the source. But the exporter puts
  `source.a11y.role` on the element hosting the INSTANCE, so every layer inside a
  source is an unroled div. Meanwhile `relationshipControls` only renders in
  `.source` scope. Net effect: the kinds are offered exactly where they are
  invalid, and there is currently NO conformant place to author the component's
  own relationships, because the element that carries the role is the instance
  and that is not selectable from inside the component.
- Proposed fix: derive kinds from the node's OWN effective export role —
  a `.instance` node uses its source's role, any other layer has no role and so
  offers nothing — and give the component's own relationships a home (either
  author them on a placed instance in document scope, or add an explicit
  "component root" row in the source editor that stands for the instance
  element). Keep already-authored relationships visible and editable regardless,
  so nothing is stranded. Emit nothing for a layer with no role.
  Per finding 7, the SUPPRESSION reason differs by kind and the code should say
  so: `labelledby` is suppressed because it is prohibited, `describedby` and
  `controls` because they are meaningless on a nameless container. No
  supported-roles gate is needed for `aria-controls` — it is global (finding 5).
- Design constraint — RELATIONSHIP SCOPE ("neighborhood", not global). Owner
  call 2026-07-24: once a component can point at something outside itself, the
  target list must NOT be the whole document. Scope it to the nearest meaningful
  container — the enclosing artboard, or an enclosing group — because a real
  document with hundreds of components would otherwise produce novel-length
  dropdowns that are unusable for everyone and actively hostile with a screen
  reader or keyboard. This also matches the DOM reality: `aria-labelledby` and
  friends are id references resolved within a document, and EXP already reports
  an `unresolvedRelationship` fidelity issue when a target lands outside the
  exported artboard (`SemanticHTMLExporter.relationshipAttributes`) — so
  artboard-scoping the PICKER simply stops people authoring links the exporter
  is going to reject anyway.
  Today `relationshipTargets` collects from `relationshipSourceNodes`, i.e. the
  current source's own children, so the scaling problem does not exist yet — it
  appears the moment this fix opens targets up. Decide the scope rule in the
  SAME change, not after. Sketch: default to the enclosing artboard, narrow to
  the enclosing group when one exists, show the container's name in the picker
  so the boundary is visible, and keep an already-authored out-of-scope target
  selectable-but-flagged rather than silently dropping it.
- Acceptance: no relationship kind is offered on a layer that would export as an
  unroled div; a Tab Panel component can still be labelled by its tab; existing
  authored relationships survive and remain editable; the semantic export emits
  no `aria-labelledby` on a `generic` host; the target picker is scoped to the
  artboard/group rather than the document and stays usable at 100+ components;
  headless check covers each case.

### FEAT-011 — Plain-language relationship UI (translate ARIA out of the interface)
- Type: feature
- Priority: P2
- Area: inspector · a11y · content design
- Status: WRITTEN 2026-07-24, NOT YET BUILT OR OWNER-VERIFIED. Shipped inside the
  BUG-008 change as sequenced. `NodeRelationship.Kind.friendlyLabel(for:)` and
  `.friendlyHelp(for:)` carry the wording; `label` is now documented as
  internal-only (undo action names, diagnostics) and no longer reaches the
  inspector. Owner chose HELP-TIP-ONLY for the raw attribute: the plain-language
  phrase is the primary label, the literal `aria-*` name appears in the hover tip
  and the VoiceOver hint, and nothing extra is added to the row — which also
  keeps FEAT-010's cramped-panel problem from getting worse.
  Wording that shipped: Tab ▸ controls = "Opens this panel"; button/link/menuitem/
  option ▸ controls = "Opens or changes"; otherwise "Operates". Tab Panel ▸
  labelledby = "Named by its tab"; dialog/alertdialog = "Named by its title";
  otherwise "Gets its name from". describedby = "Helper or error text" on form
  controls, "Extra explanation" elsewhere.
  STILL TO REVIEW: the wording has NOT been read back against every WAI-APG
  pattern — only tab/tabpanel and the dialog naming case were checked, since
  those are the ones a rename could make factually wrong. The generic phrasings
  are content-design judgment, not verified spec claims.
- Repro/Detail: Owner insight 2026-07-24, and it is a good one: "I was confusing
  labelled by as only being relevant to form elements... I bet others would be
  confused as well." Working inside tab-one's content, the expected mental model
  was "link/connect this to the tab nav item" — not "labelled by." The owner has
  a11y training and still finds Described By hard to hold onto; most designers do
  not think in ARIA vocabulary at all.
- Detail: keep the functionality and the emitted attributes exactly as they are —
  change only the words, and make them context-aware. The ARIA token should be
  secondary/on-hover for people who want it, not the primary label.
  Sketch, to be refined:
  - `controls` on a Tab → "Opens this panel" (aria-controls)
  - `labelledby` on a Tab Panel → "Named by its tab" (aria-labelledby)
  - `labelledby` generally → "Gets its name from…" with the hint that the target
    is the visible text a screen reader will read as this thing's name
  - `describedby` → "Extra explanation" / "Has helper text…" — framed as the
    hint, error, or helper text read AFTER the name, which is the part that is
    hard to remember
  Show the role-specific phrasing when the role is known, fall back to the
  generic phrasing otherwise, and keep the literal attribute in the help tip so
  the mapping stays learnable rather than hidden.
- Acceptance: no ARIA attribute name appears as a primary label; each phrasing is
  correct for the role in context; the underlying attribute is discoverable on
  hover and in the handoff; VoiceOver reads the friendly label; wording reviewed
  against the WAI-APG pattern for each role so nothing is renamed into being
  wrong.
- Note on standards language: the ADA does not specify ARIA. The applicable
  technical standards are WCAG 2.1 AA (DOJ Title II rule, Section 508,
  EN 301 549) plus WAI-ARIA 1.2 and ARIA in HTML. Use those names in docs and
  UI copy rather than "ADA compliant."
- SEQUENCING — ships WITH the component-classification work, not after it. Owner
  call 2026-07-24: roll this in as soon as work starts on adjusting and verifying
  the component classification / role authoring surfaces (BUG-008 and the
  remaining Chunk I containment items). The reasoning is sound — those changes
  are already rewriting when and where each relationship kind is offered, so
  rewording them at the same time costs almost nothing extra, whereas doing it
  later means touching the same views twice and shipping one release where the
  offers are correct but still unreadable to most designers. Treat FEAT-011 as
  part of that work's definition of done, not as a follow-up ticket.

### FEAT-009 — Per-corner radius ("Advanced") for Auto Padding / Auto Layout groups
- Type: feature
- Priority: P2
- Area: model · inspector · canvas · export
- Status: open
- Repro/Detail: Owner request 2026-07-24. An auto-padding group draws its own
  background with a single `cornerRadius`. Rectangles already support four
  independent corners; auto groups should match, behind the same "Advanced"
  disclosure so the simple case stays one field.
- Hypothesis: mostly mirroring work — the pattern already exists end to end.
  `RectangleShape` has `cornerRadii: CornerRadii?` plus
  `effectiveRadii { cornerRadii ?? CornerRadii(all: cornerRadius) }`, and the
  inspector already has the disclosure (`cornersAdvancedOpen`, the `cornerField`
  helper, and the "Matching all four snaps back to the single Corner field."
  hint) in `shapeControls`. Add the same optional field + `effectiveRadii` to
  `AutoPadding` with a tolerant decode, then update the draw and emit sites:
  `CanvasView.swift:~4892` (`pad.cornerRadius * z`), `PanelDock.swift:~793`
  (component preview thumbnail), `ExportRenderer.swift:~284/291` (SVG `rx`, plus
  the inset stroke radius), and `SemanticHTMLExporter.swift:~1025`
  (`border-radius`). Reuse whatever rounded-path builder the rectangle per-corner
  drawing already uses rather than writing a second one.
  `AutoLayoutEngine.swift:~210` (`pad.cornerRadius = style.corner`) converts a
  background child into auto padding — decide there whether a per-corner
  rectangle promotes its four radii.
- Acceptance: four corners settable and independent; matching all four collapses
  back to the single field; canvas, component preview, SVG, and semantic HTML all
  render the same shape; old documents decode unchanged; one undo step per edit;
  fields keyboard reachable with correct VoiceOver labels.

### FEAT-010 — Inspector/panel responsiveness pass + user type-size preference
- Type: feature
- Priority: P2
- Area: chrome · inspector · a11y
- Status: open
- Repro/Detail: Owner report 2026-07-24 with screenshot. At the right panel's
  DEFAULT width, the left edge of most rows sits very close to — or slightly
  clipped by — the panel edge, and the right scrollbar crowds the controls.
  Wanted: panel layouts that flex instead of assuming one width. Controls should
  be able to drop below their label when horizontal space runs out rather than
  truncating, sections should reflow at narrow widths, and the whole thing needs
  to survive a user-chosen larger UI type size.
- Hypothesis: the rows are built as fixed `HStack`s with fixed-width `TextField`s
  (`.frame(width: 56)` is used throughout), so they cannot reflow. Likely shape:
  a shared adaptive row container that switches label-beside → label-above under
  a width threshold via `ViewThatFits` or a measured container width, plus
  auditing the fixed frames into min/ideal widths. The type-size preference
  should ride Dynamic Type / the existing `EXPType` scale rather than a bespoke
  multiplier, so it composes with the system accessibility settings EXP already
  promises to follow. Reserve gutter space for the scrollbar.
- Acceptance: no clipped labels or controls at the default panel width; panels
  remain usable when narrowed and when the user raises the UI type size; nothing
  truncates without an accessible full value; VoiceOver order stays correct in
  both the beside and above arrangements; verified in light/dark and increased
  contrast.
- Fit: owner suggested "another polish version soonish" — sequence it as its own
  polish release alongside the F2 panel/tool-discoverability pass rather than
  squeezing it into v2.1.

### FEAT-008 — Font picker: remember scroll position, plus "Fonts used" and "Recent fonts" filters
- Type: feature
- Priority: P2
- Area: inspector · chrome
- Status: open
- Repro/Detail: Owner request 2026-07-24. Changing a font means scrolling the
  whole font list from the top every single time. Designers routinely have
  hundreds of families installed, so the list is long and the same handful of
  faces get used over and over.
  Wanted: (a) the picker reopens where it was — scrolled to, and highlighting,
  the currently applied font rather than the top of the list; (b) a **Fonts
  used** filter scoped to the current document, built from the faces actually
  referenced by text nodes, component sources, and type styles; (c) a **Recent
  fonts** filter persisted across sessions (app-level, not per document).
  ADDED 2026-07-24 after using (a): (d) **type-to-jump** — start typing a name and
  the list jumps to it, the behaviour every long list in macOS has and the thing
  that makes a few hundred families genuinely navigable; (e) a **search/filter
  field** over the same list. Owner's words: "some ideas for the improvements for
  v2.2 including some filtering, or start typing to jump to a font." Both belong on
  `FontFamilyPicker` alongside (b) and (c) — four filters over ONE list, not four
  controls. Owner also reported the shorter popover "scrolls better with more
  control" than the old full-length menu, so the fixed 320pt height is a deliberate
  keeper rather than an arbitrary number.
- Hypothesis: (a) is the cheap, high-value half and could ship on its own —
  scroll-to-current-selection on open is a small change and fixes the daily
  irritation. (b) reuses the same document walk the Design Language panel and
  the handoff type audit already do to enumerate faces in use. (c) needs a small
  UserDefaults MRU list, capped, deduped by family.
- Acceptance: opening the picker lands on the current font with it visibly
  marked; the two filters narrow the list and are reachable by keyboard with
  correct VoiceOver labels; filter choice persists sensibly between openings;
  an empty "Fonts used" or "Recent" state explains itself rather than showing a
  blank list.
- Fit: (b) and (c) stay in **v2.2** with the panel/tool-discoverability work.
- **(a) PULLED FORWARD into v2.1, WRITTEN 2026-07-24, needs owner build.** Owner
  call: keep v2.1 focused but take the cheap relief now.
  Implemented as `UI/FontFamilyPicker.swift`, a shared popover replacing the two
  `Menu`-of-`Button` call sites in the inspector (single text, and the
  multi-selection Type section).
  WHY NOT A PLAIN `Picker`: it would give scroll-to-selection and a checkmark for
  free, but menu items in a SwiftUI `Picker` do not reliably render in a custom
  face, and seeing each family SET IN ITSELF is most of the value of a typeface
  list in a design tool. Trading that away for free scrolling would have been a
  quiet regression in exactly the thing the control is for. A popover +
  `ScrollViewReader` keeps the previews AND scrolls.
  Details worth keeping: scrolls with `.center` anchor rather than `.top`, so the
  neighbouring faces are visible — picking a sibling face is the common next move;
  the checkmark column is reserved whether or not it is ticked, so names stay
  aligned and the list does not jitter; a multi-selection passes a fixed label and
  ticks nothing, which is honest about there being no single value; the System row
  is keyed on an EMPTY family, matching the model's meaning of `fontName == ""`
  ("no face chosen") rather than inventing a family called System.
  This is also where (b)–(e) belong — "Fonts used", "Recent fonts", type-to-jump
  and search are all filters/navigation over THIS list, not separate controls.
  BUG FIXED SAME DAY, owner-reported: on first open the rows ABOVE the selected
  font rendered as blank space until a real scroll brought them in. A `LazyVStack`
  only builds the rows it believes are visible, and the `onAppear` scroll ran
  before the popover had been laid out — so the surrounding rows were never built.
  Now scrolled twice: once immediately, then again via `DispatchQueue.main.async`
  after layout, when the visible window is known. The comment says why, because a
  duplicated-looking call is exactly what a future reader would "clean up."

### FEAT-001 — Color: saved / recent colors + palettes (doc-linked, import/export)
- Type: feature
- Priority: P2
- Area: color · model
- Status: in progress (Session 167) — document model + panel save/pick/recents landed; import/export (FEAT-007/18e) still open
- Repro/Detail: Recent-colors strip and a saved-swatches area in the color popover;
  named colors that live ON the document (so they travel with the file) AND can be
  exported/imported to share between documents. This is the first slice of ROADMAP
  Phase 18's Design Language model: document-local assets, not app chrome tokens.
- Hypothesis: add a document-level `DesignLanguage` or `colorLibrary` with
  `recentPaints` plus named entries (`id`, `name`, `status: candidate/official/
  archived`, `value`, provenance). Backward-compatible decode. Surface a minimal
  save/pick flow in `ColorPopover` first; graduate to the Design Language panel in
  FEAT-006. Generation can reuse `ColorMath` (OKLCH) for perceptually-even ramps.
- Acceptance: pick from recents/saved; save and rename a swatch; mark candidate vs.
  official; export a small JSON from doc A and import into doc B; entries persist in
  the `.design` file.

### FEAT-002 — Color-mode-specific picker behavior
- Type: feature
- Priority: P3
- Area: color
- Status: in progress (Session 166) — HSB/HSL/OKLCH mode-aware controls + sRGB gamut warning landed; wide-gamut ColorValue not pursued
- Repro/Detail: Phase 8 can type/copy HSL/LCH/OKLCH, but the visual editor is still
  essentially HSB/SV + hue/alpha with sRGB storage. Owner wants truly model-aware
  authoring, especially HSL and OKLCH, with honest gamut handling.
- Hypothesis: redesign `ColorPopover` around editing modes. HSB/HSL/OKLCH each get
  controls that match their axes; OKLCH should also drive ramp/adjustment helpers.
  Before adding Display-P3, decide whether the model stays sRGB-with-warnings or
  grows a richer `ColorValue(colorSpace:components:)`.
- Acceptance: switching mode changes the picker's controls, not just its code field;
  OKLCH edits can warn when clamped to sRGB; copied values match the selected mode.

### FEAT-003 — In-app bug/feedback reporter (agent-ingestible)
- Type: feature
- Priority: P2
- Area: infra · chrome
- Status: open
- Repro/Detail: A Help ▸ "Report an Issue / Idea…" that opens a small form (title,
  type: bug/idea, description, optional screenshot) and auto-attaches CONTEXT:
  app version, macOS version, current tool, selection summary, doc stats (artboards/
  nodes/sources), and the last few undo action names. Writes a structured record.
- Hypothesis: capture to a Markdown/JSON file matching THIS backlog's entry format
  (so an agent can drop it straight into Bugs), saved to a chosen folder and/or opened
  as a prefilled GitHub issue / mail draft. Keep the payload PII-free (no doc content,
  just stats) unless the user opts to attach the file.
- Acceptance: one action produces a ready-to-triage entry with reproducible context;
  agents can read the folder and pick items up.

### FEAT-005 — Color contrast checker (WCAG-first, APCA advisory)
- Type: feature
- Priority: P2
- Area: color · inspector · a11y
- Status: in progress (Session 166) — ContrastMath (WCAG 2.x) + picker contrast strip landed; APCA and panel comparisons pending
- Repro/Detail: Designers need to check foreground/background contrast while choosing
  colors, saving library entries, and editing text/fills. This should be part of the
  color workflow, not a separate external chore.
- Hypothesis: add pure `ContrastMath` beside `ColorMath`: WCAG 2.x relative
  luminance/contrast ratio, AA/AAA thresholds for normal text, large text, and
  non-text UI components. Flatten alpha colors over the relevant artboard/background.
  APCA can appear as advisory/exploratory if useful, but not as the primary pass/fail.
- Acceptance: picker/panel can compare two colors, selected text vs. background, and
  library swatch pairs; labels are clear; suggestions can adjust OKLCH lightness to
  reach AA without silently changing the document.

### FEAT-006 — Design Language panel (colors + gradients first)
- Type: feature
- Priority: P2
- Area: color · chrome · model
- Status: in progress (Session 167) — panel live with sections + apply/save/promote/rename/copy; in-place value edit, reveal-uses, and menu-bar command pending
- Repro/Detail: The reserved Color panel should grow into a document-local "Design
  Language" panel, similar in spirit to Components/library panels: saved colors,
  gradients, candidates/maybes, official entries, and later type/spacing/effects.
- Hypothesis: add `PanelID.designLanguage` (or rename the reserved Color panel) using
  the existing host-agnostic panel pattern. Sections: Official Colors, Candidate
  Colors, Gradients, Recents. Actions: apply to selection, rename/edit, promote,
  archive, copy values, import/export, reveal uses.
- Acceptance: panel works docked/floating, reflects the document model live, and lets
  the owner move a candidate color/gradient into the official list.

### FEAT-007 — Palette inspiration/import providers
- Type: feature
- Priority: P3
- Area: color · import
- Status: in progress (Session 169) — import + local generators done (EXP JSON / CSS / paste / OKLCH ramp / harmonies / accessible pair); image extraction + remote providers still open
- Repro/Detail: Owner wants to browse/import palette inspiration from places like
  Adobe Color, Coolors, RandomA11y, and Figma palettes, with an easy way to add
  options to the document as candidates or official entries.
- Hypothesis: build a provider/import framework before any service-specific UI. Local
  providers first: OKLCH ramps, harmonies, accessible pairs, image extraction. Remote
  or web sources should use documented APIs, user-pasted URLs, or exported files only;
  avoid scraping private/undocumented endpoints. Research snapshot lives in ROADMAP
  Phase 18f.
- Acceptance: paste/import a palette representation into the document as candidates;
  local generation produces usable options; each imported option keeps a visible source
  label/provenance.

---

## ⚡ Performance

### PERF-005 — instCacheHit/Miss counters flat at 0 — verify they still track
- Type: perf
- Priority: P3 (someday)
- Area: perf
- Status: open
- Repro/Detail: Both Testing Mode counters read 0 (max 0) across every sample
  in the 2026-07-09 v1.2.1 logs. The doc under test may simply contain no
  component instances — but if the counters are ALSO flat on an
  instance-heavy doc, the instrumentation (or the instance cache itself) has
  silently stopped tracking. Owner is keeping an eye out.
- Hypothesis: Doc had no instances (benign) OR counter increments were lost in
  a refactor (check the instance-cache hit/miss paths against the
  resolveGeneration invariants).
- Acceptance: Testing Mode on an instance-heavy doc shows nonzero hits/misses;
  or confirmed benign and this entry closed with a note.

### PERF-001 — Large / complex document performance (standing epic)
- Type: perf
- Priority: P2 (ongoing)
- Area: perf · canvas · model
- Status: open
- Repro/Detail: Keep interaction smooth (pan/zoom/drag ~60fps, fast open/save) as
  documents grow — many artboards, deep groups, many component instances, heavy paths.
- Hypothesis / levers: profile with Instruments (Time Profiler + Core Animation) on a
  stress doc; known areas — the CPU Core-Graphics canvas redraw, instance re-resolve
  cache (see the `exp-canvas-perf` memory note: culling + `resolveGeneration` invariants),
  background-blur readback (already deferred during gestures), SVG export walk. Possible
  moves: tighter dirty-rect invalidation, cache laid-out instances harder, move blur/
  compositing to a GPU/Metal layer (its own phase, see ROADMAP 16.5).
- Acceptance: a repeatable stress-test doc + before/after frame-time numbers; no
  interaction regressions.

---

### PERF-002 — Blend/opacity fidelity while dragging (conditional true-composite mode)
- Type: perf · feature
- Priority: P2
- Area: canvas · perf
- Status: needs-verify (Session 162 — implemented as the per-gesture TRUE/FAST
  decision in `CanvasNSView.shouldTrueCompositeDrag`: dragged subtree uses a
  non-normal blend mode AND `fullFrameEMA` (always-on rolling full-render cost)
  fits the budget from the user's performance mode → full live render for the
  gesture; else fast blit. The cheaper "re-render only the ABOVE region" middle
  option is NOT built — revisit if TRUE mode's budgets feel too conservative.)
- Repro/Detail: With the Session 161i drag-overlay blit, a shape with a blend
  mode (difference/overlay/…) reads as its plain color against anything baked
  into the ABOVE snapshot layer while it's being moved — it only composites
  truly against content BELOW it, and snaps to the correct look on mouseUp.
  Owner wants design-truth kept while moving when the doc can afford it.
- Hypothesis: conditional fidelity. During a drag, choose per-gesture between
  (a) TRUE mode — full live render every tick (the pre-161i path, correct
  compositing) and (b) FAST mode — the current below/above blit. Pick TRUE
  when the gesture is cheap enough: e.g. recent full-frame cost < ~20ms, or
  visible node count under a threshold, or the dragged node has a non-normal
  blend mode AND the scene is small; else FAST. The measured `frame` perf
  stats already exist to drive the decision. Cheaper middle option worth
  trying first: when ANY dragged node has a non-normal blend mode, re-render
  only the ABOVE layer's intersecting region live instead of blitting it.
- Acceptance: moving a difference/overlay shape over other content keeps its
  true composite on small/medium docs; huge docs degrade gracefully to FAST
  with no beachball; no regression to the 1.5–3.6ms drag frames in FAST mode.

### PERF-003 — Panning refinements (bigger/smarter snapshot)
- Type: perf
- Priority: P3
- Area: canvas · perf
- Status: open (partial — halo size + settle delay are now user-tuned via
  PERF-004; adaptive/directional halo and tiled snapshots still open)
- Repro/Detail: 161j's 25% halo + containment recapture works, but long fast
  pans still hit periodic ~30–80ms recaptures, and the settle render redraws
  everything. Ideas queue: adaptive halo (grow toward pan direction/velocity),
  tile-based snapshot (recapture only newly exposed tiles), reuse the drag
  blit's below/above machinery for partial invalidation.
- Acceptance: flick-panning a huge doc shows no blank edges AND no visible
  hitch; Testing Mode shows recapture cost amortized under one frame.

### PERF-004 — User-facing "Speed ↔ Detail" preference (Photoshop memory dial, humane edition)
- Type: feature
- Priority: P3
- Area: chrome · perf
- Status: needs-verify (Session 162 — Settings ▸ Canvas ▸ Performance:
  EXPSegmented "Speed focus / Balanced / Detail focus", persisted via the
  synced-prefs pattern (`AppState.CanvasPerformanceMode`,
  `exp.pref.performanceMode`). Drives: TRUE-drag budget 0/18/40ms, pan halo
  0.15/0.25/0.40, settle delay 0.12/0.08/0.05s. A11y label + hint on the
  control; plain-language footnote.)
- Repro/Detail: Owner idea: a single friendly setting (Settings ▸ Canvas) —
  a slider or segmented control from "Speed focus" to "Design detail focus" —
  instead of Photoshop's raw memory-% dial. It would set the thresholds used
  by PERF-002's conditional fidelity (and possibly halo size, mip cache
  budget, settle delay). Defaults = current behavior ("balanced").
- Hypothesis: implement AFTER PERF-002 proves out the thresholds; the setting
  is just exposing those constants. Follow the command-coverage rule for any
  user-facing control, and persist via the existing settings store.
- Acceptance: moving the control observably trades drag/pan fidelity against
  frame cost, survives relaunch, is fully keyboard/VoiceOver accessible.

### PERF-005 — Ruler pointer markers force a full canvas redraw per mouse move
- Type: perf
- Priority: P2
- Area: canvas · perf
- Status: open
- Repro/Detail: With rulers shown, `mouseMoved` sets `needsDisplay = true` to
  update the two accent pointer lines — a FULL scene render per mouse twitch.
  On the image-heavy doc (frames ~60–80ms) this reads as constant sluggishness
  even when nothing is being edited (visible in the 162c/d logs as repeated
  frame lines a few per second while idle).
- Hypothesis: the clean fix is a RETAINED last-frame snapshot: let the settle
  render also capture the scene (the machinery exists — capturePanZoomSnapshot),
  keep it while the transform + model are unchanged, and let ruler-marker /
  hover-only updates blit it + redraw rulers/chrome. This generalizes the pan
  blit into "idle repaints are blits," which also covers selection flashes.
  Cheaper stopgap: draw pointer markers in an NSView overlay above the canvas
  so marker moves never touch the canvas at all.
- Acceptance: with rulers on, waving the mouse over a heavy doc produces no
  full renders (Testing Mode shows no frame lines from pointer movement);
  markers still track exactly.

### FEAT-004 — Wider zoom-out range for "the wall is everything" workflows
- Type: feature
- Priority: P2
- Area: canvas
- Status: open
- Repro/Detail: Owner's process spreads branding, color tests, archives, and
  inspiration "miles" apart on the wall and zooms way out for the big picture.
  `AppState.minZoom` is 5% (a pre-original-perf-work constant) — potentially
  too tight for that. Owner suggestion: if a floor is still needed for
  performance, tie it to the Speed↔Detail performance setting.
- Hypothesis: lower `minZoom` to ~1% (0.01) and verify: extreme-zoom-out
  full renders scale with total node count (culling can't help when all is
  visible) but the pan/zoom blit covers gestures; check `rulerStep`,
  `pxSnap` UX (1 screen px = 100 doc px at 1%), and the zoom slider's log
  mapping still feel right. Only add a performance-mode-dependent floor if
  measured frames actually justify one.
- Acceptance: owner can zoom out far enough to see their whole wall on real
  documents without the app feeling broken; zoom slider/field/menu items all
  respect the new range.

## 🛠 Infrastructure

### INFRA-001 — One-command "approve → Roadmap → website" triage sync
- Type: feature (workflow/tooling)
- Priority: P2
- Area: infra
- Status: open
- Repro/Detail: When the owner approves a bug/idea (here, in GitHub Issues, or from
  the in-app reporter), it should be easy to PROMOTE it: move it out of the queue and
  onto the ROADMAP — and have the public roadmap on expdesign.app update automatically.
- Hypothesis / approach:
  1. **Canonical source:** keep a machine-readable roadmap the site can read —
     e.g. `docs/roadmap.json` (or a curated "public" subset) with `{id, title, area,
     status: planned|in-progress|shipped, blurb}`. ROADMAP.md stays the human plan;
     roadmap.json is the feed. (Or generate roadmap.json FROM tagged ROADMAP entries.)
  2. **Promote step:** an agent/skill "promote <ID>" that (a) moves the BACKLOG/issue
     item into ROADMAP.md as a phase/task, (b) appends/updates its entry in
     roadmap.json with `status`, (c) closes the GitHub issue with a "→ roadmap" label,
     (d) adds a ROADMAP Progress Log line.
  3. **Website sync:** if the site is static and reads `roadmap.json` from the repo,
     a push (or the site's build hook) republishes automatically; if the site fetches
     at runtime, point it at the raw file / a small endpoint. NEEDS: confirm the
     site's stack + how it currently sources roadmap/changelog content.
- Acceptance: approving an item + running one command updates ROADMAP.md, roadmap.json,
  and the GitHub issue in sync; the website reflects it on its next deploy with no
  hand-editing.

### INFRA-002 — Point the reporters at the real repo (small setup)
- Type: chore
- Priority: P1 (once the GitHub repo exists)
- Area: infra
- Status: open
- Detail: Set `FeedbackConfig.githubRepo = "owner/repo"` in `UI/Feedback.swift` and
  replace `OWNER/REPO` in `.github/ISSUE_TEMPLATE/config.yml`. Then the in-app "Send
  Feedback" opens a prefilled New Issue instead of the website fallback.

---

## Notes
- **v2.1 release alignment audit (2026-07-28):** every bug and bounded feature
  closed during the nested-component, pages, XD/Figma import, and Handoff cycle
  is marked `done` with owner verification. The website's generated known-issues
  feed therefore exposes BUG-004 as the only open item whose type is `bug`;
  longer-term feature and performance entries remain honestly open and are not
  release blockers unless promoted into a release gate.
- When an item ships, set `Status: done`, keep it here for one cycle for reference,
  then prune (or move a short line to ROADMAP's Progress Log).
- Big architectural features still get a real phase in ROADMAP.md; this list is for
  the smaller, pick-up-able queue.
