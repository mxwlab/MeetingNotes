#!/bin/zsh
# 回归：文件传输工具（微信/QQ）常先落一个 0 字节占位文件，随后才把内容写满。
# 监听器必须就地轮询等到文件稳定再搬，而不是看到 0 字节/仍在增长就跳过——
# 大文件在原地被填满往往不产生新的目录事件，跳过会让文件石沉大海。
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
mkdir -p "$project/inbox" "$project/logs" "$tmp/downloads"
cp "$ROOT/watch_downloads.sh" "$project/"

# 场景一：先 0 字节占位，几秒后才写满 —— 单次触发必须等到写完再搬。
# 延迟给足，确保脚本第一次 stat 一定读到 0 字节（复现上报的真实场景）。
audio="$tmp/downloads/权限讨论.m4a"
: > "$audio"                                   # 0 字节占位
( sleep 3; print -n -- "the-real-audio-bytes" > "$audio" ) &
writer=$!
MEETINGNOTES_STABILITY_INTERVAL=1 MEETINGNOTES_STABLE_CHECKS=2 \
  "$project/watch_downloads.sh" "$audio"
wait "$writer"
[[ ! -e "$audio" && -f "$project/inbox/权限讨论.m4a" ]] \
  || { echo "FAIL: 0 字节占位后写满的文件未被搬入 inbox"; exit 1; }
[[ "$(cat "$project/inbox/权限讨论.m4a")" == "the-real-audio-bytes" ]] \
  || { echo "FAIL: 搬入的文件内容不完整（过早搬走）"; exit 1; }

# 场景二：分块持续写入，稳定后才搬 —— 不能在增长途中搬走半截文件。
growing="$tmp/downloads/growing.m4a"
: > "$growing"
( sleep 1; print -n -- "chunk-one" > "$growing"
  sleep 1; print -n -- "chunk-one-and-chunk-two-final" > "$growing" ) &
writer=$!
MEETINGNOTES_STABILITY_INTERVAL=1 MEETINGNOTES_STABLE_CHECKS=2 \
  "$project/watch_downloads.sh" "$growing"
wait "$writer"
[[ -f "$project/inbox/growing.m4a" \
   && "$(cat "$project/inbox/growing.m4a")" == "chunk-one-and-chunk-two-final" ]] \
  || { echo "FAIL: 持续写入的文件未在稳定后完整搬入"; exit 1; }

echo "PASS"
