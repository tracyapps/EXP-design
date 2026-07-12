# EXP [design] v1.3

This release is the first full Design Language + Sparkle-update release.

## Highlights

- Design Language type styles: capture, apply, rename, categorize, update, export, and import reusable text styles.
- Component categories: friendly accessibility-centered roles, filtering, source-editor controls, and instance counts.
- Design Language transfer sheet: import/export colors, gradients, and type styles in EXP JSON plus developer-friendly text formats.
- Geometry and pixel-measurement tools: stroke alignment, per-corner radii, rounded-rect path conversion fixes, round-to-pixel, and geometry audit diagnostics.
- Tester diagnostics: file-backed performance logging plus Save Diagnostic Report.
- Canvas performance fixes for heavy imported SVG/image documents, including pan/zoom snapshot cleanup, image snapshot clamping, faster point editing, and cheaper selection chrome.
- Canvas restore: reopening a document now restores the last local pan/zoom position for that file.

## Fixes

- Fixed intermittent light canvas background / ghosting during pan and zoom.
- Fixed large default handles when converting tiny imported SVG points to curves.
- When an anchor and curve handle overlap, point editing now favors the actual anchor.
- Improved responsiveness when moving SVG points and when selecting many imported elements.
- Reduced large stock-photo slowdown during pan/zoom snapshots.

## Update Notes

- Auto-update is powered by Sparkle. This build is intended to verify the full install-from-previous-build -> update -> relaunch path.
