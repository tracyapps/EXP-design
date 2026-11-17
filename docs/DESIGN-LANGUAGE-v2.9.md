# v2.9 — Design Language focus

Owner-selected November 9, 2026. Development identity: **2.9 / build 20**.
This is the next-release to-do and interaction brief, not implemented behavior.
Public v2.8/build 19 remains immutable. ROADMAP.md tracks the sequence.
**November 16:** the model, slices, guide and import/export plan now live in
`DESIGN-LANGUAGE-PLAN.md`. This brief stays authoritative for the spacing
select/link/update/detach interaction.

## Selected work

- **FEAT-088 — Color modes:** make the modes already preserved on imported
  tokens usable in the Design Language, with named mode values, editing and
  predictable application to linked colors. Light/dark are examples; decide the
  initial mode vocabulary and scope before implementation.
- **FEAT-089 — Spacing tokens:** create/edit named spacing values in the Design
  Language and use them in existing numeric layout controls. Start with automatic
  spacing/gap and element margin/padding where those controls are supported.
  Survey other useful numeric fields afterward; those are follow-up candidates.

Existing v2.8 import retains aliases, modes and non-color tokens. That is data
preservation, not a native mode-switching or live spacing-binding implementation.
Full component contracts/changesets/library-revision refresh remain their own
FEAT-083–085 queue; they are not prerequisites silently added to this release.

## Spacing interaction — owner's November 9 direction

Keep the existing number/text field and its ordinary manual-entry behavior.
When spacing tokens are available, provide an adjacent named-token selector
(dropdown or an equally clear control; exact presentation is still to design).

| Action | Numeric field | Token selector / relationship |
| --- | --- | --- |
| Enter a number normally | Uses the entered value | None / unlinked |
| Select a spacing token | Displays that token's resolved numeric value | Shows the token name; linked |
| Change the token in Design Language | Updates to the new resolved value | Remains linked; every use updates and layout reflows |
| Commit a different number in a linked field | Uses the manually entered value | Clears the link and returns to None / default |
| Cancel a draft edit | Keeps the previous committed value | Keeps the previous relationship |
| Explicitly clear the token selection | Keeps the currently resolved number | None / unlinked |

Example: select **Space / Medium = 16** for a group's gap. Set the same token on
a padding side elsewhere. Changing Medium to **20** updates both linked uses.
Typing **18** into the gap field detaches only that gap; padding stays linked.
Changing Medium to **24** then changes the padding, while the gap remains **18**.
Typing the same resolved value without an actual change should not accidentally
break a link. Merely focusing a field, partial typing or cancelling must not
silently detach it.

Initial binding surfaces:

1. The fixed gap in automatic spacing / AutoLayout's packed distribution.
   Keep space-between's computed gap behavior distinct from a fixed token value.
2. Existing margin and padding values, preserving independent side values and
   whatever unified/per-side editing controls are offered.

## Requirements for the implementation slices

- Bind by stable token identity, not its display name. Rename preserves links;
  manual detachment affects only the edited property. Labels expose the name,
  resolved value and linked/unlinked state without relying on color alone.
- Preserve numeric field units, validation, keyboard entry and existing behavior
  when there are no tokens. Resolve only supported, well-defined numeric units;
  unsupported expressions/relative units remain honest and cannot be guessed.
- Token edits update linked layout everywhere it is supported, including nested
  groups, components and pages. Capture/apply/export must not silently flatten
  identity where the format supports it; otherwise report the limitation.
- Undo/Redo restores both the number and link. One token edit and its dependent
  reflow form one coherent undoable operation. Save/reopen must retain bindings
  in both JSON and package documents. Old documents remain visually unchanged.
- Before shipping, define token deletion/missing-token behavior so artwork keeps
  its last usable spacing and broken relationships are visible and recoverable.
- For color modes, decide document/artboard/application scope, aliases, fallback,
  editing/import precedence and export behavior before changing the model.
  Document color modes are distinct from the application's system appearance;
  continue respecting macOS appearance and accessibility settings.
- Verify numeric alternatives, keyboard/VoiceOver names and focus, larger text,
  light/dark UI and the existing import/paint/export regressions per slice.

## Sequence and verification

- [x] Close v2.8 after the owner's successful installed update; open 2.9/20.
- [x] Record the color-mode focus and spacing select/link/update/detach behavior.
- [ ] Review current token/model/inspector seams and settle the bounded mode UI,
  unit-resolution and missing-token decisions before implementation.
- [ ] Build one document-mutating slice, verify it, then await owner acceptance
  before starting the next. Do not start feature implementation from this setup
  task alone; the owner asked to add these items to the next-release to-do.
- [ ] Verify mode/spacing edits, reflow, detach, Undo/Redo, both save formats,
  legacy compatibility and accurate export behavior with focused fixtures.

Other token types and binding surfaces remain candidates. This brief records
the selected focus without promising a completed token system or code sync.
