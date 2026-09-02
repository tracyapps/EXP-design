#!/usr/bin/env bash
# BUG-058 source contract: every app-authored popover is elevated above EXP's
# intentionally floating panel trays. Native NSMenu surfaces already use the
# system pop-up-menu level.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

popover_count="$(rg -n '\.popover\(isPresented:' "$root/EXP [design]" | wc -l | tr -d ' ')"
[[ "$popover_count" -eq 4 ]]

for source in \
  "Color/ColorPopover.swift" \
  "Color/PaintEditor.swift" \
  "UI/FontFamilyPicker.swift" \
  "UI/SourceEditorWindow.swift"; do
  rg -q 'expTransientWindowLevel\(\)' "$root/EXP [design]/$source"
done

rg -q 'rootView: GradientStopEditor' "$root/EXP [design]/Canvas/CanvasView.swift"
rg -q 'expTransientWindowLevel\(\)' "$root/EXP [design]/Canvas/CanvasView.swift"
rg -q 'window\.level = \.floating' "$root/EXP [design]/UI/PanelWindow.swift"
rg -q 'window\.level = \.popUpMenu' "$root/EXP [design]/UI/GlassSurface.swift"
rg -q 'panel\.level = \.popUpMenu' "$root/EXP [design]/UI/GlassSurface.swift"

printf 'PASS  BUG-058: 4 SwiftUI popovers, the canvas gradient popover, and field tips use transient ordering above floating trays.\n'
