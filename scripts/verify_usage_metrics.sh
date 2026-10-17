#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for binary in initdb pg_ctl node xcrun; do
  command -v "$binary" >/dev/null || { echo "Required tool missing: $binary" >&2; exit 1; }
done
usage_test_dir=$(mktemp -d /tmp/exp-usage-test.XXXXXX)
cleanup() {
  pg_ctl -D "$usage_test_dir/data" -m fast stop >/dev/null 2>&1 || true
  rm -rf -- "$usage_test_dir"
}
trap cleanup EXIT
initdb -D "$usage_test_dir/data" --auth-local=trust --auth-host=scram-sha-256 > "$usage_test_dir/init.log"
pg_ctl -D "$usage_test_dir/data" -l "$usage_test_dir/server.log" \
  -o "-k $usage_test_dir -p 55489 -c listen_addresses=''" start >/dev/null
export EXP_USAGE_TEST_DATABASE_URL="postgresql:///postgres?host=$usage_test_dir&port=55489"
xcrun swiftc -parse-as-library 'EXP [design]/UI/UsageMetrics.swift' scripts/UsageMetricsCheck.swift -o "$usage_test_dir/usage-check"
node --test tests/usage.test.mjs
EXP_USAGE_CHECK_BINARY="$usage_test_dir/usage-check" node scripts/usage_http_check.mjs
