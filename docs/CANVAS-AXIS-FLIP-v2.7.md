# Canvas-axis Flip — October 19, 2026

Development 2.7/build 18 · BUG-078 · local fix, owner-verified October 19.

## Report and correction

Owner clarifies the failing shape was a rotated three-sided triangle, used for
bowtie halves. The previous command toggled a local flip flag and left rotation
unchanged: it reflected before rotation. A triangle is horizontally symmetric in
its original orientation, so Horizontal appeared to do nothing after rotation;
Vertical acted along the rotated local direction rather than the canvas direction.
Earlier native tests with a vertical flip and an asymmetric path were valid, but
did not exercise the horizontal rotated-triangle expectation.

Inspector and Canvas/menu/context commands now share `SelectionTransform.flipped`.
It preserves each layer's frame centre and editable content, toggles the appropriate
local flag and updates rotation so the resulting reflection follows canvas axes.
For a top-level layer, rotation becomes minus its old angle (normalized to 0–359).
Ancestor rotations/reflections are conjugated through the parent orientation, so
nested shapes follow the same canvas directions. This is still each selected
layer about its own centre, not a multi-selection rearrangement.

Stored flags and rendering semantics are unchanged: existing documents retain
their appearance. Only invoking Flip uses the new command geometry. Rounded
polygons stay parametric; converted paths retain their points and control handles.
No new command, shortcut, accessibility name, ARIA mapping or document field.

## Evidence

- Focused geometry check fails with the previous flag-only operation, including a
  leaf inside a rotated/reflected group. Corrected operation passes independent
  reflected-path membership checks for 0/23/90/270 degrees, all prior flip flag
  combinations, both axes, root/nested nodes, rounded polygons and converted paths.
  Frame/identity/content preservation and two-flips restoration pass. Prior Knife,
  Unite and path-editing cases also pass: `/tmp/exp-flip-geometry-20261019.log`.
- Native PNG before/after is compared with an independent pixel reflection, using
  a rounded triangle with a gradient at 23 and 90 degrees, both axes, polygon and
  converted path. Real WebKit SVG and native codec are included:
  `/tmp/exp-flip-render-20261019.log`. The initial SVG comparison incorrectly kept
  a white artboard background in PNG while SVG omitted it; matching transparency
  repaired that test rather than changing production export behavior.
- App and shared thumbnail build: `/tmp/exp-flip-build-20261019.log`.
- Isolated sandboxed native app: 90-degree polygon points right → Horizontal Flip
  points left, rotation 90→270. One Undo restores 90 and right; Redo restores left.
  A second 90-degree triangle converted to a path also flips left. Saved generated
  JSON independently confirms polygon/path types, rotation 270 and flipH=true for
  both. Screenshots in ignored `output/a11y/visual-features-20261019/`:
  `bowtie-before.png`, `bowtie-after.png`.

Only generated artwork and an agent-owned sandboxed app were changed. Owner app,
documents and preferences remain separate. No push, deployment or release action.
Full component-state/library, auto-layout, multi-selection/ancestor simultaneous
selection, AT and real-document export combinations remain release checks.

## Owner check

Rebuild in Xcode; duplicate your rotated bowtie triangle and flip it horizontally.
Then try Vertical, Undo/Redo and save/reopen. Repeat after Convert to Path and
compare your exports. The displayed rotation may change: that is necessary to
keep local storage transforms while reflecting along the canvas directions.

## Owner acceptance — October 19 follow-up

Owner confirms “the pattern anchoring and flip are also verified now as well.”
The functional owner review is closed. Earlier pending-review notes are historical;
full accessibility/export/source-library combinations remain release gates.
