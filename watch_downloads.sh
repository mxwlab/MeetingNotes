#!/bin/zsh
# launchd 在 ~/Downloads 变化时触发：把录音文件自动搬进 MeetingNotes/inbox，
# 由 inbox 的监听任务接手转录出纪要。这样 AirDrop 到 Mac 后就全自动了。
set -u
setopt NULL_GLOB

BASE="$(cd "$(dirname "$0")" && pwd)"   # 项目根 = 本脚本所在目录（随项目移动）
DOWNLOADS="$HOME/Downloads"
INBOX="$BASE/inbox"
LOGDIR="$BASE/logs"
LOG="$LOGDIR/downloads.log"
LOCK="$BASE/.dl.lock"

# 只搬这些扩展名的文件。想让其它格式也自动搬，往这里加，例如：(m4a mp3 wav)
EXTS=(m4a)
EXPLICIT_EXTS=(m4a mp3 wav mp4 aac flac)
STABILITY_INTERVAL="${MEETINGNOTES_STABILITY_INTERVAL:-2}"

mkdir -p "$INBOX" "$LOGDIR"
log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# 防并发
if ! mkdir "$LOCK" 2>/dev/null; then exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

files=()
if (( $# > 0 )); then
  files=("$@")
else
  for ext in $EXTS; do
    files+=("$DOWNLOADS"/*.$ext "$DOWNLOADS"/*.${ext:u})
  done
fi

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  if (( $# > 0 )) && (( ${EXPLICIT_EXTS[(Ie)${f:e:l}]} == 0 )); then
    log "忽略非音频文件: $(basename "$f")"
    continue
  fi
  base="$(basename "$f")"

  # 等文件写完（AirDrop/下载进行中）：不能是空文件，且大小连续三次不变。
  # Finder 可能先出现 0 字节占位文件；此时搬走会让 inbox 过早开始转录。
  s1=$(stat -f%z "$f" 2>/dev/null)
  if [ -z "$s1" ] || [ "$s1" -eq 0 ]; then
    log "文件为空，等待传输完成: $base"
    continue
  fi
  sleep "$STABILITY_INTERVAL"
  s2=$(stat -f%z "$f" 2>/dev/null)
  sleep "$STABILITY_INTERVAL"
  s3=$(stat -f%z "$f" 2>/dev/null)
  if [ "$s1" != "$s2" ] || [ "$s2" != "$s3" ]; then
    log "文件仍在传输，本次跳过（传完会再次触发）: $base"
    continue
  fi

  # inbox 已有同名文件则加时间戳前缀，避免覆盖
  dest="$INBOX/$base"
  [ -e "$dest" ] && dest="$INBOX/$(date +%H%M%S)_$base"

  if mv "$f" "$dest"; then
    log "搬入 inbox: $base"
  else
    log "搬运失败: $base"
  fi
done
exit 0
