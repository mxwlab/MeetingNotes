#!/bin/zsh

mn_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  print -r -- "$value"
}

mn_progress() {
  [[ "${MEETINGNOTES_PROGRESS_JSON:-false}" == true ]] || return 0
  local event="$1" id="$2" percent="$3" title="$4" detail="${5:-}"
  # 进度只是给 GUI 看的旁路。安装器窗口关闭/卡住导致读端断裂时，这条 printf 会
  # 写失败（EPIPE）。绝不能让它把返回码往上抛——否则调用方的 set -e 会因为一条
  # “报告进度”失败而中止整个安装（真实事故：模型步后 SIGPIPE 静默杀死 bootstrap，
  # 后台服务/菜单栏/AirDrop 全没装）。配合调用方 `trap '' PIPE` 忽略信号。
  printf '@@MEETINGNOTES@@{"event":"%s","id":"%s","percent":%d,"title":"%s","detail":"%s"}\n' \
    "$(mn_json_escape "$event")" "$(mn_json_escape "$id")" "$percent" \
    "$(mn_json_escape "$title")" "$(mn_json_escape "$detail")" 2>/dev/null || true
}

# 把一个耗时命令放后台跑，同时每隔 MN_HEARTBEAT_SECS 秒发一条带“已用时长”的进度，
# 让闷头跑数分钟的步骤（Python 依赖安装、菜单栏构建）在窗口里有活体反馈、不显假死。
# 如实返回被包裹命令的退出码，便于调用方 `|| fail`。用法：
#   mn_run_with_heartbeat <id> <percent> <title> <detail_prefix> -- cmd [args...]
mn_run_with_heartbeat() {
  local id="$1" percent="$2" title="$3" detail_prefix="$4"
  shift 4
  # 可选的 ETA 粗估提示（第 5 个位置参数，在 -- 之前）；不传则只显示已用时长
  local eta=""
  if [[ "${1:-}" != "--" ]]; then eta="$1"; shift; fi
  [[ "${1:-}" == "--" ]] && shift
  local interval="${MN_HEARTBEAT_SECS:-2}"
  local started elapsed pid rc=0 detail
  started="$(date +%s)"
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$(( $(date +%s) - started ))
    detail="$detail_prefix · 已用 ${elapsed}s"
    [[ -n "$eta" ]] && detail="$detail · $eta"
    mn_progress progress "$id" "$percent" "$title" "$detail"
    sleep "$interval"
  done
  wait "$pid" || rc=$?
  return "$rc"
}
