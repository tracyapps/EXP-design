#!/bin/bash
# verify_backlog_ids.sh — guard against duplicate / reused backlog ids.
#
# WHY THIS EXISTS: ids are referenced from docs/ROADMAP.md's Progress Log,
# docs/PERF-LOG.md and docs/PERF-TODO.md as well as from docs/BACKLOG.md itself,
# so an id can be TAKEN without ever appearing as a `### ` heading in BACKLOG.
# Picking "the next number after the highest heading" is therefore not safe.
# A PERF-005 collision survived unnoticed across four files from 2026-07-09 to
# 2026-08-11 for exactly that reason.
#
# Usage:  scripts/verify_backlog_ids.sh
# Exit 0 = no duplicate headings. Exit 1 = collision found.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

DOCS=docs
BACKLOG="$DOCS/BACKLOG.md"
[ -f "$BACKLOG" ] || { echo "verify_backlog_ids: $BACKLOG not found"; exit 1; }

status=0

echo "== duplicate headings in BACKLOG.md =="
dupes=$(grep -Eo '^### (BUG|FEAT|PERF|INFRA)-[0-9]{3}' "$BACKLOG" \
        | sed 's/^### //' | sort | uniq -d)
if [ -n "$dupes" ]; then
  echo "COLLISION — these ids have more than one entry:"
  echo "$dupes" | sed 's/^/  /'
  for d in $dupes; do
    echo "  occurrences of $d:"
    grep -rn "$d" "$DOCS" --include='*.md' | sed 's/^/    /'
  done
  status=1
else
  echo "  none"
fi

echo
echo "== next free id per prefix (across ALL of $DOCS, not just headings) =="
for pfx in BUG FEAT PERF INFRA; do
  hi=$(grep -rhoE "\b$pfx-[0-9]{3}\b" "$DOCS" --include='*.md' \
       | grep -oE '[0-9]{3}' | sort -n | tail -1)
  if [ -z "$hi" ]; then
    printf '  %-6s next: %s-001\n' "$pfx" "$pfx"
  else
    printf '  %-6s highest used: %s-%s   next: %s-%03d\n' \
      "$pfx" "$pfx" "$hi" "$pfx" $((10#$hi + 1))
  fi
done

echo
if [ "$status" -eq 0 ]; then echo "verify_backlog_ids: OK"; else echo "verify_backlog_ids: FAILED"; fi
exit "$status"
