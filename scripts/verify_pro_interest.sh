#!/bin/bash
# Isolated local PostgreSQL integration check. No hosted credentials or mail.
set -euo pipefail
cd "$(dirname "$0")/.."
for binary in initdb pg_ctl node; do
  command -v "$binary" >/dev/null || { echo "Required local tool missing: $binary" >&2; exit 1; }
done
interest_test_dir=$(mktemp -d /tmp/exp-interest-test.XXXXXX)
cleanup() {
  pg_ctl -D "$interest_test_dir/data" -m fast stop >/dev/null 2>&1 || true
  rm -rf -- "$interest_test_dir"
}
trap cleanup EXIT
initdb -D "$interest_test_dir/data" --auth-local=trust --auth-host=scram-sha-256 > "$interest_test_dir/init.log"
pg_ctl -D "$interest_test_dir/data" -l "$interest_test_dir/server.log" \
  -o "-k $interest_test_dir -p 55487 -c listen_addresses=''" start >/dev/null
export EXP_INTEREST_TEST_DATABASE_URL="postgresql:///postgres?host=$interest_test_dir&port=55487"
node --test tests/interest.test.mjs
