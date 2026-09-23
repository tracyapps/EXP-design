#!/bin/bash
# verify_sanaa_write_gate.sh — FEAT-048 gate matrix for Sanaa's `apply_edits`,
# extended for FEAT-058's bulk ops (restyleNodes, applyToken, normalizeSpacing,
# renameNodes).
#
# WHY THIS EXISTS: `apply_edits` is the first tool that can CHANGE the
# designer's document from outside the app. Its gates are the feature. A build
# that compiles proves nothing about them, and the matrix is too long to run by
# hand reliably (SANAA-PLAN.md §6/FEAT-048 test 2; §10/FEAT-058 testing). Every
# case below must fail WHOLE, with its own accurate message, and leave the
# document untouched.
#
# FEAT-058 scripted cases are refusals only: they fail during parse or the dry
# run, BEFORE any consent sheet, so the script stays unattended-safe. The
# consent-gated happy paths (bulk receipts, the preview the sheet shows, the
# source-restyle warning) need the designer's eyes and are listed at the end.
#
# This script talks to the same current-user Unix socket the bundled exp-mcp
# helper uses. It opens no network connection and needs no agent installed.
#
# Usage:
#   scripts/verify_sanaa_write_gate.sh            # all phases, prompts for switches
#   scripts/verify_sanaa_write_gate.sh --phase 3  # one phase, no prompts
#
# Requires, before you start:
#   - EXP [design] running with a document open (use a SCRATCH document).
#   - Handoff ▸ Agent ▸ "Allow local agent access" ON.
#   - `nc` (ships with macOS).
#
# Exit 0 = every assertion in the phases that were run passed.
set -uo pipefail

SOCK="$HOME/Library/Containers/tapps.EXP--design-/Data/Library/Application Support/EXP/agent.sock"
PHASE_ARG=""
[ "${1:-}" = "--phase" ] && PHASE_ARG="${2:-}"

# The all-phases path changes switches between phases and phase 3 intentionally
# creates one scratch artboard. Never interpret an absent stdin/EOF as the
# designer confirming those preconditions.
if [ -z "$PHASE_ARG" ] && [ ! -t 0 ]; then
  echo "verify_sanaa_write_gate: all phases require an interactive terminal" >&2
  echo "Run this script in Terminal with a scratch document, or pass --phase N after setting that phase's switches." >&2
  exit 2
fi

pass=0; fail=0
ok()   { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; printf '        got: %s\n' "${2:-<empty>}"; fail=$((fail+1)); }

[ -S "$SOCK" ] || {
  echo "verify_sanaa_write_gate: no socket at"
  echo "  $SOCK"
  echo "Start EXP [design] and turn on Handoff ▸ Agent ▸ Allow local agent access."
  exit 1
}

# One connection per call: initialize, then the request. Prints the raw reply.
rpc() {
  # The trailing sleep keeps stdin open long enough for EXP's reply to arrive;
  # without it `nc` can close the connection the instant printf finishes.
  { printf '%s\n%s\n' \
      '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"sanaa-gate-matrix","version":"0"}}}' \
      "$1"
    sleep 1
  } | nc -U "$SOCK" 2>/dev/null
}

call() { # call <tool> <arguments-json>
  rpc "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}"
}

artboard_count() {
  # Tool payloads are JSON text nested inside the JSON-RPC response, so their
  # quotes are escaped. Count only artboard ids in that nested payload; the old
  # plain-quote pattern counted the two envelope ids (1 and 2) on every call.
  call list_artboards '{}' | grep -o '\\"id\\"' | wc -l | tr -d ' '
}

# assert_refused <label> <expected substring> <arguments-json>
# Fails the run if the call succeeded, if the message is wrong, or if the
# artboard count moved — a refusal that still mutated is the worst outcome.
assert_refused() {
  local label="$1" expect="$2" args="$3" before after reply
  before="$(artboard_count)"
  reply="$(call apply_edits "$args")"
  after="$(artboard_count)"
  if [ "$before" != "$after" ]; then
    bad "$label — document CHANGED on a refused call ($before -> $after artboards)" "$reply"
    return
  fi
  case "$reply" in
    *'"isError":true'*|*'"isError": true'*) : ;;
    *) bad "$label — call was not refused" "$reply"; return ;;
  esac
  case "$reply" in
    *"$expect"*) ok "$label" ;;
    *) bad "$label — wrong message (wanted \"$expect\")" "$reply" ;;
  esac
}

phase_wanted() { [ -z "$PHASE_ARG" ] || [ "$PHASE_ARG" = "$1" ]; }

pause_for() {
  [ -n "$PHASE_ARG" ] && return 0
  printf '\n>> %s\n   Press Return when the switches are set. ' "$1"
  if ! read -r _; then
    printf '\nverify_sanaa_write_gate: confirmation input closed; aborting before the phase\n' >&2
    exit 2
  fi
}

# ---------------------------------------------------------------- phase 1
if phase_wanted 1; then
  pause_for 'Settings ▸ Sanaa: "Enable Sanaa" OFF; confirm the status says "Sanaa is off."'
  echo "Phase 1 — Sanaa disabled"
  assert_refused "master switch off" "Sanaa is turned off in EXP" \
    '{"summary":"gate probe","ops":[{"op":"createArtboard","name":"Gate probe","frame":{"width":320,"height":200}}]}'
  # FEAT-058: the bulk ops live behind the SAME switch, not a parallel gate.
  assert_refused "master switch off (bulk op)" "Sanaa is turned off in EXP" \
    '{"summary":"gate probe","ops":[{"op":"renameNodes","select":{"scope":"document"},"rule":{"prefix":"x"}}]}'
  reply="$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')"
  case "$reply" in
    *apply_edits*) bad "apply_edits is not advertised while Sanaa is off" "$reply" ;;
    *) ok "apply_edits is not advertised while Sanaa is off" ;;
  esac
fi

# ---------------------------------------------------------------- phase 2
if phase_wanted 2; then
  pause_for 'Settings ▸ Sanaa: enabled ON, drawing OFF; confirm the status says Sanaa can read but cannot change.'
  echo "Phase 2 — enabled but not allowed to draw"
  assert_refused "write switch off" "not allowed to draw" \
    '{"summary":"gate probe","ops":[{"op":"createArtboard","name":"Gate probe","frame":{"width":320,"height":200}}]}'
  assert_refused "write switch off (bulk op)" "not allowed to draw" \
    '{"summary":"gate probe","ops":[{"op":"restyleNodes","select":{"scope":"document","types":["rectangle"]},"set":{"opacity":0.5}}]}'
fi

# ---------------------------------------------------------------- phase 3
if phase_wanted 3; then
  pause_for 'Settings ▸ Sanaa: BOTH switches ON; confirm the status says Sanaa can add new work. Use a scratch document.'
  echo "Phase 3 — both switches on"

  before="$(artboard_count)"
  reply="$(call apply_edits '{"summary":"gate matrix artboard","ops":[{"op":"createArtboard","name":"Sanaa gate test","frame":{"width":320,"height":200},"placement":{"kind":"samePage"}}]}')"
  after="$(artboard_count)"
  if printf '%s\n' "$reply" | grep -q '"isError"'; then
    bad "happy path — createArtboard was refused" "$reply"
  elif ! printf '%s\n' "$reply" | grep -q '\\"artboards\\"'; then
    bad "happy path — response did not return created artboards" "$reply"
  elif [ "$after" -eq $((before+1)) ]; then
    ok "happy path — one artboard created and its id returned"
  else
    bad "happy path — artboard count went $before -> $after" "$reply"
  fi
  echo "     (now press Command-Z in EXP: the step must read \"Undo Sanaa: gate matrix artboard\")"

  assert_refused "missing summary" "requires a short" \
    '{"ops":[{"op":"createArtboard","name":"x","frame":{"width":10,"height":10}}]}'

  assert_refused "unknown argument" "does not accept" \
    '{"summary":"x","ops":[{"op":"createArtboard","name":"x","frame":{"width":10,"height":10}}],"force":true}'

  assert_refused "unknown operation" "is not an apply_edits operation" \
    '{"summary":"x","ops":[{"op":"deleteEverything"}]}'

  assert_refused "bogus node fragment" "not a valid EXP node" \
    '{"summary":"x","ops":[{"op":"insertNodes","artboardId":"00000000-0000-0000-0000-000000000000","nodes":[{"nope":1}]}]}'

  assert_refused "unknown artboard" "no artboard exists" \
    '{"summary":"x","ops":[{"op":"duplicateArtboard","id":"00000000-0000-0000-0000-000000000000"}]}'

  assert_refused "unknown node" "no node exists" \
    '{"summary":"x","ops":[{"op":"removeNodes","ids":["00000000-0000-0000-0000-000000000000"]}]}'

  # 201 operations — one past the cap. Built here so the cap is tested, not trusted.
  ops="$(awk 'BEGIN{ for(i=0;i<201;i++){ printf "%s{\"op\":\"createArtboard\",\"name\":\"cap\",\"frame\":{\"width\":10,\"height\":10}}", (i?",":"") } }')"
  assert_refused "operation cap" "at most 200 operations" \
    "{\"summary\":\"cap probe\",\"ops\":[$ops]}"

  # ------------------------- FEAT-058 — bulk op refusals (parse + dry run;
  # all fail BEFORE any consent sheet, so nothing here needs a click).
  assert_refused "bulk: unknown op key" "does not accept" \
    '{"summary":"x","ops":[{"op":"restyleNodes","select":{"scope":"document"},"set":{"stoke":2}}]}'

  assert_refused "bulk: no supported property" "named no supported property" \
    '{"summary":"x","ops":[{"op":"restyleNodes","select":{"scope":"document"},"set":{}}]}'

  assert_refused "bulk: bogus scope word" 'must be \"selection\", \"artboard\", \"page\", or \"document\"' \
    '{"summary":"x","ops":[{"op":"renameNodes","select":{"scope":"everywhere"},"rule":{"prefix":"x"}}]}'

  assert_refused "bulk: bogus layer type" "is not a layer type" \
    '{"summary":"x","ops":[{"op":"restyleNodes","select":{"scope":"document","types":["shapes"]},"set":{"opacity":1}}]}'

  assert_refused "bulk: normalize on selection scope" "nothing to space" \
    '{"summary":"x","ops":[{"op":"normalizeSpacing","select":{"scope":"selection"},"unit":8}]}'

  assert_refused "bulk: normalize without unit" "needs a positive" \
    '{"summary":"x","ops":[{"op":"normalizeSpacing","select":{"scope":"document"}}]}'

  assert_refused "bulk: rename with empty find" "must not be empty" \
    '{"summary":"x","ops":[{"op":"renameNodes","select":{"scope":"document"},"rule":{"find":"","replace":"y"}}]}'

  assert_refused "bulk: rename rule ambiguity" "exactly ONE kind of rule" \
    '{"summary":"x","ops":[{"op":"renameNodes","select":{"scope":"document"},"rule":{"prefix":"a ","suffix":" b"}}]}'

  assert_refused "bulk: unknown token" "no Design Language entry" \
    '{"summary":"x","ops":[{"op":"applyToken","token":"Definitely Not A Token","select":{"scope":"document"}}]}'

  assert_refused "bulk: restyle on unknown artboard" "no artboard exists" \
    '{"summary":"x","ops":[{"op":"restyleNodes","select":{"scope":"artboard","artboardId":"00000000-0000-0000-0000-000000000000"},"set":{"opacity":1}}]}'

  # A real, EMPTY artboard: the predicate must match nothing and say so —
  # a bulk op must never apply zero changes quietly and report success.
  # Id capture is two-layered: grep the apply reply first, and if that comes
  # back empty (one owner run lost this call's reply entirely to a socket
  # timing miss while the calls either side were fine), diff list_artboards
  # before/after instead. If both fail, print the raw reply so the next run
  # is diagnosable instead of a bare "<empty>".
  uuid_re='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
  bulk_before="$(call list_artboards '{}' | grep -oE "$uuid_re" | sort)"
  bulk_reply="$(call apply_edits '{"summary":"bulk gate board","ops":[{"op":"createArtboard","name":"Bulk gate","frame":{"width":240,"height":160}}]}')"
  bulk_after="$(call list_artboards '{}' | grep -oE "$uuid_re" | sort)"
  bulk_board="$(printf '%s\n' "$bulk_reply" | grep -oE "$uuid_re" | head -1)"
  if [ -z "$bulk_board" ]; then
    bulk_board="$(comm -13 <(printf '%s\n' "$bulk_before") <(printf '%s\n' "$bulk_after") | head -1)"
  fi
  if [ -z "$bulk_board" ]; then
    bad "bulk gate artboard — no id returned" "$bulk_reply"
  else
    ok "bulk gate artboard — created for predicate checks"
    assert_refused "bulk: predicate matches nothing" "matched no layers" \
      "{\"summary\":\"x\",\"ops\":[{\"op\":\"restyleNodes\",\"select\":{\"scope\":\"artboard\",\"artboardId\":\"$bulk_board\",\"types\":[\"path\"]},\"set\":{\"opacity\":0.5}}]}"
  fi

  echo
  echo "  Consent (needs your eyes, not this script):"
  echo "   - Ask a connected agent to replaceNode or removeNodes on this document."
  echo "     EXP must ask before anything changes. Choose \"Not Now\": the call is"
  echo "     refused, the document is unchanged, and re-asking waits a minute."
  echo "   - Then allow it, and confirm a second in-place batch does NOT ask again."
  echo
  echo "  FEAT-058 bulk consent (also your eyes):"
  echo "   - Draw two rectangles on the Bulk gate board, then ask the agent to"
  echo "     restyleNodes scoped to that artboard. The consent sheet must list"
  echo "     WHAT the batch will do (count first, e.g. \"Restyle 2 layers — One"
  echo "     artboard (…)\") BEFORE you choose. Allow it: the reply carries an"
  echo "     \"operations\" receipt (matched/changed/skipped), Command-Z reads one"
  echo "     \"Sanaa: …\" step, and both rectangles restyled together."
  echo "   - Scope restyleNodes at \"document\" with a name filter that hits a"
  echo "     component source: the sheet must warn that every placement of that"
  echo "     component changes, in plain words."
  echo "   - applyToken: the receipt must say values were SET, not linked."
fi

echo
printf 'verify_sanaa_write_gate: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
