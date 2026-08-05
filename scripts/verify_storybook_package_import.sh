#!/usr/bin/env bash
set -euo pipefail

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
  "$root/EXP [design]/Model/StorybookPackageImporter.swift" \
  "$root/scripts/StorybookPackageImporterCheck.swift" \
  -o "$scratch/storybook-package-importer-check"

app="$scratch/StorybookPackageImporterCheck.app"
mkdir -p "$app/Contents/MacOS"
mv "$scratch/storybook-package-importer-check" "$app/Contents/MacOS/StorybookPackageImporterCheck"

plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string StorybookPackageImporterCheck' "$plist" >/dev/null
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string org.thisroad.exp.storybook-package-importer-check' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string StorybookPackageImporterCheck' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$plist"

cd "$root"
"$app/Contents/MacOS/StorybookPackageImporterCheck"
