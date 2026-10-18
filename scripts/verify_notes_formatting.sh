#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d /tmp/exp-notes-check.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc -parse-as-library "$root/EXP [design]/UI/NotesTextView.swift" \
  "$root/scripts/NotesFormattingCheck.swift" -o "$scratch/check"
"$scratch/check" "$@"
