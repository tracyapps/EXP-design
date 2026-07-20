#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/generate_sparkle_appcast.sh <marketing-version> <build-number> <path-to-notarized-zip>

Example:
  scripts/generate_sparkle_appcast.sh 1.3 5 ~/Desktop/EXP-design-v1.3.zip

Environment:
  SPARKLE_RELEASES_DIR       Local folder holding every Sparkle release zip.
                             Default: ../sparkle-releases next to this repo.
  SPARKLE_GENERATE_APPCAST   Optional explicit path to Sparkle's generate_appcast.
  GITHUB_REPOSITORY          owner/repo for release URLs. Default: tracyapps/EXP-design

This script copies the notarized zip into the local Sparkle releases folder,
creates the matching HTML release-note file from RELEASE-NOTES-vX.Y.md, runs
generate_appcast, and verifies the generated appcast shape.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 3 ]]; then
  usage
  exit 2
fi

version="$1"
build="$2"
zip_path="$3"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="${GITHUB_REPOSITORY:-tracyapps/EXP-design}"
releases_dir="${SPARKLE_RELEASES_DIR:-$(cd "$root/.." && pwd)/sparkle-releases}"
appcast="$root/website/public/appcast.xml"
notes_md="$root/RELEASE-NOTES-v$version.md"
zip_name="EXP-design-v$version.zip"
release_zip="$releases_dir/$zip_name"
notes_html="$releases_dir/EXP-design-v$version.html"
download_prefix="https://github.com/$repo/releases/download/v$version/"
release_notes_prefix="https://expdesign.app/"
local_appcast="$releases_dir/appcast.xml"
tmpdir=""

cleanup() {
  if [[ -n "$tmpdir" && -d "$tmpdir" ]]; then
    rm -rf "$tmpdir"
  fi
}
trap cleanup EXIT

find_generate_appcast() {
  if [[ -n "${SPARKLE_GENERATE_APPCAST:-}" && -x "${SPARKLE_GENERATE_APPCAST:-}" ]]; then
    printf '%s\n' "$SPARKLE_GENERATE_APPCAST"
    return 0
  fi
  find "$HOME/Library/Developer/Xcode/DerivedData" -type f -path '*/Sparkle/bin/generate_appcast' -perm -111 2>/dev/null | head -1
}

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

normalize_github_release_urls() {
  local feed="$1"

  REPO="$repo" perl -0pi -e '
    my $repo = $ENV{"REPO"};
    s{https://github\.com/\Q$repo\E/releases/download/v[^/]+/(EXP-design-v([0-9][0-9.]*[0-9])\.zip)}
     {"https://github.com/$repo/releases/download/v$2/$1"}ge;
  ' "$feed"
}

verify_zip_for_sparkle_install() {
  local archive="$1"
  local app
  local entitlements
  local mach_names

  tmpdir="$(mktemp -d)"
  ditto -x -k "$archive" "$tmpdir"
  app="$(find "$tmpdir" -maxdepth 1 -type d -name '*.app' | head -1)"

  if [[ -z "$app" ]]; then
    echo "error: zip does not contain a top-level .app bundle" >&2
    exit 1
  fi

  entitlements="$tmpdir/entitlements.plist"
  codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null
  if ! /usr/libexec/PlistBuddy -c "Print :com.apple.security.network.client" "$entitlements" 2>/dev/null \
    | grep -qx true; then
    echo "error: exported app is missing com.apple.security.network.client" >&2
    echo "       Sparkle runs inside the app sandbox and cannot fetch appcast.xml without it." >&2
    echo "       Re-export from Xcode after enabling Outgoing Connections, then re-zip." >&2
    exit 1
  fi

  if ! /usr/libexec/PlistBuddy -c "Print :SUEnableInstallerLauncherService" "$app/Contents/Info.plist" 2>/dev/null \
    | grep -qx true; then
    echo "error: exported app does not enable SUEnableInstallerLauncherService" >&2
    echo "       A sandboxed app can download an update but cannot launch Sparkle's installer without it." >&2
    exit 1
  fi

  mach_names="$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.temporary-exception.mach-lookup.global-name" "$entitlements" 2>/dev/null || true)"
  if ! printf '%s\n' "$mach_names" | grep -q -- '-spks$' \
    || ! printf '%s\n' "$mach_names" | grep -q -- '-spki$'; then
    echo "error: exported app is missing Sparkle's -spks/-spki Mach lookup exceptions" >&2
    echo "       Add the sandbox integration entitlements, then archive/export and re-zip." >&2
    exit 1
  fi

  if ! codesign --verify --deep --strict --verbose=2 "$app"; then
    echo "error: exported app failed strict deep code-signing verification after unzip" >&2
    echo "       Sparkle launches embedded XPC services during install; forbidden" >&2
    echo "       extended attributes such as com.apple.FinderInfo can break that launch." >&2
    echo "       Strip metadata from the exported app, re-verify, and re-zip:" >&2
    echo "         xattr -cr \"path/to/EXP [design].app\"" >&2
    echo "         codesign --verify --deep --strict --verbose=2 \"path/to/EXP [design].app\"" >&2
    echo "         ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \"path/to/EXP [design].app\" \"path/to/EXP-design-v$version.zip\"" >&2
    exit 1
  fi

  if ! spctl -a -vvv -t install "$app"; then
    echo "error: exported app was not accepted by Gatekeeper after unzip" >&2
    echo "       Re-export via Xcode Direct Distribution, confirm notarization/stapling," >&2
    echo "       then re-run this helper against the final zip." >&2
    exit 1
  fi
}

if [[ ! -f "$zip_path" ]]; then
  echo "error: zip not found: $zip_path" >&2
  exit 1
fi

if [[ "$(basename "$zip_path")" != "$zip_name" ]]; then
  echo "error: zip must be named $zip_name so GitHub, appcast, and notes agree" >&2
  exit 1
fi

if [[ ! -f "$notes_md" ]]; then
  echo "error: missing release notes: $notes_md" >&2
  exit 1
fi

SPARKLE_SKIP_APPCAST_SHAPE=1 "$root/scripts/verify_sparkle_setup.sh" "$version" "$build"
verify_zip_for_sparkle_install "$zip_path"

generate_appcast="$(find_generate_appcast || true)"
if [[ -z "$generate_appcast" ]]; then
  echo "error: could not find Sparkle generate_appcast. Set SPARKLE_GENERATE_APPCAST." >&2
  exit 1
fi

mkdir -p "$releases_dir"

if [[ -f "$release_zip" ]] && ! cmp -s "$zip_path" "$release_zip"; then
  echo "error: $release_zip already exists but is not byte-identical to $zip_path" >&2
  echo "       Refusing to replace it; Sparkle signatures depend on the exact archive." >&2
  exit 1
fi

cp -p "$zip_path" "$release_zip"

if [[ -f "$appcast" && ! -f "$local_appcast" ]]; then
  cp -p "$appcast" "$local_appcast"
fi

{
  printf '<!doctype html>\n<html><head><meta charset="utf-8"><title>EXP [design] v%s</title></head>\n' "$version"
  printf '<body><pre style="white-space: pre-wrap; font: -apple-system-body;">\n'
  html_escape < "$notes_md"
  printf '\n</pre></body></html>\n'
} > "$notes_html"

(
  cd "$releases_dir"
  "$generate_appcast" \
  --versions "$build" \
  --maximum-deltas 0 \
  --download-url-prefix "$download_prefix" \
  --release-notes-url-prefix "$release_notes_prefix" \
  "$releases_dir"
  normalize_github_release_urls "$local_appcast"
)

mkdir -p "$root/website/public"
cp -p "$local_appcast" "$appcast"
cp -p "$notes_html" "$root/website/public/EXP-design-v$version.html"

expected_url="https://github.com/$repo/releases/download/v$version/$zip_name"
expected_notes_url="https://expdesign.app/EXP-design-v$version.html"
if ! grep -q "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" "$appcast"; then
  echo "error: generated appcast does not contain shortVersionString $version" >&2
  exit 1
fi
if ! grep -q "<sparkle:version>$build</sparkle:version>" "$appcast"; then
  echo "error: generated appcast does not contain build $build" >&2
  exit 1
fi
if ! grep -q "url=\"$expected_url\"" "$appcast"; then
  echo "error: generated appcast does not contain expected URL: $expected_url" >&2
  exit 1
fi
if ! grep -q "$expected_notes_url" "$appcast"; then
  echo "error: generated appcast does not contain expected release notes URL: $expected_notes_url" >&2
  exit 1
fi
if ! grep -q 'sparkle:edSignature="' "$appcast"; then
  echo "error: generated appcast is missing sparkle:edSignature" >&2
  exit 1
fi
if grep -q '<sparkle:deltas>' "$appcast"; then
  echo "error: generated appcast contains delta updates, but this release flow uploads only the full zip" >&2
  exit 1
fi

echo "Generated Sparkle appcast for v$version ($build):"
echo "  $appcast"
echo "  $root/website/public/EXP-design-v$version.html"
echo
echo "Next:"
echo "  1. Upload the SAME zip to GitHub release v$version."
echo "  2. Deploy website/public/appcast.xml and the HTML notes."
echo "  3. Verify: curl -s https://expdesign.app/appcast.xml | grep 'v$version\\|edSignature'"
echo "  4. Install a previous network-enabled public build and run Check for Updates."
echo "     For v1.3, install manually once because v1.2.1 lacked the network entitlement."
