#!/usr/bin/env bash
# Design Language model, live bindings, Guide files and semantic handoff. Usage:
#   scripts/verify_design_tokens.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

xcrun swiftc \
  -swift-version 5 \
  "$root/EXP [design]/Model/Paint.swift" \
  "$root/EXP [design]/Model/Document.swift" \
  "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
  "$root/EXP [design]/Color/DesignLanguageCode.swift" \
  "$root/EXP [design]/Color/DLCodeSyntax.swift" \
  "$root/EXP [design]/Export/DesignLanguageFolderExport.swift" \
  "$root/EXP [design]/Color/DesignLanguageGuide.swift" \
  "$root/EXP [design]/Model/LibraryTokenSync.swift" \
  "$root/EXP [design]/Color/ContrastMath.swift" \
  "$root/EXP [design]/Color/ColorMath.swift" \
  "$root/EXP [design]/Color/DesignLanguageIO.swift" \
  "$root/EXP [design]/Color/EffectsRender.swift" \
  "$root/EXP [design]/Color/PaintRender.swift" \
  "$root/EXP [design]/Color/TurbulenceNoise.swift" \
  "$root/EXP [design]/UI/Typography.swift" \
  "$root/EXP [design]/Export/ExportRenderer.swift" \
  "$root/EXP [design]/Export/SemanticHTMLContract.swift" \
  "$root/EXP [design]/Export/SemanticHTMLExporter.swift" \
  "$root/scripts/DesignTokensCheck.swift" \
  -o "$scratch/design-tokens-check"

"$scratch/design-tokens-check" "$root/EXP [design]/Resources/DesignLanguageGuide.html" "$@"
