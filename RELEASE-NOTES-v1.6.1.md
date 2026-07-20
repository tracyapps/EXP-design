# EXP [design] v1.6.1

Build 9. This is a focused stabilization release after v1.6.

## Fixes

- Rich-text word, line, and character styling is preserved when you click
  directly out of an active text box while text is still selected. Font size,
  color, weight, and underline no longer depend on collapsing the selection
  before leaving the editor.
- Changing selection from outside the canvas now commits the active text editor
  without pulling selection back to the previous text layer.
- Sparkle's installer launcher is now correctly enabled for the sandboxed app,
  including the required installer communication entitlements. Earlier builds
  could discover and download an update but then failed with “An error occurred
  while launching the installer.”
- SVG and raster files use their filenames as default layer names. Multiple SVGs
  dragged or pasted together now all import in one named batch.
- SVG exports include readable, CSS-safe `layer-…` classes derived from EXP layer
  names, without introducing duplicate IDs.
- Rotation now follows the Adobe-style outside-corner interaction instead of a
  top-center notch; existing Shift snapping and Inspector rotation remain intact.
- Inspector dimensions now follow the painted outside edge of positioned strokes.
  Group measurements use live descendant bounds, and numeric SVG-path resizing
  scales the actual vector geometry instead of only changing its stored frame.

## Update Notes

- No document-schema changes from v1.6.
- Because v1.6 and earlier are missing the sandboxed installer-launcher
  configuration, install v1.6.1 manually once. Automatic updates should work
  normally from that corrected baseline onward.
- Before publishing, verify the rich-text fix in a real document and complete
  the normal archive, notarization, and Sparkle appcast proof. The first true
  automatic-update proof starts from an installed v1.6.1 baseline.
