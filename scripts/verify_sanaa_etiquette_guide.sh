#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
GUIDE="$PROJECT_ROOT/EXP [design]/Resources/SanaaKnowledge/sanaa-guide.md"
BRIDGE="$PROJECT_ROOT/EXP [design]/Export/AgentBridge.swift"
RUNTIME="$PROJECT_ROOT/sanaa-runtime/CodexAdapter.swift"

[[ -f "$GUIDE" ]]
rg -q '^version: 1\.0\.0$' "$GUIDE"
rg -q 'Complete or finish this' "$GUIDE"
rg -q 'Variations' "$GUIDE"
rg -q 'Repetitive work on existing content' "$GUIDE"
rg -q 'only reference currency' "$GUIDE"
rg -q 'Never call `removeNodes` unless deletion is explicitly' "$GUIDE"
rg -q 'one transaction and one Undo step' "$GUIDE"
rg -q 'get_tokens' "$GUIDE"
rg -q 'exp://sanaa/guide' "$BRIDGE"
rg -q 'tool\("get_sanaa_guide"' "$BRIDGE"
rg -q '\\"get_sanaa_guide\\"' "$RUNTIME"
rg -q 'Read get_sanaa_guide before changing a canvas' "$RUNTIME"

echo 'RESULT  FEAT-053 Sanaa etiquette source/resource/runtime gate passed'
