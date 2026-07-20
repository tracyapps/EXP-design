#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/verify_installed_update_baseline.sh [path-to-installed-app]

Default:
  Auto-discovers EXP [design].app under /Applications or ~/Applications.

Checks the already-installed app that will initiate Sparkle's update. Sparkle's
Installer.xpc launches from the CURRENT app, so a clean new zip is not enough if
the installed baseline app has forbidden extended attributes.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

discover_app() {
  local roots=("/Applications")
  if [[ -d "$HOME/Applications" ]]; then
    roots+=("$HOME/Applications")
  fi

  find "${roots[@]}" -maxdepth 4 -type d -name "EXP *.app" -print 2>/dev/null | while IFS= read -r candidate; do
    if [[ "$(basename "$candidate")" == "EXP [design].app" ]]; then
      printf '%s\n' "$candidate"
    fi
  done | sort
}

if [[ $# -gt 1 ]]; then
  usage
  exit 2
fi

if [[ $# -eq 1 ]]; then
  app="$1"
else
  discovered_apps=()
  while IFS= read -r discovered_app; do
    discovered_apps+=("$discovered_app")
  done < <(discover_app)
  if [[ "${#discovered_apps[@]}" -eq 0 ]]; then
    echo "error: installed app not found under /Applications or ~/Applications." >&2
    echo "       Pass the app path explicitly if it lives somewhere else:" >&2
    echo "         scripts/verify_installed_update_baseline.sh \"path/to/EXP [design].app\"" >&2
    exit 1
  elif [[ "${#discovered_apps[@]}" -gt 1 ]]; then
    echo "error: found multiple installed EXP [design] apps; pass the one to test explicitly:" >&2
    printf '       %s\n' "${discovered_apps[@]}" >&2
    exit 1
  fi
  app="${discovered_apps[0]}"
fi

if [[ ! -d "$app" ]]; then
  echo "error: installed app not found: $app" >&2
  exit 1
fi

echo "Installed app: $app"
echo -n "Version: "
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist"
echo -n "Build: "
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist"

if ! /usr/libexec/PlistBuddy -c 'Print :SUEnableInstallerLauncherService' "$app/Contents/Info.plist" 2>/dev/null \
  | grep -qx true; then
  echo "error: installed app does not enable SUEnableInstallerLauncherService." >&2
  echo "       This sandboxed baseline can discover/download updates but cannot launch the installer." >&2
  echo "       Install v1.6.1 or later manually once, then use that as the next update baseline." >&2
  exit 1
fi

installed_entitlements="$(mktemp)"
trap 'rm -f "$installed_entitlements"' EXIT
codesign -d --entitlements :- "$app" > "$installed_entitlements" 2>/dev/null
mach_names="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.mach-lookup.global-name' "$installed_entitlements" 2>/dev/null || true)"
if ! printf '%s\n' "$mach_names" | grep -q -- '-spks$' \
  || ! printf '%s\n' "$mach_names" | grep -q -- '-spki$'; then
  echo "error: installed app is missing Sparkle's -spks/-spki Mach lookup exceptions." >&2
  echo "       Install v1.6.1 or later manually once, then use that as the next update baseline." >&2
  exit 1
fi

finder_info_paths="$(xattr -lr "$app" 2>/dev/null | awk '/: com\.apple\.FinderInfo:/{ sub(/: com\.apple\.FinderInfo:.*/, ""); print }')"
if [[ -n "$finder_info_paths" ]]; then
  echo "error: installed app has com.apple.FinderInfo metadata:" >&2
  printf '%s\n' "$finder_info_paths" | sed 's/^/       /' >&2
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
