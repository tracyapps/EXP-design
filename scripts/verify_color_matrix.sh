#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d /tmp/exp-color-matrix.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
app="$scratch/ColorMatrixCheck.app"
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
  "$root/scripts/ColorMatrixCheck.swift" -o "$app/Contents/MacOS/ColorMatrixCheck"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ColorMatrixCheck</string>
<key>CFBundleIdentifier</key><string>org.thisroad.exp.color-matrix-check</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
"$app/Contents/MacOS/ColorMatrixCheck" "$@"
