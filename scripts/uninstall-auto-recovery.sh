#!/bin/zsh
set -euo pipefail

# 家长维护用：停止孩子端并移除自动恢复。孩子端没有退出入口（ADR-0016），这是唯一的正常关闭方式。
PLIST="/Library/LaunchAgents/app.littlebeacon.mac.plist"

launchctl bootout "gui/$UID/app.littlebeacon.mac" 2>/dev/null || true
sudo rm -f "$PLIST"

echo "已停止小灯塔并移除自动恢复。重新运行 install-auto-recovery.sh 可以恢复。"
