#!/bin/zsh
# 由 launchd 在 ~/MeetingNotes/inbox 有变化时触发，处理里面所有音频文件。
# 手动测试也可直接运行本脚本。
set -u
setopt NULL_GLOB

BASE="$(cd "$(dirname "$0")" && pwd)"   # 项目根 = 本脚本所在目录（随项目移动）
INBOX="$BASE/inbox"
LOGDIR="$BASE/logs"
PY="$BASE/venv/bin/python"
SCRIPT="$BASE/process.py"
LOG="$LOGDIR/watch.log"
LOCK="$BASE/.watch.lock"

mkdir -p "$LOGDIR"

# launchd 的默认 PATH 极简，找不到 brew 装的 ffmpeg，这里补上
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# 优先读项目内 config.local.sh；不存在则回退作者原有的 .zshrc 机制（保持向后兼容）
# >>> config-load
if [ -f "$BASE/config.local.sh" ]; then
  source "$BASE/config.local.sh"
else
  eval "$(grep '^export DEEPSEEK_API_KEY=' "$HOME/.zshrc" 2>/dev/null | head -1)" 2>/dev/null
fi
# <<< config-load

log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# 防并发：拿不到锁说明已有实例在跑。锁超过 2 小时视为残留，清掉。
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then
    log "发现残留锁(>2h)，清除后继续"
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || { log "无法获取锁，退出"; exit 0; }
  else
    log "已有实例在运行，跳过本次触发"
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

processed=0
for f in "$INBOX"/*.m4a "$INBOX"/*.mp3 "$INBOX"/*.wav "$INBOX"/*.mp4 \
         "$INBOX"/*.aac "$INBOX"/*.flac; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"

  # 等文件写完（AirDrop/拷贝进行中）：不能是空文件，且大小连续三次不变。
  # Finder/快捷指令有时会先创建同名的 0 字节占位文件，之后才写入实际内容。
  s1=$(stat -f%z "$f" 2>/dev/null)
  if [ -z "$s1" ] || [ "$s1" -eq 0 ]; then
    log "文件为空，等待写入完成: $base"
    continue
  fi
  sleep 2
  s2=$(stat -f%z "$f" 2>/dev/null)
  sleep 2
  s3=$(stat -f%z "$f" 2>/dev/null)
  if [ "$s1" != "$s2" ] || [ "$s2" != "$s3" ]; then
    log "文件仍在写入，本次跳过（写完后会再次触发）: $base"
    continue
  fi

  log "开始处理: $base"
  if "$PY" "$SCRIPT" "$f" >> "$LOG" 2>&1; then
    log "✅ 完成: $base"
    processed=$((processed+1))
  else
    rc=$?
    log "❌ 失败(退出码 $rc): $base — 详见上方日志（音频仍保留在 inbox）"
  fi
done

[ "$processed" -gt 0 ] && log "本次共处理 $processed 个文件"
exit 0
