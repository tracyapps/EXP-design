#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

xcrun swiftc \
  "$root/EXP [design]/Model/Paint.swift" \
  "$root/EXP [design]/Model/Document.swift" \
  "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
  "$root/EXP [design]/Color/ColorMath.swift" \
  "$root/EXP [design]/Color/DesignLanguageIO.swift" \
  "$root/EXP [design]/Export/SemanticHTMLContract.swift" \
  "$root/EXP [design]/Export/SemanticHTMLExporter.swift" \
  "$root/scripts/AnchoredRelationshipCheck.swift" \
  -o "$scratch/anchored-relationship-check"

"$scratch/anchored-relationship-check"
