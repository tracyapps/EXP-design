#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

xcrun swiftc \
  "$root/scripts/MorphologySpreadCheck.swift" \
  -o "$scratch/morphology-spread-check"

"$scratch/morphology-spread-check"
