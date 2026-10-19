#!/usr/bin/env bash
# Paint palettes float above EXP peers and hide when inactive; application-defined
# palettes dismiss on deactivation and editor handoff. Other transient surfaces
# retain their existing menu-level ordering contract (BUG-058).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

popover_count="$(rg -n '\.popover\(isPresented:' "$root/EXP [design]" | wc -l | tr -d ' ')"
[[ "$popover_count" -eq 3 ]]

for source in \
  "UI/FontFamilyPicker.swift" \
  "UI/SourceEditorWindow.swift"; do
  rg -q 'expTransientWindowLevel\(\)' "$root/EXP [design]/$source"
done

rg -Fq 'GradientStopEditor(color:' "$root/EXP [design]/Canvas/CanvasView.swift"
for source in "Color/ColorPopover.swift" "Color/PaintEditor.swift" "Canvas/CanvasView.swift"; do
  rg -q 'expPaintWindowLevel\(\)' "$root/EXP [design]/$source"
done
rg -Fq 'window?.hidesOnDeactivate = true' "$root/EXP [design]/UI/GlassSurface.swift"
rg -Fq 'window?.level = .floating' "$root/EXP [design]/UI/GlassSurface.swift"
rg -q 'PaintPopoverActivity.shared.dismiss\(\)' "$root/EXP [design]/UI/SettingsWindowPositioner.swift"
rg -q 'NSApplication.didResignActiveNotification' "$root/EXP [design]/Color/PaintEditor.swift"
rg -q 'PaintPopoverActivity.shared.dismiss\(\)' "$root/EXP [design]/UI/SourceEditorWindow.swift"
rg -q 'window\.level = \.normal' "$root/EXP [design]/UI/PanelWindow.swift"
rg -q 'window\.level = \.popUpMenu' "$root/EXP [design]/UI/GlassSurface.swift"
rg -q 'panel\.level = \.popUpMenu' "$root/EXP [design]/UI/GlassSurface.swift"

rg -q 'popup.behavior = .applicationDefined' "$root/EXP [design]/Color/PaintEditor.swift"
printf 'PASS  Paint palettes float above app peers, hide when inactive, dismiss on settings/editor handoff; other transient surfaces retain their ordering.\n'
