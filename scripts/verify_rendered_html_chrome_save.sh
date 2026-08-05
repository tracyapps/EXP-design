#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/saved-page.html" >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

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
  "$root/scripts/RenderedHTMLChromeSaveCheck.swift" \
  -o "$scratch/rendered-html-chrome-save-check"

app="$scratch/RenderedHTMLChromeSaveCheck.app"
mkdir -p "$app/Contents/MacOS"
mv "$scratch/rendered-html-chrome-save-check" "$app/Contents/MacOS/RenderedHTMLChromeSaveCheck"

plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string RenderedHTMLChromeSaveCheck' "$plist" >/dev/null
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string org.thisroad.exp.rendered-html-chrome-save-check' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string RenderedHTMLChromeSaveCheck' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$plist"

"$app/Contents/MacOS/RenderedHTMLChromeSaveCheck" "$1"
