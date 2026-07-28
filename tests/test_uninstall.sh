#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
home="$tmp/home"
mock_bin="$tmp/mock-bin"
mkdir -p "$project/folder-action" "$home/Downloads" "$mock_bin"
project="${project:A}"
cp "$ROOT/uninstall.sh" "$project/"
cp "$ROOT/folder-action/detach-folder-action.applescript" "$project/folder-action/"

path_hash="$(printf '%s' "$project" | shasum | cut -c1-8)"
label="com.meetingnotes.$path_hash"
plist="$home/Library/LaunchAgents/$label.plist"
compiled="$home/Library/Scripts/Folder Action Scripts/MeetingNotes-$path_hash.scpt"
mkdir -p "${plist:h}" "${compiled:h}"
print -r -- "plist" > "$plist"
print -r -- "compiled" > "$compiled"

for dir in inbox output done venv models tools; do
  mkdir -p "$project/$dir"
  print -r -- "$dir" > "$project/$dir/keep.txt"
done
print -r -- "secret" > "$project/config.local.sh"

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
grep -q "bootout" "$tmp/launchctl.log" || { echo "FAIL launchctl bootout"; exit 1; }
grep -q "$home/Downloads" "$tmp/osascript.log" || { echo "FAIL Folder Action detach"; exit 1; }
for dir in inbox output done venv models tools; do
  [[ -f "$project/$dir/keep.txt" ]] || { echo "FAIL preserved $dir"; exit 1; }
done
[[ -f "$project/config.local.sh" ]] || { echo "FAIL preserved config"; exit 1; }

HOME="$home" PATH="$mock_bin:/usr/bin:/bin" \
  "$project/uninstall.sh" --non-interactive --remove-runtime

for dir in venv models tools; do
  [[ ! -e "$project/$dir" ]] || { echo "FAIL removed $dir"; exit 1; }
done
for dir in inbox output done; do
  [[ -f "$project/$dir/keep.txt" ]] || { echo "FAIL data after cleanup $dir"; exit 1; }
done

echo "PASS"
