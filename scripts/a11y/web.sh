#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${EXP_A11Y_OUTPUT:?Run via npm run test:a11y}"
a11y_pg_dir=$(mktemp -d /tmp/exp-a11y-pg.XXXXXX)
cleanup() { pg_ctl -D "$a11y_pg_dir/data" -m fast stop >/dev/null 2>&1 || true; rm -rf -- "$a11y_pg_dir"; }
trap cleanup EXIT
initdb -D "$a11y_pg_dir/data" --auth-local=trust --auth-host=scram-sha-256 > "$a11y_pg_dir/init.log"
pg_ctl -D "$a11y_pg_dir/data" -l "$a11y_pg_dir/server.log" -o "-k $a11y_pg_dir -p 55491 -c listen_addresses=''" start >/dev/null
export EXP_A11Y_DATABASE_URL="postgresql:///postgres?host=$a11y_pg_dir&port=55491"
node website/scripts/a11y/web.mjs
