#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/outputs/小灯塔.app"
CACHE="$ROOT/work"

mkdir -p "$CACHE/swift-home" "$CACHE/clang-cache" "$CACHE/swiftpm-cache"

env \
  HOME="$CACHE/swift-home" \
  CLANG_MODULE_CACHE_PATH="$CACHE/clang-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$CACHE/swiftpm-cache" \
  swift build --configuration release --disable-sandbox --package-path "$ROOT"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/LittleBeacon" "$APP/Contents/MacOS/LittleBeacon"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/branding/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

RESOURCE_BUNDLE="$ROOT/.build/release/LittleBeacon_LittleBeaconApp.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
fi

chmod 755 "$APP/Contents/MacOS/LittleBeacon"
codesign --force --deep --sign - "$APP"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/outputs/LittleBeacon-macOS.zip"
echo "$APP"
