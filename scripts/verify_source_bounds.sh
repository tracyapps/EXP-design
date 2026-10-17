#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d /tmp/exp-source-bounds.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc \
  "$root/EXP [design]/Model/Paint.swift" \
  "$root/EXP [design]/Model/Document.swift" \
  "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
  "$root/EXP [design]/Model/SVGImporter.swift" \
  "$root/EXP [design]/Color/ColorMath.swift" \
  "$root/EXP [design]/Color/DesignLanguageIO.swift" \
  "$root/EXP [design]/Color/EffectsRender.swift" \
  "$root/EXP [design]/Color/PaintRender.swift" \
  "$root/EXP [design]/Color/TurbulenceNoise.swift" \
  "$root/EXP [design]/UI/Typography.swift" \
  "$root/EXP [design]/Export/ExportRenderer.swift" \
  "$root/EXP [design]/Model/SelectionTransform.swift" \
  "$root/scripts/SourceBoundsCheck.swift" \
  -o "$scratch/source-bounds-check"

"$scratch/source-bounds-check"
