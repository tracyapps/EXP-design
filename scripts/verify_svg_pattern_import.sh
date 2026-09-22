#!/usr/bin/env bash
# FEAT-062 / BUG-060 — pattern import, tile rasterisation, and the flat-render
# regression, checked against the owner's real background fixtures.
#
# Pass the fixture directory as $1; defaults to the folder the fixtures were
# triaged from. Skips (exit 0) when that folder isn't present, so the check is
# safe to run on a machine without it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixtures="${1:-$HOME/Dropbox/work/custom-work-tools/games/pencil-and-paper/designs/svg-backgrounds-export}"

if [ ! -d "$fixtures" ]; then
  echo "verify_svg_pattern_import: fixtures not found at $fixtures — skipping"
  exit 0
fi

scratch="$(mktemp -d)"
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
  "$root/scripts/SVGPatternImportCheck.swift" \
  -o "$scratch/svg-pattern-import-check"

# ${2:+"$2"} passes the dump directory ONLY when it is set and non-empty. The
# naive "${2:-}" always passed a third (empty-string) argument, which made the
# harness's `arguments.count > 2` dump check true with an empty path — and it
# wrote the rendered fixtures into the repo root on EVERY run. That is what
# kept "resurrecting" the scratch files (it was never Dropbox).
"$scratch/svg-pattern-import-check" "$fixtures" ${2:+"$2"}
