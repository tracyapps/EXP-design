#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d /tmp/exp-visual-color-probe.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc -parse-as-library "$root/scripts/VisualFeatureColorProbe.swift" -o "$scratch/probe"
"$scratch/probe" "$@"
