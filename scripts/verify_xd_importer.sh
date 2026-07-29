#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

if [[ $# -eq 0 ]]; then
  set -- "/Users/tapps/Desktop/test2/2.0 testing/XD-FILES"
fi

xcrun swiftc \
  "$root/EXP [design]/Model/Paint.swift" \
  "$root/EXP [design]/Model/Document.swift" \
  "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
  "$root/EXP [design]/Model/SVGImporter.swift" \
  "$root/EXP [design]/Model/InteropCodec.swift" \
  "$root/EXP [design]/Model/XDImporter.swift" \
  "$root/scripts/XDImporterCorpusCheck.swift" \
  -lz \
  -o "$scratch/xd-importer-check"

"$scratch/xd-importer-check" "$@"
