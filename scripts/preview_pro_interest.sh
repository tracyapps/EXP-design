#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for binary in initdb pg_ctl node; do
  command -v "$binary" >/dev/null || { echo "Required local tool missing: $binary" >&2; exit 1; }
done
interest_preview_dir=$(mktemp -d /tmp/exp-interest-test.XXXXXX)
cleanup() {
  pg_ctl -D "$interest_preview_dir/data" -m fast stop >/dev/null 2>&1 || true
  rm -rf -- "$interest_preview_dir"
}
trap cleanup EXIT
initdb -D "$interest_preview_dir/data" --auth-local=trust --auth-host=scram-sha-256 > "$interest_preview_dir/init.log"
pg_ctl -D "$interest_preview_dir/data" -l "$interest_preview_dir/server.log" \
  -o "-k $interest_preview_dir -p 55488 -c listen_addresses=''" start >/dev/null
export EXP_INTEREST_TEST_DATABASE_URL="postgresql:///postgres?host=$interest_preview_dir&port=55488"
node website/scripts/preview-interest.mjs
