#!/bin/zsh
# 家长维护用：停止孩子端并移除自动恢复。平时孩子端用家长设置的退出密码退出即可（issue #19）。
# 不需要下载仓库：
#   curl -fsSL https://raw.githubusercontent.com/lukeliu95/little-beacon/main/scripts/uninstall-auto-recovery.sh | zsh
set -uo pipefail

LABEL="app.littlebeacon.mac"
PLIST="/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null
echo "需要输入这台 Mac 的管理员密码（输入时不显示字符）。"
sudo rm -f "$PLIST" || { echo "没能删除 $PLIST。" >&2; exit 1; }

echo "已停止小灯塔并移除自动恢复。重新运行 install-auto-recovery.sh 可以恢复。"
