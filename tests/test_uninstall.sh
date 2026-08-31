#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
home="$tmp/home"
mock_bin="$tmp/mock-bin"
mkdir -p "$project/folder-action" "$project/scripts" \
  "$home/Downloads" "$home/Desktop" "$mock_bin"
project="${project:A}"
cp "$ROOT/uninstall.sh" "$project/"
cp "$ROOT/scripts/menubar_identity.sh" "$project/scripts/"
cp "$ROOT/folder-action/detach-folder-action.applescript" "$project/folder-action/"

path_hash="$(printf '%s' "$project" | shasum | cut -c1-8)"
label="com.meetingnotes.$path_hash"
plist="$home/Library/LaunchAgents/$label.plist"
compiled="$home/Library/Scripts/Folder Action Scripts/MeetingNotes-$path_hash.scpt"
mkdir -p "${plist:h}" "${compiled:h}"
print -r -- "plist" > "$plist"
print -r -- "compiled" > "$compiled"
menubar_label="com.moxiuwen.meetingnotes.menubar.acceptance"
menubar_plist="$home/Library/LaunchAgents/$menubar_label.plist"
legacy_menubar_plist="$home/Library/LaunchAgents/com.moxiuwen.meetingnotes.menubar.plist"
print -r -- "$menubar_label" > "$project/.menubar_label"
print -r -- "$project" > "$menubar_plist"
print -r -- "$project" > "$legacy_menubar_plist"

for dir in inbox output done venv models tools runtime bin; do
  mkdir -p "$project/$dir"
  print -r -- "$dir" > "$project/$dir/keep.txt"
done
print -r -- "secret" > "$project/config.local.sh"
ln -s "$project/inbox" "$project/录音"
ln -s "$project/output" "$project/纪要"
ln -s "$project/录音" "$home/Desktop/MeetingNotes 录音"

cat > "$mock_bin/launchctl" <<EOF
#!/bin/zsh
print -r -- "\$*" >> "$tmp/launchctl.log"
exit 0
EOF
cat > "$mock_bin/osascript" <<EOF
#!/bin/zsh
print -r -- "\$*" >> "$tmp/osascript.log"
exit 0
EOF
chmod +x "$mock_bin"/*

HOME="$home" PATH="$mock_bin:/usr/bin:/bin" \
  "$project/uninstall.sh" --non-interactive

[[ ! -e "$plist" && ! -e "$compiled" ]] || { echo "FAIL service artifacts"; exit 1; }
[[ ! -e "$menubar_plist" && ! -e "$legacy_menubar_plist" && ! -e "$project/.menubar_label" ]] \
  || { echo "FAIL menu bar artifacts"; exit 1; }
grep -q "bootout" "$tmp/launchctl.log" || { echo "FAIL launchctl bootout"; exit 1; }
grep -Fq "$menubar_label" "$tmp/launchctl.log" \
  || { echo "FAIL did not boot out persisted menu bar label"; exit 1; }
grep -q "$home/Downloads" "$tmp/osascript.log" || { echo "FAIL Folder Action detach"; exit 1; }
for dir in inbox output done venv models tools runtime bin; do
  [[ -f "$project/$dir/keep.txt" ]] || { echo "FAIL preserved $dir"; exit 1; }
done
[[ -f "$project/config.local.sh" ]] || { echo "FAIL preserved config"; exit 1; }
[[ ! -e "$home/Desktop/MeetingNotes 录音" ]] || { echo "FAIL desktop entry"; exit 1; }
[[ -L "$project/录音" && -L "$project/纪要" ]] || { echo "FAIL visible links"; exit 1; }

# 同名但不是本安装创建的桌面入口不得误删。
ln -s "$tmp/not-meetingnotes" "$home/Desktop/MeetingNotes 录音"
HOME="$home" PATH="$mock_bin:/usr/bin:/bin" \
  "$project/uninstall.sh" --non-interactive --remove-runtime
[[ -L "$home/Desktop/MeetingNotes 录音" ]] || { echo "FAIL removed foreign desktop entry"; exit 1; }

for dir in venv models tools runtime bin; do
  [[ ! -e "$project/$dir" ]] || { echo "FAIL removed $dir"; exit 1; }
done
for dir in inbox output done; do
  [[ -f "$project/$dir/keep.txt" ]] || { echo "FAIL data after cleanup $dir"; exit 1; }
done

echo "PASS"
