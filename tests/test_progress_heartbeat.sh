#!/bin/zsh
# P2 回归：闷头跑数分钟的步骤（Python 依赖、菜单栏构建）必须有活体进度，
# 否则窗口定格像假死。mn_run_with_heartbeat 在后台跑命令、每隔一段发一条带
# 已用时长的进度，并如实返回命令退出码。
set -eu

ROOT="${0:A:h:h}"
source "$ROOT/scripts/installer_progress.sh"

# 行为一：慢命令期间应发出多条进度心跳（用快间隔把测试压到 ~1s）
out="$(MEETINGNOTES_PROGRESS_JSON=true MN_HEARTBEAT_SECS=0.2 \
  mn_run_with_heartbeat python 8 "准备运行环境" "正在安装处理依赖" -- sleep 0.7)"
ticks="$(print -r -- "$out" | grep -c '@@MEETINGNOTES@@')"
(( ticks >= 2 )) \
  || { echo "FAIL 心跳进度不足（$ticks 条），慢步骤仍会显得假死"; exit 1; }
print -r -- "$out" | grep -q '已用' \
  || { echo "FAIL 心跳详情未显示已用时长"; exit 1; }

# 行为一·补：传入 ETA 提示时，详情应是「已用 Xs · <ETA>」
out_eta="$(MEETINGNOTES_PROGRESS_JSON=true MN_HEARTBEAT_SECS=0.2 \
  mn_run_with_heartbeat python 8 "准备运行环境" "正在安装处理依赖" "预计还需约 1–3 分钟" -- sleep 0.5)"
print -r -- "$out_eta" | grep -q '已用' \
  || { echo "FAIL 带 ETA 时仍应显示已用时长"; exit 1; }
print -r -- "$out_eta" | grep -q '预计还需约 1–3 分钟' \
  || { echo "FAIL ETA 提示未出现在心跳详情里"; exit 1; }

# 行为二：如实返回被包裹命令的退出码（失败要能被 || fail 捕获）
rc=0
MEETINGNOTES_PROGRESS_JSON=true MN_HEARTBEAT_SECS=0.2 \
  mn_run_with_heartbeat python 8 t d -- sh -c 'exit 7' >/dev/null || rc=$?
(( rc == 7 )) \
  || { echo "FAIL 心跳包装器未透传命令退出码（得到 $rc，应为 7）"; exit 1; }

# 静态断言：bootstrap 的 Python 步必须走心跳包装，而不是裸 run_logged
# （调用跨行续写，用 -A1 把心跳调用及其被包裹命令一起看）
grep -A1 'mn_run_with_heartbeat python' "$ROOT/scripts/bootstrap_mac.sh" \
  | grep -Fq 'fetch_python.sh' \
  || { echo "FAIL Python 步未接入 mn_run_with_heartbeat"; exit 1; }
grep -A7 '^mn_run_with_heartbeat()' "$ROOT/scripts/installer_progress.sh" \
  | grep -Fq 'unsetopt BG_NICE' \
  || { echo "FAIL 心跳后台任务未关闭 zsh 自动 nice"; exit 1; }
grep -Fq 'unsetopt BG_NICE' "$ROOT/scripts/bootstrap_mac.sh" \
  || { echo "FAIL bootstrap 模型后台任务未关闭 zsh 自动 nice"; exit 1; }

echo PASS
