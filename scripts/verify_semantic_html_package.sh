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
  "$root/EXP [design]/Export/HandoffPackageWriter.swift" \
  "$root/scripts/SemanticHTMLGoldenFixtureCheck.swift" \
  "$root/scripts/SemanticHTMLPackageCheck.swift" \
  -o "$scratch/semantic-html-package-check"

"$scratch/semantic-html-package-check" "$scratch/Handoff Fixture.exph"

if [[ $# -eq 1 ]]; then
  "$scratch/semantic-html-package-check" "$1" "$scratch/Real Document.exph"
elif [[ $# -eq 2 ]]; then
  "$scratch/semantic-html-package-check" "$1" "$2"
elif [[ $# -ne 0 ]]; then
  echo "usage: $0 [DOCUMENT.design [OUTPUT.exph]]" >&2
  exit 2
fi
