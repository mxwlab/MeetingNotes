#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
source "$BASE/scripts/menubar_identity.sh"
PYTHON="$BASE/venv/bin/python"
UI_PYTHON="$BASE/venv-ui/bin/python"
MENUBAR_LABEL="$(mn_menubar_label "$BASE")"
MENUBAR_BUNDLE_ID="$(mn_menubar_bundle_id "$MENUBAR_LABEL")"

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
  MEETINGNOTES_MENUBAR_BUNDLE_ID="$MENUBAR_BUNDLE_ID" \
    "$UI_PYTHON" setup_ui.py py2app -A --dist-dir "$BASE/dist-menubar"
  "$BASE/scripts/build_main_app.sh" "$BASE/dist/MeetingNotes.app"
  "$BASE/scripts/build_pet_app.sh" "$BASE/dist/MeetingNotesPet.app"
)

[[ -x "$BASE/dist-menubar/MeetingNotes 菜单栏.app/Contents/MacOS/MeetingNotes 菜单栏" ]] || {
  echo "菜单栏 App 构建失败" >&2
  exit 1
}
[[ -x "$BASE/dist/MeetingNotes.app/Contents/MacOS/MeetingNotes" ]] || {
  echo "主界面 App 构建失败" >&2
  exit 1
}
[[ -x "$BASE/dist/MeetingNotesPet.app/Contents/MacOS/MeetingNotesPet" ]] || {
  echo "桌面进度小猫 App 构建失败" >&2
  exit 1
}

APPLICATIONS="$HOME/Applications"
mkdir -p "$APPLICATIONS"
rm -rf "$APPLICATIONS/MeetingNotes.app"
cp -R "$BASE/dist/MeetingNotes.app" "$APPLICATIONS/MeetingNotes.app"
mkdir -p "$HOME/Library/Application Support/MeetingNotes"
print -r -- "$BASE" > "$HOME/Library/Application Support/MeetingNotes/base"

"$BASE/scripts/install_menubar_autostart.sh"
