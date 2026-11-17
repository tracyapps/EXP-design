#!/usr/bin/env bash
# FEAT-090a — Design Language tokens + bindings (model only). Usage:
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
  "$root/EXP [design]/Color/ColorMath.swift" \
  "$root/EXP [design]/Color/DesignLanguageIO.swift" \
  "$root/EXP [design]/Color/EffectsRender.swift" \
  "$root/EXP [design]/Color/PaintRender.swift" \
  "$root/EXP [design]/Color/TurbulenceNoise.swift" \
  "$root/EXP [design]/UI/Typography.swift" \
  "$root/EXP [design]/Export/ExportRenderer.swift" \
  "$root/scripts/DesignTokensCheck.swift" \
  -o "$scratch/design-tokens-check"

"$scratch/design-tokens-check"
