#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${1#v}"
TAG="v$VERSION"
PLIST="$ROOT/packaging/Info.plist"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "usage: publish-release.sh MAJOR.MINOR.PATCH" >&2
  exit 2
fi
if [[ "$(git -C "$ROOT" branch --show-current)" != "main" ]]; then
  echo "release must be published from main" >&2
  exit 1
fi
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]]; then
  echo "commit tracked changes before publishing" >&2
  exit 1
fi

SOURCE_VERSION="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
if [[ "$SOURCE_VERSION" != "$VERSION" ]]; then
  echo "Info.plist version is $SOURCE_VERSION, expected $VERSION" >&2
  exit 1
fi

PARTS=("${(@s:.:)VERSION}")
BUILD_NUMBER=$((PARTS[1] * 1000000 + PARTS[2] * 1000 + PARTS[3]))
SOURCE_BUILD="$(plutil -extract CFBundleVersion raw "$PLIST")"
if [[ "$SOURCE_BUILD" != "$BUILD_NUMBER" ]]; then
  echo "Info.plist build is $SOURCE_BUILD, expected $BUILD_NUMBER" >&2
  exit 1
fi

cd "$ROOT"
./scripts/run-checks.sh
LITTLE_BEACON_VERSION="$VERSION" LITTLE_BEACON_BUILD="$BUILD_NUMBER" ./scripts/package-app.sh

SIGN_TOOL="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
if [[ ! -x "$SIGN_TOOL" ]]; then
  echo "Sparkle sign_update tool not found" >&2
  exit 1
fi
SIGNATURE="$($SIGN_TOOL --account little-beacon "$ROOT/outputs/LittleBeacon-macOS.zip")"
./scripts/make-appcast.sh "$VERSION" "$BUILD_NUMBER" \
  "$ROOT/outputs/LittleBeacon-macOS.zip" "$ROOT/outputs/appcast.xml" "$SIGNATURE"

ED_SIGNATURE="$(echo "$SIGNATURE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
$SIGN_TOOL --account little-beacon --verify "$ROOT/outputs/LittleBeacon-macOS.zip" "$ED_SIGNATURE"

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag -a "$TAG" -m "小灯塔 $VERSION"
fi
git push origin "$TAG"
gh release create "$TAG" \
  "$ROOT/outputs/LittleBeacon-macOS.zip" \
  "$ROOT/outputs/appcast.xml" \
  --title "小灯塔 $VERSION" \
  --generate-notes

echo "Published https://github.com/lukeliu95/little-beacon/releases/tag/$TAG"
