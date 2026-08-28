#!/bin/zsh
# 回归：锁语义 —— 持有进程还活着时新触发必须跳过（避免并发处理同一批文件）；
# 持有进程已退出（崩溃/被杀留下的残留锁）必须接管继续，否则文件会一直没人处理。
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
mkdir -p "$project/inbox" "$project/logs"
cp "$ROOT/watch_inbox.sh" "$project/"

# 场景一：残留锁（pid 指向已不存在的进程）→ 接管继续，锁被清理
print -n -- "x" > "$project/inbox/残留测试.m4a"
mkdir "$project/.watch.lock"
print -r -- "999999" > "$project/.watch.lock/pid"   # 该 PID 几乎必然不存在
zsh "$project/watch_inbox.sh" >/dev/null 2>&1 || true
grep -q "残留锁" "$project/logs/watch.log" \
  || { echo "FAIL: 未识别残留锁"; exit 1; }
[[ ! -e "$project/.watch.lock" ]] \
  || { echo "FAIL: 残留锁未被清理"; exit 1; }

# 场景二：持有进程还活着 → 跳过本次触发，完全不碰文件
rm -f "$project/logs/watch.log"
sleep 100 & holder=$!
mkdir "$project/.watch.lock"
print -r -- "$holder" > "$project/.watch.lock/pid"
zsh "$project/watch_inbox.sh" >/dev/null 2>&1 || true
kill "$holder" 2>/dev/null || true
grep -q "已有实例" "$project/logs/watch.log" \
  || { echo "FAIL: 未跳过仍在运行的实例"; exit 1; }
! grep -q "开始处理" "$project/logs/watch.log" \
  || { echo "FAIL: 并发实例仍尝试处理文件"; exit 1; }
[[ -e "$project/inbox/残留测试.m4a" ]] \
  || { echo "FAIL: 并发实例不应动 inbox 里的文件"; exit 1; }
[[ -d "$project/.watch.lock" ]] \
  || { echo "FAIL: 存活实例的锁被误删"; exit 1; }

echo "PASS"
