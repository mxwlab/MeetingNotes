#!/bin/zsh
set -euo pipefail

BASE="${0:A:h:h}"
source "$BASE/scripts/menubar_identity.sh"
SOURCE="$BASE/launchd/com.moxiuwen.meetingnotes.menubar.plist.template"
LABEL="$(mn_menubar_label "$BASE")"
TARGET="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_EXECUTABLE="$BASE/dist-menubar/MeetingNotes 菜单栏.app/Contents/MacOS/MeetingNotes 菜单栏"
LOG_DIR="$BASE/logs"
DOMAIN="gui/$(id -u)"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  print -u2 "未找到菜单栏 App，请先运行：./venv-ui/bin/python setup_ui.py py2app -A"
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"
sed \
  -e "s|__MENUBAR_LABEL__|$LABEL|g" \
  -e "s|__APP_EXECUTABLE__|$APP_EXECUTABLE|g" \
  -e "s|__MEETINGNOTES_BASE__|$BASE|g" \
  -e "s|__LOG_DIR__|$LOG_DIR|g" \
  "$SOURCE" > "$TARGET"
chmod 600 "$TARGET"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
if ! launchctl bootstrap "$DOMAIN" "$TARGET"; then
  sleep 1
  launchctl bootstrap "$DOMAIN" "$TARGET"
fi
launchctl kickstart "$DOMAIN/$LABEL"

# 从旧版全局 label 安全迁移：只清理由当前 BASE 创建的旧 plist，不碰其他安装。
LEGACY_LABEL="$(mn_legacy_menubar_label)"
LEGACY_TARGET="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
if [[ "$LABEL" != "$LEGACY_LABEL" && -f "$LEGACY_TARGET" ]] \
   && grep -Fq -- "$BASE" "$LEGACY_TARGET"; then
  launchctl bootout "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
  rm -f "$LEGACY_TARGET"
fi
mn_write_menubar_label "$BASE" "$LABEL"
print "已启用 MeetingNotes 菜单栏开机自启。"
