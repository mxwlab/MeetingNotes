#!/bin/zsh
set -eu

SOURCE_BASE="${0:A:h:h}"
INSTALL_DIR="${MEETINGNOTES_INSTALL_DIR:-$HOME/MeetingNotes}"
os_name="${MEETINGNOTES_UNAME_S:-$(uname -s)}"
arch="${MEETINGNOTES_UNAME_M:-$(uname -m)}"

fail_early() {
  echo
  echo "安装没有完成：$1" >&2
  echo "修复后重新双击“开始使用.command”即可继续。" >&2
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
    --exclude models --exclude runtime --exclude venv
    --exclude tools/FluidAudio
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
  exit 1
}

run_logged() {
  "$@" >> "$LOG" 2>&1
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

write_config() {
  local key="$1"
  local config="$BASE/config.local.sh"
  local config_tmp="$config.tmp.$$"
  umask 077
  {
    printf 'export DEEPSEEK_API_KEY=%q\n' "$key"
    printf 'export OBSIDIAN_DIR=%q\n' ""
  } > "$config_tmp"
  chmod 600 "$config_tmp"
  mv "$config_tmp" "$config"
}

step "确认安装位置"
echo "程序位置：$BASE"

step "设置 DeepSeek"
if [[ -f "$BASE/config.local.sh" ]]; then
  chmod 600 "$BASE/config.local.sh"
  echo "已有设置，安全保留"
else
  key=""
  if [[ "${MEETINGNOTES_BOOTSTRAP_TEST_MODE:-false}" == true ]]; then
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
  echo "DeepSeek 设置验证通过"
fi

step "准备 Python"
run_logged "$BASE/scripts/fetch_python.sh" || fail "Python 运行环境准备失败"
export MEETINGNOTES_PYTHON="$BASE/venv/bin/python"

step "准备音频工具"
run_logged "$BASE/scripts/fetch_ffmpeg.sh" || fail "ffmpeg 准备失败"

step "准备说话人识别"
run_logged "$BASE/scripts/provision_fluidaudio.sh" || fail "FluidAudio 准备失败"

step "下载并预热语音模型"
run_logged "$BASE/scripts/provision_models.sh" || fail "语音模型准备失败"

step "启动后台服务"
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

step "启用 AirDrop 自动入库"
if ! run_logged "$BASE/scripts/attach_folder_action.sh"; then
  echo "AirDrop 自动入库暂未启用；仍可把录音放入 $BASE/inbox"
  print -r -- "Folder Action attach failed; manual inbox remains available." >> "$LOG"
fi

echo
echo "MeetingNotes 安装完成。"
echo "把录音放入：$BASE/inbox"
echo "生成的纪要在：$BASE/output"
if [[ "${MEETINGNOTES_BOOTSTRAP_TEST_MODE:-false}" != true ]]; then
  osascript -e 'display dialog "安装完成！现在可以把录音放进 MeetingNotes 的录音文件夹。" with title "MeetingNotes" buttons {"好"} default button "好" with icon note' \
    >/dev/null 2>&1 || true
fi
