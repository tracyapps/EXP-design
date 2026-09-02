#!/usr/bin/env bash
# FEAT-061 deterministic app-target receipt for the compact preview, Markdown
# block parser, and external-link allowlist. Pass a built Debug .app or let the
# script use Xcode's current Debug products directory.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-}"
if [[ -z "$app" ]]; then
  products="$(xcodebuild -project "$root/EXP [design].xcodeproj" \
    -scheme 'EXP [design]' -configuration Debug -showBuildSettings 2>/dev/null |
    awk -F ' = ' '/TARGET_BUILD_DIR/ { print $2; exit }')"
  app="$products/EXP [design].app"
fi

executable="$app/Contents/MacOS/EXP [design]"
[[ -x "$executable" ]]
EXP_SANAA_RESPONSE_PROBE=1 "$executable"

# The reader is a normal companion while inactive, joins the tray level only
# while key, and yields again on resign. Popovers remain at popUpMenu above it.
source_file="$root/EXP [design]/UI/SanaaResponseWindow.swift"
grep -q 'func windowDidBecomeKey' "$source_file"
grep -q 'window.level = .floating' "$source_file"
grep -q 'func windowDidResignKey' "$source_file"
grep -q 'window.level = .normal' "$source_file"
echo "RESULT  active Sanaa response readers rise above floating trays and yield when inactive"
