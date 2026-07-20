#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/verify_installed_update_baseline.sh [path-to-installed-app]

Default:
  /Applications/EXP [design].app

Checks the already-installed app that will initiate Sparkle's update. Sparkle's
Installer.xpc launches from the CURRENT app, so a clean new zip is not enough if
the installed baseline app has forbidden extended attributes.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

app="${1:-/Applications/EXP [design].app}"

if [[ ! -d "$app" ]]; then
  echo "error: installed app not found: $app" >&2
  exit 1
fi

echo "Installed app: $app"
echo -n "Version: "
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist"
echo -n "Build: "
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist"

sparkle="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle" ]] && xattr -lr "$sparkle" 2>/dev/null | grep -q 'com.apple.FinderInfo'; then
  echo "error: installed Sparkle.framework has com.apple.FinderInfo metadata." >&2
  echo "       Sparkle may download an update but fail with:" >&2
  echo "       'An error occurred while launching the installer.'" >&2
  echo "       Reinstall from the clean release zip, or remove xattrs with permission:" >&2
  echo "         sudo xattr -cr \"$app\"" >&2
  exit 1
fi

echo "Checking strict code signature..."
codesign --verify --deep --strict --verbose=2 "$app"

echo "Checking Gatekeeper assessment..."
spctl -a -vvv -t install "$app"

echo "Installed update baseline is clean."
