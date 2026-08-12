#!/bin/zsh
# launchd 在 ~/Downloads 变化时触发：把录音文件自动搬进 MeetingNotes/inbox，
# 由 inbox 的监听任务接手转录出纪要。这样 AirDrop 到 Mac 后就全自动了。
set -u
setopt NULL_GLOB

BASE="$(cd "$(dirname "$0")" && pwd)"   # 项目根 = 本脚本所在目录（随项目移动）
DOWNLOADS="$HOME/Downloads"
if [[ -d "$BASE/录音" ]]; then
  INBOX="$BASE/录音"
else
  INBOX="$BASE/inbox"
fi
LOGDIR="$BASE/logs"
LOG="$LOGDIR/downloads.log"
LOCK="$BASE/.dl.lock"

# 只搬这些扩展名的文件。想让其它格式也自动搬，往这里加，例如：(m4a mp3 wav)
EXTS=(m4a)
EXPLICIT_EXTS=(m4a mp3 wav mp4 aac flac)
STABILITY_INTERVAL="${MEETINGNOTES_STABILITY_INTERVAL:-2}"  # 每次探测间隔(秒)
STABLE_CHECKS="${MEETINGNOTES_STABLE_CHECKS:-3}"            # 大小需连续几次不变才算稳定
MAX_WAIT="${MEETINGNOTES_MAX_WAIT:-600}"                    # 单个文件最多等多久(秒)

mkdir -p "$INBOX" "$LOGDIR"
log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# 就地轮询等文件传输完成：非空且大小连续 STABLE_CHECKS 次不变才算稳定。
# 关键：不再看到 0 字节/仍在增长就跳过、指望 launchd 再次触发——大文件在原地被
# 填满往往不产生新的目录事件，跳过会让文件石沉大海（issue: 传完却不处理）。
# 稳定返回 0；文件消失或超过 MAX_WAIT 仍未稳定返回 1。
wait_until_stable() {
  local f="$1" last=-1 size stable=0 waited=0 step="$STABILITY_INTERVAL"
  [ "$step" -le 0 ] && step=1   # 保证计时推进，避免 interval=0 时死循环
  while true; do
    size=$(stat -f%z "$f" 2>/dev/null)
    [ -z "$size" ] && return 1   # 文件被移走/删除
    if [ "$size" -gt 0 ] && [ "$size" -eq "$last" ]; then
      stable=$((stable + 1))
      (( stable >= STABLE_CHECKS - 1 )) && return 0
    else
      stable=0
    fi
    last="$size"
    (( waited >= MAX_WAIT )) && return 1
    sleep "$STABILITY_INTERVAL"
    waited=$((waited + step))
  done
}

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

  # 等文件写完（AirDrop/微信/QQ 传输进行中）：Finder 可能先出现 0 字节占位文件，
  # 内容随后在原地写满。就地轮询等到稳定再搬，单次触发即可兜住整个传输过程。
  if ! wait_until_stable "$f"; then
    [ -f "$f" ] && log "等待传输超时($MAX_WAIT 秒)，本次跳过: $base"
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
