#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CACHE="$ROOT/work"
mkdir -p "$CACHE/swift-home" "$CACHE/clang-cache" "$CACHE/swiftpm-cache"

env \
  HOME="$CACHE/swift-home" \
  CLANG_MODULE_CACHE_PATH="$CACHE/clang-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$CACHE/swiftpm-cache" \
  swift test --disable-sandbox --package-path "$ROOT"

cd "$ROOT/backend"
npm run check
npm test

plutil -lint "$ROOT/packaging/Info.plist"
plutil -lint "$ROOT/packaging/launch-agent.plist"
