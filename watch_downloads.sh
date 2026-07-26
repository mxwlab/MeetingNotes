#!/bin/zsh
# launchd 在 ~/Downloads 变化时触发：把录音文件自动搬进 MeetingNotes/inbox，
# 由 inbox 的监听任务接手转录出纪要。这样 AirDrop 到 Mac 后就全自动了。
set -u
setopt NULL_GLOB

DOWNLOADS="$HOME/Downloads"
INBOX="$HOME/MeetingNotes/inbox"
LOGDIR="$HOME/MeetingNotes/logs"
LOG="$LOGDIR/downloads.log"
LOCK="$HOME/MeetingNotes/.dl.lock"

# 只搬这些扩展名的文件。想让其它格式也自动搬，往这里加，例如：(m4a mp3 wav)
EXTS=(m4a)

mkdir -p "$INBOX" "$LOGDIR"
log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# 防并发
if ! mkdir "$LOCK" 2>/dev/null; then exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

for ext in $EXTS; do
  for f in "$DOWNLOADS"/*.$ext "$DOWNLOADS"/*.${ext:u}; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"

    # 等文件写完（AirDrop/下载进行中）：大小连续两次不变才搬
    s1=$(stat -f%z "$f" 2>/dev/null)
    sleep 2
    s2=$(stat -f%z "$f" 2>/dev/null)
    if [ "$s1" != "$s2" ]; then
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
done
exit 0
