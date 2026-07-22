#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/verify_release_candidate.sh [--local] <app-path> <version> <build>

Verifies the signed app, bundled exp-mcp helper, architectures, version, and
security entitlements. Production mode also requires Gatekeeper acceptance and
a valid notarization staple. Use --local only for an Xcode-built/archive app
that has not been exported through Direct Distribution yet.
EOF
}

LOCAL_ONLY=false
if [[ "${1:-}" == "--local" ]]; then
  LOCAL_ONLY=true
  shift
fi

if [[ $# -ne 3 ]]; then
  usage >&2
  exit 64
fi

APP_PATH="$1"
EXPECTED_VERSION="$2"
EXPECTED_BUILD="$3"

if [[ ! -d "$APP_PATH" ]]; then
  echo "FAIL: app not found: $APP_PATH" >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "FAIL: missing Info.plist: $INFO_PLIST" >&2
  exit 1
fi

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

assert_equal() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label is '$actual'; expected '$expected'" >&2
    exit 1
  fi
  echo "PASS: $label = $expected"
}

assert_universal() {
  local label="$1"
  local executable="$2"
  local architectures
  architectures="$(lipo -archs "$executable")"
  if [[ " $architectures " != *" arm64 "* || " $architectures " != *" x86_64 "* ]]; then
    echo "FAIL: $label is not universal arm64 + x86_64 ($architectures)" >&2
    exit 1
  fi
  echo "PASS: $label architectures = $architectures"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

APP_EXECUTABLE_NAME="$(read_plist "$INFO_PLIST" CFBundleExecutable)"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_EXECUTABLE_NAME"
HELPER="$APP_PATH/Contents/Helpers/exp-mcp"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "FAIL: missing app executable: $APP_EXECUTABLE" >&2
  exit 1
fi
if [[ ! -x "$HELPER" ]]; then
  echo "FAIL: missing executable agent helper: $HELPER" >&2
  exit 1
fi

assert_equal "marketing version" "$(read_plist "$INFO_PLIST" CFBundleShortVersionString)" "$EXPECTED_VERSION"
assert_equal "build number" "$(read_plist "$INFO_PLIST" CFBundleVersion)" "$EXPECTED_BUILD"
assert_universal "app executable" "$APP_EXECUTABLE"
assert_universal "exp-mcp helper" "$HELPER"

APP_ENTITLEMENTS="$TMP_DIR/app-entitlements.plist"
HELPER_ENTITLEMENTS="$TMP_DIR/helper-entitlements.plist"
codesign -d --entitlements :- "$APP_PATH" > "$APP_ENTITLEMENTS" 2>/dev/null
codesign -d --entitlements :- "$HELPER" > "$HELPER_ENTITLEMENTS" 2>/dev/null || :

require_true_entitlement() {
  local key="$1"
  local value
  value="$(read_plist "$APP_ENTITLEMENTS" "$key" || true)"
  if [[ "$value" != "true" ]]; then
    echo "FAIL: app entitlement $key is not true" >&2
    exit 1
  fi
  echo "PASS: app entitlement $key"
}

require_true_entitlement "com.apple.security.app-sandbox"
require_true_entitlement "com.apple.security.files.user-selected.read-write"
require_true_entitlement "com.apple.security.network.client"
require_true_entitlement "com.apple.security.network.server"

for suffix in -spks -spki; do
  if ! plutil -convert json -o - "$APP_ENTITLEMENTS" 2>/dev/null | grep -- "$suffix" >/dev/null; then
    echo "FAIL: app is missing Sparkle $suffix Mach lookup exception" >&2
    exit 1
  fi
  echo "PASS: Sparkle $suffix Mach lookup exception"
done

for key in \
  com.apple.security.app-sandbox \
  com.apple.security.network.client \
  com.apple.security.network.server; do
  if [[ -s "$HELPER_ENTITLEMENTS" ]] && [[ "$(read_plist "$HELPER_ENTITLEMENTS" "$key" || true)" == "true" ]]; then
    echo "FAIL: exp-mcp unexpectedly carries $key" >&2
    exit 1
  fi
  echo "PASS: exp-mcp does not carry $key"
done

if xattr -lr "$APP_PATH" 2>/dev/null | grep 'com.apple.FinderInfo' >/dev/null; then
  echo "FAIL: app contains com.apple.FinderInfo; clear metadata before shipping" >&2
  exit 1
fi
echo "PASS: no com.apple.FinderInfo metadata"

codesign --verify --strict --verbose=2 "$HELPER"
echo "PASS: exp-mcp strict signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "PASS: app strict deep signature"

if [[ "$LOCAL_ONLY" == false ]]; then
  spctl -a -vvv -t install "$APP_PATH"
  echo "PASS: Gatekeeper assessment"
  xcrun stapler validate "$APP_PATH"
  echo "PASS: notarization staple"
else
  echo "INFO: --local selected; Gatekeeper and staple checks intentionally skipped"
fi

echo "Release-candidate verification passed for EXP [design] $EXPECTED_VERSION ($EXPECTED_BUILD)."
