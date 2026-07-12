#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/verify_sparkle_setup.sh <marketing-version> <build-number>

Example:
  scripts/verify_sparkle_setup.sh 1.3 5

Checks the app-side Sparkle configuration, project version settings, release
notes, local Sparkle tools, and any checked-in appcast URL/signature shape.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

version="$1"
build="$2"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pbxproj="$root/EXP [design].xcodeproj/project.pbxproj"
info_plist="$root/Info.plist"
package_resolved="$root/EXP [design].xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
appcast="$root/website/public/appcast.xml"
notes="$root/RELEASE-NOTES-v$version.md"

failures=0

check() {
  local message="$1"
  shift
  if "$@"; then
    printf 'ok: %s\n' "$message"
  else
    printf 'FAIL: %s\n' "$message" >&2
    failures=$((failures + 1))
  fi
}

unique_setting() {
  local key="$1"
  local expected="$2"
  local values
  values="$(grep "$key =" "$pbxproj" | sed -E "s/.*$key = ([^;]+);/\\1/" | sort -u)"
  [[ "$values" == "$expected" ]]
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$info_plist" 2>/dev/null
}

find_generate_appcast() {
  if [[ -n "${SPARKLE_GENERATE_APPCAST:-}" && -x "${SPARKLE_GENERATE_APPCAST:-}" ]]; then
    printf '%s\n' "$SPARKLE_GENERATE_APPCAST"
    return 0
  fi
  find "$HOME/Library/Developer/Xcode/DerivedData" -type f -path '*/Sparkle/bin/generate_appcast' -perm -111 2>/dev/null | head -1
}

check "MARKETING_VERSION is $version in every build config" unique_setting MARKETING_VERSION "$version"
check "CURRENT_PROJECT_VERSION is $build in every build config" unique_setting CURRENT_PROJECT_VERSION "$build"
check "app target allows outgoing network connections for Sparkle" unique_setting ENABLE_OUTGOING_NETWORK_CONNECTIONS YES
check "Sparkle package is resolved" grep -q '"identity" : "sparkle"' "$package_resolved"
check "Info.plist SUFeedURL points to expdesign.app appcast" test "$(plist_value SUFeedURL)" = "https://expdesign.app/appcast.xml"
public_key="$(plist_value SUPublicEDKey || true)"
check "Info.plist SUPublicEDKey is present" test -n "$public_key"
check "release notes exist for v$version" test -f "$notes"
generate_appcast="$(find_generate_appcast || true)"
check "Sparkle generate_appcast tool is available" test -n "$generate_appcast"

if [[ -f "$appcast" ]]; then
  check "checked-in appcast does not use GitHub release-page URLs" bash -c "! grep -q '/releases/tag/' '$appcast'"
  check "checked-in appcast has no delta update entries" bash -c "! grep -q '<sparkle:deltas>' '$appcast'"
  check "older appcast entries do not point at the v$version GitHub tag" bash -c "! grep -q 'releases/download/v$version/EXP-design-v1\\.2\\.1\\.zip' '$appcast'"
  if grep -q "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" "$appcast"; then
    expected_url="https://github.com/tracyapps/EXP-design/releases/download/v$version/EXP-design-v$version.zip"
    check "appcast v$version enclosure uses downloadable GitHub asset URL" grep -q "url=\"$expected_url\"" "$appcast"
    check "appcast v$version includes an EdDSA signature" grep -q 'sparkle:edSignature="' "$appcast"
    check "appcast v$version release notes HTML is present" test -f "$root/website/public/EXP-design-v$version.html"
  else
    printf 'note: checked-in appcast does not yet contain v%s; generate it after the notarized zip exists.\n' "$version"
  fi
fi

if [[ "$failures" -ne 0 ]]; then
  echo "Sparkle setup check failed with $failures issue(s)." >&2
  exit 1
fi

echo "Sparkle setup checks passed for v$version ($build)."
