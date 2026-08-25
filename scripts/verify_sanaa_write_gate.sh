#!/bin/bash
# verify_sanaa_write_gate.sh — FEAT-048 gate matrix for Sanaa's `apply_edits`.
#
# WHY THIS EXISTS: `apply_edits` is the first tool that can CHANGE the
# designer's document from outside the app. Its gates are the feature. A build
# that compiles proves nothing about them, and the matrix is too long to run by
# hand reliably (SANAA-PLAN.md §6/FEAT-048, test 2). Every case below must fail
# WHOLE, with its own accurate message, and leave the document untouched.
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
  call list_artboards '{}' | grep -o '"id"' | wc -l | tr -d ' '
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
  read -r _
}

# ---------------------------------------------------------------- phase 1
if phase_wanted 1; then
  pause_for 'Settings ▸ Sanaa: "Enable Sanaa" OFF.'
  echo "Phase 1 — Sanaa disabled"
  assert_refused "master switch off" "Sanaa is turned off in EXP" \
    '{"summary":"gate probe","ops":[{"op":"createArtboard","name":"Gate probe","frame":{"width":320,"height":200}}]}'
  reply="$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')"
  case "$reply" in
    *apply_edits*) bad "apply_edits is not advertised while Sanaa is off" "$reply" ;;
    *) ok "apply_edits is not advertised while Sanaa is off" ;;
  esac
fi

# ---------------------------------------------------------------- phase 2
if phase_wanted 2; then
  pause_for 'Settings ▸ Sanaa: "Enable Sanaa" ON, "Allow Sanaa to draw" OFF.'
  echo "Phase 2 — enabled but not allowed to draw"
  assert_refused "write switch off" "not allowed to draw" \
    '{"summary":"gate probe","ops":[{"op":"createArtboard","name":"Gate probe","frame":{"width":320,"height":200}}]}'
fi

# ---------------------------------------------------------------- phase 3
if phase_wanted 3; then
  pause_for 'Settings ▸ Sanaa: BOTH switches ON. Use a scratch document.'
  echo "Phase 3 — both switches on"

  before="$(artboard_count)"
  reply="$(call apply_edits '{"summary":"gate matrix artboard","ops":[{"op":"createArtboard","name":"Sanaa gate test","frame":{"width":320,"height":200},"placement":{"kind":"samePage"}}]}')"
  after="$(artboard_count)"
  case "$reply" in
    *'"isError"'*) bad "happy path — createArtboard was refused" "$reply" ;;
    *'"artboards"'*)
      if [ "$after" -eq $((before+1)) ]; then ok "happy path — one artboard created and its id returned"
      else bad "happy path — artboard count went $before -> $after" "$reply"; fi ;;
    *) bad "happy path — unexpected reply" "$reply" ;;
  esac
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

  echo
  echo "  Consent (needs your eyes, not this script):"
  echo "   - Ask a connected agent to replaceNode or removeNodes on this document."
  echo "     EXP must ask before anything changes. Choose \"Not Now\": the call is"
  echo "     refused, the document is unchanged, and re-asking waits a minute."
  echo "   - Then allow it, and confirm a second in-place batch does NOT ask again."
fi

echo
printf 'verify_sanaa_write_gate: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
