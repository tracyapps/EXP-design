#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for binary in initdb pg_ctl node; do
  command -v "$binary" >/dev/null || { echo "Required local tool missing: $binary" >&2; exit 1; }
done
team_test_dir=$(mktemp -d /tmp/exp-team-test.XXXXXX)
cleanup() {
  pg_ctl -D "$team_test_dir/data" -m fast stop >/dev/null 2>&1 || true
  rm -rf -- "$team_test_dir"
}
trap cleanup EXIT
initdb -D "$team_test_dir/data" --auth-local=trust --auth-host=scram-sha-256 > "$team_test_dir/init.log"
pg_ctl -D "$team_test_dir/data" -l "$team_test_dir/server.log" -o "-k $team_test_dir -p 55489 -c listen_addresses=''" start >/dev/null
export EXP_TEAM_TEST_DATABASE_URL="postgresql:///postgres?host=$team_test_dir&port=55489"
if [[ "${1:-}" == '--preview' ]]; then node website/scripts/preview-teams.mjs; else node --test tests/teams.test.mjs; fi
