#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d /tmp/exp-mesh-fill.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
app="$scratch/MeshFillCheck.app"
mkdir -p "$app/Contents/MacOS"
xcrun swiftc -framework WebKit \
  "$root/EXP [design]/Model/Paint.swift" \
  "$root/EXP [design]/Model/Document.swift" \
  "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
  "$root/EXP [design]/Color/ColorMath.swift" \
  "$root/EXP [design]/Color/DesignLanguageIO.swift" \
  "$root/EXP [design]/Color/EffectsRender.swift" \
  "$root/EXP [design]/Color/PaintRender.swift" \
  "$root/EXP [design]/Color/TurbulenceNoise.swift" \
  "$root/EXP [design]/UI/Typography.swift" \
  "$root/EXP [design]/Model/SVGImporter.swift" \
  "$root/EXP [design]/Export/ExportRenderer.swift" \
  "$root/EXP [design]/Model/SelectionTransform.swift" \
  "$root/EXP [design]/Model/InteropCodec.swift" \
  "$root/EXP [design]/Model/RenderedHTMLImporter.swift" \
  "$root/scripts/MeshFillCheck.swift" -o "$app/Contents/MacOS/MeshFillCheck"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MeshFillCheck</string>
<key>CFBundleIdentifier</key><string>org.thisroad.exp.mesh-fill-check</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
"$app/Contents/MacOS/MeshFillCheck" "$@"
