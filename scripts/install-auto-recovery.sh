#!/bin/zsh
set -euo pipefail

APP="/Applications/小灯塔.app"
PLIST="/Library/LaunchAgents/app.littlebeacon.mac.plist"
TEMP_PLIST="$(mktemp)"

if [[ ! -d "$APP" ]]; then
  echo "请先把小灯塔.app 放进 /Applications。" >&2
  exit 1
fi

cp "${0:A:h}/../packaging/launch-agent.plist" "$TEMP_PLIST"
sudo cp "$TEMP_PLIST" "$PLIST"
sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"
rm -f "$TEMP_PLIST"

launchctl bootout "gui/$UID/app.littlebeacon.mac" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl enable "gui/$UID/app.littlebeacon.mac"

echo "小灯塔已设置为登录启动，并会在异常退出后恢复。"
