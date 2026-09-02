#!/bin/zsh
# FEAT-055 public-route gate. The source-only phase proves both allowlists and
# tool registration. The live phase talks only to EXP's local MCP socket and
# calls read tools; it never invokes apply_edits or any document write path.
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SOCKET_PATH="$HOME/Library/Containers/tapps.EXP--design-/Data/Library/Application Support/EXP/agent.sock"

rg -q 'tool\("get_design_facts"' "$PROJECT_ROOT/EXP [design]/Export/AgentBridge.swift"
rg -q 'case "get_design_facts"' "$PROJECT_ROOT/EXP [design]/Export/AgentBridge.swift"
rg -q 'SanaaFacts\.report\(' "$PROJECT_ROOT/EXP [design]/Export/AgentBridge.swift"
rg -q 'enabled_tools=.*get_design_facts' "$PROJECT_ROOT/sanaa-runtime/CodexAdapter.swift"
printf 'PASS  source registration: MCP definition, public route, engine call, and packaged allowlist\n'

if [[ "${1:-}" == "--source-only" ]]; then
  printf '\nRESULT  FEAT-055 source registration gate passed.\n'
  exit 0
fi

if [[ ! -S "$SOCKET_PATH" ]]; then
  echo "verify_sanaa_facts_live: EXP's agent socket is unavailable" >&2
  echo "Rebuild and launch EXP, open a document with an artboard, then enable Handoff ▸ Agent ▸ Allow local agent access." >&2
  exit 1
fi

initialize='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"feat-055-facts-gate","version":"1"}}}'
rpc() {
  local delay="${2:-8}"
  { printf '%s\n%s\n' "$initialize" "$1"; sleep "$delay" } |
    nc -U "$SOCKET_PATH" 2>/dev/null
}
response_for_request() {
  jq -c 'select(.id == 2)'
}
call() {
  local name="$1" arguments="$2" request
  request="$(jq -cn --arg name "$name" --argjson arguments "$arguments" \
    '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:$name,arguments:$arguments}}')"
  rpc "$request" | response_for_request
}
tool_text() {
  jq -r '.result.content[0].text'
}

tools_reply="$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' 1 | response_for_request)"
printf '%s\n' "$tools_reply" | jq -e '
  .result.tools
  | any(.name == "get_design_facts"
      and .inputSchema.additionalProperties == false
      and .inputSchema.required == []
      and (.inputSchema.properties | keys == ["artboardId"]))
' >/dev/null
printf 'PASS  tools/list advertises the bounded optional-artboard contract\n'

list_before="$(call list_artboards '{}')"
artboard_id="$(printf '%s\n' "$list_before" | tool_text | jq -r '.artboards[0].id // empty')"
if [[ -z "$artboard_id" ]]; then
  echo "verify_sanaa_facts_live: the front document needs at least one artboard" >&2
  exit 1
fi
artboard_args="$(jq -cn --arg id "$artboard_id" '{id:$id}')"
facts_args="$(jq -cn --arg id "$artboard_id" '{artboardId:$id}')"
artboard_before="$(call get_artboard "$artboard_args")"
facts_first="$(call get_design_facts "$facts_args")"
facts_second="$(call get_design_facts "$facts_args")"
artboard_after="$(call get_artboard "$artboard_args")"
list_after="$(call list_artboards '{}')"

[[ "$(printf '%s\n' "$facts_first" | jq -r '.result.isError // false')" == "false" ]]
facts_text="$(printf '%s\n' "$facts_first" | tool_text)"
printf '%s\n' "$facts_text" | jq -e '
  .schemaVersion == 2
  and .scope.kind == "artboard"
  and .interpretation == "measured facts, not verdicts"
  and .colorSpace == "sRGB"
  and (.colorPairs | type == "array")
  and (.gradientColorPairs | type == "array")
  and (.nonTextContrast | type == "array")
  and (.textSizes | type == "array")
  and (.targetSizes | type == "array")
  and (.spacingInventory.autoLayoutGaps | type == "array")
  and (.spacingInventory.siblingDeltas | type == "array")
  and (.fontInventory | type == "array")
  and (.notAssessed | type == "array")
  and (.truncated | type == "boolean")
  and .targetSizeReference.criterion == "WCAG 2.2 SC 2.5.8"
  and .targetSizeReference.exceptions == ["spacing","equivalent","inline","userAgentControl","essential"]
  and .counts.colorPairs == (.colorPairs | length)
  and .counts.gradientColorPairs == (.gradientColorPairs | length)
  and .counts.nonTextPairs == (.nonTextContrast | length)
  and .counts.targets == (.targetSizes | length)
  and (all(.colorPairs[]?; .criterion == "WCAG 2.2 SC 1.4.3" and (.ratio | type == "number")))
  and (all(.gradientColorPairs[]?; .criterion == "WCAG 2.2 SC 1.4.3" and (.minimumRatio | type == "number") and .estimated == true))
  and (all(.nonTextContrast[]?; .criterion == "WCAG 2.2 SC 1.4.11" and (.ratio | type == "number")))
' >/dev/null
if printf '%s\n' "$facts_text" | rg -qi 'ADA compliant|WCAG compliant|passes WCAG|fails WCAG|non-compliant'; then
  echo "verify_sanaa_facts_live: facts response crossed into verdict language" >&2
  exit 1
fi
printf 'PASS  live facts schema: measured categories, criteria, heuristics, omissions, and caps\n'

[[ "$(printf '%s\n' "$facts_first" | tool_text)" == "$(printf '%s\n' "$facts_second" | tool_text)" ]]
[[ "$(printf '%s\n' "$artboard_before" | tool_text)" == "$(printf '%s\n' "$artboard_after" | tool_text)" ]]
[[ "$(printf '%s\n' "$list_before" | tool_text)" == "$(printf '%s\n' "$list_after" | tool_text)" ]]
printf 'PASS  repeated facts are deterministic and leave artboard content/count unchanged\n'

bad_uuid="$(call get_design_facts '{"artboardId":"not-a-uuid"}')"
printf '%s\n' "$bad_uuid" | jq -e '
  .result.isError == true
  and (.result.content[0].text | contains("must be one valid UUID string"))
' >/dev/null
unknown_arg="$(call get_design_facts '{"force":true}')"
printf '%s\n' "$unknown_arg" | jq -e '
  .result.isError == true
  and (.result.content[0].text | contains("accepts only optional artboardId"))
' >/dev/null
missing="$(call get_design_facts '{"artboardId":"00000000-0000-0000-0000-000000000000"}')"
printf '%s\n' "$missing" | jq -e '
  .result.isError == true
  and (.result.content[0].text | contains("No artboard exists"))
' >/dev/null
printf 'PASS  malformed, extra, and unknown-artboard requests return honest tool errors\n'

printf '\nRESULT  FEAT-055 live public-route/no-write gate passed.\n'
