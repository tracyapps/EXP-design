#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

mode=()
if [[ $# -eq 1 ]]; then
  archive="$1"
  mode=(--live-opacity)
else
  fixture="$root/spike/codepen-export/fixture-tree"
  archive="$scratch/codepen-fixture.zip"
  # CodePen downloads commonly contain one title/slug wrapper folder. Keep that
  # wrapper so root detection is exercised rather than only testing a flat ZIP.
  /usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$fixture" "$archive"
fi

xcrun swiftc \
  -swift-version 5 \
  -framework AppKit \
  -framework WebKit \
  "$root/EXP [design]/Model/Paint.swift" \
  "$root/EXP [design]/Model/Document.swift" \
  "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
  "$root/EXP [design]/Model/SelectionTransform.swift" \
  "$root/EXP [design]/Model/SVGImporter.swift" \
  "$root/EXP [design]/Model/InteropCodec.swift" \
  "$root/EXP [design]/Model/RenderedHTMLImporter.swift" \
  "$root/EXP [design]/Model/RenderedHTMLWebKitCapture.swift" \
  "$root/EXP [design]/Model/CodePenPackageImporter.swift" \
  "$root/scripts/CodePenPackageImporterCheck.swift" \
  -lz \
  -o "$scratch/codepen-package-importer-check"

app="$scratch/CodePenPackageImporterCheck.app"
mkdir -p "$app/Contents/MacOS"
mv "$scratch/codepen-package-importer-check" "$app/Contents/MacOS/CodePenPackageImporterCheck"

plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string CodePenPackageImporterCheck' "$plist" >/dev/null
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string org.thisroad.exp.codepen-package-importer-check' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string CodePenPackageImporterCheck' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$plist"

cd "$root"
if (( ${#mode[@]} )); then
  "$app/Contents/MacOS/CodePenPackageImporterCheck" "$archive" "${mode[@]}"
else
  "$app/Contents/MacOS/CodePenPackageImporterCheck" "$archive"
fi
