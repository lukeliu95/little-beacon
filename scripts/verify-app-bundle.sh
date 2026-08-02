#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${1:-$ROOT/outputs/小灯塔.app}"
EXECUTABLE="$APP/Contents/MacOS/LittleBeacon"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "LittleBeacon executable is missing: $EXECUTABLE" >&2
  exit 1
fi

ARCHITECTURES="$(lipo -archs "$EXECUTABLE")"
for REQUIRED_ARCHITECTURE in arm64 x86_64; do
  if [[ " $ARCHITECTURES " != *" $REQUIRED_ARCHITECTURE "* ]]; then
    echo "LittleBeacon must be Universal 2; found architectures: $ARCHITECTURES" >&2
    exit 1
  fi
done

RESOURCE_DIRECTORY="$APP/Contents/Resources/LittleBeacon_LittleBeaconApp.bundle/Contents/Resources"
for RESOURCE in pomodoro-alarm.wav pomodoro-complete.wav; do
  if [[ ! -f "$RESOURCE_DIRECTORY/$RESOURCE" ]]; then
    echo "LittleBeacon resource is missing: $RESOURCE" >&2
    exit 1
  fi
done

plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
echo "Verified Universal 2 app bundle: $ARCHITECTURES"
