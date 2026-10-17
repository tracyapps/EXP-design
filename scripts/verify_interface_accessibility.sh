#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d /tmp/exp-interface-check.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc -parse-as-library "$root/EXP [design]/UI/InterfaceAccessibility.swift" \
  "$root/scripts/InterfaceAccessibilityCheck.swift" -o "$scratch/check"
"$scratch/check"
