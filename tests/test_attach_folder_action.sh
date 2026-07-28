#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
fake_home="$tmp/home"
mkdir -p "$project/scripts" "$project/folder-action" "$fake_home/Downloads"
cp "$ROOT/scripts/attach_folder_action.sh" "$project/scripts/"
cp "$ROOT/folder-action/airdrop-to-inbox.applescript" "$project/folder-action/"
cp "$ROOT/folder-action/attach-folder-action.applescript" "$project/folder-action/"
cp "$ROOT/watch_downloads.sh" "$project/"

HOME="$fake_home" "$project/scripts/attach_folder_action.sh" --dry-run

compiled_dir="$fake_home/Library/Scripts/Folder Action Scripts"
compiled=("$compiled_dir"/MeetingNotes-*.scpt(N))
[[ ${#compiled} == 1 ]] || { echo "FAIL compiled script"; exit 1; }
[[ -f "$compiled[1]" ]] || { echo "FAIL missing compiled script"; exit 1; }

grep -q '0059' "$project/folder-action/airdrop-to-inbox.applescript" \
  || { echo "FAIL AirDrop quarantine check"; exit 1; }
osadecompile "$compiled[1]" | grep -q "$project/watch_downloads.sh" \
  || { echo "FAIL watcher path injection"; exit 1; }
osacompile -o "$tmp/attach.scpt" "$project/folder-action/attach-folder-action.applescript"

mkdir -p "$tmp/incoming"
airdrop_audio="$tmp/incoming/from-airdrop.m4a"
browser_audio="$tmp/incoming/from-browser.m4a"
print -n -- "airdrop-audio" > "$airdrop_audio"
print -n -- "browser-audio" > "$browser_audio"
xattr -w com.apple.quarantine '0059;test;MeetingNotes;' "$airdrop_audio"
xattr -w com.apple.quarantine '0083;test;MeetingNotes;' "$browser_audio"
MEETINGNOTES_STABILITY_INTERVAL=0 osascript "$compiled[1]" \
  "$airdrop_audio" "$browser_audio"
[[ -f "$project/inbox/from-airdrop.m4a" && ! -e "$airdrop_audio" ]] \
  || { echo "FAIL AirDrop ingest"; exit 1; }
[[ -f "$browser_audio" ]] \
  || { echo "FAIL non-AirDrop quarantine filtering"; exit 1; }

echo "PASS"
