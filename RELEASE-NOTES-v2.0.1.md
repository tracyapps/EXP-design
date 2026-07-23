# EXP [design] v2.0.1

Build 11. A focused stabilization release after v2.0 that closes two defects
surfaced while recording the Help walkthroughs.

## Fixes

- Component states no longer leak edits into the shared source. Changing a text
  layer's typography (color, typeface/face, size, alignment, line-height,
  tracking, or case) or a selected layer/group's opacity while a non-default
  state (for example Disabled) is active now affects only that state. Default
  and sibling states stay unchanged, and instances render the chosen state
  correctly. Common designs such as a muted Disabled label are safe to author
  again. (BUG-006)
- Holding Shift while pulling the Bézier handles of a brand-new Pen anchor now
  constrains the handle to the same axis/45-degree increments used when editing
  an existing handle. Pressing or releasing Shift mid-drag toggles the snap, and
  the opposite handle stays mirrored. (BUG-005)

## Refinements

- The Type inspector's Font and Weight dropdowns now carry labels, and the
  semantic Content role moved into its own divider-separated sub-section below
  Case, so it is no longer mistaken for the typeface menu.

## Update Notes

- No document-schema changes from v2.0. Documents authored with leaked state
  edits open unchanged; new state-local typography and opacity are stored
  additively and decode tolerantly in existing schema-v2 files.
- Semantic HTML/CSS handoff now preserves per-state typography and opacity
  differences.
- Both fixes were reproduced from the 2026-07-23 Help recording and verified in
  real use before release.
