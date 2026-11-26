#!/bin/zsh
# 只在孩子的 Mac 上运行。孩子端被结束或崩溃后，5 秒左右自动重新启动；输对家长设的退出密码退出的那次除外（ADR-0016、issue #19）。
# 不需要下载仓库，也可以直接在孩子 Mac 的终端里运行：
#   curl -fsSL https://raw.githubusercontent.com/lukeliu95/little-beacon/main/scripts/install-auto-recovery.sh | zsh
set -uo pipefail

LABEL="app.littlebeacon.mac"
APP="/Applications/小灯塔.app"
PLIST="/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$UID"
SERVICE="$DOMAIN/$LABEL"
STATE="$HOME/Library/Application Support/LittleBeacon/state.json"
# 0.10.0 froze for about a minute when launchd started it; 0.11.0 fixed that.
MINIMUM_BUILD=11000

fail() {
  echo "没有装好：$1" >&2
  exit 1
}

running_pid() {
  launchctl print "$SERVICE" 2>/dev/null | awk '$1 == "pid" && $2 == "=" { print $3; exit }'
}

# Waits up to $1 seconds for launchd to report a running copy other than $2.
wait_for_new_pid() {
  local limit=$1 old=$2 pid tenth
  for tenth in {1..$((limit * 10))}; do
    pid=$(running_pid)
    if [[ -n "$pid" && "$pid" != "$old" ]]; then
      echo "$pid $tenth"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

[[ -d "$APP" ]] || fail "“应用程序”里没有小灯塔.app。请先把小灯塔拖进“应用程序”，再运行这条命令。"
BUILD=$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist" 2>/dev/null || echo 0)
(( BUILD >= MINIMUM_BUILD )) || fail "这台 Mac 上的小灯塔太旧（构建号 $BUILD），请先升级到 0.11.0 或更新的版本（在小灯塔菜单里“检查更新”，或从 GitHub 下载）。"
if [[ -f "$STATE" ]] && grep -Eq '"role" *: *"parent"' "$STATE"; then
  fail "这台 Mac 是家长端。自动恢复只装在孩子的 Mac 上，否则家长端会关不掉。"
fi

TEMP_PLIST="$(mktemp)"
trap 'rm -f "$TEMP_PLIST"' EXIT
# Keep this copy identical to packaging/launch-agent.plist; a test compares the two.
cat > "$TEMP_PLIST" <<'PLIST_END'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>app.littlebeacon.mac</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/小灯塔.app/Contents/MacOS/LittleBeacon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
PLIST_END
plutil -lint -s "$TEMP_PLIST" || fail "后台服务配置文件有问题。"

echo "需要输入这台 Mac 的管理员密码（输入时不显示字符）。"
sudo install -o root -g wheel -m 644 "$TEMP_PLIST" "$PLIST" || fail "没能写入 $PLIST。"

# Enable first: a job that was ever disabled refuses to bootstrap.
launchctl enable "$SERVICE" 2>/dev/null
if launchctl print "$SERVICE" >/dev/null 2>&1; then
  launchctl bootout "$SERVICE" 2>/dev/null
  # bootout returns before the old job is gone; bootstrapping too early fails.
  for _ in {1..50}; do
    launchctl print "$SERVICE" >/dev/null 2>&1 || break
    sleep 0.2
  done
fi

if ! BOOTSTRAP_ERROR=$(launchctl bootstrap "$DOMAIN" "$PLIST" 2>&1); then
  sleep 2
  BOOTSTRAP_ERROR=$(launchctl bootstrap "$DOMAIN" "$PLIST" 2>&1) \
    || fail "系统没有接受后台服务（$BOOTSTRAP_ERROR）。"
fi

FIRST=$(wait_for_new_pid 15 "") || fail "后台服务已注册，但小灯塔没有启动起来。请把这段输出发给开发者。"
FIRST_PID=${FIRST%% *}
echo "小灯塔已由后台服务启动。"

echo "正在测试：结束小灯塔，看它会不会自己回来…"
sleep 3
kill -9 "$FIRST_PID" 2>/dev/null
if SECOND=$(wait_for_new_pid 15 "$FIRST_PID"); then
  TENTHS=${SECOND##* }
  printf '测试通过：结束后 %d.%d 秒自动恢复。\n' $((TENTHS / 10)) $((TENTHS % 10))
else
  fail "小灯塔被结束后 15 秒内没有回来。请把这段输出和下面的状态发给开发者：
$(launchctl print "$SERVICE" 2>&1 | grep -E 'state|pid|last exit|runs|throttle' | head -10)"
fi

echo "完成：小灯塔已设置为登录启动，被结束后 5 秒内自动恢复。输对家长设的退出密码才能真正退出。"
