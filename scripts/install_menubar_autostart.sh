#!/bin/zsh
set -euo pipefail

BASE="${0:A:h:h}"
SOURCE="$BASE/launchd/com.moxiuwen.meetingnotes.menubar.plist.template"
TARGET="$HOME/Library/LaunchAgents/com.moxiuwen.meetingnotes.menubar.plist"
APP_EXECUTABLE="$BASE/dist/MeetingNotes.app/Contents/MacOS/MeetingNotes"
LOG_DIR="$BASE/logs"
DOMAIN="gui/$(id -u)"
LABEL="com.moxiuwen.meetingnotes.menubar"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  print -u2 "未找到菜单栏 App，请先运行：./venv-ui/bin/python setup_ui.py py2app -A"
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"
sed \
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
print "已启用 MeetingNotes 菜单栏开机自启。"
