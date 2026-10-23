#!/usr/bin/env bash
# FEAT-082 — library tokens in the Design Language. Usage:
#   scripts/verify_library_token_sync.sh [live-library-folder]
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
  "$root/EXP [design]/Model/LibraryTokenSync.swift" \
  "$root/scripts/LibraryTokenSyncCheck.swift" \
  -o "$scratch/library-token-sync-check"

"$scratch/library-token-sync-check" "$root/spike/library-tokens/start-2" "$@"
