#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
mkdir -p "$project/inbox" "$project/logs" "$tmp/downloads"
cp "$ROOT/watch_downloads.sh" "$project/"

audio="$tmp/downloads/AirDrop sample.M4A"
print -n -- "audio-data" > "$audio"
MEETINGNOTES_STABILITY_INTERVAL=0 "$project/watch_downloads.sh" "$audio"
[[ ! -e "$audio" && -f "$project/inbox/AirDrop sample.M4A" ]] \
  || { echo "FAIL explicit audio ingest"; exit 1; }

document="$tmp/downloads/not-audio.txt"
print -n -- "text" > "$document"
MEETINGNOTES_STABILITY_INTERVAL=0 "$project/watch_downloads.sh" "$document"
[[ -f "$document" ]] || { echo "FAIL non-audio filtering"; exit 1; }

echo "PASS"
