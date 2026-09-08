#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
swift build --disable-sandbox --package-path "$PACKAGE_ROOT" --target CodexQuotaCore
BIN_DIR="$(swift build --disable-sandbox --package-path "$PACKAGE_ROOT" --show-bin-path)"
CHECK_BINARY="$PACKAGE_ROOT/.build/mouse-gesture-controller-checks"
trap 'rm -f "$CHECK_BINARY"' EXIT
swiftc -parse-as-library -I "$BIN_DIR/Modules" \
    "$PACKAGE_ROOT/Sources/CodexQuotaApp/MouseGestureController.swift" \
    "$PACKAGE_ROOT/Tests/MouseGestureControllerChecks.swift" \
    "$BIN_DIR"/CodexQuotaCore.build/*.swift.o -o "$CHECK_BINARY"
"$CHECK_BINARY"
