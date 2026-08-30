#!/bin/zsh
set -eu

ROOT="${0:A:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/中文 项目/MeetingNotes"
home="$tmp/测试 用户"
calls="$tmp/launchctl.calls"
mkdir -p "$project/scripts" "$project/launchd" "$project/ui" \
  "$project/venv/bin" "$home/Library/LaunchAgents" "$tmp/mock-bin"

cp "$ROOT/scripts/provision_menubar.sh" "$project/scripts/"
cp "$ROOT/scripts/install_menubar_autostart.sh" "$project/scripts/"
cp "$ROOT/launchd/com.moxiuwen.meetingnotes.menubar.plist.template" "$project/launchd/"
cp "$ROOT/setup_ui.py" "$ROOT/requirements-ui.txt" "$project/"
mkdir -p "$project/assets"
cp "$ROOT/assets/MeetingNotes.icns" "$project/assets/"
mkdir -p "$project/installer"
cp "$ROOT/installer/MeetingNotesInstaller.m" "$ROOT/installer/MeetingNotesPet.m" "$project/installer/"
cp "$ROOT/scripts/build_main_app.sh" "$ROOT/scripts/build_pet_app.sh" "$project/scripts/"
cp "$ROOT/ui/"*.py "$project/ui/"
ln -s "$ROOT/venv/bin/python" "$project/venv/bin/python"
ln -s "$ROOT/venv-ui" "$project/venv-ui"

cat > "$tmp/mock-bin/launchctl" <<'EOF'
#!/bin/zsh
print -r -- "$*" >> "${MEETINGNOTES_TEST_CALLS:?}"
if [[ "$1" == bootstrap && ! -e "${MEETINGNOTES_TEST_BOOTSTRAP_ONCE:?}" ]]; then
  : > "$MEETINGNOTES_TEST_BOOTSTRAP_ONCE"
  exit 1
fi
exit 0
EOF
chmod +x "$tmp/mock-bin/launchctl"

PATH="$tmp/mock-bin:/usr/bin:/bin" HOME="$home" \
MEETINGNOTES_TEST_CALLS="$calls" MEETINGNOTES_TEST_BOOTSTRAP_ONCE="$tmp/once" \
  "$project/scripts/provision_menubar.sh" >/dev/null

app="$project/dist-menubar/MeetingNotes 菜单栏.app/Contents/MacOS/MeetingNotes 菜单栏"
plist="$home/Library/LaunchAgents/com.moxiuwen.meetingnotes.menubar.plist"
[[ -x "$app" ]] || { echo "FAIL app missing"; exit 1; }
[[ -x "$project/dist/MeetingNotes.app/Contents/MacOS/MeetingNotes" ]] || { echo "FAIL main app missing"; exit 1; }
[[ -x "$project/dist/MeetingNotesPet.app/Contents/MacOS/MeetingNotesPet" ]] || { echo "FAIL pet app missing"; exit 1; }
# 小猫只在终态可点击关闭，处理中点击不误关
grep -Fq 'if(self.closable) [NSApp terminate:nil]' "$ROOT/installer/MeetingNotesPet.m" || { echo "FAIL pet must only close when closable"; exit 1; }
[[ -f "$home/Applications/MeetingNotes.app/Contents/Resources/MeetingNotes.icns" ]] || { echo "FAIL installed app icon missing"; exit 1; }
[[ ! -L "$home/Applications/MeetingNotes.app/Contents/Resources/MeetingNotes.icns" ]] || { echo "FAIL installed app icon is symlink"; exit 1; }
grep -Fqx "${project:A}" "$home/Library/Application Support/MeetingNotes/base" || { echo "FAIL app base marker"; exit 1; }
plutil -lint "$plist" >/dev/null || { echo "FAIL plist invalid"; exit 1; }
grep -Fq "$project/dist-menubar/MeetingNotes 菜单栏.app/Contents/MacOS/MeetingNotes 菜单栏" "$plist" \
  || { echo "FAIL app path"; exit 1; }
grep -Fq "<string>${project:A}</string>" "$plist" || { echo "FAIL base path"; exit 1; }
grep -Fq '<string>com.moxiuwen.meetingnotes.menubar</string>' "$plist" \
  || { echo "FAIL default label"; exit 1; }
! grep -Fq '/Users/moxiuwen/workspace/MeetingNotes' "$plist" \
  || { echo "FAIL hard-coded developer path"; exit 1; }
[[ "$(grep -c '^bootstrap ' "$calls")" == 2 ]] \
  || { echo "FAIL bootstrap retry"; exit 1; }

PATH="$tmp/mock-bin:/usr/bin:/bin" HOME="$home" \
MEETINGNOTES_TEST_CALLS="$calls" MEETINGNOTES_TEST_BOOTSTRAP_ONCE="$tmp/once" \
  "$project/scripts/provision_menubar.sh" >/dev/null
[[ -x "$app" ]] || { echo "FAIL app missing after rerun"; exit 1; }
[[ "$(grep -c '^bootstrap ' "$calls")" == 3 ]] \
  || { echo "FAIL idempotent reload"; exit 1; }

isolated_label="com.moxiuwen.meetingnotes.menubar.acceptance"
PATH="$tmp/mock-bin:/usr/bin:/bin" HOME="$home" \
MEETINGNOTES_MENUBAR_LABEL="$isolated_label" \
MEETINGNOTES_TEST_CALLS="$calls" MEETINGNOTES_TEST_BOOTSTRAP_ONCE="$tmp/once" \
  "$project/scripts/install_menubar_autostart.sh" >/dev/null
isolated_plist="$home/Library/LaunchAgents/$isolated_label.plist"
[[ -f "$isolated_plist" ]] || { echo "FAIL isolated plist missing"; exit 1; }
grep -Fq "<string>$isolated_label</string>" "$isolated_plist" \
  || { echo "FAIL isolated label"; exit 1; }

echo PASS
