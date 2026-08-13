#!/bin/zsh
# 兼容入口：启动 py2app 构建的独立 macOS 菜单栏应用。
BASE="${0:A:h}"
open "$BASE/dist/MeetingNotes.app"
exit 0
