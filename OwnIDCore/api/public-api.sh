#!/usr/bin/env bash
set -euo pipefail

COMMAND="${1:-check}"
API_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$(basename "$(dirname "$API_DIR")")"
REPO_ROOT="$(cd "$API_DIR/../.." && pwd)"
BASELINE_PATH="$API_DIR/$MODULE.symbols.json"
TRIPLE="${OWNID_API_TARGET_TRIPLE:-arm64-apple-ios13.0-simulator}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ownid-public-api-${MODULE}.XXXXXX")"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

usage() {
    echo "Usage: $0 check|dump"
}

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing required tool: $1" >&2
        exit 2
    fi
}

case "$COMMAND" in
    check|dump)
        ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

require_tool jq
require_tool swift
require_tool xcrun
require_tool xcode-select

SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
SCRATCH_PATH="$TMP_ROOT/build"
RAW_SYMBOLS_DIR="$TMP_ROOT/raw"
NORMALIZED_PATH="$TMP_ROOT/$MODULE.symbols.json"

swift build \
    --package-path "$REPO_ROOT" \
    --scratch-path "$SCRATCH_PATH" \
    --sdk "$SDK_PATH" \
    --triple "$TRIPLE" \
    --target "$MODULE"

MODULE_PATH="$(find "$SCRATCH_PATH" -type f -path "*/debug/Modules/$MODULE.swiftmodule" -print -quit)"
if [[ -z "$MODULE_PATH" ]]; then
    echo "error: failed to locate built module for $MODULE" >&2
    exit 1
fi

MODULES_DIR="$(dirname "$MODULE_PATH")"
MODULE_CACHE_DIR="$(find "$SCRATCH_PATH" -type d -name ModuleCache -print -quit)"
if [[ -z "$MODULE_CACHE_DIR" ]]; then
    MODULE_CACHE_DIR="$TMP_ROOT/ModuleCache"
fi

mkdir -p "$RAW_SYMBOLS_DIR"

xcrun swift-symbolgraph-extract \
    -module-name "$MODULE" \
    -target "$TRIPLE" \
    -sdk "$SDK_PATH" \
    -I "$MODULES_DIR" \
    -F "$DEVELOPER_DIR_PATH/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks" \
    -I "$DEVELOPER_DIR_PATH/Platforms/iPhoneSimulator.platform/Developer/usr/lib" \
    -L "$DEVELOPER_DIR_PATH/Platforms/iPhoneSimulator.platform/Developer/usr/lib" \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -minimum-access-level public \
    -skip-synthesized-members \
    -omit-extension-block-symbols \
    -pretty-print \
    -output-dir "$RAW_SYMBOLS_DIR"

jq -S -s '
  def clean_nulls:
    with_entries(select(.value != null));

  def norm_fragment:
    ({kind, spelling} + (if has("preciseIdentifier") then {preciseIdentifier} else {} end));

  def norm_symbol:
    {
      kind: .kind.identifier,
      precise: .identifier.precise,
      path: .pathComponents,
      title: .names.title,
      access: .accessLevel,
      declaration: [.declarationFragments[] | norm_fragment],
      availability: (.availability // null),
      functionSignature: (.functionSignature // null),
      swiftGenerics: (.swiftGenerics // null),
      swiftExtension: (.swiftExtension // null)
    } | clean_nulls;

  def norm_relationship:
    {
      kind,
      source,
      target,
      targetFallback: (.targetFallback // null),
      sourceOrigin: (.sourceOrigin // null)
    } | clean_nulls;

  {
    format: 1,
    module: .[0].module,
    symbols: ([.[].symbols[] | norm_symbol] | unique | sort_by(.precise, (.path | join("/")), .kind)),
    relationships: ([.[].relationships[] | norm_relationship] | unique | sort_by(.kind, .source, (.target // ""), (.targetFallback // "")))
  }
' "$RAW_SYMBOLS_DIR"/*.symbols.json > "$NORMALIZED_PATH"

case "$COMMAND" in
    dump)
        cp "$NORMALIZED_PATH" "$BASELINE_PATH"
        echo "Updated $BASELINE_PATH"
        ;;
    check)
        if [[ ! -f "$BASELINE_PATH" ]]; then
            echo "error: missing API baseline: $BASELINE_PATH" >&2
            echo "Run '$0 dump' to create it." >&2
            exit 1
        fi

        if ! diff -u "$BASELINE_PATH" "$NORMALIZED_PATH"; then
            echo "error: $MODULE public API changed. Run '$0 dump' if this change is intentional." >&2
            exit 1
        fi

        echo "$MODULE public API is unchanged."
        ;;
esac
