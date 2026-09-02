#!/bin/zsh
# FEAT-054 deterministic resource gate. Talks to the running EXP Unix socket,
# never to the network, and performs no document writes.
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SOCKET_PATH="$HOME/Library/Containers/tapps.EXP--design-/Data/Library/Application Support/EXP/agent.sock"
SOURCE_DIR="$PROJECT_ROOT/EXP [design]/Resources/SanaaKnowledge"
KNOWLEDGE_COUNT=24
PACK_FILE_COUNT=$((KNOWLEDGE_COUNT + 1)) # served modules + unserved changelog
EXPECTED_PACK_BYTES=104855
EXPECTED_INDEX_BYTES=3743

registry_entries="$({
  rg '^\s+\("exp://sanaa/knowledge/' "$PROJECT_ROOT/EXP [design]/Export/AgentBridge.swift" |
    sed -E 's/.*\("([^"]+)", "([^"]+)".*/\1\t\2/'
})"
registered_count="$(printf '%s\n' "$registry_entries" | sed '/^$/d' | wc -l | tr -d ' ')"
[[ "$registered_count" -eq "$KNOWLEDGE_COUNT" ]]

while IFS=$'\t' read -r uri file; do
  [[ -n "$uri" && -f "$SOURCE_DIR/$file.md" ]]
done <<< "$registry_entries"

# FEAT-053's separate `sanaa-guide.md` shares the synchronized resource folder
# but is not one of this versioned design-knowledge pack's modules.
source_files=("$SOURCE_DIR"/sanaa-knowledge-*.md(N))
[[ "${#source_files[@]}" -eq "$PACK_FILE_COUNT" ]]
pack_bytes="$(wc -c "${source_files[@]}" | tail -n 1 | awk '{print $1}')"
index_bytes="$(wc -c < "$SOURCE_DIR/sanaa-knowledge-index.md" | tr -d ' ')"
[[ "$pack_bytes" -eq "$EXPECTED_PACK_BYTES" ]]
[[ "$index_bytes" -eq "$EXPECTED_INDEX_BYTES" ]]
rg -q '^version: 2\.0\.0$' "$SOURCE_DIR/sanaa-knowledge-index.md"
for module in directions procedural-tasks bulk-adjustments a11y-applied style-profile; do
  rg -q "^name: $module$" "$SOURCE_DIR/sanaa-knowledge-$module.md"
done
rg -q '24 CSS px diameter circles' "$SOURCE_DIR/sanaa-knowledge-a11y-applied.md"
rg -q 'equivalent to a 2 CSS px perimeter' "$SOURCE_DIR/sanaa-knowledge-a11y-applied.md"
rg -q 'must not entirely hide the focused' "$SOURCE_DIR/sanaa-knowledge-a11y-applied.md"
if rg -q 'Settings ▸ Sanaa ▸ Style Profile|app injects with every request' \
  "$SOURCE_DIR/sanaa-knowledge-style-profile.md"; then
  echo 'verify_sanaa_knowledge_pack: style module claims an unshipped persistence surface' >&2
  exit 1
fi
printf 'PASS  source pack: %d served modules + changelog, %d bytes (index %d)\n' \
  "$KNOWLEDGE_COUNT" "$pack_bytes" "$index_bytes"

if [[ "${1:-}" == "--source-only" ]]; then
  printf '\nRESULT  Sanaa guidance v2 source gate passed.\n'
  exit 0
fi

APP_RESOURCES="${1:-}"

if [[ ! -S "$SOCKET_PATH" ]]; then
  echo "verify_sanaa_knowledge_pack: EXP's agent socket is unavailable" >&2
  echo "Start EXP and enable Handoff ▸ Agent ▸ Allow local agent access." >&2
  exit 1
fi
if [[ -z "$APP_RESOURCES" || ! -d "$APP_RESOURCES" ]]; then
  echo "Usage: scripts/verify_sanaa_knowledge_pack.sh '/path/to/EXP [design].app/Contents/Resources'" >&2
  exit 1
fi

# This intentionally uses the public MCP transport directly rather than the
# bundled Codex adapter, proving the pack stays provider-neutral.
initialize='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"exp-provider-neutral-mcp-check","version":"1"}}}'
rpc() {
  local delay="${2:-0.25}"
  { printf '%s\n%s\n' "$initialize" "$1"; sleep "$delay" } |
    nc -U "$SOCKET_PATH" 2>/dev/null
}
response_for_request() {
  jq -c 'select(.id == 2)'
}

list_reply="$(rpc '{"jsonrpc":"2.0","id":2,"method":"resources/list"}' | response_for_request)"
list_count="$(printf '%s\n' "$list_reply" | jq '[.result.resources[] | select(.uri | startswith("exp://sanaa/knowledge/"))] | length')"
[[ "$list_count" -eq "$KNOWLEDGE_COUNT" ]]
printf '%s\n' "$list_reply" |
  jq -e '.result.resources | any(.uri == "exp://orientation")' >/dev/null
printf 'PASS  resources/list returned orientation + %d knowledge modules\n' "$KNOWLEDGE_COUNT"

has_guide="$(printf '%s\n' "$list_reply" | jq -r '.result.resources | any(.uri == "exp://sanaa/guide")')"
if [[ "$has_guide" == true ]]; then
  guide_reply="$(rpc '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"exp://sanaa/guide"}}' | response_for_request)"
  printf '%s\n' "$guide_reply" | jq -j '.result.contents[0].text' |
    cmp -s - "$APP_RESOURCES/sanaa-guide.md"
  cmp -s "$APP_RESOURCES/sanaa-guide.md" "$SOURCE_DIR/sanaa-guide.md"
  printf 'PASS  resources/read returned the etiquette guide byte-identically\n'
fi

checked=0
while IFS=$'\t' read -r uri file; do
  request="$(jq -cn --arg uri "$uri" '{jsonrpc:"2.0",id:2,method:"resources/read",params:{uri:$uri}}')"
  reply="$(rpc "$request" | response_for_request)"
  printf '%s\n' "$reply" | jq -j '.result.contents[0].text' |
    cmp -s - "$APP_RESOURCES/$file.md"
  cmp -s "$APP_RESOURCES/$file.md" "$SOURCE_DIR/$file.md"
  checked=$((checked + 1))
done < <(
  rg '^\s+\("exp://sanaa/knowledge/' "$PROJECT_ROOT/EXP [design]/Export/AgentBridge.swift" |
    sed -E 's/.*\("([^"]+)", "([^"]+)".*/\1\t\2/'
)
[[ "$checked" -eq "$KNOWLEDGE_COUNT" ]]
printf 'PASS  resources/read returned %d/%d modules byte-identical to source and bundle\n' "$checked" "$KNOWLEDGE_COUNT"

tools_reply="$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | response_for_request)"
printf '%s\n' "$tools_reply" |
  jq -e '.result.tools | any(.name == "get_design_guidance")' >/dev/null
printf 'PASS  tools/list advertises get_design_guidance\n'
if [[ "$has_guide" == true ]]; then
  printf '%s\n' "$tools_reply" |
    jq -e '.result.tools | any(.name == "get_sanaa_guide")' >/dev/null
  printf 'PASS  tools/list advertises get_sanaa_guide\n'

  guide_tool="$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_sanaa_guide","arguments":{}}}' | response_for_request)"
  printf '%s\n' "$guide_tool" | jq -j '.result.content[0].text' |
    cmp -s - "$APP_RESOURCES/sanaa-guide.md"
  printf 'PASS  get_sanaa_guide returned the bundled guide byte-identically\n'
fi

checked=0
while IFS=$'\t' read -r uri file; do
  module="${uri#exp://sanaa/knowledge/}"
  request="$(jq -cn --arg module "$module" '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:"get_design_guidance",arguments:{module:$module}}}')"
  reply="$(rpc "$request" | response_for_request)"
  printf '%s\n' "$reply" | jq -j '.result.content[0].text' |
    cmp -s - "$APP_RESOURCES/$file.md"
  checked=$((checked + 1))
done < <(
  rg '^\s+\("exp://sanaa/knowledge/' "$PROJECT_ROOT/EXP [design]/Export/AgentBridge.swift" |
    sed -E 's/.*\("([^"]+)", "([^"]+)".*/\1\t\2/'
)
[[ "$checked" -eq "$KNOWLEDGE_COUNT" ]]
printf 'PASS  get_design_guidance returned %d/%d bundled modules byte-identically\n' "$checked" "$KNOWLEDGE_COUNT"

bad_module="$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_design_guidance","arguments":{"module":"not-real"}}}' | response_for_request)"
printf '%s\n' "$bad_module" | jq -e '.result.isError == true and (.result.content[0].text | contains("Unknown Sanaa knowledge module"))' >/dev/null
printf 'PASS  unknown guidance module returned an honest tool error\n'

unknown="$(rpc '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"exp://sanaa/knowledge/not-real"}}' | response_for_request)"
[[ "$(printf '%s\n' "$unknown" | jq -r '.error.code')" -eq -32602 ]]
printf 'PASS  unknown resource URI returned -32602\n'

# The orientation is generated from the whole live document and may take a few
# seconds on a stress file; keep this one connection open long enough to receive
# its asynchronous reply instead of mistaking a client-side close for a failure.
orientation="$(rpc '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"exp://orientation"}}' 8 | response_for_request)"
printf '%s\n' "$orientation" | jq -e '.result.contents[0].text | length > 0' >/dev/null
printf 'PASS  existing document-backed orientation resource still reads\n'

printf '\nRESULT  FEAT-054 provider-neutral MCP resource/tool gate passed.\n'
