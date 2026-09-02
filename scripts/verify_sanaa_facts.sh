#!/usr/bin/env bash
# FEAT-055 deterministic facts gate. Pure model calculation; no app, socket,
# network, or document write path is involved.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

xcrun swiftc \
  "$root/EXP [design]/Model/Paint.swift" \
  "$root/EXP [design]/Model/Document.swift" \
  "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
  "$root/EXP [design]/Color/ColorMath.swift" \
  "$root/EXP [design]/Color/ContrastMath.swift" \
  "$root/EXP [design]/Export/SanaaFacts.swift" \
  "$root/scripts/SanaaFactsCheck.swift" \
  -o "$scratch/sanaa-facts-check"

"$scratch/sanaa-facts-check"
