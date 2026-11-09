#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc -O \
  "$root/EXP [design]/Model/Paint.swift" \
  "$root/EXP [design]/Model/Document.swift" \
  "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
  "$root/EXP [design]/Model/NativeDocumentStorage.swift" \
  "$root/scripts/NativeDocumentStorageCheck.swift" -o "$scratch/storage-check"
"$scratch/storage-check" "$scratch/legacy-export.design"
# Independent compatibility consumer: the actual released model, not a copy of
# the current decoder with a different label. git show is read-only.
for file in Paint Document AutoLayoutEngine; do
  git -C "$root" show "v2.7:EXP [design]/Model/$file.swift" > "$scratch/$file.swift"
done
xcrun swiftc -O "$scratch/Paint.swift" "$scratch/Document.swift" \
  "$scratch/AutoLayoutEngine.swift" "$root/scripts/NativeLegacyCompatibilityCheck.swift" \
  -o "$scratch/legacy-check"
"$scratch/legacy-check" "$scratch/legacy-export.design"
