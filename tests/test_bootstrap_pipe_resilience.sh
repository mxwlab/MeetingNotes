#!/bin/zsh
# 集成回归：安装必须跑满全部 8 步，即使
#   (a) 安装器 GUI 的 stdout 读端中途断裂（P1：曾导致模型步后 SIGPIPE 静默中止）；
#   (b) 模型进度轮询首次 du 时模型目录还没建好（du 返回空 -> `$(( * 1024 ))` 数学报错中止）。
# 用打桩的置备脚本 + mock launchctl/plutil，全程无真实系统副作用。
set -eu

ROOT="${0:A:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pkg="$tmp/pkg"; home="$tmp/home"; calls="$tmp/calls.log"
mkdir -p "$pkg/scripts" "$pkg/inbox" "$pkg/output" "$pkg/done" "$pkg/logs" "$pkg/venv" \
  "$home/Library/LaunchAgents" "$home/Desktop" "$home/Applications"
cp "$ROOT/scripts/bootstrap_mac.sh" "$ROOT/scripts/installer_progress.sh" "$pkg/scripts/"
: > "$calls"

for h in fetch_python.sh fetch_ffmpeg.sh provision_menubar.sh; do
  printf '#!/bin/zsh\nprint -r -- "%s" >> "%s"\n' "$h" "$calls" > "$pkg/scripts/$h"
  chmod +x "$pkg/scripts/$h"
done
# provision_models：先睡再建模型目录，故意让进度轮询首次 du 时目录还不存在（触发 du 空值路径）
cat > "$pkg/scripts/provision_models.sh" <<EOF
#!/bin/zsh
sleep 0.5
mkdir -p "\$MEETINGNOTES_INSTALL_DIR/models/qwen3-asr-1.7b-8bit"
head -c 100000 /dev/zero > "\$MEETINGNOTES_INSTALL_DIR/models/qwen3-asr-1.7b-8bit/weight.bin"
print -r -- provision_models.sh >> "$calls"
EOF
chmod +x "$pkg/scripts/provision_models.sh"
printf '#!/bin/zsh\necho "<plist><dict></dict></plist>"\n' > "$pkg/scripts/gen_launchd.sh"
printf '#!/bin/zsh\nprint -r -- attach >> "%s"\n' "$calls" > "$pkg/scripts/attach_folder_action.sh"
chmod +x "$pkg/scripts/gen_launchd.sh" "$pkg/scripts/attach_folder_action.sh"

mkdir -p "$tmp/mockbin"
for m in launchctl plutil; do printf '#!/bin/zsh\nexit 0\n' > "$tmp/mockbin/$m"; chmod +x "$tmp/mockbin/$m"; done

# 关键：PROGRESS_JSON=true + stdout 读端只取 60 字节就关闭 = 复刻 GUI 读端断裂
PATH="$tmp/mockbin:/usr/bin:/bin" HOME="$home" \
  MEETINGNOTES_UNAME_M=arm64 MEETINGNOTES_UNAME_S=Darwin MEETINGNOTES_MACOS_MAJOR=15 \
  MEETINGNOTES_INSTALL_DIR="$home/MeetingNotes" \
  MEETINGNOTES_PROGRESS_JSON=true MEETINGNOTES_BOOTSTRAP_TEST_MODE=true DEEPSEEK_API_KEY=dummy \
  MN_HEARTBEAT_SECS=0.2 \
  zsh "$pkg/scripts/bootstrap_mac.sh" 2>&1 | head -c 60 >/dev/null || true
LOG="$home/MeetingNotes/logs/bootstrap.log"
[[ -f "$LOG" ]] || { echo "FAIL 没有安装日志"; exit 1; }
# bootstrap 在后台继续跑；模型轮询本身每 2 秒一次，固定 sleep 1 会随机器负载偶发抢跑。
# 最多等 10 秒看到第 8 步，仍保留“中途静默退出”回归能力。
for _ in {1..50}; do
  grep -q "STEP 8/8" "$LOG" && break
  sleep 0.2
done
for n in 6 7 8; do
  grep -q "STEP $n/8" "$LOG" \
    || { echo "FAIL 管道断裂/du 空值下未跑到 STEP $n（安装中途静默中止）"; cat "$LOG"; exit 1; }
done
grep -q provision_menubar.sh "$calls" || { echo "FAIL 菜单栏步未执行"; exit 1; }
grep -q attach "$calls" || { echo "FAIL AirDrop 步未执行"; exit 1; }

echo PASS
