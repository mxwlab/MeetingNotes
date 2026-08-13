#!/bin/zsh
# 双击启动 MeetingNotes 菜单栏 app（状态/服务设置/失败提醒）。
BASE="${0:A:h}"
exec "$BASE/venv-ui/bin/python" "$BASE/ui/menubar.py"
