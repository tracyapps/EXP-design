#!/usr/bin/env bash
# FEAT-083 groundwork — Custom Elements Manifest reader. Usage:
#   scripts/verify_component_manifest.sh [custom-elements.json | library folder]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

xcrun swiftc -swift-version 5 \
  "$root/EXP [design]/Model/ComponentManifestReader.swift" \
  "$root/scripts/ComponentManifestCheck.swift" \
  -o "$scratch/component-manifest-check"

"$scratch/component-manifest-check" "$@"
