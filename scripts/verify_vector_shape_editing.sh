#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc \
  "$root/EXP [design]/Model/Paint.swift" \
  "$root/EXP [design]/Model/Document.swift" \
  "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
  "$root/EXP [design]/Model/SelectionTransform.swift" \
  "$root/EXP [design]/Model/NodeTreeIndex.swift" \
  "$root/EXP [design]/Model/VectorPathGeometry.swift" \
  "$root/EXP [design]/Model/VectorShapeEditing.swift" \
  "$root/EXP [design]/Model/KnifeEditing.swift" \
  "$root/scripts/VectorShapeEditingCheck.swift" -o "$scratch/check"
"$scratch/check" "$@"
