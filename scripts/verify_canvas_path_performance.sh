#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
# Exercise the actual private canvas method without compiling the entire UI.
# Extract by its stable neighboring declarations; fail rather than use stale code.
python3 - "$root" "$scratch/Check.swift" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
source = (root / 'EXP [design]/Canvas/CanvasView.swift').read_text()
start = source.index('    private func bezierPath(for ps: PathShape, frameOrigin: CGPoint) -> NSBezierPath {')
end = source.index('    /// The path\'s ink in NODE-LOCAL coordinates', start)
method = source[start:end].replace('private func bezierPath', 'func bezierPath', 1)
check = (root / 'scripts/CanvasPathPerformanceCheck.swift').read_text()
pathlib.Path(sys.argv[2]).write_text(check.replace('    // PRODUCTION_METHOD', method))
PY
# Debug matches the owner's Xcode build, where per-point observation was costly.
xcrun swiftc -Onone -parse-as-library \
  "$root/EXP [design]/Model/Paint.swift" \
  "$root/EXP [design]/Model/Document.swift" \
  "$root/EXP [design]/Model/AutoLayoutEngine.swift" \
  "$scratch/Check.swift" -o "$scratch/canvas-path-check"
"$scratch/canvas-path-check" "$@"
