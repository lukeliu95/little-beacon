#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/outputs/小灯塔.app"
CACHE="$ROOT/work"
VERSION="${LITTLE_BEACON_VERSION:-$(plutil -extract CFBundleShortVersionString raw "$ROOT/packaging/Info.plist")}"
BUILD_NUMBER="${LITTLE_BEACON_BUILD:-$(plutil -extract CFBundleVersion raw "$ROOT/packaging/Info.plist")}"

mkdir -p "$CACHE/swift-home" "$CACHE/clang-cache" "$CACHE/swiftpm-cache"

env \
  HOME="$CACHE/swift-home" \
  CLANG_MODULE_CACHE_PATH="$CACHE/clang-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$CACHE/swiftpm-cache" \
  swift build --configuration release --disable-sandbox --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$ROOT/.build/release/LittleBeacon" "$APP/Contents/MacOS/LittleBeacon"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/branding/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

SPARKLE_FRAMEWORK="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle.framework not found after Swift build" >&2
  exit 1
fi
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

RESOURCE_BUNDLE="$ROOT/.build/release/LittleBeacon_LittleBeaconApp.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
fi

chmod 755 "$APP/Contents/MacOS/LittleBeacon"
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --deep --sign - "$APP"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/outputs/LittleBeacon-macOS.zip"
echo "$APP"
