#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/set_release_version.sh <marketing-version> <build-number>

Example:
  scripts/set_release_version.sh 1.3 5

Updates MARKETING_VERSION and CURRENT_PROJECT_VERSION across all Xcode build
configs, then verifies the project has exactly one value for each setting.
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

if [[ ! "$version" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]; then
  echo "error: marketing version should look like 1.3 or 1.2.1, got '$version'" >&2
  exit 2
fi

if [[ ! "$build" =~ ^[0-9]+$ ]]; then
  echo "error: build number must be an integer, got '$build'" >&2
  exit 2
fi

perl -0pi -e "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $build;/g; s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/g" "$pbxproj"

marketing_values="$(grep 'MARKETING_VERSION =' "$pbxproj" | sed -E 's/.*MARKETING_VERSION = ([^;]+);/MARKETING_VERSION = \1;/' | sort -u)"
build_values="$(grep 'CURRENT_PROJECT_VERSION =' "$pbxproj" | sed -E 's/.*CURRENT_PROJECT_VERSION = ([^;]+);/CURRENT_PROJECT_VERSION = \1;/' | sort -u)"

expected_marketing="MARKETING_VERSION = $version;"
expected_build="CURRENT_PROJECT_VERSION = $build;"

if [[ "$marketing_values" != "$expected_marketing" ]]; then
  echo "error: MARKETING_VERSION verification failed:" >&2
  echo "$marketing_values" >&2
  exit 1
fi

if [[ "$build_values" != "$expected_build" ]]; then
  echo "error: CURRENT_PROJECT_VERSION verification failed:" >&2
  echo "$build_values" >&2
  exit 1
fi

echo "Updated project version: $version ($build)"
