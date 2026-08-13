#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
PYTHON="$BASE/venv/bin/python"
UI_PYTHON="$BASE/venv-ui/bin/python"

[[ -x "$PYTHON" ]] || {
  echo "主 Python 环境尚未准备好：$PYTHON" >&2
  exit 1
}

if [[ ! -x "$UI_PYTHON" ]]; then
  "$PYTHON" -m venv "$BASE/venv-ui"
fi

"$UI_PYTHON" -m pip install --disable-pip-version-check \
  -r "$BASE/requirements-ui.txt"

(
  cd "$BASE"
  "$UI_PYTHON" setup_ui.py py2app -A
)

[[ -x "$BASE/dist/MeetingNotes.app/Contents/MacOS/MeetingNotes" ]] || {
  echo "菜单栏 App 构建失败" >&2
  exit 1
}

"$BASE/scripts/install_menubar_autostart.sh"
