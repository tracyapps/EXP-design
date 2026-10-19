#!/usr/bin/env bash
# BUG-058 source contract: every app-authored popover is elevated above EXP's
# document-level panel trays (the floating snap indicator is separate). Native
# NSMenu surfaces already use the
# system pop-up-menu level.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

popover_count="$(rg -n '\.popover\(isPresented:' "$root/EXP [design]" | wc -l | tr -d ' ')"
[[ "$popover_count" -eq 3 ]]

for source in \
  "Color/ColorPopover.swift" \
  "Color/PaintEditor.swift" \
  "UI/FontFamilyPicker.swift" \
  "UI/SourceEditorWindow.swift"; do
  rg -q 'expTransientWindowLevel\(\)' "$root/EXP [design]/$source"
done

rg -Fq 'GradientStopEditor(color:' "$root/EXP [design]/Canvas/CanvasView.swift"
rg -q 'expTransientWindowLevel\(\)' "$root/EXP [design]/Canvas/CanvasView.swift"
rg -q 'window\.level = \.normal' "$root/EXP [design]/UI/PanelWindow.swift"
rg -q 'window\.level = \.popUpMenu' "$root/EXP [design]/UI/GlassSurface.swift"
rg -q 'panel\.level = \.popUpMenu' "$root/EXP [design]/UI/GlassSurface.swift"

rg -q 'popup.behavior = .applicationDefined' "$root/EXP [design]/Color/PaintEditor.swift"
printf 'PASS  BUG-058: 3 SwiftUI popovers, the persistent paint/canvas gradient editors, and field tips use transient ordering above document-level trays.\n'
