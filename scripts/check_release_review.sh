#!/usr/bin/env bash
# Local checks only. No publication, migration of owner files or deployment.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_root="${1:-$root/output/release-review-checks}"
mkdir -p "$report_root"
reports="$(mktemp -d "$report_root/run-XXXXXX")"
failed=0
run_step() {
  local name="$1"
  shift
  printf 'Running %s…\n' "$name"
  if "$@" > "$reports/$name.log" 2>&1; then
    printf 'PASS %s\n' "$name" | tee -a "$reports/summary.txt"
  else
    printf 'FAIL %s (see %s)\n' "$name" "$reports/$name.log" | tee -a "$reports/summary.txt"
    failed=$((failed + 1))
  fi
}
cd "$root"
for check in rendered_html_shadows rendered_html_importer rendered_html_webkit native_document_storage library_token_sync component_manifest semantic_html_package effect_export_coverage mesh_fill svg_token_bridge source_bounds; do
  run_step "$check" bash "$root/scripts/verify_$check.sh"
done
run_step app_and_thumbnail_build xcodebuild -project "$root/EXP [design].xcodeproj" \
  -scheme 'EXP [design]' -configuration Debug -destination 'platform=macOS,arch=arm64' -quiet build
run_step diff_whitespace git diff --check
run_step backlog_ids bash "$root/scripts/verify_backlog_ids.sh"
printf 'Reports: %s\n' "$reports"
printf '%s failed checks. Hands-on owner checks remain separate.\n' "$failed"
if [[ "$failed" -gt 0 ]]; then exit 1; fi
