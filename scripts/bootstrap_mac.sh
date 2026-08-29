#!/bin/zsh
set -eu

SOURCE_BASE="${0:A:h:h}"
source "$SOURCE_BASE/scripts/installer_progress.sh"

# 安装进度/信息都写到安装器 GUI 的 stdout 管道。窗口关闭或卡死导致读端断裂时，任何一次
# echo/printf 都会因 SIGPIPE 或 set -e 把安装静默中止（真实事故：模型步后进程消失，
# 后台服务/菜单栏/AirDrop 全没装）。安装本身绝不能被“报告进度失败”打断，两层防护：
#   1) trap '' PIPE：不让 SIGPIPE 杀进程；
#   2) GUI 模式把 stdout 接到一个“只读不断”的转发器：它持续读走本进程所有输出并尽力转发
#      给窗口，自身也忽略 SIGPIPE，下游断了就丢弃——于是 bootstrap 侧 stdout 永不破裂。
trap '' PIPE
if [[ "${MEETINGNOTES_PROGRESS_JSON:-false}" == true \
   && "${MEETINGNOTES_STDOUT_DRAINED:-false}" != true ]]; then
  exec > >(trap '' PIPE; while IFS= read -r __mn_line; do
    print -r -- "$__mn_line" 2>/dev/null || true
  done)
  export MEETINGNOTES_STDOUT_DRAINED=true
fi
INSTALL_DIR="${MEETINGNOTES_INSTALL_DIR:-$HOME/MeetingNotes}"
os_name="${MEETINGNOTES_UNAME_S:-$(uname -s)}"
arch="${MEETINGNOTES_UNAME_M:-$(uname -m)}"

fail_early() {
  echo
  echo "安装没有完成：$1" >&2
  echo "修复后重新双击“开始使用.command”即可继续。" >&2
  mn_progress error preflight 0 "无法开始安装" "$1"
  exit 1
}

[[ "$os_name" == "Darwin" ]] || fail_early "目前只支持 Mac"
[[ "$arch" == "arm64" ]] || fail_early "目前只支持 Apple Silicon（M1/M2/M3/M4/M5）Mac"

macos_major="${MEETINGNOTES_MACOS_MAJOR:-$(sw_vers -productVersion | cut -d. -f1)}"
(( macos_major >= 14 )) || fail_early "需要 macOS 14 或更高版本"

settle_project() {
  local source_dir="$1"
  local target_dir="$2"
  local target_parent="${target_dir:h}"
  local staging
  local -a excludes
  excludes=(
    --exclude .git --exclude .DS_Store --exclude .claude --exclude __pycache__
    --exclude config.local.sh --exclude .pet_state
    --exclude inbox --exclude output --exclude done --exclude logs
    --exclude 录音 --exclude 纪要
    --exclude models --exclude runtime --exclude venv --exclude venv-ui
    --exclude tools --exclude build --exclude dist
  )

  command -v rsync >/dev/null || fail_early "系统缺少 rsync，无法安顿程序文件"
  mkdir -p "$target_parent"
  staging="$(mktemp -d "$target_parent/.MeetingNotes-stage.XXXXXX")"
  trap 'rm -rf "$staging"' EXIT
  rsync -a "${excludes[@]}" "$source_dir/" "$staging/" \
    || fail_early "复制程序文件失败"

  if [[ -e "$target_dir" ]]; then
    rsync -a "$staging/" "$target_dir/" || fail_early "更新程序文件失败"
  else
    mv "$staging" "$target_dir" || fail_early "无法安顿到 $target_dir"
    staging=""
  fi
  [[ -z "$staging" ]] || rm -rf "$staging"
  trap - EXIT
}

if [[ "${MEETINGNOTES_BOOTSTRAP_SETTLED:-false}" != true ]] \
  && [[ "${SOURCE_BASE:A}" != "${INSTALL_DIR:A}" ]]; then
  echo "正在把 MeetingNotes 安顿到固定位置…"
  settle_project "$SOURCE_BASE" "$INSTALL_DIR"
  export MEETINGNOTES_BOOTSTRAP_SETTLED=true
  exec "$INSTALL_DIR/scripts/bootstrap_mac.sh"
fi

BASE="${INSTALL_DIR:A}"
[[ "${SOURCE_BASE:A}" == "$BASE" ]] || fail_early "程序安顿后路径异常"
LOG_DIR="$BASE/logs"
LOG="$LOG_DIR/bootstrap.log"
mkdir -p "$LOG_DIR" "$BASE/inbox" "$BASE/output" "$BASE/done"
touch "$LOG"

ensure_symlink() {
  local link_path="$1"
  local target_path="$2"
  local label="$3"
  if [[ -L "$link_path" ]]; then
    [[ "$(readlink "$link_path")" == "$target_path" ]] \
      || fail_early "$label 已存在，但指向了其他位置：$link_path"
  elif [[ -e "$link_path" ]]; then
    fail_early "$label 已存在且不是 MeetingNotes 创建的入口：$link_path"
  else
    ln -s "$target_path" "$link_path" \
      || fail_early "无法创建 $label：$link_path"
  fi
}

ensure_symlink "$BASE/录音" "$BASE/inbox" "录音文件夹"
ensure_symlink "$BASE/纪要" "$BASE/output" "纪要文件夹"
mkdir -p "$HOME/Desktop"
ensure_symlink "$HOME/Desktop/MeetingNotes 录音" "$BASE/录音" "桌面录音入口"

step_number=0
total_steps=8
step() {
  step_number=$((step_number + 1))
  echo
  echo "[$step_number/$total_steps] $1"
  print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] STEP $step_number/$total_steps $1" >> "$LOG"
}

fail() {
  local message="$1"
  print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR $message" >> "$LOG"
  echo
  echo "安装没有完成：$message" >&2
  echo "重新双击即可从已完成的位置继续。" >&2
  echo "详细日志：$LOG" >&2
  mn_progress error install 0 "安装没有完成" "$message"
  exit 1
}

run_logged() {
  "$@" >> "$LOG" 2>&1
}

run_model_with_progress() {
  if [[ "${MEETINGNOTES_PROGRESS_JSON:-false}" != true ]]; then
    run_logged "$BASE/scripts/provision_models.sh"
    return
  fi

  local expected_bytes="${QWEN_EXPECTED_BYTES:-2362232012}"
  local model_dir="$BASE/models/qwen3-asr-1.7b-8bit"
  local started now elapsed downloaded downloaded_kb rate remaining percent detail pid rc
  started="$(date +%s)"
  run_logged "$BASE/scripts/provision_models.sh" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    # 模型目录可能还没被 provision_models 建好，du 返回空。必须兜底为 0，否则
    # `$(( 空 * 1024 ))` 会“bad math expression”在 set -e 下中止整个安装（第三类静默中止）。
    downloaded_kb="$(du -sk "$model_dir" 2>/dev/null | awk '{print $1}')"
    downloaded=$(( ${downloaded_kb:-0} * 1024 ))
    (( downloaded > expected_bytes )) && downloaded="$expected_bytes"
    percent=$((39 + downloaded * 47 / expected_bytes))
    now="$(date +%s)"; elapsed=$((now - started))
    detail="已下载 $((downloaded / 1024 / 1024)) MB / 约 2.2 GB"
    if (( elapsed >= 5 && downloaded > 0 )); then
      rate=$((downloaded / elapsed))
      if (( rate > 0 )); then
        remaining=$(((expected_bytes - downloaded) / rate / 60 + 1))
        detail="$detail · 预计还需约 ${remaining} 分钟"
      fi
    fi
    mn_progress progress model "$percent" "正在下载本机语音模型" "$detail"
    sleep 2
  done
  wait "$pid" || rc=$?
  return "${rc:-0}"
}

validate_deepseek_key() {
  local key="$1"
  if [[ "${MEETINGNOTES_BOOTSTRAP_TEST_MODE:-false}" == true ]]; then
    [[ -n "$key" ]]
    return
  fi

  local response_file http_code
  response_file="$(mktemp "$LOG_DIR/.key-check.XXXXXX")"
  http_code="$(curl --silent --show-error --connect-timeout 15 --max-time 30 \
    -o "$response_file" -w '%{http_code}' \
    -H "Authorization: Bearer $key" \
    https://api.deepseek.com/models 2>/dev/null)" || {
      rm -f "$response_file"
      VALIDATION_MESSAGE="无法连接 DeepSeek，请检查网络"
      return 1
    }
  rm -f "$response_file"
  case "$http_code" in
    200) return 0 ;;
    401|403) VALIDATION_MESSAGE="API Key 无效，请重新复制"; return 1 ;;
    402) VALIDATION_MESSAGE="API Key 有效，但账户余额不足，请充值后重试"; return 1 ;;
    429) VALIDATION_MESSAGE="DeepSeek 请求过于频繁，请稍等片刻再试"; return 1 ;;
    *) VALIDATION_MESSAGE="DeepSeek 暂时返回错误（HTTP $http_code），请稍后重试"; return 1 ;;
  esac
}

validate_custom_provider() {
  local base_url="$1" model="$2" key="$3" response_file http_code endpoint
  [[ -n "$base_url" && -n "$model" && -n "$key" ]] || { VALIDATION_MESSAGE="服务设置不完整"; return 1; }
  [[ "$base_url" == https://* ]] || { VALIDATION_MESSAGE="服务地址必须以 https:// 开头"; return 1; }
  [[ "$base_url$model" != *['"\\'$'\n'$'\r']* ]] || { VALIDATION_MESSAGE="服务地址或模型名称包含无效字符"; return 1; }
  endpoint="${base_url%/}/chat/completions"
  response_file="$(mktemp "$LOG_DIR/.provider-check.XXXXXX")"
  http_code="$(curl --silent --show-error --connect-timeout 15 --max-time 45 \
    -o "$response_file" -w '%{http_code}' -H "Authorization: Bearer $key" \
    -H 'Content-Type: application/json' \
    --data "{\"model\":\"$model\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" \
    "$endpoint" 2>/dev/null)" || { rm -f "$response_file"; VALIDATION_MESSAGE="无法连接该 AI 服务，请检查地址和网络"; return 1; }
  rm -f "$response_file"
  [[ "$http_code" == 2* ]] || { VALIDATION_MESSAGE="AI 服务验证未通过（HTTP $http_code）"; return 1; }
}

write_config() {
  local key="$1"
  local config="$BASE/config.local.sh"
  local config_tmp="$config.tmp.$$"
  umask 077
  {
    printf 'export DEEPSEEK_API_KEY=%q\n' "$key"
    if [[ -n "${MEETINGNOTES_INSTALLER_BASE_URL:-}" ]]; then
      printf 'export LLM_BASE_URL=%q\n' "$MEETINGNOTES_INSTALLER_BASE_URL"
      printf 'export LLM_MODEL=%q\n' "$MEETINGNOTES_INSTALLER_MODEL"
    fi
    printf 'export OBSIDIAN_DIR=%q\n' ""
  } > "$config_tmp"
  chmod 600 "$config_tmp"
  mv "$config_tmp" "$config"
}

step "确认安装位置"
mn_progress step_start preflight 2 "检查这台 Mac" "确认系统、芯片和安装位置"
echo "程序位置：$BASE"
mn_progress step_done preflight 3 "这台 Mac 可以安装" "检查完成"

step "设置 DeepSeek"
mn_progress step_start provider 4 "连接 AI 服务" "验证并安全保存设置"
if [[ -f "$BASE/config.local.sh" ]]; then
  chmod 600 "$BASE/config.local.sh"
  echo "已有设置，安全保留"
else
  key=""
  if [[ -n "${MEETINGNOTES_INSTALLER_KEY:-}" ]]; then
    key="$MEETINGNOTES_INSTALLER_KEY"
    if [[ -n "${MEETINGNOTES_INSTALLER_BASE_URL:-}" ]]; then
      validate_custom_provider "$MEETINGNOTES_INSTALLER_BASE_URL" "$MEETINGNOTES_INSTALLER_MODEL" "$key" || fail "$VALIDATION_MESSAGE"
    else
      validate_deepseek_key "$key" || fail "$VALIDATION_MESSAGE"
    fi
  elif [[ "${MEETINGNOTES_BOOTSTRAP_TEST_MODE:-false}" == true ]]; then
    key="${DEEPSEEK_API_KEY:-}"
    [[ -n "$key" ]] || fail "测试模式缺少 DEEPSEEK_API_KEY"
    validate_deepseek_key "$key" || fail "测试 key 验证失败"
  else
    open "https://platform.deepseek.com/api_keys" >/dev/null 2>&1 || true
    prompt_message=""
    while true; do
      if [[ -n "$prompt_message" ]]; then
        key="$(osascript "$BASE/scripts/prompt_deepseek_key.applescript" "$prompt_message" 2>/dev/null)" \
          || fail "你取消了 API Key 设置"
      else
        key="$(osascript "$BASE/scripts/prompt_deepseek_key.applescript" 2>/dev/null)" \
          || fail "你取消了 API Key 设置"
      fi
      if validate_deepseek_key "$key"; then
        break
      fi
      prompt_message="$VALIDATION_MESSAGE"
    done
  fi
  write_config "$key"
  unset key
  unset MEETINGNOTES_INSTALLER_KEY
  unset MEETINGNOTES_INSTALLER_BASE_URL MEETINGNOTES_INSTALLER_MODEL
  echo "DeepSeek 设置验证通过"
fi
mn_progress step_done provider 7 "AI 服务已连接" "设置只保存在这台 Mac"

step "准备 Python"
mn_progress step_start python 8 "准备运行环境" "首次安装通常需要 1–3 分钟"
# 下 Python + pip 装 torch/mlx 等重依赖要跑几分钟；用心跳包装让窗口持续显示已用时长，
# 否则进度条会定格在 8% 像假死（run_logged 把细节写日志，不往 GUI 发事件）。
mn_run_with_heartbeat python 8 "准备运行环境" "正在下载并安装处理依赖" "预计还需约 1–3 分钟" \
  -- run_logged "$BASE/scripts/fetch_python.sh" || fail "Python 运行环境准备失败"
mn_progress step_done python 32 "运行环境已准备好" "Python 与处理依赖安装完成"
export MEETINGNOTES_PYTHON="$BASE/venv/bin/python"

step "准备音频工具"
mn_progress step_start ffmpeg 33 "安装音频工具" "用于读取常见录音和视频格式"
run_logged "$BASE/scripts/fetch_ffmpeg.sh" || fail "ffmpeg 准备失败"
mn_progress step_done ffmpeg 38 "音频工具已安装" "常见音视频格式已支持"

step "下载语音模型"
mn_progress step_start model 39 "下载本机语音模型" "约 2.2 GB，通常需要 2–8 分钟"
run_model_with_progress || fail "语音模型准备失败"
mn_progress step_done model 86 "语音模型已准备好" "录音会在本机完成识别"

step "启动后台服务"
mn_progress step_start service 87 "启动后台服务" "以后拖入录音即可自动处理"
path_hash="$(printf '%s' "$BASE" | shasum | cut -c1-8)"
label="com.meetingnotes.$path_hash"
launch_agents="$HOME/Library/LaunchAgents"
plist="$launch_agents/$label.plist"
mkdir -p "$launch_agents"
"$BASE/scripts/gen_launchd.sh" "$BASE" > "$plist" 2>> "$LOG" \
  || fail "生成后台服务配置失败"
plutil -lint "$plist" >> "$LOG" 2>&1 || fail "后台服务配置无效"
launchctl bootout "gui/$(id -u)" "$plist" >> "$LOG" 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$plist" >> "$LOG" 2>&1 \
  || fail "启动后台服务失败"
mn_progress step_done service 91 "后台服务已启动" "正在等待新录音"

step "安装菜单栏"
mn_progress step_start menubar 92 "安装菜单栏小猫" "用于显示转录进度和完成提醒"
# 构建菜单栏 App（py2app）也要一两分钟，同样用心跳避免窗口假死。
mn_run_with_heartbeat menubar 92 "安装菜单栏小猫" "正在构建菜单栏 App" "预计约 1–2 分钟" \
  -- run_logged "$BASE/scripts/provision_menubar.sh" \
  || fail "菜单栏 App 安装失败"
mn_progress step_done menubar 98 "菜单栏小猫已启动" "以后登录时会自动出现"

step "启用 AirDrop 自动入库"
mn_progress step_start airdrop 99 "启用 AirDrop 自动处理" "从 iPhone 接收录音后自动开始"
if ! run_logged "$BASE/scripts/attach_folder_action.sh"; then
  echo "AirDrop 自动入库暂未启用；仍可把录音放入 $BASE/inbox"
  print -r -- "Folder Action attach failed; manual inbox remains available." >> "$LOG"
fi
mn_progress complete complete 100 "MeetingNotes 已准备好" "现在可以放入第一段录音"

echo
echo "MeetingNotes 安装完成。"
echo "把录音放入：$BASE/录音"
echo "生成的纪要在：$BASE/纪要"
# 仅在纯终端回退安装时才弹系统完成框；GUI 模式下由原生安装器窗口的完成页承担，
# 不再单独弹一个割裂的系统对话框（PROGRESS_JSON=true 表示原生窗口在驱动）。
if [[ "${MEETINGNOTES_BOOTSTRAP_TEST_MODE:-false}" != true \
   && "${MEETINGNOTES_PROGRESS_JSON:-false}" != true ]]; then
  osascript -e 'display dialog "安装完成！现在可以把录音放进 MeetingNotes 的录音文件夹。" with title "MeetingNotes" buttons {"好"} default button "好" with icon note' \
    >/dev/null 2>&1 || true
fi
