#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
app="$tmp/MeetingNotes 安装器.app"
"$ROOT/scripts/build_installer_app.sh" "$app" >/dev/null
[[ -x "$app/Contents/MacOS/MeetingNotes Installer" ]] || { echo "FAIL executable"; exit 1; }
plutil -lint "$app/Contents/Info.plist" >/dev/null || { echo "FAIL plist"; exit 1; }
[[ -s "$app/Contents/Resources/MeetingNotes.icns" ]] || { echo "FAIL app icon"; exit 1; }
[[ "$(plutil -extract CFBundleIconFile raw "$app/Contents/Info.plist")" == MeetingNotes ]] \
  || { echo "FAIL icon plist"; exit 1; }
file "$app/Contents/MacOS/MeetingNotes Installer" | grep -q 'arm64' || { echo "FAIL arm64"; exit 1; }
strings "$app/Contents/MacOS/MeetingNotes Installer" | grep -q '@@MEETINGNOTES@@' || { echo "FAIL protocol"; exit 1; }
grep -Fq '请先填写 DeepSeek API Key' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL key validation"; exit 1; }
grep -Fq 'DeepSeek（推荐）' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL recommended provider"; exit 1; }
grep -Fq '其他 OpenAI 兼容服务' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL custom provider option"; exit 1; }
echo PASS
