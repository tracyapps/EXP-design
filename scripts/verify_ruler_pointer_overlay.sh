#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc "$root/EXP [design]/Canvas/RulerPointerOverlay.swift" \
  "$root/scripts/RulerPointerOverlayCheck.swift" -o "$scratch/check"
"$scratch/check"
