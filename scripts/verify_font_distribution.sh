#!/usr/bin/env bash
# Reject known downloadable Apple SF font payloads in new distribution trees.
# This filename guard is not a general font license audit; third-party faces
# still require a reviewed redistribution license and bundled notices.
set -euo pipefail
if [[ $# -eq 0 ]]; then
  echo "Usage: scripts/verify_font_distribution.sh <distribution-tree> [...]" >&2
  exit 64
fi
for tree in "$@"; do
  if [[ ! -d "$tree" ]]; then
    echo "FAIL: missing distribution tree: $tree" >&2
    exit 1
  fi
  payloads="$(find "$tree" -type f \( -iname 'SF-*.otf' -o -iname 'SF-*.ttf' -o -iname 'SF-*.woff' -o -iname 'SF-*.woff2' \) -print)"
  if [[ -n "$payloads" ]]; then
    echo "FAIL: downloadable Apple SF font payloads in $tree" >&2
    echo "$payloads" >&2
    exit 1
  fi
  echo "PASS: no known Apple SF font payloads in $tree"
done
