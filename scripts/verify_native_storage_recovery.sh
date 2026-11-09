#!/usr/bin/env bash
# Fault injection is confined to a new 64 MB disposable image and temp files.
# Never point the probe at an owner document or fill the system volume.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d /tmp/exp-recovery.XXXXXX)"
mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then
    if ! hdiutil detach "$scratch/volume" -quiet; then
      echo "Cleanup: could not detach disposable volume at $scratch/volume" >&2
      return
    fi
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT
xcrun swiftc -O \
  "$root/EXP [design]/Model/Paint.swift" \
  "$root/EXP [design]/Model/Document.swift" \
  "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
  "$root/EXP [design]/Model/NativeDocumentStorage.swift" \
  "$root/scripts/NativeStorageRecoveryCheck.swift" -o "$scratch/recovery-check"
mkdir "$scratch/volume"
hdiutil create -size 64m -fs HFS+ -volname EXPRecovery -type UDIF "$scratch/disposable.dmg" -quiet
hdiutil attach "$scratch/disposable.dmg" -mountpoint "$scratch/volume" -nobrowse -quiet
mounted=1
"$scratch/recovery-check" "$scratch/volume"
