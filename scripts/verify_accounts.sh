#!/bin/bash
# Every invocation owns a disposable socket-only PostgreSQL cluster. No hosted DB.
set -euo pipefail
cd "$(dirname "$0")/.."
for binary in initdb pg_ctl node; do command -v "$binary" >/dev/null; done
account_test_dir=$(mktemp -d /tmp/exp-account-test.XXXXXX)
cleanup() {
  pg_ctl -D "$account_test_dir/data" -m fast stop >/dev/null 2>&1 || true
  rm -rf -- "$account_test_dir"
}
trap cleanup EXIT
initdb -D "$account_test_dir/data" --auth-local=trust --auth-host=scram-sha-256 > "$account_test_dir/init.log"
pg_ctl -D "$account_test_dir/data" -l "$account_test_dir/server.log" \
  -o "-k $account_test_dir -p 55489 -c listen_addresses=''" start >/dev/null
export EXP_ACCOUNT_TEST_DATABASE_URL="postgresql:///postgres?host=$account_test_dir&port=55489"
if [[ "${1:-}" == "--schema" ]]; then
  node scripts/account_schema.mjs
elif [[ "${1:-}" == "--preview" ]]; then
  node website/scripts/preview-accounts.mjs
else
  node --test tests/accounts.test.mjs
fi
