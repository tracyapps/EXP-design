# EXP [design] v1.4

Build 6. This release tightens the v1.3 Design Language build with the
late-found performance fix, explicit layer reveal behavior, and the first
document-schema marker for future handoff work.

## Highlights

- **Major performance fix.** The multi-second lag on complex documents was traced
  to Layers-panel recomputation during SwiftUI layout and fixed. Selection,
  nudging, point editing, and panel refreshes should feel normal again.
- **Safer drag performance.** Drag-overlay blit is no longer disabled by unrelated
  visible gradients or shadows, which made anchor and handle drags feel
  hit-or-miss.
- **Reveal in Layers.** Selection changes no longer yank-scroll the Layers panel,
  but View -> Reveal Selection in Layers and the canvas context menu can scroll
  deliberately when you ask.
- **Pan/zoom sensitivity memo.** Pan/zoom now memoizes the all-clear
  bitmap-sensitivity case per document generation, avoiding repeated scene walks
  in flat/plain documents while preserving exact viewport checks when sensitive
  content exists.
- **Interop prep.** New `.design` saves include top-level `schemaVersion: 1`, so
  future v2 handoff readers can identify v1.x documents cleanly.
- **Release plumbing cleanup.** The release checklist now reflects the real
  Sparkle flow: notarized zip first, appcast from those exact bytes, then GitHub
  release and website deploy.

## Fixes

- Fixed multi-second beachballs triggered by selection, nudge, and point-edit
  workflows in documents with many artboards/layers.
- Fixed unnecessary full live drag rendering when non-dragged gradients/shadows
  were visible elsewhere on canvas.
- Restored deliberate layer reveal as an explicit command instead of automatic
  panel scrolling on every canvas selection change.
- Added `schemaVersion` with tolerant decode so old `.design` files still open
  and new files self-identify.

## Update Notes

- v1.4 is intended to be the first real Sparkle update proof from the
  network-enabled v1.3 baseline.
- After publishing, test from v1.3 with Check for Updates -> install -> relaunch,
  then confirm About EXP [design] shows 1.4 / build 6.
- Known carry-overs remain intentionally deferred: the rich-text click-out style
  bug, centered-title rename popover polish, nested transformed-group unified
  transform box, component instance navigation, and Components-panel grid view.
