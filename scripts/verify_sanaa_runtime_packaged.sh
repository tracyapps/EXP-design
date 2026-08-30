#!/bin/zsh
# Build the real app bundle, then repeat Sanaa's conversation transport contract
# through the helper copied into Contents/Helpers. The runtime advertises only
# EXP's canvas MCP server; these generic probe prompts intentionally call no tools.
# Pass `--canvas-read` while EXP is running with Agent access enabled to add the
# read-only list_artboards → get_artboard approval regression.
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
CHECK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/exp-sanaa-runtime.XXXXXX")"
trap 'rm -rf "$CHECK_TMP"' EXIT

CANVAS_READ_ARGS=()
if [[ "${1:-}" == "--canvas-read" ]]; then
  CANVAS_READ_ARGS=(--canvas-read)
  shift
fi

CODEX_EXECUTABLE="${1:-$(command -v codex || true)}"
if [[ -z "$CODEX_EXECUTABLE" || ! -x "$CODEX_EXECUTABLE" ]]; then
  echo "verify_sanaa_runtime_packaged: Codex was not found; pass its executable path." >&2
  exit 1
fi

# npm exposes a JavaScript shim at bin/codex.js, while the sandboxed runtime
# deliberately launches and authenticates the signed native package binary.
CODEX_RESOLVED="${CODEX_EXECUTABLE:A}"
if [[ "$CODEX_RESOLVED" == */@openai/codex/bin/codex.js ]]; then
  CODEX_PACKAGE_ROOT="${CODEX_RESOLVED:h:h}"
  case "$(uname -m)" in
    arm64) CODEX_NATIVE="$CODEX_PACKAGE_ROOT/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex" ;;
    x86_64) CODEX_NATIVE="$CODEX_PACKAGE_ROOT/node_modules/@openai/codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex" ;;
    *) CODEX_NATIVE="" ;;
  esac
  if [[ -n "$CODEX_NATIVE" && -x "$CODEX_NATIVE" ]]; then
    CODEX_EXECUTABLE="$CODEX_NATIVE"
  fi
fi

BUILD_LOG="$CHECK_TMP/xcodebuild.log"
if ! xcodebuild \
  -project "$PROJECT_ROOT/EXP [design].xcodeproj" \
  -scheme "EXP [design]" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$CHECK_TMP/DerivedData" \
  build CODE_SIGNING_ALLOWED=NO >"$BUILD_LOG" 2>&1; then
  tail -120 "$BUILD_LOG" >&2
  exit 1
fi

RUNTIME="$CHECK_TMP/DerivedData/Build/Products/Debug/EXP [design].app/Contents/Helpers/sanaa-runtime"
if [[ ! -x "$RUNTIME" ]]; then
  echo "verify_sanaa_runtime_packaged: app build did not embed sanaa-runtime" >&2
  exit 1
fi

xcrun swiftc \
  "$PROJECT_ROOT/EXP [design]/UI/SanaaRuntimeProtocol.swift" \
  "$PROJECT_ROOT/scripts/SanaaRuntimePackagedCheck.swift" \
  -o "$CHECK_TMP/sanaa-runtime-packaged-check"

"$CHECK_TMP/sanaa-runtime-packaged-check" \
  --runtime "$RUNTIME" \
  --codex "$CODEX_EXECUTABLE" \
  "${CANVAS_READ_ARGS[@]}"
