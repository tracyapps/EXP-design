#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="$ROOT/EXP [design]/UI/SettingsWindow.swift"
PANEL="$ROOT/EXP [design]/UI/SanaaPanel.swift"

require() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! grep -Fq "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

require 'Button("Set up Sanaa…")' "$SETTINGS" "Settings is missing the guided setup entry point"
require 'Button("Set up Sanaa…")' "$PANEL" "Sanaa empty state is missing the guided setup entry point"

for host in \
  'case codex = "Sanaa in EXP (Codex)"' \
  'case claudeCode = "Claude Code"' \
  'case claudeDesktop = "Claude Desktop"' \
  'case other = "Another MCP app"' \
  'case none = "I don'"'"'t have one yet"'; do
  require "$host" "$SETTINGS" "guided setup is missing a supported host choice"
done

require 'EXP never asks for or stores its password, subscription, or API key.' "$SETTINGS" "privacy copy is missing"
require 'Connect without sharing credentials' "$SETTINGS" "credential boundary step is missing"
require 'Copy setup' "$SETTINGS" "copy-first setup action is missing"
require 'Turn on canvas bridge' "$SETTINGS" "external-client bridge action is missing"
require 'Enable and connect Sanaa' "$SETTINGS" "in-app Sanaa action is missing"
require 'Send a hello' "$SETTINGS" "read-only connection check is missing"
require 'Do not change it.' "$SETTINGS" "hello check does not explicitly stay read-only"
require '.accessibilityHint("Opens a guided connection walkthrough")' "$SETTINGS" "setup entry point accessibility hint is missing"
require '.accessibilityHint("Chooses the local assistant to connect with EXP")' "$SETTINGS" "host picker accessibility hint is missing"
require '.accessibilityHint("Copies this setup for the selected assistant")' "$SETTINGS" "copy action accessibility hint is missing"

echo 'RESULT  FEAT-051 guided setup source/accessibility gate passed'
